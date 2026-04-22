# pt-stalk PostgreSQL mode — test-server quickstart

This is a copy/paste guide for trying the `pt-stalk-pgsql` branch
(branch [`pt-stalk-pgsql`](https://github.com/guriandoro/percona-toolkit/tree/pt-stalk-pgsql))
on a test server. The full reference lives in
[`docs/pt-stalk-pgsql.rst`](pt-stalk-pgsql.rst).

`pt-stalk` is a self-contained Bash script (the `collect` library is
inlined into `bin/pt-stalk`), so there is **nothing to compile or
build** — just download and run.

## One-shot install on the test server

```bash
# 1. pt-stalk from the pt-stalk-pgsql branch
curl -fsSL -o /usr/local/bin/pt-stalk \
   https://raw.githubusercontent.com/guriandoro/percona-toolkit/pt-stalk-pgsql/bin/pt-stalk
chmod +x /usr/local/bin/pt-stalk

# 2. gather.sql from pg_gather (one of pt-stalk's default search paths)
mkdir -p /usr/local/share/pt-stalk
curl -fsSL -o /usr/local/share/pt-stalk/gather.sql \
   https://raw.githubusercontent.com/jobinau/pg_gather/main/gather.sql
```

## Verify

```bash
pt-stalk --version
pt-stalk --help 2>&1 | grep -E '^\s+--(pgsql|pg-)'
ls -l /usr/local/share/pt-stalk/gather.sql
which psql && psql --version
```

## Smoke-test against a live PostgreSQL

```bash
mkdir -p /var/lib/pt-stalk
pt-stalk \
   --pgsql --no-stalk --collect --iterations 1 \
   --run-time 30 \
   --pg-host 127.0.0.1 --pg-user postgres --pg-database postgres \
   --pg-ask-pass \
   --dest /var/lib/pt-stalk \
   --pid /tmp/pt-stalk.pid --log /tmp/pt-stalk.log

# inspect results
ls /var/lib/pt-stalk
zcat /var/lib/pt-stalk/*/*-pg-gather.tsv.gz | head
cat /tmp/pt-stalk.log
```

## Updating later

If you push more commits to `pt-stalk-pgsql`, just re-run the first
`curl` (raw GitHub serves the latest tip of the branch). To pin to a
specific commit instead of the branch tip, swap the branch name for
the SHA, e.g.:

```bash
curl -fsSL -o /usr/local/bin/pt-stalk \
   https://raw.githubusercontent.com/guriandoro/percona-toolkit/800984ee/bin/pt-stalk
```
