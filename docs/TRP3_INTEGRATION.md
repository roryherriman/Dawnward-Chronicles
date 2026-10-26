# Total RP 3 integration

**Status (v0.3.0-dev):** read-only status (tested in game, v0.1/v0.2), plus **experimental automatic sync** of a Dawnward-owned biography section and Dawnward-owned personality traits.

The sync is **built and tested against mocks only (L2)**:
- It is **off by default**. Each character has to opt in with `/dawnward trp3 enable about|traits confirm`.
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
- Callback argument positions differ between TRP3's own listeners and its comments. **Dawnward treats these events as hints only and never reads their arguments.**

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
| `Ledger.lua` | `DawnwardChroniclesTRP3DB`: opt-ins, ownership records, conflicts, backups and log |
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
   - At most 20 backups are kept.
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
| `/dawnward trp3 rollback [#] confirm` | Restores the newest (or a chosen) backup for the **active** profile. It applies the same guards as a write (allowlisted version, not simulation, not combat, editor closed), and refuses another profile's backup. It also undoes any other edits made to that section since the backup. It backs up the current state first (so a rollback can be undone), restores the ownership record saved with the backup (so Dawnward still recognises its own content), and switches sync for that section off. |
| `/dawnward trp3 release about\|traits confirm` | Removes only Dawnward's content and switches sync off |
| `/dawnward trp3 backups`, `/dawnward trp3 log` | Inspect backups and diagnostics |
| `/dawnward trp3 paste` | The manual path: the same section and suggested traits as text to paste into TRP3 yourself (always available, any TRP3 version) |

### Automatic runs
- Runs are requested after login, after any `/dawnward` command, and when TRP3 reports a profile switch or edit.
- Requests are merged into one run 5 s later (`C_Timer.After`).
- A run that has to wait (editor open, combat) retries every 30 s, up to 20 times.
- A persistent state (blocked, conflict) is reported once.

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

## Open questions (to verify in game)

- Does TRP3's open profile page refresh by itself after the update event?
- Does a second client (and an MSP client) receive the update after mouse-over?
- Does the page-context edit-mode check match what TRP3 does in every path (cancel, tab switch, closing the window mid-edit, `/reload` while editing)? Check with `/dawnward trp3 diagnose`.
