# Synthetic seed data

All data is fictional. Install the sole third-party dependency with
`python -m pip install bcrypt`, then run:

```powershell
python .\load-tests\seed\generate.py
python .\load-tests\seed\generate.py --upload-sample 5000
```

Outputs are written to the git-ignored `load-tests/seed/out/` directory. Use
`--unpublished` for a DRAFT exam and unpublished rows, or `--seed N` to choose
another deterministic data set. The shared demo password is printed once. It
is only for synthetic accounts and must never be reused.

Use `psql` with the Neon URL for each primary. The `SHARD_1_PRIMARY` and
`SHARD_2_PRIMARY` values in `.env` are used below. PowerShell does not import
`.env` automatically; the commands read the URL from that file without
printing it. Load schema, exam, and results in that order:

```powershell
$envLines = Get-Content .env
$shard1 = ($envLines | Where-Object { $_ -match '^SHARD_1_PRIMARY=' } | Select-Object -First 1) -replace '^SHARD_1_PRIMARY=', ''
psql $shard1 -v ON_ERROR_STOP=1 -f .\load-tests\seed\out\schema_shard.sql
psql $shard1 -v ON_ERROR_STOP=1 -c "\copy exams FROM 'load-tests/seed/out/exams.csv' WITH (FORMAT csv, HEADER true)"
psql $shard1 -v ON_ERROR_STOP=1 -c "\copy results FROM 'load-tests/seed/out/results_shard1.csv' WITH (FORMAT csv, HEADER true)"
```

Repeat those commands with `$shard2` set from `SHARD_2_PRIMARY` and replace the results filename with `results_shard2.csv`. `\copy` reads files
from your machine. Never seed replicas. Load `schema_account.sql` and
`credentials.csv` only when the account service is needed.
Loading is intentionally a one-time setup for an empty shard: `\copy` appends
rows, and repeating it will hit the results primary key. Generating CSVs again
does not modify Neon. For a fresh run, use a new empty Neon branch/database;
do not truncate an existing dataset unless you have confirmed it is disposable.

Optional disposable PostgreSQL 16 COPY check (validation only; the app still
uses Neon):

```powershell
docker run -d --name ou-seed-check -e POSTGRES_PASSWORD=seedtest -e POSTGRES_DB=ouresults -v "${PWD}\load-tests\seed\out:/seed:ro" postgres:16
docker exec ou-seed-check sh -c "until pg_isready -U postgres; do sleep 1; done"
docker exec ou-seed-check psql -U postgres -d ouresults -f /seed/schema_shard.sql
docker exec ou-seed-check psql -U postgres -d ouresults -c "\copy exams FROM '/seed/exams.csv' WITH (FORMAT csv, HEADER true)"
docker exec ou-seed-check psql -U postgres -d ouresults -c "\copy results FROM '/seed/results_shard1.csv' WITH (FORMAT csv, HEADER true)"
docker exec ou-seed-check psql -U postgres -d ouresults -c "SELECT count(*) FROM results"
docker rm -f ou-seed-check
```

The optional `upload-sample.csv` has the result columns except `published` and
`uploaded_at`; its roll numbers are reserved from the shard seed and are
intended for the later ingestion path. `F = 0` is a modeling assumption; it
has only been checked against S, A, B, and C grades, not verified as university
policy.


You're working in the monorepo `ou-results/`. Build the seed-data tooling in
`load-tests/seed/`. Purpose: generate synthetic Osmania University style result
data so I can bulk-load Postgres and drive k6 load tests. Everything must be fake.

Read first: docs/ou-results-spec.md, sections 2, 5 and 10 (roll number format,
data model, seed rules). Follow it. Where this prompt is more specific, this
prompt wins.

Write a Python 3 script (generate.py) plus a short README in that folder.
Outputs go to load-tests/seed/out/ (gitignored):

1. schema.sql: DDL for exams and results per spec section 5 (PK
   (exam_id, roll_no, semester), subjects as JSONB, published, uploaded_at,
   publish_status), plus student_credentials for the account DB.
