#!/usr/bin/env bash

# Download everything needed before a first build, so that `lake build` does
# not have to compile from source.
#
# Fetches both halves: Mathlib's prebuilt files (via Mathlib's own
# `lake exe cache get`) and Physlib's. Running one command rather than two is
# the only reason the Mathlib step lives here -- pass --no-mathlib to skip it.
#
# Physlib's artifacts are published by CI on every merge to master (see
# .github/workflows/build.yml and alphaBuild.yml).
#
# Downloaded archives are kept in a local cache directory that persists across
# checkouts, so returning to a commit you have fetched before costs nothing.
# Override its location with PHYSLIB_CACHE_DIR.
#
# Safe to run at any time, and safe to skip. If anything goes wrong -- no
# network, nothing published yet, a bad download -- this warns and exits 0, and
# `lake build` simply compiles from source as it always did.
#
# Usage:
#   ./scripts/get-cache.sh              fetch everything needed
#   ./scripts/get-cache.sh --force      re-fetch even if things look current
#   ./scripts/get-cache.sh --no-mathlib skip Mathlib, fetch only Physlib's
#   ./scripts/get-cache.sh --clean      delete the local cache directory

set -u

# TODO: point this at leanprover-community/physlib before opening the upstream PR.
DEFAULT_REPO="Alex-Zughaid/physlib"
REPO="${PHYSLIB_CACHE_REPO:-$DEFAULT_REPO}"
TAG="cache-master"
MAIN_ASSET="physlib-cache.tar.gz"
ALPHA_ASSET="physlibalpha-cache.tar.gz"
MARKER="cache-commit.txt"

DEST=".lake/build/lib/lean"
INFO="$DEST/.physlib-cache-info"

# Persistent store of downloaded archives, keyed by the commit they were built
# from. This is what makes switching between commits you have already fetched
# free, rather than re-downloading ~160MB each time.
CACHE_DIR="${PHYSLIB_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/physlib}"
KEEP=3   # how many commits' archives to retain

force=0
skip_mathlib=0
for arg in "$@"; do
  case "$arg" in
    -f|--force) force=1 ;;
    --no-mathlib) skip_mathlib=1 ;;
    --clean)
      rm -rf "$CACHE_DIR" && echo "Removed local cache: $CACHE_DIR"
      exit 0
      ;;
    -h|--help)
      sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
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

# Mathlib's artifacts first. This is `lake exe cache get`, Mathlib's own tool,
# which knows nothing about Physlib -- but there is no reason to make people
# run two commands, so it is done here. It is cheap when already present
# (~15s), and skipping it would leave Physlib's artifacts unusable, since they
# were built against Mathlib's.
if [ "$skip_mathlib" -eq 0 ]; then
  echo "Fetching Mathlib's prebuilt files ..."
  if ! lake exe cache get > /dev/null 2>&1; then
    echo "  could not fetch Mathlib's cache -- continuing anyway."
    echo "  ('lake build' may then have to compile Mathlib, which is slow.)"
  fi
fi

head_commit="$(git rev-parse HEAD 2>/dev/null)"

# Cheapest case: the artifacts are already unpacked and were built from exactly
# the commit we are on. Nothing to download, nothing to extract.
if [ "$force" -eq 0 ] && [ -f "$INFO" ] && [ -f "$DEST/Physlib.olean" ]; then
  have_commit="$(sed -n 's/^commit=//p' "$INFO" 2>/dev/null | head -1)"
  if [ -n "$have_commit" ] && [ "$have_commit" = "$head_commit" ]; then
    echo "Cache for ${have_commit:0:8} is already in place -- nothing to do."
    echo "Run with --force to fetch it again anyway."
    exit 0
  fi
fi

# Preferred path: Lake's own content-addressed cache, backed by the project's
# R2 bucket. Unlike the release tarball this is per-file and keyed by an input
# hash, so a branch that is not tip-of-master still gets hits and Lake can
# backtrack revisions to find them.
#
# The committed config still carries placeholders until the bucket is
# provisioned (see docs/cache-setup.md); until then this is skipped and we fall
# through to the release tarball below.
LAKE_CACHE_CONF="$PWD/lake-cache.toml"
if [ "$force" -eq 0 ] && [ -f "$LAKE_CACHE_CONF" ] && ! grep -q '<R2_' "$LAKE_CACHE_CONF"; then
  echo "Fetching via Lake's cache from the Physlib R2 bucket ..."
  # `lake cache get` walks back up to 100 revisions looking for a hit and logs
  # two lines per revision, so keep its output in a file and surface only the
  # outcome. It exits non-zero when nothing is found, which is our cue to fall
  # back to the release tarball.
  lake_log="$(mktemp)"
  if LAKE_CONFIG="$LAKE_CACHE_CONF" lake cache get --scope=physlib-master \
       > "$lake_log" 2>&1; then
    grep -E "^(info|warning): " "$lake_log" | grep -viE "downloading build outputs" | sed 's/^/  /'
    rm -f "$lake_log"
    echo
    echo "Done. Now run: lake build"
    exit 0
  fi
  grep -E "^error: " "$lake_log" | head -2 | sed 's/^/  /'
  rm -f "$lake_log"
  echo "  Falling back to the release tarball."
