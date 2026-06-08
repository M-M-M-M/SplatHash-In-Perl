use strict ;
use warnings ;

use Digest::SHA ;
use Test::More ;

my $checksum_path = 't/fixtures/upstream-assets.sha256' ;
open my $checksum_file, '<:encoding(UTF-8)', $checksum_path
  or die "Cannot read '$checksum_path': $!" ;

while ( my $line = <$checksum_file> ) {
  chomp $line ;
  next if $line eq q{} ;
  my ( $expected, $path ) = split /\s+/, $line, 2 ;

  open my $asset, '<', $path
    or die "Cannot read asset '$path': $!" ;
  binmode $asset ;
  my $actual = Digest::SHA->new(256)->addfile($asset)->hexdigest ;
  close $asset or die "Cannot close asset '$path': $!" ;

  is $actual, $expected, "$path matches the pinned upstream asset" ;
}

close $checksum_file
  or die "Cannot close '$checksum_path': $!" ;

done_testing ;
