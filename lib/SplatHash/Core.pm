package SplatHash::Core ;

use strict ;
use warnings ;

use constant TARGET_SIZE     => 32 ;
use constant RIDGE_LAMBDA    => 0.001 ;
use constant GAUSS_TABLE_MAX => 1923 ;

my @SIGMA_VALUES = ( 0.025, 0.1, 0.2, 0.35 ) ;
my (
  @GAUSS_LUT,
  @GAUSS_KERNEL_1D,
  @KERNEL_HW,
  @GAUSS_POW,
  @KERNEL_NEIGHBORS,
) ;
my ( @LIN_TO_SRGB_LUT, @SRGB_LIN_LUT, @CBRT_LUT ) ;

_init_tables() ;

sub encode_raw {
  my ( $rgba, $width, $height ) = @_ ;

  _validate_image( $rgba, $width, $height ) ;

  my $grid        = _image_to_oklab_grid( $rgba, $width, $height ) ;
  my $mean        = _compute_mean($grid) ;
  my $packed_mean = _pack_mean( @{$mean} ) ;
  my ( $mean_l, $mean_a, $mean_b ) = _unpack_mean($packed_mean) ;

  my ( @res_l, @res_a, @res_b ) ;
  for my $i ( 0 .. TARGET_SIZE * TARGET_SIZE - 1 ) {
    my $index = $i * 3 ;
    $res_l[$i] = $grid->[$index] - $mean_l ;
    $res_a[$i] = $grid->[ $index + 1 ] - $mean_a ;
    $res_b[$i] = $grid->[ $index + 2 ] - $mean_b ;
  }

  my $splats = _find_all_splats(
    \@res_l,     \@res_a,     \@res_b,
    TARGET_SIZE, TARGET_SIZE, 6,
  ) ;

  if ( @{$splats} ) {
    $splats = _solve_weights(
      $splats,     $grid,
      $mean_l,     $mean_a, $mean_b,
      TARGET_SIZE, TARGET_SIZE,
    ) ;
  }

  return _pack_hash( $packed_mean, $splats ) ;
}

sub decode {
  my ($hash) = @_ ;

  die "SplatHash must be exactly 16 bytes"
    if !defined $hash || length($hash) != 16 ;

  my ( $mean_l, $mean_a, $mean_b, $splats ) = _unpack_hash($hash) ;
  my @grid ;

  for my $i ( 0 .. TARGET_SIZE * TARGET_SIZE - 1 ) {
    push @grid, $mean_l, $mean_a, $mean_b ;
  }

  for my $splat ( @{$splats} ) {
    _add_splat_to_grid( \@grid, $splat, TARGET_SIZE, TARGET_SIZE ) ;
  }

  my @rgba ;
  for my $i ( 0 .. TARGET_SIZE * TARGET_SIZE - 1 ) {
    my $index = $i * 3 ;
    my $l     = $grid[$index] ;
    my $a     = $grid[ $index + 1 ] ;
    my $b     = $grid[ $index + 2 ] ;
    my $l_    = $l + 0.3963377774 * $a + 0.2158037573 * $b ;
    my $m_    = $l - 0.1055613458 * $a - 0.0638541728 * $b ;
    my $s_    = $l - 0.0894841775 * $a - 1.2914855480 * $b ;
    $l_ = $l_ * $l_ * $l_ ;
    $m_ = $m_ * $m_ * $m_ ;
    $s_ = $s_ * $s_ * $s_ ;

    my $r
      = 4.0767416621 * $l_ - 3.3077115913 * $m_ + 0.2309699292 * $s_ ;
    my $g
      = -1.2684380046 * $l_ + 2.6097574011 * $m_ - 0.3413193965 * $s_ ;
    my $blue
      = -0.0041960863 * $l_ - 0.7034186147 * $m_ + 1.7076147010 * $s_ ;

    $r = $r <= 0 ? 0
      : $r >= 1 ? 1
      :           $LIN_TO_SRGB_LUT[ int( $r * 1023 + 0.5 ) ] ;
    $g = $g <= 0 ? 0
      : $g >= 1 ? 1
      :           $LIN_TO_SRGB_LUT[ int( $g * 1023 + 0.5 ) ] ;
    $blue = $blue <= 0 ? 0
      : $blue >= 1 ? 1
      :              $LIN_TO_SRGB_LUT[ int( $blue * 1023 + 0.5 ) ] ;

    push @rgba,
      int( $r * 255 + 0.5 ),
      int( $g * 255 + 0.5 ),
      int( $blue * 255 + 0.5 ),
      255 ;
  }

  return pack 'C*', @rgba ;
}

