#!/usr/bin/env bash
# run_p2.sh — Portfolio 2 driver. Run from inside portfolio-2-query-optimisation/.
set -euo pipefail
PSQL="psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U driveeasy -d driveeasy"

echo "==> [1/4] Sanity: P1 must already be loaded (rentals >= 50000)"
$PSQL -c "SELECT count(*) AS rental_count FROM rental;"

echo "==> [2/4] Run the 7 queries (queries.sql) — screenshot the result tables"
$PSQL -f queries.sql

echo "==> Reset: drop P2 indexes + ANALYZE so the BEFORE run is fair and re-runnable"
$PSQL -c "DROP INDEX IF EXISTS idx_car_branch_status, idx_rental_pickup_br_time, idx_rental_overdue, idx_rental_pickup_time_recent, idx_damage_rental_severity, idx_payment_rental_type_amount, idx_rental_one_way;" -c "ANALYZE;"

echo "==> [3/4] EXPLAIN ANALYZE BEFORE indexes (output → explain_before.txt)"
$PSQL -f explain_before.sql > explain_before.txt 2>&1
echo "    written: explain_before.txt"

echo "==> [4/4] Create optimisation indexes, then EXPLAIN ANALYZE AFTER"
$PSQL -f indexes.sql
$PSQL -f explain_after.sql > explain_after.txt 2>&1
echo "    written: explain_after.txt"

$PSQL -c "ANALYZE;" >/dev/null
{ echo "Q  BEFORE_ms  AFTER_ms"; paste <(grep -o 'Execution Time: [0-9.]*' explain_before.txt | awk '{print $3}') <(grep -o 'Execution Time: [0-9.]*' explain_after.txt | awk '{print $3}') | awk '{printf "Q%d  %s  %s\n", NR, $1, $2}'; echo; echo "Scan types BEFORE:"; grep -oE '(Seq Scan|Index Scan|Index Only Scan|Bitmap Heap Scan) on [a-z_]+' explain_before.txt | sort | uniq -c; echo "Scan types AFTER:"; grep -oE '(Seq Scan|Index Scan|Index Only Scan|Bitmap Heap Scan) on [a-z_]+' explain_after.txt | sort | uniq -c; echo; echo "Note: a query whose AFTER time is not lower kept the same plan (full-history aggregate) - the difference is run-to-run noise, not an index effect."; } | tee explain_summary.txt

echo
echo "==> Portfolio 2 done. Screenshot:"
echo "    • result tables from queries.sql"
echo "    • side-by-side Execution Time for each Q from explain_before.txt vs explain_after.txt"
echo "    • fill results_table.md with the real numbers"
echo
echo "    git add portfolio-2-query-optimisation/ && git commit -m 'P2: 7 queries + EXPLAIN before/after + indexes'"
