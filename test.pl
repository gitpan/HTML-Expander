use Test;
BEGIN { plan tests => 1 };
use HTML::Expander;

my $ex = new HTML::Expander;

$ex->define_tag( 'main', '<name>',  '<h1><font color=%c>' );
$ex->define_tag( 'main', '</name>', '</font></h1>' );
$ex->style_copy( 'new', 'main' );
$ex->define_tag( 'new', '<h1>',  '<p><h1>' );
$ex->define_tag( 'new', '<box>',  '<pre>' );
$ex->define_tag( 'new', '</box>',  '</pre>' );

print $ex->expand( "<style name=new>
                      <box>(current style is '<var name=!STYLE>')</box>
                      <name c=#fff>This is me</name>
                    </style>
                      <box>(cyrrent style is '<var name=!STYLE>')</box>
                      <name>empty</name>
                    1.<var name=TEST>
                    2.<var name=TEST set=opala! echo>
                    3.<var name=TEST>
                    \n" );
print $ex->expand( '<exec cmd=date>(%HOME)' ), "\n";

$ex->{ 'INC' }{ '.' } = 1;
print $ex->expand( '<inc file=test.pl>' ), "\n";

print "done.";

# use Data::Dumper;
# print Dumper( $ex );

ok(1); # there is no bad condition check yet

