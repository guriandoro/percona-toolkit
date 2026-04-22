.. _pt-stalk-pgsql:

==================================
:program:`pt-stalk` PostgreSQL mode
==================================

Overview
========

Starting with this release, :program:`pt-stalk` can target PostgreSQL in
addition to MySQL. PostgreSQL support is intentionally narrow: when
``--pgsql`` is set, each triggered iteration runs the ``gather.sql``
script from the `pg_gather <https://github.com/jobinau/pg_gather>`_
project once via ``psql``, capturing its output to
``<prefix>-pg-gather.tsv[.gz]`` inside the iteration's collection
directory.

The system-data collection loop (``vmstat``, ``iostat``, ``df``,
``/proc`` snapshots, etc.) still runs alongside ``pg_gather``. Only the
MySQL-specific collectors are skipped.

Key constraints
---------------

* ``--run-time`` must be at least ``30`` seconds in PostgreSQL mode.
  ``gather.sql`` contains internal ``pg_sleep`` calls totalling more than
  20 seconds and would be cut off otherwise.
* If a previous iteration's ``pg_gather`` is still running when the next
  one is triggered, :program:`pt-stalk` skips the new ``psql`` invocation
  and writes a warning into the would-be output file. This guarantees a
  given ``--dest`` directory never has two concurrent ``pg_gather``
  processes writing in parallel.
* ``--pgsql`` is mutually exclusive with ``--mysql-only``.

Requirements
------------

* The ``psql`` PostgreSQL command-line client in ``PATH`` (or supplied
  via ``--pg-psql``).
* The ``gather.sql`` script from
  `pg_gather <https://github.com/jobinau/pg_gather>`_, either at one of
  the default search paths (see below) or supplied via
  ``--pg-gather-sql``.
* A PostgreSQL role with at least the privileges needed by ``gather.sql``
  (typically ``pg_monitor`` or equivalent).

New options
===========

Connection
----------

``--pgsql``
  Switch :program:`pt-stalk` to PostgreSQL mode. Must be present for any
  of the ``--pg-*`` options or PostgreSQL trigger functions to take
  effect.

``--pg-host``
  PostgreSQL host. Falls through to the ``PGHOST`` environment variable
  if not provided.

``--pg-port``
  PostgreSQL port. Default: ``5432``. Falls through to ``PGPORT``.

``--pg-user``
  PostgreSQL user. Falls through to ``PGUSER``.

``--pg-database``
  Database to connect to. Default: ``postgres``. Falls through to
  ``PGDATABASE``.

``--pg-service``
  Service name from ``pg_service.conf``. Falls through to ``PGSERVICE``.

``--pg-password``
  PostgreSQL password. Falls through to ``PGPASSWORD``. Insecure on the
  command line; prefer a ``.pgpass`` file or ``--pg-ask-pass``.

``--pg-ask-pass``
  Prompt interactively for a PostgreSQL password.

Behaviour
---------

``--pg-gather-sql``
  Path to ``gather.sql``. If unset, :program:`pt-stalk` searches in this
  order and uses the first file that exists:

  1. ``/usr/share/pt-stalk/gather.sql``
  2. ``/usr/local/share/pt-stalk/gather.sql``
  3. ``<tool dir>/../share/pt-stalk/gather.sql``
  4. ``$PWD/gather.sql``

  If no file is found, the tool exits with an error.

``--pg-psql``
  Path to the ``psql`` binary to use. Defaults to whatever the tool
  finds on ``PATH``.

``--pg-gzip``
  Pipe the ``gather.sql`` output through ``gzip``, producing
  ``<prefix>-pg-gather.tsv.gz``. Default: ``yes``. Use
  ``--no-pg-gzip`` to keep the raw ``.tsv`` file instead.

New built-in trigger functions
==============================

Both functions are valid only with ``--pgsql`` and ignore
``--variable`` / ``--match``. The trigger value is compared against
``--threshold`` exactly like the existing ``status`` and ``processlist``
triggers.

