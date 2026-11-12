#!/usr/bin/env bash
# setup.sh — install and start PostgreSQL 16 + MongoDB 8 in GitHub Codespaces (Ubuntu).
# Run:  bash setup.sh
set -euo pipefail

echo "==> [1/7] Remove stale yarn list (breaks apt update in Codespaces)"
sudo rm -f /etc/apt/sources.list.d/yarn.list

echo "==> [2/7] apt-get update + base packages"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg lsb-release wget unzip \
    postgresql-client-common build-essential python3-pip jq

echo "==> [3/7] Install PostgreSQL 16 (official PGDG repo)"
if ! command -v psql >/dev/null 2>&1 || ! pg_lsclusters 2>/dev/null | grep -q '^16 '; then
    sudo install -d /usr/share/postgresql-common/pgdg
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-contrib-16
fi

echo "==> [4/7] Start PostgreSQL 16 cluster"
sudo pg_ctlcluster 16 main start 2>/dev/null || true
sudo pg_lsclusters

# codespace user can use sudo only as root; create app role + db via runuser -u postgres
echo "==> [5/7] Create driveeasy role + database (Unix socket, no password)"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='driveeasy') THEN
    CREATE ROLE driveeasy WITH LOGIN SUPERUSER;
  END IF;
END$$;
SELECT 'role ok' AS info;
SQL

sudo runuser -u postgres -- psql -c "CREATE DATABASE driveeasy OWNER driveeasy" 2>/dev/null \
    || echo "driveeasy db already exists"

# Codespaces default pg_hba.conf uses `peer` for local connections, which would
# reject the codespace user `z` connecting as role `driveeasy`. Per the brief,
# put trust lines at the TOP of pg_hba.conf (above the default peer/md5 rules).
HBA=/etc/postgresql/16/main/pg_hba.conf
if ! sudo grep -q '^local\s\+all\s\+all\s\+trust$' "$HBA"; then
    sudo cp "$HBA" "${HBA}.bak.$(date +%s)"
    sudo sed -i '1i local   all             all                                     trust\nhost    all             all             127.0.0.1/32            trust\nhost    all             all             ::1/128                 trust' "$HBA"
    sudo pg_ctlcluster 16 main reload
    echo "    pg_hba.conf updated (trust at top, reloaded)."
else
    echo "    pg_hba.conf already permits local trust."
fi

# enable btree_gist + pgcrypto extensions (needed by P1/P3)
sudo runuser -u postgres -- psql -d driveeasy -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"
sudo runuser -u postgres -- psql -d driveeasy -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

echo "==> [6/7] Install MongoDB 8 (official repo, MongoDB Community Edition)"
if ! command -v mongod >/dev/null 2>&1; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
        | sudo tee /etc/apt/trusted.gpg.d/mongodb-server-8.0.asc >/dev/null
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/8.0 multiverse" \
        | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y mongodb-org
fi

echo "==> [7/7] Start MongoDB 8 (no systemd in Codespaces → run mongod directly)"
sudo mkdir -p /data/db /var/log/mongodb
sudo chown -R mongodb:mongodb /data/db /var/log/mongodb 2>/dev/null || true
if ! pgrep -x mongod >/dev/null 2>&1; then
    sudo runuser -u mongodb -- mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log \
        --fork --bind_ip 127.0.0.1 --port 27017 || \
    sudo mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log \
        --fork --bind_ip 127.0.0.1 --port 27017
fi

# Lagos time zone for the database (CHECKs/date logic use local time)
sudo runuser -u postgres -- psql -c "ALTER DATABASE driveeasy SET timezone TO 'Africa/Lagos'"

# psycopg2 for the P3 concurrency demos: fallback chain, then verify
python3 -c 'import psycopg2' 2>/dev/null || pip install psycopg2-binary 2>/dev/null \
  || pip install --user psycopg2-binary 2>/dev/null \
  || pip install --break-system-packages psycopg2-binary 2>/dev/null \
  || pip install --user --break-system-packages psycopg2-binary 2>/dev/null \
  || sudo apt-get install -y python3-psycopg2
python3 -c 'import psycopg2; print("psycopg2 OK")'

echo
echo "==> Verify"
sudo runuser -u postgres -- psql -d driveeasy -c "SELECT version();"
mongosh --quiet --eval 'db.version()' || mongo --quiet --eval 'db.version()'

echo
echo "==============================================================="
echo "Setup complete."
echo "  PostgreSQL 16  → connect:  psql \"host=/var/run/postgresql dbname=driveeasy user=driveeasy\""
echo "  MongoDB 8       → connect:  mongosh"
echo "Run each portfolio's run_pN.sh next."
echo "==============================================================="
