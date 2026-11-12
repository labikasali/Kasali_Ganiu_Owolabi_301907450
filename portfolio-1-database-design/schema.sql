-- =============================================================================
-- Portfolio 1 — schema.sql
-- DriveEasy Rentals — DDL for 9 tables + extensions + triggers + exclusion
-- Run:  psql "host=/var/run/postgresql dbname=driveeasy user=driveeasy" -f schema.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- Extensions --------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- needed for EXCLUDE on (bigint, tstzrange)
CREATE EXTENSION IF NOT EXISTS pgcrypto;      -- gen_random_uuid() / convenience

DROP TABLE IF EXISTS damage_report  CASCADE;
DROP TABLE IF EXISTS payment        CASCADE;
DROP TABLE IF EXISTS maintenance    CASCADE;
DROP TABLE IF EXISTS rental         CASCADE;
DROP TABLE IF EXISTS driver_licence CASCADE;
DROP TABLE IF EXISTS customer       CASCADE;
DROP TABLE IF EXISTS car            CASCADE;
DROP TABLE IF EXISTS car_category   CASCADE;
DROP TABLE IF EXISTS branch         CASCADE;

-- 1. branch ----------------------------------------------------------------
CREATE TABLE branch (
    branch_id  bigserial PRIMARY KEY,
    code        text        NOT NULL UNIQUE,            -- IKE, LKK, VTC, MMA, ABJ
    name        text        NOT NULL,
    city        text        NOT NULL CHECK (city IN ('Lagos','Abuja')),
    address     text        NOT NULL,
    phone       text
);

-- 2. car_category ----------------------------------------------------------
CREATE TABLE car_category (
    category_id bigserial PRIMARY KEY,
    name        text        NOT NULL UNIQUE,            -- Economy, SUV, Luxury, Mini-bus, Van
    daily_rate  numeric(12,2) NOT NULL CHECK (daily_rate  > 0),   -- ₦
    deposit     numeric(12,2) NOT NULL CHECK (deposit     > 0)    -- ₦
);

-- 3. car -------------------------------------------------------------------
CREATE TABLE car (
    car_id        bigserial PRIMARY KEY,
    plate_number  text        NOT NULL UNIQUE,           -- e.g. LAG-482AB
    category_id   bigint      NOT NULL REFERENCES car_category(category_id),
    home_branch_id bigint     NOT NULL REFERENCES branch(branch_id),
    mileage       integer     NOT NULL DEFAULT 0 CHECK (mileage >= 0),
    status        text        NOT NULL DEFAULT 'available'
                  CHECK (status IN ('available','rented','maintenance'))
);
CREATE INDEX idx_car_category   ON car(category_id);
CREATE INDEX idx_car_homebranch ON car(home_branch_id);
CREATE INDEX idx_car_status     ON car(status);

