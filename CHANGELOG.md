# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/) (`0.x` while pre-release).

Every release entry has a **Verified** line naming the highest test level reached. The levels are defined in [`docs/TESTING.md`](docs/TESTING.md):

- **L0**: static checks
- **L1**: unit tests
- **L2**: mocked integration tests
- **L3**: in game, Classic Era
- **L4**: in game, WoW Forever

A feature is never called "tested" or "compatible" in this file unless it reached L3 or L4.

## [Unreleased]

### Added
- Repository foundation: licence, third-party notices, contribution guide, issue and PR templates, and a CI workflow (lint and tests).
- Architecture, compatibility, privacy, testing, development-workflow and Total RP 3 integration documents.
- Total RP 3 3.4.1 compatibility audit and phased plan (`docs/planning/`).
- Development tooling: Lua 5.1 test runner, a minimal test harness, luacheck configuration and a repository hygiene check.

### Not yet included
- There is no installable addon yet. The first addon code is planned for v0.1.0.

**Verified:** L0 and L1 for the tooling and harness only, run locally. CI has not run yet.
