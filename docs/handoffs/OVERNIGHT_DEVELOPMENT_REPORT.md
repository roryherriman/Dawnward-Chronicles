# Dawnward Chronicles: overnight development report (2026-10-26)

This report covers one Claude Code cloud session: v0.4 "The Living Chronicle" plus post-v0.4 backlog work, integration, repository cleanup, documentation and CurseForge preparation. It only states results that were produced and checked in this session.

**Nothing in this report was tested in the real game client.** "Tested" always means the automated suite: Lua 5.1 with a mocked WoW client and a Total RP 3 3.4.1 fake.

<!-- MERGE-STATUS -->

---

## A. Executive summary

- **v0.4 is complete at the automated level.** The minimum playable loop works end to end in mocked tests:

  ```
  gameplay event -> contextual reaction -> player decision -> personality evolution -> journal entry -> optional approved TRP3 publication
  ```

- **Version:** `0.4.0-dev`, saved data schema **4** (additive migration from 3).
- **Major systems added:**
  - gameplay events (quests, level-ups, deaths, first zone visits, dungeon entries, reputation tiers, guild changes, player-authored moments);
  - a paced reaction queue, announced only at calm moments;
  - player-approved personality evolution;
  - story journal drafts with approval and defining moments;
  - a shared record contract (provenance, canon status, visibility) used by memories, arcs, goals, persona vs convictions and people;
  - a Story Director (context-aware prompts) and a continuity review;
  - a timeline and reflection;
  - TRP3 presentation styles;
  - two new GUI areas (Story section, Chronicle section) and a reaction card;
  - a README overhaul with the companion-to-TRP3 positioning, an unpublished website and an unpublished CurseForge listing.
