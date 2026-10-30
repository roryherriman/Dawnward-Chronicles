# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/) (`0.x` while pre-release).

Every release entry has a **Verified** line naming the highest test level reached. The levels are defined in [`docs/TESTING.md`](docs/TESTING.md):

- **L0**: static checks
- **L1**: unit tests
- **L2**: mocked integration tests
- **L3**: in game, Classic Era
- **L4**: in game, WoW Forever

A feature is never called "tested" or "compatible" in this file unless it reached L3 or L4.

## [Unreleased]: 0.8.0-dev (pre-playthrough candidate)

**Verified: L2** (mocked). Nothing in this section has been tested in game yet.

### Automatic Total RP 3 sync (#4, #5, #6, #7, #10, #15)
- **Five profile fields, kept up to date:**
  - **Which fields:** Title (TRP3 full title), Race, Class, Age and Homeland (shown in TRP3 as Birthplace).
  - **Source:** your Public Dawnward profile, one field at a time.
  - **When:** only after you authorise it. Every field starts as "Managed by Total RP 3".
- **Never overwritten:**
  - **Your own values:** Dawnward writes a field only while it is empty, or still holds exactly what Dawnward last wrote. A value you wrote in Total RP 3 (even one that happens to match) is never claimed or overwritten: that field pauses until you choose **Keep yours** or **Use Dawnward's**. The other fields keep updating.
  - **Back to Private:** a field you make Private again is taken back out of Total RP 3, only if it still holds Dawnward's value.
- **Total RP 3 page, new Mappings tab:** who manages each part, a preview of the first sync (Public values only), a warning when several characters share the profile, and the list of what Dawnward never writes (and why).
- **Compare and import:** compare Total RP 3 with your Public values, and import a value into Dawnward explicitly (Private by default). Total RP 3 never changes Dawnward by itself.
- **New commands:** `/dawnward trp3 fields`, `trp3 field <name> dawnward|trp3|off confirm`, `trp3 import <field> confirm`.
- **Rollback is now visibility-aware:**
  - **Preview:** it first lists anything in the backup that is no longer Public.
  - **Default (`rollback confirm`):** it restores your own text and rebuilds Dawnward's part from today's Public data.
  - **Exact restore (`rollback exact confirm`):** brings the old section back unchanged, after a confirmation naming what would become visible again.
  - **Never automatic:** rollback never runs by itself.
- **Reliability:**
  - a sync that waited for combat runs as soon as combat ends;
  - retries are bounded per change, and "still waiting" is reported once;
  - Dawnward's own write no longer triggers a second run;
  - an exact rollback is read back and undone at once if it does not match.
- **Not synchronised automatically:**
  - first and last name;
  - the short title;
  - pronouns;
  - faith, occupation, appearance, summary and motivation;
  - Currently, OOC and RP status;
  - eye colour, height, weight, residence and relationship.

  The manual `trp3 paste` text now carries every Public profile field.
- **Multiplayer:** a two-client test procedure is in `docs/TRP3_INTEGRATION.md`. Multiplayer propagation is **not verified yet**.
- **From the code review:**
  - **Backups:** Total RP 3 backups always keep the state from before Dawnward's first write, and any value you handed over with "Use Dawnward's".
  - **No altered values:** a value Total RP 3 would alter is never written, shortened, or used to clear a field.
  - **Handing a field back:** this first removes a Dawnward value that is no longer Public, unless you choose to keep it.
  - **Authorize:** it applies all your choices or none.
  - **Reads and imports:** reading Total RP 3 for import needs an audited version, and an import that would be shortened is refused.
  - **Less work:** updates to other players' profiles no longer trigger a sync.
- **Undo answer** in Continuity review never makes anything Public again: a hidden side that was Public comes back as Private. A backup without secrets leaves out the text of answered findings.

### Story Director context and continuity (#20, #25, #42)
- **Moments draw on your established story:**
  - **Ranking:** goals, arcs and memories that name the place or faction rank first.
  - **Stances:** a stance about the event's subject can offer one answer, which never shows the private conviction.
  - **Why now:** names your homeland, marked places, people, a standing that rose or fell, and your goals and stances about a faction.
  - **Last time:** recalls your own earlier answer about the same situation.
- **New authored wording** for a return to your homeland, and for a standing change with a faction you have a stance on.
- **No repeated questions:**
  - **Window:** the same question about the same place, faction, zone's quests, instance or guild is not asked again within 3 narrative days of play (`/dawnward story set repeat 0-14`).
  - **Diagnostics:** `dev story status` explains each suppression.
  - **Frequency:** this only ever lowers how often you are asked.
