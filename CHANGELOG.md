# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/) (`0.x` while pre-release).

Every release entry has a **Verified** line naming the highest test level reached. The levels are defined in [`docs/TESTING.md`](docs/TESTING.md):

- **L0**: static checks
- **L1**: unit tests
- **L2**: mocked integration tests
- **L3**: in game, Classic Era
- **L4**: in game, WoW Forever

A feature is never called "tested" or "compatible" in this file unless it reached L3 or L4.

## [Unreleased]: 0.2.0 (journal window)

### Added
- **Journal window.** `/dawnward` (or `/dwc`) opens and closes a compact, draggable journal.
  - Three sections only: **Journal**, **Character** and **Story**.
  - The window stays on screen and remembers its position.
  - It sits below game dialogs and tooltips, and the export window opens above it.
- **Journal:**
  - Entries show newest first, ten per page.
  - Write entries with an optional title; edit them, and delete them after confirming.
  - Every entry has a visibility: Public, Private or Secret.
- **Automatic level-up entries** record the level, zone and subzone, the time, and the source event.
  - A level is recorded only once, even after its entry is pruned.
  - Real level-ups always go to your real journal.
  - `/dawnward sim levelup <n>` adds simulated ones to simulation data, for testing.
- **Journal retention:**
  - At most 500 entries per character.
  - When the journal is full, the oldest automatic entry makes room.
  - Entries you wrote are never removed automatically; if they fill the journal, adding more is refused with an explanation.
- **Character section:** edit profile fields (single-line or multi-line) and change their visibility. Clearing a field asks for confirmation. Family and history are shown in readable form; they are still edited with commands.
- **Story section:** an empty state explaining that story decisions are coming later.
- **Settings panel** behind a gear button, not a fourth section:
  - theme choice;
  - export backup, export for sharing, and import;
  - simulation on/off and a confirmed reset;
  - read-only Total RP 3 status.
- **Cosmetic themes, chosen per character:** Neutral (the default for every new character), Silver Hand and Arcane. They change colours and the border tint only. Every text colour is tested for at least 4.5:1 contrast. No theme is chosen from class or race.
- **Commands:**
  - `/dawnward status` for diagnostics (the bare command now opens the journal);
  - `journal list|add|edit|vis|remove`;
  - `theme <id>`;
  - `sim levelup <n>`.
- **Saved data schema 2:** an additive, idempotent upgrade from schema 1 that preserves every v0.1 profile, family entry, history entry, privacy setting and import backup.
- **Docs:**
  - the story interpretation architecture (`docs/STORY_ARCHITECTURE.md`);
  - an updated architecture document, including the retention policy;
  - the v0.2 in-game checklist.

### Changed
- Exports and imports now include the journal, under the same privacy rules. Backups also keep milestone keys, so a restore can't record old milestones again. v0.1 exports still import.
- Read-only Total RP 3 status text is shared between chat and the settings panel.

### Known limitations
- Only level-ups are recorded automatically. Quests, discoveries and other milestones are planned, and the milestone registry is ready for them.
- Family and history are edited with slash commands, not in the window.
- Automatic entries can't be edited or deleted (only their visibility changes). This keeps the record factual.
- No story decisions, personality development or Total RP 3 writes yet.
- English only.
- Once v0.2 has upgraded saved data to schema 2, v0.1 opens it read-only rather than changing it.

### Known issues
- **KI-1:** a one-time return to character select happened shortly after entering the world in the first v0.2 test session. It is **unresolved, not reproduced, and has no confirmed connection to Dawnward**. It does not block development unless it recurs. See `docs/COMPATIBILITY.md`.

**Verified:**
- L0, L1 and L2: 180 tests, run locally.
- **L3 (Classic Era 1.15.9):** all 24 mandatory acceptance items pass, including a real level-up, backup/import integrity and coexistence with TRP3 3.4.1 (read-only, TRP3 unchanged). See `docs/TESTING.md`.
- **Untested:** optional checks O1–O6, including UI scaling and the remembered window position. The interface number wasn't reported.
- Not tested on Forever (L4).

## 0.1.0 (foundation): merged, not released

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
- L0, L1 and L2: 103 tests.
- **L3, partial** (Classic Era 1.15.9, Total RP 3 3.4.1): history, persistence, export, import with undo, checksum rejection, simulation mode and default-profile detection were confirmed in game. The copy window fix passed an in-game re-test.
- UI scaling is **untested**, and several checklist steps weren't reported. See the results table in `docs/TESTING.md`.
- Not tested on Forever (L4).

## Repository foundation (2026-10-25)

### Added
- Licence, third-party notices, contribution guide, issue and PR templates, and a CI workflow.
- Architecture, compatibility, privacy, testing, workflow and Total RP 3 integration documents, and the Phase 0 audit and plan.
- Development tooling: a Lua 5.1 test runner and harness, luacheck configuration, and a repository hygiene check.

**Verified:** L0 and L1 for the tooling only. CI passed on GitHub.
