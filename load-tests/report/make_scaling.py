#!/usr/bin/env python3
"""Render scaling comparison charts: 1 vs 2 vs 3 read-service instances."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[2]
RESULTS_DIR = ROOT / "load-tests" / "results"
RAW_DIR = RESULTS_DIR / "optimized" / "raw"
OUTPUT_DIR = RESULTS_DIR / "comparison"

INSTANCE_CONFIGS = {
    "stress-1inst": {"label": "1 instance (stress)", "color": "#ef4444"},
    "stress-2inst": {"label": "2 instances (stress)", "color": "#f59e0b"},
    "stress-3inst": {"label": "3 instances (stress)", "color": "#16a34a"},
    "scale-1inst": {"label": "1 instance", "color": "#ef4444"},
    "scale-2inst": {"label": "2 instances", "color": "#f59e0b"},
    "scale-3inst": {"label": "3 instances", "color": "#16a34a"},
}

RUN_PATTERN = re.compile(
    r"^(?P<label>(?:stress|scale)-\dinst)-(?P<mode>hot|uniform)-arrival-"
    r"(?P<peak>\d+)-run(?P<run>\d+)\.json$"
)


@dataclass(frozen=True)
class Run:
    config: str
    mode: str
    peak: int
    run: int
    p95_s: float
    average_s: float
    dropped_pct: float
    delivered_pct: float


def median(values: list[float]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def metric(summary: dict, name: str, *keys: str, default: float | None = None) -> float:
    metrics = summary.get("metrics")
    if not isinstance(metrics, dict):
        if default is not None:
            return default
        raise ValueError("Missing metrics object in k6 summary")
    value = metrics.get(name)
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
    quarter_rate = (peak + 3) // 4
    return (
        ((5 + quarter_rate) / 2 * 20)
        + ((quarter_rate + peak) / 2 * 5)
        + (peak * 30)
        + (peak / 2 * 5)
    )


def read_runs(mode: str) -> list[Run]:
    if not RAW_DIR.exists():
        raise FileNotFoundError(f"Missing raw-results directory: {RAW_DIR}")
    runs = []
    for path in sorted(RAW_DIR.glob("*inst-*-arrival-*-run*.json")):
        match = RUN_PATTERN.fullmatch(path.name)
        if match is None or match.group("mode") != mode:
            continue
        config = match.group("label")
        if config not in INSTANCE_CONFIGS:
            continue
        summary = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(summary, dict):
            raise ValueError(f"Invalid k6 JSON summary: {path}")
        peak = int(match.group("peak"))
        dropped = metric(summary, "dropped_iterations", "count", default=-1.0)
        if dropped < 0:
            dropped = metric(summary, "dropped_iterations", "value", default=0.0)
        completed = metric(summary, "iterations", "count", default=-1.0)
        if completed < 0:
            completed = metric(summary, "http_reqs", "count")
        total = completed + dropped
        runs.append(
            Run(
                config=config,
                mode=mode,
                peak=peak,
                run=int(match.group("run")),
                p95_s=metric(summary, "http_req_duration", "p(95)") / 1000,
                average_s=metric(summary, "http_req_duration", "avg") / 1000,
                dropped_pct=100 * dropped / expected_arrivals(peak),
                delivered_pct=100 * completed / total if total else 0.0,
            )
        )
    if not runs:
        raise ValueError(f"No scaling runs found in {RAW_DIR}")
    return runs


def group_runs(runs: list[Run]) -> dict[tuple[str, int], list[Run]]:
    grouped: dict[tuple[str, int], list[Run]] = {}
    for run in runs:
        grouped.setdefault((run.config, run.peak), []).append(run)
    return grouped


def summarize(grouped: dict[tuple[str, int], list[Run]]) -> dict[tuple[str, int], dict[str, float]]:
    fields = ("p95_s", "average_s", "dropped_pct", "delivered_pct")
    return {
        key: {field: median([getattr(r, field) for r in values]) for field in fields}
        for key, values in grouped.items()
    }


def footer() -> str:
    readme_path = RESULTS_DIR / "machine.md"
    try:
        readme = readme_path.read_text(encoding="utf-8")
        machine_match = re.search(r"^- Machine:\s*(.+)$", readme, re.MULTILINE)
        machine = machine_match.group(1).strip() if machine_match else "Machine info not recorded"
    except FileNotFoundError:
        machine = "Machine info not recorded"
    return f"{machine} | Median of 3 runs, single laptop | {date.today():%Y-%m-%d}"


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


def render_chart(
    mode: str,
    grouped: dict[tuple[str, int], list[Run]],
    medians: dict[tuple[str, int], dict[str, float]],
    field: str,
    title: str,
    ylabel: str,
    filename: str,
) -> None:
    fig, ax = plt.subplots(figsize=(16, 9))
    for config, style in INSTANCE_CONFIGS.items():
        peaks = sorted(peak for c, peak in medians if c == config)
        if not peaks:
            continue
        color = style["color"]
        for peak in peaks:
            if (config, peak) in grouped:
                values = grouped[(config, peak)]
                ax.scatter(
                    [peak] * len(values),
                    [getattr(r, field) for r in values],
                    color=color, alpha=0.25, s=48, edgecolors="none", zorder=2,
                )
        ax.plot(
            peaks,
            [medians[(config, peak)][field] for peak in peaks],
            color=color, marker="o", linewidth=2.8, markersize=8,
            label=style["label"], zorder=3,
        )

    ax.set(
        title=f"Scaling ({mode} mode): {title}",
        xlabel="Peak arrival rate (req/s)",
        ylabel=ylabel,
        xlim=(0, None),
        ylim=(0, None),
    )
    style_axis(ax)
    ax.legend(title="Instances", fontsize=12)
    fig.text(0.5, 0.025, footer(), ha="center", va="bottom", fontsize=10, color="#536174", wrap=True)
    fig.tight_layout(rect=(0.05, 0.08, 0.98, 0.96))
    fig.savefig(OUTPUT_DIR / filename, dpi=100, facecolor="white", bbox_inches="tight", pad_inches=0.12)
    plt.close(fig)


def render_table(mode: str, medians: dict[tuple[str, int], dict[str, float]]) -> None:
    fig, ax = plt.subplots(figsize=(14, 6))
    ax.axis("off")
    rows = []
    row_colors = []
    color_map = {
        "scale-1inst": "#fef2f2",
        "scale-2inst": "#fffbeb",
        "scale-3inst": "#ecfdf3",
    }
    for config in INSTANCE_CONFIGS:
        for (c, peak), vals in sorted(medians.items(), key=lambda x: x[0][1]):
            if c != config:
                continue
            rows.append([
                INSTANCE_CONFIGS[config]["label"],
                str(peak),
                f"{vals['p95_s']:.2f}",
                f"{vals['average_s']:.2f}",
                f"{vals['dropped_pct']:.3f}",
                f"{vals['delivered_pct']:.2f}",
            ])
            row_colors.append(color_map.get(config, "#ffffff"))

    table = ax.table(
        cellText=rows,
        colLabels=["Instances", "Peak req/s", "Median p95 (s)", "Median avg (s)", "Dropped (%)", "Delivered (%)"],
        loc="center", cellLoc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(12)
    table.auto_set_column_width(list(range(6)))
    table.scale(1.0, 1.8)
    for (row, col), cell in table.get_celld().items():
        cell.set_edgecolor("#d0d5dd")
        if row == 0:
            cell.set_facecolor("#e8eef6")
            cell.set_text_props(weight="bold", color="#1d2939")
        elif row_colors:
            cell.set_facecolor(row_colors[row - 1])
            cell.set_text_props(color="#344054")
    ax.set_title(f"Scaling ({mode} mode): median comparison table", fontsize=19, pad=24)
    fig.text(0.5, 0.025, footer(), ha="center", va="bottom", fontsize=10, color="#536174")
    fig.tight_layout(rect=(0.03, 0.12, 0.97, 0.9))
    fig.savefig(
        OUTPUT_DIR / f"scaling-{mode}-summary-table.png",
        dpi=100, facecolor="white", bbox_inches="tight", pad_inches=0.12,
    )
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate scaling comparison charts.")
    parser.add_argument("--mode", default="hot", choices=["hot", "uniform"])
    args = parser.parse_args()
    mode = args.mode

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    runs = read_runs(mode)
    grouped = group_runs(runs)
    medians = summarize(grouped)

    if not medians:
        raise ValueError(f"No {mode} scaling runs found")

    render_chart(mode, grouped, medians, "p95_s", "p95 latency", "Median p95 latency (seconds)", f"scaling-{mode}-p95.png")
    render_chart(mode, grouped, medians, "average_s", "average latency", "Median average latency (seconds)", f"scaling-{mode}-average.png")
    render_chart(mode, grouped, medians, "delivered_pct", "delivered arrivals", "Median delivered arrivals (%)", f"scaling-{mode}-delivered.png")
    render_table(mode, medians)

    print(f"Wrote 4 scaling charts to {OUTPUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
