#
# $Id: Optimizer.pm,v 0.1 2003/05/31 10:43:20 dankogai Exp dankogai $
#
package Regexp::Optimizer;
use 5.006; # qr/(??{}/ needed
use strict;
use warnings;
use base qw/Regexp::List/;
our $VERSION = do { my @r = (q$Revision: 0.1 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

#our @EXPORT = qw();
#our %EXPORT_TAGS = ( 'all' => [ qw() ] );
#our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
#our $DEBUG     = 0;

# see perldoc perlop
our $RE_PAREN = 
    qr{
       (?!\\)\(
       (?:
	(?> [^()]+ )
	|
	(??{ $RE_PAREN })
       )*
       (?!\\)\)
      }xo;
our $RE_EXPR = 
    qr{
       (?!\\)\{
       (?:
	(?> [^{}]+ )
	|
	(??{ $RE_EXPR })
       )*
       (?!\\)\}
      }xo;
our $RE_PIPE = qr/(?!\\)\|/o;
our $RE_CHAR = 
    qr{(?:
	# single character...
	(?!\\)[^\\\[(|)\]]      | # raw character except '[(|)]'
	$Regexp::List::RE_XCHAR  | # extended characters
       )}xo;
our $RE_CCLASS = 
    qr{(?:
	(?!\\)\[ $RE_CHAR+ (?!\\)\] |
	$Regexp::List::RE_XCHAR      | # extended characters
	(?!\\)[^(|)]                | # raw character except '[(|)]'
	# Note pseudo-characters are not included
    )}xo;
our $RE_QUANT =
    qr{(?:
	(?!\\)
	(?:
	 \? |
	 \+ |
	 \* |
	 \{[\d,]+\}
	)\??
       )}xo;
our $RE_TOKEN = 
    qr{(?:
	(?:
	\\[ULQ] (?:$RE_CHAR+)(?:\\E|$) | # [ul]c or quotemeta
        $Regexp::List::RE_PCHAR  | # pseudo-characters
        $RE_CCLASS |
	$RE_CHAR     
       )
	 $RE_QUANT?
       )}xo;
our $RE_START = $Regexp::List::RE_START;

our %PARAM = (meta      => 1,
	      quotemeta => 0,
	      optim_cc  => 1,
	      modifiers => '',
	      _char     => $RE_CHAR,
	      _token    => $RE_TOKEN,
	      _cclass   => $RE_CCLASS,
	     );

sub new{
    my $class = ref $_[0] ? ref shift : shift;
    my $self = $class->SUPER::new;
    $self->set(%PARAM, @_);
    $self;
}

sub optimize{
    my $self = shift;
    my $str  = shift;
    $self->unexpand($str);
    my $re = $self->_optimize($str);
    qr/$re/;
}

sub _optimize{
    no warnings 'uninitialized';
    my $self = shift;
    my $str  = shift;
    # don't waste time unless we have to
    $str !~ /$RE_PIPE/ and return $str;
    my $regopt = '';

    $str =~ s/^($RE_START)//o;
    $regopt =  $1; $regopt =~ s/^\(//o;
    $str =~ s/\)$//o;

    $str =~ s/\\([()])/"\\x" . sprintf("%X", ord($1))/ego;
    # $str =~ s/(\s)/"\\x" . sprintf("%X", ord($1))/ego;
    unless ($str =~ /$RE_PAREN/){
        my @words = split /$RE_PIPE/ => $str;
	my $l = $self->clone->set(as_string => 0);
        return $l->list2re(@words);
    }
    
    $str =~ s{
	      ($RE_PAREN)
            }{
		 my $group = $1;
		 if ($group =~ /$RE_PIPE/o){
		     $group =~ s/^($RE_START)//o;
		     my $regopt =  $1; $regopt =~ s/^\(//o;
		     $group =~ s/\)$//o;
		     my @words;
		     $group =~ 
			 s{
			   ($RE_TOKEN+|$RE_PAREN)
			  }{
			      my $word = $1;
			      if ($word =~ /$RE_PAREN/){
				  # recurse;
				  $word = $self->_optimize($word); 
			      }
			      if ($word){
				  push @words, $word;
			      }
			  }egox;
		     
		     # warn join(",", @words);
		     $group = $self->list2re(@words);
		     $regopt and $group = "($regopt$group)";
		     # warn $group;
		 }
		 $group;
	     }egoxs;
    # warn qq($str, $regopt);
    return $regopt ? qq/($regopt$str)/ : $str;
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Regexp::Optimizer - optimizes regular expressions

=head1 SYNOPSIS

  use Regexp::Optimizer;
  my $o  = Regexp::List->new;
  my $re = $o->optimize(qr/foobar|fooxar|foozap/);
  # $re is now qr/foo(?:[bx]ar|zap)/

=head1 ABSTRACT

This module does, ahem, attempts to, optimize regular expressions.

=head1 INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

=head1 DESCRIPTION

Here is a quote from L<perltodo>

  Factoring out common suffices/prefices in regexps (trie optimization)

       Currently, the user has to optimize "foo|far" and "foo|goo" into
       "f(?:oo|ar)" and "[fg]oo" by hand; this could be done automatically.

This module implements just that.

=head2 EXPORT

Since this is an OO module there is no symbol exported.

=head1 METHODS

This module is implemented as a subclass of L<Regexp::List>.  For
methods not listed here, see L<Regexp::List>.

=over

=item $o  = Regexp::Optimizer->new;

=item $re = $o->optimize(I<regexp>);

Does the job.  Note that unlike C<< ->list2re() >> in L<Regexp::List>,
the argument is the regular expression itself.  What it basically does
is to find groups will alterations and replace it with the result of
C<< $o->list2re >>.

=item $re = $o->list2re(I<list of words ...>)

Same as C<list2re()> in L<Regexp::List> in terms of functionality but
how it tokenize "atoms" is different since the arguments can be
regular expressions, not just strings.  Here is a brief example.

  my @expr = qw/foobar fooba+/;
  Regexp::List->new->list2re(@expr) eq qr/fooba[\+r]/;
  Regexp::Optimizer->new->list2re(@expr) eq qr/foob(?:a+ar)/;

=back

=head1 CAVEATS

This module is still experimental.  Do not assume that the result is
the same as the unoptimized version.

=over

=item *

When you just want a regular expression which matches normal words
with not metacharacters, use <Regexp::List>.  It's more robus and 
much faster.

=item *

When you have a list of regular expessions which you want to
aggregate, use C<list2re> of THIS MODULE.

=item *

Use C<< ->optimize() >> when and only when you already have a big
regular expression with alterations therein.

C<< ->optimize() >> does support nested groups but its parser is not
tested very well.

=back

=head1 BUGS

=over

=item *

Regex parser in this module (which itself is implemented by regular
expression) is not as thoroughly tested as L<Regex::List>

=item *

Does not grok (?{expression}) and (?(cond)yes|no) constructs yet

=back

=head1 SEE ALSO

L<Regexp::List> -- upon which this module is based

C<eg/> directory in this package contains example scripts.

=over

=item Perl standard documents

 L<perltodo>, L<perlre>

=item CPAN Modules

L<Regexp::Presuf>, L<Text::Trie>

=item Books

Mastering Regular Expressions  L<http://www.oreilly.com/catalog/regex2/>

=back

=head1 AUTHOR

Dan Kogai <dankogai@dan.co.jp>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Dan Kogai

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
