# Total RP 3 integration

**Status (v0.9-dev):** read-only status (tested in game, v0.1/v0.2), plus **experimental automatic sync** of the character's whole public profile: the About page (the whole biography and every Public section, in templates 1, 2 and 3), Dawnward-owned personality traits, thirteen profile fields, four additional-information entries and the At First Glance entries the player writes for it, each under a per-item ownership policy. Connecting is **one authorisation** (the setup wizard's Total RP 3 stage, or Overview > Connect everything); after that, changes in Dawnward reach Total RP 3 automatically.

The sync is **built and tested against mocks only (L2)**:
- It is **off by default**. A character connects once (setup's Total RP 3 stage, or Settings > Total RP 3 > Overview > **Connect everything…**), or authorises single mappings on the Mappings tab, or with `/dawnward trp3 enable about|traits|glance confirm` and `/dawnward trp3 field <name> dawnward confirm`.
- It is **allowlisted for TRP3 3.4.1 only**.
- **Nothing in this document about sync has been validated in game yet.** The checklist is in [TESTING.md](TESTING.md#v03-in-game-checklist-l3).

Findings come from reading the TRP3 **3.4.1** Lua source (tag `3.4.1`, commit `4c25cb0`), compared with upstream `main`. TRP3 is Apache-2.0 and is not included in this repository.

Evidence labels:
- **S**: confirmed from source.
- **L2**: confirmed by Dawnward's mocked tests.
- **I**: inferred from source; not proven.
- **L3**: confirmed in game.

## Rules

1. TRP3 is an independent addon. Dawnward never modifies its files, never edits SavedVariables on disk, and never patches or replaces TRP3 functions.
2. **Public API first.** Anything outside `AddOn_TotalRP3` is internal and may change without warning. Each internal dependency is listed below with its risk.
3. **Experimental internal writes are off by default.** They need all of these:
   - the TRP3 version is allowlisted;
   - the character has opted in, bound to one exact profile ID;
   - every runtime capability and shape check passes.
4. **No write without a backup, a read-back check, and automatic restore on mismatch.**
5. Only the **public projection** reaches TRP3 (see [PRIVACY.md](PRIVACY.md)). Private and secret facts, simulation data and unapproved suggestions can never reach it.
6. Dawnward changes **only content it owns**, proven by an exact match against its ledger. It never changes the player's text, template choice, layout, preset traits or the player's own traits. When in doubt, it stops and asks.
7. A failure in the integration cannot reach the core: every TRP3 access is wrapped in `pcall` and type-checked.

## Public API capabilities (TRP3 3.4.1 and `main`), issue #8

| Data | Public read | Public write | Notes |
|---|---|---|---|
| Profile identity | `GetProfileID`, `GetProfileName`, `IsProfileDefault`, `GetCharacterID` **S** | `SetProfileID` (select only) **S** | Default profile IDs end in `*` and change every login **S** |
| Names, title, full title, race, class, colour, icon | getters **S** | `SetFirstName`, `SetLastName`, `SetTitle`, `SetFullTitle`, `SetCustomRace`, `SetCustomClass`, `SetCustomClassColor`, `SetCustomIcon` **S** | Refused silently on the default profile **S** |
| Currently, OOC, RP status, walk-up, RP experience | getters **S** | `SetCurrentlyText`, `SetOutOfCharacterInfo`, `SetRoleplayStatus`, `SetWalkup`, `SetRoleplayExperience` **S** | The setters (`UpdateProfileField`): no-op if unchanged, bump `v`, fire `REGISTER_DATA_UPDATED(player_id, profileID, section)` **S** |
| **About / biography** | none (`GetProfile().about` is the live table) **S** | **none** **S** | Same in `main` **S** |
| **Personality traits** (`characteristics.PS`) | none (`GetCharacteristics().PS`, live table) **S** | **none** **S** | Same in `main` **S** |

**Missing setters that would make biography and trait sync supported:**
- a way to write or register an addon-owned About section;
- a way to write addon-owned personality traits;
- an "editor has unsaved draft" query.

A draft proposal is in [planning/living-character/trp3-upstream-proposal.md](planning/living-character/trp3-upstream-proposal.md). It has **not been submitted**, and Dawnward does not contact the TRP3 maintainers.

**Replaceability:** when an official setter appears:
1. Add its method name to `TRP3Adapter.PUBLIC_SECTION_WRITERS` (`Integrations/TRP3/Adapter.lua`). `DriverFor` then prefers it over the experimental driver.
2. Planning, ownership, the ledger, backups and conflicts don't change.

## What TRP3 3.4.1 does (verified from source)

### Storage and profiles
- Your own profiles live in `TRP3_Profiles[id]`, with data under `.player` **S**.
- `TRP3_Characters[characterID].profileID` links characters to profiles, so **several characters can share one profile table** **S**.
- `CurrentUser:GetProfile()` returns the live `.player` table **S**.
- Every character starts on the **default profile** (its ID ends in `*`; `CurrentUser:IsProfileDefault()` compares with the `default_profile_id` setting) **S**. Dawnward never writes to it.
- `TRP3_API.profile` (global through `_G.TRP3_API`, `Init.lua` 62) exposes the profile manager **S** (`Core/Profiles.lua`):
  - `getProfiles()` (76): the profiles table.
  - `isProfileNameAvailable(name)` (101): asserts a non-empty string; `false, id` when the name is taken.
  - `createProfile(name)` (144): a copy of TRP3's blank template (`PR_DEFAULT_PROFILE`, filled by the Register modules), never of another profile; new random ID; prints "Profile … created."
  - `selectProfile(id)` (193): asserts the ID exists, sets the current profile and `TRP3_Characters[player].profileID`, prints "Profile … is loaded.", fires `REGISTER_PROFILES_LOADED` and `REGISTER_DATA_UPDATED(player_id, id)`. The public `CurrentUser:SetProfileID` (`Core/Player.lua` 391) calls it.
  - TRP3's own "Create profile" button on the default profile's page does `selectProfile(createProfile(name))` after `isProfileNameAvailable` (`Modules/Register/Characters/RegisterMain.lua` 735-742). Deleting and renaming are local functions, not exposed.

### About (`player.about`)
- The layout is `{ v, TE = 1|2|3, BK, MU, T1 = {TX}, T2 = { {TX, IC, BK}, … }, T3 = { PH, PS, HI = {TX, BK, IC} } }` **S**.
- Only the active template is sent to other players **S**.

### Characteristics (`player.characteristics`)
- `PS` is a list. A preset trait is `{ID, V2}`; a custom trait is `{LT, RT, LI, RI, LC, RC, V2}` **S**. The editor's "new" custom trait is `{ LT, LI = "INV_Misc_QuestionMark", RT, RI = "INV_Misc_QuestionMark", V2 = 10 }` (`RegisterCharacteristics.lua` `psychoAdd`, line 685) **S**.
- `V2` runs from 0 to 20 (`Globals.lua` 68–69: `PSYCHO_DEFAULT_VALUE_V2 = 10`, `PSYCHO_MAX_VALUE_V2 = 20`). It is the number of points toward the **left** trait; the right trait gets `20 - V2` (`refreshPsycho`, line 186–191: `leftCount = value`, `rightCount = PSYCHO_MAX_VALUE_V2 - value`); MSP sends `V2 / 20` (`MSP/Fields.lua` 146) **S**.
- There is no limit on the number of traits **S**.
- `MI` (additional information) is a list of `{ ID = type, NA = name, VA = value, IC = icon }` (`Core/ProfileUtil.lua` 9–21 `MiscInfoType`: 1 custom, 2 house, 3 nickname, 4 motto, 5 facial features, 6 piercings, 7 pronouns, 8 guild name, 9 guild rank, 10 tattoos, 11 voice reference) **S**. The profile page shows every entry in order with `IC` (else the type's icon) and `NA` (else the type's name) (`CreateMiscFieldInfo` 103, `setConsultDisplay` 412) **S**. An entry without `ID` is typed by `NA` matching a preset's English **or localised** name (`GetMiscInfoTypeByName` 143) **S**. The editor adds a preset as `{ ID, NA = localised name, VA, IC = preset icon }` and "Create new" as `{ ID = 1, NA = "Name", VA, IC = TRP3_InterfaceIcons.Default }` (`miscAdd` 602, `miscAddDropDownSelection` 650) **S**.
- A new profile starts with `RA = Globals.player_race_loc`, `CL = Globals.player_class_loc`, `FN = Globals.player` (`RegisterCharacteristics.lua` 44–51; `Globals.lua` 48–51: the first returns of `UnitRace`, `UnitClass`, `UnitNameUnmodified`) **S**.

### Miscellaneous (`player.misc`)
- Default `{ v = 1, PE = {}, ST = {} }` (`RegisterMisc.lua` 18) **S**. It is its own section: its own `v`, its own exchange type `"misc"` (`RegisterMain.lua` 49) **S**.
- **At First Glance** `PE`: five slots keyed `"1"`…`"5"` (`displayPeek` 251–254, `getMiscExchangeData` 452–457), each `{ IC, AC, TI, TX }` **S**. The glance editor has **no draft**: Apply calls `applyPeekSlot` (332), which writes the live slot, bumps `v` (`incrementNumber(v, 2)`) and fires `REGISTER_DATA_UPDATED(player_id, profileID, "misc")` **S**. The editor saves `TI`/`TX` as `stEtN(text)` (`RegisterGlance.lua` `openGlanceEditor` 428) **S**. Its frame `TRP3_AtFirstGlanceEditor` is declared `hidden="true"` (`RegisterUIMisc.xml` 239) **S**. Dragging swaps whole slots (`swapDataFromSlots`, `RegisterGlance.lua` 95) **S**.
- Only **active** slots reach others: `getMiscExchangeData` drops `AC == false` slots (452), and MSP sends only `AC` slots as `PE` (`RegisterMSP.lua` `updateMiscData` 167–189) **S**.
- `sanitizeMisc` (293) strips codes from `TI` (one line) and `TX` (multi-line) on load **S**.
- `ST` holds the RP-style answers (injury, death, romance, …); written only by the player's dropdowns (`onEditStyle` 104) **S**.

### Character status (`player.character`)
- Default `{ v = 1, RP, WU }` (`Dashboard.lua` 30); `CU` (Currently) and `CO` (OOC information) are written through the public setters `SetCurrentlyText` / `SetOutOfCharacterInfo` (`Core/Player.lua` 442–447, `UpdateProfileField` 419), from the Miscellaneous tab's boxes (`RegisterMisc.lua` 396, 408) **S**. RP experience is stored in TRP3's configuration, not the profile (`Player.lua` 500) **S**.

### Notes (`profile.notes`, `TRP3_Notes`)
- The Notes tab writes `profile.notes[profileID]` (the current profile's notes **about** the viewed profile) and the account-wide `TRP3_Notes[profileID]` (`RegisterNotes.lua` 62, 75) **S**. Neither is part of `player`, and the exchange only answers `characteristics`, `about`, `misc` and `character` (`RegisterExchange.lua` 436–445) **S**. **Notes are local and private: never sent to anyone.** Dawnward never reads or writes them.

### Editors
- The About and characteristics editors work on a **draft copied when the editor opens** **S**.
- **Save** wipes the live section, copies the draft back, sets `v = draft.v + 1`, and fires `REGISTER_DATA_UPDATED(player_id, nil, section)`. The profile ID is nil on the player's own page **S**.
- **So anything written to the live section while an editor holds a draft is lost on Save.**

### Version rule
`Utils.math.incrementNumber(v, 2)`: +1, with 100 wrapping to 1 **S**.

### Events
- They come through the `TRP3_Addon` registry, via `TRP3_API.RegisterCallback(TRP3_Addon, event, fn)` **S**.
- Callback argument positions differ between TRP3's own listeners and its comments. **Dawnward treats these events as hints only.** Since v0.8 it looks at the arguments only to drop hints about other profiles: TRP3 fires `REGISTER_DATA_UPDATED` for every other player's profile it receives (`RegisterMain.lua` `saveInformation`), MSP senders, register list edits (no arguments) and companions. A hint counts only when one of its arguments is the player's own unit ID (`TRP3_API.globals.player_id`) or the active profile ID, matched by value, not position (`Adapter.IsOwnHint`).

### Exchange
- The exchange is **pull-only**:
  - other clients send a version query with your `characteristics.v`, `about.v`, `misc.v` and `character.v`, and re-fetch only a section whose number differs **S**;
  - `REGISTER_DATA_UPDATED` doesn't broadcast; it only refreshes local UI and the MSP fields **S**.
- Another player sees an update the next time they mouse over or target you. TRP3 queries at most once per 10 s per unit **S**.
- There is no hard size limit, only a "profile too heavy" warning **S**.

### MSP bridge (MyRolePlay/XRP)
- It rebuilds only when `REGISTER_DATA_UPDATED` fires with your own unit ID **S**.
- Field mapping **S**:
  - `DE` is the About text: T1, or T2 frames joined, or T3 physical plus personality.
  - `HI` is the T3 history.
  - Traits are sent as `[trait value=V2/20 …]`.
- So after an outside write, firing the event exactly as TRP3's setters do is what keeps MSP users up to date.

## The sync design (as built)

### Modules
All of them are under `Integrations/TRP3/`:

| Module | Role |
|---|---|
| `Adapter.lua` | **The only module that touches TRP3 for sync.** `Probe` re-reads everything on every call: version, profile ID, default, linked characters, update-event API and editor state. `ReadSection` returns validated deep copies. `WriteSection` is the experimental driver. `Listen` registers the hints. |
| `Shape.lua` | Fail-closed layout checks for About, characteristics and (v0.9) misc (unknown extra fields are preserved), and the version rule |
| `AboutBlock.lua` | Composes the Dawnward section from public facts, and plans insert, replace, remove, no-op or conflict (pure) |
| `TraitPlan.lua` | Maps public Dawnward personality axes to owned custom traits, and plans changes (pure) |
| `FieldPlan.lua` | Profile field mappings (13 fields, below), the value cleaner, the game's own defaults and the per-field plan (pure) |
| `MiscPlan.lua` | v0.9: Dawnward-owned entries in TRP3's additional-information list (pronouns, faith, occupation, allegiance) (pure) |
| `GlancePlan.lua` | v0.9: Dawnward-owned At First Glance slots in TRP3's misc section, from the entries the player wrote (pure) |
| `Core/Glance.lua` | v0.9: the player's own At First Glance entries (`char.glance`, five at most), `/dawnward trp3 glance` |
| `AboutDoc.lua` | v0.9: the full-profile About document (the whole biography and Public sections), rendered for templates 1, 2 and 3, and its plan (pure) |
| `Ledger.lua` | `DawnwardChroniclesTRP3DB`: ownership policies per character and profile, ownership records, conflicts, backups and log |
| `Sync.lua` | The transaction, plus rollback, release and resolve |
| `Commands.lua` | `/dawnward trp3 …` |
| `Platform/TRP3Bridge.lua` | Saved variable, debounced automatic runs, event hints |

### Ownership without visible markers
| Template | What Dawnward owns | How it's identified |
|---|---|---|
| T1 | A block appended to `T1.TX`, including the blank-line separator Dawnward added | Exact match of the ledger's last-written string, ending at a line break or the end of the text |
| T2 | One whole frame Dawnward added (book icon, background 1) | Exact `TX` match. A frame the player restyled is never removed (conflict). |
| T3 | A block appended to the history text `T3.HI.TX` | As for T1 |
| Traits | One custom trait per public axis, with Dawnward's own pole labels (for example Cautious/Bold) | Exact `LT`/`RT` pair, and `V2` equal to the value Dawnward last wrote |
| Profile fields | The value of a mapped characteristics field that Dawnward wrote | The field holds exactly the value the ledger says Dawnward last wrote. Text that merely matches is never claimed. |
| Additional information | One `MI` entry per managed mapping | Same type (preset `ID`, or the localised/English name TRP3 types it by; custom by name) and `VA` equal to the ledger's value; `IC` is never compared |
| At First Glance | Each `PE` slot Dawnward filled | The slot holds exactly the `TI`, `TX`, `IC` and `AC` Dawnward last wrote there (per slot in the ledger). A slot the player filled is never written; a new entry only goes into a free slot (absent or an empty table), and never when a slot already shows the same title and text |

These cases are a **conflict**:
- The owned content is missing, appears more than once, or was edited.
- The template changed.
- The player already has a trait with Dawnward's labels.

On a conflict, Dawnward writes nothing and pauses that feature until the player runs `/dawnward trp3 resolve about|traits|glance keep|reclaim`:
- **keep**: the player's version stays and Dawnward stops managing it.
- **reclaim**: for the biography, the edited text becomes the player's and Dawnward appends a fresh section. For traits, Dawnward takes back its labelled traits at their current values. For At First Glance, the edited slots become the player's and Dawnward writes its entries again into free slots.

Removing the owned block (release) restores the player's text **byte for byte** (L2).

### Guards (re-checked on every run)
1. The ledger loaded (a ledger from a newer build stays untouched and blocks sync).
2. Not in simulation mode, and saved data is writable.
3. TRP3 is loaded, the version is on the allowlist (`VersionProfiles`: `experimentalWrite`), and the public API, profile data and update event exist. **A matching version number alone is never enough.**
4. The active profile has an ID, is **not the default profile**, and is **exactly the profile the character opted in with**. Switching profile pauses sync.
5. No TRP3 editor holds an unsaved draft of the section. That is the case only while TRP3's `player_main` page context is in edit mode, the section's tab is shown and its edit frame is shown (`Adapter.EditorState`) **S**. Closing TRP3's window mid-edit keeps all three, so that draft still blocks.
   - The edit frame's shown flag alone is **not** a reliable signal: both edit frames are declared without `hidden="true"` (`RegisterUIAbout.xml`, `RegisterUICharacteristics.xml`), so they read as shown after every login and `/reload` until TRP3 draws that tab. The characteristics tab is drawn whenever a profile page opens; the About tab only when the player views it **S**. Before this was fixed in PR #9, it left the biography "waiting" forever after a `/reload` (in-game report, TRP3 3.4.1).
   - A `/reload` discards a draft (it is a Lua local), and leaving the profile page replaces the context, after which TRP3 discards the draft before any new edit **S**.
   - `/dawnward trp3 diagnose` prints every input of this check, read-only.
6. Not in combat.
7. No unresolved conflict, and the section passes the shape check.

### Transaction
1. Plan against a **copy**. A **no-op writes nothing**: no backup, no version bump, no event.
2. **Back up** the whole section (serialised) into the ledger.
   - At most 20 backups are kept in total. The oldest **unpinned** backup goes first. Pinned (at most 4): the state before Dawnward's first write in a section (no Dawnward content; kept until a newer such state exists), and the player's value saved when they choose "Use Dawnward's" on a field. So many automatic writes never push out the way back to the player's own profile.
   - A section too large to back up (over 64 KB serialised) is **never written**.
3. Write the owned change: replace the live section's contents in place, as TRP3's editors do.
4. Bump `v` by **two** steps.
   - TRP3's editors save `draft.v + 1`. Skipping a number means an editor save from an older draft can never reuse the version other clients already fetched from Dawnward **I**.
   - Without this, those clients would keep showing stale data.
5. Fire `REGISTER_DATA_UPDATED(player_id, profileID, section)` exactly as TRP3's own setters do. This updates TRP3's UI and the MSP fields.
6. **Read back** and compare with the expected section.
7. On any mismatch or error: restore the backup, switch the feature off, log it, and tell the player.

### Recovery
| Command | What it does |
|---|---|
| `/dawnward trp3 rollback [#]` | **Preview only.** Names the backup and lists every piece of Dawnward-owned content in it that is **no longer Public** in Dawnward now (biography lines, personality values, field values), and whether your own text can be separated from Dawnward's part. Writes nothing. |
| `/dawnward trp3 rollback [#] confirm` | **Safe default (v0.8).** Restores **your own** content from the newest (or a chosen) backup for the **active** profile; Dawnward's part of that backup is dropped and planned again from what is Public **now**, for the features Dawnward manages now. Nothing that is no longer Public comes back. Refused (with the reason) if Dawnward's part cannot be separated exactly. |
| `/dawnward trp3 rollback [#] exact confirm` | The v0.7 behaviour, now explicit: restores the section **exactly** as it was, including Dawnward content that may no longer be Public (the preview names it), restores the ownership records saved with the backup, and switches off every feature of that section (fields go back to "Managed by Total RP 3"). |
| `/dawnward trp3 release about\|traits\|fields confirm` | Removes only Dawnward's content and stops managing it |
| `/dawnward trp3 resolve about\|traits\|<field> keep\|reclaim` | Settles a conflict (see Ownership policies) |
| `/dawnward trp3 fields` | Every mapping, who manages it, and the differences view (read only) |
| `/dawnward trp3 import <field> [private\|public\|secret] confirm` | Copies Total RP 3's value of one field into Dawnward (Private by default) |
| `/dawnward trp3 backups`, `/dawnward trp3 log` | Inspect backups and diagnostics |
| `/dawnward trp3 paste` | The manual path: the same section, suggested traits and every Public profile field (including fields Dawnward never writes) as text to paste into TRP3 yourself (always available, any TRP3 version) |

Both rollback modes apply the same guards as a write (allowlisted version, not simulation, not combat, editor closed), refuse another profile's backup, back up the current state first (so a rollback can itself be undone), and **read the result back**: if Total RP 3 does not hold exactly what was restored, the pre-rollback state is put back. A rollback is never started automatically. The Total RP 3 page offers the same two choices: **Roll back…** (safe) and **Exact restore…**, whose confirmation lists what would become visible again and whose button says "Restore, including these" when the list is not empty.

### Automatic runs
A run is requested (only when this character authorised at least one mapping):
- at login;
- after **any** `/dawnward` command (`Platform/Bootstrap.lua`);
- after **any** successful change made in the window, because every window write goes through `Actions.withCharacter` (`Core/Actions.lua`): profile fields and their visibility, facts, personality values and their visibility, journal visibility, approving a story entry, marking a defining moment, applying or reversing a personality change, decisions, the Total RP 3 presentation style (`trp3Style`), and finishing setup;
- after a policy change on the Total RP 3 page (Authorize, Keep yours / Use Dawnward's);
- when Total RP 3 reports a profile switch or a profile edit (`REGISTER_PROFILES_LOADED`, `REGISTER_DATA_UPDATED`, as hints) — including TRP3's own editor Save;
- when combat ends (`PLAYER_REGEN_ENABLED`) and a run was waiting for it.

Bounds:
- Requests are merged into one run 5 s later (`C_Timer.After`), so a burst of changes writes at most once per feature.
- The `REGISTER_DATA_UPDATED` that Dawnward's own write fires is ignored, so a write never schedules another run.
- A run that has to wait (editor open, combat) retries every 30 s, at most 20 times **per request**; a new request starts a fresh, equally bounded series. A superseded timer does nothing (generation counter), so a combat-end run and an old retry never both run.
- A persistent state (blocked, conflict, still waiting after the last retry) is reported once.
- A no-op performs no write, no backup, no version bump and no event.

## Audit of the sync (v0.8)

What the existing bridge and sync did, checked against the code and the 3.4.1 source before the field work, and what changed:

| Area | Finding | Action |
|---|---|---|
| Debounce | One pending flag merged requests into a run 5 s later. Correct. | Kept. |
| Retries | The retry counter was only reset by a run that did not wait. After 20 retries, every later wait got a single attempt and no further retries. Nothing told the player. | Each request now starts a fresh bounded series; "still waiting" is reported once. |
| Own-write echo | Dawnward's write fires `REGISTER_DATA_UPDATED` (deliberately, for TRP3's UI and MSP); the hint listener then requested another run 5 s later (a no-op, but a wasted run). | Hints are ignored while Dawnward's own run is writing. The page's "Approve and write" still causes one harmless no-op run. |
| Combat | Combat end was not a trigger: a deferred run waited for the next 30 s retry, or forever once retries were exhausted. | `PLAYER_REGEN_ENABLED` requests a run when one is waiting. Stale timers are ignored. |
| Guards | Every run re-probes TRP3 (version allowlist, API shape, profile ID, default profile, editor draft) and re-checks simulation, read-only data and combat. Correct. | Kept; fields use the same guards (the characteristics editor draft holds every field Dawnward writes). |
| Ownership | Exact-match ownership for the About block and traits. Correct. | Extended to fields (exact recorded value). |
| Backups | A backup recorded only the ownership of the feature that wrote it. With traits and fields sharing the characteristics section, an exact rollback would have lost the other feature's ownership and caused a false conflict. | Backups also record `owners` for every feature of the section. |
| Rollback | Restored the backup without a read-back, and could re-publish content that had since been made Private or Secret (only a warning). | Read-back with automatic undo; visibility-aware preview; safe "own text only" default; exact restore explicit. |
| Privacy filter | Only `Projection.GetPublic` reaches a plan; story data never does; simulation blocks every write. Correct. | Fields read `public.fields` only, and only entries whose visibility is `public`. |
| Version allowlist | 3.4.1 only (`VersionProfiles`). Correct. | Kept; the read-only differences view also needs an audited version. |
| Shared profiles | One character per profile and feature. Correct. | Extended per mapping; the page warns before authorising. |
| Opt-in | Two booleans per character, bound to one profile. | Replaced by per-mapping policies (booleans kept in step for older builds). |

## The empty About page found in game (0.9) and its fix (v0.10)

**Observed (owner, Classic Era, TRP3 3.4.1):** Characteristics showed the synced name, race, class, birthplace and pronouns, but the About tab said "No description" although the whole backstory had been imported during first-time setup.

**Verified cause:**
1. The setup wizard's **Import a story** stores the text at once (`ImportWizard.Save` → `StoryImport.Import` → `Sources.Capture`), which set the biography's visibility from `Privacy.DefaultFor(char, "biography")`.
2. The character was switched to the profile model only at **Finish** (`Actions.CompleteSetup` → `Publication.Adopt`), after the import, so the biography was stored **Private**.
3. `Projection.GetPublic` left a non-Public biography out, so `AboutDoc.Build` composed nothing for the About page and no About write happened. Total RP 3 3.4.1 shows "No description" exactly when the active template's text is empty (`RegisterAbout.lua` `shouldShowTemplate1/2/3`, `REG_PLAYER_ABOUT_EMPTY`).
4. The fields were set at Finish, under the profile model, so they were Public and synced.
5. The mocked tests adopted the model before importing, so they never took the real order of steps.

The write driver itself was checked against the TRP3 3.4.1 source (`CurrentUser:GetProfile` returns `getPlayerCurrentProfile().player`; the About tab draws `T1.TX` / `T2` / `T3`): it matches, so missing data was the only cause.

**Fix (v0.10):** the character profile publishes as a whole (`Core/Publication.lua` version 2); per-item visibility no longer decides what reaches Total RP 3. New characters start this way however they are created. A 0.9 character with something kept back (such as that biography) waits for one confirmation (`/dawnward publish confirm` or **Publish whole profile…**), which changes no record and can be undone. `tests/spec/trp3_about_ingame_repro_spec.lua` drives the real path and the owner's 0.9 saved-data shape.

**Diagnosing in game:** `/dawnward trp3 diagnose` (read-only) prints, without the story text: the character, the publication state, the biography's version, bytes and paragraphs, whether it is in the profile Dawnward publishes, the About content, layout and style, the number of composed sections, whether About sync is authorised and for which profile, Total RP 3's current About template, version and size, the next run's state and reason, the last About write and the last read-back result. **Note:** Total RP 3 draws your own About tab when it opens; if it was already open during a write, close and reopen it.

## Field mappings

Verified against the Total RP 3 source at tag **`3.4.1`** (commit `4c25cb0`): `Core/Player.lua` (public getters and setters, `UpdateProfileField`), `Modules/Register/Characters/RegisterCharacteristics.lua` (`saveInDraft`, `saveCharacteristics`, `sanitizeCharacteristics`), `Modules/Register/Characters/RegisterMain.lua` (`cleanupMyProfiles`, `saveInformation`), `Modules/Register/MSP/RegisterMSP.lua`, `Modules/Dashboard/Dashboard.lua` and `Currently.lua`, `Core/ProfileUtil.lua` (misc info types), `UI/Widgets.xml` (`letters="0"`).

Facts that apply to every characteristics field below **S**:
- They are top-level strings of `player.characteristics`. The characteristics editor writes them as `stEtN(strtrim(text))`, so an empty field is stored as `nil`, never `""`.
- The editor boxes have no length limit (`letters="0"`).
- `Utils.str.sanitize` strips colour, link, texture and line codes from them when **your own** profiles load (`cleanupMyProfiles`) and when another client receives them (`saveInformation`). Dawnward therefore only writes a value **exactly as it is**, and only if sanitising would leave it unchanged: one line, no `|`, no extra spaces, at most 100 bytes (`FieldPlan.Check`). A value that does not qualify is **not writable**: it is never rewritten or shortened, nothing is written, a field Dawnward already wrote is left untouched (never cleared because of it), and the reason is shown (page row, `trp3 preview`, `trp3 fields`).
- The characteristics editor works on a draft (as for About); its Save copies the draft over the whole section. The existing editor guard covers them.
- On the default profile, TRP3 wipes everything except `v`, `RA`, `CL`, `FN`, `IC`; Dawnward never writes the default profile anyway.

### Complete mapping matrix (v0.9 audit)

Verified line by line against Total RP 3 **3.4.1** (tag `3.4.1`, commit `4c25cb0`). File paths are under `totalRP3/`; `RC.lua` is `Modules/Register/Characters/RegisterCharacteristics.lua`, `RM.lua` is `Modules/Register/Characters/RegisterMisc.lua`. Every write uses the editor path (replace the section's contents, bump `v` by two steps, fire `REGISTER_DATA_UPDATED(player_id, profileID, section)`) inside a backed-up, read-back transaction; the public setters are only noted. "Ownership" is how Dawnward proves a value is its own (ledger exact match); "auto" means the guarded debounced run keeps it up to date once the player authorised that mapping. Every row still needs the in-game check (L3) listed in the last column; none has been done.

**Supported and implemented**

| Dawnward source | TRP3 destination | API / data path (evidence) | Ownership | Auto | Verify in game |
|---|---|---|---|---|---|
| `firstName` (Public) | `characteristics.FN` | `saveInDraft` `RC.lua` 484 (`or Globals.player`); setter `SetFirstName` `Player.lua` 454 | per field, exact value | yes | name on tooltip and profile |
| `lastName` | `LN` | `RC.lua` 485; `SetLastName` 458 | per field | yes | as above |
| `honorific` ("Title prefix") | `TI` (shown before the name, `getCompleteName` `RC.lua` 154) | `RC.lua` 483; `SetTitle` 466 | per field | yes | "Lady Kyssarra" |
| `title` | `FT` (full title under the name) | `RC.lua` 486; `SetFullTitle` 470 | per field | yes | title line |
| `race` | `RA` | `RC.lua` 487 (not trimmed); `SetCustomRace` 492 | per field | yes | Characteristics: Race |
| `class` | `CL` (colour `CH` untouched) | `RC.lua` 488; `SetCustomClass` 474 | per field | yes | Class |
| `age` | `AG` | `RC.lua` 489 | per field | yes | Age |
| `homeland` | `BP` (Birthplace) | `RC.lua` 494 | per field | yes | Birthplace |
| `residence` | `RE` (map pin `RC` untouched) | `RC.lua` 493 | per field | yes | Residence |
| `eyes` | `EC` (colour `EH` untouched) | `RC.lua` 490 | per field | yes | Eye colour |
| `height` | `HE` | `RC.lua` 491 | per field | yes | Height |
| `weight` ("Build") | `WE` (Body shape) | `RC.lua` 492 | per field | yes | Body shape |
| `relationship` | `RS` number: 1 single … 5 widowed; 0 = do not show | `RC.lua` 495 (`tonumber`), `Core/Enums.lua` 15, `RELATIONSHIP_STATUS_DROPDOWN` `RC.lua` 1298 | per field | yes | Relationship status |
| game race, class, name (no Public value of the player's) | `RA`, `CL`, `FN` | TRP3's default profile `RC.lua` 44–51 = `UnitRace`/`UnitClass`/`UnitNameUnmodified` (`Globals.lua` 48–51) | **never owned**; counts as replaceable; restored when Dawnward takes its own value out | yes | Race "Human", Class "Paladin" after making a Dawnward race Private |
| `pronouns` | `MI` entry `{ ID = 7, NA = localised "Pronouns", VA, IC = preset icon }`; MSP `PN` | `ProfileUtil.lua` 9–21, 143, 157; `miscAdd` `RC.lua` 602, 650; `RegisterMSP.lua` 145 | type + exact `VA` (an ID-less entry typed by its English or localised name is recognised: never duplicated) | yes | pronouns row with its icon; MSP `PN` |
| `faith`, `occupation`, `allegiance` | custom `MI` entries `{ ID = 1, NA = "Faith" …, VA, IC = TRP3_InterfaceIcons.Default }` | `RC.lua` 644 ("Create new"), `CreateMiscFieldInfo` `ProfileUtil.lua` 103 | name + exact `VA`; `IC` never compared | yes | three rows, question-mark icon, restylable |
| Personality axes (6), named with the player's own axis words when set (v0.10) | custom `PS` traits `{ LT, LI, RT, RI, V2 }`, `V2 = 20 − value`; a renamed axis renames the same owned trait in place | `refreshPsycho` `RC.lua` 186–191; `psychoAdd` 685 (icons `INV_Misc_QuestionMark`); `Globals.lua` 68–69; MSP `Fields.lua` 146 | `LT`/`RT` pair + `V2` | yes | bar leans to the right pole for a high Dawnward value |
| About page | `about` T1 / T2 / T3 | see "The About page (v0.9)" | owned block / frames / slots | yes | see that section |
| At First Glance entries the player wrote (`/dawnward trp3 glance`) | `misc.PE["1".."5"] = { TI, TX, IC, AC }` | `applyPeekSlot` `RM.lua` 332; default `RM.lua` 18; five slots `RM.lua` 254, 457; inactive dropped from exchange `getMiscExchangeData` 452 and MSP `RegisterMSP.lua` 167–189 | per slot, exact `TI`/`TX`/`IC`/`AC`; only free slots; no duplicate titles+texts | yes (feature `glance`, off by default) | slot on the Miscellaneous tab; glance icon on others' target frame; hidden entry not visible to others |

**Supported by TRP3, not implemented** (Dawnward has no source data, or the value is the player's live choice)

| TRP3 field | Path (evidence) | Why not |
|---|---|---|
| Currently (`character.CU`) | `SetCurrentlyText` `Player.lua` 446; `RM.lua` 383, 396 | A live, in-the-moment status the player types; Dawnward has no source. Not auto-generated (the public setter exists, so an explicit opt-in "Currently" text could be added later). |
| OOC information (`character.CO`) | `SetOutOfCharacterInfo` `Player.lua` 442; `RM.lua` 408 | The player's out-of-character note; no source |
| RP status (`character.RP`), walk-up (`WU`) | `SetRoleplayStatus` 438, `SetWalkup` 450 | Preferences the player toggles; never changed |
| RP style (`misc.ST`) | `onEditStyle` `RM.lua` 104 | Consent preferences (injury, death, romance…): never changed; the whole-section misc write keeps them exactly |
| Eye colour colour `EH`, class colour `CH` | `RC.lua` 569–580 | No Dawnward source |
| Profile icon `IC`, background `bkg`, residence pin `RC` | `RC.lua` 49, 304, 372 | TRP3 choices with no Dawnward source |
| Other additional-information presets (house, nickname, motto, facial features, piercings, guild name/rank, tattoos, voice reference) | `ProfileUtil.lua` 9–21 | No matching Dawnward field |
| Personality preset traits (`{ ID, V2 }`) | `RC.lua` 1212 | Dawnward uses its own labelled custom traits so ownership is provable; presets are never touched |

**Experimental**: everything in the first table is written through the version-allowlisted experimental driver (`Adapter.WriteSection`), because TRP3 3.4.1 has no public writer for About, traits, `MI`, `misc.PE` or most fields.

**Unsupported**

| Item | Why |
|---|---|
| Relationships with other players (`story.people`) → TRP3 relations | TRP3 relations describe *other* characters' profiles, not the player's own |
| Name (one field) split into first/last | It would be a guess; first and last name are their own Dawnward fields |
| Memories, arcs, goals, places, people, journal notes | Story records, not profile content; never published (PRIVACY.md) |

**Not applicable**

| Item | Why |
|---|---|
| Notes tab (`profile.notes`, `TRP3_Notes`) | Local, per-viewer notes about *other* profiles (`RegisterNotes.lua` 62, 75); never exchanged (`RegisterExchange.lua` 436–445). Dawnward never reads or writes them |
| RP experience | Account configuration, not profile data (`Player.lua` 500) |
| Companion profiles | Separate pet/mount profiles; out of scope |

Why the editor path rather than the public setters for Title, Race and Class: Age and Birthplace have no setter, and the five fields are written as **one** backed-up, read-back-verified transaction on the characteristics section, exactly as TRP3's own `saveCharacteristics` does (replace contents, bump `v`, fire `REGISTER_DATA_UPDATED`). The effect for TRP3, MSP and other clients is the same as the setters' `UpdateProfileField`. The setter names are recorded in `FieldPlan.MAPPINGS` (`setter`) for a later switch.

Inferred values are never written: every supported source is a field the player typed (or a homeland the player chose), only when its Dawnward visibility is **Public**, or an At First Glance entry the player wrote for Total RP 3. The one game-derived exception is v0.9's **game fallback** for race, class and first name: when Dawnward takes its own value of one of those back out, the field returns to the value the game itself shows (`UnitRace`/`UnitClass`/`UnitName`, exactly what TRP3 puts in a new profile), unowned. A field the player emptied or wrote in TRP3 is never filled. `Character.GameValue(key)` / `Character.FieldOrGame(char, key)` give the UI the same value for display.

## Ownership policies

Stored per character **and** linked profile in `DawnwardChroniclesTRP3DB.optIn[character]` (`profileId`, `policy[mapping]`):

| Policy | Meaning | Who sets it |
|---|---|---|
| `dawnward` — Managed by Dawnward | Updated automatically from Public data | Only an explicit authorisation: the page's **Authorize…** confirmation, `trp3 enable about\|traits\|glance confirm`, `trp3 field <name> dawnward confirm` |
| `trp3` — Managed by Total RP 3 | Never written; shown in the differences view, importable on request | The default for every field |
| `off` — Not synchronised | Never written, not compared | The default for the biography and traits (that is "sync off") |

- **Migration:** a v0.7 opt-in (`about = true` / `traits = true`) loads as policy `dawnward` for that feature, with no change in behaviour; the booleans are still written so an older build reads the same choice (an older build drops the policies, and every field then falls back to "Managed by Total RP 3").
- **Writes** happen only while the field holds exactly the value Dawnward last wrote, or is empty and has never been written by Dawnward. If Total RP 3 already holds the player's own value, or the player (or another addon) changed Dawnward's value, that field is **paused** (`profiles[id].fieldConflicts`), nothing is overwritten, and the other fields keep updating. A field whose Dawnward value stops being Public is cleared in TRP3 (it was Dawnward's own value); race, class and first name go back to the game's value instead.
- **Resolve:** **Keep yours** (`resolve <field> keep`) hands the field to Total RP 3; **Use Dawnward's** (`resolve <field> reclaim`) records TRP3's current value as Dawnward's, so the next run replaces it after a backup (the player's value stays in that backup).
- **One character per profile** may manage each mapping; a second character's authorisation is refused, and **Authorize** is all-or-nothing.
- Leaving `dawnward` for a field forgets Dawnward's ownership; TRP3 keeps its current value. **Except** when TRP3 still shows the exact value Dawnward wrote and that value is no longer your Public value (`Sync.FieldRisk`): the command refuses until you choose `trp3 field <name> trp3|off release confirm` (remove it first, recommended) or `… keep confirm`; on the page, the row and the Authorize confirmation say it will be removed first, and Authorize removes it (guarded, backed-up write) before saving the choice.
- Field conflicts are cleared when Dawnward stops managing the field (Keep yours, release, policy change, exact rollback) and when it is authorised again; the page shows conflicts only for fields Dawnward manages.
- **Authorize is all-or-nothing:** every choice is validated first (write capability, a storable non-default profile, the shared-profile rule), then applied on a snapshot of the ledger that is restored if anything fails.

## First-time connection (Total RP 3 page, Mappings tab)

The page opens on **Mappings** while nothing is managed yet:
1. The summary strip shows whether TRP3 is installed and supported, and the active profile.
2. A warning appears when the profile is shared with other characters (`TRP3_Characters`, read only), or explains why writing is impossible (for example the default profile).
3. Every mapping has a selector (Dawnward / TRP3 / Off; Dawnward / Off for the biography and traits) and a line saying what TRP3 holds against Dawnward's **Public** value (a non-Public Dawnward value is never shown, only "not Public"). The fields Dawnward never synchronises are listed below, with the reasons on hover.
4. Choices are only staged. **Authorize…** opens a confirmation listing, per mapping, what the first sync would do (Public only: "writes \"Elf\"", "already shows the same text (stays yours)", "Total RP 3 has your own value: paused until you choose, never overwritten", "nothing Public to write"), plus the shared-profile and experimental warnings. Cancel saves nothing.
5. After **Authorize**, the normal debounced, guarded run does the writing.
6. **Import** (per field, with a confirmation) copies TRP3's value into Dawnward through the normal Actions write path, as **Private**. Nothing is ever imported automatically.

## Connecting from setup, and the connection area (v0.9)

`TRP3Commands.Connection` (read only, one probe) gives the setup's Total RP 3 stage and the Overview tab the same view: the version and whether it is supported, the active profile and its kind, and what Finish / Connect would do.

- **Default profile, or a profile another character already keeps up to date** (Sync.Authorize would refuse): connecting is not offered. The player is guided to a profile of their own:
  - **Create a profile…** (after a confirmation naming it): `Adapter.CreateProfile` calls `createProfile(name)` with the character's name (or "name 2" … when taken), then `selectProfile`. No other profile is changed; the default profile is never touched. Not offered when a free profile already has that name: switching to it is offered instead.
  - **Switch profile…** (after a confirmation naming it): `Adapter.SelectProfile` with one of the player's named profiles (never the default one, never one another character keeps up to date); each click offers the next one.
  - Both are refused while a TRP3 editor holds an unsaved draft, in simulation or on read-only data, and on any version without `tiers.profileTools` (3.4.1 only). Without the functions, the stage shows the steps in Total RP 3 (Profiles, create or select) instead.
  - **Refresh connection** reads Total RP 3 again; `REGISTER_PROFILES_LOADED` also redraws the stage and the page.
  - Creating or switching connects nothing and writes no profile data; the single authorisation is still Finish (or **Connect everything…**).
- **Shared profile** (other characters use it): connectable, with a note that they would show the same; a profile of its own is offered.
- **Unsupported version:** explained; nothing to connect; never written.
- **Switched after connecting:** the guards pause sync. The Overview opens by itself, says "Paused" and which profile is connected, and offers **Switch back…** (sync carries on) and **Reconnect…** (connects the active profile instead).

| Dependency | Why | If TRP3 changes |
|---|---|---|
| `TRP3_API.profile.getProfiles`, `isProfileNameAvailable`, `createProfile`, `selectProfile` | Create or select a named profile, only after the player confirms | Missing → the step-by-step help instead; any error is caught and reported, and the result is read back |

## Multiplayer test procedure (two clients; not yet performed)

Nothing below is verified. Use two accounts (A writes, B observes), both on Classic Era 1.15.9 with Total RP 3 3.4.1; B also once with MyRolePlay or XRP instead of TRP3. A uses a **spare, non-default** TRP3 profile. Record each step as Pass/Fail with the TRP3 version and time.

1. **Baseline.** On A, `/dawnward trp3 diagnose` (all guards pass). On B, target A and open A's TRP3 profile: note About, traits, Full title, Race, Class, Age, Birthplace. `/reload` B afterwards so its cache is fresh but kept.
2. **Public profile propagation.** On A, make Race and Age Public in Dawnward, Mappings → Race and Age → Dawnward → Authorize. Wait 5 s. On A, `/dawnward trp3 log` shows one `fields` write. On B, mouse over / target A (wait at least 10 s between checks): Race and Age show A's Dawnward values; nothing else changed.
3. **Biography rendering.** Authorize Biography with two Public facts and one defining moment in each presentation style (`/dawnward story set trp3Style neutral|silverhand|arcane`). On B, the headings, colours and icon render; no raw `{h3}` or `{col:…}` text; the player's own text above is intact (templates 1, 2 and 3).
4. **Trait direction.** Make Courage 15 (Bold side) Public; authorise Traits. On B, the Cautious/Bold bar leans **Bold** (5 / 15).
5. **Names and titles.** With Title managed: B shows the full title under A's name; first and last name are unchanged (never written).
6. **Updates after changes.** Change A's Public Age; within one minute B sees the new value after re-targeting. Make Age Private: B sees the age field empty. Make a fact Private: the line disappears from B's view of the biography.
7. **Conflict.** On A, edit Race in TRP3's editor and Save. Change Dawnward's Race. A shows the conflict once; B keeps showing A's TRP3 value. Keep yours → never overwritten again.
8. **Shared-profile isolation.** Link a second character C of A's account to the same TRP3 profile. On C, Authorize Race: refused, naming A. Switch A to another TRP3 profile: no write lands on it (`/dawnward trp3 log` unchanged), and B sees the other profile untouched.
9. **MSP interoperability.** With B running MyRolePlay or XRP (no TRP3): B sees A's description (`DE`) including Dawnward's block, and `RA`, `AG`, `NT`, `HB` with Dawnward's values after re-targeting.
10. **Formatting.** A Public Race with a `|` or line break in Dawnward: TRP3 shows it without codes, and it reads the same after A's `/reload` (TRP3's load-time sanitising leaves it unchanged; no conflict appears).
11. **No duplication.** After `/reload` and a second sync on A: exactly one Dawnward block, one trait per axis, `log` shows no write.
12. **No unrelated modifications.** Compare A's TRP3 profile before and after (A's own About text, preset traits, icon, colours, misc info, Currently, RP status): unchanged except the authorised mappings.
13. **At First Glance.** On A, `/dawnward trp3 glance title 1 Silver scar`, `… text 1 Across the jaw.`, `trp3 enable glance confirm`. On A's Miscellaneous tab the entry shows in the first free slot with its icon; A's own slots are unchanged. On B (and an MSP client), the glance icon appears on A's tooltip/target frame and the slot reads the same. `glance hide 1`: B no longer sees it (A still does, greyed). Edit the slot in TRP3: `/dawnward trp3 preview` shows the conflict; nothing is overwritten.
14. **Rollback.** On A, make a fact Secret, then **Exact restore…** shows the fact; cancel. **Roll back…** (safe): B never sees the Secret fact.

## Internal dependencies and their risk

| Dependency | Why | If TRP3 changes |
|---|---|---|
| `CurrentUser:GetProfile()` returning the live table | No public section reader or writer | Probe or shape check fails → sync blocked |
| About / PS layout (above) | To find owned content | Shape check fails closed → sync blocked |
| `TRP3_Addon:TriggerEvent`, `TRP3_Addon.Events.REGISTER_DATA_UPDATED`, `TRP3_API.globals.player_id` | So TRP3's UI, MSP and the exchange see the change | Probe fails → sync blocked |
| Version rule (+1, wrap at 100) | Other clients re-fetch on a different number | Remote clients may not re-fetch → caught by the two-client L3 test |
| `TRP3_API.navigation.page.getCurrentPageID` / `getCurrentContext` (`isEditMode`); frames `TRP3_RegisterAbout`, `TRP3_RegisterCharact`, `TRP3_RegisterAbout_AboutPanel_Edit`, `TRP3_RegisterCharact_Edit_NamePanel` | To avoid writing under an unsaved draft | Navigation or edit frame missing or failing → "cannot tell whether the editor is open" → sync blocked |
| `TRP3_API.RegisterCallback` | Hints only | Missing → still works on Dawnward's own triggers |
| `TRP3_Characters` (read only) | To warn about shared profiles | Missing → no warning |
| `characteristics.FT`, `RA`, `CL`, `AG`, `BP` as top-level strings, `nil` when empty; `Utils.str.sanitize` on load | Profile field sync | A non-string value pauses the field (conflict); a changed sanitiser could alter a value at load → a conflict, never an overwrite |

**Newer TRP3 (3.5.x / `main`):**
- Same setters and save path.
- Icons are now stored as numeric file IDs.
- **Not allowlisted.** It needs its own audit and an in-game test first.

## Known limits and risks

- **Not validated in game.** Every sync claim above is source analysis (S/I) or mocked tests (L2).
- **Other players don't see changes instantly.** TRP3 is pull-only: they see the update when their client next checks your profile (mouse-over or target, at most every 10 s, and only after their cached version differs).
- **Shared profiles:** every character using that profile shows the same section, and only **one character per profile** can sync each feature. A second character's opt-in is refused, because the two would keep replacing each other's content. Opting in names the other characters. Keep, rollback, release and a failed write switch the feature off for every character on that profile.
- **A literal copy of Dawnward's section** pasted elsewhere in the same text field makes the block ambiguous. That's a conflict, never a guess. But if the player deletes Dawnward's section and keeps an identical copy of it, Dawnward treats the copy as its own. The same applies to a trait with Dawnward's labels and value.
- **If a TRP3 editor was opened and the window closed without saving**, sync waits until the editor is cancelled or saved. That is deliberate.
- **Simulation data is never published.** Turning simulation on pauses sync.
- **Field values are never shortened or reformatted.** A Dawnward value Total RP 3 would alter is "not writable" and left alone. **Import** is exact too: a TRP3 value longer than Dawnward's field (or with formatting Dawnward does not keep) is refused, not shortened.
- **Reading for display or import** (differences, `trp3 import`, the story import) goes through `Adapter.ReadAudited`, which refuses an unaudited TRP3 version. `AboutBlock.WithoutOwned` returns nil plus a reason when Dawnward's section cannot be separated, so the player's "own text" never silently includes Dawnward's block.
- **The Total RP 3 page** builds its view with one probe and one read per section (`TRP3Commands.Overview` caches them); a write never uses that cache.
- **A field Dawnward wrote is cleared** in TRP3 when its Dawnward value stops being Public (race, class and first name return to the game's value). If the player had chosen "Use Dawnward's" over their own value, their old value is only in the backup.
- **An exact rollback** of the characteristics section stops managing both traits and fields; the safe rollback keeps the current policies.
- **Homeland maps to TRP3's Birthplace.** If you use Homeland for where your character lives now, keep that mapping on Total RP 3 and type Residence yourself.

## Open questions (to verify in game)

- Does TRP3's open profile page refresh by itself after the update event?
- Does a second client (and an MSP client) receive the update after mouse-over?
- Do profile field writes (`FT`, `RA`, `CL`, `AG`, `BP`) reach other TRP3 and MSP clients exactly like the public setters do (multiplayer procedure, steps 2, 5 and 9)?
- Do additional-information entries written with `IC` from `GetMiscTypeInfo` show the expected icon on Classic Era (some preset icons, for example pronouns' `vas_namechange`, may not exist in the Classic icon set; TRP3 then resolves its own fallback at load)?
- Do Dawnward's custom traits (icons `INV_Misc_QuestionMark`) render like a trait created in TRP3's editor?
- Do At First Glance slots written by Dawnward show on the player's own Miscellaneous tab immediately, and on other clients after their next misc version query?
- Does the page-context edit-mode check match what TRP3 does in every path (cancel, tab switch, closing the window mid-edit, `/reload` while editing)? Check with `/dawnward trp3 diagnose`.

## The About page (v0.9)

`Integrations/TRP3/AboutDoc.lua` builds the document, `Presentation.lua` styles it, and the plan follows the same ownership rules as before.

**Settings (Settings > Total RP 3 > Overview, or `/dawnward story set …`):**
- **About page** (`trp3About`): **Auto** (the full profile for characters on the profile model, the v0.3 summary block for others), **Profile**, or **Summary**.
- **Template** (`trp3Layout`): **Keep** your Total RP 3 template, or **Text** (1), **Frames** (2), **Sections** (3). Choosing one in Dawnward moves only Dawnward's content (the player's text in the old template is untouched) and switches TRP3's template; switching the template in TRP3 instead is a conflict, never overwritten.
- **Style** (`trp3Style`): Neutral (plain headings), Silver Hand (gold headings, background 3: Marble), Arcane (violet headings with section icons).

**Sections**, in order, each only when it has Public content: Character overview, Appearance, the biography (one section per heading of the player's own, the text before the first heading titled "Background"), Family, Beliefs and motivations, Personality, Defining experiences, Chronicle notes. Section titles are generic container names or the player's own headings; nothing is invented.

**Templates:**
| Template | Where Dawnward writes |
|---|---|
| 1 | One text after the player's own `T1.TX` (each section a `{h2}` heading and its text) |
| 2 | One frame per section after the player's frames: `{ TX, IC = the section icon, BK = the style's background }`. A frame the player restyles keeps their icon and background; only its text is updated |
| 3 | `PH`: the appearance (TRP3 titles it); `PS`: beliefs and personality; `HI`: overview, biography, family, experiences, notes; each after the player's own text in that part |

**Ownership modes:**
- **Append** (default): the player's own text and frames are never changed.
- **Adopt**: the player chose "Replace it with Dawnward's" when connecting. The first write takes over each slot it uses after a backup (the player's previous text stays in that backup); afterwards an edit in TRP3 is a conflict.

**Never duplicated:** content is found by exact match; missing, duplicated or edited content is a conflict. Text identical to Dawnward's that Dawnward has no record of writing (for example after a lost ledger) is also a conflict, so the About page is never written twice.

**Never shortened:** a slot over 30 000 bytes is refused with the reason. The biography itself is stored up to 16 KB and is never cut. TRP3 has no hard size limit, only a "profile too heavy" warning when the profile would need more than 20 messages to send (`RegisterExchange.lua`); a long biography may trigger it.

**Icons** are Total RP 3 3.4.1's own interface icons, the entry it uses on older clients (`DirectorySection`, `HistorySection`, `MiscInfoSection`, `PhysicalSection`, `TraitSection`, `TargetNotes`, `ProfileDefault`). **Backgrounds** are indices 1 (Dialog) and 3 (Marble) of TRP3's tiled background list (v0.10: Silver Hand moved from 2, Bank-Background, which the Classic Era 1.15.9 UI source does not use; every icon and background is on the allowlist in `Presentation.ICONS` / `Presentation.BACKGROUNDS`, checked by `tests/spec/trp3_presentation_allowlist_spec.lua`). Frames the player restyled keep their own icon and background on every update. Whether each icon and background renders on Classic Era is to be checked in game (L3).

**Preview:** Overview > **Preview profile** (or `/dawnward trp3 profile`) shows everything that would be published, read only.

## Presentation and supported markup (v0.4)

`Integrations/TRP3/Presentation.lua` formats Dawnward's own section; `AboutBlock` decides what is in it. Markup confirmed in TRP3 3.4.1's source (`totalRP3/Core/Utils.lua`: `convertTextTags`, `structureTags` and the HTML conversion) **S**:

| Markup | Effect |
|---|---|
| `{h1}…{/h1}` to `{h3}…{/h3}`, optionally `{h2:c}` / `{h2:r}` | Headings (left, centre, right) |
| `{p:c}…{/p}`, `{p:r}…{/p}` | Centred or right-aligned paragraph |
| `{col:RRGGBB}…{/col}` (also `{col:<letter>}`) | Text colour |
| `{icon:<icon file name>:<size>}` | An icon |
| `{img:<path>:<w>:<h>[:align]}` | An image |
| `{link*<url>*<text>}`, `[text](url)` | Links |

TRP3 has **no font tags**: headings use TRP3's own heading fonts. Dawnward uses only headings, colour and icons. Its styles are Neutral (the default, exactly the v0.3 block), Silver Hand (gold headings) and Arcane (violet headings, book icon). How they render in game is **not yet verified** (v0.4 checklist I3). Player text is always escaped (`{` and `}` become brackets), so it can never become markup.

**What reaches TRP3:** public facts (as in v0.3); public personality axes (traits sync); and, new in v0.4, the titles of journal entries the player approved, marked as defining moments and made public. Drafts cannot be public. The story table (events, decisions, private answers) is never part of a projection.
