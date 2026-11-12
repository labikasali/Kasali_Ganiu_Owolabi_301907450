# CHANGES.md — Ganiu Owolabi Kasali (matric 2026/A/MIT/0106), DriveEasy Rentals

The project was drafted by the student's AI tool. Claude tested it in a Codespaces-like environment and fixed what failed. Every "tested" result below was produced by running the script once as a non-root `codespace` user.

| # | File | Problem when run | Fix | Tested result |
|---|------|------------------|-----|---------------|
| 1 | P1 `bulk_generator.sql` | `SELECT ... INTO v_cat_daily[v_cat_id]` is invalid in PL/pgSQL, so the generator crashed and no rentals were created | Assign with `v_cat_daily[v_cat_id] := (SELECT ...)` | Runs without error |
| 2 | P1 `bulk_generator.sql` | Day weights were recomputed on every attempt (slow), and rentals piled up at the end of the timeline, so only 3,242 rentals were created | Each car's timeline is walked forward with random idle gaps that shrink on December/Easter/Sallah days. History plus the next 14 days | 52,000 rentals, 133,674 payments, 1,552 damage reports in about 40 s |
| 3 | P1 `seed_data.sql` | 200 cars cannot hold 50k+ non-overlapping rentals; most licences had expired, so the licence trigger rejected them | 600 cars; licences valid for the whole demo window, about 2% expired | All 11 constraint tests fail on the intended constraint |
| 4 | P2 `queries.sql`, `explain_before.sql`, `explain_after.sql` | `window` is a reserved word; `sum(interval)::numeric / interval` is invalid; `round(interval, 2)` does not exist | CTE renamed `win`; days via `EXTRACT(EPOCH ...)/86400`; average length in days | All 7 queries run |
| 5 | P2 `run_p2.sh` | BEFORE run was not fair or re-runnable (indexes stayed from the last run) | Drops the P2 indexes and runs ANALYZE before BEFORE; writes `explain_summary.txt` | Q1 4.0 → 0.8 ms, Q4 4.5 → 0.05 ms. Q2 (full-history aggregate) stays about 90-100 ms: same plan, difference is noise |
| 6 | P3 `run_p3.sh` | Race, isolation and deadlock demos needed two hand-typed terminals, so real output was hard to reproduce | New `run_race_demos.py`: 6 demos with two real sessions (bug, EXCLUDE, FOR UPDATE, SERIALIZABLE, READ COMMITTED vs REPEATABLE READ, deadlock). Output saved to `race_demos_output.log` | Bug: 2 bookings. EXCLUDE: 23P01. FOR UPDATE: 1 booking. SERIALIZABLE: 40001. Deadlock: 40P01. About 4 s |
| 7 | P4 `indexes.js` | Reported `FETCH` and `indexName: undefined` instead of IXSCAN; hard-coded car 42; not re-runnable | Walks the plan to the scan stage; picks a real target; drops the demo indexes first; prints a real summary line | COLLSCAN 42,000 docs, 12 ms → IXSCAN 210 docs, 1 ms |
| 8 | P5 `replica_setup.md` (manual) | About 8 hand steps; `pg_basebackup` waits for a spread checkpoint (hangs for minutes); replica has no config in Ubuntu | New `replica_demo.sh`: hba line at the top, `pg_basebackup -c fast`, minimal conf, copy hba/ident, chmod 700. Proves read-only replica, write rejected, row arrives, lag, `pg_stat_replication` | Primary `f`, replica `t`; INSERT rejected; new row replicated; state `streaming`. About 5 s |
| 9 | P5 `partition_setup.sql` | No DEFAULT partition; row counts came from stale statistics (all 0) | DEFAULT partition (must hold 0 rows); real counts per partition; one-month timing on partitioned vs unpartitioned tables | 19 monthly partitions plus DEFAULT = 0 rows |
| 10 | `setup.sh` | psycopg2 was never installed (P3 would fail); no time zone set | pip fallback chain with a check; `ALTER DATABASE ... SET timezone TO 'Africa/Lagos'` | `psycopg2 OK` |
| 11 | new `collect_results.sh`, `runall.sh` | No single place for evidence | Writes `my_results.txt` from the student's own logs; `runall.sh` runs P1 to P5, commits each | See `runall.sh` |

Not changed: the schema, the P4 documents/aggregations and the written cloud-architecture notes.