``--function pg-activity``
  Trigger value is the count of active backends in
  ``pg_stat_activity`` (``state = 'active'``).

``--function pg-waiting``
  Trigger value is the count of active backends in
  ``pg_stat_activity`` whose ``wait_event`` is not NULL (i.e. backends
  that are blocked or otherwise waiting).

Output files per iteration
==========================

For an iteration with prefix ``<ts>``, the iteration directory contains:

* ``<ts>-pg-gather.tsv`` (or ``.tsv.gz`` when ``--pg-gzip`` is on) -
  raw output of ``gather.sql`` to be processed by the pg_gather
  toolchain.
* ``<ts>-trigger`` - the trigger value(s) that fired the iteration.
* The usual system-side files (``<ts>-vmstat``, ``<ts>-iostat``,
  ``<ts>-df``, ``<ts>-meminfo``, ``<ts>-hostname``, etc.).

No MySQL-specific files (``-variables``, ``-innodbstatus``,
``-processlist``, ``-mutex-status*``, ``-pmap``, ``-stacktrace``,
``-mysqladmin``, ``-tcpdump``, ``-log_error``, ``-lock-waits``,
``-transactions``, ``-opentables*``) are produced.

Examples
========

1. Minimal one-shot collection
------------------------------

Place ``gather.sql`` next to your shell, then run a single iteration of
30 seconds against a local PostgreSQL on the default port:

.. code-block:: bash

   # one-shot, no stalking, just collect once
   pt-stalk \
      --pgsql \
      --no-stalk --collect --iterations 1 \
      --run-time 30 \
      --pg-host 127.0.0.1 \
      --pg-user postgres \
      --pg-database postgres \
      --pg-ask-pass \
      --dest /tmp/pt-stalk-pg

You will be prompted for the PostgreSQL password, then a single
iteration directory will appear under ``/tmp/pt-stalk-pg``:

.. code-block:: none

   /tmp/pt-stalk-pg/
      2026_04_22_15_30_05-pg-gather.tsv.gz
      2026_04_22_15_30_05-vmstat
      2026_04_22_15_30_05-iostat
      2026_04_22_15_30_05-df
      ...

2. Stalking on active connections
---------------------------------

Watch ``pg_stat_activity`` and start collecting whenever there are more
than 50 active queries; stop after 5 iterations:

.. code-block:: bash

   pt-stalk \
      --pgsql \
      --function pg-activity \
      --threshold 50 \
      --cycles 2 \
      --interval 5 \
      --run-time 30 \
      --iterations 5 \
      --pg-host db.example.com \
      --pg-user monitor \
      --pg-service prod_primary \
      --dest /var/lib/pt-stalk

The ``--cycles 2`` option means the threshold has to be exceeded twice
in a row (``--interval 5`` apart) before an iteration starts; this is
the same semantics as the existing MySQL trigger functions.

3. Stalking on waiting / blocked backends
-----------------------------------------

Trigger when more than 5 backends are blocked on a wait event:

.. code-block:: bash

   pt-stalk \
      --pgsql \
      --function pg-waiting \
      --threshold 5 \
      --run-time 60 \
      --pg-host db.example.com \
      --pg-user monitor \
      --pg-database appdb \
      --dest /var/lib/pt-stalk

4. Using libpq environment variables only
-----------------------------------------

Any ``--pg-*`` option you do not supply falls through to the standard
libpq environment variables, so existing ``.pgpass`` and
``pg_service.conf`` setups work unchanged:

.. code-block:: bash

   export PGHOST=db.example.com
   export PGUSER=monitor
   export PGSERVICE=prod_primary
   # password comes from ~/.pgpass

   pt-stalk --pgsql --no-stalk --collect --iterations 1 \
      --run-time 30 --dest /tmp/pt-stalk-pg

5. Custom path to ``gather.sql``
--------------------------------

If you do not want to install ``gather.sql`` into one of the default
locations, point :program:`pt-stalk` at it directly:

