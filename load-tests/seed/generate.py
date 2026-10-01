#!/usr/bin/env python3
"""Generate deterministic synthetic OU-style result data."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
import re
import sys
from collections import defaultdict
from pathlib import Path

try:
    import bcrypt
except ImportError as exc:
    raise SystemExit("Missing bcrypt. Install it with: python -m pip install bcrypt") from exc

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "out"
SHARD_MAP = ROOT / "contracts" / "shard-map.yml"
EXAM = "2026-jul-aug"
UPLOADED_AT = "2026-09-19T00:00:00Z"
PASSWORD = "OU-Demo-Password-2026"
SALT = b"$2b$12$abcdefghijklmnopqrstuu"
COLLEGES = ["1604", "1605", "1606", "1607", "1608", "1609", "1610", "1611", "1612"]
BATCHES = [23, 24, 25]
DEPTS = ["733", "734", "735", "736", "737"]
SEMESTER = {23: 6, 24: 4, 25: 2}
FIRST = ["AARIN", "BELA", "CHETAN", "DARA", "ELI", "FARAH", "GIRISH", "HEERA", "ISHAN", "JAYA"]
FATHER = ["AMAN", "BHAVAN", "CHANDRA", "DEV", "EKANSH", "FAIZ", "GOVIND", "HARISH", "IMRAN", "JITEN"]
GENDERS = ["MALE", "FEMALE"]
GRADES = ["S", "A", "B", "C"]
GRADE_WEIGHTS = [8, 24, 34, 34]
GRADE_POINTS = {"S": 10, "A": 9, "B": 8, "C": 7, "F": 0}
RESULT_COLUMNS = [
    "exam_id", "roll_no", "semester", "college_code", "batch_year", "dept_code",
    "name", "father_name", "gender", "course", "medium", "subjects",
    "result_status", "sgpa", "cgpa", "published", "uploaded_at",
]


def subject_catalog(dept: str, semester: int) -> list[dict[str, object]]:
    return [
        {"code": f"{semester:02d}{dept[-1]}{i}",
         "name": f"DEPARTMENT {dept[-1]} SEMESTER {semester} SUBJECT {i}",
         "credits": 3 if i < 5 else 2}
        for i in range(1, 7)
    ]


def roll_no(college: str, batch: int, dept: str, number: int) -> str:
    return f"{college}{batch:02d}{dept}{number:03d}"


def group_sizes(rng: random.Random) -> dict[str, list[int]]:
    # Four larger and five smaller colleges let whole-college shards balance near 50/50.
    return {
        college: [center + rng.randint(-18, 18) for _ in range(15)]
        for index, college in enumerate(COLLEGES)
        for center in [820 if index < 4 else 656]
    }


def assign_shards(sizes: dict[str, list[int]]) -> dict[str, str]:
    totals = {"shard1": 0, "shard2": 0}
    assignment = {}
    college_counts = {college: sum(groups) for college, groups in sizes.items()}
    for college, count in sorted(college_counts.items(), key=lambda item: (-item[1], item[0])):
        shard = min(totals, key=totals.get)
        assignment[college] = shard
        totals[shard] += count
    while True:
        current_difference = abs(totals["shard1"] - totals["shard2"])
        best_assignment = None
        best_difference = current_difference
        colleges = list(assignment)
        for college in colleges:
            source = assignment[college]
            destination = "shard2" if source == "shard1" else "shard1"
            if sum(1 for value in assignment.values() if value == source) > 1:
                candidate_totals = dict(totals)
                candidate_totals[source] -= college_counts[college]
                candidate_totals[destination] += college_counts[college]
                difference = abs(candidate_totals["shard1"] - candidate_totals["shard2"])
                if difference < best_difference:
                    best_difference = difference
                    best_assignment = (college, None, candidate_totals)
            for other in colleges:
                if assignment[other] == source:
                    continue
                candidate_totals = dict(totals)
                candidate_totals[source] += college_counts[other] - college_counts[college]
                candidate_totals[destination] += college_counts[college] - college_counts[other]
                difference = abs(candidate_totals["shard1"] - candidate_totals["shard2"])
                if difference < best_difference:
                    best_difference = difference
                    best_assignment = (college, other, candidate_totals)
        if best_assignment is None:
            break
        college, other, totals = best_assignment
        source = assignment[college]
        destination = "shard2" if source == "shard1" else "shard1"
        assignment[college] = destination
        if other is not None:
            assignment[other] = source
    imbalance = abs(totals["shard1"] - totals["shard2"]) / (
        (totals["shard1"] + totals["shard2"]) / 2
    )
    if imbalance > 0.10:
        raise RuntimeError(f"Greedy shard assignment exceeds 10% of the average: {totals} ({imbalance:.1%})")
    return assignment


def create_result(
    rng: random.Random, college: str, batch: int, dept: str, number: int,
    semester: int, published: bool, backlog: bool = False,
) -> dict[str, object]:
    count = rng.randint(1, 2) if backlog else 6
    catalog = subject_catalog(dept, semester)[:count]
    force_failure = not backlog and rng.random() < 0.05
    fail_index = rng.randrange(count) if force_failure else -1
    result_subjects = []
    points = 0
    credits = 0
    failed = False
    for i, item in enumerate(catalog):
        grade = "F" if i == fail_index else rng.choices(GRADES, weights=GRADE_WEIGHTS, k=1)[0]
        result_subjects.append({**item, "grade": grade})
        points += int(item["credits"]) * GRADE_POINTS[grade]
        credits += int(item["credits"])
        failed = failed or grade == "F"
    person = int(hashlib.sha256(roll_no(college, batch, dept, number).encode()).hexdigest(), 16)
    return {
        "exam_id": EXAM, "roll_no": roll_no(college, batch, dept, number),
        "semester": semester, "college_code": college, "batch_year": batch,
        "dept_code": dept, "name": f"{FIRST[person % len(FIRST)]} STUDENT",
        "father_name": f"{FATHER[(person // 7) % len(FATHER)]} PARENT",
        "gender": GENDERS[(person // 13) % 2], "course": "B.E. (AICTE)",
        "medium": "ENGLISH", "subjects": json.dumps(result_subjects, separators=(",", ":")),
        "result_status": "FAILED" if failed else "PASSED",
        "sgpa": f"{points / credits:.2f}", "cgpa": "",
        "published": str(published).lower(), "uploaded_at": UPLOADED_AT,
    }


def write_csv(path: Path, columns: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_schemas() -> None:
    shard_schema = """\
