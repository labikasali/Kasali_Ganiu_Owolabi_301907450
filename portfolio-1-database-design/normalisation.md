# Portfolio 1 — Normalisation (1NF → 2NF → 3NF) Notes

## Case study data items (un-normalised, as collected from DriveEasy Rentals operations)

A single flat spreadsheet captured: rental reference, customer name, customer phone, customer email, customer address, driver's licence number, licence expiry, car plate number, car category, car daily rate, car deposit, home branch, pickup branch, pickup time, return branch, return time, start mileage, end mileage, total mileage, daily rate applied, days rented, deposit paid, late fee, extra-mileage fee, damage description, damage cost, maintenance description, maintenance start, maintenance end, maintenance cost.

This flat sheet has many problems: repeated customer info on every rental, repeated car info on every rental, multiple damage items crammed into one cell, multiple maintenance items in one cell, derived columns (`total_mileage = end - start`, `days_rented`), and update anomalies (changing a daily rate would update many rows inconsistently).

## 1NF — atomic values, no repeating groups
Split the multi-valued `damage` and `maintenance` columns into their own rows so each cell holds one value:
- `damage_report(rental_id, seq, description, cost)`
- `maintenance(car_id, seq, start_time, end_time, cost, description)`

Pick a primary key for every table (`rental_id`, `car_id+seq`, etc.). Remove derived columns (`total_mileage`, `days_rented`) — they are computed from base columns.

## 2NF — remove partial dependencies (only meaningful on composite keys)
After 1NF, `damage_report` had a composite key `(rental_id, seq)`. Every non-key attribute (`description`, `cost`) depends on the whole key, so 2NF is satisfied. The rental row's `daily_rate`, `deposit`, `home_branch` depend only on `car_id` (a partial dependency on the rental's key), so we extract them into `car` (and `car_category`), leaving only the rental-specific facts on the rental row.

## 3NF — remove transitive dependencies
On the rental row, `car_category_name` and `daily_rate` depend on `car_id`, and `daily_rate` then transitively depends on `car_id → category_id → daily_rate`. We split `car` into:
- `car(car_id, plate_number, category_id, home_branch_id, mileage, status)` and
- `car_category(category_id, name, daily_rate, deposit)`.

So `daily_rate` lives only on `car_category`, never on `car` or `rental`. Likewise branch info lives only in `branch`, customer info only in `customer`, licence info only in `driver_licence` (1:1 with customer), payment facts in `payment`, damage facts in `damage_report`.

## Final 3NF relational schema (9 tables)

| Table | PK | Notable columns / constraints |
|---|---|---|
| `branch` | `branch_id` | `code UNIQUE`, `name`, `city`, `address`, `phone` |
| `car_category` | `category_id` | `name UNIQUE`, `daily_rate > 0`, `deposit > 0` |
| `car` | `car_id` | `plate_number UNIQUE`, `category_id FK`, `home_branch_id FK`, `mileage >= 0`, `status IN (available, rented, maintenance)` |
| `customer` | `customer_id` | `email UNIQUE`, `first_name`, `last_name`, `phone`, `address` |
| `driver_licence` | `licence_id` | `customer_id UNIQUE FK` (1:1), `licence_number UNIQUE`, `expiry_date > issue_date` |
| `rental` | `rental_id` | `car_id FK`, `customer_id FK`, `pickup_branch_id FK`, `return_branch_id FK`, `pickup_time`, `return_time` (CHECK `return_time > pickup_time`), `start_mileage`, `end_mileage` (CHECK `end_mileage >= start_mileage`), `rental_range tstzrange` (EXCLUDE using `btree_gist`), `status` |
| `payment` | `payment_id` | `rental_id FK`, `amount > 0`, `payment_type`, `paid_at`, `channel` |
| `damage_report` | `damage_id` | `rental_id FK`, `description`, `estimated_cost`, `reported_at`, `severity` |
| `maintenance` | `maintenance_id` | `car_id FK`, `start_time`, `end_time` (CHECK `end_time > start_time`), `description`, `cost` |

## Why each constraint
- **EXCLUDE gist (car_id = , rental_range &&)** — the only correct way to forbid two overlapping rentals of the same car; a UNIQUE index cannot express "ranges must not overlap". Requires the `btree_gist` extension because the equality is on a `bigint` column.
- **Trigger `trg_no_rental_during_maintenance`** — same overlap idea but cross-table (rental vs maintenance). Could also be enforced with a second exclusion constraint if maintenance were modelled as a range on the car; we use a trigger because maintenance rows are rarer and the cost of a trigger is acceptable.
- **Trigger `trg_licence_valid_on_pickup`** — business rule from the case study: a customer whose licence has expired cannot legally pick up a car. Enforced at INSERT/UPDATE on `rental`.
- **CHECK `return_time > pickup_time`** — a rental must last a positive interval.
- **CHECK `end_mileage >= start_mileage`** — odometer cannot go backwards.
- **CHECK `amount > 0`, `daily_rate > 0`, `deposit > 0`** — payments and prices are strictly positive.
- **UNIQUE on `driver_licence.customer_id`** — a customer has at most one Nigerian driver's licence recorded.

## Design choices worth noting
- `rental_range` is generated by a trigger (`trg_set_rental_range`) from `pickup_time` / `return_time` so application code never has to compute a range literal.
- `car.status` is denormalised for fast filtering; kept consistent by triggers when a rental transitions between `booked`, `active`, `returned`, and when maintenance starts/ends.
- Branches are referenced three times from `rental` (pickup, return, and indirectly via `car.home_branch_id`). Three FK columns is normal in 3NF — the alternative (a `branch_role` table) would over-normalise a stable relationship.
