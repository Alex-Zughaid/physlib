/-
Copyright (c) 2026 Physlib community. All rights reserved.
Released under Apache 2.0 license.
-/
import Lean

/-!
# Get cache

Downloads everything needed before a first build, so that `lake build` does
not have to compile from source.

Fetches both halves: Mathlib's prebuilt files (via Mathlib's own
`lake exe cache get`) and Physlib's own (via Lake's built-in `lake cache`,
backed by the project's R2 bucket -- see `lake-cache.toml` and
`docs/cache-setup.md`). Running one command rather than two is the only
reason the Mathlib step lives here -- pass `--no-mathlib` to skip it.

Safe to run at any time, and safe to skip: if anything goes wrong -- no
network, an unreachable bucket -- this warns and exits 0, and `lake build`
simply compiles from source as it always did.

It can be run from the terminal using `lake exe get_cache`.
-/

def helpText : String :=
"Download everything needed before a first build, so that `lake build` does \
not have to compile from source.

Usage:
  lake exe get_cache              fetch everything needed
  lake exe get_cache --no-mathlib skip Mathlib, fetch only Physlib's
"

/-- `println`, then flush stdout immediately. Without this, messages printed
before spawning a subprocess can sit in a buffer and appear out of order (or
not at all until the child exits) whenever stdout is piped rather than a
terminal -- e.g. `lake exe get_cache | tee log.txt`. -/
def say (s : String) : IO Unit := do
  IO.println s
  (← IO.getStdout).flush

/-- Run a subprocess, inheriting stdout/stderr, with optional extra
environment variables. Returns whether it exited successfully. -/
def runStreamed (cmd : String) (args : Array String)
    (env : Array (String × Option String) := #[]) : IO Bool := do
  let child ← IO.Process.spawn { cmd, args, env }
  return (← child.wait) == 0

/-- The options this program understands. Anything else is rejected up
front, rather than silently ignored and treated as "no flags given" --
which would otherwise run the full fetch when the user typed a typo'd flag
expecting it to be validated. -/
def knownFlags : List String := ["--help", "-h", "--no-mathlib"]

def main (args : List String) : IO UInt32 := do
  if let some bad := args.find? (!knownFlags.contains ·) then
    say s!"Unknown option: {bad} (try --help)"
    return 0

  if args.contains "--help" || args.contains "-h" then
    say helpText
    return 0

  unless ← System.FilePath.pathExists "lakefile.toml" do
    say "Run this from the root of the Physlib repository."
    return 0

  let skipMathlib := args.contains "--no-mathlib"

  if !skipMathlib then
    say "Fetching Mathlib's prebuilt files ..."
    unless ← runStreamed "lake" #["exe", "cache", "get"] do
      say "  could not fetch Mathlib's cache -- continuing anyway."
      say "  ('lake build' may then have to compile Mathlib, which is slow.)"
    say ""

  say "Fetching Physlib's prebuilt files ..."
  let cwd ← IO.currentDir
  let configPath := (cwd / "lake-cache.toml").toString
  let ok ← runStreamed "lake" #["cache", "get", "--scope=physlib-master"]
    #[("LAKE_CONFIG", some configPath)]
  if ok then
    say ""
    say "Done. Now run: lake build"
  else
    say ""
    say "Could not fetch Physlib's cache. This is not fatal -- run 'lake build'"
    say "as usual, it will just take longer, compiling from source."
  return 0
