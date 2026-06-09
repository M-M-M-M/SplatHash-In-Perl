use strict ;
use warnings ;

use Test::More ;

use_ok 'SplatHash', qw(encode_raw encode_file decode) ;
is $SplatHash::VERSION, '1.0.0', 'release version is 1.0.0' ;

done_testing ;
