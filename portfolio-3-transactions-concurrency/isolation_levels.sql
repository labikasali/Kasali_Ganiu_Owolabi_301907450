-- =============================================================================
-- Portfolio 3 — isolation_levels.sql
-- Demonstrates the difference between READ COMMITTED and REPEATABLE READ
-- (and SERIALIZABLE) on the DriveEasy Rentals schema.
--
-- Run the FIRST half of this file in Terminal A and the SECOND half in Terminal B,
-- interleaving them as the comments say. Each block is independent.
-- =============================================================================

\echo '########################################################################'
\echo '# DEMO 1 — READ COMMITTED: a non-repeatable read'
\echo '# Run "Step A1" in Terminal A, then "Step B1" in Terminal B, then "Step A2" in A.'
\echo '########################################################################'

\echo
\echo '--- Terminal A — Step A1: BEGIN ISOLATION LEVEL READ COMMITTED; read deposit ---'
\echo 'BEGIN ISOLATION LEVEL READ COMMITTED;'
\echo 'SELECT deposit FROM car_category WHERE category_id = 1;  -- observe the value'
\echo '-- (do not commit; switch to Terminal B)'

\echo
\echo '--- Terminal B — Step B1: UPDATE the deposit and COMMIT ---'
\echo 'UPDATE car_category SET deposit = deposit + 1 WHERE category_id = 1;'
\echo 'COMMIT;'

\echo
\echo '--- Terminal A — Step A2: re-read the SAME row inside the SAME tx ---'
\echo 'SELECT deposit FROM car_category WHERE category_id = 1;'
\echo '-- >>> screenshot: value CHANGED inside the same transaction (non-repeatable read).'
\echo 'ROLLBACK;'

\echo
\echo '########################################################################'
\echo '# DEMO 2 — REPEATABLE READ: the same row read twice returns the SAME value'
\echo '########################################################################'

\echo
\echo '--- Terminal A — Step A1: BEGIN ISOLATION LEVEL REPEATABLE READ ---'
\echo 'BEGIN ISOLATION LEVEL REPEATABLE READ;'
\echo 'SELECT deposit FROM car_category WHERE category_id = 2;  -- observe the value'
\echo '-- (do not commit; switch to Terminal B)'

\echo
\echo '--- Terminal B — Step B1: UPDATE the deposit and COMMIT ---'
\echo 'UPDATE car_category SET deposit = deposit + 1 WHERE category_id = 2;'
\echo 'COMMIT;'

\echo
\echo '--- Terminal A — Step A2: re-read ---'
\echo 'SELECT deposit FROM car_category WHERE category_id = 2;'
\echo '-- >>> screenshot: value UNCHANGED inside this transaction (snapshot isolation).'
\echo '-- Now if Terminal A tries to UPDATE the same row it just read,'
\echo '-- it gets: ERROR: could not serialize access due to concurrent update'
\echo 'ROLLBACK;'

\echo
\echo '########################################################################'
\echo '# DEMO 3 — SERIALIZABLE: a write-skew anomaly prevented'
\echo '# Two transactions both check "is the other category under-used?" and'
\echo '# both decide to mark a car as available — under SERIALIZABLE one is aborted.'
\echo '########################################################################'

\echo '--- Terminal A ---'
\echo 'BEGIN ISOLATION LEVEL SERIALIZABLE;'
\echo 'SELECT count(*) AS active FROM rental WHERE car_id = 6 AND status=''booked'';'
\echo '-- if active < 5, INSERT a new maintenance row (this is our write)'
\echo 'INSERT INTO maintenance (car_id, start_time, end_time, description, cost)'
\echo 'VALUES (6, now() + ''30 days'', now() + ''31 days'', ''Serializable test A'', 1000);'
\echo 'COMMIT;  -- may raise: ERROR: could not serialize access due to read/write dependencies'

\echo '--- Terminal B (run concurrently with A) ---'
\echo 'BEGIN ISOLATION LEVEL SERIALIZABLE;'
\echo 'SELECT count(*) AS active FROM rental WHERE car_id = 6 AND status=''booked'';'
\echo 'INSERT INTO maintenance (car_id, start_time, end_time, description, cost)'
\echo 'VALUES (6, now() + ''30 days'', now() + ''31 days'', ''Serializable test B'', 1000);'
\echo 'COMMIT;  -- the second to commit gets SQLSTATE 40001 and must retry'
