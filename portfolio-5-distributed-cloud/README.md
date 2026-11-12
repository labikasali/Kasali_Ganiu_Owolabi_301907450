# Portfolio 5 — Distributed & Cloud Database Exercise

**Demonstrates:** declarative partitioning by month, physical streaming replication with primary/replica roles, replica rejecting writes, new rows arriving on the replica, CAP trade-offs, sync vs async replication, NDPA 2023 data sovereignty, and December-rush scaling.
**Study session:** declarative partitioning, physical streaming replication, primary/replica roles, CAP & consistency, sharding, cloud deployment, data sovereignty.

## Files
| File | Purpose |
|---|---|
| `partition_setup.sql` | Creates `rental_p` as a partitioned-by-month table, copies rentals in, demonstrates pruning. |
| `replica_setup.md` | Step-by-step (Codespaces-safe) guide for setting up a primary + streaming read replica, including replica rejecting writes and new rows arriving. |
| `cloud_architecture.md` | NDPA 2023 sovereignty, CAP positioning, sync vs async, sharding strategy, December-rush handling, reference architecture diagram, summary table. |
| `run_p5.sh` | Driver (runs the partitioning demo; replica setup is hand-run from `replica_setup.md`). |

## Run (Codespaces)
```bash
# assumes setup.sh has installed PostgreSQL 16 and P1 is loaded
cd portfolio-5-distributed-cloud
bash run_p5.sh
# then follow replica_setup.md by hand (~5 min, two terminals)
```

## What to screenshot for evidence
1. `partition_setup.sql`: `\d+ rental_p` showing the partition tree; partition sizes; `EXPLAIN (COSTS OFF)` showing only the touched partitions scanned ("Subplans Removed").
2. `replica_setup.md`:
   - `pg_lsclusters` with `16/main` (online) and `16/replica` (online).
   - `SELECT pg_is_in_recovery();` returning `f` on 5432 and `t` on 5433.
   - `pg_stat_replication` row with `state=streaming`.
   - Replica rejecting an `INSERT` (read-only transaction error).
   - New branch on the primary arriving on the replica.
   - (Optional) `sync_state=sync` after enabling synchronous replication.
3. `cloud_architecture.md` is read-only — no screenshot needed, but reference it in the final documentation.

## Git commit
```bash
git add portfolio-5-distributed-cloud/
git commit -m "P5: monthly partitioning + primary/replica + cloud architecture (NDPA, CAP)"
```

## What it demonstrates
- Real declarative partitioning with **partition pruning** — the planner skips partitions whose ranges fall outside the query window.
- A working **physical streaming replica**: same VM, two clusters, different ports, Unix-socket connections, trust lines at the top of `pg_hba.conf` (per the Codespaces rules in the brief).
- Honest replication behaviour: the replica rejects writes (read-only transaction), and new rows inserted on the primary arrive on the replica within seconds.
- A written cloud design that ties the technical setup to NDPA 2023 (data stays in Nigeria), CAP (CP at the primary, eventual at the replica), sync vs async trade-offs, and the December-rush scaling plan.


> **Update:** `run_p5.sh` now builds the replica with one script (`replica_demo.sh`, output in `replication_output.log`). `replica_setup.md` is the manual version of the same steps.
