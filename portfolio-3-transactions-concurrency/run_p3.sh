#!/usr/bin/env bash
# run_p3.sh - Portfolio 3 driver. Run from inside portfolio-3-transactions-concurrency/.
# Runs book_car(), the COMMIT/ROLLBACK demo, then all 6 two-session concurrency demos automatically.
set -euo pipefail
PSQL="psql -v ON_ERROR_STOP=0 -h /var/run/postgresql -U driveeasy -d driveeasy"

python3 -c 'import psycopg2' 2>/dev/null || {
  pip install psycopg2-binary 2>/dev/null || pip install --user psycopg2-binary 2>/dev/null || \
  pip install --break-system-packages psycopg2-binary 2>/dev/null || sudo apt-get install -y python3-psycopg2
}
python3 -c 'import psycopg2'

echo "==> [1/3] Create book_car() function + v_recent_bookings view"
$PSQL -v ON_ERROR_STOP=1 -f book_car.sql

echo "==> [2/3] commit_rollback_demo.sql (COMMIT / ROLLBACK / SAVEPOINT)"
$PSQL -f commit_rollback_demo.sql

echo "==> [3/3] Race condition, isolation levels and deadlock (two real sessions)"
python3 run_race_demos.py 2>&1 | tee race_demos_output.log

echo
echo "==> Portfolio 3 done. Evidence: race_demos_output.log and p3_output.log"
