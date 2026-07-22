# Project structure

Physlib was formed by merging two previously-separate libraries, and the repo
layout still reflects that.

## `Physlib`

The main library. Organized by physics topic (not by proof technique), with
physics-based documentation expected on every definition and module.

## `PhyslibAlpha`

Sits downstream of `Physlib`, in the same repository, mirroring `Physlib`'s
structure. It exists to lower the barrier for large PRs, AI-generated
content, or formalizations that aren't quite polished — see
[Review-Guidelines](./Review-Guidelines.md#physlibalphas-lighter-bar) for what
that means in practice.

## `QuantumInfo`

The quantum-information library (formerly Lean-QuantumInfo), merged into
Physlib alongside the general physics library (formerly PhysLean/HepLean).
Currently an essentially disjoint build target from `Physlib` — see
[Getting-Started](./Getting-Started.md) for building them individually. There
is ongoing work to integrate the two more deeply.

## Docs and scripts

- `docs/` — review guidelines, maintainer info, curated notes, the TODO
  list source, citation references.
- `scripts/` — linters and their local-run instructions, including the
  separate `scripts/PhyslibAlpha` checks.
