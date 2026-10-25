# Total RP 3 integration

Status: **audit and design only, no code.** Findings come from reading the TRP3 **3.4.1** Lua source. They have not been run or tested in game. TRP3 is Apache-2.0 and is not included in this repository.

## Rules

1. TRP3 is an independent addon. Dawnward never modifies its files, never edits SavedVariables on disk, and never patches or replaces TRP3 functions.
2. The public API comes first. Anything outside `AddOn_TotalRP3` is treated as internal and may change without warning. Each internal dependency is listed below with its risk.
3. No write without a capability check, a backup, a read-back check and the player's approval.
4. Only the public projection is used (see [PRIVACY.md](PRIVACY.md)). Private and secret facts can never reach TRP3.
5. A failure in the integration cannot reach the core. See the isolation rule in [ARCHITECTURE.md](ARCHITECTURE.md#saved-data).

## What 3.4.1 offers

### Reading
- `AddOn_TotalRP3.Player.GetCurrentUser()` gives a `CurrentUser` with `GetProfileID`, `GetProfileName`, `IsProfileDefault`, name, title, race, class, icon and colour getters, `GetRoleplayStatus`, `GetCurrentlyText`, `GetMiscFields` and `GetCustomPronouns`.
- `GetProfile()` and `GetCharacteristics()` return **live** SavedVariables tables. Dawnward deep-copies them and never changes them.
- **There is no public reader for the About page or for personality traits.** `GetInfo(path)` can read them, but the source marks it `TODO Deprecate`. → Classed as an *internal read*.

### Writing (public setters)
- **Fields with a setter:** `SetCurrentlyText`, `SetOutOfCharacterInfo`, `SetTitle`, `SetFullTitle`, `SetFirstName`, `SetLastName`, `SetCustomRace`, `SetCustomClass`, `SetCustomClassColor`, `SetCustomIcon`, `SetRoleplayStatus`, `SetWalkup`, `SetRoleplayExperience`.
- On the **default profile**, the setters do nothing and give no error, except for RP status and walk-up. Each setter bumps the section version `v` (it wraps from 99 back to 1) and fires `REGISTER_DATA_UPDATED`, which is how other players and MSP addons learn of the change.
- **No public setter exists for `about` (biography) or `characteristics.PS` (personality traits).**

### Events (semi-public)
These come through the CallbackHandler registry on the global `TRP3_Addon`:

| Event | When it fires |
|---|---|
| `REGISTER_PROFILES_LOADED` | The player switched profile |
| `REGISTER_DATA_UPDATED(unitID, profileID, dataType)` | Profile data changed |
| `REGISTER_PROFILE_DELETED` | A profile was deleted |
| `WORKFLOW_ON_FINISH` | TRP3 has finished starting up |

### Profiles
- **The default profile's ID ends in `*` and is regenerated at every login.** Dawnward never stores it and never writes to it.
- **Profiles can be shared by several characters.** Before the first sync, Dawnward shows which characters share the profile.
- Since 3.4.0, TRP3's own import always creates a *new* profile.

### Data formats (relevant parts)
- **about**
  - `TE` is the template number, 1 to 3.
  - Template 1 is a single text, `T1.TX`.
  - Template 2 is a list of frames, `T2[i] = {TX, IC, BK}`.
  - Template 3 is `T3.PH/PS/HI = {TX, IC, BK}` (physical, psychological, history).
  - Section version is `v`. Text uses TRP3 tag markup such as `{h1}` and `{col:rrggbb}`.
- **characteristics.PS** is a list of traits.
  - A preset trait is `{ID, V2}`.
  - A custom trait is `{LT, RT, V2, LI, RI, LC, RC}`, where `V2` runs 0 to 20 (default 10).
- **Size:** TRP3 sets no text limit, but large profiles are slow for other players to receive. Dawnward caps its generated biography block at 4,000 characters, which is our own policy.

## Sync tiers

| Tier | What it does | Planned for | Default |
|---|---|---|---|
| 0 | Detect TRP3, read through the public API, preview what would change | v0.1 | On |
| A | Public setters for Currently, OOC, Title and Full title, with field backup and rollback | v0.5 | Off (opt-in) |
| B | Copy-and-paste: Dawnward builds biography and trait text in TRP3 markup, and the player pastes it into TRP3's own editor | v0.5 | **Always available. The supported path for biography and personality.** |
| C | Version-specific direct write of Dawnward-owned biography and trait content | **Research.** Long-term goal. | Off. Needs separate approval. |

### Current limitation (documented for players)
> Total RP 3 has no supported way for another addon to change your About page or personality traits. Until a safe, version-checked method has been tested, Dawnward gives you the text to paste in yourself.

## Research: a version-specific adapter for fields with no public setter (Tier C)

Automatic biography and personality sync is a **long-term goal**. The design below is research only. It is not implemented, and it will only be built after Tiers A and B are verified in game and you have signed off on the risks.

### 1. Version profiles, not version guessing
Each TRP3 version gets its own adapter profile, kept in `Integrations/TRP3/VersionProfiles.lua`:

```lua
-- illustrative only
["3.4.1"] = {
	audited = true,               -- source has been read
	verified = nil,               -- "L3" / "L4" once tested in game
	tiers = { read = true, publicSetters = true, manualExport = true, ownedWrite = false },
}
```

- The version is read with the client's `GetAddOnMetadata("totalRP3", "Version")` (or `C_AddOns.GetAddOnMetadata`), not from TRP3 internals.
- A version that isn't listed gets Tier 0 and Tier B only.
- `ownedWrite` is switched on per version, only after that version's source has been audited and tested in game.
- **3.4.1 and 3.5.3 are both design targets. Only versions that have been audited and tested ever get `ownedWrite = true`.**

### 2. Capability checks run each time, before every write
A write is refused, with the reason shown, unless **all** of these hold:

- The TRP3 version profile allows `ownedWrite`, and the expected functions and tables exist with the expected types.
- TRP3 has finished starting up (`WORKFLOW_ON_FINISH` has fired).
- The player is not in combat.
- The active profile ID equals the bound profile ID, and it is not the default profile.
- **TRP3's main window is closed**, so its editor cannot be holding a draft that would overwrite our change. Checking that the frame is hidden avoids relying on the internal `isEditMode` flag.
- The player has seen a preview showing the change, with removed and added text, and confirmed it.

### 3. Ownership without visible markers
Dawnward never changes text it didn't write. Visible markers in the text would show up for other players, so ownership is tracked in `DawnwardChroniclesTRP3DB` instead:

| Template | What Dawnward owns | How it's identified |
|---|---|---|
| T2 (frames) | One whole frame that Dawnward added | The exact `TX` text matches the ledger's record of what was last written |
| T1, or T3 history (`HI`) | One trailing block that Dawnward appended | An exact suffix match against the last-written block |
| Traits (`PS`) | Custom traits that Dawnward added | Exact `LT`/`RT` pair from the ledger |

If the owned content can't be found **exactly** (because the player edited it), Dawnward stops and asks. The edited content then belongs to the player. Dawnward never changes the player's template choice (`TE`), never touches preset traits or traits the player created, and never deletes anything it doesn't own.

### 4. Transaction
1. Deep-copy the affected section into a backup in `DawnwardChroniclesTRP3DB`, keeping at most N per profile.
2. Apply only the owned-content change to TRP3's in-memory section.
3. Bump the section's `v` with TRP3's rule (+1, wrapping 99 → 1), then fire `REGISTER_DATA_UPDATED(player_id, profileID, "about" or "characteristics")`. This copies what TRP3's own editor does when it saves, so it is a documented internal dependency.
4. Read the section back and compare. If anything outside the owned content differs, restore the backup at once and turn Tier C off.
5. Keep the backup as the rollback point (`/dawnward trp3 rollback`).

### 5. Internal dependencies and their risk

| Dependency | Why it's needed | Risk if TRP3 changes |
|---|---|---|
| `GetInfo("about")`, `GetInfo("characteristics")` (deprecated) | No public reader for these sections | The reader disappears → Tier C turns itself off |
| Section shape (`TE/T1/T2/T3`, `PS` fields) | To find owned content | A Flyway migration reshapes the data → the version profile blocks the write |
| The `v` bump rule and the `REGISTER_DATA_UPDATED` event | So other players see the change | The change stays local → caught by an L3 check with a second client |
| `TRP3_Addon:TriggerEvent` | Firing the update event | A signature change → caught by the capability check |

### 6. Before enabling Tier C for any version (3.4.1 or 3.5.3)
- [ ] Audit that version's source: `Core/Player.lua`, `Core/Profiles.lua`, `RegisterAbout.lua`, `RegisterCharacteristics.lua`, `RegisterExchange.lua`, the MSP bridge, and the Flyway patches.
- [ ] Build an L2 fake that matches that version's data shapes and behaviour, then test the ownership, transaction and rollback paths.
- [ ] L3/L4 in game: TRP3's own page shows the change after the write, and opening and saving TRP3's editor afterwards keeps the change.
- [ ] L3/L4 with a second client: another player receives the update, and MSP addons see it.
- [ ] L3/L4: the write is refused while the editor is open, while in combat, and on the default profile.
- [ ] You review and approve the results.

## Open questions (to verify in game)
- Does Classic Era expose `C_AddOns.GetAddOnMetadata`, `GetAddOnMetadata`, or both?
- Does TRP3's open profile page refresh by itself when the update event fires for the player?
- Does TRP3 3.5.3 support the Forever client, and does Forever have `C_EncodingUtil` (which TRP3 3.4.1 needs for its own import and export)?
