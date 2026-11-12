# Portfolio 2 — Query Processing & Optimisation

**Demonstrates:** analytical SQL, `EXPLAIN ANALYZE`, B-tree / partial / covering indexes, sequential vs index scans, query plan analysis.
**Study session:** query execution & cost estimation, indexing, `EXPLAIN`, statistics.

## Files
| File | Purpose |
|---|---|
| `queries.sql` | 7 business queries (availability, revenue, utilisation, overdue, damage, one-way, category stats) |
| `explain_before.sql` | `EXPLAIN ANALYZE` of all 7 queries BEFORE indexes |
| `indexes.sql` | 7 optimisation indexes (B-tree, partial, covering) + `ANALYZE` |
| `explain_after.sql` | `EXPLAIN ANALYZE` AFTER indexes |
| `results_table.md` | Before/After table — fill `[paste real result]` from the `.txt` outputs |
| `run_p2.sh` | Driver |

## Run (Codespaces)
```bash
# assumes P1 is loaded
cd portfolio-2-query-optimisation
bash run_p2.sh
# then open results_table.md and paste the real numbers
```

## What to screenshot for evidence
1. Result tables from each of the 7 queries in `queries.sql`.
2. Side-by-side `EXPLAIN ANALYZE` for one query before vs after — show the Node Type change (Seq Scan → Index Scan) and the Execution Time drop.
3. `\di` listing the indexes created by `indexes.sql`.

## Git commit
```bash
git add portfolio-2-query-optimisation/
git commit -m "P2: 7 queries + EXPLAIN before/after + 7 optimisation indexes"
```

## What it demonstrates
- Realistic analytical workload on a 55k-row rentals table.
- Honest before/after methodology: indexes are picked for each query, applied, and `EXPLAIN ANALYZE` is rerun. No fabricated numbers — every cell in `results_table.md` is `[paste real result]` until you run it.
- Partial indexes and covering indexes (INCLUDE clause), which are advanced PostgreSQL features beyond plain B-tree.
