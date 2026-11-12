# Portfolio 5 — Primary + Streaming Read Replica Setup

> Goal: configure a PostgreSQL **primary** + one **streaming read replica** on the
> same Codespaces VM (different data directories, different ports).
> The replica serves the customer booking site (read-only); the primary serves
> the operations team (writes).
>
> Codespaces-specific notes used here:
> - The codespace user can use sudo only as root, so every `postgres` command is
>   `sudo runuser -u postgres -- …` (never `sudo -u postgres`).
> - PostgreSQL 16 on Ubuntu keeps its config in `/etc/postgresql/16/main/`.
> - `pg_ctl` lives at `/usr/lib/postgresql/16/bin/pg_ctl`.
> - TCP logins need a password; we connect through the Unix socket
>   (`host=/var/run/postgresql`).
> - `pg_hba.conf` trust lines must go at the **top** of the file (above the
>   default peer/md5 rules) so they take effect.
> - `postgres_fdw` is intentionally NOT used (per the brief).

## Step 0 — make sure primary is set up
The `setup.sh` at the repo root already installed PostgreSQL 16 and started the
`16/main` cluster (the primary) on the default port `5432`. Confirm:
```bash
sudo pg_lsclusters
sudo runuser -u postgres -- psql -d driveeasy -c "SELECT pg_is_in_recovery();"
# should return f (false) → this is the PRIMARY
```

## Step 1 — create a replication role on the primary
```bash
sudo runuser -u postgres -- psql <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='repl_user') THEN
    CREATE ROLE repl_user WITH REPLICATION LOGIN PASSWORD 'repl_pwd_2026';
  END IF;
END$$;
SQL
```

## Step 2 — enable WAL streaming on the primary
Edit `/etc/postgresql/16/main/postgresql.conf`:
```ini
listen_addresses            = '127.0.0.1'
wal_level                   = replica
max_wal_senders             = 10
max_replication_slots       = 10
hot_standby                  = on          # needed on the REPLICA only, harmless on primary
synchronous_commit           = on          # default; covered in the CAP discussion
```
Apply: `sudo pg_ctlcluster 16 main restart`.

Then put a trust line for replication at the **top** of `/etc/postgresql/16/main/pg_hba.conf`:
```text
#  TOP OF FILE — must come before the default rules
local   replication     repl_user                                       trust
host    replication     repl_user        127.0.0.1/32                    trust
host    replication     repl_user        ::1/128                         trust
```
Apply: `sudo pg_ctlcluster 16 main reload`.

## Step 3 — create the replica's data directory + take a base backup
```bash
# Stop any stale replica cluster first
sudo pg_ctlcluster 16 replica stop 2>/dev/null || true
sudo rm -rf /var/lib/postgresql/16/replica

sudo mkdir -p /var/lib/postgresql/16/replica
sudo chown postgres:postgres /var/lib/postgresql/16/replica
sudo chmod 0700              /var/lib/postgresql/16/replica

# pg_basebackup copies the primary's data dir + writes standby.signal
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_basebackup \
    -h 127.0.0.1 -p 5432 -D /var/lib/postgresql/16/replica -U repl_user \
    -Fp -Xs -P -R
#   -R writes standby.signal + primary_conninfo for us
ls -la /var/lib/postgresql/16/replica/standby.signal   # must exist
```

## Step 4 — give the replica its own config + port
A `pg_basebackup`-created replica inherits a copy of the primary's config, which
points at port 5432. We need it on a different port (5433) and listening on
Unix socket + TCP localhost.

Edit `/var/lib/postgresql/16/replica/postgresql.conf` (or the `postgresql.auto.conf`
that `pg_basebackup -R` writes). Append/override:
```ini
port                  = 5433
listen_addresses      = '127.0.0.1'
hot_standby           = on
unix_socket_directories = '/var/run/postgresql'
shared_buffers        = 128MB
```

Edit the replica's `pg_hba.conf` (`/var/lib/postgresql/16/replica/pg_hba.conf`).
Put trust lines at the TOP:
```text
local   all             all                                             trust
host    all             all             127.0.0.1/32                    trust
host    all             all             ::1/128                        trust
```

## Step 5 — register + start the replica cluster
```bash
# Register the replica as a separate cluster (so pg_lsclusters can see it)
sudo pg_createcluster 16 replica --datadir=/var/lib/postgresql/16/replica \
    -- --listen_addresses='127.0.0.1' --port=5433 2>/dev/null || true

# Start it
sudo pg_ctlcluster 16 replica start
sudo pg_lsclusters
```

If `pg_createcluster` complains the directory already has data (it does), start the
cluster directly with `pg_ctl`:
```bash
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
    -D /var/lib/postgresql/16/replica -l /var/log/postgresql/replica.log start
```

## Step 6 — verify the replica
On the **replica** (port 5433):
```bash
sudo runuser -u postgres -- psql -p 5433 -d driveeasy -c "SELECT pg_is_in_recovery();"
# should return t (true) → this is a REPLICA

sudo runuser -u postgres -- psql -p 5433 -d driveeasy -c \
  "SELECT status, sync_state FROM pg_stat_replication;"   # this row appears on the PRIMARY only
```

On the **primary** (port 5432):
```bash
sudo runuser -u postgres -- psql -p 5432 -d driveeasy -c \
  "SELECT application_name, state, sync_state, sent_lsn, replay_lsn
     FROM pg_stat_replication;"
# >>> screenshot: state='streaming', sync_state='async' (default)
```

## Step 7 — show that the replica REJECTS writes
```bash
sudo runuser -u postgres -- psql -p 5433 -d driveeasy -c \
  "INSERT INTO branch (code, name, city, address) VALUES ('TST','Test','Lagos','x');"
# >>> EXPECTED:  ERROR: cannot execute INSERT in a read-only transaction
```

## Step 8 — show that new rows on the primary ARRIVE on the replica
Open two terminals:

**Terminal A (primary)**
```bash
sudo runuser -u postgres -- psql -p 5432 -d driveeasy -c \
  "INSERT INTO branch (code, name, city, address) VALUES ('PRB','Probe','Lagos','test');"
```

**Terminal B (replica)**
```bash
sudo runuser -u postgres -- psql -p 5433 -d driveeasy -c \
  "SELECT code, name FROM branch WHERE code='PRB';"
# >>> screenshot: the new branch appears on the replica (within milliseconds,
#     async streaming). If you switched synchronous_commit / synchronous_standby_names
#     to a sync replica, the primary would block on the insert until the replica ACKs.
```

## Step 9 — switch to SYNCHRONOUS replication (optional, for the CAP discussion)
On the primary, in `postgresql.conf`:
```ini
synchronous_standby_names = 'FIRST 1 (replica)'    # block until 1 named replica ACKs
synchronous_commit        = on
```
Apply: `sudo pg_ctlcluster 16 main reload`.
Then check `pg_stat_replication.sync_state` again — should now read `sync`.
Inserting on the primary now blocks until the replica acknowledges.

## What to screenshot for evidence
1. `pg_lsclusters` showing both clusters `16/main` (online, primary) and `16/replica` (online).
2. `SELECT pg_is_in_recovery();` returning `f` on port 5432 and `t` on port 5433.
3. `pg_stat_replication` row on the primary with `state=streaming`.
4. The replica rejecting an INSERT (the read-only transaction error).
5. New branch on the primary appearing on the replica.
6. (Optional) `sync_state=sync` after Step 9.
