#########################################################################
#
# HTML::Expander
# Vladi Belperchinov-Shabanski "Cade"
# <cade@biscom.net> <cade@datamax.bg> <cade@cpan.org>
# http://cade.datamax.bg
# http://play.evrocom.net/cade
# $Id: Expander.pm,v 1.13 2004/09/21 21:14:45 cade Exp $
#
#########################################################################
package HTML::Expander;
use Exporter;
@ISA     = qw( Exporter );

our $VERSION  = '2.3';

use Carp;
use strict;

#########################################################################

sub new
{
  my $pack = shift;
  my $class = ref( $pack ) || $pack;
  
  my $self = {};
  
  $self->{ 'TAGS'     } = {}; # tag tables
  $self->{ 'INC'      } = {}; # include directories
  $self->{ 'ENV'      } = {}; # local environment, this is free for use
  
  $self->{ 'STYLE'    } = []; # style stack
  $self->{ 'VISITED'  } = {}; # avoids recursion

  $self->{ 'WARNINGS' } = 0; # set to 1 for debug
  
  bless  $self, $class;
  return $self;
}

sub DESTROY
{
  my $self = shift;
  # nothing
}

sub define_tag
{
  my $self  = shift;
  my $style = shift;
  my $tag   = shift;
  my $value = shift;
  
  $style = 'main' unless $style;
  $self->{ 'TAGS' }{ $style }{ $tag } = $value;
}

sub style_copy
{
  my $self  = shift;
  my $style = shift; # destination style
  
  for my $s ( @_ ) # for each source styles
    {
    # print "DEBUG: style copy: [$style] <- [$s]\n";
    while( my ( $k, $v ) = each %{ $self->{ 'TAGS' }{ $s } } )
      {
      # print "DEBUG:             ($k) = ($v)\n";
      $self->define_tag( $style, $k, $v );
      }
    }
}