sub _validate_image {
  my ( $rgba, $width, $height ) = @_ ;

  die "RGBA bytes are required" if !defined $rgba ;
  die "Image width must be a positive integer"
    if !defined $width || $width !~ /\A[1-9][0-9]*\z/ ;
  die "Image height must be a positive integer"
    if !defined $height || $height !~ /\A[1-9][0-9]*\z/ ;

  my $expected = $width * $height * 4 ;
  die "RGBA byte length does not match image dimensions"
    if length($rgba) != $expected ;

  return ;
}

sub _init_tables {
  my $width_squared = TARGET_SIZE * TARGET_SIZE ;

  for my $sigma_index ( 0 .. $#SIGMA_VALUES ) {
    my $sigma  = $SIGMA_VALUES[$sigma_index] ;
    my $scale2 = 2 * $sigma * $sigma * $width_squared ;
    my @lut ;

    for my $distance_squared ( 0 .. GAUSS_TABLE_MAX - 1 ) {
      my $value = exp( -$distance_squared / $scale2 ) ;
      $value = 0 if $value < 1e-7 ;
      $lut[$distance_squared] = $value ;
    }
    $GAUSS_LUT[$sigma_index] = \@lut ;

    my $half_width = 0 ;
    for my $distance ( 0 .. TARGET_SIZE - 1 ) {
      last if $lut[ $distance * $distance ] < 1e-7 ;
      $half_width = $distance ;
    }
    $KERNEL_HW[$sigma_index] = $half_width ;

    my @kernel = map { $lut[ $_ * $_ ] } 0 .. $half_width ;
    $GAUSS_KERNEL_1D[$sigma_index] = \@kernel ;

    for my $coordinate ( 0 .. TARGET_SIZE - 1 ) {
      my @neighbors ;
      for my $distance ( 1 .. $half_width ) {
        push @neighbors, -$distance if $coordinate - $distance >= 0 ;
        push @neighbors, $distance
          if $coordinate + $distance < TARGET_SIZE ;
      }
      $KERNEL_NEIGHBORS[$sigma_index][$coordinate] = \@neighbors ;
    }

    my $sum = 0 ;
    for my $distance ( -$half_width .. $half_width ) {
      my $value = $kernel[ abs $distance ] ;
      $sum += $value * $value ;
    }
    $GAUSS_POW[$sigma_index] = $sum * $sum ;
  }

  for my $value ( 0 .. 255 ) {
    my $channel = $value / 255 ;
    $SRGB_LIN_LUT[$value] = $channel <= 0.04045
      ? $channel / 12.92
      : ( ( $channel + 0.055 ) / 1.055 )**2.4 ;
  }

  for my $index ( 0 .. 1023 ) {
    $LIN_TO_SRGB_LUT[$index] = _lin_to_srgb_scalar( $index / 1023 ) ;
  }

  for my $index ( 0 .. 1024 ) {
    $CBRT_LUT[$index] = _go_cbrt( $index / 1024 ) ;
  }

  return ;
}

sub _lin_to_srgb_scalar {
  my ($channel) = @_ ;

  return 12.92 * $channel if $channel <= 0.0031308 ;
  return 0                if $channel < 0 ;
  return 1.055 * $channel**( 1 / 2.4 ) - 0.055 ;
}

