#!/usr/bin/env bash
# run_p1.sh — Portfolio 1 driver. Run from inside portfolio-1-database-design/.
set -euo pipefail
PSQL="psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U driveeasy -d driveeasy"

echo "==> [1/4] Drop & recreate schema (schema.sql)"
$PSQL -f schema.sql

echo "==> [2/4] Load base seed data (seed_data.sql)"
$PSQL -f seed_data.sql

echo "==> [3/4] Generate 52,000 rentals (bulk_generator.sql) — this takes about a minute"
$PSQL -f bulk_generator.sql

echo "==> [4/4] Run constraint tests — every block MUST FAIL (constraint_tests.sql)"
# constraint tests deliberately use ON_ERROR_STOP=0 inside the file
psql -h /var/run/postgresql -U driveeasy -d driveeasy -v ON_ERROR_STOP=0 -f constraint_tests.sql

echo
echo "==> Portfolio 1 done. Screenshot:"
echo "    • \\d+ rental  (shows the EXCLUDE constraint)"
echo "    • final counts (rentals/payments/damage_reports)"
echo "    • every constraint_tests.sql block failing with its SQLSTATE"
echo
echo "    git add portfolio-1-database-design/ && git commit -m 'P1: ER + 3NF + schema + 55k rentals + constraint tests'"
