-- =============================================================================
-- Portfolio 1 — seed_data.sql  (small base data; bulk rentals are in bulk_generator.sql)
-- Run AFTER schema.sql:  psql ... -f seed_data.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- Branches -----------------------------------------------------------------
INSERT INTO branch (code, name, city, address, phone) VALUES
  ('IKE', 'DriveEasy Ikeja',           'Lagos', '21 Awolowo Way, Ikeja',          '+2348010000001'),
  ('LKK', 'DriveEasy Lekki',           'Lagos', '4 Admiralty Way, Lekki Phase 1', '+2348010000002'),
  ('VTC', 'DriveEasy Victoria Island', 'Lagos', '12 Akin Adesola St, V/I',        '+2348010000003'),
  ('MMA', 'DriveEasy MM Airport',      'Lagos', 'Murtala Muhammed Intl Airport',  '+2348010000004'),
  ('ABJ', 'DriveEasy Abuja Airport',   'Abuja', 'Nnamdi Azikiwe Intl Airport',    '+2348010000005');

-- Car categories (₦ prices) ------------------------------------------------
INSERT INTO car_category (name, daily_rate, deposit) VALUES
  ('Economy',  18000.00,  50000.00),
  ('SUV',      45000.00, 100000.00),
  ('Luxury',   90000.00, 250000.00),
  ('Mini-bus', 60000.00, 120000.00),
  ('Van',      55000.00, 110000.00);

-- 200 cars, plate numbers like LAG-001AA .. LAG-200HG (state codes LAG/ABJ)
DO $$
DECLARE
    c text[]; st text; plate text;
    i int; cat int; br int;
BEGIN
    c := ARRAY['IKE','LKK','VTC','MMA','ABJ'];
    FOR i IN 1..600 LOOP
        cat := ((i-1) % 5) + 1;                          -- cycle through 5 categories
        br  := ((i-1) % 5) + 1;                          -- cycle through 5 branches
        st  := CASE WHEN br = 5 THEN 'ABJ' ELSE 'LAG' END;
        plate := st || '-' || lpad((i::text), 3, '0') ||
                 chr(65 + ((i-1) % 26)) ||               -- A..Z
                 chr(65 + ((i-1) % 24));                  -- A..X
        INSERT INTO car (plate_number, category_id, home_branch_id, mileage, status)
        VALUES (plate, cat, br, 1000 + (i*73) % 180000, 'available');
    END LOOP;
END$$;

-- 5,000 customers + licences (Nigerian names, expiry dates spanning past+future)
DO $$
DECLARE first TEXT[]; last TEXT[]; fn TEXT; ln TEXT; em TEXT; ph TEXT; addr TEXT;
        i int; cid bigint; issue date; expiry date;
BEGIN
    first := ARRAY['Adebayo','Chinedu','Fatima','Tunde','Ngozi','Emeka','Aisha','Bola',
                   'Ibrahim','Yetunde','Kunle','Halima','Obinna','Zainab','Seyi','Amina',
                   'Temitope','Yusuf','Funmilayo','Danjuma','Adaeze','Gbenga','Mariam',
                   'Oluwaseun','Hauwa','Chiamaka','Bayo','Ruqayyah','Ekene','Bilqis'];
    last  := ARRAY['Adeyemi','Okafor','Bello','Olawale','Eze','Mohammed','Okafor','Lawal',
                   'Ogunleye','Suleiman','Nwosu','Adewale','Yusuf','Okonkwo','Abdullahi',
                   'Adeleke','Ibrahim','Ojo','Adebowale','Musa','Okeke','Balogun','Idris',
                   'Olanrewaju','Danjuma','Ibrahim','Eze','Okoro','Adebayo','Mohammed'];
    FOR i IN 1..5000 LOOP
        fn := first[1 + (i % array_length(first,1))];
        ln := last [1 + ((i*7) % array_length(last,1))];
        em := lower(replace(replace(fn||'.'||ln,' ',''),'''','')) || i || '@example.com';
        ph := '+23480' || lpad((10000000 + i)::text, 8, '0');
        addr := CASE (i % 5) WHEN 0 THEN 'Ikeja, Lagos'
                             WHEN 1 THEN 'Lekki, Lagos'
                             WHEN 2 THEN 'V/I, Lagos'
                             WHEN 3 THEN 'Yaba, Lagos'
                             ELSE 'Garki, Abuja' END;
        INSERT INTO customer (first_name, last_name, phone, email, address)
        VALUES (fn, ln, ph, em, addr)
        RETURNING customer_id INTO cid;

        IF random() < 0.02 THEN                                    -- ~2% expired (realistic; generator skips them)
            expiry := current_date - (30 + (random()*400)::int);
        ELSE
            expiry := current_date + 120 + (random()*1400)::int;   -- valid through the whole demo window
        END IF;
        issue  := expiry - (5 * 365);
        INSERT INTO driver_licence (customer_id, licence_number, issue_date, expiry_date)
        VALUES (cid, 'NIG-'||lpad(cid::text,7,'0'), issue, expiry);
    END LOOP;
END$$;

-- Pick 20 cars for routine maintenance (next 30 days) ----------------------
DO $$
DECLARE r record; st timestamptz; en timestamptz;
BEGIN
    FOR r IN SELECT car_id FROM car WHERE car_id % 7 = 0 LIMIT 20 LOOP
        st := now() + ((random()*30)::int || ' days')::interval;
        en := st + ((2 + (random()*5)::int) || ' days')::interval;
        INSERT INTO maintenance (car_id, start_time, end_time, description, cost)
        VALUES (r.car_id, st, en,
                CASE (random()::int % 3) WHEN 0 THEN 'Oil change + filter'
                                         WHEN 1 THEN 'Brake pads replacement'
                                         ELSE 'Tyre rotation & alignment' END,
                15000 + (random()*60000)::int);
    END LOOP;
END$$;

-- Counts -------------------------------------------------------------------
SELECT 'branches' AS table_name, count(*) FROM branch
UNION ALL SELECT 'car_categories', count(*) FROM car_category
UNION ALL SELECT 'cars', count(*) FROM car
UNION ALL SELECT 'customers', count(*) FROM customer
UNION ALL SELECT 'licences', count(*) FROM driver_licence
UNION ALL SELECT 'maintenance', count(*) FROM maintenance;
