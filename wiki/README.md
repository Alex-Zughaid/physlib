# Wiki staging area

GitHub wikis live in a separate repo (`physlib.wiki.git`) rather than in this
main repo, so they can't be opened as a normal pull request. This folder is a
staging area for drafting that content on a branch here first, so it can be
reviewed like any other change before being copied over to the actual wiki
(via `git clone https://github.com/leanprover-community/physlib.wiki.git` and
pushing the finished pages there, once a maintainer enables the wiki).

Pages so far are seeded from existing docs (`README.md`, `CONTRIBUTING.md`,
`docs/*.md`) so content isn't duplicated by hand — they should be trimmed and
cross-linked as the wiki grows.

## Proposed structure

- [Home](./Home.md) — landing page, orientation
- [Getting-Started](./Getting-Started.md) — install Lean, build the project
- [Contributing](./Contributing.md) — how to make a PR
- [Review-Guidelines](./Review-Guidelines.md) — what reviewers look for
- [Project-Structure](./Project-Structure.md) — Physlib vs PhyslibAlpha vs QuantumInfo
- [Maintainers](./Maintainers.md) — who they are, how the team works
