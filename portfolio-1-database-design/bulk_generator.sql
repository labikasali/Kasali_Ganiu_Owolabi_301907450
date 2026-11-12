-- =============================================================================
-- Portfolio 1 — bulk_generator.sql
-- Generates 50,000+ rentals over the last 2 years (relative to TODAY, never expires)
--   • No overlapping rentals per car (enforced by EXCLUDE; we also avoid them up front)
--   • Seasonal peaks: December rush + Easter + Sallah peaks (heavier volume)
--   • Nigerian plate numbers (already seeded in seed_data.sql)
--   • Nigerian customer names (already seeded)
--   • Dates and prices in ₦
-- Run AFTER schema.sql + seed_data.sql:  psql ... -f bulk_generator.sql
-- =============================================================================

\set ON_ERROR_STOP on
\timing on

-- 1. Standalone helper function: weight per day-of-year so December + Easter + Sallah peak.
--    (Declared OUTSIDE the DO block so we can use plain $$ dollar-quoting without clashing.)
CREATE OR REPLACE FUNCTION driveeasy_day_weight(d timestamptz) RETURNS float LANGUAGE plpgsql AS $$
DECLARE
    m            int  := extract(month FROM d);
    eid_window   boolean := (d::date IN (
        '2024-04-10','2024-04-11','2024-04-12','2024-04-13','2024-04-14','2024-04-15',
        '2024-06-16','2024-06-17','2024-06-18','2024-06-19','2024-06-20',
        '2025-03-30','2025-03-31','2025-04-01','2025-04-02','2025-04-03','2025-04-04',
        '2025-06-06','2025-06-07','2025-06-08','2025-06-09','2025-06-10','2025-06-11',
        '2026-03-20','2026-03-21','2026-03-22','2026-03-23','2026-03-24','2026-03-25',
        '2026-05-27','2026-05-28','2026-05-29','2026-05-30','2026-05-31','2026-06-01',
        '2027-03-10','2027-03-11','2027-03-12','2027-03-13','2027-03-14','2027-03-15'
    ));
    easter_window boolean := (d::date IN (
        '2024-03-29','2024-03-30','2024-03-31','2024-04-01','2024-04-02',
        '2025-04-18','2025-04-19','2025-04-20','2025-04-21','2025-04-22',
        '2026-04-03','2026-04-04','2026-04-05','2026-04-06','2026-04-07',
        '2027-03-26','2027-03-27','2027-03-28','2027-03-29','2027-03-30'
    ));
BEGIN
    IF m = 12 THEN
        RETURN 3.5;
    END IF;
    IF easter_window OR eid_window THEN
        RETURN 3.0;
    END IF;
    IF extract(dow FROM d) IN (0,6) THEN
        RETURN 1.4;
    END IF;
    RETURN 1.0;
END;
$$;

-- 2. Main generation loop (DO block).
DO $gen$
DECLARE
    v_target_rentals int  := 52000;
    v_years_back     int  := 2;
    v_horizon_start  timestamptz := date_trunc('day', now()) - (v_years_back || ' years')::interval;
    v_horizon_end    timestamptz := date_trunc('day', now()) + '14 days'::interval;
    v_horizon_days   int  := (extract(epoch FROM (v_horizon_end - v_horizon_start))::bigint / 86400)::int;

    v_cars        bigint[];
    v_cust_ids    bigint[];
    v_cust_n      int;
    v_cat_daily   numeric(12,2)[];   -- index 1..5
    v_cat_dep     numeric(12,2)[];
    v_br_ids      bigint[];

    v_inserted    int  := 0;
    v_attempts    int  := 0;
    v_max_attempts int := 400000;

    v_car_id      bigint;
    v_cust_id     bigint;
    v_p_brk       bigint;
    v_r_brk       bigint;
    v_p_time      timestamptz;
    v_r_time      timestamptz;
    v_start_km    int;
    v_end_km      int;
    v_cat_id      int;
    v_days        int;
    v_daily       numeric(12,2);
    v_dep         numeric(12,2);
    v_base_amount numeric(12,2);
    v_extra_km    int;
    v_extra_fee   numeric(12,2);
    v_late_hours  int;
    v_late_fee    numeric(12,2);

    v_w_sum       float;
    v_rnd         float;
    v_cum         float;
    v_chosen_day  timestamptz;
    v_d_idx       int;
    v_i           int;
    v_lp_epoch    bigint;
    v_car_idx     int;
    v_cust_idx    int;
    v_brk_idx     int;
    v_last_pickup bigint[];   -- v_last_pickup[car_id] = epoch millis
    v_window      tstzrange;
    v_rental_id   bigint;
    v_attempts_save int;
    v_wcum        float[];
