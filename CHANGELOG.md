# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/) (`0.x` while pre-release).

Every release entry has a **Verified** line naming the highest test level reached. The levels are defined in [`docs/TESTING.md`](docs/TESTING.md):

- **L0**: static checks
- **L1**: unit tests
- **L2**: mocked integration tests
- **L3**: in game, Classic Era
- **L4**: in game, WoW Forever

A feature is never called "tested" or "compatible" in this file unless it reached L3 or L4.

## [Unreleased]: 0.1.0 (foundation)

### Added
- The first installable addon (`DawnwardChronicles/`) for Classic Era (TOC interface 11509).
- **Character profile:** 12 optional fields (name, title, race, class, age, pronouns, homeland, faith, occupation, appearance, summary, motivation). Nothing about any particular character is hardcoded.
- **Family and history:** family members (relation, name, status, notes) and dated history entries.
- **Privacy:** every fact is `public`, `private` or `secret`, and defaults to private. `/dawnward show public` previews the only facts that can ever be shared.
- **Saved data:** `DawnwardChroniclesDB` with schema version 1. A migration framework works on a copy, and newer, unversioned or damaged data is left untouched in read-only mode. Text length and list size limits are enforced on every load.
- **Export and import**, through a copy window:
  - A personal backup includes private facts, and secrets only on request.
  - A share export includes public facts only.
  - Imports are checksummed, never executed as code, checked before they apply, and can be undone in one step.
  - Importing a backup that has no secrets keeps your existing secret facts.
- **Simulation mode:** test data goes in a separate saved variable (`DawnwardChroniclesSimDB`). It is off at every login, and `sim copy` and `sim reset` need `confirm`.
- **Read-only Total RP 3 status** (`/dawnward trp3`): the TRP3 version, whether that version has been audited, and the active profile name with a default-profile warning. It uses TRP3's public API only, never writes, and never keeps references to TRP3 data.
- **Commands:** `/dawnward` (alias `/dwc`). Anything that deletes or replaces data asks for `confirm`.
- **Tooling:**
  - an L2 load test that runs the TOC file order against a WoW API mock;
  - a fake TRP3 3.4.1 public API;
  - a TOC completeness check;
  - a release packaging script.

### Fixed (found in the first in-game test)
- The export/import window was hard to read when opened over Total RP 3. Its background was translucent, and it shared the DIALOG layer with Total RP 3's popups. It now:
  - opens in the FULLSCREEN_DIALOG layer and comes to the front each time it opens;
  - has an opaque background and a dark text area;
  - keeps the text, status line and buttons from overlapping;
  - pads and wraps text, and scrolls to follow the cursor.

### Known limitations
- No adventure journal, story popups, personality changes or TRP3 writes yet. These are planned for v0.2–v0.5.
- Profile editing is through slash commands only. Long text is cut short in chat; the export window shows it in full.
- UI strings are English only. Localisation files will come once the strings settle.

**Verified:**
- L0, L1 and L2: 103 tests, run locally. CI has not run on this branch yet.
- **L3, partial** (Classic Era 1.15.9, Total RP 3 3.4.1): the items listed in `docs/COMPATIBILITY.md` were confirmed in game.
- The window fix has not been re-tested in game yet.
- Not tested on Forever (L4).

## Repository foundation (2026-10-25)

### Added
- Licence, third-party notices, contribution guide, issue and PR templates, and a CI workflow.
- Architecture, compatibility, privacy, testing, workflow and Total RP 3 integration documents, and the Phase 0 audit and plan.
- Development tooling: a Lua 5.1 test runner and harness, luacheck configuration, and a repository hygiene check.

**Verified:** L0 and L1 for the tooling only. CI passed on GitHub.
