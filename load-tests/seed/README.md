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
