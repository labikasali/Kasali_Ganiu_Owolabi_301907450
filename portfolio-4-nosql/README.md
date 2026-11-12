# Portfolio 4 — NoSQL & Advanced Data Models

**Demonstrates:** MongoDB document model with JSON-Schema validation, embedded checklists that vary by car category, time-series collection for GPS logs, aggregation pipeline (damage per category, distance per rental, repeat-damage cars), COLLSCAN → IXSCAN index demonstration, and a SQL-vs-NoSQL comparison.
**Study session:** CAP & BASE, document model, schema validation, embedding vs referencing, aggregation pipeline, time-series collections, indexing, SQL vs NoSQL suitability.

## Files
| File | Purpose |
|---|---|
| `setup_validation.js` | Drops + recreates both collections with `$jsonSchema` validators (strict/error) |
| `seed_inspections.js` | Generates 42,000 inspection docs (pickup+return), checklists differ by category |
| `seed_gps_logs.js` | Generates ~150,000 GPS trip-log docs (time-series, 5,000 rentals × 30 points) |
| `aggregations.js` | 3 pipelines: damage per category, distance per rental, repeat-damage cars + severity distribution |
| `indexes.js` | COLLSCAN → IXSCAN before/after on `vehicle_inspections` |
| `sql_vs_nosql.md` | Honest side-by-side comparison for DriveEasy Rentals |
| `run_p4.sh` | Driver |

## Run (Codespaces)
```bash
# assumes setup.sh has installed MongoDB 8
cd portfolio-4-nosql
bash run_p4.sh
```

## What to screenshot for evidence
1. `db.vehicle_inspections.countDocuments()` = 42,000 and `db.gps_trip_logs.countDocuments()` ≈ 150,000.
2. `db.runCommand({ listCollections: 1 })` showing the `$jsonSchema` validator on `vehicle_inspections`.
3. The four aggregation outputs from `aggregations.js`.
4. The `indexes.js` "BEFORE index (COLLSCAN, totalDocsExamined = N)" vs "AFTER index (IXSCAN, totalKeysExamined = small)" — paste the real numbers into the placeholder block at the bottom of that file.

## Git commit
```bash
git add portfolio-4-nosql/
git commit -m "P4: MongoDB inspections + GPS + aggregations + index demo"
```

## What it demonstrates
- A genuine document-model choice: **embed** the checklist and damage array in the inspection document (one read returns everything the inspection app needs), instead of spreading them across multiple SQL tables.
- Schema discipline in MongoDB is real — the `$jsonSchema` validator with `validationLevel: strict` and `validationAction: error` rejects malformed documents, so the "NoSQL = schema-less" misconception is corrected.
- Different checklists per car category are modelled as conditional fields in the schema, matching the case study.
- Time-series collection for GPS trip logs uses MongoDB's native `timeseries` option.
- Honest COLLSCAN → IXSCAN comparison; the numbers are placeholders until you run.
