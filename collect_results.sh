#!/usr/bin/env bash
# collect_results.sh - gathers the real output of your own run into my_results.txt
cd "$(dirname "$0")"
OUT=my_results.txt
sec() { echo; echo "=================== $1 ==================="; }
{
 echo "MIT 8103 results - generated $(date) - $(hostname)"
 sec "P1 counts"; psql -h /var/run/postgresql -U driveeasy -d driveeasy -c "SELECT (SELECT count(*) FROM rental) rentals,(SELECT count(*) FROM payment) payments,(SELECT count(*) FROM damage_report) damage_reports,(SELECT count(*) FROM car) cars,(SELECT count(*) FROM customer) customers" 2>&1
 sec "P1 constraint tests (EXPECT_FAIL lines)"; grep -E "EXPECT_FAIL|^--- TEST" portfolio-1-database-design/p1_output.log 2>&1 | head -40
 sec "P2 summary"; cat portfolio-2-query-optimisation/explain_summary.txt 2>&1
 sec "P3 race demos"; cat portfolio-3-transactions-concurrency/race_demos_output.log 2>&1
 sec "P4 index summary + counts"; grep -E "count:|Stage|COLLSCAN|IXSCAN|totalDocsExamined|totalKeysExamined|executionTimeMs|nReturned" portfolio-4-nosql/p4_output.log 2>&1 | head -30
 sec "P5 partitions"; grep -E "rental_p_|rows_in_default|Subplans Removed|Execution Time|UNPARTITIONED|PARTITIONED" portfolio-5-distributed-cloud/p5_output.log 2>&1 | head -60
 sec "P5 replica"; cat portfolio-5-distributed-cloud/replication_output.log 2>&1
} > "$OUT"
echo "Written $OUT ($(wc -l < $OUT) lines)"