sub style_load
{
  my $self  = shift;
  my $file  = shift;
  
  my $target = 'main';
  open my $i, $file;
  while(<$i>)
    {
    next if /^\s*[#;]/; # comments
    chomp;
    if ( /^\s*STYLE/i )
      {
      $_ = lc $_;
      s/\s+//g; # get rid of whitespace
      my @a = split /[:,]/;
      shift @a; # skip `style' keyword
      $target = shift @a;
      $self->style_copy( $target, @a );
      }
    else
      {
      $self->define_tag( $target, lc $1, $2 ) if /^\s*(\S+)\s+(.*)$/;
      }
    }
  close $i;
}

sub expand
{
  my $self  = shift;
  my $text  = shift;
  my $level = shift;
  
  # print "DEBUG: expand (level=$level) [text=$text]\n";
  
  $text =~ s/\(\%([^\(\)]+)\)/$self->var_expand($1,$level+1)/gie;
  # print "DEBUG: ----------------------\n";
  $text =~ s/<([^<>]+)>/$self->tag_expand($1,$level+1)/gie;
  # print "DEBUG: expand result: [text=$text]\n";
  return $text;
}

sub var_expand
{
  my $self    = shift;
  my $var     = shift;
  my $level   = shift;

  $self->{ 'VISITED' } = {} if $level == 1;
  
  return undef if $self->{ 'VISITED' }{ "!VAR::$var" }++; # avoids recursion
  my $value = $self->{ 'ENV' }{ $var } || $ENV{ $var };
  # use Data::Dumper; # DEBUG
  # print "DEBUG: var_expand: [$var] = ($value)".Dumper($self->{ 'ENV' })."\n";
  return $self->expand( $value, $level + 1 );
}

sub tag_expand
{
  my $self    = shift;
  my $tag_org = shift;
  my $level   = shift;

  $self->{ 'VISITED' } = {} if $level == 1;
  
  my %args;
  my ( $tag, $args ) = split /\s+/, $tag_org, 2;
  # print "DEBUG: tag_expand: [$tag] -- ($args)\n";
  my $tag_lc = lc $tag;
  while( $args =~ /\s*([^=]+)(=('([^']*)'|"([^"]*)"|(\S*)))?/g ) # "' # fix string colorization
    {
    my $k = lc $1;
    my $v = $4 || $5 || $6 || 1;
    $args{ $k } = $v;
    # print "DEBUG:          [$k] = ($v)\n";
    }
  
  if ( $tag_lc eq 'style' )
    {
    unshift @{ $self->{ 'STYLE' } }, ( $args{ 'name' } || 'main' );
    $self->{ 'ENV' }{ '!STYLE' } = $self->{ 'STYLE' }[0] || 'main';
    return undef;    
    }
  elsif ( $tag_lc eq '/style' )
    {
    shift @{ $self->{ 'STYLE' } };
    $self->{ 'ENV' }{ '!STYLE' } = $self->{ 'STYLE' }[0] || 'main';
    return undef;    
    }
  if ( $tag_lc eq 'var' )
    {
    if( $args{ 'set' } eq '' )
      {
      return $self->var_expand( $args{ 'name' }, $level + 1 );
      }
    else
      {
      $self->{ 'ENV' }{ uc $args{ 'name' } } = $args{ 'set' };
      return $args{ 'echo' } ? $args{ 'set' } : undef;
      }  
    }
  elsif ( $tag_lc eq 'include' or $tag_lc eq 'inc' )
    {
    my $file;
    for( keys %{ $self->{ 'INC' } } )
      {
      $file = $_ . '/' . $args{ 'file' };
      last if -e $file;
      $file = undef;
      }
    return undef if $self->{ 'VISITED' }{ "!INC::$file" }++; # avoids recursion
    open( my $i, $file ) || do
      {
      carp __PACKAGE__ . ": cannot open file `$file'" 
          if $self->{ WARNINGS };
      };
    my $data = $self->expand( join( '', <$i> ), $level + 1 );
    close( $i );
    return $data;
    }
  elsif ( $tag_lc eq 'exec' )
    {
    open( my $i, $args{ 'cmd' } . '|' ) || do 
      { 
      carp __PACKAGE__ . ": cannot exec file `" . $args{ 'cmd' } . "'" 
          if $self->{ WARNINGS };
      };
    my $data = $self->expand( join( '', <$i> ), $level + 1 );
    close $i;
    return $data;
    }
  else
    {
    $tag = "<$tag>";
    
    my $style = $self->{ 'STYLE' }[0] || 'main';
    my $value = $self->{ 'TAGS' }{ $style }{ $tag };
    # print "DEBUG: style name {$style}, tag: $tag -> ($value)\n" if defined $value;
    if ( $value and ! $self->{ 'VISITED' }{ "$style::$tag" } )
      {
      # print "DEBUG:               ---> ($value)\n";
      $self->{ 'VISITED' }{ "$style::$tag" }++; # avoids recursion
      $value = $self->expand( $value, $level + 1 );
      $value =~ s/\%([a-z_0-9]+)/$args{ lc $1 }/gi;
      my $ret = $self->expand( $value, $level + 1 );
      # print "DEBUG: tag_expand return: [$ret]\n";
      return $ret;
      }
    else
      {
      # print "DEBUG: tag_expand original: [$tag_org]\n";
      return "<$tag_org>";
      }
    }  
}

=pod

=head1 NAME

HTML::Expander - html tag expander with inheritable tag definitions (styles)

=head1 SYNOPSIS

  use HTML::Expander;
 
  # get new HTML::Expander object;
  my $ex = new HTML::Expander;
  
  # load style (tags) definitions
  $ex->style_load( "/path/to/style.def.txt" );
 
  # define some more tags
  $ex->define_tag( 'main', '<name>',  '<h1><font color=%c>' );
  $ex->define_tag( 'main', '</name>', '</font></h1>' );
  
  # copy `main' into `new' style
  $ex->style_copy( 'new', 'main' );
  
  # define one more tag
  $ex->define_tag( 'new', '<h1>',  '<p><h1>' );
  $ex->define_tag( 'new', '<box>',  '<pre>' );
  $ex->define_tag( 'new', '</box>',  '</pre>' );
  
  # expand!
  print $ex->expand( "<style name=new>
                        (current style is '<var name=!STYLE>') 
                        <name c=#fff>This is me</name>
                      </style>
                        (cyrrent style is '<var name=!STYLE>') 
                        <name>empty</name>
                      1.<var name=TEST>
                      2.<var name=TEST set=opala! echo>
                      3.<var name=TEST>
                      \n" );
  # the result will be:
  #                     <pre>(current style is 'new')</pre>
  #                     <p><h1><font color=#fff>This is me</font></h1>
  #                   
  #                     <box>(cyrrent style is 'main')</box>
  #                     <h1><font color=>empty</font></h1>
  #                   1.
  #                   2.opala!
  #                   3.opala!
  
  # this should print current date
  print $ex->expand( '<exec cmd=date>' ), "\n";
  
  # add include paths
  $ex->{ 'INC' }{ '.' } = 1;
  $ex->{ 'INC' }{ '/usr/html/inc' } = 1;
  $ex->{ 'INC' }{ '/opt/test' } = 1;
  
  # remove path
  delete $ex->{ 'INC' }{ '/usr/html/inc' };
  
  # include some file (avoiding recursion if required)
  print $ex->expand( '<inc file=test.pl>' ), "\n";

=head1 DESCRIPTION

HTML::Expander replaces html tags with other text (more tags, so it 'expands':)) 
with optional arguments. HTML::Expander uses tag tables which are called styles. 
Styles can inherit other styles (several ones if needed). The goal is to have 
as simple input html document as you need and have multiple different outputs. 
For example you may want <box> tag to render either as <pre> or as 
<table><tr><td> in two separated styles. 

Essentially HTML::Expander works as preprocessor.

The style file syntax is:

  tag   tag-replacement-string

  STYLE: style-name: inherited-styles-list

  tag   tag-replacement-string

  etc...
 
inherited-styles-list is comma or semicolon-separated list of styles that
should be copied (inherited) in this style
 
The style file example:

  ### begin style

  # top-level style is called `main' and is silently defined by default
  # style: main

  <head1>   <h1>
  </head1>  </h1>

  <head2>   <h1><font color=#ff0000>
  </head2>  </h1></font>

  STYLE: page: main

  <head2>   <h1><font color=#00ff00>

  STYLE: edit: page, main
  
  # actually `page' inherits `main' so it is not really
  # required here to list `main'

  <head2>   <h1><font color=#0000ff><u>
 
This is not exhaustive example but it is just for example...

=head1 TAG ARGUMENTS

Inside the tag you can define arguments that can be used later during the
interpolation or as argument to the special tags etc.

Arguments cannot contain whitespace unless enclosed in " or ':

  <mytag arg=value>              # correct
  <mytag arg=this is long value> # incorrect!
  <mytag arg='the second try'>   # correct
  <mytag arg="cade's third try"> # correct
  
There is no way to mix " and ':  

  <mytag arg='cade\'s third try'> # incorrect! there is no escape syntax

You can have unary arguments (without value) which, if used, have '1' value.

   <mytag echo> is the same as <mytag echo=1>

=head1 SPECIAL TAGS

There are several tags with special purposes:

  <style name=name>
  
Sets current style to `name' (saves it on the top of the style stack).  

  </style>
  
Removes last used style from the stack (if stack is empty `main' is used).
Both <style> and </style> are replaced with empty strings.

  <exec cmd=command>
  
This tag is replaced with `command's output.

  <include file=incfile>
  or
  <inc file=incfile>
  
This tag is replaced with `incfile' file's content (which will be 
HTML::Expanded recursively).

=head1 VARIABLES/ENVIRONMENT

HTML::Expander object have own 'environment' which is accessed this way:

$ex->{'ENV'}{ 'var-name' } = 'var-value';

i.e. $ex->{'ENV'} is hash reference to the local environment. There is no
special access policy.

There is syntax for variables interpolation. Values are taken either from
internal environment table or program environment (internal has priority):

  (%VARNAME)
  
All variables are replaced before tag expansion! This helps to handle this:

  <tag argument=(%VAR) etc.>

If you need to interpolate variable in the tag expansion process (after the
variables interpolation) you need to:

  <var name=VARNAME>
  
If you need to set variable name during tag interpolation you should:

  <var name=VARNAME set=VALUE>
  
If you want to set variable and return its value at the same time you have to
use unary 'echo' argument:

  <var name=VARNAME set=VALUE echo>

(%VAR) variables are interpolated before %arg interpolation, so it is safe to
use this:

  <img src=(%WWWROOT)/%src>
  
=head1 BUGS

Unknown tags are left as-is, this is not bug but if you write non-html tag
which is not defined in style tables it will passed into the output text.
(see <box> example above for 'main' style)

If you find bug please contact me, thank you.

=head1 TODO

  <empty>

=head1 AUTHOR

  Vladi Belperchinov-Shabanski "Cade"

  <cade@biscom.net> <cade@datamax.bg> <cade@cpan.org>

  http://cade.datamax.bg
  http://play.evrocom.net/cade
 
=head1 VERSION

  $Id: Expander.pm,v 1.13 2004/09/21 21:14:45 cade Exp $
 
=cut

#########################################################################
#   eof
#########################################################################
1;
