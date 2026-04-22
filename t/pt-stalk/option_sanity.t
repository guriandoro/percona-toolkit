#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;

my $output = `$trunk/bin/pt-stalk --help`;

like(
   $output,
   qr/^\s+--verbose\s+2/m,
   "Default --verbose=2"
);

like(
   $output,
   qr/^\s+--pgsql\s+/m,
   "--pgsql appears in --help"
);

like(
   $output,
   qr/^\s+--pg-gather-sql\s+/m,
   "--pg-gather-sql appears in --help"
);

like(
   $output,
   qr/^\s+--pg-host\s+/m,
   "--pg-host appears in --help"
);

like(
   $output,
   qr/^\s+--pg-port\s+5432/m,
   "Default --pg-port=5432"
);

like(
   $output,
   qr/^\s+--pg-database\s+postgres/m,
   "Default --pg-database=postgres"
);

like(
   $output,
   qr/^\s+--pg-gzip\s+TRUE/m,
   "Default --pg-gzip=TRUE"
);

like(
   $output,
   qr/^\s+--pgsql\s+FALSE/m,
   "Default --pgsql=FALSE"
);

done_testing;
