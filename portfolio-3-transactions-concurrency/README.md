# Portfolio 3 — Transactions & Concurrency

**Demonstrates:** ACID, `BEGIN/COMMIT/ROLLBACK`, savepoints, a transactional stored function (`book_car`), a concurrency bug + two fixes (exclusion constraint, `SELECT … FOR UPDATE`), isolation levels, a deadlock + lock-ordering fix.
**Study session:** ACID, isolation levels, row-level locks, deadlocks, optimistic vs pessimistic concurrency control.

## Files
| File | Purpose |
|---|---|
| `book_car.sql` | `book_car()` transactional function — check car free, validate licence, insert rental, take deposit; COMMIT/ROLLBACK implied by the function body. |
| `commit_rollback_demo.sql` | Single-terminal demos: COMMIT case, deposit-failure → ROLLBACK, savepoint partial-rollback. |
| `race_condition_guide.md` | Two-terminal walkthrough: BUG (double booking on a table with no constraint) → FIX 1 (exclusion) → FIX 2 (`FOR UPDATE`). |
| `isolation_levels.sql` | READ COMMITTED (non-repeatable read) vs REPEATABLE READ (snapshot) vs SERIALIZABLE (write-skew abort). |
| `deadlock_demo.sql` | AB/BA deadlock across two terminals + lock-ordering fix. |
| `run_p3.sh` | Driver (single-terminal parts). |

## Run (Codespaces)
```bash
# assumes P1 + P2 are loaded
cd portfolio-3-transactions-concurrency
bash run_p3.sh           # runs book_car.sql + commit_rollback_demo.sql
# then open TWO psql terminals and follow:
#   race_condition_guide.md   →  isolation_levels.sql   →  deadlock_demo.sql
```

## What to screenshot for evidence
1. `commit_rollback_demo.sql`: the COMMIT case booking visible in `v_recent_bookings`, the ROLLBACK case showing `rentals_after = 0`, the savepoint case showing only the first maintenance row survived.
2. `race_condition_guide.md`: the BUG (two rows in `rental_loose` for the same car/window), FIX 1 (`exclusion_violation` raised in Terminal B), FIX 2 (Terminal B blocking, then unblocking with the function's "already booked" message).
3. `isolation_levels.sql`: the deposit value changing inside a READ COMMITTED tx but staying stable inside a REPEATABLE READ tx; SERIALIZABLE raising SQLSTATE 40001 on concurrent writes.
4. `deadlock_demo.sql`: `ERROR: deadlock detected (SQLSTATE 40P01)` in one terminal.

## Git commit
```bash
git add portfolio-3-transactions-concurrency/
git commit -m "P3: book_car() + commit/rollback + race condition + isolation + deadlock"
```

## What it demonstrates
- A real `book_car()` transaction that does several checks before inserting the rental and the deposit together — and rolls both back atomically if either fails.
- The double-booking bug reproduced honestly on a deliberately loose table, then fixed by two independent mechanisms (declarative exclusion + explicit row lock).
- The four PostgreSQL isolation levels illustrated by observable anomalies (or their absence).
- A textbook deadlock reproduced, then resolved by consistent lock ordering.


> **Update:** `run_p3.sh` now runs all six demos automatically with two real database sessions (`run_race_demos.py`, output in `race_demos_output.log`). The step-by-step guide below is the manual version of the same demos.
