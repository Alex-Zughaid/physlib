# Review guidelines

What reviewers look for in a Physlib pull request. Not exhaustive — reviews
are ultimately within the reviewer's judgement. Also see
[what to consider when reviewing](https://leanprover-community.github.io/contribute/pr-review.html#what-to-consider-when-reviewing).

## Code quality

- Correct abstraction of lemmas and definitions.
- Correct use of type theory in definitions.
- Correct use of Mathlib lemmas (don't reprove what's already proved).
- Concise proofs where possible.

## Organization

- Lemmas and definitions live in the right place.
- Modules are easy to read with a well-defined scope.
- New files are suitably named and located.
- Modules have enough documentation to follow their flow.

## Style conventions

- Follow the [Mathlib style guide](https://leanprover-community.github.io/contribute/style.html).
- Use `lemma` instead of `theorem`, except for the most important results.

## PR and authorship

- The author understands the material in the PR.
- The PR is concise and adds a single new concept (which may span multiple
  lemmas or definitions).

## PhyslibAlpha's lighter bar

PRs into `PhyslibAlpha` only need to pass basic linter checks and a light
"one-look" review checking:

1. Is the content mainstream physics?
2. Does it look reasonable (no stray axioms, easy to read, etc.)?
3. Is it in the right place within `PhyslibAlpha` (mirroring its place in `Physlib`)?

Because of the lower bar, contributions there aren't guaranteed to be
maintained if they break — breakage is simply recorded.
