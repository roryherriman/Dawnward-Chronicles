# Development workflow

## Branches and commits
- `main` must always pass CI and be releasable.
- Work happens on `feat/<topic>`, `fix/<topic>`, `docs/<topic>` or `chore/<topic>`, and merges into `main` by pull request.
- One logical change per commit, with an imperative subject of 72 characters or fewer (for example "Add journal ring buffer").
- Contributors commit under their GitHub no-reply email.

## Milestones
Each milestone is small enough to test on its own and ends at a review checkpoint before anything is published:

1. Code is complete, with L0, L1 and L2 green locally and in CI.
2. The L3 checklist has been run in game and the results recorded in `docs/COMPATIBILITY.md`.
3. The changelog is updated with a **Verified** line.
4. The version is tagged and a release created.

Any operation that could destroy data, and any change to TRP3 profile data, needs an explicit approval step in the addon's UI as well as in the development process.

## Versioning
- [SemVer](https://semver.org/): `0.MINOR.PATCH` while pre-release, with one minor version per milestone.
- The version appears in exactly two places: the TOC `## Version:` line and the `CHANGELOG.md` heading.
- Tags are `vX.Y.Z`. Pre-releases are `vX.Y.Z-beta.N`.
- **SavedVariables schema versions are separate from the addon version.** Any schema change needs a migration and an L1 test.

## Releases
- `python tools/package.py` builds `dist/DawnwardChronicles-<version>.zip`. It contains only git-tracked files under `DawnwardChronicles/`; tests, tools, docs and dot-files are never packaged. The script refuses to run if the addon folder has untracked files.
- A release whose highest verified level is below L3 is marked as a GitHub **pre-release**.

## Local setup
See [CONTRIBUTING.md](../CONTRIBUTING.md#setup). The tooling goes in `.tooling/`, which git ignores and which is never shipped.

## Migration dry run on real saved data

`tools/migration_dryrun.lua` loads a copy of a real `DawnwardChronicles.lua` SavedVariables file, runs the migrations and normalisation in memory, and prints only structure and counts, never content. It **never writes**. Usage: `lua5.1 tools/migration_dryrun.lua <copy of DawnwardChronicles.lua>`. Always run it on a copy, never on the live file inside `WTF\`.
