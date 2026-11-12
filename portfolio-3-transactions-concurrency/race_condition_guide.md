# Portfolio 3 — Race-Condition Walkthrough (two interactive `psql` sessions)

> Goal: show the **double-booking bug** with a plain check-then-insert, then **two fixes** —
> Fix 1 = the `EXCLUDE` constraint from P1 rejects the second insert;
> Fix 2 = `SELECT … FOR UPDATE` on the `car` row makes the second request wait and then see a clear "already booked" message.
>
> Run this in two terminals side-by-side. Open Terminal A and Terminal B, both connected to the same database:
> ```bash
> # Terminal A
> psql "host=/var/run/postgresql dbname=driveeasy user=driveeasy"
> # Terminal B
> psql "host=/var/run/postgresql dbname=driveeasy user=driveeasy"
> ```

## Setup (once, in Terminal A)
```sql
-- Create a "loose" table WITHOUT the EXCLUDE constraint, to reproduce the bug.
-- (Do NOT drop the real rental table — this is a separate scratch table.)
CREATE TABLE IF NOT EXISTS rental_loose (
    rental_id   bigserial PRIMARY KEY,
    car_id      bigint NOT NULL,
    customer_id bigint NOT NULL,
    pickup_time timestamptz NOT NULL,
    return_time timestamptz NOT NULL,
    CHECK (return_time > pickup_time)
);

-- Pick a car + window to fight over. Use dates relative to today.
SELECT 3 AS car_id,
       now() + '7 days'  AS pickup_time,
       now() + '9 days'  AS return_time;
```

---

## BUG — check-then-insert on a table WITHOUT the exclusion constraint

Two customers hit the same car & same window at the same time. Both `SELECT NOT EXISTS …` returns true before either has inserted. Both inserts succeed → DOUBLE BOOKING.

**Terminal A**
```sql
BEGIN;
SELECT NOT EXISTS (
    SELECT 1 FROM rental_loose
     WHERE car_id = 3
       AND tstzrange(pickup_time, return_time, '[)')
           && tstzrange(now() + '7 days', now() + '9 days', '[)')
) AS free;
-- free = t. Looks available. DO NOT commit yet — switch to Terminal B.
```

**Terminal B**
```sql
BEGIN;
SELECT NOT EXISTS (
    SELECT 1 FROM rental_loose
     WHERE car_id = 3
       AND tstzrange(pickup_time, return_time, '[)')
           && tstzrange(now() + '7 days', now() + '9 days', '[)')
) AS free;
-- free = t again, because Terminal A has not committed yet (READ COMMITTED)
INSERT INTO rental_loose (car_id, customer_id, pickup_time, return_time)
VALUES (3, 2, now() + '7 days', now() + '9 days');
COMMIT;
-- Insert succeeds.
```

**Terminal A (back)**
```sql
INSERT INTO rental_loose (car_id, customer_id, pickup_time, return_time)
VALUES (3, 1, now() + '7 days', now() + '9 days');
COMMIT;
-- Insert ALSO succeeds — DOUBLE BOOKING confirmed.
SELECT * FROM rental_loose WHERE car_id = 3 ORDER BY rental_id;
-- >>> screenshot: two rows for the same car & overlapping window
```

```sql
-- cleanup
DROP TABLE rental_loose;
```

---

## FIX 1 — the `EXCLUDE` constraint on the real `rental` table rejects it

The P1 schema already has `EXCLUDE USING gist (car_id WITH =, rental_range WITH &&)`. Two transactions can no longer both insert the same overlapping window: the second `INSERT` raises `exclusion_violation` at COMMIT time (or at INSERT time, depending on timing).

**Terminal A**
```sql
BEGIN;
SELECT book_car(
    p_car_id        := 4,
    p_customer_id   := 1,
    p_pickup_branch := 1,
    p_return_branch := 1,
    p_pickup_time   := now() + '7 days',
    p_return_time   := now() + '9 days'
) AS rental_id;
-- keep this transaction open; do NOT commit yet.
```

**Terminal B**
```sql
BEGIN;
SELECT book_car(
    p_car_id        := 4,
    p_customer_id   := 2,
    p_pickup_branch := 1,
    p_return_branch := 1,
    p_pickup_time   := now() + '7 days',
    p_return_time   := now() + '9 days'
) AS rental_id;
-- >>> EXPECTED: ERROR: conflicting key value violates exclusion constraint
--                  "excl_no_overlapping_rental"
--     (or the function raises 'car 4 already booked in [...)' from its up-front check)
ROLLBACK;
```

**Terminal A**
```sql
COMMIT;
SELECT * FROM v_recent_bookings;
-- >>> screenshot: only ONE booking for car 4 in this window
```

> Why this works: PostgreSQL's GiST exclusion check is *not* deferred to commit time by default — it fails the second INSERT immediately if a conflicting *uncommitted* row is already visible in the same transaction. If the planner defers (because of timing), the COMMIT itself fails.

---

## FIX 2 — `SELECT … FOR UPDATE` on the `car` row serialises access

Alternative (also valid for tables that cannot have a GiST exclusion): lock the car row. The second transaction BLOCKS on the row lock, then once Terminal A commits, the second transaction re-checks and sees the booking is already there.

**Terminal A**
```sql
BEGIN;
-- Lock the car row — Terminal B's identical SELECT will block here.
SELECT * FROM car WHERE car_id = 5 FOR UPDATE;
SELECT book_car(
    p_car_id        := 5,
    p_customer_id   := 1,
    p_pickup_branch := 1,
    p_return_branch := 1,
    p_pickup_time   := now() + '7 days',
    p_return_time   := now() + '9 days'
) AS rental_id;
-- keep open
```

**Terminal B**
```sql
BEGIN;
SELECT * FROM car WHERE car_id = 5 FOR UPDATE;
-- >>> this BLOCKS until Terminal A commits or rolls back.
--     Once Terminal A commits, B's lock is granted and B re-evaluates the
--     up-front check inside book_car() — which now sees Terminal A's row and
--     raises:  ERROR: car 5 already booked in ["...","...")
ROLLBACK;
```

**Terminal A**
```sql
COMMIT;
SELECT * FROM v_recent_bookings;
-- >>> screenshot: Terminal B was forced to wait, then got a clear message
```

> Why this works: `FOR UPDATE` is a row-level write lock; the second transaction waits for the first to release it (at COMMIT/ROLLBACK). By the time the second transaction proceeds, the new rental row is visible, so the `NOT EXISTS` check inside `book_car()` returns false and the function raises a clean business error instead of silently inserting a duplicate.

---

## What to screenshot
1. The BUG: two rows in `rental_loose` for the same car & overlapping window.
2. FIX 1: Terminal B raising `exclusion_violation` on `excl_no_overlapping_rental`.
3. FIX 2: Terminal B visibly blocking (then unblocking with a clear message after Terminal A commits).
4. `v_recent_bookings` after each fix showing only one booking.
