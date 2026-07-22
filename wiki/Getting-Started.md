# Getting started

The full guide lives at [physlib.io/GettingStarted](https://physlib.io/GettingStarted.html).
Summary below.

## Installing Lean 4

- https://lean-lang.org/lean4/doc/quickstart.html
- or https://leanprover-community.github.io/get_started.html

## Installing Physlib

1. Clone this repository (or download it as a zip).
2. Open a terminal at the top level of the repo.
3. Run `lake exe cache get`.
4. Run `lake build`.
5. Open the directory (not a single file) in VS Code or another Lean-compatible editor.

Physlib is currently split into two build targets that live in the same repo:

- `Physlib` — the main library
- `QuantumInfo` — the quantum-information library

Both are default targets, so `lake build` builds both. To build just one:

```
lake build Physlib
lake build QuantumInfo
```

## PhyslibAlpha

`PhyslibAlpha` sits downstream of `Physlib` in the same repository, with a
lower review bar — useful for large PRs, AI-generated content, or
formalizations that aren't quite polished yet. See
[Project-Structure](./Project-Structure.md) for details.
