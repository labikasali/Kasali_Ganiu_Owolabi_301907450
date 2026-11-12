-- =============================================================================
-- Portfolio 5 — partition_setup.sql
-- Demonstrates DECLARATIVE PARTITIONING of `rental` by RANGE on pickup_time,
-- with one partition per month. Then a quick test: insert a rental and verify
-- PostgreSQL routes it to the correct month partition.
--
-- Run AFTER P1 (so you already have a rental table) — this file works by
-- creating a NEW partitioned table `rental_p` (sibling), copying data in, and
-- testing routing. (It does NOT touch your live rental table.)
--
--   psql ... -f partition_setup.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- 1. Drop & recreate a partitioned parent table ----------------------------
-- NOTE: PostgreSQL does NOT allow EXCLUDE constraints on a PARTITIONED parent
-- table (they must be added per-partition). For this demo we keep the
-- rental_range column + CHECK constraints on the parent, and add the EXCLUDE
-- to each monthly partition inside the DO loop below.
DROP TABLE IF EXISTS rental_p CASCADE;

CREATE TABLE rental_p (
    rental_id        bigserial,
    car_id           bigint        NOT NULL,
    customer_id      bigint        NOT NULL,
    pickup_branch_id bigint        NOT NULL,
    return_branch_id bigint        NOT NULL,
    pickup_time      timestamptz   NOT NULL,
    return_time      timestamptz   NOT NULL,
    start_mileage    integer       NOT NULL,
    end_mileage      integer       NOT NULL,
    status           text          NOT NULL DEFAULT 'booked'
                       CHECK (status IN ('booked','active','returned','cancelled')),
    rental_range     tstzrange,
    CONSTRAINT rp_chk_return_after_pickup CHECK (return_time > pickup_time),
    CONSTRAINT rp_chk_mileage_monotonic   CHECK (end_mileage >= start_mileage)
) PARTITION BY RANGE (pickup_time);

-- 2. Create a partition per month from 12 months ago → 6 months ahead -------
-- Use a DO block so we can loop on dates (relative to today, never expires).
-- A per-partition EXCLUDE constraint is added so the no-overlap rule still holds.
DO $$
DECLARE
    d     timestamptz := date_trunc('month', now()) - '12 months'::interval;
    end_d timestamptz := date_trunc('month', now()) + '7 months'::interval;
    name  text;
BEGIN
    WHILE d < end_d LOOP
        name := 'rental_p_' || to_char(d, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF rental_p FOR VALUES FROM (%L) TO (%L)',
            name, d, d + '1 month'::interval
        );
        -- per-partition exclusion constraint (GiST + btree_gist)
        EXECUTE format(
            'ALTER TABLE %I ADD CONSTRAINT %I EXCLUDE USING gist (car_id WITH =, rental_range WITH &&)',
            name, name || '_excl_no_overlap'
        );
        RAISE NOTICE 'Created partition %  (with EXCLUDE constraint)', name;
        d := d + '1 month'::interval;
    END LOOP;
END$$;

-- DEFAULT partition catches anything outside the monthly range (must stay empty)
CREATE TABLE rental_p_default PARTITION OF rental_p DEFAULT;

-- 3. Same trigger to populate rental_range (copy of P1's trigger) ----------
CREATE OR REPLACE FUNCTION fn_set_rental_range_p() RETURNS trigger AS $$
BEGIN
    NEW.rental_range := tstzrange(NEW.pickup_time, NEW.return_time, '[)');
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_rental_range_p
BEFORE INSERT OR UPDATE OF pickup_time, return_time ON rental_p
FOR EACH ROW EXECUTE FUNCTION fn_set_rental_range_p();

-- 4. Copy a slice of rentals into the partitioned table (last 12 months) ----
INSERT INTO rental_p (rental_id, car_id, customer_id, pickup_branch_id, return_branch_id,
                      pickup_time, return_time, start_mileage, end_mileage, status)
SELECT rental_id, car_id, customer_id, pickup_branch_id, return_branch_id,
       pickup_time, return_time, start_mileage, end_mileage, status
  FROM rental
 WHERE pickup_time >= date_trunc('month', now()) - '12 months'::interval;

-- 5. Show partition sizes --------------------------------------------------
SELECT
    c.relname                          AS partition,
    pg_size_pretty(pg_relation_size(c.oid)) AS size,
    pg_get_expr(c.relpartbound, c.oid)  AS bound
  FROM pg_inherits i
  JOIN pg_class c ON c.oid = i.inhrelid
 WHERE i.inhparent = 'rental_p'::regclass
 ORDER BY c.relname;

-- 6. Verify routing: insert a rental for "next month" and confirm it lands
--    in the right partition -----------------------------------------------
DO $$
DECLARE pt timestamptz := date_trunc('month', now()) + '1 month'::interval + '5 days'::interval;
        rt timestamptz := pt + '3 days'::interval;
        rid bigint;
BEGIN
    INSERT INTO rental_p (car_id, customer_id, pickup_branch_id, return_branch_id,
                          pickup_time, return_time, start_mileage, end_mileage, status)
    VALUES (1, 1, 1, 1, pt, rt, 0, 100, 'booked')
    RETURNING rental_id INTO rid;
    RAISE NOTICE 'Inserted rental_id=% into rental_p with pickup_time=%', rid, pt;
END$$;

ANALYZE rental_p;
ANALYZE rental;

-- Real row count per partition (counted, not estimated)
SELECT tableoid::regclass AS partition, count(*) AS rows
  FROM rental_p GROUP BY 1 ORDER BY 1;
SELECT count(*) AS rows_in_default_partition_must_be_0 FROM rental_p_default;

-- 7. EXPLAIN: show Partition pruning on a date-restricted query ------------
EXPLAIN (COSTS OFF)
SELECT count(*) FROM rental_p
 WHERE pickup_time >= now() - '1 month'::interval;
\echo '>>> screenshot: only the relevant partitions are scanned (Partition pruning).'

-- 8. One-month query: partitioned table vs the ordinary rental table (real timings) ---
\echo '--- UNPARTITIONED rental, last month ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT count(*) FROM rental WHERE pickup_time >= now() - '1 month'::interval;
\echo '--- PARTITIONED rental_p, last month ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) SELECT count(*) FROM rental_p WHERE pickup_time >= now() - '1 month'::interval;

-- 8b. EXPLAIN ANALYZE: scans only the touched partitions ----------------------
EXPLAIN ANALYZE
SELECT count(*) FROM rental_p
 WHERE pickup_time >= now() - '2 months'::interval;
\echo '>>> screenshot: Subplans Removed = N (pruned partitions).'

\d+ rental_p
