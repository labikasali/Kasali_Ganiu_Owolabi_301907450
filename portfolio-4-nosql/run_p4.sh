#!/usr/bin/env bash
# run_p4.sh — Portfolio 4 driver. Run from inside portfolio-4-nosql/.
set -euo pipefail

echo "==> [1/5] Create collections with JSON Schema validators"
mongosh --quiet --file setup_validation.js

echo "==> [2/5] Seed 42,000 vehicle_inspection documents (this takes ~30-60s)"
mongosh --quiet --file seed_inspections.js

echo "==> [3/5] Seed ~150,000 GPS trip-log documents (this takes ~30-60s)"
mongosh --quiet --file seed_gps_logs.js

echo "==> [4/5] Run aggregations (damage per category, distance per rental, repeat damage)"
mongosh --quiet --file aggregations.js

echo "==> [5/5] COLLSCAN → IXSCAN index demo (before vs after)"
mongosh --quiet --file indexes.js

echo
echo "==> Portfolio 4 done. Screenshot:"
echo "    • collection count after seeding (vehicle_inspections, gps_trip_logs)"
echo "    • db.runCommand({listCollections:1}) showing the validator on vehicle_inspections"
echo "    • the four aggregation outputs from aggregations.js"
echo "    • indexes.js: COLLSCAN stage + totalDocsExamined BEFORE,"
echo "      IXSCAN stage + totalKeysExamined + executionTimeMs AFTER"
echo
echo "    git add portfolio-4-nosql/ && git commit -m 'P4: MongoDB inspections + GPS + aggregations + index demo'"