CREATE TABLE IF NOT EXISTS exams (
    exam_id text PRIMARY KEY,
    title text NOT NULL,
    result_date date NOT NULL,
    publish_status text NOT NULL CHECK (publish_status IN ('DRAFT', 'PUBLISHING', 'SHARDS_PUBLISHED', 'PUBLISHED', 'FAILED'))
);
CREATE TABLE IF NOT EXISTS results (
    exam_id text NOT NULL REFERENCES exams (exam_id),
    roll_no text NOT NULL CHECK (roll_no ~ '^[0-9]{12}$'),
    semester smallint NOT NULL,
    college_code text NOT NULL,
    batch_year smallint NOT NULL,
    dept_code text NOT NULL,
    name text NOT NULL,
    father_name text NOT NULL,
    gender text NOT NULL,
    course text NOT NULL,
    medium text NOT NULL,
    subjects jsonb NOT NULL,
    result_status text NOT NULL CHECK (result_status IN ('PASSED', 'FAILED')),
    sgpa numeric(4,2) NOT NULL,
    cgpa numeric(4,2),
    published boolean NOT NULL DEFAULT false,
    uploaded_at timestamptz NOT NULL,
    PRIMARY KEY (exam_id, roll_no, semester)
);
CREATE INDEX IF NOT EXISTS idx_results_roll_exam_semester
    ON results (roll_no, exam_id, semester DESC);
"""
    account_schema = """\