BEGIN
    SELECT array_agg(car_id)      INTO v_cars      FROM car;
    SELECT array_agg(customer_id) INTO v_cust_ids  FROM customer;
    SELECT array_agg(branch_id)   INTO v_br_ids    FROM branch;
    v_cust_n := array_length(v_cust_ids, 1);

    -- daily_rate / deposit per category id 1..5
    FOR v_cat_id IN 1..5 LOOP
        v_cat_daily[v_cat_id] := (SELECT daily_rate FROM car_category WHERE category_id = v_cat_id);
        v_cat_dep[v_cat_id]   := (SELECT deposit    FROM car_category WHERE category_id = v_cat_id);
    END LOOP;

    -- last pickup per car = horizon_start - 1d (so the first rental can start anywhere)
    FOR v_i IN 1..array_length(v_cars, 1) LOOP
        v_last_pickup[v_cars[v_i]] := (extract(epoch FROM (v_horizon_start - '1 day'::interval))::bigint) * 1000;
    END LOOP;

    <<gen_loop>>
    WHILE v_inserted < v_target_rentals AND v_attempts < v_max_attempts LOOP
        v_attempts := v_attempts + 1;

        -- pick a car uniformly at random
        v_car_idx := 1 + floor(random() * array_length(v_cars, 1))::int;
        v_car_id  := v_cars[v_car_idx];

        -- pick a day weighted by driveeasy_day_weight()
        -- rental length: 1..10 days (mostly 1..3)
        IF random() < 0.6 THEN
            v_days := 1 + floor(random()*3)::int;
        ELSE
            v_days := 1 + floor(random()*10)::int;
        END IF;

        -- next pickup = this car's previous return + a random idle gap; the gap shrinks on
        -- peak days (December / Easter / Sallah) so volume peaks there. Walking each car's
        -- timeline forward means rentals never overlap and never pile up at the end.
        v_p_time := to_timestamp(v_last_pickup[v_car_id] / 1000.0);
        v_p_time := v_p_time + make_interval(mins => (random() * 5760 / driveeasy_day_weight(v_p_time))::int + 120);
        v_p_time := date_trunc('hour', v_p_time) + (floor(random()*4) * 15 || ' minutes')::interval;
        v_r_time := v_p_time + (v_days || ' days')::interval - (floor(random()*3) || ' hours')::interval;
        IF v_r_time <= v_p_time THEN
            v_r_time := v_p_time + '1 day'::interval;
        END IF;

        -- skip if this rental would extend beyond the horizon end
        IF v_r_time > v_horizon_end THEN
            CONTINUE;
        END IF;

        v_window := tstzrange(v_p_time, v_r_time, '[)');

        -- skip if a maintenance window overlaps (cheap pre-check)
        PERFORM 1 FROM maintenance
          WHERE maintenance.car_id = v_car_id
            AND tstzrange(maintenance.start_time, maintenance.end_time, '[)') && v_window
          LIMIT 1;
        IF FOUND THEN CONTINUE; END IF;

        -- customer & branches
        v_cust_idx := 1 + floor(random() * v_cust_n)::int;
        v_cust_id  := v_cust_ids[v_cust_idx];
        v_brk_idx  := 1 + floor(random() * array_length(v_br_ids, 1))::int;
        v_p_brk    := v_br_ids[v_brk_idx];
        v_r_brk    := v_br_ids[1 + floor(random() * array_length(v_br_ids, 1))::int];

        -- mileage
        SELECT mileage INTO v_start_km FROM car WHERE car.car_id = v_car_id;
        v_end_km := v_start_km + (v_days * (80 + floor(random()*200)::int));
        SELECT category_id INTO v_cat_id FROM car WHERE car.car_id = v_car_id;
        v_daily := v_cat_daily[v_cat_id];
        v_dep   := v_cat_dep[v_cat_id];

        v_base_amount := v_daily * v_days;

        -- late fee (~15% of rentals return late)
        v_late_hours := 0;
        IF random() < 0.15 THEN
            v_late_hours := 1 + floor(random()*36)::int;
            v_late_fee   := (v_daily / 24.0) * v_late_hours;
        ELSE
            v_late_fee := 0;
        END IF;

        -- extra mileage fee: ₦250/km over 200 km/day
        v_extra_km  := GREATEST(0, (v_end_km - v_start_km) - v_days * 200);
        v_extra_fee := v_extra_km * 250.0;

        BEGIN
            INSERT INTO rental (car_id, customer_id, pickup_branch_id, return_branch_id,
                                pickup_time, return_time, start_mileage, end_mileage, status)
            VALUES (v_car_id, v_cust_id, v_p_brk, v_r_brk, v_p_time, v_r_time,
                    v_start_km, v_end_km,
                    CASE WHEN v_r_time < now() THEN 'returned' ELSE 'booked' END)
            RETURNING rental_id INTO v_rental_id;

            -- payments: deposit (always) + rental + fees (only if returned)
            INSERT INTO payment (rental_id, amount, payment_type, paid_at, channel)
            VALUES (v_rental_id, v_dep, 'deposit',
                    v_p_time - '15 minutes'::interval,
                    CASE floor(random()*3)::int WHEN 0 THEN 'card' WHEN 1 THEN 'transfer' ELSE 'cash' END);

            IF v_r_time < now() THEN
                INSERT INTO payment (rental_id, amount, payment_type, paid_at, channel)
                VALUES (v_rental_id, v_base_amount, 'rental',
                        v_r_time, CASE floor(random()*2)::int WHEN 0 THEN 'card' ELSE 'transfer' END);

                IF v_late_fee > 0 THEN
                    INSERT INTO payment (rental_id, amount, payment_type, paid_at, channel)
                    VALUES (v_rental_id, v_late_fee, 'late_fee', v_r_time + '1 hour'::interval, 'card');
                END IF;
                IF v_extra_fee > 0 THEN
                    INSERT INTO payment (rental_id, amount, payment_type, paid_at, channel)
                    VALUES (v_rental_id, v_extra_fee, 'mileage_fee', v_r_time + '1 hour'::interval, 'card');
                END IF;

                -- damage report (~3% of returned rentals)
                IF random() < 0.03 THEN
                    INSERT INTO damage_report (rental_id, description, estimated_cost, reported_at, severity)
                    VALUES (v_rental_id,
                            CASE floor(random()*4)::int
                                WHEN 0 THEN 'Bumper scratch'
                                WHEN 1 THEN 'Cracked side mirror'
                                WHEN 2 THEN 'Tyre puncture'
                                ELSE 'Interior stain' END,
                            5000 + floor(random()*120000)::int,
                            v_r_time + '30 minutes'::interval,
                            CASE WHEN random() < 0.7  THEN 'minor'
                                 WHEN random() < 0.95 THEN 'moderate'
                                 ELSE 'major' END);

                    INSERT INTO payment (rental_id, amount, payment_type, paid_at, channel)
                    SELECT v_rental_id, estimated_cost, 'damage_fee',
                           v_r_time + '1 hour'::interval, 'card'
                      FROM damage_report WHERE rental_id = v_rental_id
                      ORDER BY damage_id DESC LIMIT 1;
                END IF;

                -- advance the car's odometer
                UPDATE car SET mileage = v_end_km WHERE car.car_id = v_car_id;
            END IF;

            v_last_pickup[v_car_id] := (extract(epoch FROM v_r_time)::bigint) * 1000;
            v_inserted := v_inserted + 1;

            IF v_inserted % 5000 = 0 THEN
                RAISE NOTICE 'Inserted % / % rentals (attempts=%)', v_inserted, v_target_rentals, v_attempts;
            END IF;
        EXCEPTION
            WHEN exclusion_violation THEN
                CONTINUE;     -- overlap with an existing rental — try another car/time
            WHEN OTHERS THEN
                RAISE NOTICE 'Skipped at attempt %: %', v_attempts, SQLERRM;
                CONTINUE;
        END;
    END LOOP;

    RAISE NOTICE 'Done. inserted=%  attempts=%', v_inserted, v_attempts;
END
$gen$;

-- 3. Drop the helper (no longer needed)
DROP FUNCTION IF EXISTS driveeasy_day_weight(timestamptz);

-- 4. Final counts
SELECT 'rentals' AS table_name, count(*) FROM rental
UNION ALL SELECT 'payments', count(*) FROM payment
UNION ALL SELECT 'damage_reports', count(*) FROM damage_report;

-- 5. Show the December rush effect (rentals per month should peak in December)
SELECT to_char(pickup_time, 'YYYY-MM') AS ym,
       count(*) AS rentals
  FROM rental
 GROUP BY ym
 ORDER BY ym DESC
 LIMIT 24;
