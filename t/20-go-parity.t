use strict ;
use warnings ;

use Digest::SHA qw(sha256_hex) ;
use JSON::PP    qw(decode_json) ;
use Test::More ;
use SplatHash qw(encode_raw decode) ;

my $fixture_path = 't/fixtures/splathash-vectors.json' ;
open my $fixture_file, '<:encoding(UTF-8)', $fixture_path
  or die "Cannot read '$fixture_path': $!" ;
local $/ ;
my $fixture_data = decode_json(<$fixture_file>) ;
close $fixture_file or die "Cannot close '$fixture_path': $!" ;

is(
  $fixture_data->{reference_commit},
  '038b4f7025ec044ed9f319371e0ec2ed863a6f45',
  'fixtures identify the Go reference commit',
) ;

for my $fixture ( @{ $fixture_data->{vectors} } ) {
  my $rgba = _fixture_rgba( $fixture->{name}, $fixture->{width}, $fixture->{height} ) ;
  my $hash = encode_raw( $rgba, $fixture->{width}, $fixture->{height} ) ;

  is(
    unpack( 'H*', $hash ),
    $fixture->{hash_hex},
    "$fixture->{name} matches the Go reference",
  ) ;
  my $decoded = decode($hash) ;
  is length($decoded), 4096, "$fixture->{name} decodes successfully" ;
  is(
    sha256_hex($decoded),
    $fixture->{decode_sha256},
    "$fixture->{name} decoded RGBA remains stable",
  ) ;
}

done_testing ;

sub _fixture_rgba {
  my ( $name, $width, $height ) = @_ ;
  my $rgba = q{} ;

  for my $y ( 0 .. $height - 1 ) {
    for my $x ( 0 .. $width - 1 ) {
      my @pixel ;
      if ( $name eq 'solid_red_1x1' ) {
        @pixel = ( 230, 15, 31, 255 ) ;
      } elsif ( $name eq 'solid_blue_7x5' ) {
        @pixel = ( 10, 80, 210, 255 ) ;
      } elsif ( $name eq 'gradient_17x11' ) {
        @pixel = (
          int( $x * 255 / ( $width - 1 ) ),
          int( $y * 255 / ( $height - 1 ) ),
          int( ( $x + $y ) * 255 / ( $width + $height - 2 ) ),
          255,
        ) ;
      } elsif ( $name eq 'checker_13x9' ) {
        @pixel = ( int( $x / 2 ) + int( $y / 3 ) ) % 2 == 0
          ? ( 245, 240, 230, 255 )
          : ( 12, 24, 48, 255 ) ;
      } elsif ( $name eq 'spot_32x32' ) {
        my $distance_squared = ( $x - 23 )**2 + ( $y - 9 )**2 ;
        @pixel = $distance_squared < 36
          ? ( 255, 210, 30, 255 )
          : ( 20, 35, 55, 255 ) ;
      } elsif ( $name eq 'irregular_alpha_19x23' ) {
        @pixel = (
          ( $x * 37 + $y * 11 ) % 256,
          ( $x * 19 + $y * 29 ) % 256,
          ( $x * 7 + $y * 43 ) % 256,
          ( $x * $y ) % 256,
        ) ;
      } else {
        die "Unknown fixture '$name'" ;
      }
      $rgba .= pack 'C4', @pixel ;
    }
  }

  return $rgba ;
}