- **Continuity review:**
  - **Examine:** shows the records side by side with their dates and origin.
  - **Edit:** opens a record's own form.
  - **Explain:** keeps your note with your answer.
  - **Undo answer:** in the Answered list.
  - **New checks:**
    - a public stance contradicting a public fact;
    - a goal marked achieved with open steps, or before its objective is reached;
    - a memory dated before its event;
    - a missing replacement record.

  Nothing is ever rewritten for you. Chat: `/dawnward continuity examine|explain|answered|undo <n>`.

### Character journey (#13, #16, #19, #21, #23, #27, #32)
- **Import a story you already wrote:**
  - **How:** paste it, or read your Total RP 3 About text, read-only and without Dawnward's own block.
  - **Exact text:** it is kept word for word (up to 16 KB, never cut).
  - **Review:** you approve, edit or skip each sentence or paragraph before it becomes part of your character, as Private by default. Approving as Public shows exactly what becomes public and asks first.
  - **Re-importing:** it only suggests what is new.
  - **Where:** Character → Import story, Settings → Data → Your story, the setup wizard's Character step, or `/dawnward biography`.
- **Your own words for personality:** name each axis's two ends in your own words, write what it means, or lock it so story answers never propose changing it. Click an axis in Character → Personality. Everything is reversible ("Use Dawnward's words").
- **Rejecting a suggested arc** (`/dawnward arc reject`, or Remove in Chronicle) stops that theme being suggested again. Before, a removed suggestion came back.
- **Publishing a journal entry:** making it Public shows exactly what becomes shareable and asks first.
- **Restoring a backup:** the preview lists what changes for each record type ("now → after") and warns if the backup came from another character. Backups now keep your axis meanings.
- **Privacy fix:** public facts no longer carry the original sentence they were approved from into share exports or Total RP 3.
- **Tests:**
  - arcs and goals never reach any public output;
  - a full backup round trip covers every record type;
  - a damaged saved character is repaired without losing the rest.
- **Deferred:**
  - filling profile fields from an import (it would mean guessing);
  - a diff view when re-importing;
  - journal reordering and pinning;
  - selective export.

### Gameplay events and locations (#11, #14, #18, #35, #48)
- **Zone Atlas:**
  - **Evidence:** the owner's in-game export and 1–5000 scan from #48 are kept verbatim, with their SHA-256 checked, and all 17 maps and 49 areas are promoted to in-game evidence.
  - **Candidate settlements:** 49 settlements outside the starting zones are named by `/dawnward atlas`, with the uiMap shown as evidence. They are never classified as places until their parent map is confirmed.
  - **Quarantine:** a list stops unused, test, open-sea and generic battleground area IDs from ever being classified.
