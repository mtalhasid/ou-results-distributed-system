#!/usr/bin/env python3
"""Render naive-versus-optimized arrival-rate comparisons from profile summaries."""

from __future__ import annotations

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
OUTPUT_DIR = RESULTS_DIR / "comparison"
PROFILE_COLORS = {"naive": "#2563eb", "optimized": "#16a34a"}
PROFILE_LABELS = {"naive": "Naive (session2)", "optimized": "Optimized"}
MODES = ("hot", "uniform")
RUN_PATTERN = re.compile(
    r"^(?P<label>[^-]+)-(?P<mode>hot|uniform)-arrival-"
    r"(?P<peak>\d+)-run(?P<run>\d+)\.json$"
)
TABLE_COLUMNS = (
    ("p95_s", "Median p95 (s)"),
    ("average_s", "Median avg (s)"),
    ("dropped_pct", "Dropped (%)"),
    ("delivered_pct", "Delivered (%)"),
)


@dataclass(frozen=True)
class Run:
    profile: str
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


def metric(
    summary: dict[str, object],
    name: str,
    *keys: str,
    default: float | None = None,
) -> float:
    metrics = summary.get("metrics")
    if not isinstance(metrics, dict):
        if default is not None:
            return default
        raise ValueError("Missing metrics object in k6 summary")
    value: object = metrics.get(name)
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


def read_profile_runs(profile: str, expected_label: str) -> list[Run]:
    raw_dir = RESULTS_DIR / profile / "raw"
    if not raw_dir.exists():
        raise FileNotFoundError(f"Missing profile raw-results directory: {raw_dir}")
    runs = []
    for path in sorted(raw_dir.glob("*-arrival-*-run*.json")):
        match = RUN_PATTERN.fullmatch(path.name)
        if match is None or match.group("label") != expected_label:
            continue
        summary: object = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(summary, dict):
            raise ValueError(f"Invalid k6 JSON summary: {path}")
        mode = match.group("mode")
        if mode not in MODES:
            continue
        peak = int(match.group("peak"))
        dropped = metric(summary, "dropped_iterations", "count", default=-1.0)
        if dropped < 0:
            dropped = metric(
                summary, "dropped_iterations", "value", default=0.0
            )
        completed = metric(summary, "iterations", "count", default=-1.0)
        if completed < 0:
            completed = metric(summary, "http_reqs", "count")
        completed_and_dropped = completed + dropped
        runs.append(
            Run(
                profile=profile,
                mode=mode,
                peak=peak,
                run=int(match.group("run")),
                p95_s=metric(summary, "http_req_duration", "p(95)") / 1000,
                average_s=metric(summary, "http_req_duration", "avg") / 1000,
                dropped_pct=100 * dropped / expected_arrivals(peak),
                delivered_pct=(
                    100 * completed / completed_and_dropped
                    if completed_and_dropped
                    else 0.0
                ),
            )
        )

    if not runs:
        raise ValueError(
            f"No raw arrival-rate runs labeled {expected_label!r} found in {raw_dir}"
        )
    return runs


def group_runs(runs: list[Run], mode: str) -> dict[tuple[str, int], list[Run]]:
    grouped: dict[tuple[str, int], list[Run]] = {}
    for run in runs:
        if run.mode == mode:
            grouped.setdefault((run.profile, run.peak), []).append(run)
    return grouped


def validate_groups(grouped: dict[tuple[str, int], list[Run]], mode: str) -> None:
    naive_peaks = {peak for profile, peak in grouped if profile == "naive"}
    optimized_peaks = {peak for profile, peak in grouped if profile == "optimized"}
    if not naive_peaks or naive_peaks != optimized_peaks:
        raise ValueError(f"{mode} mode must have matching peaks for both profiles")
    for key, values in grouped.items():
        if len(values) != 3:
            profile, peak = key
            raise ValueError(
                f"Expected 3 {profile} {mode} runs at {peak} req/s; found {len(values)}"
            )


def footer() -> str:
    readme_path = RESULTS_DIR / "naive" / "README.md"
    readme = readme_path.read_text(encoding="utf-8")
    machine_match = re.search(r"^- Machine:\s*(.+)$", readme, re.MULTILINE)
    machine = (
        machine_match.group(1).strip()
        if machine_match
        else "Machine specifications not recorded"
    )
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


def summarize(
    grouped: dict[tuple[str, int], list[Run]],
) -> dict[tuple[str, int], dict[str, float]]:
    return {
        key: {
            field: median([getattr(run, field) for run in values])
            for field, _ in TABLE_COLUMNS
        }
        for key, values in grouped.items()
    }