.. code-block:: bash

   pt-stalk \
      --pgsql \
      --pg-gather-sql /opt/pg_gather/gather.sql \
      --no-stalk --collect --iterations 1 \
      --run-time 30 \
      --dest /tmp/pt-stalk-pg

6. Custom trigger plugin in PostgreSQL mode
-------------------------------------------

The existing ``--function FILE`` plugin mechanism still works. The
plugin must define ``trg_plugin`` and may use the ``$(pgsql_env)``
helper to construct ``psql`` invocations:

.. code-block:: bash

   # /etc/pt-stalk/long_idle_in_xact.sh
   trg_plugin() {
      eval "$(pgsql_env) psql -X -Atq -c \
         \"SELECT count(*) FROM pg_stat_activity \
            WHERE state = 'idle in transaction' \
              AND xact_start < now() - interval '5 minutes';\""
   }

.. code-block:: bash

   pt-stalk \
      --pgsql \
      --function /etc/pt-stalk/long_idle_in_xact.sh \
      --threshold 0 \
      --run-time 30 \
      --pg-host 127.0.0.1 --pg-user monitor --pg-database appdb \
      --dest /var/lib/pt-stalk

Concurrency: skipping overlapping ``pg_gather`` runs
====================================================

``gather.sql`` can take a long time on busy clusters. If a previous
iteration's ``pg_gather`` is still running when a new iteration starts,
:program:`pt-stalk` will:

1. Detect the still-running PID via the
   ``<dest>/pg_gather.running`` flag file.
2. Log a warning to the tool log and to the new iteration's
   ``<prefix>-pg-gather.tsv[.gz]`` file, e.g.::

      TS 1745345406.123456789 2026-04-22 15:30:06 pg_gather from a
      previous iteration (PID 12345) is still running; skipping
      pg_gather for this iteration

3. Continue with the rest of the iteration (system-data collection,
   trigger metrics, etc.).

If the flag file exists but the PID inside it is gone (stale flag,
e.g. after a crash or a manual kill), the file is removed and a fresh
``pg_gather`` is started normally.

Validation errors
=================

The following mistakes are caught at start-up before any data is
collected:

``--pgsql and --mysql-only are mutually exclusive``
  You used both flags. Pick one.

``--pgsql requires --run-time to be at least 30 seconds (...)``
  ``--run-time`` is below 30 in PG mode. Increase it.

``--pgsql requires gather.sql; provide it via --pg-gather-sql or place it at one of the default search paths (see --help)``
  No ``gather.sql`` was found in any of the four default locations and
  ``--pg-gather-sql`` was not supplied.

``--function=pg-activity requires --pgsql`` /
``--function=pg-waiting requires --pgsql``
  These trigger functions only make sense in PostgreSQL mode.

``Cannot execute psql (...). Check that it is in PATH or set --pg-psql.``
  ``psql --version`` failed. Install ``psql`` or pass an explicit path
  via ``--pg-psql``.

``Cannot connect to PostgreSQL. Check the --pg-* options or libpq env vars.``
  ``psql -X -tAc 'SELECT 1'`` failed. Verify host/port/credentials,
  ``.pgpass``, and ``pg_service.conf``.

Environment
===========

In addition to the existing ``CMD_*`` overrides, PostgreSQL mode honours
``CMD_PSQL`` (the ``psql`` binary used internally) and the standard
libpq environment variables: ``PGHOST``, ``PGPORT``, ``PGUSER``,
``PGDATABASE``, ``PGSERVICE``, ``PGPASSWORD``, ``PGPASSFILE``,
``PGSSLMODE``, etc. Unset ``--pg-*`` options fall through to these
variables transparently.

See also
========

* :manpage:`pt-stalk(1)` - main manual page (now includes a "PostgreSQL
  mode" section with the full option reference).
* `pg_gather <https://github.com/jobinau/pg_gather>`_ - source of
  ``gather.sql`` and the analysis scripts that consume the captured
  TSV.
