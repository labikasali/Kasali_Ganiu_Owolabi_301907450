-- =============================================================================
-- Portfolio 1 — constraint_tests.sql
-- Each test MUST FAIL with the constraint named in the comment. Run:
--   psql ... -v ON_ERROR_STOP=0 -f constraint_tests.sql
-- Expected: every "EXPECT_FAIL_*" block prints the matching SQLSTATE.
-- =============================================================================

\set ON_ERROR_STOP 0
\echo '================================================================'
\echo 'Constraint tests for DriveEasy Rentals — every test should FAIL'
\echo '================================================================'

-- Helper: pull IDs we will reuse
\set car_id 1
\set cust_id 1
\set brk_id 1

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 1 — EXCLUDE: two overlapping rentals for the SAME car MUST FAIL ---'
-- Pick a car that already has rentals; create a new rental that overlaps the most recent
DO $$
DECLARE c_id bigint; p timestamptz; r timestamptz; cust bigint; br bigint;
BEGIN
    SELECT car_id, pickup_time, return_time INTO c_id, p, r
      FROM rental ORDER BY rental_id DESC LIMIT 1;
    SELECT customer_id INTO cust FROM customer LIMIT 1;
    SELECT branch_id INTO br FROM branch LIMIT 1;
    INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                         pickup_time, return_time, start_mileage, end_mileage)
    VALUES (c_id, cust, br, br, p, r + '1 hour'::interval, 0, 50);   -- overlaps existing
END$$;
\echo '[EXPECT_FAIL] SQLSTATE 23P01 (exclusion_violation) above'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 2 — CHECK: return_time > pickup_time (returns at same time) ---'
INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                    pickup_time, return_time, start_mileage, end_mileage)
SELECT car_id, customer_id, 1, 1, now(), now(), 0, 10
  FROM car, customer LIMIT 1;
\echo '[EXPECT_FAIL] SQLSTATE 23514 (check_violation) on chk_return_after_pickup'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 3 — CHECK: end_mileage >= start_mileage (odometer backwards) ---'
INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                    pickup_time, return_time, start_mileage, end_mileage)
SELECT car_id, customer_id, 1, 1, now(), now() + '1 day'::interval, 5000, 4000
  FROM car, customer LIMIT 1;
\echo '[EXPECT_FAIL] SQLSTATE 23514 (check_violation) on chk_mileage_monotonic'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 4 — CHECK: payment.amount > 0 ---'
INSERT INTO payment (rental_id, amount, payment_type) VALUES (1, 0, 'deposit');
\echo '[EXPECT_FAIL] SQLSTATE 23514 on payment_amount_check'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 5 — CHECK: daily_rate > 0 on car_category ---'
INSERT INTO car_category (name, daily_rate, deposit) VALUES ('BadCat', 0, 1000);
\echo '[EXPECT_FAIL] SQLSTATE 23514 on car_category_daily_rate_check'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 6 — UNIQUE: duplicate plate_number ---'
INSERT INTO car (plate_number, category_id, home_branch_id, mileage, status)
SELECT plate_number, category_id, home_branch_id, 1000, 'available'
  FROM car LIMIT 1;
\echo '[EXPECT_FAIL] SQLSTATE 23505 (unique_violation) on car_plate_number_key'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 7 — FK: rental.car_id referencing a non-existent car ---'
INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                    pickup_time, return_time, start_mileage, end_mileage)
VALUES (9999999, 1, 1, 1, now(), now() + '1 day'::interval, 0, 100);
\echo '[EXPECT_FAIL] SQLSTATE 23503 (foreign_key_violation)'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 8 — TRIGGER: licence expired before pickup date ---'
-- Insert a customer with an expired licence, then try to book a pickup after expiry
DO $$
DECLARE cid bigint; now_dt timestamptz := now();
BEGIN
    INSERT INTO customer (first_name, last_name, phone, email, address)
    VALUES ('Expired','Licence','+2348099999999','expired.licence@example.com','Lagos')
    RETURNING customer_id INTO cid;
    INSERT INTO driver_licence (customer_id, licence_number, issue_date, expiry_date)
    VALUES (cid, 'NIG-EXP0001', date '2018-01-01', date '2019-01-01');  -- expired

    INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                        pickup_time, return_time, start_mileage, end_mileage)
    VALUES (1, cid, 1, 1, now_dt + '7 days'::interval, now_dt + '8 days'::interval, 0, 50);
END$$;
\echo '[EXPECT_FAIL] SQLSTATE P0001 raised by trg_licence_valid_on_pickup'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 9 — TRIGGER: rental overlapping a maintenance window ---'
DO $$
DECLARE c_id bigint; m_start timestamptz; m_end timestamptz;
BEGIN
    -- find a car that has a maintenance window in the future
    SELECT car_id, start_time, end_time INTO c_id, m_start, m_end
      FROM maintenance WHERE end_time > now() LIMIT 1;
    IF c_id IS NULL THEN
        RAISE NOTICE 'No future maintenance row found — skipping TEST 9';
        RETURN;
    END IF;
    INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                        pickup_time, return_time, start_mileage, end_mileage)
    VALUES (c_id, 1, 1, 1, m_start + '1 hour'::interval, m_end + '1 hour'::interval, 0, 100);
END$$;
\echo '[EXPECT_FAIL] SQLSTATE P0001 raised by trg_no_rental_during_maintenance'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 10 — CHECK: maintenance end_time > start_time ---'
INSERT INTO maintenance (car_id, start_time, end_time, description, cost)
VALUES (1, now(), now(), 'Bad', 1000);
\echo '[EXPECT_FAIL] SQLSTATE 23514 on chk_maint_end_after_start'

-- ---------------------------------------------------------------------------
\echo
\echo '--- TEST 11 — CHECK: car.status invalid enum ---'
INSERT INTO car (plate_number, category_id, home_branch_id, mileage, status)
VALUES ('TEST-999XX', 1, 1, 0, 'stolen');
\echo '[EXPECT_FAIL] SQLSTATE 23514 on car_status_check'

\echo
\echo '================================================================'
\echo 'End of constraint tests. All blocks above should have shown an ERROR.'
\echo '================================================================'