sub _go_cbrt {
  my ($value) = @_ ;

  return $value if $value == 0 ;

  my $sign = 0 ;
  if ( $value < 0 ) {
    $value = -$value ;
    $sign  = 1 ;
  }

  my $b1              = 715094163 ;
  my $b2              = 696219795 ;
  my $smallest_normal = 2.22507385850720138309e-308 ;

  my $estimate = _float_from_bits(
    _integer_divide_by_three( _float_bits($value) ) + ( $b1 << 32 )
  ) ;
  if ( $value < $smallest_normal ) {
    $estimate = 1 << 54 ;
    $estimate *= $value ;
    $estimate = _float_from_bits(
      _integer_divide_by_three( _float_bits($estimate) ) + ( $b2 << 32 )
    ) ;
  }

  my $c = 5.42857142857142815906e-01 ;
  my $d = -7.05306122448979611050e-01 ;
  my $e = 1.41428571428571436819e+00 ;
  my $f = 1.60714285714285720630e+00 ;
  my $g = 3.57142857142857150787e-01 ;

  my $ratio = $estimate * $estimate / $value ;
  my $scale = $c + $ratio * $estimate ;
  $estimate *= $g + $f / ( $scale + $e + $d / $scale ) ;
  my $chop_mask = unpack 'Q>', pack 'H*', 'ffffffffc0000000' ;
  $estimate = _float_from_bits(
    ( _float_bits($estimate) & $chop_mask ) + ( 1 << 30 )
  ) ;

  $scale = $estimate * $estimate ;
  $ratio = $value / $scale ;
  my $double_estimate = $estimate + $estimate ;
  $ratio    = ( $ratio - $estimate ) / ( $double_estimate + $ratio ) ;
  $estimate = $estimate + $estimate * $ratio ;

  return $sign ? -$estimate : $estimate ;
}

sub _integer_divide_by_three {
  use integer ;
  return $_[0] / 3 ;
}

sub _float_bits {
  my ($value) = @_ ;
  return unpack 'Q>', pack 'd>', $value ;
}

sub _float_from_bits {
  my ($bits) = @_ ;
  return unpack 'd>', pack 'Q>', $bits ;
}

sub _cbrt_fast {
  my ($value) = @_ ;

  return 0               if $value <= 0 ;
  return $CBRT_LUT[1024] if $value >= 1 ;
  return $CBRT_LUT[ int( $value * 1024 + 0.5 ) ] ;
}

sub _lin_to_srgb_fast {
  my ($channel) = @_ ;

  return 0 if $channel <= 0 ;
  return 1 if $channel >= 1 ;
  return $LIN_TO_SRGB_LUT[ int( $channel * 1023 + 0.5 ) ] ;
}

sub _image_to_oklab_grid {
  my ( $rgba, $source_width, $source_height ) = @_ ;

  my $offsets = _sample_offsets( $source_width, $source_height ) ;
  my @grid ;

  for my $offset ( @{$offsets} ) {
    my ( $red, $green, $blue ) = unpack 'C3', substr( $rgba, $offset, 3 ) ;
    my ( $l, $a, $b ) = _srgb_linear_to_oklab(
      $SRGB_LIN_LUT[$red],
      $SRGB_LIN_LUT[$green],
      $SRGB_LIN_LUT[$blue],
    ) ;
    push @grid, $l, $a, $b ;
  }

  return \@grid ;
}

sub _sample_coordinates {
  my ( $source_width, $source_height ) = @_ ;
  my ( @source_x, @source_y ) ;

  for my $y ( 0 .. TARGET_SIZE - 1 ) {
    my $sample_y = int(
      ( $y * $source_height + int( $source_height / 2 ) ) / TARGET_SIZE
    ) ;

    for my $x ( 0 .. TARGET_SIZE - 1 ) {
      push @source_x,
        int(
        ( $x * $source_width + int( $source_width / 2 ) ) / TARGET_SIZE
        ) ;
      push @source_y, $sample_y ;
    }
  }

  return ( \@source_x, \@source_y ) ;
}

sub _sample_offsets {
  my ( $source_width, $source_height ) = @_ ;
  my ( $source_x, $source_y )
    = _sample_coordinates( $source_width, $source_height ) ;
  my @offsets ;

  for my $index ( 0 .. $#{$source_x} ) {
    push @offsets,
      ( $source_y->[$index] * $source_width + $source_x->[$index] ) * 4 ;
  }

  return \@offsets ;
}

sub _compute_mean {
  my ($grid) = @_ ;
  my ( $l, $a, $b ) = ( 0, 0, 0 ) ;

  for ( my $i = 0 ; $i < @{$grid} ; $i += 3 ) {
    $l += $grid->[$i] ;
    $a += $grid->[ $i + 1 ] ;
    $b += $grid->[ $i + 2 ] ;
  }

  my $count = @{$grid} / 3 ;
  return [ $l / $count, $a / $count, $b / $count ] ;
}

