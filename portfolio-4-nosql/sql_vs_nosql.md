# Portfolio 4 — SQL vs NoSQL Comparison

For DriveEasy Rentals, the relational PostgreSQL schema (Portfolio 1) and the MongoDB document model (this portfolio) coexist by design. Below is an honest side-by-side comparison against the same case study.

| Aspect | PostgreSQL (relational) | MongoDB (document) |
|---|---|---|
| **Data shape** | Flat, normalised, one row per rental / car / customer / inspection. 9 tables linked by FKs. | Nested documents. A `vehicle_inspection` document embeds the entire checklist and damage marks array in one read. |
| **Schema enforcement** | DDL: `CREATE TABLE` with CHECK, UNIQUE, EXCLUDE, FK. Schema is hard. | `validator: { $jsonSchema: ... }` at collection level. Fields can be added without migration; `validationLevel: strict` rejects non-conforming docs. |
| **Joins vs embedding** | Multi-table `JOIN` (e.g. rental → payment → damage_report). Need 3 round trips or one join plan. | Embed the checklist + damage marks array in one document → one read returns everything for that inspection. |
| **Transactions** | Full ACID. Cross-table `BEGIN/COMMIT/ROLLBACK` (Portfolio 3). | Single-document atomicity by default. Multi-document transactions exist but are heavier; not used here. |
| **Referential integrity** | Foreign keys enforced by the engine. | No FKs. Application must keep `rental_id` consistent. Denormalised `car_category` can drift. |
| **Overlap exclusion** | `EXCLUDE USING gist` (P1) — declarative, server-enforced. | Not expressible declaratively. Application must check-and-insert, or use unique compound indexes on `car_id + window`. |
| **Bulk generation** | PL/pgSQL loops + `generate_series` (P1 `bulk_generator.sql`). | JavaScript loops + `insertMany` (this portfolio's `seed_*.js`). |
| **Aggregation** | `SELECT … GROUP BY`. SQL is well-known to analysts. | `aggregate([{ $match }, { $group }, { $project }])` pipeline. Powerful but steeper learning curve. |
| **Index** | B-tree, GiST, partial, covering (`INCLUDE`). | B-tree on plain fields, compound, time-series-aware, geospatial (2dsphere) — not used here but available. |
| **Best at** | The transactional core: rentals, payments, deposits, ACID guarantees, exclusion of overlapping bookings, monthly partitioning + streaming replication (P5). | Auxiliary data that is read-with-parent: inspection checklists, GPS trip logs, photo links. Reads are one hop; writes are append-only. |
| **Worst at** | Schema changes that touch many tables; nested arrays of damage marks require a separate `damage_report` table + join. | Cross-collection consistency (rental ↔ inspection); declarative overlap exclusion; ad-hoc analytic SQL. |

## Suitability verdict for DriveEasy Rentals
- **Use PostgreSQL for the transactional core** — rentals, payments, deposits, customers, cars, exclusion constraints. ACID + declarative overlap exclusion + monthly partitioning + streaming replication are essential here.
- **Use MongoDB for inspection reports and GPS trip logs** — these are append-mostly, read-with-parent documents whose shape varies by car category. Embedding the checklist and damage array in one document matches how the mobile inspection app reads and writes them (one document = one inspection). Time-series collections are well suited to GPS logs.
- **Synchronisation**: each `vehicle_inspection.rental_id` references a `rental.rental_id` in PostgreSQL; the application enforces referential consistency by reading from PostgreSQL first. We accept eventual-consistency for inspection attachments (a missing attachment does not block a rental), so async sync is acceptable.

## CAP positioning
- The PostgreSQL core is a CP system in the partition-tolerant sense (PA/EC on the CAP triangle depending on configuration): writes go to the primary; the streaming replica is read-only (see Portfolio 5).
- MongoDB here is single-node (a CP-leaning deployment). For higher availability DriveEasy would deploy a 3-member replica set with `w:majority` writes — still CP. Eventual consistency on GPS logs (a few seconds lag) is acceptable for fleet analytics but not for billing.
