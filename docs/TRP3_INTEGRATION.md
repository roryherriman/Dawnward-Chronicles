# Total RP 3 integration

**Status (v0.9-dev):** read-only status (tested in game, v0.1/v0.2), plus **experimental automatic sync** of the character's whole public profile: the About page (the character overview, the whole biography and the sections the player chose, in templates 1, 2 and 3), Dawnward-owned personality traits, thirteen profile fields, four additional-information entries and the At First Glance entries the player writes for it, each under a per-item ownership policy. Connecting is **one authorisation** (the setup wizard's Total RP 3 stage, or Overview > Connect everything); after that, changes in Dawnward reach Total RP 3 automatically.

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
5. Only the **published profile** (`Projection.GetPublic`, see [PRIVACY.md](PRIVACY.md)) reaches TRP3: journal notes, drafts, unapproved suggestions, story answers, memories, inner convictions and simulation data never do. Since v0.10 there is no per-item Public / Private / Secret; an older character publishes only what an earlier version marked Public until the player confirms once.
6. Dawnward changes **only content it owns**, proven by an exact match against its ledger. It never changes the player's text, template choice, layout, preset traits or the player's own traits. When in doubt, it stops and asks.
7. A failure in the integration cannot reach the core: every TRP3 access is wrapped in `pcall` and type-checked.

## Public API capabilities (TRP3 3.4.1 and `main`), issue #8

| Data | Public read | Public write | Notes |
|---|---|---|---|
| Profile identity | `GetProfileID`, `GetProfileName`, `IsProfileDefault`, `GetCharacterID` **S** | `SetProfileID` (select only) **S** | Default profile IDs end in `*` and change every login **S** |
| Names, title, full title, race, class, colour, icon | getters **S** | `SetFirstName`, `SetLastName`, `SetTitle`, `SetFullTitle`, `SetCustomRace`, `SetCustomClass`, `SetCustomClassColor`, `SetCustomIcon` **S** | Refused silently on the default profile **S** |
| Currently, OOC, RP status, walk-up, RP experience | getters **S** | `SetCurrentlyText`, `SetOutOfCharacterInfo`, `SetRoleplayStatus`, `SetWalkup`, `SetRoleplayExperience` **S** | The setters (`UpdateProfileField`): no-op if unchanged, bump `v`, fire `REGISTER_DATA_UPDATED(player_id, profileID, section)` **S**. Dawnward (v0.10.1) uses the first four, and `SetCustomIcon` / `SetCustomClassColor`, for what the player sets on the Total RP 3 page (`StatusPlan.lua`); never `SetRoleplayExperience` (account-wide) **L2** |
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
- `ST` holds the RP-style answers, keyed by `STYLE_FIELDS` id (`RegisterMisc.lua` 33–99): `"2"` injury, `"3"` death, `"4"` romance, `"7"` criminal activity, `"8"` loss of control — values 0 "Do not show", 2 "No", 3 "With player permission", 1 "Yes" — and `"6"` guild membership (0, 2 "OOC membership", 1 "IC membership"); a missing key reads as 0 (line 160) **S**. Labels: `Locales/enUS.lua` 142–158 and 996, `NO`/`YES` are the game's own **S**. Written only by the player's dropdowns (`onEditStyle` 104–120: `ST[id] = choice`, then `incrementNumber(v, 2)` and `REGISTER_DATA_UPDATED(player_id, profileID, "misc")`); there is **no public setter** **S**. MSP sends `RI`/`RD`/`RR`/`RM`/`RO` from it (`RegisterMSP.lua` 159–196) **S**.
- `PE` peek display settings live only in each slot (`IC`, `AC`, `TI`, `TX`); there is no other per-profile "peek" setting **S**.

