use strict ;
use warnings ;

use File::Temp qw(tempdir) ;
use Imager ;
use IPC::Open3 ;
use Symbol qw(gensym) ;
use Test::More ;

my $tempdir     = tempdir( CLEANUP => 1 ) ;
my $input_path  = "$tempdir/input.png" ;
my $output_path = "$tempdir/output.png" ;
my $image       = Imager->new( xsize => 4, ysize => 3, channels => 4 ) ;

for my $y ( 0 .. 2 ) {
  for my $x ( 0 .. 3 ) {
    $image->setpixel(
      x     => $x,
      y     => $y,
      color => Imager::Color->new(
        ( $x * 61 + $y * 17 ) % 256,
        ( $x * 23 + $y * 89 ) % 256,
        ( $x * 131 + $y * 7 ) % 256,
        255,
      ),
    ) ;
  }
}

$image->write( file => $input_path )
  or die "Cannot write test input '$input_path': " . $image->errstr ;

my ( $exit, $stdout, $stderr ) = _run(
  $^X,        '-Ilib', 'bin/splathash',
  '--input',  $input_path,
  '--output', $output_path,
) ;

is $exit, 0, 'CLI exits successfully' ;
like $stdout, qr/\A[0-9a-f]{32}\n\z/, 'CLI prints a hexadecimal hash' ;
is $stderr, q{}, 'CLI does not write to stderr on success' ;
ok -f $output_path, 'CLI writes the output image' ;

my $preview = Imager->new ;
$preview->read( file => $output_path )
  or die "Cannot read CLI output '$output_path': " . $preview->errstr ;
is $preview->getwidth,  32, 'output image width is 32 pixels' ;
is $preview->getheight, 32, 'output image height is 32 pixels' ;

( $exit, $stdout, $stderr ) = _run( $^X, '-Ilib', 'bin/splathash' ) ;
isnt $exit, 0, 'CLI rejects missing arguments' ;
like $stderr, qr/--input/, 'missing argument error names --input' ;

done_testing ;

sub _run {
  my (@command) = @_ ;
  my $stderr    = gensym ;
  my $pid       = open3( my $stdin, my $stdout, $stderr, @command ) ;
  close $stdin or die "Cannot close child stdin: $!" ;

  local $/ ;
  my $stdout_text = <$stdout> // q{} ;
  my $stderr_text = <$stderr> // q{} ;
  waitpid $pid, 0 ;

  return ( $? >> 8, $stdout_text, $stderr_text ) ;
}
