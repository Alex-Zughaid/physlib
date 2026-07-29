#!/usr/bin/env python3
"""
Generates monthly-diffs-doc/MonthlyDoc.lean - a Verso (Manual genre) document
listing every line added to every file between the start and end of the
given month on leanprover-community/physlib's default branch, one section
per file - plus an updated monthly-diffs/index.json summary (contributors,
total lines changed, PDF filename) consumed by the physlib-website "Monthly
Updates" page.

MonthlyDoc.lean is then built by scripts/build_monthly_pdf.sh, which runs
Verso (emitting LaTeX) and lualatex (emitting the actual PDF) to produce
monthly-diffs/<YYYY-MM>.pdf.

Expects a git remote named "upstream" pointing at
https://github.com/leanprover-community/physlib.git to already be fetched.

Usage:
    python3 scripts/generate_monthly_diff.py [YYYY-MM]

With no argument, generates the previous calendar month (relative to today),
which is what the end-of-month scheduled workflow uses.
"""

import json
import os
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "monthly-diffs"
INDEX_PATH = OUT_DIR / "index.json"
DOC_PROJECT_DIR = REPO_ROOT / "monthly-diffs-doc"
DOC_SOURCE_PATH = DOC_PROJECT_DIR / "MonthlyDoc.lean"
REF = "upstream/master"
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"  # sha of an empty git tree


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


def commit_before(date_str: str) -> str:
    """Latest first-parent (mainline) commit on REF strictly before date_str,
    or the empty tree if none. Restricting to --first-parent matters here:
    REF's history isn't linear (feature branches get merged in), so two
    commits picked by date alone aren't guaranteed to be ancestors of each
    other - diffing them can pull in unrelated parallel-branch content and
    wildly overstate the change. The first-parent chain is guaranteed to be
    a single ancestor line, so any two commits on it are always comparable."""
    out = git("rev-list", "-1", REF, "--first-parent", f"--before={date_str}").strip()
    return out if out else EMPTY_TREE


def lines_changed(start_commit: str, end_commit: str) -> int:
    stat = git("diff", "--shortstat", start_commit, end_commit)
    total = 0
    for part in stat.split(","):
        part = part.strip()
        if "insertion" in part or "deletion" in part:
            total += int(part.split()[0])
    return total


SKIP_PREFIXES = (
    "--- ",
    "@@",
    "index ",
    "new file mode",
    "deleted file mode",
    "old mode",
    "new mode",
    "similarity index",
    "rename from",
    "rename to",
    "Binary files",
)


def added_lines_only(diff: str) -> list[tuple[str, str]]:
    """Strips diff syntax down to, per changed file, just the raw lines added
    between the two commits - no +/- markers, no hunk headers, no per-commit
    breakdown. Returns a list of (file path, added-lines content) pairs."""
    sections: list[tuple[str, str]] = []
    current_file: str | None = None
    current_lines: list[str] = []

    def flush() -> None:
        if current_file and current_lines:
            sections.append((current_file, "\n".join(current_lines)))

    for line in diff.splitlines():
        if line.startswith("diff --git "):
            flush()
            current_file, current_lines = None, []
        elif line.startswith("+++ "):
            path = line[4:]
            current_file = (
                None
                if path == "/dev/null"
                else path[2:] if path.startswith("b/") else path
            )
        elif line.startswith(SKIP_PREFIXES):
            continue
        elif line.startswith("+") and current_file:
            current_lines.append(line[1:])
    flush()
    return sections


def code_fence(content: str) -> str:
    """A backtick fence at least one tick longer than the longest run of
    backticks in content, so the content can never prematurely close it."""
    longest = 0
    run = 0
    for ch in content:
        run = run + 1 if ch == "`" else 0
        longest = max(longest, run)
    return "`" * max(3, longest + 1)


def heading_safe(path: str) -> str:
    """Verso's LaTeX backend doesn't escape a literal `_` used in a chapter/
    section title (it hits a "moving argument" context that isn't wrapped in
    a verbatim environment like body code is), so a raw underscore renders
    as a LaTeX subscript instead of a literal character - and an unescaped
    `_` outside a code span is a Verso parse error in the first place, since
    `_..._` is its emphasis syntax. Swap in U+2017 DOUBLE LOW LINE: it's not
    LaTeX-special, isn't Verso markup syntax, is present in the PDF's
    monospace font, and reads as a normal underscore."""
    return path.replace("_", "‗")


def write_verso_doc(label: str, sections: list[tuple[str, str]]) -> None:
    lines = ["import VersoManual", "", "open Verso.Genre Manual", "", f'#doc (Manual) "{label}" =>', "", "# Changes", ""]
    for path, content in sections:
        fence = code_fence(content)
        lines.append(f"## `{heading_safe(path)}`")
        lines.append("")
        lines.append(fence)
        lines.append(content)
        lines.append(fence)
        lines.append("")
    DOC_PROJECT_DIR.mkdir(exist_ok=True)
    DOC_SOURCE_PATH.write_text("\n".join(lines))


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

    start_commit = commit_before(since)
    end_commit = commit_before(until)

    total_lines = lines_changed(start_commit, end_commit)
    sections = added_lines_only(git("diff", start_commit, end_commit))

    write_verso_doc(label, sections)

    update_index(
        {
            "month": month_key,
            "label": label,
            "contributors": people,
            "linesChanged": total_lines,
            "pdfFile": f"{month_key}.pdf",
        }
    )
    print(
        f"Wrote {DOC_SOURCE_PATH} for {label}: {len(people)} contributor(s), "
        f"{total_lines} lines changed, {len(sections)} file(s) touched. "
        f"Run scripts/build_monthly_pdf.sh {month_key} to render the PDF."
    )


if __name__ == "__main__":
    if len(sys.argv) > 1:
        y, m = (int(x) for x in sys.argv[1].split("-"))
    else:
        y, m = previous_month(datetime.utcnow().date())

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        # The CLI arg is only given for a manual workflow_dispatch run; on
        # the scheduled run it's empty and "previous month" is computed
        # above, so the workflow needs this to know which month it's
        # actually building (for the PDF filename and commit message).
        with open(github_output, "a") as f:
            f.write(f"month={y:04d}-{m:02d}\n")

    generate(y, m)
