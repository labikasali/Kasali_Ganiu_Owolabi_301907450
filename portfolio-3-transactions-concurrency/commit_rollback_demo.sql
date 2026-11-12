-- =============================================================================
-- Portfolio 3 — commit_rollback_demo.sql
-- Demonstrates COMMIT and ROLLBACK:
--   • Successful booking → COMMIT (deposit taken)
--   • Deposit failure (negative amount, blocked by CHECK) → ROLLBACK cancels the rental
-- Run:  psql ... -f commit_rollback_demo.sql
-- =============================================================================

\set ON_ERROR_STOP 0
\echo '================ COMMIT case ================'
BEGIN;
SELECT book_car(
    p_car_id        := 3,
    p_customer_id   := 5,
    p_pickup_branch := 1,
    p_return_branch := 1,
    p_pickup_time   := now() + '14 days',
    p_return_time   := now() + '16 days',
    p_channel       := 'card'
) AS rental_id;
-- show the booking + deposit row inside this tx
TABLE v_recent_bookings;
COMMIT;
\echo '[OK] COMMIT — booking + deposit persisted.'

\echo
\echo '================ ROLLBACK case (deposit failure cancels the booking) ================'
BEGIN;
\echo 'Count before:'
SELECT count(*) AS rentals_before FROM rental WHERE car_id = 3
  AND pickup_time::date = (now() + '14 days')::date;
-- We simulate a "deposit failure" by calling book_car() and then deliberately
-- violating the payment.amount > 0 CHECK in the SAME transaction.
-- The CHECK violation aborts the whole tx, so the rental INSERT rolls back too.
DO $$
DECLARE rid bigint;
BEGIN
    SELECT book_car(
        p_car_id        := 3,
        p_customer_id   := 6,
        p_pickup_branch := 1,
        p_return_branch := 1,
        p_pickup_time   := now() + '20 days',
        p_return_time   := now() + '22 days',
        p_channel       := 'card'
    ) INTO rid;
    RAISE NOTICE 'book_car returned rental_id=% — but we will now force a deposit failure', rid;
    -- simulate downstream deposit capture failure: insert a NEGATIVE refund
    INSERT INTO payment (rental_id, amount, payment_type, paid_at, channel)
    VALUES (rid, -500, 'refund', now(), 'card');  -- violates amount > 0
END$$;
\echo '[EXPECTED] ERROR: new row for relation "payment" violates check "payment_amount_check"'
ROLLBACK;
\echo 'Count after ROLLBACK:'
SELECT count(*) AS rentals_after FROM rental WHERE car_id = 3
  AND pickup_time::date = (now() + '20 days')::date;
\echo '[OK] ROLLBACK — neither the rental nor the deposit survived.'

\echo
\echo '================ Savepoint demo (partial rollback) ================'
BEGIN;
\echo 'Inserting a maintenance row, then attempting a bad one…'
INSERT INTO maintenance (car_id, start_time, end_time, description, cost)
VALUES (3, now() + '40 days', now() + '41 days', 'Savepoint test', 5000);
SAVEPOINT sp1;
INSERT INTO maintenance (car_id, start_time, end_time, description, cost)
VALUES (3, now(), now(), 'Bad row', 1000);  -- violates end_time > start_time
\echo '[EXPECTED] ERROR on the second insert'
ROLLBACK TO sp1;
\echo 'After ROLLBACK TO sp1, the first insert survives:'
SELECT * FROM maintenance WHERE car_id = 3 AND description = 'Savepoint test';
COMMIT;
\echo '[OK] Savepoint let us roll back only the failing statement.'
