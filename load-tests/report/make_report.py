#!/usr/bin/env python3
"""Summarize k6 VU and arrival-rate runs and render presentation-ready charts."""

from __future__ import annotations

import csv
import json
import math
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[2]
RESULTS_DIR = ROOT / "load-tests" / "results"
CHARTS_DIR = RESULTS_DIR / "charts"
VU_PATTERN = re.compile(r"^(?P<label>.+)-(?P<vus>\d+)-run(?P<run>\d+)\.json$")
ARRIVAL_PATTERN = re.compile(
    r"^(?P<label>.+)-arrival-(?P<peak>\d+)-run(?P<run>\d+)\.json$"
)
MACHINE_PATTERN = re.compile(r"^- Machine:\s*(.+)$", re.MULTILINE)
ARRIVAL_DURATION_SECONDS = 60
CHART_SIZE = (16, 9)
CHART_DPI = 100


@dataclass(frozen=True)
class VuRun:
    label: str
    vus: int
    run: int
    p95_ms: float
    average_ms: float
    requests_per_second: float
    error_rate: float


@dataclass(frozen=True)
class ArrivalRun:
    label: str
    peak: int
    run: int
    p95_ms: float
    average_ms: float
    error_rate: float
    dropped_count: float
    dropped_rate: float
    max_vus: float
    request_count: float
    achieved_rps: float


def metric(
    summary: dict,
    name: str,
    *keys: str,
    default: float | None = None,
) -> float:
    value: object = summary.get("metrics", {}).get(name, {})
    for key in keys:
        if not isinstance(value, dict) or key not in value:
            if default is not None:
                return default
            raise ValueError(f"Missing k6 metric field: {name}.{'.'.join(keys)}")
        value = value[key]
    if not isinstance(value, (int, float)):
        if default is not None:
            return default
        raise ValueError(f"Non-numeric k6 metric field: {name}.{'.'.join(keys)}")
    return float(value)


def expected_arrivals(peak: int) -> float:
    quarter_rate = math.ceil(peak * 0.25)
    return (
        ((5 + quarter_rate) / 2 * 20)
        + ((quarter_rate + peak) / 2 * 5)
        + (peak * 30)
        + (peak / 2 * 5)
    )


def read_summaries() -> tuple[list[VuRun], list[ArrivalRun]]:
    vu_runs = []
    arrival_runs = []
    if not RESULTS_DIR.exists():
        return vu_runs, arrival_runs

    for path in sorted(RESULTS_DIR.glob("*.json")):
        arrival_match = ARRIVAL_PATTERN.fullmatch(path.name)
        vu_match = VU_PATTERN.fullmatch(path.name)
        if arrival_match is None and vu_match is None:
            continue

        summary = json.loads(path.read_text(encoding="utf-8"))
        if arrival_match is not None:
            label = arrival_match.group("label")
            peak = int(arrival_match.group("peak"))
            dropped = metric(
                summary, "dropped_iterations", "count", default=-1.0
            )
            if dropped < 0:
                dropped = metric(
                    summary, "dropped_iterations", "value", default=0.0
                )
            expected = expected_arrivals(peak)
            requests = metric(summary, "http_reqs", "count")
            arrival_runs.append(
                ArrivalRun(
                    label=label,
                    peak=peak,
                    run=int(arrival_match.group("run")),
                    p95_ms=metric(summary, "http_req_duration", "p(95)"),
                    average_ms=metric(summary, "http_req_duration", "avg"),
                    error_rate=metric(summary, "http_req_failed", "value"),
                    dropped_count=dropped,
                    dropped_rate=(dropped / expected) if expected else 0.0,
                    max_vus=metric(summary, "vus_max", "max"),
                    request_count=requests,
                    achieved_rps=requests / ARRIVAL_DURATION_SECONDS,
                )
            )
            continue

        if vu_match is not None:
            vu_runs.append(
                VuRun(
                    label=vu_match.group("label"),
                    vus=int(vu_match.group("vus")),
                    run=int(vu_match.group("run")),
                    p95_ms=metric(summary, "http_req_duration", "p(95)"),
                    average_ms=metric(summary, "http_req_duration", "avg"),
                    requests_per_second=metric(summary, "http_reqs", "rate"),
                    error_rate=metric(summary, "http_req_failed", "value"),
                )
            )

    vu_runs.sort(key=lambda item: (item.label, item.vus, item.run))
    arrival_runs.sort(key=lambda item: (item.label, item.peak, item.run))
    return vu_runs, arrival_runs


