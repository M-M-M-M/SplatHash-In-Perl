use strict ;
use warnings ;

use Test::More ;
use SplatHash::Core () ;

for my $case (
  [ 1,    1,    'single pixel' ],
  [ 7,    5,    'source smaller than target' ],
  [ 32,   32,   'source equal to target' ],
  [ 97,   53,   'irregular source' ],
  [ 3840, 2160, 'large widescreen source' ],
) {
  my ( $width, $height, $name ) = @{$case} ;
  my $offsets = SplatHash::Core::_sample_offsets( $width, $height ) ;
  my @expected ;

  for my $y ( 0 .. 31 ) {
    my $source_y
      = int( ( $y * $height + int( $height / 2 ) ) / 32 ) ;
    for my $x ( 0 .. 31 ) {
      my $source_x
        = int( ( $x * $width + int( $width / 2 ) ) / 32 ) ;
      push @expected, ( $source_y * $width + $source_x ) * 4 ;
    }
  }

  is_deeply $offsets, \@expected, "$name sampling offsets match the reference" ;
}

done_testing ;
