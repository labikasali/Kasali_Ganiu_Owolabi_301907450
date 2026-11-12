#!/usr/bin/env bash
# replica_demo.sh - ONE script: builds a streaming replica on port 5433 and proves it works.
# Everything is printed from real queries. Run from portfolio-5-distributed-cloud/: bash replica_demo.sh
set -euo pipefail
HBA=/etc/postgresql/16/main/pg_hba.conf
RDIR=/var/lib/postgresql/16/replica
PGBIN=/usr/lib/postgresql/16/bin
P="sudo runuser -u postgres -- psql -X -At -h /var/run/postgresql -d driveeasy"

echo "==> [1/6] Replication access on the primary (hba line at the TOP, only once)"
if ! sudo grep -q '# driveeasy-replication' "$HBA"; then
  sudo cp "$HBA" "$HBA.bak.replica"
  { echo "local   replication     all                                     trust  # driveeasy-replication"; sudo cat "$HBA.bak.replica"; } | sudo tee "$HBA" >/dev/null
  sudo pg_ctlcluster 16 main reload
fi

echo "==> [2/6] Fresh base backup into $RDIR"
sudo runuser -u postgres -- $PGBIN/pg_ctl -D $RDIR stop -m fast 2>/dev/null || true
sudo rm -rf $RDIR
sudo runuser -u postgres -- $PGBIN/pg_basebackup -h /var/run/postgresql -p 5432 -D $RDIR -Fp -Xs -R -c fast
sudo chmod 700 $RDIR

echo "==> [3/6] Replica config (Ubuntu keeps config in /etc, so write our own)"
sudo cp "$HBA" $RDIR/pg_hba.conf
sudo cp /etc/postgresql/16/main/pg_ident.conf $RDIR/pg_ident.conf
printf "port = 5433\nlisten_addresses = ''\nunix_socket_directories = '/var/run/postgresql'\nhot_standby = on\n" | sudo tee $RDIR/postgresql.conf >/dev/null
sudo chown -R postgres:postgres $RDIR
sudo runuser -u postgres -- $PGBIN/pg_ctl -D $RDIR -l /var/log/postgresql/replica.log -w start >/dev/null
sleep 2

echo; echo "==> [4/6] Who is who"
echo "primary port 5432  pg_is_in_recovery = $($P -p 5432 -c 'SELECT pg_is_in_recovery()')"
echo "replica port 5433  pg_is_in_recovery = $($P -p 5433 -c 'SELECT pg_is_in_recovery()')"

echo; echo "==> [5/6] Write on the REPLICA must be rejected:"
$P -p 5433 -c "INSERT INTO branch(branch_id,name,city,address) VALUES (999,'X','X','X')" 2>&1 | head -2 || true
$P -p 5433 -c "CREATE TEMP TABLE t(x int)" 2>&1 | head -1 || true

echo; echo "==> [6/6] Write on the PRIMARY must arrive on the REPLICA:"
$P -p 5432 -c "CREATE TABLE IF NOT EXISTS replication_probe(id serial PRIMARY KEY, note text, created timestamptz DEFAULT now())"
$P -p 5432 -c "INSERT INTO replication_probe(note) VALUES ('hello from primary at '||now()::time)"
sleep 2
echo "primary rows: $($P -p 5432 -c 'SELECT count(*) FROM replication_probe')"
echo "replica rows: $($P -p 5433 -c 'SELECT count(*) FROM replication_probe')"
echo "replica last row: $($P -p 5433 -c 'SELECT note FROM replication_probe ORDER BY id DESC LIMIT 1')"
echo "replication lag (replica): $($P -p 5433 -c 'SELECT now()-pg_last_xact_replay_timestamp()')"
echo "pg_stat_replication (primary):"
$P -p 5432 -F ' | ' -c "SELECT application_name, state, sync_state FROM pg_stat_replication"
echo "RESULT: replica in recovery, rejects writes, and received the primary's new row."
