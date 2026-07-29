#!/usr/bin/env bash
# Builds monthly-diffs-doc/MonthlyDoc.lean (written by generate_monthly_diff.py)
# into monthly-diffs/<month>.pdf: Verso renders it to LaTeX, then lualatex
# compiles that to a PDF (run three times, standard for resolving the table
# of contents / cross-references).
set -euo pipefail

month="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
doc_dir="$repo_root/monthly-diffs-doc"

cd "$doc_dir"
lake build
lake exe monthlydoc

cd "$doc_dir/_out/tex"
# lualatex exits non-zero on things like a missing glyph in the monospace
# font (e.g. an emoji pulled verbatim from a source file) even when it still
# produces a perfectly good PDF, so don't let `set -e` treat that as fatal -
# check for the actual output file afterwards instead.
for _ in 1 2 3; do
  lualatex -shell-escape -interaction=nonstopmode main || true
done
if [ ! -f main.pdf ]; then
  echo "error: lualatex did not produce main.pdf - see main.log" >&2
  exit 1
fi

mkdir -p "$repo_root/monthly-diffs"
cp main.pdf "$repo_root/monthly-diffs/$month.pdf"
echo "Wrote monthly-diffs/$month.pdf"
