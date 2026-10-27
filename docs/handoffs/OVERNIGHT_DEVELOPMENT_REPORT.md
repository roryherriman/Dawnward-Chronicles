# Dawnward Chronicles: overnight development report (2026-10-27)

> **Status: COMPLETE for this session.** The previous night's report is [OVERNIGHT_2026-10-26.md](OVERNIGHT_2026-10-26.md). The Zone Atlas has its own report: [LOCATION_ATLAS_OVERNIGHT_REPORT.md](LOCATION_ATLAS_OVERNIGHT_REPORT.md).

## A. Executive summary
- **v0.5 code (PR [#52](https://github.com/roryherriman/Dawnward-Chronicles/pull/52)), merged into `main` after CI passed:**
  - The Chronicle overlap bug (#46) is fixed with two-line rows and a no-overlap test.
  - Every record can be created and edited from forms; slash commands are no longer needed.
  - New Places tab with a Homeland link, and family and history forms.
  - Minimap button (#45).
  - First-run guide and searchable help (#51).
  - Weighted Story Director place moments.
  - Reputation goal objectives (#27).
  - Zone Atlas evidence model, `/dawnward atlas` verifier and offline DBC pipeline (#48).
- **Branding, site, README and CurseForge materials (PR [#53](https://github.com/roryherriman/Dawnward-Chronicles/pull/53)): open, NOT merged.**
  - It would replace the current branding on the public README, so it needs your approval.
  - Nothing has been deployed, uploaded or made public.
- **Tests:** `python tools/check.py` passes: hygiene, TOC, luacheck, **519 tests passed, 0 failed**, and the atlas tools self-test. The package builds (`DawnwardChronicles-0.5.0-dev.zip`, 71 files).
- **Not tested in game:** everything new tonight. The morning checklist is in section R.

## B. Safety rules
| Rule | Kept? |
|---|---|
| Issue #24 untouched | Yes. Not read, edited or commented on |
| No WoW Forever compatibility claim | Yes. Forever has no place data, and the verifier says "evidence only" on non-Classic clients |
| No stable release; CurseForge not published, made visible, logged into or uploaded to | Yes. Only documents were prepared |
| SavedVariables not overwritten; additive fields only | Yes. Schema stays at 5; `char.guide`, `ui.minimap` and `places[*].homeland` are cleaned on load |
| TRP3: no silent writes, sync still opt-in | Yes. TRP3 code is unchanged |
| Nothing fabricated (IDs, screenshots, results, URLs) | Yes. No new area IDs; no screenshots; test counts are from real runs |
| No unsafe or failing merges | #52 merged only after local checks and CI passed and an independent review's findings were fixed |
| No unfinished issues closed | Yes. Issues got progress comments only |
| Temporary branding not replaced on live services | Yes. The new identity sits in an unmerged PR |
| No secrets exposed | Yes. The hygiene secret scan passes |

## C. Testing closeout (your 2026-10-26 results)
- Recorded as owner-reported L3 evidence in `docs/COMPATIBILITY.md` ("Kinds of evidence" section and results table) and mapped to checklist parts in `docs/TESTING.md`.
- All passed:
  - persistence;
  - people and relationships;
  - stances, privacy and contradiction review;
  - arcs;
  - goals;
  - journal and memories;
  - TRP3 opt-in sync, editor guard, backup and rollback;
  - place discovery and first visits (Elwynn Forest, Northshire, Goldshire, Lion's Pride Inn);
  - Story Director place reactions;
  - personality approval;
  - marking a meaningful place;
  - Homeland persistence.
- Your observations were acted on:
  - Place prompts are now weighted.
  - Homeland is linked to Places.
  - Chronicle rows no longer overlap.
  - Help is shorter, and the window replaces most commands.
  - Compatibility docs now separate source audits from manual tests.
  - The docs say plainly that a missing reaction can be a cooldown.

## D. GitHub activity
| Item | Result |
|---|---|
| PR #47 (origins and places) | Audited and merged at session start (`a8634d7`) |
| PR #52 (v0.5) | Opened, reviewed (5 findings, all fixed), CI passed, merged |
| PR #53 (branding, site, README, CurseForge docs) | Opened for your approval; not merged |
| Issues closed | #3, #12, #30 (with evidence); #22 as a duplicate of #10 (its unique ask moved to #10) |
| Issues commented, left open | #17, #19, #27, #42, #44, #45, #46, #48, #49, #50, #51 |
| `data/client-db-reference-import` | Checked twice; it holds only its README. Not merged |

## E. UI overhaul (#46, #17)
- **Chronicle rows (#46):**
  - Two lines per row: the text at full width, then the status plus up to five buttons.
  - `ChronicleView.RowRects` is the single source of the layout, and a test checks no parts overlap and everything fits.
  - Six rows per page, with Prev and Next.
- **Forms (`UI/Forms.lua`):** line, text area, cycle and number fields, Save, Cancel and a confirmed Remove. Each field honours its stored byte limit, so edits never truncate text.
- **What the forms cover:**
  - Memories: new and edit, importance.
  - Arcs: kind and state, plus turning points.
  - Goals: target level or faction standing, state, milestone ticks.
  - Stances: including a deliberate contradiction.
  - People: kind, realm for players, private feelings.
- **Places tab:** Mark or Unmark; **Homeland** (confirmed, keeps the field's visibility, and counts only while the field still names the place); **Memory** (linked to the place).
- **Character section:** Add, Edit, visibility and Remove for family and history.

## F. Minimap button (#45)
- Click opens the journal; right-click opens story moments; drag moves the button.
- The tooltip shows how many moments are waiting.
- Its angle and hidden state are saved account-wide. Toggle it in Settings or with `/dawnward minimap`.
- APIs were checked against Blizzard's Classic Era source.

## G. Branding (#49), proposal only
- **Direction A, "dawn over an open book", is chosen.** B (an illuminated tome) and C (a compass and quill) are documented as alternatives.
- **Assets:**
  - SVG mark, lockups (dark, light, transparent) and favicon.
  - PNG icons from 16 to 1024 px.
  - Social preview (1280 × 640) and CurseForge banner (1920 × 480).
  - Preview sheet: `assets/branding/previews/branding-preview.png`.
- **Guide:** `docs/BRANDING_GUIDE.md` covers the palette with contrast ratios, Cinzel and EB Garamond (both SIL OFL), usage rules and provenance.
- **Rebuild:** `tools/branding/build.py`. The geometry is hand-written; nothing is traced or AI-generated.

## H. GitHub Pages and README (#50)
- **Pages:** not enabled, not deployed. The repository's Pages settings could not be read from this environment.
- **Site (`docs/site/`):**
  - Redesigned: hero with the logo and the tagline from #50, how it works, TRP3, features with honest status tags, install, compatibility, FAQ, roadmap, metadata and social preview.
  - Checked at 1280 px and 390 px: no horizontal overflow, no failed requests, light and dark modes.
- **README (in PR #53):** logo header, navigation, current statuses, and a documentation index.
- **Preview:** `python -m http.server -d docs/site 8000`.

## I. CurseForge
- **Project:** exists and is **unlisted** (you confirmed this): https://www.curseforge.com/wow/addons/dawnward-chronicles/preview. Not independently verified, because curseforge.com is unreachable from here.
- **Prepared for a manual update (in PR #53):**
  - `docs/marketing/curseforge/FINAL_DESCRIPTION.md`
  - `BRANDING_GUIDE.md`
  - `UPLOAD_INSTRUCTIONS.md`
  - `docs/handoffs/CURSEFORGE_STATUS.md`, updated
- No API or login was used, and no file was uploaded.

## J. Zone Atlas (#48)
- **Client DB files:** not uploaded yet. The branch had only its README, so no binary was inspected.
- **Built:**
  - `Core/Atlas.lua`: evidence levels `in-game`, `source` and `unverified`, with expected names for 49 areas and 17 maps.
  - `/dawnward atlas` with here, verify, scan and export: read-only, C_Map APIs only.
  - `tools/atlas/client_db.py`: DBC/DB2 header inspection and WDBC AreaTable parsing, split into Classic, later-expansion and instance records.
  - Raw DB files are refused inside the addon.
- No IDs were added, and #48 stays open. Details: [LOCATION_ATLAS_OVERNIGHT_REPORT.md](LOCATION_ATLAS_OVERNIGHT_REPORT.md) and `docs/ZONE_ATLAS.md`.

## K. Onboarding and help (#51)
- **Guide:** eight topics, opened once per character the first time the journal opens.
  - Closing it is remembered per character. It never creates data on read-only saves.
  - It can be replayed from **?**, from Settings or with `/dawnward guide`, and it is searchable.
- **Help:** `/dawnward help` is short; `help <topic or words>` and `help all` give more.
- **Errors:** arc and goal commands missing a record number explain what to type, with an example.

## L. Story Director: weighted place moments
- **Scoring:**
  - A beginning scores 10 and always asks; the first recorded place scores 6.
  - First visits: a capital 3, a town or inn 1, anything else 0.
  - A return scores 0.
  - Ties add points: homeland +4, marked or memory +3, active arc, goal or person +2.
  - "Fewer" place moments subtracts 2.
- **Chance of asking:** 20% / 40% / 60% / 80% for 1–4 points, and always at 5 or more.
- **At 5 or more,** the place also skips the location cooldown (it is deferred to a calm moment, not dropped).
- **Rolls** are fixed per event key, so the same event always gets the same result.
- **Privacy:** only established records count, and the reasons never quote private text.
- **Tests** cover eligibility, cooldowns, weighting and privacy (`tests/spec/director_relevance_spec.lua`).

## M. Backlog done tonight
- **#27:** reputation objectives. A goal can track a standing with a faction the game has shown, from the goal form or with `/dawnward goal reputation <#> <standing> <faction>`. It shows progress and never completes the goal; the continuity review asks you instead.
- **#19 and #42:** their GUI asks (arc editing and a GUI for the review choices) are covered by the new Chronicle forms and Review tab. Still to verify in game.

## N. Automated tests
- `python tools/check.py`: hygiene ok, TOC ok, luacheck ok, **519 passed, 0 failed**, atlas tools self-test ok. The baseline was 478.
- New specs:
  - `core_record_editing_spec`
  - `ui_minimap_spec`
  - `ui_guide_spec`
  - `director_relevance_spec`
  - `atlas_spec`
  - expanded `ui_chronicle_spec` and `ui_character_editing_spec`
- The test mock now models `SetMaxBytes` truncation.

## O. Validation and packaging
- `python tools/package.py` → `dist/DawnwardChronicles-0.5.0-dev.zip`: 71 files; no images, Python or raw data.
- No migration needed: schema 5 is unchanged, and the new fields are additive and cleaned on load.
- Site links checked: every relative link resolves.
- Secrets scan: clean.

## P. Bugs found and fixed tonight
An independent review of PR #52 found five issues. All are fixed in `942fef5`:
- Form text limits could truncate long family or history notes on edit.
- A place memory wasn't linked to its place.
- A stale homeland flag survived a Homeland field change.
- Places buttons looked places up by name instead of exact key.
- A global `_` was written.

**Known limits:**
- Mocked UI tests don't prove FrameXML behaviour.
- The guide also opens the first time the journal is opened from a reaction card.

## Q. Blockers
- The client database files aren't uploaded, and their provenance and redistribution rights are unknown.
- Branding, README and site changes are waiting for your approval (PR #53).
- GitHub Pages is not enabled, which needs your decision.
- The CurseForge update is manual (no API, by design).
- No in-game testing of v0.5 yet.

## R. Morning testing checklist
`docs/TESTING.md`, **Part M** (M1–M18). The short version:
1. Back up `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua`, install the build from `main`, and log in. Check for no Lua errors.
2. Open the journal. The guide shows once (M5); close it, `/reload`, and confirm it stays closed.
3. **Chronicle → Memories → New memory:** confirm the text, status and buttons don't overlap (M8, #46). Add 7 memories to see paging (M9).
4. Edit an arc, a goal (try a faction standing; open the Reputation panel first), a stance and a person (M10–M12).
5. **Places tab:** Mark Goldshire, set Homeland (confirm), write a memory (M13).
6. Minimap button: click, right-click, drag, `/reload` (M1–M4).
7. Family and history: Add, Edit, visibility, Remove (M14).
8. Run `/dawnward atlas`, `atlas verify`, `atlas export` and `atlas scan 1 5000`, and paste the outputs into #48 (M17–M18).
9. Review PR #53's preview images; approve or ask for changes.

## S. Recommended next steps
1. Run part M in game and report the results. Close #45, #46 and #51 if they pass.
2. Decide on the branding (#49). If approved, merge PR #53, then update CurseForge by hand following `UPLOAD_INSTRUCTIONS.md`.
3. Upload the client DB files with their source, or rely on `atlas scan` output to widen place coverage.
4. Decide whether to enable GitHub Pages for `docs/site`.
5. Next features: the journal redesign (#17 remainder), more continuity rules (#42), letters and scrapbook.

## T. Continuation
- `main` holds v0.5 (PR #52). The branding, site, README and CurseForge work is on `feat/branding-site` (PR #53).
- Run `python tools/check.py` before any change.

## COPY EVERYTHING BELOW INTO CHATGPT

```
DAWNWARD CHRONICLES: HANDOFF 2026-10-27

Repo: https://github.com/roryherriman/Dawnward-Chronicles (WoW Classic Era 1.15.9 addon, Lua 5.1; optional TRP3 3.4.1 companion).
State: main = v0.5.0-dev (PR #52 merged). Schema 5 (unchanged). check.py: 519 tests pass, luacheck clean, package builds (71 files).

Merged tonight (PR #52, automated tests only; NOT yet tested in game):
- Chronicle tab: two-line rows (fixes #46 overlap) with paging; New/Edit forms for memories, arcs (+turning points), goals (target level OR faction standing, state, milestone ticks), stances, people; Places tab (mark, set Homeland with confirm, write a linked memory); family/history forms in the Character tab.
- Minimap button (#45): click opens the journal, right-click opens story moments, drag moves it; hide it in Settings or with /dawnward minimap.
- First-run guide (#51): shown once per character; replay from ?, Settings or /dawnward guide; searchable. /dawnward help is short; help all gives the full list.
- Story Director: place moments weighted. Beginning 10 (always asks); first recorded place 6; capital 3; town/inn 1; other places/returns 0; ties: homeland +4, marked/memory +3, arc/goal/person +2; "fewer" -2. Chance 20/40/60/80%; at 5+ always asks and skips the cooldown. Roll is deterministic per event.
- Reputation goal objectives (#27): /dawnward goal reputation <#> <standing> <faction>.
- Zone Atlas (#48): evidence levels (in-game/source/unverified); /dawnward atlas [verify|scan a b|export]; tools/atlas/client_db.py for DBC/DB2. No new area IDs. Client DB files not uploaded yet.

Open for owner approval (PR #53, not merged): branding ("dawn over an open book"), README and site redesign, CurseForge FINAL_DESCRIPTION / UPLOAD_INSTRUCTIONS. Nothing published; GitHub Pages not enabled; CurseForge project is unlisted (owner-confirmed) and was not touched.

Owner-verified in game 2026-10-26 (Classic Era): persistence, people, stances/privacy/contradictions, arcs, goals, journal and memories, TRP3 opt-in sync with backup and rollback, place discovery (Elwynn, Northshire, Goldshire, Lion's Pride Inn), Story Director place reactions, personality approval, marking a place, Homeland persistence.

Next: run docs/TESTING.md Part M in game; paste the /dawnward atlas export and scan into #48; decide on PR #53; then the journal redesign.
Rules: never touch #24; no Forever compatibility claim; no release; no CurseForge changes without the owner; never invent area IDs or screenshots.
```
