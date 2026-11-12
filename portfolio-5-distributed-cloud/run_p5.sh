#!/usr/bin/env bash
# run_p5.sh — Portfolio 5 driver. Run from inside portfolio-5-distributed-cloud/.
# Runs the partitioning demo. The primary+replica setup is a separate
# multi-step procedure documented in replica_setup.md (run by hand).
set -euo pipefail
PSQL="psql -v ON_ERROR_STOP=1 -h /var/run/postgresql -U driveeasy -d driveeasy"

echo "==> [1/2] Monthly partitioning demo (partition_setup.sql)"
$PSQL -f partition_setup.sql

echo
echo "==> [2/2] Streaming replica (replica_demo.sh: one script, real output)"
bash replica_demo.sh 2>&1 | tee replication_output.log

echo
echo "==> Cloud architecture: read cloud_architecture.md (NDPA 2023, CAP, sync vs async, December rush)."
echo "==> Portfolio 5 done. Evidence: p5_output.log and replication_output.log"
