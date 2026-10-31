# Total RP 3 integration

**Status (v0.9-dev):** read-only status (tested in game, v0.1/v0.2), plus **experimental automatic sync** of the character's whole public profile: the About page (the whole biography and every Public section, in templates 1, 2 and 3), Dawnward-owned personality traits, thirteen profile fields and four additional-information entries, each under a per-item ownership policy. Connecting is **one authorisation** (the setup wizard's Total RP 3 stage, or Overview > Connect everything); after that, changes in Dawnward reach Total RP 3 automatically.

The sync is **built and tested against mocks only (L2)**:
- It is **off by default**. A character connects once (setup's Total RP 3 stage, or Settings > Total RP 3 > Overview > **Connect everything…**), or authorises single mappings on the Mappings tab, or with `/dawnward trp3 enable about|traits confirm` and `/dawnward trp3 field <name> dawnward confirm`.
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

### About (`player.about`)
- The layout is `{ v, TE = 1|2|3, BK, MU, T1 = {TX}, T2 = { {TX, IC, BK}, … }, T3 = { PH, PS, HI = {TX, BK, IC} } }` **S**.
- Only the active template is sent to other players **S**.

### Characteristics (`player.characteristics`)
- `PS` is a list. A preset trait is `{ID, V2}`; a custom trait is `{LT, RT, LI, RI, LC, RC, V2}` **S**.
- `V2` runs from 0 to 20 (default 10). It is the number of points toward the **left** trait; the right trait gets `20 - V2` (`refreshPsycho`) **S**.
- There is no limit on the number of traits **S**.

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
| `Shape.lua` | Fail-closed layout checks for About and characteristics (unknown extra fields are preserved), and the version rule |
| `AboutBlock.lua` | Composes the Dawnward section from public facts, and plans insert, replace, remove, no-op or conflict (pure) |
| `TraitPlan.lua` | Maps public Dawnward personality axes to owned custom traits, and plans changes (pure) |
| `FieldPlan.lua` | Profile field mappings (13 fields, below), the value cleaner, the game's own defaults and the per-field plan (pure) |
| `MiscPlan.lua` | v0.9: Dawnward-owned entries in TRP3's additional-information list (pronouns, faith, occupation, allegiance) (pure) |
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
| Profile fields | The value of `FT`, `RA`, `CL`, `AG` or `BP` that Dawnward wrote | The field holds exactly the value the ledger says Dawnward last wrote. Text that merely matches is never claimed. |

These cases are a **conflict**:
- The owned content is missing, appears more than once, or was edited.
- The template changed.
- The player already has a trait with Dawnward's labels.

On a conflict, Dawnward writes nothing and pauses that feature until the player runs `/dawnward trp3 resolve about|traits keep|reclaim`:
- **keep**: the player's version stays and Dawnward stops managing it.
- **reclaim**: for the biography, the edited text becomes the player's and Dawnward appends a fresh section. For traits, Dawnward takes back its labelled traits at their current values.

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

## Field mappings

Verified against the Total RP 3 source at tag **`3.4.1`** (commit `4c25cb0`): `Core/Player.lua` (public getters and setters, `UpdateProfileField`), `Modules/Register/Characters/RegisterCharacteristics.lua` (`saveInDraft`, `saveCharacteristics`, `sanitizeCharacteristics`), `Modules/Register/Characters/RegisterMain.lua` (`cleanupMyProfiles`, `saveInformation`), `Modules/Register/MSP/RegisterMSP.lua`, `Modules/Dashboard/Dashboard.lua` and `Currently.lua`, `Core/ProfileUtil.lua` (misc info types), `UI/Widgets.xml` (`letters="0"`).

Facts that apply to every characteristics field below **S**:
- They are top-level strings of `player.characteristics`. The characteristics editor writes them as `stEtN(strtrim(text))`, so an empty field is stored as `nil`, never `""`.
- The editor boxes have no length limit (`letters="0"`).
- `Utils.str.sanitize` strips colour, link, texture and line codes from them when **your own** profiles load (`cleanupMyProfiles`) and when another client receives them (`saveInformation`). Dawnward therefore only writes a value **exactly as it is**, and only if sanitising would leave it unchanged: one line, no `|`, no extra spaces, at most 100 bytes (`FieldPlan.Check`). A value that does not qualify is **not writable**: it is never rewritten or shortened, nothing is written, a field Dawnward already wrote is left untouched (never cleared because of it), and the reason is shown (page row, `trp3 preview`, `trp3 fields`).
- The characteristics editor works on a draft (as for About); its Save copies the draft over the whole section. The existing editor guard covers them.
- On the default profile, TRP3 wipes everything except `v`, `RA`, `CL`, `FN`, `IC`; Dawnward never writes the default profile anyway.

### Complete mapping matrix (v0.9)

Verified against Total RP 3 **3.4.1** as installed (the same files as tag `3.4.1`): `Core/Player.lua`, `Core/ProfileUtil.lua`, `Core/Enums.lua`, `Core/Utils.lua` (`toHTML`, `convertTextTags`), `Core/UITools.lua` (backgrounds), `Resources/InterfaceIcons.lua`, `Modules/Register/Characters/RegisterCharacteristics.lua`, `RegisterAbout.lua`, `RegisterMain.lua` and `Modules/Register/MSP/RegisterMSP.lua`. Every write uses the editor path (replace the section's contents, bump `v`, fire `REGISTER_DATA_UPDATED`) inside a backed-up, read-back transaction; "public setter" only notes what TRP3 also offers.

| Area | Dawnward source | TRP3 destination | Public setter | Format and limits | Status |
|---|---|---|---|---|---|
| First name | `firstName` | `characteristics.FN` | `SetFirstName` | one clean line ≤ 100 bytes | **Synced.** The game's own name (TRP3's default) counts as empty and is replaced |
| Last name | `lastName` | `LN` | `SetLastName` | as above | **Synced** |
| Full name | (derived) | TRP3 shows `TI FN LN` | — | — | Follows from the three above |
| Title prefix | `honorific` | `TI` | `SetTitle` | as above | **Synced** |
| Full title | `title` | `FT` | `SetFullTitle` | as above | **Synced** |
| Race | `race` | `RA` | `SetCustomRace` | as above | **Synced.** The game's race counts as empty |
| Class | `class` | `CL` | `SetCustomClass` | as above; the class colour `CH` is untouched | **Synced.** The game's class counts as empty |
| Age | `age` | `AG` | none | as above | **Synced** |
| Birthplace | `homeland` | `BP` | none | as above | **Synced** |
| Residence | `residence` | `RE` (the map pin `RC` is untouched) | none | as above | **Synced** |
| Eye colour | `eyes` | `EC` (its colour `EH` untouched) | none | as above | **Synced** |
| Height | `height` | `HE` | none | as above | **Synced** |
| Body shape | `weight` ("Build") | `WE` | none | as above | **Synced** |
| Relationship status | `relationship` | `RS` (number) | none | single 1, taken 2, married 3, divorced 4, widowed 5; anything else is "not writable" and shown with the reason. RS 0 ("do not show") counts as empty | **Synced** |
| Pronouns | `pronouns` | an `MI` entry, preset type 7 | none | `{ ID = 7, NA = <TRP3's own localised name>, VA }`; MSP `PN` | **Synced** (additional information) |
| Faith, occupation, allegiance | `faith`, `occupation`, `allegiance` | custom `MI` entries named Faith, Occupation, Allegiance | none | `{ ID = 1, NA, VA }` | **Synced** (additional information); icons are never written or compared, so the player can restyle them |
| Physical description | `appearance` (Public) | template 3 `PH`; templates 1 and 2: an Appearance section | none | text | **Synced** in the About page |
| Full biography | the current biography source (when the biography is Public) | the About page: T1 text, T2 frames, T3 history | none | word for word, split only at the player's own headings; ≤ 16 KB stored, ≤ 30 000 bytes per written slot | **Synced** |
| Character overview | `summary` | About page section | none | text | **Synced** |
| Family | Public family members | About page section "Family" | none | one line each | **Synced** |
| Beliefs, motivations, fears | `motivation`, Public belief / motivation / fear facts | About "Beliefs and motivations" (T3: personality) | none | | **Synced** |
| Personality (described) | Public stances, Public trait facts | About "Personality" (T3: personality) | none | | **Synced** |
| Personality values | Public personality axes | Dawnward-owned custom traits in `PS` | none | `V2` = 20 − value (points toward the left trait) | **Synced** (traits) |
| Defining experiences | approved Public defining moments, Public history entries | About "Defining experiences" | none | | **Synced** |
| Other public facts | origin, relationship, event, place, other | About "Chronicle notes" | none | | **Synced** |
| Memories, arcs, goals, places, people, journal | story records | — | — | — | **Never published** (private by design; see PRIVACY.md) |
| Custom axis words | `axisMeanings` | — | — | — | **Not published**: private; traits keep Dawnward's own labels so ownership stays provable |
| Relationships with other players | `story.people` | TRP3 relations (`register.relations`) | none | describe *other* players' profiles | **Unsupported**: TRP3 relations are about other characters' profiles, not the player's own |
| Currently, OOC info | none | `character.CU`, `character.CO` | `SetCurrentlyText`, `SetOutOfCharacterInfo` | | **Unsupported**: a live status the player sets in TRP3; Dawnward has no source |
| RP status | none | `character.RP` | `SetRoleplayStatus` | | **Unsupported** (live status) |
| Icon, class and eye colours, walk-up, RP experience, music | none | `IC`, `CH`, `EH`, `WU`, `MU`, config | some | | **Out of scope**: TRP3 customisation the player keeps |
| Name (one field) | `name` | — | — | | Kept in Dawnward; never split into first and last name (that would be a guess) |

Why the editor path rather than the public setters for Title, Race and Class: Age and Birthplace have no setter, and the five fields are written as **one** backed-up, read-back-verified transaction on the characteristics section, exactly as TRP3's own `saveCharacteristics` does (replace contents, bump `v`, fire `REGISTER_DATA_UPDATED`). The effect for TRP3, MSP and other clients is the same as the setters' `UpdateProfileField`. The setter names are recorded in `FieldPlan.MAPPINGS` (`setter`) for a later switch.

Inferred or game-derived values are never written: every supported source is a field the player typed (or a homeland the player chose), and only when its Dawnward visibility is **Public**.

## Ownership policies

Stored per character **and** linked profile in `DawnwardChroniclesTRP3DB.optIn[character]` (`profileId`, `policy[mapping]`):

| Policy | Meaning | Who sets it |
|---|---|---|
| `dawnward` — Managed by Dawnward | Updated automatically from Public data | Only an explicit authorisation: the page's **Authorize…** confirmation, `trp3 enable about\|traits confirm`, `trp3 field <name> dawnward confirm` |
| `trp3` — Managed by Total RP 3 | Never written; shown in the differences view, importable on request | The default for every field |
| `off` — Not synchronised | Never written, not compared | The default for the biography and traits (that is "sync off") |

- **Migration:** a v0.7 opt-in (`about = true` / `traits = true`) loads as policy `dawnward` for that feature, with no change in behaviour; the booleans are still written so an older build reads the same choice (an older build drops the policies, and every field then falls back to "Managed by Total RP 3").
- **Writes** happen only while the field holds exactly the value Dawnward last wrote, or is empty and has never been written by Dawnward. If Total RP 3 already holds the player's own value, or the player (or another addon) changed Dawnward's value, that field is **paused** (`profiles[id].fieldConflicts`), nothing is overwritten, and the other fields keep updating. A field whose Dawnward value stops being Public is cleared in TRP3 (it was Dawnward's own value).
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
13. **Rollback.** On A, make a fact Secret, then **Exact restore…** shows the fact; cancel. **Roll back…** (safe): B never sees the Secret fact.

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
- **A field Dawnward wrote is cleared** in TRP3 when its Dawnward value stops being Public. If the player had chosen "Use Dawnward's" over their own value, their old value is only in the backup.
- **An exact rollback** of the characteristics section stops managing both traits and fields; the safe rollback keeps the current policies.
- **Homeland maps to TRP3's Birthplace.** If you use Homeland for where your character lives now, keep that mapping on Total RP 3 and type Residence yourself.

## Open questions (to verify in game)

- Does TRP3's open profile page refresh by itself after the update event?
- Does a second client (and an MSP client) receive the update after mouse-over?
- Do profile field writes (`FT`, `RA`, `CL`, `AG`, `BP`) reach other TRP3 and MSP clients exactly like the public setters do (multiplayer procedure, steps 2, 5 and 9)?
- Does the page-context edit-mode check match what TRP3 does in every path (cancel, tab switch, closing the window mid-edit, `/reload` while editing)? Check with `/dawnward trp3 diagnose`.

## The About page (v0.9)

`Integrations/TRP3/AboutDoc.lua` builds the document, `Presentation.lua` styles it, and the plan follows the same ownership rules as before.

**Settings (Settings > Total RP 3 > Overview, or `/dawnward story set …`):**
- **About page** (`trp3About`): **Auto** (the full profile for characters on the profile model, the v0.3 summary block for others), **Profile**, or **Summary**.
- **Template** (`trp3Layout`): **Keep** your Total RP 3 template, or **Text** (1), **Frames** (2), **Sections** (3). Choosing one in Dawnward moves only Dawnward's content (the player's text in the old template is untouched) and switches TRP3's template; switching the template in TRP3 instead is a conflict, never overwritten.
- **Style** (`trp3Style`): Neutral (plain headings), Silver Hand (gold headings, background 2), Arcane (violet headings with section icons).

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

**Icons** are Total RP 3 3.4.1's own interface icons, the entry it uses on older clients (`DirectorySection`, `HistorySection`, `MiscInfoSection`, `PhysicalSection`, `TraitSection`, `TargetNotes`, `ProfileDefault`). **Backgrounds** are indices 1 and 2 of TRP3's tiled background list. Whether each icon and background renders on Classic Era is to be checked in game (L3).

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
