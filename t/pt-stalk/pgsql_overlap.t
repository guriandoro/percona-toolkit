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
use File::Temp qw(tempdir);

use PerconaTest;

# Unit-style shell test for collect_pgsql_data_one(). We extract the
# function from the inlined collect package in bin/pt-stalk and wrap it
# in a small driver script that fakes the OPT_* / CMD_* / d / p variables.

my $tool      = "$trunk/bin/pt-stalk";
my $work_dir  = tempdir(CLEANUP => 1);
my $dest_dir  = "$work_dir/dest";
my $coll_dir  = "$work_dir/coll";
my $driver    = "$work_dir/driver.sh";
mkdir $dest_dir or die "Cannot mkdir $dest_dir: $!";
mkdir $coll_dir or die "Cannot mkdir $coll_dir: $!";

# Tiny driver that sources just the helpers we need from bin/pt-stalk.
# Sourcing the entire tool is awkward because of its top-level main()
# guard, so we extract the two helpers we care about with a
# straight-forward awk line range.
my $extract_cmd = qq{awk '/^pgsql_env\\(\\) \\{/,/^\\}/' $tool > $work_dir/pgsql_env.sh && }
                . qq{awk '/^collect_pgsql_data_one\\(\\) \\{/,/^\\}/' $tool > $work_dir/collect_pgsql_data_one.sh};
system($extract_cmd) == 0 or die "Failed to extract pg helpers from $tool: $!";

open my $fh, ">", $driver or die "Cannot write $driver: $!";
print $fh <<"EOF";
#!/usr/bin/env bash
set -u

# Stubs for what the helpers depend on from the surrounding library.
log()  { echo "LOG  \$*"; }
warn() { echo "WARN \$*" >&2; }
ts()   { TS=\$(date +%F-%T | tr ':-' '_'); echo "\$TS \$*"; }

# Globals collect_pgsql_data_one references.
OPT_DEST="$dest_dir"
d="$coll_dir"
p="testprefix"
OPT_PG_GZIP=""
OPT_PG_GATHER_SQL="\$1"
OPT_PG_PSQL="\$2"
CMD_PSQL="\$2"

# Source the helper bodies.
. "$work_dir/pgsql_env.sh"
. "$work_dir/collect_pgsql_data_one.sh"

collect_pgsql_data_one
EOF
close $fh;
chmod 0755, $driver;

# A "psql" that takes a few seconds so we can race a second invocation.
my $slow_psql = "$work_dir/slow_psql.sh";
open my $sfh, ">", $slow_psql or die "Cannot write $slow_psql: $!";
print $sfh <<'EOF';
#!/usr/bin/env bash
sleep 5
echo "fake-pg-gather-output"
EOF
close $sfh;
chmod 0755, $slow_psql;

# A "psql" that exits immediately (used after we expect the flag file
# to be cleared).
my $fast_psql = "$work_dir/fast_psql.sh";
open my $ffh, ">", $fast_psql or die "Cannot write $fast_psql: $!";
print $ffh <<'EOF';
#!/usr/bin/env bash
echo "fast-pg-gather-output"
EOF
close $ffh;
chmod 0755, $fast_psql;

my $fake_sql = "$work_dir/gather.sql";
open my $gfh, ">", $fake_sql or die "Cannot write $fake_sql: $!";
print $gfh "SELECT 1;\n";
close $gfh;

# ---------------------------------------------------------------------------
# Case 1: A previous-iteration pg_gather is still running; the next
# invocation must skip and write a warning into its own output file.
# ---------------------------------------------------------------------------
unlink glob "$coll_dir/*";
unlink "$dest_dir/pg_gather.running";

# First invocation kicks off the slow "psql" in the background and
# writes the running flag.
system(qq{$driver $fake_sql $slow_psql >/dev/null 2>&1});
sleep 1;  # let it actually start

ok(
   -f "$dest_dir/pg_gather.running",
   "Flag file exists while pg_gather is running"
);

my $first_output = (glob "$coll_dir/testprefix-pg-gather.tsv*")[0];
ok($first_output, "First iteration produced an output file") or diag(`ls $coll_dir`);

# Second invocation should detect the still-running first one and skip.
my $second_run = `$driver $fake_sql $fast_psql 2>&1`;
like(
   $second_run,
   qr/pg_gather from a previous iteration .* is still running/,
   "Second iteration logs a warning when previous is still running"
);

# The first iteration's output file must still be the one being written
# by slow_psql, but the *second* iteration's output should contain the
# skip warning. Because both iterations share the same prefix in this
# test, the new line is appended to the same file. Look for the
# warning text in there:
my $combined = `cat $coll_dir/testprefix-pg-gather.tsv* 2>/dev/null`;
like(
   $combined,
   qr/pg_gather from a previous iteration .* is still running/,
   "Skip warning was written into the iteration output file"
);

# Wait for slow_psql to finish (and the flag file to be cleaned up).
my $waited = 0;
while ( -f "$dest_dir/pg_gather.running" && $waited < 15 ) {
   sleep 1;
   $waited++;
}
ok(
   ! -f "$dest_dir/pg_gather.running",
   "Flag file is removed after pg_gather completes"
);

# ---------------------------------------------------------------------------
# Case 2: A stale flag file (PID is gone) is recovered from instead of
# blocking forever.
# ---------------------------------------------------------------------------
unlink glob "$coll_dir/*";
# pick a PID that almost certainly does not exist
open my $sfhx, ">", "$dest_dir/pg_gather.running" or die $!;
print $sfhx "999999\n";
close $sfhx;

my $third_run = `$driver $fake_sql $fast_psql 2>&1`;
unlike(
   $third_run,
   qr/pg_gather from a previous iteration .* is still running/,
   "Stale flag file does not block a fresh collection"
);

# Wait briefly for the backgrounded fast_psql to complete and clean up.
sleep 1;
ok(
   ! -f "$dest_dir/pg_gather.running",
   "Flag file is recreated and removed for the fresh collection"
);

ok(
   (glob "$coll_dir/testprefix-pg-gather.tsv*")[0],
   "Fresh collection produced an output file"
) or diag(`ls $coll_dir`);

done_testing;
