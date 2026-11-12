# Portfolio 1 — ER Diagram (Mermaid)

> DriveEasy Rentals — entity-relationship diagram for 9 tables.
> Render this file in any Mermaid viewer (GitHub renders it natively in `.md`).

```mermaid
erDiagram
    BRANCH ||--o{ CAR : "home_branch"
    BRANCH ||--o{ RENTAL : "pickup_branch"
    BRANCH ||--o{ RENTAL : "return_branch"
    CAR_CATEGORY ||--o{ CAR : "category"
    CAR ||--o{ RENTAL : "car"
    CAR ||--o{ MAINTENANCE : "car"
    CUSTOMER ||--|| DRIVER_LICENCE : "holds"
    CUSTOMER ||--o{ RENTAL : "customer"
    RENTAL ||--o{ PAYMENT : "payment"
    RENTAL ||--o{ DAMAGE_REPORT : "report"

    BRANCH {
        bigint   branch_id PK
        text     code          "IKE, LKK, VTC, MMA, ABJ"
        text     name
        text     city           "Lagos / Abuja"
        text     address
        text     phone
    }
    CAR_CATEGORY {
        bigint   category_id PK
        text     name            "Economy, SUV, Luxury, Mini-bus, Van"
        numeric  daily_rate      "₦ per day, > 0"
        numeric  deposit         "₦ security deposit, > 0"
    }
    CAR {
        bigint   car_id PK
        text     plate_number    "Unique, e.g. LAG-482AB"
        bigint   category_id FK
        bigint   home_branch_id FK
        integer  mileage          "current odometer, km"
        text     status           "available | rented | maintenance"
    }
    CUSTOMER {
        bigint   customer_id PK
        text     first_name
        text     last_name
        text     phone
        text     email            "Unique"
        text     address
    }
    DRIVER_LICENCE {
        bigint   licence_id PK
        bigint   customer_id FK   "Unique (1:1)"
        text     licence_number   "Unique"
        date     issue_date
        date     expiry_date      "must be >= pickup date"
    }
    RENTAL {
        bigint   rental_id PK
        bigint   car_id FK
        bigint   customer_id FK
        bigint   pickup_branch_id FK
        bigint   return_branch_id FK
        timestamptz pickup_time
        timestamptz return_time   "must be > pickup_time"
        integer  start_mileage
        integer  end_mileage       "must be >= start_mileage"
        tstzrange rental_range    "EXCLUDE gist(car_id=, rental_range &&)"
        text     status            "booked | active | returned | cancelled"
    }
    PAYMENT {
        bigint   payment_id PK
        bigint   rental_id FK
        numeric  amount            "₦, > 0"
        text     payment_type      "deposit | rental | late_fee | mileage_fee | damage_fee | refund"
        timestamptz paid_at
        text     channel           "card | transfer | cash"
    }
    DAMAGE_REPORT {
        bigint   damage_id PK
        bigint   rental_id FK
        text     description
        numeric  estimated_cost    "₦"
        timestamptz reported_at
        text     severity           "minor | moderate | major"
    }
    MAINTENANCE {
        bigint   maintenance_id PK
        bigint   car_id FK
        timestamptz start_time
        timestamptz end_time         "must be > start_time"
        text     description
        numeric  cost                "₦"
    }
```

## Constraints encoded in the ER / schema

1. **EXCLUSION (no overlapping rentals per car)** — on `rental.rental_range` (a `tstzrange`) using `btree_gist`: `(car_id WITH =, rental_range WITH &&)`.
2. **Trigger: a car in maintenance can't be rented in that period** — `trg_no_rental_during_maintenance` blocks `INSERT` on `rental` whose range overlaps an existing `maintenance` row for the same car.
3. **Trigger: driver's licence valid on pickup date** — `trg_licence_valid_on_pickup` raises if `driver_licence.expiry_date < rental.pickup_time::date`.
4. **CHECK: `return_time > pickup_time`** and **`end_mileage >= start_mileage`**.
5. **CHECK: `daily_rate > 0`, `deposit > 0`, `payment.amount > 0`**.
6. **UNIQUE:** `car.plate_number`, `customer.email`, `driver_licence.licence_number`, `driver_licence.customer_id` (1:1).
7. **FK** integrity on all `*_id` columns; `ON DELETE RESTRICT` on cars/customers (cannot delete while rentals exist).