def median(values: list[float]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def grouped_medians(
    runs: list[VuRun] | list[ArrivalRun], rate_name: str
) -> dict[tuple[str, int], dict[str, float]]:
    grouped: dict[tuple[str, int], list[VuRun | ArrivalRun]] = defaultdict(list)
    for run in runs:
        grouped[(run.label, getattr(run, rate_name))].append(run)

    fields = (
        ("p95_ms", "p95_ms"),
        ("average_ms", "average_ms"),
        ("error_rate", "error_rate"),
    )
    if rate_name == "vus":
        fields += (("requests_per_second", "requests_per_second"),)
    else:
        fields += (
            ("dropped_count", "dropped_count"),
            ("dropped_rate", "dropped_rate"),
            ("max_vus", "max_vus"),
            ("achieved_rps", "achieved_rps"),
        )
    return {
        key: {
            output: median([getattr(run, attribute) for run in values])
            for output, attribute in fields
        }
        for key, values in grouped.items()
    }


def machine_footer() -> str:
    readme = RESULTS_DIR / "README.md"
    content = readme.read_text(encoding="utf-8") if readme.exists() else ""
    match = MACHINE_PATTERN.search(content)
    machine = match.group(1).strip() if match else "Machine specifications not recorded"
    return f"{machine} | {datetime.now().astimezone():%Y-%m-%d}"


def label_color(label: str, fallback_index: int) -> str:
    normalized = label.lower()
    if "baseline" in normalized or "naive" in normalized:
        return "#667085"
    if "optimized" in normalized or "optimised" in normalized:
        return "#16803c"
    if "replica" in normalized:
        return "#2563eb"
    if "cache" in normalized:
        return "#0f766e"
    if "gateway" in normalized:
        return "#7c3aed"
    return matplotlib.colors.to_hex(plt.get_cmap("tab10").colors[fallback_index % 10])


def style_axis(ax: plt.Axes) -> None:
    ax.set_facecolor("#f7f9fc")
    ax.grid(True, color="#d9e1ec", linewidth=0.8)
    ax.spines[["top", "right"]].set_visible(False)
    ax.spines[["left", "bottom"]].set_color("#8996a8")
    ax.tick_params(colors="#344054", labelsize=12)
    ax.xaxis.label.set_color("#344054")
    ax.yaxis.label.set_color("#344054")
    ax.title.set_fontsize(20)
    ax.xaxis.label.set_size(15)
    ax.yaxis.label.set_size(15)


def save_chart(fig: plt.Figure, name: str, footer: str) -> None:
    fig.text(0.5, 0.025, footer, ha="center", va="bottom", fontsize=11, color="#536174")
    fig.tight_layout(rect=(0.06, 0.07, 0.97, 0.96))
    fig.savefig(CHARTS_DIR / name, dpi=CHART_DPI, facecolor="white")
    plt.close(fig)


def render_vu_charts(medians: dict[tuple[str, int], dict[str, float]]) -> None:
    if not medians:
        return

    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    labels = sorted({label for label, _ in medians})
    footer = machine_footer()

    fig, ax = plt.subplots(figsize=CHART_SIZE)
    for index, label in enumerate(labels):
        vus = sorted(vu for run_label, vu in medians if run_label == label)
        ax.plot(
            vus,
            [medians[(label, vu)]["p95_ms"] for vu in vus],
            marker="o",
            linewidth=2.8,
            markersize=8,
            label=label,
            color=label_color(label, index),
        )
    p95_values = [values["p95_ms"] for values in medians.values() if values["p95_ms"] > 0]
    if p95_values and max(p95_values) / min(p95_values) > 10:
        ax.set_yscale("log")
    ax.set(
        title="VU baseline: p95 latency",
        xlabel="Virtual users (VUs)",
        ylabel="Median p95 latency (ms)",
    )
    style_axis(ax)
    ax.legend(title="Run label", fontsize=12)
    save_chart(fig, "p95-latency.png", footer)

    fig, ax = plt.subplots(figsize=CHART_SIZE)
    for index, label in enumerate(labels):
        vus = sorted(vu for run_label, vu in medians if run_label == label)
        ax.plot(
            vus,
            [medians[(label, vu)]["requests_per_second"] for vu in vus],
            marker="o",
            linewidth=2.8,
            markersize=8,
            label=label,
            color=label_color(label, index),
        )
    ax.set(
        title="VU baseline: throughput",
        xlabel="Virtual users (VUs)",
        ylabel="Requests per second (req/s)",
    )
    style_axis(ax)
    ax.legend(title="Run label", fontsize=12)
    save_chart(fig, "throughput.png", footer)

    fig, ax = plt.subplots(figsize=CHART_SIZE)
    ax.axis("off")
    rows = [
        [
            label,
            str(vus),
            f"{values['p95_ms']:.1f}",
            f"{values['average_ms']:.1f}",
            f"{values['requests_per_second']:.2f}",
            f"{100 * values['error_rate']:.3f}%",
        ]
        for (label, vus), values in sorted(medians.items())
    ]
    table = ax.table(
        cellText=rows,
        colLabels=["Label", "VUs", "Median p95 (ms)", "Median avg (ms)", "Req/s", "Errors"],
        loc="center",
        cellLoc="center",
    )
    style_table(table, font_size=14)
    ax.set_title("VU baseline summary (median per label and VU count)", fontsize=20, pad=25)
    save_chart(fig, "summary-table.png", footer)


def style_table(table: matplotlib.table.Table, font_size: int) -> None:
    table.auto_set_font_size(False)
    table.set_fontsize(font_size)
    table.scale(1.0, 1.9)
    for (row, _), cell in table.get_celld().items():
        cell.set_edgecolor("#d0d5dd")
        if row == 0:
            cell.set_facecolor("#e8eef6")
            cell.set_text_props(weight="bold", color="#1d2939")
        else:
            cell.set_facecolor("#ffffff" if row % 2 else "#f7f9fc")
            cell.set_text_props(color="#344054")


def render_arrival_charts(medians: dict[tuple[str, int], dict[str, float]]) -> None:
    if not medians:
        return

    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    labels = sorted({label for label, _ in medians})
    footer = machine_footer()
    rates_by_label = {
        label: sorted(rate for run_label, rate in medians if run_label == label)
        for label in labels
    }

    fig, ax = plt.subplots(figsize=CHART_SIZE)
    for index, label in enumerate(labels):
        rates = rates_by_label[label]
        ax.plot(
            rates,
            [medians[(label, rate)]["p95_ms"] for rate in rates],
            marker="o",
            linewidth=2.8,
            markersize=8,
            label=label,
            color=label_color(label, index),
        )
    ax.set(
        title="Arrival-rate load: p95 latency",
        xlabel="Target peak request rate (req/s)",
        ylabel="Median p95 latency (ms)",
    )
    style_axis(ax)
    ax.legend(title="Run label", fontsize=12)
    save_chart(fig, "arrival-p95.png", footer)

    fig, ax = plt.subplots(figsize=CHART_SIZE)
    for index, label in enumerate(labels):
        rates = rates_by_label[label]
        color = label_color(label, index)
        ax.plot(
            rates,
            [100 * medians[(label, rate)]["error_rate"] for rate in rates],
            marker="o",
            linewidth=2.5,
            color=color,
            label=f"{label} errors",
        )
        ax.plot(
            rates,
            [100 * medians[(label, rate)]["dropped_rate"] for rate in rates],
            marker="x",
            linestyle="--",
            linewidth=2.5,
            color=color,
            label=f"{label} dropped iterations",
        )
    ax.set(
        title="Arrival-rate load: errors and dropped iterations",
        xlabel="Target peak request rate (req/s)",
        ylabel="Median rate (%)",
    )
    style_axis(ax)
    ax.legend(fontsize=11)
    save_chart(fig, "arrival-errors.png", footer)

    fig, ax = plt.subplots(figsize=CHART_SIZE)
    all_rates = sorted({rate for _, rate in medians})
    ax.plot(all_rates, all_rates, color="#667085", linestyle=":", linewidth=2.5, label="Ideal")
    for index, label in enumerate(labels):
        rates = rates_by_label[label]
        ax.plot(
            rates,
            [medians[(label, rate)]["achieved_rps"] for rate in rates],
            marker="o",
            linewidth=2.8,
            markersize=8,
            label=label,
            color=label_color(label, index),
        )
    ax.set(
        title="Arrival-rate load: achieved throughput",
        xlabel="Target peak request rate (req/s)",
        ylabel=f"Achieved throughput (req/s; requests / {ARRIVAL_DURATION_SECONDS} s)",
    )
    style_axis(ax)
    ax.legend(title="Run label", fontsize=12)
    save_chart(fig, "arrival-achieved.png", footer)

    fig, ax = plt.subplots(figsize=CHART_SIZE)
    ax.axis("off")
    rows = [
        [
            label,
            str(rate),
            f"{values['p95_ms']:.1f}",
            f"{values['average_ms']:.1f}",
            f"{100 * values['error_rate']:.2f}%",
            f"{100 * values['dropped_rate']:.2f}%",
            f"{values['max_vus']:.0f}",
        ]
        for (label, rate), values in sorted(medians.items())
    ]
    table = ax.table(
        cellText=rows,
        colLabels=[
            "Label",
            "Peak req/s",
            "Median p95 (ms)",
            "Median avg (ms)",
            "Errors",
            "Dropped",
            "Max VUs",
        ],
        loc="center",
        cellLoc="center",
    )
    style_table(table, font_size=13)
    ax.set_title("Arrival-rate summary (median per label and peak)", fontsize=20, pad=25)
    save_chart(fig, "arrival-summary-table.png", footer)


def render_hikari_chart() -> None:
    csv_path = RESULTS_DIR / "hikari-100.csv"
    if not csv_path.exists():
        return

    elapsed = []
    pending = []
    active = []
    start_time = None
    with csv_path.open(newline="", encoding="utf-8-sig") as csv_file:
        for index, row in enumerate(csv.DictReader(csv_file)):
            try:
                timestamp = datetime.fromisoformat(row["timestamp"])
                if start_time is None:
                    start_time = timestamp
                elapsed.append((timestamp - start_time).total_seconds())
                pending.append(float(row["pending"]))
                active.append(float(row["active"]))
            except (KeyError, ValueError) as error:
                raise ValueError(f"Invalid Hikari observation row {index + 2} in {csv_path}") from error
    if not elapsed:
        raise ValueError(f"No Hikari samples found in {csv_path}")

    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=CHART_SIZE)
    ax.plot(elapsed, pending, linewidth=2.8, label="Pending connections", color="#dc2626")
    ax.plot(elapsed, active, linewidth=2.8, label="Active connections", color="#2563eb")
    ax.set(
        title="HikariCP connection activity during 100-VU run",
        xlabel="Elapsed time (seconds)",
        ylabel="Connections (count)",
    )
    style_axis(ax)
    ax.legend(fontsize=12)
    save_chart(fig, "hikari.png", machine_footer())


