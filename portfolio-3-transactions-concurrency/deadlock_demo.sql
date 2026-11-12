-- =============================================================================
-- Portfolio 3 — deadlock_demo.sql
-- Classic AB-BA deadlock between two transactions:
--   T1 locks car A then tries to lock car B
--   T2 locks car B then tries to lock car A
-- One of them is aborted with SQLSTATE 40P01 (deadlock_detected).
--
-- Run Step 1 in Terminal A and Step 1 in Terminal B first; then run Step 2 in both.
-- =============================================================================

\echo '########################################################################'
\echo '# DEADLOCK DEMO — AB/BA pattern'
\echo '# Each terminal must BEGIN, lock its first car, wait, then try the second.'
\echo '########################################################################'

\echo
\echo '--- Terminal A — Step 1 ---'
\echo 'BEGIN;'
\echo 'SELECT * FROM car WHERE car_id = 7 FOR UPDATE;   -- locks car 7'
\echo '-- pause; switch to Terminal B Step 1'

\echo
\echo '--- Terminal B — Step 1 ---'
\echo 'BEGIN;'
\echo 'SELECT * FROM car WHERE car_id = 8 FOR UPDATE;   -- locks car 8'
\echo '-- pause; switch back to Terminal A Step 2'

\echo
\echo '--- Terminal A — Step 2 ---'
\echo 'SELECT * FROM car WHERE car_id = 8 FOR UPDATE;   -- WAITS for Terminal B'
\echo '-- switch to Terminal B Step 2 immediately'

\echo
\echo '--- Terminal B — Step 2 ---'
\echo 'SELECT * FROM car WHERE car_id = 7 FOR UPDATE;   -- DEADLOCK detected here'
\echo '-- >>> EXPECTED:  ERROR: deadlock detected  (SQLSTATE 40P01)'
\echo 'ROLLBACK;'

\echo
\echo '--- Terminal A — now unblocked ---'
\echo 'SELECT * FROM car WHERE car_id = 8 FOR UPDATE;  -- succeeds'
\echo 'COMMIT;'

\echo
\echo '########################################################################'
\echo '# HOW TO FIX IT — consistent lock ordering'
\echo '# Always lock cars in ascending car_id order. Then T1 and T2 both grab'
\echo '# car 7 first, then car 8 — they serialise instead of deadlocking.'
\echo '########################################################################'
