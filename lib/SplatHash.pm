package SplatHash ;

use strict ;
use warnings ;

use Exporter        qw(import) ;
use SplatHash::Core () ;

our $VERSION   = '1.0.0' ;
our @EXPORT_OK = qw(encode_raw encode_file decode) ;

sub encode_raw {
  return SplatHash::Core::encode_raw(@_) ;
}

sub decode {
  return SplatHash::Core::decode(@_) ;
}

sub encode_file {
  my ($path) = @_ ;

  die "Image path is required" if !defined $path || $path eq q{} ;

  eval { require Imager ; 1  }
    or die "Imager is required to encode image files" ;

  my $image = Imager->new ;
  $image->read( file => $path )
    or die "Cannot read image '$path': " . $image->errstr ;

  my $width  = $image->getwidth ;
  my $height = $image->getheight ;
  my ( $source_x, $source_y )
    = SplatHash::Core::_sample_coordinates( $width, $height ) ;
  my @colors = $image->getpixel( x => $source_x, y => $source_y ) ;
  die "Cannot sample image '$path': " . $image->errstr
    if @colors != 32 * 32 ;

  my $rgba = q{} ;
  for my $color (@colors) {
    my @channels = $color->rgba ;
    push @channels, 255 while @channels < 4 ;
    $rgba .= pack 'C4', @channels[ 0 .. 3 ] ;
  }

  return encode_raw( $rgba, 32, 32 ) ;
}

1 ;

=pod

=head1 NAME

SplatHash - encode images as fixed 16-byte perceptual placeholders

=head1 SYNOPSIS

  use SplatHash qw(encode_raw decode);

  my $hash = encode_raw($rgba, $width, $height);
  my $preview_rgba = decode($hash);

=head1 DESCRIPTION

SplatHash represents an image as a quantized Oklab mean and six Gaussian
splats. The encoded value is always 16 bytes. Decoding returns a 32x32
row-major RGBA byte buffer.

=head1 FUNCTIONS

=head2 encode_raw

  my $hash = encode_raw($rgba, $width, $height);

Encodes a row-major RGBA byte buffer. Alpha bytes are ignored, matching the
reference implementation.

=head2 encode_file

  my $hash = encode_file($path);

Loads an image with L<Imager> and encodes it.

=head2 decode

  my $rgba = decode($hash);

Decodes a 16-byte hash to a 4096-byte 32x32 RGBA buffer.

=cut
