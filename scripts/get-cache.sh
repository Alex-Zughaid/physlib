#!/usr/bin/env bash

# Download everything needed before a first build, so that `lake build` does
# not have to compile from source.
#
# Fetches both halves: Mathlib's prebuilt files (via Mathlib's own
# `lake exe cache get`) and Physlib's own (via Lake's built-in `lake cache`,
# backed by the project's R2 bucket -- see lake-cache.toml and
# docs/cache-setup.md). Running one command rather than two is the only
# reason the Mathlib step lives here -- pass --no-mathlib to skip it.
#
# Safe to run at any time, and safe to skip: if anything goes wrong -- no
# network, an unreachable bucket -- this warns and exits 0, and `lake build`
# simply compiles from source as it always did. Both caches are also safe to
# re-run: Lake only fetches artifacts it does not already have.
#
# Usage:
#   ./scripts/get-cache.sh              fetch everything needed
#   ./scripts/get-cache.sh --no-mathlib skip Mathlib, fetch only Physlib's

set -u

if [ ! -f "lakefile.toml" ]; then
  echo "Run this from the root of the Physlib repository."
  exit 0
fi

if ! command -v curl > /dev/null 2>&1; then
  echo "curl not found, skipping cache download."
  exit 0
fi

skip_mathlib=0
for arg in "$@"; do
  case "$arg" in
    --no-mathlib) skip_mathlib=1 ;;
    -h|--help)
      sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)"
      exit 0
      ;;
  esac
done

if [ "$skip_mathlib" -eq 0 ]; then
  echo "Fetching Mathlib's prebuilt files ..."
  if ! lake exe cache get; then
    echo "  could not fetch Mathlib's cache -- continuing anyway."
    echo "  ('lake build' may then have to compile Mathlib, which is slow.)"
  fi
  echo
fi

echo "Fetching Physlib's prebuilt files ..."
if LAKE_CONFIG="$PWD/lake-cache.toml" lake cache get --scope=physlib-master; then
  echo
  echo "Done. Now run: lake build"
else
  echo
  echo "Could not fetch Physlib's cache. This is not fatal -- run 'lake build'"
  echo "as usual, it will just take longer, compiling from source."
fi
