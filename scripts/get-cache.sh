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

set -u

# TODO: point this at leanprover-community/physlib before opening the upstream PR.
REPO="${PHYSLIB_CACHE_REPO:-Alex-Zughaid/physlib}"
TAG="cache-master"
ASSETS=("physlib-cache.tar.gz" "physlibalpha-cache.tar.gz")

DEST=".lake/build/lib/lean"

if [ ! -f "lakefile.toml" ]; then
  echo "Run this from the root of the Physlib repository."
  exit 0
fi

if ! command -v curl > /dev/null 2>&1; then
  echo "curl not found, skipping cache download."
  exit 0
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
cache_commit="$(sed -n 's/^commit=//p' "$DEST/.physlib-cache-info" 2>/dev/null | head -1)"
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