- **Tests:** 180 → 338 (v0.3) → **441 passing, 0 failing** (`python tools/check.py`: hygiene, TOC, luacheck, tests).
- **Important unfinished work:**
  - no in-game verification of any v0.3/v0.4 feature;
  - GUI redesign (#17) and the import wizard (#23) not started;
  - dungeon boss detection not built (its events are unverified on Classic Era);
  - WoW Forever untested (release gate #24 deliberately not run).

## B. GitHub development activity

- Repository: https://github.com/roryherriman/Dawnward-Chronicles (default branch `main`).
- **Branches:**
  - `feat/v0.3-character-foundations-d5vaq9`: v0.3, PR [#9](https://github.com/roryherriman/Dawnward-Chronicles/pull/9). Head `7746032`, the TRP3 editor-detection fix made earlier in this session.
  - `feat/v0.4-living-chronicle`: all v0.4 and backlog work, PR [#43](https://github.com/roryherriman/Dawnward-Chronicles/pull/43), stacked on #9.

**Commits on `feat/v0.4-living-chronicle` (oldest first):**

| SHA | What |
|---|---|
| `32bba27` | v0.4 core: events, reactions, decisions, personality evolution, story drafts, schema v4 |
| `142bd64` | Story actions and commands, quest/death/level-up observers, safe-time notices |
| `70ab58e` | TRP3 presentation styles, defining moments in the About block |
| `74faa39` | Story section, reaction card, journal approvals, story settings; backups carry the story |
| `1484c8c` | Docs: v0.4 plan, verified APIs, TRP3 markup, checklist G–I |
| `93cc0c2` | README overhaul |
| `cf1e7f7` | Unpublished project website |
| `2dc1933` | Narrative architecture: records contract, memories, arcs, goals, identity, Director, continuity |
| `d05b711` | World events and people; fix for the dropped `GetFactionInfo` return values |
| `254f9b7` | Chronicle section |
| `e1552d0` | Player moments, timeline, reflection |
| `da2bdb6` | CurseForge listing prepared offline (#44) |
| `966b69e` | Repository cleanup |
| `89e2e2d` | Docs for the later batches |
| `da5dfca` | Performance and bounded-growth tests |

Later commits (review fixes, the final report) are listed in section M.

**Issues.** None was closed: every one still needs in-game verification or has unmet GUI acceptance criteria. Progress comments were posted (see M).

| State | Issues |
|---|---|
| Substantially implemented (automated tests), awaiting in-game checks | #12, #19, #20, #25, #27, #30, #42 (core, chat commands and the Chronicle section) |
| Partially implemented | #10 and #22 (styles and markup audit; no per-section template editor or preview UI), #11 (zones, instances, reputation, guild; no bosses or encounters), #13 (approve, edit, search, defining moments; no diff, reorder or pin UI), #14 (pacing, card, quiet modes; accessibility and scaling untested), #18 (observed standing plus stance plus NPC records; no relationships UI beyond the list), #26 (timeline from chat only), #28 and #37 (people records; no graph or tree view), #29 (Reflect), #36 (guild events; no organisation records), #40 (player moments), #44 (listing prepared; project not created) |
| Blocked on the real client or second players | #3–#7 and #15 (TRP3 in-game and two-client verification), #8 (owner's decision to contact TRP3 maintainers) |
| Not started | #16, #17, #21, #23, #31, #32 (beyond the existing export/import), #33, #34, #35, #38, #39, #41 |
| Excluded | **#24, not run, not touched** |

## C. Implemented functionality

Every module is pure Lua 5.1 under `DawnwardChronicles/Core/` unless noted. Every write goes through `Core/Actions.lua`: read-only saved data is refused, and a failed first write creates nothing. Simulation mode keeps a separate database.

**Gameplay events** (`GameEvents.lua`, `Platform/Observers.lua`)
- Categories: quest (`QUEST_COMPLETE` caches ID, title and quest level; `QUEST_TURNED_IN` records it), level-up, death, first recorded zone visit, first recorded dungeon/raid entry, reputation tier change, guild join/leave, and player moment.
- Each record holds: a stable key (duplicates are refused across reloads, and keys outlive pruned records), time, zone, level, class/race/faction tokens, verified metadata, source, confidence (verified / partial / player) and status.
- Significance (1–3) comes from explicit rules on verified data only.
- **Enabled by default; no TRP3 involvement.**
- Limits:
  - A record is created only for characters that already use Dawnward (except level-ups, as in v0.2).
  - Repeatable quests are recorded once.
  - The first reputation and guild readings are silent baselines.

**Reactions** (`ReactionLibrary.lua`, `Reactions.lua`, `Platform/SafeTime.lua`, `UI/ReactionCard.lua`)
- Templates are authored and universal. Each has 4 directional answers plus a neutral one, a theme tag per answer, and neutral fallback questions when details are missing. There are 11 templates across the categories.
- Optional class flavour adds one effect-free answer; all 9 Classic classes are covered, and it can be switched off.
- The queue (at most 20) applies frequency (off / rare / normal / frequent), a threshold, per-category cooldowns, same-zone quest coalescing, expiry after 7 days, and Later / Not now / Dismiss.
- SafeTime announces a moment with one chat line and an optional card. It never announces in combat, while dead or a ghost, during a cinematic or a loading screen; it checks on calm-moment events and never polls.
- **Enabled by default.**

**Decisions and personality evolution** (`Decisions.lua`, `Evolution.lua`)
- An answer proposes ±1 changes on the existing six axes (0–20). The default is "ask": the change waits for approval. "auto" applies it at once, still reversible.
- At most 2 steps per axis per day. Values never go past 0 or 20; a blocked change waits instead of being clipped.
- The player's own value is kept as the axis baseline. An unset axis starts at 10, private.
- Manual edits are recorded in the same history.
- Custom answers propose nothing.
- Class, race and faction are never inputs (tested).

**Living journal** (`Narrative.lua`, `Journal.lua`, `UI/JournalView.lua`)
- Story drafts are private and written from verified data plus the player's answer or own words.
- Drafts can be edited, approved and marked as defining moments, and searched (`journal search`, `journal drafts`).
- **A draft cannot be made public before approval.** Loading data repairs any draft that was stored as public.
- Retention prunes milestones first, then unapproved drafts; never approved, important or player-written entries.

**Records contract** (`Records.lua`, `RecordTypes.lua`)
- Provenance (observed / player / suggested), canon status (proposed / established / disputed / superseded) and visibility are separate fields.
- Suggestions are always proposed and private. Public requires established.
- Established suggestions can't be deleted, only disputed or superseded.
- All records live in the per-character `story` table; there is no new SavedVariables store.

**Narrative modules**
- **Memories:** suggested from notable answers and custom words, or written by the player.
- **Arcs:** suggested when 3 answers share a theme; rename, pause, conclude and turning points.
- **Goals:** a verified level objective kept apart from player-ticked milestones; never completed automatically.
- **Identity:** a public persona per subject, plus a private conviction with its own visibility.
- **People:** NPCs, players keyed by name and realm (never merged) and family, with private feelings and no score.
- **Director:** ranks established records only, adds contextual answers (goal, arc), recalls a memory and explains "why now"; nothing is cached.
- **Continuity:** 6 rules (persona vs conviction, axis vs trait fact, disputed records, goal objective met, duplicate memories, public linked to secret). The player's answers are recorded; canon is never rewritten.
- **Timeline:** a view over existing records; undated backstory is never given a date.
- **Reflection:** brings back moments kept for later.
- GUI: the **Chronicle** section (`UI/ChronicleView.lua`). Commands: `memory`, `arc`, `goal`, `stance`, `person`, `continuity`, `moment`, `timeline`, `reflect`.

**Backups:** personal backups carry the story table. Share exports never do, and importing a share export or an older backup keeps the current story.

## D. TRP3 integration

**Architecture (from v0.3, unchanged in its guards):**
- `Integrations/TRP3/Adapter.lua` is the only module that touches TRP3 for sync.
- Allowlisted for TRP3 3.4.1 only.
- Opt-in per character, bound to one non-default profile ID. Never in simulation, combat, after a profile switch, or while an editor holds an unsaved draft (fixed earlier in this session: commit `7746032`).

**What it writes:**
- A Dawnward-owned Chronicle section in the About page: an appended block in template 1, its own frame in template 2, or appended to the history in template 3.
- Dawnward-owned personality traits.

**Safety mechanisms:**
- Ownership is an exact match against the ledger.
- Any edit by the player is a conflict, resolved with keep or reclaim; it is never overwritten.
- A backup is taken before every write, and the result is read back. A mismatch restores the backup automatically and switches sync off.
- `rollback`, `release`, `preview`, `backups` and `log` commands.

**Changes tonight:**
- `Presentation.lua` styles: Neutral (default, byte-identical to v0.3, so an upgrade never rewrites a synced profile; tested), Silver Hand and Arcane. They use only markup confirmed in TRP3 3.4.1's source: `{h1-3}`, `{col:RRGGBB}`, `{icon:…}`. All player and game text is escaped.
- The About block can now also contain approved, important, public story entries ("Defining moments") and established public stances ("Where they stand"). A private conviction is never included unless it is itself public.
- Public facts and public axes flow as before.

**Privacy:**
- The story table never enters a projection.
- Drafts can't be public.
- Tests cover share export, the About block and the identity projection.

**Unsupported or unused:** TRP3 has no public setters for About or traits (documented in #8). Fonts can't be chosen in TRP3 markup.

**Risks:**
- Internal writes depend on TRP3 3.4.1's structure; other versions refuse.
- Rendering of the Silver Hand and Arcane styles is unverified in game.
- Multiplayer propagation is unverified (#7, #15). Not claimed.

## E. Automated testing

- **Command:** `python tools/check.py`. It runs repository hygiene, TOC completeness, luacheck (L0) and the Lua 5.1 suite (L1 unit, L2 mocked client and TRP3 3.4.1 fake).
- **Final result:** **441 passed, 0 failed**; hygiene ok, TOC ok, luacheck ok (0 warnings).
- **New spec files:** `core_story_spec`, `story_loop_spec`, `trp3_presentation_spec`, `ui_story_spec`, `core_narrative_spec`, `world_events_spec`, `ui_chronicle_spec`, `storytelling_spec`, `performance_spec`.
- **Regression coverage includes:**
  - v3 → v4 migration with nothing changed and nothing published; idempotent normalisation;
  - duplicate events across reloads;
  - combat, death and cinematic guards;
  - the universality scan (no class, race, faction, city, deity, moral-label or gendered words in universal text);
  - identical universal prompts and effects for 10 fixture characters (Human Paladin, Orc Warlock, Night Elf Druid, Undead Rogue, Dwarf Priest, Tauren Warrior, Gnome Mage, Troll Shaman, Night Elf Hunter, and an unnamed Undead Mage), with personalities set against stereotype;
  - no private data in share exports or TRP3 output;
  - idempotent repeated sync;
  - the v0.3 block unchanged under the default style;
  - release restores the player's text exactly;
  - burst events schedule at most one check.
- **Failures found and fixed while developing:**
  - The template selection gave a "challenge" question for a first quest in a zone; it now needs verified difficulty.
  - The observers' pcall wrapper dropped return values after the 8th, so reputation would have failed in game.
  - Tests were adjusted for the new 4th tab and the version bump.
- **Performance (Lua 5.1 interpreter on the CI machine, not the WoW client):**
  - 5,000 quest events with a decision every third event took about 9 s, roughly 1.8 ms per event. The suite now runs 2,000.
  - All saved lists stayed within their limits.
  - No in-game profiling has been done.
- **Mocked vs real:** everything above is mocked. No test touched a real WoW client, a real TRP3 or real SavedVariables.

<!-- REVIEW-FINDINGS -->

## F. Bugs and limitations

- **Fixed tonight:**
  - TRP3 editor detection: a false "editor is open" after `/reload` (`7746032`);
  - the challenge-template selection;
  - the 8-value pcall truncation;
  - review findings (section M).
- **Unresolved or known limitations:**
  - Factions under a collapsed reputation header aren't listed by the client.
  - "First visit" means the first visit Dawnward recorded.
  - Standing names are English fallbacks.
  - Repeatable quests are recorded once.
  - A level-up records a character even if it never used Dawnward (v0.2 behaviour).
  - A stance must be added from chat; the GUI lists it but has no form.
- **Data risks:** none known. Migrations are additive and tested; read-only mode protects newer or unknown data. **Still back up SavedVariables before installing.**
- **UI concerns:**
  - The new sections were laid out by coordinates and tested for fit, but have never been seen on screen. Clipping and long-text overflow at various UI scales are untested.
  - Option buttons can truncate long answer text.
- **API concerns:** every new API is source-confirmed (1.15.9 interface source), none in game. Encounter and boss events are unverified, so they aren't used.
- **Technical debt:**
  - Story commands live in several command modules.
  - The Chronicle section has no edit forms (edits go through chat).
  - English-only strings.
- **Needs manual verification:** everything in the in-game plan (J).

## G. GUI and user experience

- **The window:** `/dawnward` opens the existing 620 × 520 themed window (Neutral, Silver Hand, Arcane; any character can use any theme). It has four sections:
  - **Journal:** entries, with Approve and `*` (defining moment) on story drafts.
  - **Character:** profile, family and history (v0.2).
  - **Story:** a summary with the next suggested step, the waiting moment's question and answers, an own-words box, Later / Not now / Dismiss, Reflect, personality changes to approve or reject, and "why now" plus a recalled memory.
  - **Chronicle:** Memories, Arcs, Goals, Stances, People and Review tabs with provenance, status and visibility on every row.
- **Gear (settings):** theme, backup and import, simulation, story settings (moments frequency, significance, approval, drafts, card, class flavour, TRP3 style, quest tracking) and TRP3 status.
- **Reaction card:** a small, non-blocking card at a calm moment, with Answer / Later / Dismiss.
- **Biography import:** only the v0.3 foundations (verbatim sources, suggestions); there is no import wizard (#23 not started).
- **Timeline:** chat only (`/dawnward timeline`).
- **Remaining:** the immersive redesign (#17), a resizable window, edit forms in the Chronicle section, scaling and accessibility checks.

## H. Documentation and presentation

- **README.md** rewritten:
  - tagline;
  - "Built to Complement Total RP 3 — Not Replace It";
  - how it works;
  - features with honest status markers;
  - install, getting started, customisation, development status, compatibility (Forever pending), contributing, licence and TRP3 credit.
- **docs/README.md** (new index). Updated: `ARCHITECTURE.md`, `COMPATIBILITY.md` (every new API with its source evidence), `TESTING.md` (checklists G–K), `TRP3_INTEGRATION.md` (markup), `CHANGELOG.md`, `docs/planning/v0.4-plan.md`.
- **Website:** `docs/site/`, static and responsive, checked at phone and desktop widths. **Not published**; GitHub Pages is not configured.
- **GitHub repository description and topics:** not changed. The tools available in this session can't edit repository settings. A suggested description and topics are in section M.
- **CurseForge:** `docs/marketing/curseforge/LISTING.md` and `PUBLICATION_CHECKLIST.md`.

## I. CurseForge status

From `docs/handoffs/CURSEFORGE_STATUS.md`: **Project URL: NOT CREATED.**
- There was no CurseForge access in the session.
- CurseForge documents no private draft state: a project goes live once the project and a file are approved.
- WoW Forever is unverified.

Search results suggest CurseForge lists Forever addons under game version 1.60.1, and that they use Interface 16001. This was not confirmed in the author console.

## J. Tomorrow morning in-game test plan

Use WoW Classic Era 1.15.9 with a **test character**. Use **a disposable TRP3 profile** for anything TRP3.

1. **Back up first.** Exit WoW. Copy `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua` and `totalRP3*.lua` somewhere safe.
2. **Install.**
   - Build `python tools/package.py` from the merged commit (or the `feat/v0.4-living-chronicle` head).
   - Replace `World of Warcraft\_classic_era_\Interface\AddOns\DawnwardChronicles\`, so that `DawnwardChronicles.toc` sits directly inside it.
   - Keep Total RP 3 3.4.1 installed.
3. **Log in.**
   - Expect "Saved data upgraded from schema 3" (or schema 2 if you were on v0.2) and no Lua errors (`/console scriptErrors 1`).
   - Run `/dawnward status`: version 0.4.0-dev, and a Story line.
4. **Upgrade safety.** Your journal, facts and personality are unchanged, and nothing became public (`/dawnward show public`).
5. **The quest moment (the core loop).**
   - Turn in a quest out of combat. Expect one chat line plus a card naming the quest.
   - Click Answer, then pick an answer.
   - Approve the change in the Story section. `/dawnward personality list` shows exactly ±1.
   - Journal: a private draft. Making it Public is refused. Approve it, mark it `*`, then make it Public.
6. **Calm moments.**
   - Turn in a quest during combat: no card until combat ends.
   - Die: nothing while dead; it may appear after reviving.
7. **Persistence.** `/reload`, then `/dawnward story events`: the same records, no duplicates; drafts and approved changes kept.
8. **Chronicle tab.**
   - Add a memory and accept a suggested one.
   - `/dawnward goal add …`, `/dawnward stance add Subject; public; private`. The Review tab asks about the contradiction.
9. **World events.**
   - Enter a new zone and a dungeon: `/dawnward story events` shows "First recorded …".
   - After a reputation gain that crosses a tier: one event (none at login).
10. **TRP3: disposable profile only.**
    - Switch TRP3 to the disposable profile. `/dawnward trp3 enable about confirm`, then `/dawnward trp3 preview`.
    - After step 5's public defining moment: the About page shows your text, then Chronicle, then "Defining moments:".
    - Make the entry private: it disappears.
    - `/dawnward story set trp3Style arcane`: screenshot it.
    - `/dawnward trp3 rollback confirm`, then `/dawnward trp3 release about confirm`: your text is exactly as before.
11. **Conflict.** Edit a word inside Dawnward's section in TRP3, save, then add a public fact. Sync pauses with a conflict and your edit is kept.
12. **Editor guard.** Open TRP3's About editor, close the window without saving, then `/dawnward trp3 diagnose`. Then `/reload` and run it again: no longer waiting.
13. **Collect:**
    - screenshots of the Story section, the card, a draft, the Chronicle tab, and the TRP3 About page (each style);
    - `/dawnward trp3 diagnose` output;
    - any Lua error text;
    - `/dawnward status` output.
14. **Do NOT yet:** enable sync on your real TRP3 profile; test on WoW Forever; rely on multiplayer propagation.

Full checklists: `docs/TESTING.md`, parts A–F (v0.3) and G–K (v0.4).

## K. Recommended next steps

1. Run the in-game plan above. Fix what it finds before adding features.
2. Then #17 (GUI redesign: edit forms, a resizable window, a dashboard), with #13 and #14 UI parts folded in.
3. #23 and #16 (story import wizard and onboarding; the v0.3 sources and suggestions layer is ready).
4. #21 (custom personality rules), #10 and #22 (template editor and preview), #31 (letters), #41 (scrapbook).
5. Probe `ENCOUNTER_END` and `BOSS_KILL` with `/etrace` in a Classic dungeon before building boss moments (#11).
6. Two-client TRP3 tests (#7, #15), then the Forever TOC (Interface 16001 per community reports), then #24 last.

<!-- CLEANUP -->

<!-- SECTION-M -->

<!-- CHATGPT -->
