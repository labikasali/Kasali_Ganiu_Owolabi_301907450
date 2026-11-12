# Portfolio 2 — Query Optimisation: Before / After Indexes

> Replace every `[paste real result]` placeholder with the actual values from your `explain_before.txt` and `explain_after.txt` runs (run `run_p2.sh`). Do NOT invent numbers.

All times in **milliseconds** unless stated. Capture: the **Execution Time** line at the bottom of each `EXPLAIN ANALYZE`, the top **Node Type** (Seq Scan / Index Scan / Bitmap Heap Scan), and a one-line comment.

| Q# | Query | Before: Node Type | Before: Exec Time (ms) | After: Node Type | After: Exec Time (ms) | Speedup | Notes |
|----|-------|-------------------|-------------------------|------------------|------------------------|---------|-------|
| Q1 | Cars available at branch for dates | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | Seq Scan on car → Index Scan via `idx_car_branch_status`; the gist index `idx_rental_range_gist` collapses the anti-join subquery. |
| Q2 | Revenue per branch per month | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | Composite `idx_rental_pickup_br_time` lets the planner skip older months without re-sorting. |
| Q3 | Fleet utilisation % per category | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | The GiST index on `rental_range` is reused for the overlap predicate. |
| Q4 | Overdue returns | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | Partial index `idx_rental_overdue WHERE status='booked'` reduces the scanned set. |
| Q5 | Customers with damage history | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | Index-only scan possible via `idx_payment_rental_type_amount INCLUDE (amount)`. |
| Q6 | One-way rentals between branches | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | Partial index `idx_rental_one_way WHERE pickup_branch_id <> return_branch_id`. |
| Q7 | Avg rental length + revenue per category | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | `[paste real result]` | The LATERAL `payment` lookup uses `idx_payment_rental_type_amount`. |

## Indexes added (from `indexes.sql`)
| Index | On | Used by |
|-------|----|--------|
| `idx_car_branch_status` | `car(home_branch_id, status)` | Q1 |
| `idx_rental_pickup_br_time` | `rental(pickup_branch_id, pickup_time)` | Q2, Q6 |
| `idx_rental_overdue` | `rental(return_time) WHERE status='booked'` | Q4 |
| `idx_rental_pickup_time_recent` | `rental(pickup_time) WHERE status='returned'` | Q3, Q7 |
| `idx_damage_rental_severity` | `damage_report(rental_id)` | Q5 |
| `idx_payment_rental_type_amount` | `payment(rental_id, payment_type) INCLUDE (amount)` | Q2, Q5, Q7 |
| `idx_rental_one_way` | `rental(pickup_branch_id, return_branch_id, pickup_time) WHERE pickup_branch_id <> return_branch_id` | Q6 |

## Observations to discuss in the final documentation (after real runs)
- The biggest gain is expected on **Q4 (overdue returns)** because the partial index filters out ~99% of rows (most rentals are `returned`).
- **Q5** gains an index-only scan only if `VACUUM`/`ANALYZE` have run — included in `indexes.sql`.
- The GiST index on `rental_range` is already required by the EXCLUDE constraint in P1, so it is "free" for Q1 and Q3.
- Some queries (Q2, Q6) need a sort at the end because the GROUP BY columns differ from the index order; consider an aggregate-increasing strategy if the gap is large.
