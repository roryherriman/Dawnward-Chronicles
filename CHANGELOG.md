# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/) (`0.x` while pre-release).

Every release entry has a **Verified** line naming the highest test level reached. The levels are defined in [`docs/TESTING.md`](docs/TESTING.md):

- **L0**: static checks
- **L1**: unit tests
- **L2**: mocked integration tests
- **L3**: in game, Classic Era
- **L4**: in game, WoW Forever

A feature is never called "tested" or "compatible" in this file unless it reached L3 or L4.

## [Unreleased]: 0.4.0-dev (the living chronicle)

**Verified: L2** (mocked). Not tested in game yet; see the v0.4 checklist in [`docs/TESTING.md`](docs/TESTING.md#v04-in-game-checklist-l3-the-living-chronicle).

### Added
- **Schema v4:** a per-character `story` table and "story" journal entries, by an additive 3 → 4 migration. No existing value or visibility changes; nothing becomes public.
- **Gameplay events:** quest turn-ins (`QUEST_COMPLETE` + `QUEST_TURNED_IN`), deaths and level-ups become normalised records with a stable key, time, zone, character context, verified metadata, source, confidence and status. They are never recorded twice, across reloads and sessions.
- **Reactions:** authored, universal questions with several moral and emotional directions, a neutral answer, your own words, and Later / Not now / Dismiss. They are paced by frequency, a significance threshold and cooldowns, same-zone quests are folded together, and the queue is bounded. Announced only at a calm moment (never in combat, while dead, in a cinematic or loading).
- **Optional class flavour:** one extra answer per class, with no personality effect. It can be switched off, and never changes the universal answers.
- **Personality evolution:** answers propose one-step changes on the six axes. They apply only on approval (or automatically if you choose; still reversible), with a daily limit, a preserved baseline and a history that also records your manual edits.
- **Living journal:** private story drafts from verified data and your answer; edit, approve, mark as a defining moment, search (`journal search`, `journal drafts`). Drafts cannot be made public before approval.
- **TRP3 presentation:** formatting is separate from narrative data (Neutral, Silver Hand, Arcane), using only markup confirmed in TRP3 3.4.1's source. Approved, public defining moments can appear in Dawnward's own About section. Neutral is the default and gives exactly the v0.3 block.
- **UI:** a working Story section, a small reaction card, journal Approve and defining-moment buttons, and story settings in the settings panel.
- **Commands:** `story`, `develop`, `journal approve|important|search|drafts`, `sim quest`, `sim death`.
- **Narrative records with one shared contract:** each record has provenance (observed, player or suggested), a canon status (proposed, established, disputed or superseded) and a visibility. Suggestions are proposed and private, and only established records can be public.
  - Memories (#12), arcs (#19), goals (#27).
  - Public persona vs private convictions (#30).
  - People: NPCs, other players' characters keyed by name and realm, and family (#18, #28, #37).
- **Story Director (#20, #25):** context-aware answers drawn from your established goals and arcs, a recalled memory, and "why now" from verified data. It is deterministic and runs offline.
- **Continuity review (#42):** finds contradictions and asks what each is (growth, unreliable narration, secret, correction or ignore). It never rewrites canon.
- **World events (#11, #18, #36):** reputation tier changes (silent first baseline), first recorded zone visits and dungeon entries, and guild joins and leaves. An observed standing never implies an attitude.
- **Roleplay moments (#40), timeline (#26), reflection (#29).**
- **Chronicle section** in the window for all of the above.
- Commands: `memory`, `arc`, `goal`, `stance`, `person`, `continuity`, `moment`, `timeline`, `reflect`.
- Docs: a documentation index, the CurseForge (WoW Forever) listing prepared but **not published** (#44), and an unpublished project website (`docs/site/`).

### Fixed
- Story observers passed at most 8 return values from client functions, so the faction ID from `GetFactionInfo` (14th return) would always have been missing.

### Changed
- Personal backups carry the story. Share exports never do, and importing a share export or an older backup keeps the current story.
- `/dawnward status` reports story counts.

## [Unreleased]: 0.3.0-dev (character foundations, experimental TRP3 sync)

**Verified: L2** (mocked). Nothing in this section has been tested in game yet; see the v0.3 checklist in [`docs/TESTING.md`](docs/TESTING.md#v03-in-game-checklist-l3).

### Added
- **Schema v3: character foundations.** Each character gains biography sources, suggestions (interpretations) and their key memory, canon facts, personality values and a reserved wizard table.
  - The v2 → v3 migration only adds empty containers; every v2 value is preserved (L1, L2).
  - v0.2 builds open v3 data read-only.
- **Facts (canon):** nine categories; private by default; at most 200, and canon is never removed automatically.
  - Commands: `/dawnward fact list | add <category> <statement> | vis <#> <level> | remove <#> confirm`.
  - Facts are only created by the player or by explicit promotion of a suggestion; an architecture test enforces this.
- **Biography sources:** stored verbatim (three versions; the current one is never dropped; over 16 KB is refused, never truncated). There are display-only tag-stripping and sentence-splitting helpers.
- **Suggestions:** stable keys; rejected and promoted suggestions are remembered, so unchanged re-imports suggest nothing twice. No automatic promotion exists.
- **Personality axes:** six Dawnward axes, 0–20, private by default: `/dawnward personality list | set <axis> <0-20> | vis <axis> <level> | clear <axis> confirm`. The evolution model is still under review; values are set by the player for now.
- **Exports:**
  - Share exports include public facts and personality only.
  - Backups include facts, suggestions and key memory, and the biography only with `/dawnward export backup biography`.
  - Restoring a backup without a biography keeps the current one. Secret facts carry over.
- `/dawnward status` shows a Foundations line.
- **Experimental Total RP 3 sync (off by default; TRP3 3.4.1 only; L2 only).** Dawnward can keep two things up to date in your own TRP3 profile:
  - its own **Chronicle** section of public facts in the About page;
  - its own personality traits.

  It never changes your text, layout or traits. Safeguards:
  - **Per-character opt-in:** `/dawnward trp3 enable about|traits confirm`, bound to one TRP3 profile. Never on the default profile.
  - **Before each write:** backup and compare-before-write.
  - **After each write:** read-back, with automatic restore on any mismatch.
  - **Conflicts:** they are detected and never silently overwritten (`/dawnward trp3 resolve about|traits keep|reclaim`).
  - **Waits:** no writes while a TRP3 editor holds a draft, in combat, in simulation mode, or after a profile switch.
  - **No churn:** unchanged content writes nothing.
  - **Recovery:** `/dawnward trp3 rollback [#] confirm`, `release`, `backups`, `log`, `preview`.
  - **Manual fallback:** `/dawnward trp3 paste`.
  - The new saved variable is `DawnwardChroniclesTRP3DB`.

### Changed
- The Adler-32 checksum moved to `Util.Checksum`; `Transfer.Checksum` remains as an alias.
- Export text now declares schema 3, so v0.2 builds refuse v0.3 exports as "newer".
- **TRP3 editor detection (PR #9 in-game report):** the biography no longer stays "waiting - the Total RP 3 editor is open" after the editor was closed or after `/reload`. TRP3 3.4.1's edit frames read as shown from load until their tab is drawn, so Dawnward now treats a draft as present only while TRP3's profile page is in edit mode on that section's tab (still including a window closed mid-edit). New read-only `/dawnward trp3 diagnose` shows each guard input (L2).

## 0.2.0 (journal window)

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
  - the story interpretation architecture (`docs/planning/archive/story-architecture-v0.2.md`);
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
