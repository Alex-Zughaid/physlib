#!/usr/bin/env bash

# Download prebuilt Physlib artifacts so that your first `lake build` does not
# have to compile the whole library from source.
#
# This is the Physlib counterpart to `lake exe cache get`, which fetches
# Mathlib's prebuilt files but knows nothing about Physlib's own code.
#
# The artifacts are published by CI on every merge to master (see
# .github/workflows/build.yml and alphaBuild.yml).
#
# Safe to run at any time, and safe to skip. If anything goes wrong -- no
# network, nothing published yet, a bad download -- this warns and exits 0, and
# `lake build` simply compiles from source as it always did.
#
# Usage:
#   ./scripts/get-cache.sh            download the cache if it would help
#   ./scripts/get-cache.sh --force    download even if the cache looks current

set -u

# TODO: point this at leanprover-community/physlib before opening the upstream PR.
DEFAULT_REPO="Alex-Zughaid/physlib"
REPO="${PHYSLIB_CACHE_REPO:-$DEFAULT_REPO}"
TAG="cache-master"
ASSETS=("physlib-cache.tar.gz" "physlibalpha-cache.tar.gz")

DEST=".lake/build/lib/lean"
INFO="$DEST/.physlib-cache-info"

force=0
for arg in "$@"; do
  case "$arg" in
    -f|--force) force=1 ;;
    -h|--help)
      sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)"
      exit 0
      ;;
  esac
done

if [ ! -f "lakefile.toml" ]; then
  echo "Run this from the root of the Physlib repository."
  exit 0
fi

if ! command -v curl > /dev/null 2>&1; then
  echo "curl not found, skipping cache download."
  exit 0
fi

# Downloaded .olean files are loaded and executed by Lean, so pointing this at
# an untrusted repository is equivalent to running its code. Warn loudly when
# the override is in play, rather than silently fetching from anywhere.
if [ "$REPO" != "$DEFAULT_REPO" ]; then
  {
    echo
    echo "WARNING: PHYSLIB_CACHE_REPO is set."
    echo "  Downloading build artifacts from: $REPO"
    echo "  instead of the usual:             $DEFAULT_REPO"
    echo
    echo "  Lean loads and executes .olean files. Only point this at a"
    echo "  repository you trust."
    echo
  } >&2
fi

# If the cache already in place was built from exactly the commit we are sitting
# on, re-downloading cannot improve anything: a newer published cache would be
# for a different commit and would fit this checkout no better. Skipping keeps
# repeat runs free instead of re-fetching and re-extracting ~160MB every time.
if [ "$force" -eq 0 ] && [ -f "$INFO" ] && [ -f "$DEST/Physlib.olean" ]; then
  have_commit="$(sed -n 's/^commit=//p' "$INFO" 2>/dev/null | head -1)"
  head_commit="$(git rev-parse HEAD 2>/dev/null)"
  if [ -n "$have_commit" ] && [ "$have_commit" = "$head_commit" ]; then
    echo "Cache for ${have_commit:0:8} is already in place -- nothing to download."
    echo "Run with --force to fetch it again anyway."
    exit 0
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DEST"

echo "Fetching Physlib build cache from $REPO ..."

fetched=0
for asset in "${ASSETS[@]}"; do
  url="https://github.com/$REPO/releases/download/$TAG/$asset"

  if ! curl -fL --retry 3 --progress-bar -o "$TMP/$asset" "$url"; then
    echo "  could not download $asset -- skipping it."
    continue
  fi

  # These archives come off the network, so make sure nothing escapes $DEST
  # before unpacking them.
  if tar -tzf "$TMP/$asset" | grep -qE '^/|(^|/)\.\.(/|$)'; then
    echo "  $asset contains unsafe paths -- refusing to extract it."
    continue
  fi

  if ! tar -xzf "$TMP/$asset" -C "$DEST"; then
    echo "  could not extract $asset -- skipping it."
    continue
  fi

  fetched=$((fetched + 1))
done

if [ "$fetched" -eq 0 ]; then
  echo
  echo "No cache was downloaded. This is not fatal -- run 'lake build' as usual,"
  echo "it will just take longer."
  exit 0
fi

# Report how well the cache matches this checkout. A mismatch is expected and
# harmless: Lake rebuilds whatever no longer matches and reuses the rest.
cache_commit="$(sed -n 's/^commit=//p' "$INFO" 2>/dev/null | head -1)"
local_commit="$(git rev-parse HEAD 2>/dev/null)"

echo
if [ -n "$cache_commit" ] && [ -n "$local_commit" ]; then
  if [ "$cache_commit" = "$local_commit" ]; then
    echo "Cache matches your checkout exactly. 'lake build' should have little left to do."
  else
    echo "Cache was built from ${cache_commit:0:8}, you are on ${local_commit:0:8}."
    echo "'lake build' will rebuild the files that changed between them, plus"
    echo "anything importing them."
  fi
fi

echo
echo "Done. Now run: lake build"