def write_summary(
    vu_medians: dict[tuple[str, int], dict[str, float]],
    arrival_medians: dict[tuple[str, int], dict[str, float]],
) -> None:
    lines = [
        "# Load Test Summary",
        "",
        f"Generated: {datetime.now().astimezone():%Y-%m-%d %H:%M:%S %Z}",
        "",
        "## VU baseline",
        "",
        "Values are medians across matching `-run<i>.json` files. Latencies are milliseconds; errors are percentages.",
        "",
        "| Label | VUs | Median p95 (ms) | Median avg (ms) | Requests/s | Error rate |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for (label, vus), values in sorted(vu_medians.items()):
        lines.append(
            f"| {label} | {vus} | {values['p95_ms']:.2f} | {values['average_ms']:.2f} "
            f"| {values['requests_per_second']:.2f} | {100 * values['error_rate']:.3f}% |"
        )
    if not vu_medians:
        lines.append("| _No VU run files found._ | | | | | |")

    lines.extend(
        [
            "",
            "## Arrival-rate runs",
            "",
            f"Values are medians across matching `-arrival-<P>-run<i>.json` files. Achieved throughput is `http_reqs.count / {ARRIVAL_DURATION_SECONDS} seconds`; dropped-iteration percentage uses expected arrivals from the configured rate stages.",
            "",
            "| Label | Peak req/s | Median p95 (ms) | Median avg (ms) | Error rate | Dropped iterations | Max VUs |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ]
    )
    for (label, peak), values in sorted(arrival_medians.items()):
        lines.append(
            f"| {label} | {peak} | {values['p95_ms']:.2f} | {values['average_ms']:.2f} "
            f"| {100 * values['error_rate']:.3f}% | {100 * values['dropped_rate']:.3f}% "
            f"({values['dropped_count']:.0f}) | {values['max_vus']:.0f} |"
        )
    if not arrival_medians:
        lines.append("| _No arrival-rate run files found._ | | | | | | |")

    (RESULTS_DIR / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    vu_runs, arrival_runs = read_summaries()
    vu_medians = grouped_medians(vu_runs, "vus")
    arrival_medians = grouped_medians(arrival_runs, "peak")

    write_summary(vu_medians, arrival_medians)
    render_vu_charts(vu_medians)
    render_arrival_charts(arrival_medians)
    render_hikari_chart()
    print(
        f"Wrote summary for {len(vu_runs)} VU runs and "
        f"{len(arrival_runs)} arrival-rate runs."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