sub _srgb_linear_to_oklab {
  my ( $r, $g, $b ) = @_ ;

  my $l1 = 0.4122214708 * $r + 0.5363325363 * $g + 0.0514459929 * $b ;
  my $m1 = 0.2119034982 * $r + 0.6806995451 * $g + 0.1073969566 * $b ;
  my $s1 = 0.0883024619 * $r + 0.2817188376 * $g + 0.6299787005 * $b ;
  my $l_ = _cbrt_fast($l1) ;
  my $m_ = _cbrt_fast($m1) ;
  my $s_ = _cbrt_fast($s1) ;

  return (
    0.2104542553 * $l_ + 0.7936177850 * $m_ - 0.0040720468 * $s_,
    1.9779984951 * $l_ - 2.4285922050 * $m_ + 0.4505937099 * $s_,
    0.0259040371 * $l_ + 0.7827717662 * $m_ - 0.8086757660 * $s_,
  ) ;
}

sub _oklab_to_srgb {
  my ( $l, $a, $b ) = @_ ;

  my $l_ = $l + 0.3963377774 * $a + 0.2158037573 * $b ;
  my $m_ = $l - 0.1055613458 * $a - 0.0638541728 * $b ;
  my $s_ = $l - 0.0894841775 * $a - 1.2914855480 * $b ;
  $l_ = $l_ * $l_ * $l_ ;
  $m_ = $m_ * $m_ * $m_ ;
  $s_ = $s_ * $s_ * $s_ ;

  return (
    _lin_to_srgb_fast(
      4.0767416621 * $l_ - 3.3077115913 * $m_ + 0.2309699292 * $s_
    ),
    _lin_to_srgb_fast(
      -1.2684380046 * $l_ + 2.6097574011 * $m_ - 0.3413193965 * $s_
    ),
    _lin_to_srgb_fast(
      -0.0041960863 * $l_ - 0.7034186147 * $m_ + 1.7076147010 * $s_
    ),
  ) ;
}

