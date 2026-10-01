# Load tests

One shared set of k6 scripts, seed data, and report tools is used for both
service profiles. Run the same test against each profile; results are kept
separate.

```text
load-tests/
  k6/          Shared tests and runners
  report/      Shared report generator
  seed/        Shared generator and manifest
  results/
    naive/     Fixed baseline JSON, summaries, charts, and HTML exports
    optimized/ Optimized-profile results
```

From the repository root, with the read service running in the selected
profile, choose that profile explicitly:

```powershell
.\load-tests\k6\run-arrival.ps1 -Profile naive -Label baseline -Mode uniform
.\load-tests\k6\run-arrival.ps1 -Profile optimized -Label optimized -Mode uniform
```

The VU runner and Hikari observation runner also require `-Profile naive` or
`-Profile optimized`. To regenerate a report without running a test:

```powershell
python .\load-tests\report\make_report.py --profile naive
python .\load-tests\report\make_report.py --profile optimized
```

Each runner/report reads and writes only the selected profile's folder.