-- 4. customer --------------------------------------------------------------
CREATE TABLE customer (
    customer_id bigserial PRIMARY KEY,
    first_name  text NOT NULL,
    last_name   text NOT NULL,
    phone       text NOT NULL,
    email       text NOT NULL UNIQUE,
    address     text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- 5. driver_licence (1:1 with customer) -----------------------------------
CREATE TABLE driver_licence (
    licence_id     bigserial PRIMARY KEY,
    customer_id    bigint NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE,
    licence_number text   NOT NULL UNIQUE,
    issue_date     date   NOT NULL,
    expiry_date    date   NOT NULL,
    CONSTRAINT chk_licence_dates CHECK (expiry_date > issue_date)
);

-- 6. rental ---------------------------------------------------------------
CREATE TABLE rental (
    rental_id        bigserial PRIMARY KEY,
    car_id           bigint        NOT NULL REFERENCES car(car_id) ON DELETE RESTRICT,
    customer_id      bigint        NOT NULL REFERENCES customer(customer_id),
    pickup_branch_id bigint        NOT NULL REFERENCES branch(branch_id),
    return_branch_id bigint        NOT NULL REFERENCES branch(branch_id),
    pickup_time      timestamptz   NOT NULL,
    return_time      timestamptz   NOT NULL,
    start_mileage    integer       NOT NULL CHECK (start_mileage >= 0),
    end_mileage      integer       NOT NULL CHECK (end_mileage   >= 0),
    status           text          NOT NULL DEFAULT 'booked'
                       CHECK (status IN ('booked','active','returned','cancelled')),
    rental_range     tstzrange,                          -- populated by trigger
    CONSTRAINT chk_return_after_pickup   CHECK (return_time >  pickup_time),
    CONSTRAINT chk_mileage_monotonic     CHECK (end_mileage >= start_mileage),
    -- No two rentals of the SAME car may overlap in time:
    CONSTRAINT excl_no_overlapping_rental
        EXCLUDE USING gist (car_id WITH =, rental_range WITH &&)
);
CREATE INDEX idx_rental_car          ON rental(car_id);
CREATE INDEX idx_rental_customer     ON rental(customer_id);
CREATE INDEX idx_rental_pickup_br    ON rental(pickup_branch_id);
CREATE INDEX idx_rental_return_br    ON rental(return_branch_id);
CREATE INDEX idx_rental_pickup_time  ON rental(pickup_time);
CREATE INDEX idx_rental_range_gist   ON rental USING gist (rental_range);

-- 7. payment --------------------------------------------------------------
CREATE TABLE payment (
    payment_id   bigserial PRIMARY KEY,
    rental_id    bigint        NOT NULL REFERENCES rental(rental_id) ON DELETE CASCADE,
    amount       numeric(12,2) NOT NULL CHECK (amount > 0),   -- ₦
    payment_type text          NOT NULL CHECK (payment_type IN
                    ('deposit','rental','late_fee','mileage_fee','damage_fee','refund')),
    paid_at      timestamptz   NOT NULL DEFAULT now(),
    channel      text          NOT NULL DEFAULT 'card'
                  CHECK (channel IN ('card','transfer','cash'))
);
CREATE INDEX idx_payment_rental  ON payment(rental_id);
CREATE INDEX idx_payment_paid_at ON payment(paid_at);

-- 8. damage_report --------------------------------------------------------
CREATE TABLE damage_report (
    damage_id      bigserial PRIMARY KEY,
    rental_id      bigint        NOT NULL REFERENCES rental(rental_id) ON DELETE CASCADE,
    description    text          NOT NULL,
    estimated_cost numeric(12,2) NOT NULL DEFAULT 0 CHECK (estimated_cost >= 0),
    reported_at    timestamptz   NOT NULL DEFAULT now(),
    severity       text          NOT NULL DEFAULT 'minor'
                   CHECK (severity IN ('minor','moderate','major'))
);
CREATE INDEX idx_damage_rental ON damage_report(rental_id);

-- 9. maintenance ----------------------------------------------------------
CREATE TABLE maintenance (
    maintenance_id bigserial PRIMARY KEY,
    car_id        bigint        NOT NULL REFERENCES car(car_id) ON DELETE RESTRICT,
    start_time    timestamptz   NOT NULL,
    end_time      timestamptz   NOT NULL,
    description   text          NOT NULL,
    cost          numeric(12,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
    CONSTRAINT chk_maint_end_after_start CHECK (end_time > start_time)
);
CREATE INDEX idx_maint_car      ON maintenance(car_id);
CREATE INDEX idx_maint_range    ON maintenance USING gist
    (car_id, tstzrange(start_time, end_time)) ;

-- ===========================================================================
-- TRIGGERS
-- ===========================================================================

-- (a) Auto-fill rental_range from pickup/return times
CREATE OR REPLACE FUNCTION fn_set_rental_range() RETURNS trigger AS $$
BEGIN
    NEW.rental_range := tstzrange(NEW.pickup_time, NEW.return_time, '[)');
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_rental_range
BEFORE INSERT OR UPDATE OF pickup_time, return_time ON rental
FOR EACH ROW EXECUTE FUNCTION fn_set_rental_range();

-- (b) Reject a rental that overlaps a maintenance window for the same car
CREATE OR REPLACE FUNCTION fn_no_rental_during_maintenance() RETURNS trigger AS $$
DECLARE m maintenance%ROWTYPE;
BEGIN
    SELECT * INTO m FROM maintenance
     WHERE car_id = NEW.car_id
       AND tstzrange(start_time, end_time, '[)') && NEW.rental_range
     LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION
            'Car % is in maintenance %..% — cannot rent in that period',
            NEW.car_id, m.start_time, m.end_time
            USING ERRCODE = 'exclusion_violation';
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_no_rental_during_maintenance
BEFORE INSERT OR UPDATE OF rental_range, car_id ON rental
FOR EACH ROW EXECUTE FUNCTION fn_no_rental_during_maintenance();

-- (c) Reject a rental if the customer's licence has expired on pickup date
CREATE OR REPLACE FUNCTION fn_licence_valid_on_pickup() RETURNS trigger AS $$
DECLARE dl driver_licence%ROWTYPE;
BEGIN
    SELECT * INTO dl FROM driver_licence WHERE customer_id = NEW.customer_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer % has no driver_licence on file', NEW.customer_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF dl.expiry_date < NEW.pickup_time::date THEN
        RAISE EXCEPTION
            'Customer % driver''s licence expired % — before pickup %',
            NEW.customer_id, dl.expiry_date, NEW.pickup_time::date
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_licence_valid_on_pickup
BEFORE INSERT OR UPDATE OF pickup_time, customer_id ON rental
FOR EACH ROW EXECUTE FUNCTION fn_licence_valid_on_pickup();

-- (d) Keep car.status roughly in sync (best-effort) -----------------------
CREATE OR REPLACE FUNCTION fn_sync_car_status() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE car SET status = 'rented' WHERE car_id = NEW.car_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.status = 'returned' AND OLD.status <> 'returned' THEN
        UPDATE car SET status = 'available',
                       mileage = GREATEST(mileage, NEW.end_mileage)
         WHERE car_id = NEW.car_id;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_car_status
AFTER INSERT OR UPDATE OF status ON rental
FOR EACH ROW EXECUTE FUNCTION fn_sync_car_status();

-- ===========================================================================
-- Sanity check
-- ===========================================================================
\d+ rental