sub _find_all_splats {
  my ( $res_l, $res_a, $res_b, $width, $height, $count ) = @_ ;
  my @splats ;
  my ( @tmp_l, @tmp_a, @tmp_b, @score_map, @sigma_map ) ;

  while ( @splats < $count ) {
    my $is_baryon = @splats < 3 ;
    @score_map = (-1) x ( $width * $height ) ;
    @sigma_map = (-1) x ( $width * $height ) ;

    for my $sigma_index ( 0 .. $#SIGMA_VALUES ) {
      my $kernel        = $GAUSS_KERNEL_1D[$sigma_index] ;
      my $half_width    = $KERNEL_HW[$sigma_index] ;
      my $inverse_power = 1 / $GAUSS_POW[$sigma_index] ;

      if ($is_baryon) {
        for my $y ( 0 .. $height - 1 ) {
          my $row_offset = $y * $width ;
          for my $x ( 0 .. $width - 1 ) {
            my $index = $row_offset + $x ;
            my $sum_l = $kernel->[0] * $res_l->[$index] ;
            my $sum_a = $kernel->[0] * $res_a->[$index] ;
            my $sum_b = $kernel->[0] * $res_b->[$index] ;

            for my $delta ( @{ $KERNEL_NEIGHBORS[$sigma_index][$x] } ) {
              my $weight = $kernel->[ abs $delta ] ;
              my $offset = $index + $delta ;
              $sum_l += $weight * $res_l->[$offset] ;
              $sum_a += $weight * $res_a->[$offset] ;
              $sum_b += $weight * $res_b->[$offset] ;
            }

            $tmp_l[$index] = $sum_l ;
            $tmp_a[$index] = $sum_a ;
            $tmp_b[$index] = $sum_b ;
          }
        }

        for my $x ( 0 .. $width - 1 ) {
          for my $y ( 0 .. $height - 1 ) {
            my $index = $y * $width + $x ;
            my $sum_l = $kernel->[0] * $tmp_l[$index] ;
            my $sum_a = $kernel->[0] * $tmp_a[$index] ;
            my $sum_b = $kernel->[0] * $tmp_b[$index] ;

            for my $delta ( @{ $KERNEL_NEIGHBORS[$sigma_index][$y] } ) {
              my $weight = $kernel->[ abs $delta ] ;
              my $offset = $index + $delta * $width ;
              $sum_l += $weight * $tmp_l[$offset] ;
              $sum_a += $weight * $tmp_a[$offset] ;
              $sum_b += $weight * $tmp_b[$offset] ;
            }

            my $score
              = ( $sum_l * $sum_l + $sum_a * $sum_a + $sum_b * $sum_b )
              * $inverse_power ;
            if ( $score > $score_map[$index] ) {
              $score_map[$index] = $score ;
              $sigma_map[$index] = $sigma_index ;
            }
          }
        }
      } else {
        for my $y ( 0 .. $height - 1 ) {
          my $row_offset = $y * $width ;
          for my $x ( 0 .. $width - 1 ) {
            my $index = $row_offset + $x ;
            my $sum_l = $kernel->[0] * $res_l->[$index] ;

            for my $delta ( @{ $KERNEL_NEIGHBORS[$sigma_index][$x] } ) {
              my $weight = $kernel->[ abs $delta ] ;
              $sum_l += $weight * $res_l->[ $index + $delta ] ;
            }

            $tmp_l[$index] = $sum_l ;
          }
        }

        for my $x ( 0 .. $width - 1 ) {
          for my $y ( 0 .. $height - 1 ) {
            my $index = $y * $width + $x ;
            my $sum_l = $kernel->[0] * $tmp_l[$index] ;

            for my $delta ( @{ $KERNEL_NEIGHBORS[$sigma_index][$y] } ) {
              my $weight = $kernel->[ abs $delta ] ;
              $sum_l += $weight * $tmp_l[ $index + $delta * $width ] ;
            }

            my $score = $sum_l * $sum_l * $inverse_power ;
            if ( $score > $score_map[$index] ) {
              $score_map[$index] = $score ;
              $sigma_map[$index] = $sigma_index ;
            }
          }
        }
      }
    }

    my ( $best_score, $best_index ) = ( -1, -1 ) ;
    for my $index ( 0 .. $#score_map ) {
      if ( _score_is_better( $score_map[$index], $best_score ) ) {
        $best_score = $score_map[$index] ;
        $best_index = $index ;
      }
    }
    last if $best_index < 0 || $best_score < 1e-9 ;

    my $best_x      = $best_index % $width ;
    my $best_y      = int( $best_index / $width ) ;
    my $sigma_index = $sigma_map[$best_index] ;
    my $kernel      = $GAUSS_KERNEL_1D[$sigma_index] ;
    my $half_width  = $KERNEL_HW[$sigma_index] ;
    my $power       = $GAUSS_POW[$sigma_index] ;
    my ( $dot_l, $dot_a, $dot_b ) = ( 0, 0, 0 ) ;

    for my $dy ( -$half_width .. $half_width ) {
      my $y = $best_y + $dy ;
      next if $y < 0 || $y >= $height ;
      my $vertical_weight = $kernel->[ abs $dy ] ;

      for my $dx ( -$half_width .. $half_width ) {
        my $x = $best_x + $dx ;
        next if $x < 0 || $x >= $width ;
        my $weight = $vertical_weight * $kernel->[ abs $dx ] ;
        my $offset = $y * $width + $x ;
        $dot_l += $weight * $res_l->[$offset] ;
        $dot_a += $weight * $res_a->[$offset] ;
        $dot_b += $weight * $res_b->[$offset] ;
      }
    }

    my $splat = {
      x         => $best_x / $width,
      y         => $best_y / $height,
      sigma     => $SIGMA_VALUES[$sigma_index],
      l         => $dot_l / $power,
      a         => $dot_a / $power,
      b         => $dot_b / $power,
      is_lepton => $is_baryon ? 0 : 1,
    } ;
    push @splats, $splat ;

    my $start_y = _clamp_int( $best_y - $half_width, 0, $height - 1 ) ;
    my $end_y   = _clamp_int( $best_y + $half_width, 0, $height - 1 ) ;
    my $start_x = _clamp_int( $best_x - $half_width, 0, $width - 1 ) ;
    my $end_x   = _clamp_int( $best_x + $half_width, 0, $width - 1 ) ;

    for my $y ( $start_y .. $end_y ) {
      my $dy = $y - $best_y ;
      for my $x ( $start_x .. $end_x ) {
        my $dx               = $x - $best_x ;
        my $distance_squared = $dx * $dx + $dy * $dy ;
        next if $distance_squared >= GAUSS_TABLE_MAX ;
        my $weight = $GAUSS_LUT[$sigma_index][$distance_squared] ;
        next if $weight == 0 ;
        my $offset = $y * $width + $x ;
        $res_l->[$offset] -= $splat->{l} * $weight ;
        $res_a->[$offset] -= $splat->{a} * $weight ;
        $res_b->[$offset] -= $splat->{b} * $weight ;
      }
    }
  }

  return \@splats ;
}