2. results_shard1.csv and results_shard2.csv: COPY-ready, about 50,000 rows each
   (about 100,000 total). One row per student per semester. About 95% of
   students get one row for the current semester; about 5% also get extra
   backlog-semester rows, so multi-row lookups exist.
3. exams.csv: one exam, 2026-jul-aug, publish_status PUBLISHED and rows
   published=true by default (the load tests need readable data). A
   --unpublished flag produces published=false and DRAFT instead.
4. credentials.csv: roll_no plus ONE shared precomputed BCrypt hash of a known
   test password. Compute the hash once, not per row. Print the plain test
   password once to stdout.
5. seed-manifest.json: small file listing college codes, shard assignment,
   batch years, dept codes, and the roll-number range per (college, batch,
   dept). k6 will use it to generate valid roll numbers without a huge list.
6. --upload-sample N: writes a small file of N rows (5,000 to 10,000) in a
   simple, documented format for the future ingestion service.

Rules:
- Roll number: 12 digits = college(4) + batch year(2) + dept(3) + roll(3).
  Use 8 to 9 college codes (1604 must be one), 2 to 3 batch years, 3 to 5 dept
  codes, and roll numbers sequential from 001 within each group.
- Sharding: assign whole college codes to shards, balanced by student count so
  the two shards are within about 10% of each other. Also write the assignment
  to contracts/shard-map.yml.
- Fake students: name, father's name and gender from small built-in lists.
  Course "B.E. (AICTE)", medium "ENGLISH".
- Subjects: a small catalog per department and semester (5 to 7 subjects each
  with code, name, credits), with a grade per student stored as a JSON array.
  Grades are random, weighted toward S/A/B/C, with about 5% of students getting
  at least one fail (F).
- SGPA = sum(credits x grade points) / sum(credits), rounded to 2 decimals.
  S=10, A=9, B=8, C=7, F=0, and failed subjects still count in the credit
  total. result_status is PASSED unless any F, then FAILED. cgpa is null.
- Deterministic by default (fixed random seed), --seed to change it.
- No network calls or external services. Standard library plus bcrypt only.

Why this matters: k6 uses these roll numbers directly, and the shard balance
and file formats decide whether the real upload path in Phase 4 works without
regenerating data.

Before finishing, verify and report: row counts per file, no duplicate
(exam_id, roll_no, semester), every roll number matches ^\d{12}$, the shard
split is within 10%, and COPY of results_shard1.csv into a throwaway Postgres 16
container succeeds. Do not add tests or extra features.

ADDENDUM (overrides anything above)
- Use exactly 9 college codes (1604 included), 3 batch years (23, 24, 25) and 5 dept codes (e.g. 733 to 737): 135 groups. Shard CSV roll numbers run 001 to 900 only. Group sizes differ (about 400 to 900). Assign colleges to shards by greedy balancing on student count.
- Semester by batch: 23 -> 6, 24 -> 4, 25 -> 2. Backlog rows use an earlier semester with only 1 to 2 subjects.
- roll_no, college_code, dept_code, course, medium are TEXT (keep leading zeros). batch_year and semester are smallint. uploaded_at is one fixed timestamp.
- exams.csv columns: exam_id, title, result_date (2026-09-19), publish_status. Load the same file into both shards.
- Two schema files: schema_shard.sql (exams, results) and schema_account.sql (student_credentials, registrations). Never create student_credentials on a shard.
- README: show loading with psql \copy (client-side) using the direct Neon connection string, in order: schema, exams, results.
- Upload sample: roll numbers 901 to 999 in each group, NOT in the shard CSVs. Format: CSV with the shard columns minus published and uploaded_at.
- Names and gender in uppercase like the real page. No real people's names.
- If Docker is unavailable for the verification, say so instead of reporting it as done.
- README note: F = 0 scoring is an assumption, checked only against S to C grades.