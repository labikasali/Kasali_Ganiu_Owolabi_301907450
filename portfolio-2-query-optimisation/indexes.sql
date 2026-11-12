-- =============================================================================
-- Portfolio 2 — indexes.sql
-- Optimisation indexes chosen for the 7 queries in queries.sql.
-- Run AFTER explain_before.sql, BEFORE explain_after.sql.
--   psql ... -f indexes.sql
-- =============================================================================

\echo '==> Adding optimisation indexes (idempotent)'

-- Q1: cars available at a branch for a date window.
--     filter: car.home_branch_id, car.status
--     subquery: rental.rental_range gist + rental.car_id
CREATE INDEX IF NOT EXISTS idx_car_branch_status
    ON car (home_branch_id, status);

-- Q2: revenue per branch per month — group on pickup_branch_id, filter on pickup_time
CREATE INDEX IF NOT EXISTS idx_rental_pickup_br_time
    ON rental (pickup_branch_id, pickup_time);

-- Q3 / Q4 / Q6 / Q7: all filter on pickup_time or rental_range
--     the existing idx_rental_range_gist already helps Q3, but add a partial index on status='booked'
CREATE INDEX IF NOT EXISTS idx_rental_overdue
    ON rental (return_time)
    WHERE status = 'booked';

CREATE INDEX IF NOT EXISTS idx_rental_pickup_time_recent
    ON rental (pickup_time)
    WHERE status = 'returned';

-- Q5: damage history — join rental→damage_report grouped by customer
CREATE INDEX IF NOT EXISTS idx_damage_rental_severity
    ON damage_report (rental_id);

-- Q2: payments grouped by payment_type — composite covering index
CREATE INDEX IF NOT EXISTS idx_payment_rental_type_amount
    ON payment (rental_id, payment_type)
    INCLUDE (amount);

-- Q6: one-way routes — already covered by idx_rental_pickup_br_time
-- Add a partial index for one-way rentals
CREATE INDEX IF NOT EXISTS idx_rental_one_way
    ON rental (pickup_branch_id, return_branch_id, pickup_time)
    WHERE pickup_branch_id <> return_branch_id;

-- ANALYZE so the planner sees the new stats
ANALYZE car;
ANALYZE rental;
ANALYZE payment;
ANALYZE damage_report;
ANALYZE customer;

\echo '==> Indexes created. Run explain_after.sql next.'