sub _score_is_better {
  my ( $candidate, $current ) = @_ ;

  return 1 if $current < 0 ;

  my $scale = abs($candidate) > abs($current)
    ? abs($candidate)
    : abs($current) ;
  $scale = 1e-300 if $scale < 1e-300 ;

  return $candidate > $current + 1e-15 * $scale ;
}

sub _solve_weights {
  my ( $basis, $grid, $mean_l, $mean_a, $mean_b, $width, $height ) = @_ ;
  my $pixel_count = $width * $height ;
  my ( @target_l, @target_a, @target_b ) ;

  for my $i ( 0 .. $pixel_count - 1 ) {
    my $index = $i * 3 ;
    $target_l[$i] = $grid->[$index] - $mean_l ;
    $target_a[$i] = $grid->[ $index + 1 ] - $mean_a ;
    $target_b[$i] = $grid->[ $index + 2 ] - $mean_b ;
  }

  my @activations = map {
    _compute_basis_map( $_, $width, $height )
  } @{$basis} ;

  my $baryon_count = @{$basis} < 3 ? @{$basis} : 3 ;
  my $weights_l    = _solve_channel(
    \@activations, \@target_l, scalar @{$basis}, RIDGE_LAMBDA
  ) ;
  my $weights_a = _solve_channel(
    [ @activations[ 0 .. $baryon_count - 1 ] ],
    \@target_a, $baryon_count, RIDGE_LAMBDA,
  ) ;
  my $weights_b = _solve_channel(
    [ @activations[ 0 .. $baryon_count - 1 ] ],
    \@target_b, $baryon_count, RIDGE_LAMBDA,
  ) ;

  my @solved ;
  for my $i ( 0 .. $#{$basis} ) {
    my %splat = %{ $basis->[$i] } ;
    $splat{l} = $weights_l->[$i] ;
    if ( $i < 3 ) {
      $splat{a} = $weights_a->[$i] ;
      $splat{b} = $weights_b->[$i] ;
    } else {
      $splat{a} = 0 ;
      $splat{b} = 0 ;
    }
    push @solved, \%splat ;
  }

  return \@solved ;
}

sub _compute_basis_map {
  my ( $splat, $width, $height ) = @_ ;
  my @map         = (0) x ( $width * $height ) ;
  my $sigma_index = _sigma_index( $splat->{sigma} ) ;
  my $half_width  = $KERNEL_HW[$sigma_index] ;
  my $center_x    = int( $splat->{x} * $width ) ;
  my $center_y    = int( $splat->{y} * $height ) ;
  my $start_y     = _clamp_int( $center_y - $half_width, 0, $height - 1 ) ;
  my $end_y       = _clamp_int( $center_y + $half_width, 0, $height - 1 ) ;
  my $start_x     = _clamp_int( $center_x - $half_width, 0, $width - 1 ) ;
  my $end_x       = _clamp_int( $center_x + $half_width, 0, $width - 1 ) ;

  for my $y ( $start_y .. $end_y ) {
    my $dy = $y - $center_y ;
    for my $x ( $start_x .. $end_x ) {
      my $dx               = $x - $center_x ;
      my $distance_squared = $dx * $dx + $dy * $dy ;
      if ( $distance_squared < GAUSS_TABLE_MAX ) {
        $map[ $y * $width + $x ]
          = $GAUSS_LUT[$sigma_index][$distance_squared] ;
      }
    }
  }

  return \@map ;
}

sub _solve_channel {
  my ( $activations, $target, $count, $lambda ) = @_ ;
  return [] if $count == 0 ;

  my @matrix = (0) x ( $count * $count ) ;
  my @vector = (0) x $count ;

  for my $i ( 0 .. $count - 1 ) {
    for my $j ( $i .. $count - 1 ) {
      my $sum = 0 ;
      for my $pixel ( 0 .. $#{$target} ) {
        $sum += $activations->[$i][$pixel]
          * $activations->[$j][$pixel] ;
      }
      $matrix[ $i * $count + $j ] = $sum ;
      $matrix[ $j * $count + $i ] = $sum ;
    }

    my $sum = 0 ;
    for my $pixel ( 0 .. $#{$target} ) {
      $sum += $activations->[$i][$pixel] * $target->[$pixel] ;
    }
    $vector[$i] = $sum ;
  }

  for my $i ( 0 .. $count - 1 ) {
    $matrix[ $i * $count + $i ] += $lambda ;
  }

  return _solve_linear_system( \@matrix, \@vector, $count ) ;
}

