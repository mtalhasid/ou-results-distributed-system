# Load-test reports

Generate the Markdown summary and comparison charts from the repeated k6 JSON
exports for one service profile:

```powershell
pip install matplotlib
python load-tests/report/make_report.py --profile naive
```

The script requires Python 3.10 or later and matplotlib. It has no network
access requirements. It reads VU summaries named
`<label>-<N>-run<i>.json` and arrival-rate summaries named
`<label>-<mode>-arrival-<P>-run<i>.json`; older arrival names without a mode
are treated as `uniform`. Historical `baseline-arrival-...` files are reported
under `baseline-legacy`. Files without the `-run<i>` suffix, including the
original unwarmed baseline exports, are ignored.

The required `--profile` value is `naive` or `optimized`. The script reads only
raw run files from `load-tests/results/<profile>/raw/` and writes that profile's
`summary.md` and charts under `load-tests/results/<profile>/charts/`. It also
includes `raw/hikari-100.csv` from that profile when present. Arrival results
are grouped by label and mode. Use repeatable aliases to merge or rename labels
in a report, for example:

```powershell
python load-tests/report/make_report.py --profile naive --alias baseline-confirmation=baseline
```

Tables show latency in seconds to two decimal places. Arrival charts show
individual run values as faint points, medians as lines, and iteration delivery
percentage against a 100% reference.
