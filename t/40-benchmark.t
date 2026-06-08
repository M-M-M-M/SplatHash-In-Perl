use strict ;
use warnings ;

use IPC::Open3 ;
use Symbol qw(gensym) ;
use Test::More ;

my $stderr = gensym ;
my $pid    = open3(
  my $stdin,
  my $stdout,
  $stderr,
  $^X,
  'bench/compare-perl-go.pl',
  '--help',
) ;
close $stdin or die "Cannot close child stdin: $!" ;

local $/ ;
my $stdout_text = <$stdout> // q{} ;
my $stderr_text = <$stderr> // q{} ;
waitpid $pid, 0 ;

is $? >> 8, 0, 'benchmark help exits successfully' ;
like $stdout_text, qr/--assets/, 'benchmark help documents --assets' ;
like $stdout_text, qr/--encode-iterations/,
  'benchmark help documents encode iterations' ;
like $stdout_text, qr/--decode-iterations/,
  'benchmark help documents decode iterations' ;
like $stdout_text, qr/--iterations/,
  'benchmark help documents the iteration override' ;
like $stdout_text, qr/--format/,
  'benchmark help documents output formats' ;
like $stdout_text, qr/--include-full/,
  'benchmark help documents full file processing' ;
like $stdout_text, qr/--download-assets/,
  'benchmark help documents asset download' ;
is $stderr_text, q{}, 'benchmark help does not write to stderr' ;

done_testing ;