sub _solve_linear_system {
  my ( $matrix, $vector, $count ) = @_ ;
  my @matrix = @{$matrix} ;
  my @vector = @{$vector} ;

  for my $column ( 0 .. $count - 2 ) {
    for my $row ( $column + 1 .. $count - 1 ) {
      my $factor = $matrix[ $row * $count + $column ]
        / $matrix[ $column * $count + $column ] ;
      for my $index ( $column .. $count - 1 ) {
        $matrix[ $row * $count + $index ]
          -= $factor * $matrix[ $column * $count + $index ] ;
      }
      $vector[$row] -= $factor * $vector[$column] ;
    }
  }

  my @solution = (0) x $count ;
  for ( my $row = $count - 1 ; $row >= 0 ; $row-- ) {
    my $sum = 0 ;
    for my $column ( $row + 1 .. $count - 1 ) {
      $sum += $matrix[ $row * $count + $column ] * $solution[$column] ;
    }
    $solution[$row]
      = ( $vector[$row] - $sum ) / $matrix[ $row * $count + $row ] ;
  }

  return \@solution ;
}

sub _pack_hash {
  my ( $mean, $splats ) = @_ ;
  my $bits  = sprintf '%016b', $mean ;
  my $count = 0 ;

  for my $splat ( grep { !$_->{is_lepton} } @{$splats} ) {
    last if $count >= 3 ;
    $bits .= sprintf '%04b%04b%02b%04b%04b%04b',
      _clamp_int( int( $splat->{x} * 15 + 0.5 ), 0, 15 ),
      _clamp_int( int( $splat->{y} * 15 + 0.5 ), 0, 15 ),
      _sigma_index( $splat->{sigma} ),
      _quantize( $splat->{l}, -0.8, 0.8, 4 ),
      _quantize( $splat->{a}, -0.4, 0.4, 4 ),
      _quantize( $splat->{b}, -0.4, 0.4, 4 ) ;
    $count++ ;
  }
  $bits .= '0' x ( 22 * ( 3 - $count ) ) ;

  $count = 0 ;
  for my $splat ( grep { $_->{is_lepton} } @{$splats} ) {
    last if $count >= 3 ;
    $bits .= sprintf '%04b%04b%02b%05b',
      _clamp_int( int( $splat->{x} * 15 + 0.5 ), 0, 15 ),
      _clamp_int( int( $splat->{y} * 15 + 0.5 ), 0, 15 ),
      _sigma_index( $splat->{sigma} ),
      _quantize( $splat->{l}, -0.8, 0.8, 5 ) ;
    $count++ ;
  }
  $bits .= '0' x ( 15 * ( 3 - $count ) ) ;
  $bits .= '0' ;

  return pack 'B*', $bits ;
}

sub _unpack_hash {
  my ($hash)   = @_ ;
  my $bits     = unpack 'B*', $hash ;
  my $position = 0 ;
  my $read     = sub {
    my ($count) = @_ ;
    my $value = oct '0b' . substr( $bits, $position, $count ) ;
    $position += $count ;
    return $value ;
  } ;

  my ( $mean_l, $mean_a, $mean_b ) = _unpack_mean( $read->(16) ) ;
  my @splats ;

  for ( 1 .. 3 ) {
    my ( $x, $y, $sigma, $l, $a, $b )
      = map { $read->($_) } ( 4, 4, 2, 4, 4, 4 ) ;
    next if $l == 0 && $a == 0 && $b == 0 && $x == 0 && $y == 0 ;
    push @splats, {
      x         => $x / 15,
      y         => $y / 15,
      sigma     => $SIGMA_VALUES[$sigma],
      l         => _unquantize( $l, -0.8, 0.8, 4 ),
      a         => _unquantize( $a, -0.4, 0.4, 4 ),
      b         => _unquantize( $b, -0.4, 0.4, 4 ),
      is_lepton => 0,
    } ;
  }

  for ( 1 .. 3 ) {
    my ( $x, $y, $sigma, $l ) = map { $read->($_) } ( 4, 4, 2, 5 ) ;
    next if $l == 0 && $x == 0 && $y == 0 ;
    push @splats, {
      x         => $x / 15,
      y         => $y / 15,
      sigma     => $SIGMA_VALUES[$sigma],
      l         => _unquantize( $l, -0.8, 0.8, 5 ),
      a         => 0,
      b         => 0,
      is_lepton => 1,
    } ;
  }

  return ( $mean_l, $mean_a, $mean_b, \@splats ) ;
}

