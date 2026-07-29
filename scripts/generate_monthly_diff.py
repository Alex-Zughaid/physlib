#!/usr/bin/env python3
"""
Generates a monthly-diffs/<YYYY-MM>.diff plain-text file (every commit made
in the given month on leanprover-community/physlib's default branch,
concatenated) plus an updated monthly-diffs/index.json summary (contributors,
total lines changed, diff filename) consumed by the physlib-website
"Monthly Updates" page.

Expects a git remote named "upstream" pointing at
https://github.com/leanprover-community/physlib.git to already be fetched.

Usage:
    python3 scripts/generate_monthly_diff.py [YYYY-MM]

With no argument, generates the previous calendar month (relative to today),
which is what the end-of-month scheduled workflow uses.
"""

import json
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "monthly-diffs"
INDEX_PATH = OUT_DIR / "index.json"
REF = "upstream/master"


def month_range(year: int, month: int) -> tuple[str, str]:
    start = date(year, month, 1)
    end = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    return start.isoformat(), end.isoformat()


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=REPO_ROOT, check=True, capture_output=True, text=True
    ).stdout


def previous_month(today: date) -> tuple[int, int]:
    if today.month == 1:
        return today.year - 1, 12
    return today.year, today.month - 1


def contributors(since: str, until: str) -> list[str]:
    names = git(
        "log", REF, f"--since={since}", f"--until={until}", "--format=%an"
    ).splitlines()
    return sorted(set(names))


def lines_changed(since: str, until: str) -> int:
    stat = git("log", REF, f"--since={since}", f"--until={until}", "--shortstat")
    total = 0
    for line in stat.splitlines():
        line = line.strip()
        if "changed" not in line:
            continue
        for part in line.split(","):
            part = part.strip()
            if "insertion" in part or "deletion" in part:
                total += int(part.split()[0])
    return total


def diff_text(since: str, until: str) -> str:
    return git("log", REF, f"--since={since}", f"--until={until}", "-p", "--reverse")


def update_index(entry: dict) -> None:
    index = json.loads(INDEX_PATH.read_text()) if INDEX_PATH.exists() else []
    index = [e for e in index if e["month"] != entry["month"]]
    index.append(entry)
    index.sort(key=lambda e: e["month"])
    INDEX_PATH.write_text(json.dumps(index, indent=2) + "\n")


def generate(year: int, month: int) -> None:
    since, until = month_range(year, month)
    month_key = f"{year:04d}-{month:02d}"
    label = date(year, month, 1).strftime("%b %Y")

    people = contributors(since, until)
    if not people:
        print(f"No commits found for {label} ({since} to {until}), skipping.")
        return

    total_lines = lines_changed(since, until)
    diff = diff_text(since, until)

    OUT_DIR.mkdir(exist_ok=True)
    diff_file = f"{month_key}.diff"
    (OUT_DIR / diff_file).write_text(diff)

    update_index(
        {
            "month": month_key,
            "label": label,
            "contributors": people,
            "linesChanged": total_lines,
            "diffFile": diff_file,
        }
    )
    print(f"Generated {diff_file}: {len(people)} contributor(s), {total_lines} lines changed.")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        y, m = (int(x) for x in sys.argv[1].split("-"))
    else:
        y, m = previous_month(datetime.utcnow().date())
    generate(y, m)
