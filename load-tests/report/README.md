# Load-test reports

Generate the Markdown summary and comparison charts from the repeated k6 JSON
exports in `load-tests/results/`:

```powershell
pip install matplotlib
python load-tests/report/make_report.py
```

The script requires Python 3.10 or later and matplotlib. It has no network
access requirements. It reads VU summaries named
`<label>-<N>-run<i>.json` and arrival-rate summaries named
`<label>-arrival-<P>-run<i>.json`; files without the `-run<i>` suffix, including
the original unwarmed baseline exports, are ignored.

It regenerates `load-tests/results/summary.md` with separate VU baseline and
arrival-rate sections. It also writes charts to
`load-tests/results/charts/`. If `load-tests/results/hikari-100.csv` exists, a
HikariCP pending/active connection chart is generated as well. The separate
`baseline-summary.md` report is not modified.