CREATE TABLE IF NOT EXISTS student_credentials (
    roll_no text PRIMARY KEY CHECK (roll_no ~ '^[0-9]{12}$'),
    password_hash text NOT NULL
);
CREATE TABLE IF NOT EXISTS registrations (
    roll_no text PRIMARY KEY REFERENCES student_credentials (roll_no),
    email text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
"""
    (OUT / "schema_shard.sql").write_text(shard_schema, encoding="utf-8")
    (OUT / "schema_account.sql").write_text(account_schema, encoding="utf-8")


def generate(args: argparse.Namespace) -> None:
    rng = random.Random(args.seed)
    sizes = group_sizes(rng)
    assignment = assign_shards(sizes)
    OUT.mkdir(parents=True, exist_ok=True)
    write_schemas()

    SHARD_MAP.parent.mkdir(parents=True, exist_ok=True)
    SHARD_MAP.write_text(
        "colleges:\n" + "".join(f'  "{college}": {assignment[college]}\n' for college in COLLEGES),
        encoding="utf-8",
    )
    password_hash = bcrypt.hashpw(PASSWORD.encode(), SALT).decode()
    rows: dict[str, list[dict[str, object]]] = defaultdict(list)
    credentials = []
    upload_rows = []
    groups = []
    for college in COLLEGES:
        group_index = 0
        for batch in BATCHES:
            for dept in DEPTS:
                size = sizes[college][group_index]
                group_index += 1
                groups.append({
                    "college_code": college, "shard": assignment[college],
                    "batch_year": batch, "dept_code": dept,
                    "semester": SEMESTER[batch], "roll_min": 1, "roll_max": size,
                })
                for number in range(1, size + 1):
                    rows[assignment[college]].append(
                        create_result(rng, college, batch, dept, number, SEMESTER[batch], not args.unpublished)
                    )
                    credentials.append({"roll_no": roll_no(college, batch, dept, number),
                                        "password_hash": password_hash})
                    if number % 20 == 0:
                        previous = max(1, SEMESTER[batch] - rng.randint(1, min(2, SEMESTER[batch] - 1)))
                        rows[assignment[college]].append(
                            create_result(rng, college, batch, dept, number, previous,
                                          not args.unpublished, backlog=True)
                        )
                for number in range(901, 1000):
                    upload_rows.append(
                        create_result(rng, college, batch, dept, number, SEMESTER[batch], False)
                    )

    for shard in ("shard1", "shard2"):
        write_csv(OUT / f"results_{shard}.csv", RESULT_COLUMNS, rows[shard])
    keys = set()
    seeded_rolls = set()
    for shard_rows in rows.values():
        for row in shard_rows:
            if not re.fullmatch(r"\d{12}", str(row["roll_no"])):
                raise RuntimeError(f"Invalid generated roll number: {row['roll_no']}")
            seeded_rolls.add(row["roll_no"])
            key = (row["exam_id"], row["roll_no"], row["semester"])
            if key in keys:
                raise RuntimeError(f"Duplicate result key: {key}")
            keys.add(key)
    generated_rolls = [row["roll_no"] for row in credentials]
    if args.upload_sample is not None:
        generated_rolls.extend(row["roll_no"] for row in upload_rows[:args.upload_sample])
    if not all(re.fullmatch(r"\d{12}", roll) for roll in generated_rolls):
        raise RuntimeError("Invalid roll number in credentials or upload sample")
    if any(row["roll_no"] in seeded_rolls for row in upload_rows[:args.upload_sample or 0]):
        raise RuntimeError("Upload sample overlaps a seeded result roll number")
    shard_counts = {shard: len(shard_rows) for shard, shard_rows in rows.items()}
    imbalance = abs(shard_counts["shard1"] - shard_counts["shard2"]) / (
        sum(shard_counts.values()) / 2
    )
    if imbalance > 0.10:
        raise RuntimeError(f"Generated result rows exceed 10% shard imbalance: {shard_counts}")
    exam_columns = ["exam_id", "title", "result_date", "publish_status"]
    write_csv(OUT / "exams.csv", exam_columns, [{
        "exam_id": EXAM, "title": "B.E. RESULTS - JULY/AUGUST 2026",
        "result_date": "2026-09-19",
        "publish_status": "DRAFT" if args.unpublished else "PUBLISHED",
    }])
    write_csv(OUT / "credentials.csv", ["roll_no", "password_hash"], credentials)
    manifest = {
        "exam_id": EXAM, "published": not args.unpublished,
        "colleges": [{"code": c, "shard": assignment[c]} for c in COLLEGES],
        "batch_years": BATCHES, "department_codes": DEPTS, "groups": groups,
    }
    (OUT / "seed-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    if args.upload_sample is not None:
        sample_columns = RESULT_COLUMNS[:-2]
        sample = upload_rows[:args.upload_sample]
        write_csv(OUT / "upload-sample.csv", sample_columns, sample)
    print(f"Test password (shared synthetic password): {PASSWORD}")
    print(f"Seed files written to {OUT}")
    print(f"Rows: exams=1, credentials={len(credentials)}, shard1={shard_counts['shard1']}, "
          f"shard2={shard_counts['shard2']}, duplicate_keys=0")
    print(f"Roll numbers validated: {sum(shard_counts.values()) + len(generated_rolls)}")
    print(f"Shard row-count difference vs average: {imbalance:.1%}")
    if args.upload_sample is not None:
        print(f"Upload sample rows: {args.upload_sample}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=20260919)
    parser.add_argument("--unpublished", action="store_true")
    parser.add_argument("--upload-sample", type=int)
    args = parser.parse_args()
    if args.upload_sample is not None and not 5000 <= args.upload_sample <= 10000:
        parser.error("--upload-sample must be between 5000 and 10000")
    return args


if __name__ == "__main__":
    try:
        generate(parse_args())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Seed generation failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