sub _pack_mean {
  my ( $l, $a, $b ) = @_ ;

  my $l_quantized = _clamp_int( int( $l * 63.5 ),                     0, 63 ) ;
  my $a_quantized = _clamp_int( int( ( ( $a + 0.2 ) / 0.4 ) * 31.5 ), 0, 31 ) ;
  my $b_quantized = _clamp_int( int( ( ( $b + 0.2 ) / 0.4 ) * 31.5 ), 0, 31 ) ;

  return ( $l_quantized << 10 ) | ( $a_quantized << 5 ) | $b_quantized ;
}

sub _unpack_mean {
  my ($packed) = @_ ;

  my $l = ( ( $packed >> 10 ) & 0x3f ) / 63 ;
  my $a = ( ( ( $packed >> 5 ) & 0x1f ) / 31 * 0.4 ) - 0.2 ;
  my $b = ( ( $packed & 0x1f ) / 31 * 0.4 ) - 0.2 ;
  return ( $l, $a, $b ) ;
}

sub _quantize {
  my ( $value, $minimum, $maximum, $bits ) = @_ ;

  my $steps      = ( 1 << $bits ) - 1 ;
  my $normalized = ( $value - $minimum ) / ( $maximum - $minimum ) ;
  return _clamp_int( int( $normalized * $steps + 0.5 ), 0, $steps ) ;
}

sub _unquantize {
  my ( $value, $minimum, $maximum, $bits ) = @_ ;

  my $steps = ( 1 << $bits ) - 1 ;
  return ( $value / $steps ) * ( $maximum - $minimum ) + $minimum ;
}

sub _sigma_index {
  my ($sigma)          = @_ ;
  my $best_index       = 0 ;
  my $minimum_distance = abs( $SIGMA_VALUES[0] - $sigma ) ;

  for my $index ( 1 .. $#SIGMA_VALUES ) {
    my $distance = abs( $SIGMA_VALUES[$index] - $sigma ) ;
    if ( $distance < $minimum_distance ) {
      $minimum_distance = $distance ;
      $best_index       = $index ;
    }
  }

  return $best_index ;
}

sub _add_splat_to_grid {
  my ( $grid, $splat, $width, $height ) = @_ ;

  my $sigma_index = _sigma_index( $splat->{sigma} ) ;
  my $half_width  = $KERNEL_HW[$sigma_index] ;
  my $center_x    = int( $splat->{x} * $width ) ;
  my $center_y    = int( $splat->{y} * $height ) ;
  my $start_y     = _clamp_int( $center_y - $half_width, 0, $height - 1 ) ;
  my $end_y       = _clamp_int( $center_y + $half_width, 0, $height - 1 ) ;
  my $start_x     = _clamp_int( $center_x - $half_width, 0, $width - 1 ) ;
  my $end_x       = _clamp_int( $center_x + $half_width, 0, $width - 1 ) ;

  for my $y ( $start_y .. $end_y ) {
    my $dy = $y - $center_y ;
    for my $x ( $start_x .. $end_x ) {
      my $dx               = $x - $center_x ;
      my $distance_squared = $dx * $dx + $dy * $dy ;
      next if $distance_squared >= GAUSS_TABLE_MAX ;
      my $weight = $GAUSS_LUT[$sigma_index][$distance_squared] ;
      next if $weight == 0 ;
      my $index = ( $y * $width + $x ) * 3 ;
      $grid->[$index]       += $splat->{l} * $weight ;
      $grid->[ $index + 1 ] += $splat->{a} * $weight ;
      $grid->[ $index + 2 ] += $splat->{b} * $weight ;
    }
  }

  return ;
}

sub _clamp_int {
  my ( $value, $minimum, $maximum ) = @_ ;

  return $minimum if $value < $minimum ;
  return $maximum if $value > $maximum ;
  return $value ;
}

1 ;
