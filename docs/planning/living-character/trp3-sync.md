# TRP3 3.4.1: read/write compatibility matrix and synchronisation feasibility

**Sources:**
- the installed TRP3 **3.4.1** (full audit);
- TRP3 upstream **`main`** (current as of the 3.5.3 release, 2026-10-25): `Core/Player.lua` and `Core/Profiles.lua`, plus the 3.5.0–3.5.3 release notes.

**Project rule:** no writes to undocumented TRP3 tables or SavedVariables. "Public" means the `AddOn_TotalRP3` API, which TRP3's `Init.lua` describes as the "New public API, intended for external use".

Labels: **S** source-confirmed, **G** confirmed in game, **F** feasible but unverified, **X** unsupported under project rules.

## 1. Field-by-field matrix (the player's own active profile)

| Profile field (TRP3 key) | Read | Write | Notes |
|---|---|---|---|
| First / last name (`characteristics.FN/LN`) | `GetFirstName`/`GetLastName` **S** | `SetFirstName`/`SetLastName` **S** | All setters do nothing on the TRP3 **default profile** (except RP status and walk-up) and report no error, so a read-back is required **S** |
| Title (`TI`) | `GetTitle` **S** | `SetTitle` **S** | A good "living" field, such as "Knight-Aspirant" |
| Full title (`FT`) | `GetFullTitle` **S** | `SetFullTitle` **S** | A good "living" field, such as "Defender of Hearthglen" |
| Race / class labels (`RA`/`CL`), class colour (`CH`), icon (`IC`) | getters **S** | setters **S** | Dawnward has no reason to manage these by default |
| **Currently** (`character.CU`) | `GetCurrentlyText` **S** | **`SetCurrentlyText`** **S** | **The best living-narrative field**: shown in tooltips and sent to other players. No length limit in 3.4.1 source **S**; tooltips crop long text (3.5.0 notes), so Dawnward keeps it to ~140 characters **F** |
| OOC info (`character.CO`) | Copy of `CurrentUser:GetProfile()` (a public method that returns TRP3's live table) **S** | `SetOutOfCharacterInfo` **S** | Out-of-character, so **not used for narrative** |
| RP status (`RP`), walk-up (`WU`), RP experience | getters **S** | setters **S** | Not narrative; never managed |
| Age, eyes, height, residence, birthplace, relationship status (`AG/EC/HE/RE/BP/RS`) | Copy of `GetCharacteristics()` (public method, live table) **S** | **none** **X** | Imported into Dawnward only |
| Misc fields: pronouns, guild, voice reference, custom fields (`MI`) | `GetMiscFields`, `GetCustomPronouns`… **S** | **none** **X** | — |
| **Personality traits / sliders** (`PS`) | Copy of `GetCharacteristics().PS` **S**; preset names need our own 3.4.1 list | **none** **X** | Only TRP3's own editor writes these |
| **About / biography** (`about`: templates 1–3) | `GetInfo("about")`, deprecated, through the 3.4.1-gated adapter (approved) **S** | **none** **X** | TRP3's editor wipes and recopies the whole section on save, so any outside write would be lost if the editor is open |
| "At first glance" glances (`misc.PE`) | `GetInfo("misc")` (deprecated) **S** | only internal `TRP3_API.register.applyPeekSlot` **X** | — |
| Profile identity | `GetProfileID`, `GetProfileName`, `IsProfileDefault` **S** **G** | — | The default profile's ID changes every login **S** |
| Select an existing profile | — | `CurrentUser:SetProfileID(id)` **S** | Never done without an explicit player action |
| Create / rename / duplicate a profile | — | only internal `TRP3_API.profile.createProfile` etc. **X** | A new profile is created by the player in TRP3 |

**Extension mechanisms:**
- TRP3 has an internal module registry (`TRP3_API.module.registerModule`). It provides lifecycle hooks only, with **no** API for adding a managed section to a profile. **X**
- MSP fields (`msp.my`) are rebuilt by TRP3 from its own profile **S**, so other addons can't publish through them.
- **Result: no supported way exists for a Dawnward-managed section inside the TRP3 profile.**

**Change detection:**
- Profile switch: `REGISTER_PROFILES_LOADED` **S**.
- Edits: `REGISTER_DATA_UPDATED(unitID, profileID, dataType)`, fired by TRP3's own editors for the player **S**.
- Both come through the semi-public `TRP3_Addon` callback registry. They are useful as **hints**; the reliable check is the read-back described below.

**Newer TRP3:** upstream `main` (3.5.3) has **the same setter list** **S**. No 3.5.x release note mentions an API for other addons. 3.5.2 mentions fixes "on Forever" (relevant to the Forever target; unverified for Dawnward).

## 2. What automatic sync can and cannot do

| Goal | Feasibility | How |
|---|---|---|
| Profile reflects the character's **current state** | **Automatic** (S API, F behaviour) | Dawnward manages **Currently**: a short line composed from mood, recent defining decision and active motivation, for example "Determined, after the fall of Stratholme." |
| **Earned titles** | **Automatic** (S / F) | Dawnward manages **Title** and/or **Full title** when the player chose a title-type option or milestone (for example "Champion of the Argent Dawn" at Exalted) |
| Evolving **biography** | **One player action per update** (X for automatic) | Dawnward prepares the updated biography in TRP3 markup, with changes highlighted. The player opens TRP3's About editor and pastes. Dawnward then remembers the version applied. |
| **Personality sliders** | **Player action** (X for automatic) | Dawnward shows "Suggested TRP3 traits: Lawful 15/20…" for the player to set in TRP3's editor |
| A Dawnward section inside the TRP3 profile | **Not possible** (X) | — |
| Fully automatic biography and trait sync | **Only if TRP3 adds a public API** | Upstream proposal (§5) |

This delivers the core experience ("TRP3 reflects that evolution") **automatically for the most visible, most frequently changing fields** (Currently, titles). The deeper biography and traits need **one paste per update**, which Dawnward makes as quick as possible.

**Product requirement (review decision 4):** automatic biography synchronisation stays a **core long-term requirement**. The paste-assisted path is an **interim fallback**. The Writer is built so that a supported TRP3 biography or trait API (§5) can be added as one more capability-gated field writer, without changing the sync design.

## 3. Synchronisation policy

- **Categories:** milestones, mood and Currently, titles, personality developments, relationships, beliefs and motivations, biography sections. Each is set to **Never** (default), **Ask** or **Automatic**.
- **Informed authorisation:** when a category is **Automatic**, story-prompt options whose result would publish show a small **"Public"** badge. Choosing that option *is* the approval to publish its result (as specified). Without the badge, nothing publishes.
- **Never published:** anything **private** or **secret**, anything from **simulation mode**, interpretations not yet approved.
- **Managed fields:** the player chooses which TRP3 fields Dawnward may manage. Proposed defaults: Currently off until enabled; title and full title off. **Unmanaged fields are never written.**

## 4. Write safety design (the Writer)

**Before every write:**
1. **Version guard:** the TRP3 version is on the allowlist (3.4.1; 3.5.3 only after audit and an in-game test).
2. **Profile guard:** the active profile ID equals the linked ID and isn't the default; otherwise sync pauses and the player is told once.
3. **State guard:** not in combat, not in simulation, and the setter exists and is a function.

**Each write (compare-and-set):**
1. Read the current field value.
2. If the ledger has a `lastWritten` value and the current value **differs**, the player edited it in TRP3. Mark a **conflict**, stop managing that field, and ask: *keep yours* (stays unmanaged) or *let Dawnward manage it again*.
3. Otherwise record a **pending intent**, call the public setter, **read back** and compare. On success, update `lastWritten`; on a mismatch, mark it failed and retry later. After repeated failures, disable the field and tell the player.

**Safety net:**
- **Backups:** before Dawnward first manages a field, its previous value is saved. **Release** restores it through the same setter.
- **Recovery:** at login, pending intents are re-checked against TRP3's current values. Nothing is applied twice, and nothing is applied to another profile.
- **Duplicates and conflicts:** desired values are computed from state (idempotent), not appended. If the desired value equals the current one, nothing is written.

**Without TRP3:** everything else works. Composed Currently text and titles appear in Dawnward with a **Copy** button.

## 5. Supported alternative worth pursuing: upstream API proposal
TRP3 is open source (Apache-2.0) and actively maintained. A small public API would make biography and trait sync supported:

- **`CurrentUser:SetAboutText(text)`** (template 1 only), or better, **registered external sections**: an addon registers a named section; TRP3 owns placement and rendering, and the player can hide it.
- **`CurrentUser:SetPersonalityTraits(list)`.**
- **An "edit in progress" check**, so outside writes never collide with TRP3's editor.

**This is an outward-facing action** (opening an issue or discussion in TRP3's repository) and **needs your explicit approval**. Until such an API exists, Dawnward uses the paste-assisted path for those fields.

## 6. Rejected alternatives
| Alternative | Why rejected |
|---|---|
| Writing `about` / `PS` tables directly and firing TRP3's update event | Undocumented internals; ruled out by project rules (it was "Tier C research" only) |
| Generating TRP3's profile export string for import | An internal format (compression plus a binary encoding); importing creates a *new* profile, not an update |
| Publishing through MSP fields | TRP3 rebuilds `msp.my` from its own profile and would overwrite them |
