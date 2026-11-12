# Step 0 — Brief Summary of the CA

**Student:** Ganiu Owolabi Kasali · **Matric:** 2026/A/MIT/0106 · **Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems · **Cohort:** September 2026 · **Total marks:** 40
**Case study:** DriveEasy Rentals — a simulated car-rental company with branches in Lagos (Ikeja, Lekki, Victoria Island, Murtala Muhammed Airport) and Abuja (Nnamdi Azikiwe Airport). Customers rent cars by the day, may pick up at one branch and return at another, pay a security deposit, and are charged extra for late returns, extra mileage, or damage.

## What the CA requires

- **Type:** Individual practical database portfolio (not a written essay). Five portfolios, each with real, runnable evidence (scripts, schemas, ER diagrams, execution plans, screenshots, logs).
- **Case study:** Each student picks ONE realistic organisation and uses it consistently across all five portfolios. DriveEasy Rentals is the chosen case study here.
- **Deliverables per portfolio:** P1 design/modelling · P2 query processing & optimisation · P3 transactions & concurrency · P4 NoSQL/advanced models · P5 distributed/cloud. Plus a 2–3 page Final Documentation submitted through the LMS.
- **GitHub:** Private repo `advanced-database-portfolio/` with the suggested six-folder structure; **progressive commits expected** — bulk uploads near the deadline reduce marks.
- **LMS submission:** 2–3 page documentation + GitHub link + supporting screenshots. Repo must be accessible to the assessor before LMS submission.
- **Naming rules (for the later documentation file):** `Kasali_Ganiu_2026-A-MIT-0106_Documentation.pdf`.
- **Page limit:** 2–3 pages for the final documentation (produced AFTER all portfolios are run, using real results only).
- **AI use:** Permitted as a learning aid but must be declared — tool name, what it was used for, and how the output was reviewed/corrected/tested. AI use does not remove the student's responsibility for accuracy and understanding.
- **Similarity / integrity:** Individual work; properly acknowledge all sources, datasets, libraries. Copied, unclear, or inaccessible submissions may be flagged for an individual verification discussion.
- **Marking (40 total):** Technical correctness 8 · Design quality 6 · Practical implementation 8 · Query/performance analysis 5 · Advanced concepts 5 · Documentation & GitHub 5 · Reflection 3.

## Portfolio → Study-session map

> The course-notes PDF supplied (Edited - MIT8103 Advanced Database Systems.pdf, 154 pp.) is image-only and contains no extractable text layer, so the mapping below is derived from the CA's portfolio descriptions, which define exactly what each portfolio must demonstrate.

| Portfolio | Title | Maps to MIT 8103 study sessions |
|---|---|---|
| P1 | Database Design & Modelling | ER modelling; relational schema; keys & constraints (PRIMARY, FOREIGN, UNIQUE, CHECK, EXCLUSION); triggers; functional-dependency analysis; normalisation (1NF → 2NF → 3NF); PostgreSQL `tstzrange` + `btree_gist`; bulk data generation. |
| P2 | Query Processing & Optimisation | Relational algebra & query execution; `EXPLAIN` / `EXPLAIN ANALYZE`; sequential vs index scans; B-tree indexes; multi-column & covering indexes; statistics & cost estimation; query rewriting. |
| P3 | Transactions & Concurrency | ACID; `BEGIN/COMMIT/ROLLBACK`; savepoints; isolation levels (READ COMMITTED, REPEATABLE READ, SERIALIZABLE); phantom & dirty reads; row-level locks (`SELECT … FOR UPDATE`); exclusion constraints as concurrency control; deadlocks & lock ordering. |
| P4 | NoSQL & Advanced Data Models | CAP & BASE; document model (MongoDB); schema validation (JSON Schema); embedding vs referencing; aggregation pipeline; time-series collections; indexing (COLLSCAN vs IXSCAN); SQL vs NoSQL suitability. |
| P5 | Distributed & Cloud Database | Declarative partitioning; physical streaming replication; primary/replica roles; sync vs async replication; CAP trade-offs; sharding; cloud deployment; data-sovereignty (Nigeria Data Protection Act, NDPA 2023); scaling for seasonal peaks. |