- **Interiors:** a building the client reports as the zone (for example Lion's Pride Inn) is logged as a place inside its zone. Places logged before keep their names.
- **Trimmed names:** place names are trimmed, so a name with a trailing space (Bloodvenom Post) is no longer logged again after every reload.
- **Calmer timing:** story notices also wait while you are AFK or inside a dungeon or raid, and Escape hides the reaction card (the moment keeps waiting).
- **Goals in context:** reputation and level moments say when they move an active goal forward or reach its target. They never complete the goal; only you decide that. They also note when you have written a stance toward that faction, without quoting it.
- **Encounter probe:** a development-only probe notes whether `ENCOUNTER_END` or `BOSS_KILL` fire on Classic Era (`/dawnward dev story status`). Nothing is saved or recorded from them.
- **Deferred:**
  - boss and dungeon-completion events (not yet shown to fire on Classic Era);
  - promoting candidate settlements (needs parent-map evidence);
  - wilderness and danger kinds (no client data);
  - localised clients and WoW Forever.

## [Unreleased]: 0.7.1-dev (fixes from the first in-game inspection)

**Verified: L2** (mocked). The fixes below answer the owner's first in-game inspection of v0.7. None is confirmed in game yet; see part T of [`docs/TESTING.md`](docs/TESTING.md).

### Fixed
- **Character Showcase live model:** the model never appeared ("Portrait: model unavailable"), and switching back from the portrait did not work.
  - **Cause:** after a failed load, and in portrait mode, the model frame was hidden. Every later attempt then ran on a hidden model frame, which cannot load, so one failure or one visit to the portrait blocked the live model for good.
  - **Now:** the model frame stays shown (the portrait mode only makes it transparent). A failed load is retried for about 8 s, and again on reopening, on a gear change and after a loading screen. "Try the live model again" is always available.
  - **Mode:** the chip says which mode is showing (Live model, Loading, Portrait by choice, Portrait because the model is unavailable).
  - **Diagnostics:** `/dawnward dev showcase` reports what the client returned.
- **Chronicle → Review:** the answers are real buttons with readable labels and an explanation each.
- **Chronicle cards:** a title cut short shows in full on hover.
- **Settings → Total RP 3:** backups are two-line rows (name, then the full date), no longer crowded.
- **Settings → Story:** each button shows its current value in words, with a "›" for "click for the next option"; the tooltip lists every option and marks the current one.

### Added
- **Resizable window:** a gold grip in the bottom-right corner.
  - **How it resizes:** it scales the whole window, keeping the approved layout's proportions, between 0.7 (still readable) and 1.4, never beyond the screen.
  - **Persistence:** the size is remembered across `/reload` and logout, and the window is re-fitted when the UI scale or resolution changes.
  - **Reset:** Settings → General → Reset window size.

### Saved data
- Additive and cleaned on load: `ui.windowScale`, `ui.position.scale`.

## [Unreleased]: 0.7.0-dev (approved visual direction, gameplay time)

**Verified: L2** (mocked). Not tested in game yet; see parts Q, R and S of [`docs/TESTING.md`](docs/TESTING.md). Design: [`docs/design/UI_DESIGN_V07.md`](docs/design/UI_DESIGN_V07.md). Builds on 0.6.0-dev below, which is also unreleased.

### Added
- **Every screen rebuilt to the approved mockups:**
  - **Journal dashboard:**
    - "The road so far", with real counts;
    - New entry, search, and All / Defining / Story / Events filters;
    - a "moment awaits" callout with Answer and Later;
    - entry cards with date block, meta line, status chips, visibility and actions;
    - Active goals with progress, and Recent places.
  - **Character profile:**
    - Identity, Background and Summary panels of tiles, each with its own visibility chip and Edit;
    - personality values with changes waiting for approval;
    - family and relationships;
    - a public profile preview built from the same public projection as exports and Total RP 3.
  - **Character Showcase:**
    - turning, and zoom with buttons and the mouse wheel;
    - a portrait choice remembered per character;
    - "In game" identity (level, race, class colour, guild, realm), read live, shown apart from what the player wrote.
  - **Story Director:**
    - event context, "why now" from the Director's real reasons, and the memories it recalls;
    - a two-column choice grid, own words with inline validation, and Later / Not now / Dismiss;
    - other waiting moments;
    - growth to approve, with reasons, Approve, Reject and Reverse.
  - **Chronicle:**
    - cards for Memories, Arcs, Goals, Stances, People and Review, with tab counts and search;
    - Places as list and detail, including when a return could next become a moment.
  - **First-time setup:**
    - a step rail, grouped panels, your portrait on the Character step and privacy chips;
    - Total RP 3 status only (setup never publishes).
- **Total RP 3 page** (Settings → Total RP 3, or the rail's Total RP 3 line):
  - **Status:** installed, version, linked profile, and sync per feature.
  - **What would be written:** exactly what would be shared (public only), the proposed changes, and what is never shared (as counts). It also lists the fields Dawnward never writes.
  - **Approve and write**, conflicts with Keep yours / Use Dawnward's, and backups with Roll back.
  - It writes only through the same guarded functions as `/dawnward trp3`. Opening or previewing writes nothing.
- **Shared components:** chips, panels, callouts, date blocks, progress bars and search boxes.
- **Approved mockups** in [`docs/design/mockups`](docs/design/mockups/README.md): seven approved design concepts (Journal, Character, Story Director, Chronicle memories and places, first-time setup, design system) and two proposals awaiting approval (Total RP 3 sync page, Character Showcase). They are design concepts with sample data, not screenshots, and are not part of the addon package.
- **Window shell (stage A):**
  - A permanent character rail with the player's portrait, name, title, race, class, pronouns and level, and the section navigation, with a badge counting moments waiting on Story.
  - Guide and Settings are at the bottom of the rail.
  - A header with an eyebrow and a title.
  - A Total RP 3 status line.
  - The window scales down to fit small screens by width as well as height.
- **Character Showcase:** the player's live 3D model beside the profile, in the gear being worn. Turn it with buttons or by dragging. The portrait is shown when the model is unavailable, and nothing renders while the journal is closed.
- **Bundled fonts:** Cinzel and Alegreya Sans (SIL OFL 1.1). Clients in languages the fonts do not cover keep the game's fonts.
- **Story pace** setting (Settings → Story): Brisk, Standard (default) or Slow narrative days.
- `/dawnward dev story simulate time <n>m|h|d [place]`: shows what a return would do after that much more play, on a discarded copy (development builds only).

### Changed
- **Story Director counts gameplay time.**
  - Return visits and moment cooldowns now use a per-character narrative clock that advances only while you play: not while logged out, and not while AFK.
  - A narrative day is 2 hours of play by default.
  - A return needs 1 narrative day away, and a place's weekly return 7.
  - Unanswered moments expire after 7 narrative days, at the pace in force when they were created, so changing the pace never removes a moment already waiting.
  - Changing the computer's clock no longer affects any of this.
  - Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#gameplay-time-the-narrative-clock).
- `/dawnward dev story status` shows the narrative clock and day, time away from the place, play still needed, cooldowns and why a return would or would not happen.
- The Classic Dawnward theme uses the colours of the approved design system.
- Setup wizard: an over-long field now shows an inline error instead of being cut silently, and clicking a step in the rail jumps to it.
- **Total RP 3 rollback** now warns, before confirming, that the restored section comes back exactly as it was, including anything Dawnward wrote then from items since made Private or Secret. Rollback itself is unchanged.
- Changes made in the window now prompt an opted-in Total RP 3 sync to catch up, as slash commands already did.
- The README, site and CurseForge drafts describe Dawnward's own full character profile accurately: it is not meant to replace Total RP 3's public social profile, and shares approved public information through the optional integration.

### Fixed (found in review before merge)
- The bundled fonts never loaded in the real client: a Font object's `SetFont` returns nothing in 1.15.9. Each font file is now checked once on a hidden font string.
- Tooltips on plain hover areas could not show (mouse input was off).

### Saved data
- Waiting moments gain `expiresPlay` (their own deadline in play time).
- One additive key, `DawnwardChroniclesDB.ui.showcase[characterKey]`, holds the Showcase portrait choice only when chosen. It is cleaned on load.

### Migration
- Additive. The schema number is unchanged.
- Each character gains a narrative clock starting at zero.
- Places, marks, Homeland, memories and history are untouched.
- Places logged before the upgrade start counting time away from their next visit, so the upgrade cannot cause a burst of return moments.
- Old real-time timestamps are kept, but are never read as play time.

## [Unreleased]: 0.6.0-dev (visual and onboarding overhaul)

**Verified: L2** (mocked). Not tested in game yet; see part N of [`docs/TESTING.md`](docs/TESTING.md). Design: [`docs/design/UI_DESIGN_V06.md`](docs/design/UI_DESIGN_V06.md).

### Added
- **Design system:**
  - Shared tokens, a theme registry and frame chrome (`UI/Style.lua`).
  - A component kit (`UI/Widgets.lua`): template-free buttons in default, primary, ghost, danger and choice variants, with hover, pressed, disabled and selected states; icon buttons; segmented controls; cards; dividers; styled inputs; and a Dawnward confirmation dialog.
- **Themes:** Classic Dawnward (new default for new characters), Lightbound and Shadowbound. Neutral, Silver Hand and Arcane are kept, and a saved theme is never changed. Themes are cosmetic and never depend on class, race or faction.
- **First-time setup wizard:** Welcome, Character, Story, Privacy, Appearance, Finish.
  - It opens by itself only for a genuinely new character, once per session.
  - Drafts are kept on close and resume on the same page.
  - Finish applies only what you changed and never clears an existing value.
  - Nothing is written to Total RP 3.
  - `/dawnward setup`, or Settings → Run setup, opens it on demand.
- **Keyboard navigation in every form** (Stances, People, Memories, Goals, Arcs, Character fields, Family, History, the journal editor and the setup wizard): Tab and Shift+Tab move between inputs, skipping hidden or disabled ones; opening a form focuses its first input; the focused input is clearly marked; Enter moves on and saves only from the last one-line input; multi-line text keeps Enter for new lines; Escape cancels, asking first if something was typed.
- **Inline validation:** when a save is refused, the reason appears directly under the field concerned, which is highlighted and focused. Everything typed is kept, the form stays open, and the message clears as soon as the field is corrected. The validation rules themselves are unchanged.
- **Entry rows:** every record and its buttons form one panel, with a gap between panels and a highlight on hover, so each action clearly belongs to its record. Places show their status (Homeland, Meaningful) apart from the buttons that change it, with clearer labels: "Write memory", "Set as homeland", "Mark meaningful" / "Unmark meaningful".
- **Story diagnostics** (development builds only):
  - `/dawnward dev story status` explains the current place's ties, return eligibility, Director weight, location cooldown, and why the last arrival asked or not.
  - `/dawnward dev story simulate [place]` runs a return on a discarded copy of the character and changes nothing.
- **Developer commands** (development builds only): `/dawnward dev setup` (a marked preview), `dev setup status`, and `dev setup reset confirm`, which resets only the setup state.

### Fixed
- **Returns to unmapped places tied to the story:** an area without a verified area ID (for example Crystal Lake in Elwynn Forest) that the player tied to their story by an established memory or by naming it in the Homeland field never produced a return; the check fell through to the zone. It now counts like a marked place. Found while investigating v0.5 manual test M16.
- **Investigated, expected behaviour (v0.5 M16):** returning to a marked Homeland in the same session records nothing, because a return needs 2 days away. The checklist step was ambiguous. It is now clarified, and the exact rules are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#return-visits-exact-eligibility).

### Changed
- **Every screen restyled:**
  - The window has an emblem header, ?/settings/close buttons, underlined navigation and a status footer. It is 640 × 540 and scales down to fit small screens.
  - Journal entries are cards, Story answers are choice cards, and the Chronicle has a segmented sub-navigation.
  - Settings is split into General, Story, Data and Total RP 3 pages, with a theme gallery.
  - The reaction card, copy window, forms and guide use the same frame and controls.
- **Guide:** now contextual help only. It no longer opens by itself, and closing it saves nothing.

### Data
- **Schema stays 5.** New saved values are additive and cleaned on load:
  - `char.wizard`, reserved since schema 3;
  - `ui.wizardDrafts`, keyed by character, capped at 50, so unfinished setups never create a character record.

## [Unreleased]: 0.4.0-dev (the living chronicle)

**Verified: L2** (mocked). Not tested in game yet; see the v0.4 checklist in [`docs/TESTING.md`](docs/TESTING.md#v04-in-game-checklist-l3-the-living-chronicle).

### Fixed
- **Journal development status:** a story draft no longer writes "(waiting for your approval)" into its text. The journal shows the current status of the proposed change (waiting, approved, rejected or reversed) next to it. Older drafts that still say "waiting" are shown with the real status. Display only: stored text, approved or not, is never rewritten. (Found in game on 2026-10-26.)

### Added
- **Character origins and places (#20, #11, #14), schema v5:**
  - A new character in its race's usual starting area (Classic Era only, level 5 or lower, the first location ever recorded) gets a beginning-of-journey moment instead of an arrival. An established character first seen by Dawnward gets neutral "first recorded" wording. Nothing is inferred about birthplace, home, upbringing or loyalty.
  - Named areas inside zones are tracked separately from zones (`GetSubZoneText`, `C_Map.GetBestMapForUnit`, `C_Map.GetAreaInfo`). A small mapping checked against the 1.15.9.70576 client data classifies starting areas, settlements, inns, farmland, roads, ruins and capitals. Unknown places are logged, never classified from their name, and never asked about.
  - New "place" events and moments: first visits to settlements, farmland and other mapped places, a first settlement in a new region, and returns after a real absence to settlements, capitals, starting areas, places you marked as meaningful (`/dawnward place mark <name>`) or places tied to an established memory.
  - Pacing: zone and place moments share one cooldown and fold together (a zone followed by its subzone asks once, about the more meaningful place). A quest turned in right after arriving takes precedence over the arrival. Returns are asked at most weekly per place, and never for farmland or roads by themselves. New setting: **Places** on, fewer or off (`/dawnward story set places …`), plus `story track zone|place`.
  - Pronouns: new questions follow the profile's Pronouns field when it clearly starts with she, he or they, and are neutral otherwise.
  - `/dawnward places` lists where the character has been.
  - Schema 5 is an additive 4 → 5 migration (an empty places log). Past events and approved journal entries are not changed. An older v0.4 build opens schema 5 data read-only.
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
