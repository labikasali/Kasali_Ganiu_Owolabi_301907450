# Portfolio 1 — Database Design & Modelling

**Demonstrates:** ER modelling, 3NF normalisation, keys (PK/FK/UNIQUE), CHECK constraints, an EXCLUDE constraint using `btree_gist`, two BEFORE-INSERT triggers, bulk data generation.
**Study session:** ER modelling + relational schema + normalisation + advanced constraints (PostgreSQL `tstzrange` / `btree_gist` / triggers).

## Files
| File | Purpose |
|---|---|
| `er_diagram.md` | Mermaid ER diagram for all 9 tables + constraint notes |
| `normalisation.md` | 1NF → 2NF → 3NF walkthrough with rationale |
| `schema.sql` | DDL: extensions, 9 tables, indexes, EXCLUDE, 3 triggers |
| `seed_data.sql` | 5 branches, 5 categories, 600 cars, 5,000 customers+licences, 20 maintenance rows |
| `bulk_generator.sql` | 52,000+ rentals across 2 years, seasonal weights, no overlaps |
| `constraint_tests.sql` | 11 tests that MUST FAIL with the documented SQLSTATE |
| `run_p1.sh` | Driver script |

## Run (Codespaces)
```bash
bash ../setup.sh                # only once — installs PG16 + MongoDB 8
cd portfolio-1-database-design
bash run_p1.sh
```

## What to screenshot for evidence
1. `psql \d+ rental` — shows the EXCLUDE constraint `excl_no_overlapping_rental` and CHECKs.
2. The final counts (rentals, payments, damage_reports) after `bulk_generator.sql`.
3. `\timing on` elapsed for `bulk_generator.sql`.
4. Every block in `constraint_tests.sql` printing its expected ERROR + SQLSTATE.
5. The Mermaid ER diagram rendered (GitHub renders it in the `.md` file).

## Git commit
```bash
git add portfolio-1-database-design/
git commit -m "P1: ER + 3NF + schema + 52k rentals + constraint tests"
```

## What it demonstrates
- Correct 3NF schema for the DriveEasy Rentals case study.
- Real-world advanced constraint: `EXCLUDE USING gist (car_id WITH =, rental_range WITH &&)` to forbid overlapping rentals of one car (impossible with UNIQUE alone).
- Two triggers that enforce cross-table/cross-row business rules (licence validity on pickup, no rental during maintenance).
- Bulk generator that produces realistic Nigerian plate numbers, names and ₦ prices, with seasonal peaks in December and at Easter/Sallah, while respecting all constraints.