def render_metric_chart(
    mode: str,
    grouped: dict[tuple[str, int], list[Run]],
    medians: dict[tuple[str, int], dict[str, float]],
    field: str,
    title: str,
    ylabel: str,
    filename: str,
) -> None:
    fig, ax = plt.subplots(figsize=(16, 9))
    for profile in ("naive", "optimized"):
        peaks = sorted(peak for candidate, peak in medians if candidate == profile)
        color = PROFILE_COLORS[profile]
        for peak in peaks:
            values = grouped[(profile, peak)]
            ax.scatter(
                [peak] * len(values),
                [getattr(run, field) for run in values],
                color=color,
                alpha=0.25,
                s=48,
                edgecolors="none",
                zorder=2,
            )
        ax.plot(
            peaks,
            [medians[(profile, peak)][field] for peak in peaks],
            color=color,
            marker="o",
            linewidth=2.8,
            markersize=8,
            label=PROFILE_LABELS[profile],
            zorder=3,
        )

    ax.set(
        title=f"{mode.title()} mode: {title}",
        xlabel="Peak arrival rate (req/s)",
        ylabel=ylabel,
        xlim=(0, None),
        ylim=(0, None),
    )
    style_axis(ax)
    ax.legend(title="Profile", fontsize=12)
    fig.text(
        0.5,
        0.025,
        footer(),
        ha="center",
        va="bottom",
        fontsize=10,
        color="#536174",
        wrap=True,
    )
    fig.tight_layout(rect=(0.05, 0.08, 0.98, 0.96))
    fig.savefig(OUTPUT_DIR / filename, dpi=100, facecolor="white", bbox_inches="tight", pad_inches=0.12)
    plt.close(fig)


def render_summary_table(
    mode: str, medians: dict[tuple[str, int], dict[str, float]]
) -> None:
    fig, ax = plt.subplots(figsize=(14, 5))
    ax.axis("off")
    rows = []
    row_colors = []
    for profile in ("naive", "optimized"):
        for (candidate, peak), values in sorted(medians.items(), key=lambda item: item[0][1]):
            if candidate != profile:
                continue
            rows.append(
                [
                    PROFILE_LABELS[profile],
                    str(peak),
                    f"{values['p95_s']:.2f}",
                    f"{values['average_s']:.2f}",
                    f"{values['dropped_pct']:.3f}",
                    f"{values['delivered_pct']:.2f}",
                ]
            )
            row_colors.append("#eff6ff" if profile == "naive" else "#ecfdf3")

    table = ax.table(
        cellText=rows,
        colLabels=[
            "Profile",
            "Peak req/s",
            "Median p95 (s)",
            "Median avg (s)",
            "Dropped (%)",
            "Delivered (%)",
        ],
        loc="center",
        cellLoc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(12)
    table.auto_set_column_width(list(range(6)))
    table.scale(1.0, 1.8)
    for (row, column), cell in table.get_celld().items():
        cell.set_edgecolor("#d0d5dd")
        if row == 0:
            cell.set_facecolor("#e8eef6")
            cell.set_text_props(weight="bold", color="#1d2939")
        elif row_colors:
            cell.set_facecolor(row_colors[row - 1])
            cell.set_text_props(color="#344054")
    ax.set_title(f"{mode.title()} mode: median comparison table", fontsize=19, pad=24)
    fig.text(0.5, 0.025, footer(), ha="center", va="bottom", fontsize=10, color="#536174")
    fig.tight_layout(rect=(0.03, 0.16, 0.97, 0.9))
    fig.savefig(
        OUTPUT_DIR / f"{mode}-summary-table.png",
        dpi=100,
        facecolor="white",
        bbox_inches="tight",
        pad_inches=0.12,
    )
    plt.close(fig)


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    runs = read_profile_runs("naive", "session2")
    runs.extend(read_profile_runs("optimized", "optimized"))
    for mode in MODES:
        grouped = group_runs(runs, mode)
        validate_groups(grouped, mode)
        medians = summarize(grouped)
        if not medians:
            raise ValueError(f"No {mode} runs found for both profiles")
        render_metric_chart(
            mode,
            grouped,
            medians,
            "p95_s",
            "p95 latency",
            "Median p95 latency (seconds)",
            f"{mode}-p95.png",
        )
        render_metric_chart(
            mode,
            grouped,
            medians,
            "average_s",
            "average latency",
            "Median average latency (seconds)",
            f"{mode}-average.png",
        )
        render_metric_chart(
            mode,
            grouped,
            medians,
            "delivered_pct",
            "delivered arrivals",
            "Median delivered arrivals (%)",
            f"{mode}-delivered.png",
        )
        render_summary_table(mode, medians)
    print(f"Wrote 8 comparison charts to {OUTPUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
