use strict ;
use warnings ;

use IPC::Open3 ;
use Symbol qw(gensym) ;
use Test::More ;

if ( !$ENV{SPLATHASH_RUN_BENCH} ) {
  plan skip_all => 'Set SPLATHASH_RUN_BENCH=1 to run comparison benchmarks' ;
}

my $assets = $ENV{SPLATHASH_ASSETS} // 'assets' ;
plan skip_all => "Benchmark asset directory '$assets' does not exist"
  if !-d $assets ;

my $stderr = gensym ;
my $pid    = open3(
  my $stdin,
  my $stdout,
  $stderr,
  $^X,
  '-Ilib',
  'bench/compare-perl-go.pl',
  '--assets',
  $assets,
  '--encode-iterations',
  1,
  '--decode-iterations',
  1,
  '--format',
  'markdown',
) ;
close $stdin or die "Cannot close child stdin: $!" ;

local $/ ;
my $stdout_text = <$stdout> // q{} ;
my $stderr_text = <$stderr> // q{} ;
waitpid $pid, 0 ;

is $? >> 8, 0, 'comparison benchmark exits successfully' ;
like $stdout_text, qr/\| Image \| Perl encode/,
  'comparison benchmark prints a Markdown table' ;
like $stdout_text, qr/\| \*\*Average\*\* \|/,
  'comparison benchmark prints an average row' ;
like $stdout_text, qr/\| [^|]+ \| [^|]+ \| \*\*[0-9.]+\*\* \|/,
  'comparison benchmark highlights the fastest time' ;
is $stderr_text, q{}, 'comparison benchmark does not write errors' ;

done_testing ;
