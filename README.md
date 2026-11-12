# DriveEasy Rentals — Advanced Database Portfolio

**Student:** Ganiu Owolabi Kasali · **Matric:** 2026/A/MIT/0106 · **Programme:** MIT, Miva Open University
**Course:** MIT 8103 Advanced Database Systems (September 2026 cohort) · **40 marks**

## Case study
DriveEasy Rentals — a simulated car-rental company with branches in Lagos (Ikeja, Lekki, Victoria Island, Murtala Muhammed Airport) and Abuja (Nnamdi Azikiwe Airport). Customers rent cars by the day, may pick up at one branch and return at another, pay a security deposit, and are charged extra for late returns, extra mileage, or damage. All amounts in ₦ (Nigerian Naira). Dates are generated relative to *today* so the demo never expires.

## Repository layout
```
advanced-database-portfolio/
├── docs/
│   └── 00_brief_summary.md
├── portfolio-1-database-design/        ER + 3NF + schema + bulk data + constraint tests
├── portfolio-2-query-optimisation/     6 queries + indexes + EXPLAIN before/after
├── portfolio-3-transactions-concurrency/  book_car() + race condition + isolation + deadlock
├── portfolio-4-nosql/                   MongoDB inspections + GPS + aggregations + indexes
├── portfolio-5-distributed-cloud/      Partitioning + replica + cloud architecture
├── setup.sh                             installs PostgreSQL 16 + MongoDB 8 in Codespaces
└── README.md                            (this file)
```

## Quick start (Codespaces)
```bash
# 1. clone your private repo, then in the repo root:
bash setup.sh                      # installs PostgreSQL 16 + MongoDB 8, creates driveeasy db
cd portfolio-1-database-design && bash run_p1.sh
cd ../portfolio-2-query-optimisation && bash run_p2.sh
cd ../portfolio-3-transactions-concurrency && bash run_p3.sh
cd ../portfolio-4-nosql && bash run_p4.sh
cd ../portfolio-5-distributed-cloud && bash run_p5.sh
```

## GitHub repository
Private repo link (invite assessor as collaborator): **[GitHub link]**

## Conventions used everywhere
- All PostgreSQL connections go through the **Unix socket** (`host=/var/run/postgresql`), not TCP — TCP needs a password and Codespaces does not set one by default.
- Codespaces root-only sudo: every postgres command is `sudo runuser -u postgres -- …`, never `sudo -u postgres`.
- Bulk data is generated inside SQL/JS scripts (`generate_series`, PL/pgSQL loops, JS loops) — no CSV/JSON data files are committed.
- Every screenshot/output that depends on a real run is marked **`[paste real output here]`** in the source files; nothing is fabricated.

## AI use declaration (final)
This portfolio was prepared with AI assistance (Z.ai). The AI tool was used to scaffold SQL/JS scripts, ER/normalisation notes, MongoDB aggregations, and the cloud-architecture discussion. The student reviewed every file, ran each portfolio in Codespaces, replaced every `[paste real output here]` placeholder with real EXPLAIN timings / logs / screenshots, and is responsible for the accuracy and understanding of all submitted work.

## Honest, late-stage deliverable (NOT in this zip)
After running all five portfolios, the student produces a single 2–3 page PDF named
`Kasali_Ganiu_2026-A-MIT-0106_Documentation.pdf` containing the real results, the GitHub link, an individual technical reflection, and the AI-use declaration. This PDF is produced **only after** the real runs.
