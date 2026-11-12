#!/usr/bin/env bash
# runall.sh - runs Portfolios 1-5 in order, commits each, then collects results.
# Usage (from the repo root):  bash runall.sh        (all)    |    bash runall.sh 3   (resume from P3)
set -uo pipefail
START="${1:-1}"
REPO="$(pwd)"
KIT_ROOT="$HOME/kit"
FOLDERS=(portfolio-1-database-design portfolio-2-query-optimisation portfolio-3-transactions-concurrency portfolio-4-nosql portfolio-5-distributed-cloud)

echo "==> Finding the kit"
KIT="$(find "$KIT_ROOT" -maxdepth 3 -type d -name 'portfolio-1-*' -printf '%h\n' 2>/dev/null | head -1)"
if [ -z "$KIT" ]; then
  ZIP="$(ls "$REPO"/*FIXED*.zip 2>/dev/null | head -1)"
  [ -n "$ZIP" ] || { echo "!!! No kit and no FIXED zip in $REPO - send Joseph this message"; exit 1; }
  mkdir -p "$KIT_ROOT" && unzip -oq "$ZIP" -d "$KIT_ROOT"
  KIT="$(find "$KIT_ROOT" -maxdepth 3 -type d -name 'portfolio-1-*' -printf '%h\n' | head -1)"
fi
echo "    kit: $KIT"

echo "==> Starting PostgreSQL and MongoDB (Codespaces stops them when it sleeps)"
sudo pg_ctlcluster 16 main start 2>/dev/null || true
if ! pgrep -x mongod >/dev/null; then
  sudo mkdir -p /data/db /var/log/mongodb
  sudo chown -R mongodb:mongodb /data/db /var/log/mongodb 2>/dev/null || true
  sudo runuser -u mongodb -- mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null 2>&1 || true
fi
sleep 3

if ! psql -h /var/run/postgresql -U driveeasy -d driveeasy -c 'SELECT 1' >/dev/null 2>&1; then
  echo "==> Database missing - running setup.sh again"
  bash "$KIT/setup.sh" || { echo "!!! SETUP FAILED - send Joseph the text above"; exit 1; }
fi

python3 -c 'import psycopg2' 2>/dev/null || {
  pip install psycopg2-binary >/dev/null 2>&1 || pip install --user psycopg2-binary >/dev/null 2>&1 || \
  pip install --break-system-packages psycopg2-binary >/dev/null 2>&1 || \
  pip install --user --break-system-packages psycopg2-binary >/dev/null 2>&1 || \
  sudo apt-get install -y python3-psycopg2 >/dev/null 2>&1
}
python3 -c 'import psycopg2' || { echo "!!! psycopg2 could not be installed - send Joseph this message"; exit 1; }

for N in 1 2 3 4 5; do
  [ "$N" -lt "$START" ] && continue
  F="${FOLDERS[$((N-1))]}"
  echo; echo "################  PORTFOLIO $N  ($F)  ################"
  rm -rf "$REPO/$F"; cp -r "$KIT/$F" "$REPO/$F"
  ( cd "$REPO/$F" && bash "run_p${N}.sh" 2>&1 | tee "p${N}_output.log"; exit "${PIPESTATUS[0]}" )
  if [ $? -ne 0 ]; then
    echo "!!! P$N FAILED - send Joseph $F/p${N}_output.log"
    exit 1
  fi
  ( cd "$REPO" && git add "$F" && git commit -qm "P$N: run and results" && git push -q ) || echo "    (commit or push skipped - check git status)"
done

cp "$KIT/collect_results.sh" "$REPO/collect_results.sh" 2>/dev/null || true
cd "$REPO" && bash collect_results.sh && code my_results.txt 2>/dev/null || true
echo; echo "==> ALL DONE. Copy the whole text of my_results.txt (Ctrl+A, Ctrl+C) and send it to Joseph."
