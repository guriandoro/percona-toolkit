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

# These tests do not require a running database; they only exercise
# pt-stalk's option parsing and PG-mode validation.

my $pid_file  = "/tmp/pt-stalk-pgsql-options.pid.$PID";
my $dest_dir  = "/tmp/pt-stalk-pgsql-options.dest.$PID";

sub cleanup {
   unlink $pid_file;
   system("rm -rf $dest_dir 2>/dev/null");
}

cleanup();

# ---------------------------------------------------------------------------
# --pgsql requires --run-time >= 30
# ---------------------------------------------------------------------------
my $output = `$trunk/bin/pt-stalk --pgsql --run-time 10 --no-stalk --collect --iterations 1 --pid $pid_file --dest $dest_dir 2>&1`;
like(
   $output,
   qr/--pgsql requires --run-time to be at least 30 seconds/,
   "--pgsql --run-time 10 is rejected"
);

cleanup();

# ---------------------------------------------------------------------------
# --pgsql is incompatible with --mysql-only
# ---------------------------------------------------------------------------
$output = `$trunk/bin/pt-stalk --pgsql --mysql-only --no-stalk --collect --iterations 1 --pid $pid_file --dest $dest_dir 2>&1`;
like(
   $output,
   qr/--pgsql and --mysql-only are mutually exclusive/,
   "--pgsql + --mysql-only is rejected"
);

cleanup();

# ---------------------------------------------------------------------------
# --pgsql with no gather.sql in any default location nor --pg-gather-sql
# ---------------------------------------------------------------------------
my $empty_dir = "/tmp/pt-stalk-pgsql-empty.$PID";
mkdir $empty_dir or die "Cannot mkdir $empty_dir: $!";
$output = `cd $empty_dir && $trunk/bin/pt-stalk --pgsql --no-stalk --collect --iterations 1 --pid $pid_file --dest $dest_dir 2>&1`;
like(
   $output,
   qr/--pgsql requires gather\.sql/,
   "--pgsql with missing gather.sql is rejected"
);
rmdir $empty_dir;

cleanup();

# ---------------------------------------------------------------------------
# Built-in PG trigger functions need --pgsql.
# ---------------------------------------------------------------------------
$output = `$trunk/bin/pt-stalk --function pg-activity --no-stalk --collect --iterations 1 --pid $pid_file --dest $dest_dir 2>&1`;
like(
   $output,
   qr/--function=pg-activity requires --pgsql/,
   "--function=pg-activity without --pgsql is rejected"
);

cleanup();

$output = `$trunk/bin/pt-stalk --function pg-waiting --no-stalk --collect --iterations 1 --pid $pid_file --dest $dest_dir 2>&1`;
like(
   $output,
   qr/--function=pg-waiting requires --pgsql/,
   "--function=pg-waiting without --pgsql is rejected"
);

cleanup();

# ---------------------------------------------------------------------------
# --pgsql with a fake gather.sql (--no-stalk path) bails out at the
# connectivity check rather than the gather.sql lookup.
# ---------------------------------------------------------------------------
my $fake_sql = "/tmp/pt-stalk-pgsql-fake-gather.$PID.sql";
open my $fh, ">", $fake_sql or die "Cannot write $fake_sql: $!";
print $fh "SELECT 1;\n";
close $fh;

$output = `$trunk/bin/pt-stalk --pgsql --pg-gather-sql $fake_sql --pg-host /nonexistent/socket/dir --no-stalk --collect --iterations 1 --pid $pid_file --dest $dest_dir 2>&1`;
unlike(
   $output,
   qr/--pgsql requires gather\.sql/,
   "--pg-gather-sql is honored (no missing-gather error)"
);

unlink $fake_sql;
cleanup();

done_testing;
