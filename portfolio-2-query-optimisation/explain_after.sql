-- =============================================================================
-- Portfolio 2 — explain_after.sql
-- Same 7 EXPLAIN ANALYZE statements, but AFTER indexes.sql has run.
--   psql ... -f explain_after.sql  > explain_after.txt 2>&1
-- =============================================================================

\echo '================ Q1 EXPLAIN ANALYZE (AFTER INDEXES) ================'
EXPLAIN ANALYZE
WITH params AS (
    SELECT 1::bigint AS branch_id,
           date_trunc('day', now()) AS p_start,
           date_trunc('day', now()) + '3 days'::interval AS p_end
)
SELECT c.car_id, c.plate_number, cc.name AS category, c.mileage
  FROM car c
  JOIN car_category cc ON cc.category_id = c.category_id
  JOIN params p ON c.home_branch_id = p.branch_id
 WHERE c.status <> 'maintenance'
   AND NOT EXISTS (
        SELECT 1 FROM rental r
         WHERE r.car_id = c.car_id
           AND r.rental_range && tstzrange(p.p_start, p.p_end, '[)'))
 ORDER BY cc.name, c.plate_number
 LIMIT 25;

\echo
\echo '================ Q2 EXPLAIN ANALYZE (AFTER INDEXES) ================'
EXPLAIN ANALYZE
SELECT b.code AS branch,
       to_char(date_trunc('month', r.pickup_time), 'YYYY-MM') AS ym,
       sum(p.amount) FILTER (WHERE p.payment_type IN ('rental','late_fee','mileage_fee','damage_fee')) AS revenue_ngn,
       count(DISTINCT r.rental_id) AS rentals
  FROM rental r
  JOIN payment p ON p.rental_id = r.rental_id
  JOIN branch  b ON b.branch_id = r.pickup_branch_id
 WHERE r.pickup_time >= date_trunc('month', now()) - '12 months'::interval
 GROUP BY b.code, ym
 ORDER BY ym DESC, b.code;

\echo
\echo '================ Q3 EXPLAIN ANALYZE (AFTER INDEXES) ================'
EXPLAIN ANALYZE
WITH win AS (
    SELECT date_trunc('day', now()) - '30 days'::interval AS s,
           date_trunc('day', now())                      AS e
),
cat_days AS (
    SELECT cc.category_id, cc.name, count(*) * 30 AS available_days
      FROM car c JOIN car_category cc ON cc.category_id = c.category_id
     WHERE c.status <> 'maintenance'
     GROUP BY cc.category_id, cc.name
),
rented AS (
    SELECT c.category_id,
           EXTRACT(EPOCH FROM sum(LEAST(r.return_time, (SELECT e FROM win)) - GREATEST(r.pickup_time, (SELECT s FROM win)))) / 86400.0 AS rented_days
      FROM rental r JOIN car c ON c.car_id = r.car_id
     WHERE r.rental_range && tstzrange((SELECT s FROM win), (SELECT e FROM win), '[)')
     GROUP BY c.category_id
)
SELECT cd.name AS category,
       round(COALESCE(r.rented_days,0)::numeric / cd.available_days * 100, 2) AS utilisation_pct
  FROM cat_days cd LEFT JOIN rented r ON r.category_id = cd.category_id
 ORDER BY utilisation_pct DESC;

\echo
\echo '================ Q4 EXPLAIN ANALYZE (AFTER INDEXES) ================'
EXPLAIN ANALYZE
SELECT r.rental_id, c.plate_number, cust.last_name,
       r.pickup_time, r.return_time,
       extract(epoch FROM (now() - r.return_time))/3600 AS hours_overdue
  FROM rental r
  JOIN car c      ON c.car_id      = r.car_id
  JOIN customer cust ON cust.customer_id = r.customer_id
 WHERE r.status = 'booked' AND r.return_time < now()
 ORDER BY hours_overdue DESC
 LIMIT 25;

\echo
\echo '================ Q5 EXPLAIN ANALYZE (AFTER INDEXES) ================'
EXPLAIN ANALYZE
SELECT cu.customer_id, cu.first_name, cu.last_name,
       count(d.damage_id) AS damage_count,
       sum(d.estimated_cost) AS total_damage_ngn
  FROM customer cu
  JOIN rental r      ON r.customer_id = cu.customer_id
  JOIN damage_report d ON d.rental_id = r.rental_id
 GROUP BY cu.customer_id, cu.first_name, cu.last_name
 HAVING count(d.damage_id) >= 1
 ORDER BY damage_count DESC, total_damage_ngn DESC
 LIMIT 25;

\echo
\echo '================ Q6 EXPLAIN ANALYZE (AFTER INDEXES) ================'
EXPLAIN ANALYZE
SELECT pb.code AS pickup_branch, rb.code AS return_branch,
       count(*) AS trips,
       sum(p.amount) FILTER (WHERE p.payment_type='rental') AS revenue_ngn
  FROM rental r
  JOIN branch pb ON pb.branch_id = r.pickup_branch_id
  JOIN branch rb ON rb.branch_id = r.return_branch_id
  JOIN payment p ON p.rental_id = r.rental_id
 WHERE r.pickup_branch_id <> r.return_branch_id
   AND r.pickup_time >= now() - '6 months'::interval
 GROUP BY pb.code, rb.code
 ORDER BY trips DESC
 LIMIT 15;

\echo
\echo '================ Q7 EXPLAIN ANALYZE (AFTER INDEXES) ================'
EXPLAIN ANALYZE
SELECT cc.name AS category,
       round((EXTRACT(EPOCH FROM avg(r.return_time - r.pickup_time))/86400)::numeric, 2) AS avg_length_days,
       round(avg(p.revenue), 2)                    AS avg_revenue_ngn,
       count(*)                                     AS rentals
  FROM rental r
  JOIN car c           ON c.car_id      = r.car_id
  JOIN car_category cc ON cc.category_id = c.category_id
  JOIN LATERAL (
        SELECT sum(amount) AS revenue FROM payment
         WHERE rental_id = r.rental_id
           AND payment_type IN ('rental','late_fee','mileage_fee','damage_fee')
  ) p ON true
 WHERE r.pickup_time >= now() - '6 months'::interval
   AND r.status = 'returned'
 GROUP BY cc.name
 ORDER BY avg_revenue_ngn DESC;
