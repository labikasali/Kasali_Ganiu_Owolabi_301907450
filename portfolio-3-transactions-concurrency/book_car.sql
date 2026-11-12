-- =============================================================================
-- Portfolio 3 — book_car.sql
-- A transactional function that:
--   1. checks the car is free for the requested window (no overlapping rental,
--      no overlapping maintenance)
--   2. checks the customer's driver licence is valid on pickup
--   3. inserts the rental (status='booked')
--   4. takes the security deposit (inserts a 'deposit' payment)
--   5. COMMITs on success, ROLLBACKs on any failure (the rental is cancelled too)
--
-- Run AFTER P1 + P2:   psql ... -f book_car.sql
-- Call:
--   SELECT book_car(car_id => 7,
--                   customer_id => 42,
--                   pickup_branch_id => 1,
--                   return_branch_id => 1,
--                   pickup_time => now() + '3 days',
--                   return_time => now() + '5 days');
-- =============================================================================

\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS book_car(bigint, bigint, bigint, bigint, timestamptz, timestamptz, text);

CREATE OR REPLACE FUNCTION book_car(
    p_car_id        bigint,
    p_customer_id   bigint,
    p_pickup_branch bigint,
    p_return_branch bigint,
    p_pickup_time   timestamptz,
    p_return_time   timestamptz,
    p_channel       text DEFAULT 'card'
) RETURNS bigint AS $$
DECLARE
    v_rental_id   bigint;
    v_deposit     numeric(12,2);
    v_licence_exp date;
    v_window      tstzrange := tstzrange(p_pickup_time, p_return_time, '[)');
    v_status      text;
BEGIN
    -- basic validations
    IF p_return_time <= p_pickup_time THEN
        RAISE EXCEPTION 'return_time must be later than pickup_time'
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_channel NOT IN ('card','transfer','cash') THEN
        RAISE EXCEPTION 'invalid payment channel %', p_channel
            USING ERRCODE = 'check_violation';
    END IF;

    -- (1) car must exist and not be in maintenance
    SELECT status INTO v_status FROM car WHERE car_id = p_car_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'car % not found', p_car_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_status = 'maintenance' THEN
        RAISE EXCEPTION 'car % is in maintenance — cannot book', p_car_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- (2) licence must be valid on pickup date
    SELECT expiry_date INTO v_licence_exp
      FROM driver_licence WHERE customer_id = p_customer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'customer % has no licence on file', p_customer_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_licence_exp < p_pickup_time::date THEN
        RAISE EXCEPTION 'licence expired % before pickup %', v_licence_exp, p_pickup_time::date
            USING ERRCODE = 'check_violation';
    END IF;

    -- (3) car must be free in the requested window.
    --     The EXCLUDE constraint enforces this at write time; we ALSO check up front
    --     so we can return a clear message instead of an exclusion_violation.
    PERFORM 1 FROM rental
      WHERE car_id = p_car_id
        AND rental_range && v_window
      LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'car % already booked in %', p_car_id, v_window
            USING ERRCODE = 'exclusion_violation';
    END IF;

    -- (3b) car must not be in maintenance during the window
    PERFORM 1 FROM maintenance
      WHERE car_id = p_car_id
        AND tstzrange(start_time, end_time, '[)') && v_window
      LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'car % is scheduled for maintenance in %', p_car_id, v_window
            USING ERRCODE = 'exclusion_violation';
    END IF;

    -- (4) deposit for this car's category
    SELECT cc.deposit INTO v_deposit
      FROM car c JOIN car_category cc ON cc.category_id = c.category_id
     WHERE c.car_id = p_car_id;

    -- (5) INSERT rental — status 'booked'
    INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                        pickup_time, return_time, start_mileage, end_mileage, status)
    VALUES (p_car_id, p_customer_id, p_pickup_branch, p_return_branch,
            p_pickup_time, p_return_time,
            (SELECT mileage FROM car WHERE car_id = p_car_id),
            (SELECT mileage FROM car WHERE car_id = p_car_id),
            'booked')
    RETURNING rental_id INTO v_rental_id;

    -- (6) take deposit payment — if this fails, the whole function rolls back
    INSERT INTO payment (rental_id, amount, payment_type, paid_at, channel)
    VALUES (v_rental_id, v_deposit, 'deposit', now(), p_channel);

    RETURN v_rental_id;
END;
$$ LANGUAGE plpgsql;

-- helper view to inspect a booking
CREATE OR REPLACE VIEW v_recent_bookings AS
SELECT r.rental_id, c.plate_number, cu.last_name AS customer,
       r.pickup_time, r.return_time, r.status,
       p.amount AS deposit, p.channel
  FROM rental r
  JOIN car c ON c.car_id = r.car_id
  JOIN customer cu ON cu.customer_id = r.customer_id
  LEFT JOIN payment p ON p.rental_id = r.rental_id AND p.payment_type = 'deposit'
  ORDER BY r.rental_id DESC
  LIMIT 20;