### Character status (`player.character`)
- Default `{ v = 1, RP = 2, WU = 1 }` (`Dashboard.lua` 30: `ROLEPLAY_STATUS.OUT_OF_CHARACTER`, `WALKUP.NO`; `Core/Enums.lua` 25–28: `IN_CHARACTER = 1`, `OUT_OF_CHARACTER = 2`; 50–53: `NO = 1`, `YES = 2`) **S**. `CU` (Currently) and `CO` (OOC information) are written through the public setters `SetCurrentlyText` / `SetOutOfCharacterInfo` (`Core/Player.lua` 442–447, `UpdateProfileField` 419), from the Miscellaneous tab's boxes (`RegisterMisc.lua` 396, 408, debounced, `Utils.str.sanitize(text, true)`) and the Currently frame (`Dashboard/Currently.lua`) **S**. **No length limit**: neither box sets `letters`/`maxLetters` (`RegisterUIMisc.xml` 176, 204; `UI/ScrollingEditBox.xml` 14 leaves it commented out); `DB_STATUS_CURRENTLY_COMMON` says other players' tooltips show the first **140** characters by default (`enUS.lua` 830) **S**. Dawnward caps its own copy at 1000 bytes and shows the 140-character mark.
- `UpdateProfileField` (`Player.lua` 413–436): refused on the default profile except `character.RP` and `WU`; no-op when unchanged; else stores, `incrementNumber(v, 2)`, `REGISTER_DATA_UPDATED(player_id, profileID, subtable)` **S**. `SetCustomClassColor` raises unless given six hex digits or a colour object (478–490) **S**.
- RP experience is stored in TRP3's configuration, not the profile (`Player.lua` 500) **S**.
- `sanitizeCharacter` (`Dashboard.lua` 72) strips codes from `CU`/`CO` and, on the default profile, every key but `v`, `RP`, `WU` **S**.

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
| `AboutBlock.lua` | The v0.3-v0.8 summary block (`Compose`, `Plan`): kept to read and replace what those versions wrote; no longer published (pure) |
| `TraitPlan.lua` | Maps public Dawnward personality axes to owned custom traits, and plans changes (pure) |
| `FieldPlan.lua` | Profile field mappings (13 fields, below), the value cleaner, the game's own defaults and the per-field plan (pure) |
| `MiscPlan.lua` | v0.9: Dawnward-owned entries in TRP3's additional-information list (pronouns, faith, occupation, allegiance) (pure) |
| `GlancePlan.lua` | v0.9: Dawnward-owned At First Glance slots in TRP3's misc section, from the entries the player wrote (pure) |
| `Core/Glance.lua` | v0.9: the player's own At First Glance entries (`char.glance`, five at most), `/dawnward trp3 glance`; v0.10.1: `Save`, `Move` (order) and Dawnward's icon picker list (`ICON_CHOICES`) |
| `Core/RPStatus.lua` | v0.10.1: what the player sets for Total RP 3 (`char.trp3status`): Currently, OOC, roleplay status, walk-up, profile icon, class colour, and the six roleplay style preferences; `Suggest` (a Currently draft for the editor only) |
| `StatusPlan.lua` | v0.10.1: the `status` (`character.CU/CO/RP/WU`) and `look` (`characteristics.IC/CH`) features, planned as setter calls (pure) |
| `StylePlan.lua` | v0.10.1: the `style` feature: the preferences the player handed to Dawnward, in `misc.ST` (pure) |
| `UI/TRP3MiscSections.lua` | v0.10.1: the At First Glance, Status and OOC and profile-look editors of the Total RP 3 page |
| `AboutDoc.lua` | The About page (v0.10.1: overview, the whole biography, the player's optional sections; deduplicated), rendered for templates 1, 2 and 3, and its plan (pure) |
| `Presentation.lua` | Styles, body colour, headings, verified icons and backgrounds, and the preview model (pure) |
| `UI/TRP3BiographyPanel.lua` | v0.10.1: the About choices and the live preview (embedded in Settings > Total RP 3 > Biography) |
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
| Status and look (v0.10.1) | `CU`, `CO`, `RP`, `WU`, `IC`, `CH` that Dawnward wrote through the setters | The key holds exactly the value the ledger says Dawnward last wrote (`profiles[id].status` / `.look`). A value Total RP 3 already shows exactly when the player sets the same in Dawnward is taken over without a write |
| Roleplay style (v0.10.1) | Each `ST` preference the player handed to Dawnward | `ST[key]` holds exactly the value Dawnward last wrote (`profiles[id].style`) |

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
   - At most 20 backups are kept in total. The state before Dawnward's first write in each section (no Dawnward content; one per profile and section, kept until a newer such state exists) is pinned and never pushed out by other backups. The player's value saved when they choose "Use Dawnward's" on a field is pinned too (at most 4 such pins; past that the oldest becomes an ordinary backup). Of the ordinary backups, the oldest of the section with the most goes first, so frequent writes to one section (the status, for example) push out their own backups, never another section's. So many automatic writes never push out the way back to the player's own profile.
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
| `/dawnward trp3 rollback [#]` | **Preview only.** Names the backup and lists every piece of Dawnward-owned content in it that is **no longer in your profile** in Dawnward now (biography lines, personality values, field values), and whether your own text can be separated from Dawnward's part. Writes nothing. |
| `/dawnward trp3 rollback [#] confirm` | **Safe default (v0.8).** Restores **your own** content from the newest (or a chosen) backup for the **active** profile; Dawnward's part of that backup is dropped and planned again from what is Public **now**, for the features Dawnward manages now. Nothing that is no longer Public comes back. Refused (with the reason) if Dawnward's part cannot be separated exactly. |
| `/dawnward trp3 rollback [#] exact confirm` | The v0.7 behaviour, now explicit: restores the section **exactly** as it was, including Dawnward content that may no longer be Public (the preview names it), restores the ownership records saved with the backup, and switches off every feature of that section (fields go back to "Managed by Total RP 3"). |
| `/dawnward trp3 release about\|traits\|fields confirm` | Removes only Dawnward's content and stops managing it |
| `/dawnward trp3 resolve about\|traits\|<field> keep\|reclaim` | Settles a conflict (see Ownership policies) |
| `/dawnward trp3 fields` | Every mapping, who manages it, and the differences view (read only) |
| `/dawnward trp3 import <field> confirm` | Copies Total RP 3's value of one field into your Dawnward profile |
| `/dawnward trp3 backups`, `/dawnward trp3 log` | Inspect backups and diagnostics |
| `/dawnward trp3 paste` | The manual path: the same section, suggested traits and every profile field (including fields Dawnward never writes) as text to paste into TRP3 yourself (always available, any TRP3 version) |

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
| `firstName` | `characteristics.FN` | `saveInDraft` `RC.lua` 484 (`or Globals.player`); setter `SetFirstName` `Player.lua` 454 | per field, exact value | yes | name on tooltip and profile |
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
| game race, class, name (no value of the player's own) | `RA`, `CL`, `FN` | TRP3's default profile `RC.lua` 44–51 = `UnitRace`/`UnitClass`/`UnitNameUnmodified` (`Globals.lua` 48–51) | **never owned**; counts as replaceable; restored when Dawnward takes its own value out | yes | Race "Human", Class "Paladin" after making a Dawnward race Private |
| `pronouns` | `MI` entry `{ ID = 7, NA = localised "Pronouns", VA, IC = preset icon }`; MSP `PN` | `ProfileUtil.lua` 9–21, 143, 157; `miscAdd` `RC.lua` 602, 650; `RegisterMSP.lua` 145 | type + exact `VA` (an ID-less entry typed by its English or localised name is recognised: never duplicated) | yes | pronouns row with its icon; MSP `PN` |
| `faith`, `occupation`, `allegiance` | custom `MI` entries `{ ID = 1, NA = "Faith" …, VA, IC = TRP3_InterfaceIcons.Default }` | `RC.lua` 644 ("Create new"), `CreateMiscFieldInfo` `ProfileUtil.lua` 103 | name + exact `VA`; `IC` never compared | yes | three rows, question-mark icon, restylable |
| Personality axes (6), named with the player's own axis words when set (v0.10) | custom `PS` traits `{ LT, LI, RT, RI, V2 }`, `V2 = 20 − value`; a renamed axis renames the same owned trait in place | `refreshPsycho` `RC.lua` 186–191; `psychoAdd` 685 (icons `INV_Misc_QuestionMark`); `Globals.lua` 68–69; MSP `Fields.lua` 146 | `LT`/`RT` pair + `V2` | yes | bar leans to the right pole for a high Dawnward value |
| About page | `about` T1 / T2 / T3 | see "The About page (v0.10.1)" | owned block / frames / slots | yes | see that section |
| At First Glance entries the player wrote (the page's At First Glance editor, or `/dawnward trp3 glance`) | `misc.PE["1".."5"] = { TI, TX, IC, AC }` | `applyPeekSlot` `RM.lua` 332; default `RM.lua` 18; five slots `RM.lua` 254, 457; inactive dropped from exchange `getMiscExchangeData` 452 and MSP `RegisterMSP.lua` 167–189 | per slot, exact `TI`/`TX`/`IC`/`AC`; only free slots; no duplicate titles+texts; v0.10.1: Dawnward's order (Move up/down) is the order of its owned slots, a removed entry empties its slot | yes (feature `glance`, off by default) | slot on the Miscellaneous tab; glance icon on others' target frame; hidden entry not visible to others; reordering in Dawnward reorders Dawnward's slots only |
| Currently (v0.10.1, typed by the player in Dawnward; "Suggest" only drafts) | `character.CU` | public setter `SetCurrentlyText` `Player.lua` 446 (`UpdateProfileField` 419) | per value, exact; feature `status`, row `currently` | only after the player turns sync on for it | tooltip "Currently" line; Miscellaneous tab box |
| OOC information (v0.10.1) | `character.CO` | `SetOutOfCharacterInfo` 442 | as above, row `ooc` | as above | tooltip OOC line |
| Roleplay status (v0.10.1) | `character.RP` 1 in character / 2 out of character | `SetRoleplayStatus` 438; `Enums.lua` 25 | as above, row `rpStatus` | as above (never inferred) | the toolbar/target status icon |
| Walk-up (v0.10.1) | `character.WU` 1 no / 2 yes | `SetWalkup` 450; `Enums.lua` 50 | as above, row `walkup` | as above (never automatic) | walk-up icon on the tooltip |
| Profile icon (v0.10.1) | `characteristics.IC` | `SetCustomIcon` 462 | feature `look`, row `icon`; releasing keeps the icon (no empty value) | after Authorize in Profile | the profile's icon |
| Class colour (v0.10.1) | `characteristics.CH` (six hex digits) | `SetCustomClassColor` 478 (raises on anything else, so never cleared) | feature `look`, row `classColor` | after Authorize in Profile | the coloured name and class |
| Roleplay style preference (v0.10.1, one by one) | `misc.ST["2"/"3"/"4"/"7"/"8"/"6"]` | **no setter**: the guarded internal misc write (backup, read-back, restore), as `onEditStyle` `RM.lua` 104 writes it | feature `style`, one row per preference; `OPT_IN_ONLY`: never by Connect everything | only after "Dawnward" is chosen for that preference (default: Total RP 3, read only) | Miscellaneous tab → Roleplay style; MSP `RI`…`RO` |

**Supported by TRP3, not implemented** (Dawnward has no source data, or the value is the player's live choice)

| TRP3 field | Path (evidence) | Why not |
|---|---|---|
| Eye colour colour `EH` | `RC.lua` 569–580 | No Dawnward source |
| Background `bkg`, residence pin `RC` | `RC.lua` 304, 372 | TRP3 choices with no Dawnward source |
| TRP3's own icon browser | `TRP3_API.popup.showPopup(ICONS, …)` (`Core/Popup.lua` 815); `TRP3_IconBrowser.Open` (`UI/Browsers/IconBrowser.lua` 978) | `TRP3_IconBrowserFrame` is a child of `TRP3_PopupsFrame` inside `TRP3_MainFrame` (`IconBrowser.xml` 184, `UI/Main.xml` 271): showing it from Dawnward would mean re-parenting Total RP 3's frames, which Dawnward never does. Dawnward offers its own picker over icons verified for Classic Era (`Glance.ICON_CHOICES`: TRP3 3.4.1's older-client fallbacks in `Resources/InterfaceIcons.lua`, and icons the 1.15.9 UI itself uses), and any icon name can be typed |
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
| RP experience | Account configuration, not profile data (`Player.lua` 496–511: `configuration.setValue("roleplay_experience")`); changing it from a character tool would change every profile |
| Opening Total RP 3's Miscellaneous tab directly | The page's **Open in Total RP 3** calls `TRP3_API.navigation.openMainFrame` (`MainStructure.lua` 253) and `navigation.menu.selectMenu("main_12_player_character")` (156; `RegisterMain.lua` 771), the same as TRP3's menu, and says to open the Miscellaneous tab: the tab group is a local (`RegisterMain.lua` 578). Refused while a TRP3 editor holds an unsaved draft, which a new page context would discard |
| Companion profiles | Separate pet/mount profiles; out of scope |

Why the editor path rather than the public setters for Title, Race and Class: Age and Birthplace have no setter, and the five fields are written as **one** backed-up, read-back-verified transaction on the characteristics section, exactly as TRP3's own `saveCharacteristics` does (replace contents, bump `v`, fire `REGISTER_DATA_UPDATED`). The effect for TRP3, MSP and other clients is the same as the setters' `UpdateProfileField`. The setter names are recorded in `FieldPlan.MAPPINGS` (`setter`) for a later switch.

Inferred values are never written: every supported source is a field the player typed (or a homeland the player chose), only when it is in the published profile (before v0.10: when its Dawnward visibility was **Public**), or an At First Glance entry the player wrote for Total RP 3. The one game-derived exception is v0.9's **game fallback** for race, class and first name: when Dawnward takes its own value of one of those back out, the field returns to the value the game itself shows (`UnitRace`/`UnitClass`/`UnitName`, exactly what TRP3 puts in a new profile), unowned. A field the player emptied or wrote in TRP3 is never filled. `Character.GameValue(key)` / `Character.FieldOrGame(char, key)` give the UI the same value for display.

## Ownership policies

Stored per character **and** linked profile in `DawnwardChroniclesTRP3DB.optIn[character]` (`profileId`, `policy[mapping]`):

| Policy | Meaning | Who sets it |
|---|---|---|
| `dawnward` — Managed by Dawnward | Updated automatically from your profile (status, look and style rows: from what the player set for Total RP 3) | Only an explicit authorisation: the page's **Authorize…** confirmation, `trp3 enable about\|traits\|glance confirm`, `trp3 field <name> dawnward confirm`, a row's "Sync on" / "Dawnward" with its confirmation, `trp3 sync-status <row> on` |
| `trp3` — Managed by Total RP 3 | Never written; shown in the differences view, importable on request | The default for every field |
| `off` — Not synchronised | Never written, not compared | The default for the biography and traits (that is "sync off") |

- **Migration:** a v0.7 opt-in (`about = true` / `traits = true`) loads as policy `dawnward` for that feature, with no change in behaviour; the booleans are still written so an older build reads the same choice (an older build drops the policies, and every field then falls back to "Managed by Total RP 3").
- **Writes** happen only while the field holds exactly the value Dawnward last wrote, or is empty and has never been written by Dawnward. If Total RP 3 already holds the player's own value, or the player (or another addon) changed Dawnward's value, that field is **paused** (`profiles[id].fieldConflicts`), nothing is overwritten, and the other fields keep updating. A field whose Dawnward value stops being Public is cleared in TRP3 (it was Dawnward's own value); race, class and first name go back to the game's value instead.
- **Resolve:** **Keep yours** (`resolve <field> keep`) hands the field to Total RP 3; **Use Dawnward's** (`resolve <field> reclaim`) records TRP3's current value as Dawnward's, so the next run replaces it after a backup (the player's value stays in that backup).
- **One character per profile** may manage each mapping; a second character's authorisation is refused, and **Authorize** is all-or-nothing.
- Leaving `dawnward` for a field forgets Dawnward's ownership; TRP3 keeps its current value. **Except** when TRP3 still shows the exact value Dawnward wrote and that value is no longer your Public value (`Sync.FieldRisk`): the command refuses until you choose `trp3 field <name> trp3|off release confirm` (remove it first, recommended) or `… keep confirm`; on the page, the row and the Authorize confirmation say it will be removed first, and Authorize removes it (guarded, backed-up write) before saving the choice.
- Field conflicts are cleared when Dawnward stops managing the field (Keep yours, release, policy change, exact rollback) and when it is authorised again; the page shows conflicts only for fields Dawnward manages.
- **Authorize is all-or-nothing:** every choice is validated first (write capability, a storable non-default profile, the shared-profile rule), then applied on a snapshot of the ledger that is restored if anything fails.

## Status, OOC, walk-up, icon, colour and roleplay style (v0.10.1)

Everything here is the player's own, set in Dawnward (Settings > Total RP 3 > **Status and OOC**, and the icon and colour editors at the top of **Profile**; or `/dawnward trp3 currently|ooc|rpstatus|walkup …`). Nothing is inferred: **Suggest** drafts a Currently text from the zone (`GetRealZoneText`) and the established active goal into the editor only; only **Save** keeps it. In the default **Manual** Currently mode nothing reacts to a zone change; the Suggested and Automatic modes are described under *Profile suggestions (v0.10.2)*.

- **Writes** go through Total RP 3's own setters (`Adapter.ApplySetters`; `VersionProfiles` tier `publicSetters`, 3.4.1 only). The same guards as every other write apply (opt-in per row, profile binding, never the default profile even though TRP3 would accept `RP`/`WU` there, simulation, read-only data, combat). A backup of the section (`character`, or `characteristics` for the icon and colour) is taken first and the result is read back; on a mismatch the backup is restored (through the setters for `character`).
- **Ownership** (per row, `profiles[id].status|look`): Dawnward owns a value only after the player set it in Dawnward with sync on for that row, and only while Total RP 3 still shows exactly what Dawnward last wrote. Total RP 3 holding anything else is a **conflict**: the row pauses, nothing is overwritten, the others carry on. **Keep yours** hands the row to Total RP 3; **Use Dawnward's** keeps Total RP 3's value in a pinned backup and writes Dawnward's on the next run; **Import** copies Total RP 3's value into Dawnward (with a confirmation) and ends the pause (both now agree, so nothing is written). First connection with an existing Total RP 3 value: the same pause and **Import** offer, never an overwrite. A value Total RP 3 already shows exactly is taken over without a write. No write when the value is the same.
- **Clear** empties Currently/OOC in Total RP 3 on the next sync (as `""`, as TRP3's own box stores an emptied text), only if Dawnward wrote them. Roleplay status, walk-up, icon and colour have no empty value: releasing them leaves Total RP 3's value and forgets ownership.
- **Roleplay style** is shown read only with Total RP 3's own labels. Each preference can be handed to Dawnward on its own ("Dawnward" in its row, after an EXPERIMENTAL confirmation); it is never handed over by **Connect everything** (`Ledger.OPT_IN_ONLY`). Handed-over preferences are written by the guarded internal misc write (same backup and read-back as At First Glance, which shares the section and is kept exactly). Otherwise **Open in Total RP 3** opens the player's page there.
- **Rollback:** `character` backups restore `CU`, `CO`, `RP` and `WU` through the setters (other keys there are Total RP 3's own and are left alone); the safe restore empties Dawnward's old texts and plans Dawnward's current values again.
- **Ledger** (still schema 2): `profiles[id].status`, `.look`, `.style`, their row conflicts in `fieldConflicts`, and `character` backups. An older build drops them and their policies, which only switches those rows off; the next run then pauses on Dawnward's old value (never overwrites it).
- **Saved data:** `char.trp3status` (cleaned by `RPStatus.Clean` in `Schema.NormalizeCharacter`; older characters load with `{ style = {} }`); kept in personal backups, and a backup without it keeps the current values.

## Profile suggestions (v0.10.2)

The one link from the character's development to the public profile: verified gameplay event → the player's answer in the Story Director → approved development → a **suggested** profile change → the player accepts → Dawnward's own copy changes → the existing guarded sync publishes it. `Core/ProfileSuggestions.lua` (store, generators, wording) and `Core/ProfileActions.lua` (the player's actions, the Automatic gate) never touch Total RP 3.

- **At First Glance** (`glance`): offered only from cumulative evidence: `AXIS_STEPS` (3) approved story changes net in one direction on one axis (the player's own settings, reversed and rejected changes never count; a second, stronger tier at 6 may revise it), a memory the player established and marked defining (importance 3), or a goal the player marked achieved. Never from levels, quests or zone visits alone. The wording describes only the approved direction as an outward impression (templates per axis and tier, the character's Pronouns field or neutral words), never a physical trait. A suggestion goes into a free Dawnward entry, or revises the entry an earlier accepted suggestion of the same theme filled, only while that entry still reads exactly as accepted (`PS.ManagedSlot`); an entry the player wrote or edited is never revised, and a slot the player filled in Total RP 3 is never written (`GlancePlan`, unchanged). With no free entry and nothing of Dawnward's to revise, it waits.
- **Currently** (`currently`): per character **Manual** (the default; every existing character, and any with a Currently value, stays Manual), **Suggested**, or **Automatic** (only after a confirmation; `RPStatus.SetCurrentlyMode`, stored as `trp3status.currentlyMode`, never sent to Total RP 3). Triggers: a first recorded visit to a zone, a major moment the player answered (significance 3: a completed quest, an instance, a reputation standing; never a level or a death), a new goal. The text holds only verified facts and the player's own goal ("In Westfall. Recently completed The Defias Brotherhood. Working towards: Find my brother."); a 30-minute cooldown, never the same text twice, one waiting at a time.
- **Automatic** writes Dawnward's Currently by itself only when the suggestion was made in that mode and names no private goal, Dawnward's own text is empty, still the one it held when Automatic was turned on, or Automatic's own last text, and Total RP 3 lets it: not simulation, connected and bound, Currently kept in sync by Dawnward, no conflict, Total RP 3 shows nothing or exactly what Dawnward last wrote (`ProfileActions.CurrentlyGate`, through `Sync.StatusView`). Otherwise the suggestion waits for the player with the reason. The write then goes through the usual status transaction (backup, setter, read-back), and **Undo last automatic update** brings the previous text back.
- **Provenance and dedupe:** each suggestion names its records (decision, personality change, memory, goal ids, event keys) and why, in plain words. A theme (axis and direction, memory, goal, zone) is offered once: accepted or dismissed, it comes back only with materially new evidence (a higher tier). **Later** hides it for a day.
- **UI:** the Story Director's side column ("Your profile could show this"), the At First Glance editor (the suggestion takes the preview's place), Status and OOC > **Currently updates** (mode, waiting suggestion, Undo), and a count in the Total RP 3 page's rail. **Edit** puts a suggestion in the section's own editor; **Save** accepts it in the player's words. All refused in simulation mode.
- **Saved data:** `char.profileSuggestions` (absent until the first suggestion; cleaned by `ProfileSuggestions.Clean` in `Schema.NormalizeCharacter`; at most 40 suggestions, the oldest settled ones pruned first, and 200 remembered keys); kept in personal backups, never in a shared export.
- **Not done (issue E):** appearance or personality-description wording. Dawnward's approved facts say nothing about appearance, and the personality description is already Dawnward's traits (`TraitPlan`) from the approved axis values; no wording could be grounded better than those, so none is suggested.

## The Total RP 3 page as a profile editor (v0.10.1)

Sections: **Profile** (icon and class colour editors, then who keeps each identity, title, race, class, physical, relationship and additional-information field: Dawnward / TRP3 / Off, staged until **Authorize…**, with **Import**), **Biography** (`UI/TRP3BiographyPanel.lua` when present, else the About page's choices and preview), **Personality** (Dawnward's traits, one per axis, `V2 = 20 − value`, and the player's own Total RP 3 traits, read only), **At First Glance** (the five entries: editor, icon picker, shown/hidden, order, preview, sync on/off), **Status and OOC** (two views: Currently and OOC; Status and style), **Synchronization** (three views: Connection, with **Disconnect…**; Status; Recovery: conflicts, backups, rollback). Opening or refreshing the page only reads (`TRP3Commands.Overview`, one probe and one read per section).

## First-time connection (Total RP 3 page, Mappings tab)

The page opens on **Mappings** while nothing is managed yet:
1. The summary strip shows whether TRP3 is installed and supported, and the active profile.
2. A warning appears when the profile is shared with other characters (`TRP3_Characters`, read only), or explains why writing is impossible (for example the default profile).
3. Every mapping has a selector (Dawnward / TRP3 / Off; Dawnward / Off for the biography and traits) and a line saying what TRP3 holds against Dawnward's value (a non-Public Dawnward value is never shown, only "not Public"). The fields Dawnward never synchronises are listed below, with the reasons on hover.
4. Choices are only staged. **Authorize…** opens a confirmation listing, per mapping, what the first sync would do (from your profile: "writes \"Elf\"", "already shows the same text (stays yours)", "Total RP 3 has your own value: paused until you choose, never overwritten", "nothing Public to write"), plus the shared-profile and experimental warnings. Cancel saves nothing.
5. After **Authorize**, the normal debounced, guarded run does the writing.
6. **Import** (per field, with a confirmation) copies TRP3's value into Dawnward through the normal Actions write path, into your profile. Nothing is ever imported automatically.

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
2. **Profile propagation.** On A, set Race and Age in Dawnward, Mappings → Race and Age → Dawnward → Authorize. Wait 5 s. On A, `/dawnward trp3 log` shows one `fields` write. On B, mouse over / target A (wait at least 10 s between checks): Race and Age show A's Dawnward values; nothing else changed.
3. **Biography rendering.** Authorize Biography with a summary, an imported story with two chapter headings and an appearance, in each presentation style. On B, the body text is ivory or parchment (not gold), the headings and icons render; no raw `{h2}` or `{col:…}` text; no sentence twice; the player's own text above is intact (templates 1, 2 and 3).
4. **Trait direction.** Set Courage 15 (Bold side); authorise Traits. On B, the Cautious/Bold bar leans **Bold** (5 / 15).
5. **Names and titles.** With Title managed: B shows the full title under A's name; first and last name are unchanged (never written).
6. **Updates after changes.** Change A's Age; within one minute B sees the new value after re-targeting. Clear Age in Dawnward: B sees the age field empty. Hide the Appearance section in Dawnward: it disappears from B's view of the About page.
7. **Conflict.** On A, edit Race in TRP3's editor and Save. Change Dawnward's Race. A shows the conflict once; B keeps showing A's TRP3 value. Keep yours → never overwritten again.
8. **Shared-profile isolation.** Link a second character C of A's account to the same TRP3 profile. On C, Authorize Race: refused, naming A. Switch A to another TRP3 profile: no write lands on it (`/dawnward trp3 log` unchanged), and B sees the other profile untouched.
9. **MSP interoperability.** With B running MyRolePlay or XRP (no TRP3): B sees A's description (`DE`) including Dawnward's block, and `RA`, `AG`, `NT`, `HB` with Dawnward's values after re-targeting.
10. **Formatting.** A Race with a `|` or line break in Dawnward: TRP3 shows it without codes, and it reads the same after A's `/reload` (TRP3's load-time sanitising leaves it unchanged; no conflict appears).
11. **No duplication.** After `/reload` and a second sync on A: exactly one Dawnward block, one trait per axis, `log` shows no write.
12. **No unrelated modifications.** Compare A's TRP3 profile before and after (A's own About text, preset traits, icon, colours, misc info, Currently, RP status, roleplay style): unchanged except the authorised mappings.
13. **At First Glance.** On A, `/dawnward trp3 glance title 1 Silver scar`, `… text 1 Across the jaw.`, `trp3 enable glance confirm`. On A's Miscellaneous tab the entry shows in the first free slot with its icon; A's own slots are unchanged. On B (and an MSP client), the glance icon appears on A's tooltip/target frame and the slot reads the same. `glance hide 1`: B no longer sees it (A still does, greyed). Edit the slot in TRP3: `/dawnward trp3 preview` shows the conflict; nothing is overwritten.
14. **Rollback.** On A, hide a section that was published, then **Exact restore…** names its lines; cancel. **Roll back…** (safe): B never sees them again.

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
- **A field Dawnward wrote is cleared** in TRP3 when its Dawnward value is removed from your profile (race, class and first name return to the game's value). If the player had chosen "Use Dawnward's" over their own value, their old value is only in the backup.
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

## The About page (v0.10.1)

The About page is the character's **public narrative**, not a list of Dawnward's records. `Integrations/TRP3/AboutDoc.lua` decides what is on it, `Presentation.lua` how it looks, and the plan follows the same ownership rules as every other part of the sync. Dawnward's own records (facts, family, stances, history entries, personality axes, journal) stay in Dawnward, untouched; only what is published changed.

**What the page holds**, in the player's order (default order below), each only when the player wrote it:

| Section (default title) | Source | Default |
|---|---|---|
| Character overview | the Summary field, in the player's words | on |
| Biography | the current biography, **word for word**: every paragraph and line break, and the player's own chapter headings (`# Title` or `{h2}Title{/h2}` lines become chapter titles) | on |
| Appearance | the Appearance field | on |
| Personality | the Personality field on the Character page (the player's own description), when written; nothing is ever generated from personality axes, traits or facts | on |
| Motivation | the Motivation field | **off** |
| New developments | approved defining moments (journal entries the player approved and marked important) that the biography does not already tell | **off** |

Never published any more: facts and their "Origin:" / "Relationship:" lists, family lists, "Beliefs and motivations", stance or persona lines, "Defining experiences", "Chronicle notes", history entries. No section is ever empty, and no text is invented to fill one: every heading is a section title (the player may rename it) or one of the player's own chapter titles.

**No repetition** (`AboutDoc.Dedupe`, pure, `tests/spec/trp3_about_v0101_spec.lua`): the biography is never changed. A sentence of the overview, an optional section or a development that the biography (or an earlier section) already says is left out; sentences are compared without case, spacing, punctuation or TRP3 tags, and a sentence of 24 characters or more also counts as said when it appears inside a longer one. The rest of the player's text stays exactly as written, paragraph breaks included. A section left with nothing (for example an overview that only repeats the biography's opening) is not shown.

**Choices** (saved per character in the story preferences; Settings > Total RP 3 > Biography, `UI/TRP3BiographyPanel.lua`, with a live preview):
- **Template** (`trp3Layout`): **Keep** Total RP 3's own, **Text** (1), **Frames** (2), **Sections** (3). Choosing one moves only Dawnward's content and switches TRP3's template; switching it in TRP3 instead is a conflict, never overwritten.
- **Style** (`trp3Style`): **Neutral** (ivory body text, TRP3's own white headings), **Silver Hand** (parchment body text, gold headings, muted gold chapter titles, Marble frames), **Arcane** (cool ivory body text, light violet headings with the section's icon).
- **Heading colour** (`trp3Accent`): the style's own, or gold, silver, crimson, azure, violet or verdant for section and chapter titles.
- **Sections** (`trp3Sections`): shown or hidden, title (60 characters), order (Up / Down), and for template 2 each frame's icon and background, picked from the verified lists only.
- **Content** (`trp3About`, chat only): `summary` publishes the overview alone; `auto` and `profile` the whole page.

**Templates:**
| Template | Where Dawnward writes |
|---|---|
| 1 | One text after the player's own `T1.TX`: each section a `{h2}` title, chapters `{h3}` |
| 2 | One frame per section after the player's frames, `{ TX, IC, BK }` from the section's icon and background (or the style's). The biography stays **one** frame; only when it is over 30 000 bytes is it split, and then only at the player's own chapter headings (never inside a chapter, never losing text) |
| 3 | `PH`: the appearance alone (TRP3 titles the part); `PS`: a personality description alone (none today, so the player's own `PS` text is all that shows); `HI`: the overview, the biography and the other chosen sections. Each after the player's own text in that part |

**Ownership modes:**
- **Append** (default): the player's own text and frames are never changed.
- **Adopt**: the player chose "Replace it with Dawnward's" when connecting. The first write takes over each slot it uses after a backup (the player's previous text stays in that backup); afterwards an edit in TRP3 is a conflict. A slot Dawnward does not write (for example the personality part when the Personality field is empty) is not taken over: what the player writes there later is theirs, and if Dawnward needs that slot later its text is appended after the player's. The takeover applies to the template it was made on: after a template change chosen in Dawnward, the new template's texts and frames are the player's and Dawnward appends there.

**Frames and the player's styling:** the record keeps, for each of Dawnward's frames, the section it holds (`frameIds`) and the icon and background Dawnward gave it (`frameStyles`, both v0.10.1, additive in the ledger). A frame still in Dawnward's style takes a newly chosen icon or background; a frame the player restyled in TRP3 keeps the player's choice, and moves with its section when the order changes. A restyled frame that is no longer needed is a **conflict** (never dropped). For a record written before v0.10.1 the style is unknown: such frames keep the icon and background they have, and count as restyled when they carry an icon or background Dawnward never writes.

**Upgrading from v0.9 / v0.10:** nothing to do. The next sync finds Dawnward's old text exactly (the ledger's `slots` and `frames`) and replaces it in place with the new page, in one backed-up, read-back write: no conflict, no duplicate. In template 2 each old frame is matched to a section by its heading ("Character overview", "Appearance", the first chapter for the biography); frames no longer needed are removed (Dawnward's only). In template 3 the old beliefs and personality text leaves `PS`. The player's own text and frames are untouched. `tests/spec/trp3_about_v0101_spec.lua` replays exactly what v0.10.0 wrote (`tests/fixtures/about_v010.lua`).

**Never duplicated:** content is found by exact match; missing, duplicated or edited content is a conflict. Text identical to Dawnward's that Dawnward has no record of writing (for example after a lost ledger) is also a conflict, so the About page is never written twice.

**Never shortened:** a slot or frame over 30 000 bytes is refused with the reason. The biography itself is stored up to 16 KB and is never cut. TRP3 has no hard size limit, only a "profile too heavy" warning when the profile would need more than 20 messages to send (`RegisterExchange.lua`); a long biography may trigger it.

**Why the body text was yellow, and the fix (v0.10.1).** Total RP 3 3.4.1 draws the About text in a SimpleHTML frame (`RegisterAbout.lua` `setupHTMLFonts`, lines 67-75): paragraphs use `TRP3_AboutParagraphFont`, a copy of `SystemFont_Shadow_Med1` (line 55), and headings `h1`-`h3` use Huge3, Huge1 and Large. It sets the three heading colours to white (`SetTextColor("h1", 1, 1, 1)` …) but **never sets the paragraph colour**, so every paragraph keeps the system font's normal gold. Dawnward wrote plain text, so all of it showed in that gold. The only colour mechanism in the About text is the `{col:RRGGBB}` tag: `convertTextTag` (`Core/Utils.lua` 441-455) turns it into `|cffRRGGBB … |r` after the HTML is built, so it colours text inside one paragraph but cannot span block elements. Dawnward now wraps **every non-empty body line** it writes in its style's body colour, and re-opens that colour after a `{/col}` of the player's own, so no line falls back to gold. Headings stay TRP3's white unless the style or heading colour sets one.

**What Total RP 3 cannot do (limits):**
- **No dividers.** `toHTML` converts only `h1`-`h3` and `p` (`structureTags`), and SimpleHTML has no `<hr>`; sections are separated by their title and one blank line.
- **No fonts or sizes** beyond `h1`-`h3`; the sizes are the player's own TRP3 settings (`CONFIG_REGISTER_ABOUT_*_SIZE`).
- **High contrast:** with TRP3's high-contrast option, `convertTextToHTML` strips every `{col}` tag (lines 115-127) and draws its own backgrounds, so the page shows in TRP3's own colours, as that player chose.
- **Colour tags are visible in TRP3's editor:** the player sees `{col:…}` around Dawnward's lines when editing the About text in TRP3. Editing Dawnward's part there is a conflict anyway (nothing is overwritten).
- **Other clients via MSP** (MyRolePlay, XRP): TRP3 sends the About text through `removeTextTags` (`RegisterMSP.lua` 64-93), which turns `{col}` into the client's own colour codes; headings stay as written, as for any TRP3 profile.
- **Template 3's titles and icons** are TRP3's own ("Physical Description", "Personality Traits", "History"); Dawnward cannot rename them.
- **Frame icons and backgrounds** are limited to the verified lists (`Presentation.ICONS`, `Presentation.BACKGROUNDS`): Total RP 3 3.4.1's own interface icons, the entry it uses on older clients (`DirectorySection`, `HistorySection`, `MiscInfoSection`, `PhysicalSection`, `TraitSection`, `TargetNotes`, `ProfileDefault`), and backgrounds 1 (Dialog), 3 (Marble) and 4 (Rock), each checked in the Classic Era 1.15.9 UI source (`tests/spec/trp3_presentation_allowlist_spec.lua`). Whether each renders on Classic Era is to be checked in game (L3).

**Preview:** Settings > Total RP 3 > Biography draws the page as Total RP 3 does (white headings, coloured body text, TRP3's gold for any uncoloured paragraph, frames with their icon and tiled background, template 3's titled parts). Connection > **Preview profile** (or `/dawnward trp3 profile`) shows everything that would be published, read only.

## Presentation and supported markup (v0.4)

`Integrations/TRP3/Presentation.lua` formats Dawnward's own content; `AboutDoc` decides what is in it. Markup confirmed in TRP3 3.4.1's source (`totalRP3/Core/Utils.lua`: `convertTextTags`, `structureTags` and the HTML conversion) **S**:

| Markup | Effect |
|---|---|
| `{h1}…{/h1}` to `{h3}…{/h3}`, optionally `{h2:c}` / `{h2:r}` | Headings (left, centre, right) |
| `{p:c}…{/p}`, `{p:r}…{/p}` | Centred or right-aligned paragraph |
| `{col:RRGGBB}…{/col}` (also `{col:<letter>}`) | Text colour |
| `{icon:<icon file name>:<size>}` | An icon |
| `{img:<path>:<w>:<h>[:align]}` | An image |
| `{link*<url>*<text>}`, `[text](url)` | Links |

TRP3 has **no font tags**: headings use TRP3's own heading fonts. Dawnward uses only headings, colour and icons (the styles are described in "The About page" above). How they render in game is **not yet verified** (v0.4 checklist I3). Titles and the player's field text are always escaped (`{` and `}` become brackets), so they can never become markup; the biography is kept exactly as written.

**What reaches TRP3 (v0.10.1):** the published profile (`Projection.GetPublic`, `docs/PRIVACY.md`): on the About page the overview, the biography, the appearance and, when switched on, the motivation and the defining moments the player approved; personality axes as traits (traits sync); the mapped profile fields. Drafts are never published. The story table (events, decisions, private answers) is never part of a projection. (Until v0.10.0 the About page also listed facts and stances; it no longer does.)
