use strict ;
use warnings ;

use File::Temp qw(tempdir) ;
use Imager ;
use Test::More ;
use SplatHash qw(encode_raw encode_file decode) ;

my $rgba = pack 'C4', 23, 91, 207, 17 ;
my $hash = encode_raw( $rgba, 1, 1 ) ;

is length($hash),             16,    'encode_raw returns 16 bytes' ;
is encode_raw( $rgba, 1, 1 ), $hash, 'encoding is deterministic' ;

my $decoded = decode($hash) ;
is length($decoded), 32 * 32 * 4, 'decode returns a 32x32 RGBA buffer' ;

my @alpha = ( unpack 'C*', $decoded )[ 3, 7, 11, 4095 ] ;
is_deeply \@alpha, [ 255, 255, 255, 255 ], 'decoded pixels are opaque' ;

for my $invalid (
  [ undef, 1, 1, 'missing RGBA bytes' ],
  [ q{},   0, 1, 'zero width' ],
  [ q{},   1, 0, 'zero height' ],
  [ q{},   1, 1, 'incorrect RGBA length' ],
) {
  my ( $bytes, $width, $height, $name ) = @{$invalid} ;
  eval { encode_raw( $bytes, $width, $height )  } ;
  ok $@, $name ;
}

for my $length ( 0, 15, 17 ) {
  eval { decode( "\0" x $length )  } ;
  ok $@, "decode rejects a $length-byte hash" ;
}

my $tempdir    = tempdir( CLEANUP => 1 ) ;
my $png_path   = "$tempdir/splathash-fixture.png" ;
my $image      = Imager->new( xsize => 3, ysize => 2, channels => 4 ) ;
my $image_rgba = q{} ;

for my $y ( 0 .. 1 ) {
  for my $x ( 0 .. 2 ) {
    my @pixel = (
      ( $x * 83 + $y * 17 ) % 256,
      ( $x * 29 + $y * 97 ) % 256,
      ( $x * 151 + $y * 11 ) % 256,
      255,
    ) ;
    $image->setpixel(
      x     => $x,
      y     => $y,
      color => Imager::Color->new(@pixel),
    ) ;
    $image_rgba .= pack 'C4', @pixel ;
  }
}

$image->write( file => $png_path )
  or die "Cannot write test PNG '$png_path': " . $image->errstr ;

is(
  encode_file($png_path),
  encode_raw( $image_rgba, 3, 2 ),
  'encode_file matches encode_raw for a PNG loaded through Imager',
) ;

my $irregular_path = "$tempdir/irregular.png" ;
my $irregular      = Imager->new( xsize => 41, ysize => 27, channels => 4 ) ;
my $irregular_rgba = q{} ;

for my $y ( 0 .. 26 ) {
  for my $x ( 0 .. 40 ) {
    my @pixel = (
      ( $x * 37 + $y * 11 ) % 256,
      ( $x * 19 + $y * 29 ) % 256,
      ( $x * 7 + $y * 43 ) % 256,
      255,
    ) ;
    $irregular->setpixel(
      x     => $x,
      y     => $y,
      color => Imager::Color->new(@pixel),
    ) ;
    $irregular_rgba .= pack 'C4', @pixel ;
  }
}

$irregular->write( file => $irregular_path )
  or die "Cannot write test PNG '$irregular_path': " . $irregular->errstr ;

is(
  encode_file($irregular_path),
  encode_raw( $irregular_rgba, 41, 27 ),
  'encode_file preserves point sampling for irregular dimensions',
) ;

done_testing ;