fi

mkdir -p "$DEST" "$CACHE_DIR"

# Sweep up .part files left by a download that was killed rather than failing
# cleanly. Done on every run, including ones that go on to fail, so they cannot
# accumulate. They are never reused -- a partial archive must not look usable.
find "$CACHE_DIR" -maxdepth 1 -name '.*.part' -delete 2>/dev/null

# Unpack the archives held locally for $1, if they are there. Returns non-zero
# if the main archive is missing, so callers can fall through to downloading.
extract_from_local() {
  local sha="$1" main="$CACHE_DIR/$1-$MAIN_ASSET" alpha="$CACHE_DIR/$1-$ALPHA_ASSET" n=0
  [ -f "$main" ] || return 1

  for archive in "$main" "$alpha"; do
    [ -f "$archive" ] || continue
    # These archives came off the network, so re-check before every unpack that
    # nothing escapes $DEST -- not just on the run that downloaded them.
    if tar -tzf "$archive" 2>/dev/null | grep -qE '^/|(^|/)\.\.(/|$)'; then
      echo "  $(basename "$archive") contains unsafe paths -- refusing to extract it."
      continue
    fi
    if tar -xzf "$archive" -C "$DEST" 2>/dev/null; then
      n=$((n + 1))
    else
      echo "  could not extract $(basename "$archive")."
    fi
  done

  [ "$n" -gt 0 ]
}

# Keep only the $KEEP most recently used commits' archives.
prune_cache() {
  local shas
  shas="$(ls -t "$CACHE_DIR" 2>/dev/null | sed -n "s/-$MAIN_ASSET$//p" | tail -n +$((KEEP + 1)))"
  for old in $shas; do
    rm -f "$CACHE_DIR/$old-$MAIN_ASSET" "$CACHE_DIR/$old-$ALPHA_ASSET"
  done
}

used_local=0

# Do we already hold archives built from the commit we are sitting on? If so we
# need no network at all -- this is the case that makes branch switching cheap.
if [ "$force" -eq 0 ] && [ -n "$head_commit" ] && [ -f "$CACHE_DIR/$head_commit-$MAIN_ASSET" ]; then
  echo "Using locally cached archives for ${head_commit:0:8} (no download needed)."
  extract_from_local "$head_commit" && used_local=1
fi

if [ "$used_local" -eq 0 ]; then
  # Ask the release which commit it was built from before pulling ~160MB: the
  # marker is a few bytes, and we may already hold that commit's archives.
  remote_sha="$(curl -fsL --retry 3 "https://github.com/$REPO/releases/download/$TAG/$MARKER" 2>/dev/null | tr -d '[:space:]')"

  if [ -n "$remote_sha" ] && [ "$force" -eq 0 ] && [ -f "$CACHE_DIR/$remote_sha-$MAIN_ASSET" ]; then
    echo "Published cache is ${remote_sha:0:8}, already held locally (no download needed)."
    extract_from_local "$remote_sha" && used_local=1
  fi

  if [ "$used_local" -eq 0 ]; then
    # Fall back to the SHA in the archive's own metadata if the marker is
    # unavailable, e.g. a release published before markers existed.
    sha="${remote_sha:-unknown}"
    echo "Fetching Physlib build cache from $REPO ..."

    got=0
    for asset in "$MAIN_ASSET" "$ALPHA_ASSET"; do
      tmp="$CACHE_DIR/.$sha-$asset.part"
      if curl -fL --retry 3 --progress-bar -o "$tmp" \
           "https://github.com/$REPO/releases/download/$TAG/$asset"; then
        # Rename only once the download is complete, so an interrupted run
        # never leaves a truncated archive looking like a usable cache entry.
        mv "$tmp" "$CACHE_DIR/$sha-$asset"
        got=$((got + 1))
      else
        rm -f "$tmp"
        echo "  could not download $asset -- skipping it."
      fi
    done

    if [ "$got" -eq 0 ]; then
      echo
      echo "No cache was downloaded. This is not fatal -- run 'lake build' as usual,"
      echo "it will just take longer."
      exit 0
    fi

    extract_from_local "$sha" || {
      echo
      echo "Nothing could be unpacked. Run 'lake build' as usual."
      exit 0
    }
  fi
fi

prune_cache

# Report how well the cache matches this checkout. A mismatch is expected and
# harmless: Lake rebuilds whatever no longer matches and reuses the rest.
cache_commit="$(sed -n 's/^commit=//p' "$INFO" 2>/dev/null | head -1)"

echo
if [ -n "$cache_commit" ] && [ -n "$head_commit" ]; then
  if [ "$cache_commit" = "$head_commit" ]; then
    echo "Cache matches your checkout exactly. 'lake build' should have little left to do."
  else
    echo "Cache was built from ${cache_commit:0:8}, you are on ${head_commit:0:8}."
    echo "'lake build' will rebuild the files that changed between them, plus"
    echo "anything importing them."
  fi
fi

echo "Local cache: $CACHE_DIR ($(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1) held)"
echo
echo "Done. Now run: lake build"
