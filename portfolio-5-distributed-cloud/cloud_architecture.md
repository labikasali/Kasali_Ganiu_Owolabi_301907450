# Portfolio 5 — Cloud Architecture for DriveEasy Rentals (Nigeria, NDPA 2023)

> This document describes the proposed cloud deployment for DriveEasy Rentals'
> database tier, addressing (a) data sovereignty under the Nigeria Data Protection
> Act 2023 (NDPA), (b) the CAP theorem trade-offs of the chosen architecture,
> (c) synchronous vs asynchronous replication, and (d) how the design absorbs the
> December rush. It is a written design — not a deployable template — and is meant
> to be paired with the live primary + streaming replica (see `replica_setup.md`)
> and the monthly partitioning in `partition_setup.sql`.

## 1. NDPA 2023 — data sovereignty

The Nigeria Data Protection Act 2023 requires that personal data of Nigerian
data subjects be processed in line with the principles of lawfulness, fairness,
transparency, purpose limitation, data minimisation, accuracy, storage limitation,
integrity/confidentiality, and accountability. Practically for DriveEasy Rentals:

- **In-country storage of personal data.** All customer PII (names, phone, email,
  address, driver's licence number, payment channels) is stored on infrastructure
  physically located in Nigeria. DriveEasy should select a cloud region hosted in
  Nigeria (e.g. a Lagos region of a hyperscaler or a Tier-III Nigerian data
  centre such as MTN NXtra/LG/Medallion/MDXi) for the primary and the synchronous
  replica.
- **Cross-border transfer.** The Act permits transfer outside Nigeria only with
  adequate safeguards (NDPC-approved mechanisms, BCRs, adequacy decision, or
  explicit informed consent of the data subject). DriveEasy's replicas for
  disaster-recovery or analytics should therefore live in another Nigerian
  region (or a West-African region with an NDPC-acknowledged transfer
  arrangement), not on a default overseas region.
- **Data Protection Officer (DPO).** DriveEasy must designate a DPO and register
  with the NDPC as a data controller of major importance (DCMI) once it processes
  the volume threshold set by the NDPC.
- **Data subject rights.** The schema already supports: access (read on
  `customer`, `driver_licence`, `payment`), rectification (UPDATE), erasure
  (cascading DELETE on `customer` with `ON DELETE CASCADE` from `driver_licence`),
  and portability (SQL `COPY` of a customer's rows to CSV).
- **Retention.** Rentals, payments, and damage reports must be kept for at least
  the statutory tax/accounting period (typically 6 years under Nigerian tax law)
  and then securely purged. Maintenance logs follow vehicle lifecycle.
- **Encryption.** TLS in transit (TLS 1.2+) for client connections to PostgreSQL
  and MongoDB, and AES-256 at rest (LUKS or cloud-volume encryption) for the data
  directories. Backups encrypted.
- **Audit logs.** `pgaudit` on PostgreSQL, MongoDB's profiler + an OS-level log
  collector. Access logs retained for ≥ 12 months.

## 2. CAP positioning

| Workload | CAP class | Why |
|---|---|---|
| Booking + payment core (PostgreSQL primary) | **CP** | Single-writer primary. Network partition between primary and replica → primary stays authoritative; writes can continue. The replica may lag but is not allowed to accept writes. |
| Customer booking site (reads from replica) | **AP-leaning** with eventual consistency | If the replica is unreachable the site can fall back to the primary for reads, or degrade gracefully. Reads may be slightly stale (a few seconds). |
| GPS trip logs (MongoDB time-series) | **CP** (single-node here; a 3-member replica set in production with `w:majority`) | Append-only telemetry; tolerate seconds of staleness on reads. |
| Inspection attachments (MongoDB inspections) | **CP** as above | Per-document atomicity; cross-document transactions avoided by design. |

DriveEasy does **not** need a fully AP system for its transactional core: a
momentary unavailability of the primary is preferable to a double booking. The
read-replica pattern is the standard trade-off: CP at the primary, eventual
consistency at the read side, all within the same Nigeria region so partitions
are rare.

## 3. Synchronous vs asynchronous replication

| Mode | How it works | Latency cost | Failover guarantee | When to use |
|---|---|---|---|---|
| **Async** (default) | Primary commits as soon as WAL is flushed locally; replica streams and applies at its own pace. | Lowest write latency. | Potential data loss = LSN gap at the moment of primary failure (typically sub-second). | Default for the booking site replica. Acceptable because DriveEasy's data-loss tolerance per rental is small but bounded. |
| **Sync** (`synchronous_commit=on` + `synchronous_standby_names='FIRST 1 (replica)'`) | Primary waits for at least one named replica to ACK before reporting COMMIT to the client. | Higher write latency = the round-trip to the replica. | Zero data loss on failover (the replica has the committed WAL). | Use for `payment` writes (deposit, late fee, damage fee). Could be applied per-transaction with `SET LOCAL synchronous_commit = on` to keep most rentals async. |
| **Local-only** (`synchronous_commit=local`) | Primary waits only for local WAL flush. | Lowest. | Higher data loss risk. | Not recommended for DriveEasy; only used in benchmarks. |

DriveEasy's chosen trade-off: **async by default** for booking throughput, with
the option to escalate **specifically to sync for payments** via per-transaction
`synchronous_commit` settings — keeping NDPA's "integrity" principle satisfied
where it matters most.

## 4. Sharding

PostgreSQL 16 native sharding is via declarative partitioning + a foreign data
wrapper per partition — but the brief forbids `postgres_fdw`, so we **do not**
shard across nodes. Instead:

- **Vertical split:** the transactional core (PostgreSQL) and the document store
  (MongoDB) are separate clusters, scaling independently.
- **Horizontal scaling of reads:** the primary + N streaming read replicas.
  Read replicas absorb the customer-site load; the primary serves operations.
- **Time-based partitioning:** `rental` is partitioned by month of `pickup_time`
  (see `partition_setup.sql`). Old partitions can be detached, archived to cold
  storage (still in Nigeria), and dropped from the hot set — a common pattern
  for retaining the 6-year history without bloating the working set.

MongoDB uses its native sharding (shard key on `car_id` for inspections, on the
time-series `ts` for GPS) when the data volume grows beyond one node. Not needed
for the cohort demo.

## 5. December rush handling

DriveEasy sees 3–4× the normal rental volume in December (the seasonal weight in
`bulk_generator.sql` models this). The architecture absorbs the rush as follows:

1. **Read scaling** — add 2 more streaming replicas before December. The customer
   booking site round-robins across replicas; `pgbouncer` in transaction mode
   pools connections.
2. **Write scaling** — partitioning by month means December inserts touch only
   `rental_p_<year>_12`, a much smaller index than the full table → faster inserts.
   Drop the December index buildup cost by re-creating indexes on the next
   month's partition just before December 1.
3. **Connection pooling** — `pgbouncer` caps the number of backends; the customer
   site uses the `transaction` pooling mode (safe for `book_car()`).
4. **Autoscaling the application tier** — the booking app (Node.js or similar)
   runs in a container cluster that scales on CPU/RPS. The DB does not autoscale
   in-place; instead we provision headroom in advance.
5. **Rate-limiting + queue** — extreme spikes go through a queue (e.g. Redis
   Streams) so the booking transactions execute at the database's pace, not the
   customer's. The `book_car()` function's lock-aware design (P3) means the queue
   never produces double bookings.
6. **Monitoring** — `pg_stat_statements`, `pg_stat_replication`, MongoDB's
   `db.serverStatus()` are scraped into Prometheus + Grafana. Alerts fire on
   replica lag > 5 s, primary CPU > 80 %, or payment write latency > 200 ms.
7. **Disaster recovery** — daily `pg_basebackup` to an S3-compatible object store
   in Nigeria + WAL archiving (5-minute RPO). A DR replica in a second Nigerian
   region can be promoted in < 5 minutes (RTO).

## 6. Cloud reference architecture (text diagram)

```
                       +-----------------------------+
                       |   Nigerian cloud region     |
                       |   (Lagos)                   |
   Customer app  --->  |  pgbouncer (transaction)   |
                       |     |                       |
                       |     v                       |
                       |  +----------------------+   |
                       |  | PostgreSQL 16 PRIMARY |   |
                       |  |  (driveeasy db)       |   |
                       |  +----------+-----------+   |
                       |             | WAL stream   |
                       |     +-------+--------+      |
                       |     v                v      |
                       |  replica-1         replica-2|   <-- customer booking site reads
                       |  (port 5433)       (port 5434)  (round-robin)
                       |                                |
                       |  MongoDB 8 (3-member replica set, w:majority)
                       |     - vehicle_inspections
                       |     - gps_trip_logs (time-series)
                       +--------------------------------+
                                          |
                                          v
                          Object storage (Nigeria) for encrypted backups
                          (pg_basebackup + WAL archive, NDPA retention)
```

## 7. Summary table

| Concern | Decision | Rationale |
|---|---|---|
| Data location | Nigeria (Lagos region) | NDPA 2023 sovereignty |
| Replication | Primary + ≥2 streaming replicas, async by default, sync for payments | CP for bookings, low write latency |
| Sharding | None on PostgreSQL (declarative partitioning by month only) | brief forbids postgres_fdw; read replicas absorb read load |
| Consistency | Strong on primary; eventual on replica (seconds) | Acceptable for booking site reads; not for billing |
| December rush | +2 replicas, partitioning, pgbouncer, app autoscaling, queue | Bounded write latency + read scaling |
| Backup | Daily base backup + WAL archive to Nigerian object storage, encrypted | RPO ≤ 5 min, RTO ≤ 5 min |
| Compliance | DPO, NDPC registration, TLS in transit, AES at rest, 6-yr retention, audit logs | NDPA 2023 + Nigeria tax law |
