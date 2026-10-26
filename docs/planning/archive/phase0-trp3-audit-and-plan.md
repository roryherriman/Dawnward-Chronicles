> **Archived.** The Phase 0 Total RP 3 audit, kept for history. Current findings are in [`../../TRP3_INTEGRATION.md`](../../TRP3_INTEGRATION.md).

# Dawnward Chronicles: Phase 0 Audit and Plan

Status: **approved (Phase 0)**. The decisions are recorded in §12. No addon code has been written yet.

| Evidence level | Meaning in this document |
|---|---|
| **Source-read** | I read it in the installed TRP3 3.4.1 Lua source. It has not been run. |
| **Inferred** | Follows from the source or from another file, but nothing has confirmed it. |
| **Unverified** | An assumption. It has to be tested in a real client. |

Nothing in this document is **in-game verified**.

---

## 1. Scope of the audit

- Input: `AddOns.zip` from `_classic_era_\Interface`. It was extracted to a temporary scratch folder outside the project and will not be committed or redistributed.
- Addons in the archive: `totalRP3`, `totalRP3_Data`, and RaiderIO (not relevant here).
- TRP3 version: **3.4.1** (from the TOC and `Init.lua`). Licence: Apache-2.0.
- TOC `## Interface: 120100, 11509, 20506, 50504`. **11509 (Classic Era) is listed.**
- SavedVariables owned by TRP3: `TRP3_Profiles`, `TRP3_Characters`, `TRP3_Configuration`, `TRP3_Register` (in `totalRP3_Data`, which loads on demand), and others.

### Forever note (inferred)
The WoW Forever client is believed to use interface `16001`, based on an earlier project's TOC; this has not been confirmed. TRP3 3.4.1 does not list 16001, so on Forever 3.4.1 would load as "out of date" at best. Whether TRP3 3.5.3 supports Forever is **unverified**. TRP3 3.4.1 also calls `C_EncodingUtil` (CBOR serialisation and compression) for profile import and export. Whether the Forever client has that API is **unverified**.

---

## 2. TRP3 public read API (source-read)

`Init.lua` declares the global `AddOn_TotalRP3` as the "New public API, intended for external use". It is the only surface TRP3 itself calls public.

**`AddOn_TotalRP3.Player.GetCurrentUser()`** returns the player as a `CurrentUser` object:

| Method | Returns |
|---|---|
| `GetProfileID()`, `GetProfileName()`, `IsProfileDefault()` | Active profile identity |
| `GetFirstName()`, `GetLastName()`, `GetFullName()`, `GetRoleplayingName()` | `characteristics.FN/LN` |
| `GetTitle()`, `GetFullTitle()`, `GetCustomRace()`, `GetCustomClass()`, `GetCustomIcon()`, `GetCustomColor()` | `TI`, `FT`, `RA`, `CL`, `IC`, `CH` |
| `GetRoleplayStatus()`, `GetCurrentlyText()`, `GetWalkup()` | `character.RP/CU/WU` |
| `GetMiscFields()`, `GetCustomPronouns()`, `GetCustomGuildMembership()` | `characteristics.MI` |
| `GetCharacteristics()`, `GetProfile()` | **Live references** into TRP3's SavedVariables |
| `GetInfo(path)` | Generic path read. Marked in source as `TODO Deprecate`. |

Other public tables include `AddOn_TotalRP3.Enums` (ROLEPLAY_STATUS, WALKUP, RELATIONSHIP_STATUS and others), `.MSP`, `.Directory` and `.Communications`.

**Risk:** `GetProfile()` and `GetCharacteristics()` return TRP3's own tables, not copies. Changing anything inside them is a direct SavedVariables write. The adapter will deep-copy everything it reads.

**Gaps:** the public API has **no reader for the About page (biography)** or for personality traits (`characteristics.PS`). Reading them needs `GetInfo("about")` (deprecated) or the live table. The adapter will use that read-only path, behind a capability check, and document it as unstable.

---

## 3. Supported modification interfaces (source-read)

`CurrentUser` has these setters:

`SetRoleplayStatus`, `SetOutOfCharacterInfo` (CO), `SetCurrentlyText` (CU), `SetWalkup`, `SetFirstName`, `SetLastName`, `SetCustomIcon`, `SetTitle`, `SetFullTitle`, `SetCustomClass`, `SetCustomClassColor`, `SetCustomRace`, `SetRoleplayExperience`, `SetProfileID`.

Behaviour of every field setter (`UpdateProfileField`):

1. **It does nothing on the default profile**, except for RP status and walk-up. It reports no error and returns no value, so the adapter must check `IsProfileDefault()` first and confirm the write with a read-back.
2. It does nothing when the value is unchanged.
3. It increments the section version `v` (wraps from 99 to 1) and fires `REGISTER_DATA_UPDATED`. That is what makes other players and MSP addons see the change.

### No public write path for biography or personality
Nothing in the public API writes `player.about` (biography templates) or `characteristics.PS` (personality traits). Only TRP3's own editor writes them. Its save step **wipes the section table and copies its draft back over it**, increments `v`, and fires the event.

**Conclusion:** syncing biography and personality cannot use a supported interface in 3.4.1. So, as your brief asks:

- **Default, and the only option in v0.x:** a manual copy-and-paste export. Dawnward produces the text and the player pastes it into TRP3's own editor.
- **Public setters** for the small fields that have one: Currently, OOC info, Title and Full title. These are opt-in.
- **Direct biography or trait writes** are a possible later experimental feature, off by default, and only with your separate approval. See §7, Tier C.

---

## 4. Change notifications and synchronisation (source-read)

TRP3 events go through a CallbackHandler registry on the global `TRP3_Addon`. You subscribe with `TRP3_Addon.RegisterCallback(owner, event, handler)` or `TRP3_API.RegisterCallback(TRP3_Addon, event, fn)`. These sit outside `AddOn_TotalRP3`, so I class them as **semi-public**: they are used widely but not declared external.

| Event | Arguments | Use for Dawnward |
|---|---|---|
| `REGISTER_PROFILES_LOADED` | profile table | Profile switched. Re-check the binding. |
| `REGISTER_DATA_UPDATED` | unitID, profileID, dataType (`characteristics`/`about`/`misc`/`character`/nil) | Detect edits made by the player or by other addons |
| `REGISTER_PROFILE_DELETED` | profileID | Remove the binding |
| `ROLEPLAY_STATUS_CHANGED` | status | Optional: hold story popups while the player is OOC |
| `WORKFLOW_ON_LOADED` / `WORKFLOW_ON_FINISH` | none | TRP3 has finished starting up. Do not read before this. |

**How changes reach other players:** TRP3 sends a "vernum" query that carries each section's `v`. Other clients request a section again only when its `v` has changed. A direct write that does not bump `v` is invisible to everyone else. The MSP bridge rebuilds its `DE`/`HI`/`PS` fields from `about` and `characteristics`.

**Editor clobber risk:** while TRP3's About or Characteristics editor is open (`context.isEditMode`), it holds a draft copy. Saving the draft overwrites the whole section. Any write made while the editor is open would be lost silently.

---

## 5. Field formats and size constraints (source-read)

**characteristics:** `v`, `FN`, `LN`, `TI`, `FT`, `RA`, `CL`, `CH` (6-digit hex), `IC` (icon name), `AG`, `EC`, `HE`, `RE`, `BP`, `RS`, `MI`, `PS`.

- `MI` (misc) is an array of `{ ID, NA, VA, IC }`.
- `PS` (personality traits) is an array. A preset trait is `{ ID, V2 }`. A custom trait is `{ LT, RT, V2, LI?, RI?, LC?, RC? }`, where `V2` runs 0 to 20 (default 10) and `LC`/`RC` are `{r,g,b}`.

**about:** `v`, `TE` (template 1, 2 or 3), `BK`, `MU`.

- `T1.TX` is one free-text body.
- `T2` is an array of frames `{ TX, IC, BK }`.
- `T3` has `PH`/`PS`/`HI` (physical, psychological, history), each `{ TX, IC, BK }`.
- Text uses TRP3 tag markup such as `{h1}`, `{col:xxxxxx}` and `{/col}`.

**character:** `RP`, `CU` (Currently), `CO` (OOC), `WU`.

**Sanitisation:** TRP3 sanitises incoming single-line fields (`RA, CL, FN, LN, FT, TI, EC, AG, HE, RE, BP` and trait text). It strips `|` escape codes and newlines. The default profile is reduced to `v, RA, CL, FN, IC`.

**Size:** TRP3 sets **no character limit** on About text (`letters="0"`). The practical limit is transfer cost: broadcast messages are capped at 254 bytes and larger data is split by Chomp, so a very large About is slow for other players to receive. Dawnward will set its own budget for generated text (proposed: biography block ≤ 4,000 characters, trait labels ≤ 30, Currently ≤ 200). These numbers are **our policy, not TRP3 limits**.

---

## 6. Profile identification and switching (source-read)

- Profile IDs are random strings. `TRP3_Characters[Name-Realm].profileID` links a character to a profile.
- **The default profile's ID ends in `*` and is regenerated at every login.** Dawnward must never store it and never write to the default profile.
- **One profile can be shared by several characters.** A write to that profile shows on every linked character.
- Switching profile fires `REGISTER_PROFILES_LOADED`, then `REGISTER_DATA_UPDATED`.
- Since 3.4.0, TRP3's import creates a **new** profile instead of overwriting one. The export format is PEM with CBOR and compression, and it is internal. Dawnward will not generate or parse it.

**Binding rule:** each Dawnward character is bound to one TRP3 profile ID by explicit player choice. Before any TRP3 action, the adapter checks that the active profile ID matches the binding and is not the default. If either check fails, it does nothing and tells the player why.

---

## 7. Risks of direct SavedVariables modification

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | TRP3's own source says `TRP3_Profiles` "shouldn't be used outside this file". There is no stability guarantee. | High | Use public setters only. Direct writes are Tier C, opt-in, gated to tested TRP3 versions. |
| R2 | Edits to the `.lua` SavedVariables file on disk are overwritten at logout, and editing it is a write to client files. | High | **Never edit files on disk.** All writes happen in memory through the running addons. |
| R3 | An open TRP3 editor overwrites our write when it saves. | High | Refuse to write while either editor is open. Read back afterwards to confirm. |
| R4 | A write without a `v` bump never reaches other players. A write with a manual bump depends on internal behaviour. | Medium | Public setters bump `v` for us. Tier C would have to copy the internal behaviour, which is documented as a risk. |
| R5 | The default profile is regenerated at login, and setters silently do nothing on it. | Medium | Binding rule (§6) and read-back check. |
| R6 | A shared profile spreads a change to other characters. | Medium | Show the linked characters before the first sync. |
| R7 | Flyway migrations (for example trait `VA`→`V2`) can reshape data between TRP3 versions. | Medium | Allowlist of tested TRP3 versions. Unknown versions fall back to read-only and manual export. |
| R8 | Overwriting text the player wrote themselves. | High | Dawnward only ever touches a block it owns, and never text outside it. Backup before writing, with one-command rollback. |
| R9 | Private facts leaking into a public profile. | High | Every fact has a visibility: `public`, `private` or `secret`. Only `public` can reach TRP3 or a shareable export. |
| R10 | Forever API differences (`C_EncodingUtil`, events, interface number). | Unknown | Forever adapter stays separate, provisional and disabled until a Forever client has been tested. |

### Sync tiers

| Tier | Mechanism | Status |
|---|---|---|
| 0 | Detect TRP3, read through the public API, show what would change | v0.1 |
| A | Public setters (Currently, OOC, Title, Full title), with field backup and rollback | v0.5, opt-in |
| B | Manual copy-and-paste of biography and traits in TRP3's own formatting | v0.5, **default** for biography and personality |
| C | Direct in-memory write to an owned About frame or block and to owned traits | Not planned for v0.x. Needs your explicit approval after Tier A and B have been tested in game. |

---

## 8. Repository architecture

```
Dawnward-Chronicles/
  DawnwardChronicles/                  ← the installable addon folder
    DawnwardChronicles.toc             Classic Era only for now (Interface 11509 + build check)
    Core/                              Pure Lua 5.1. No WoW globals, so it can be unit-tested.
      Namespace.lua  Util.lua  Log.lua
      Schema.lua  Migrations.lua       Versioned SavedVariables and upgrade steps
      Character.lua  Family.lua        Universal character model (any race, class or background)
      Journal.lua                      Capped ring buffer of observed events
      Story.lua                        Decision nodes. Content is data, not code.
      Personality.lua                  Traits, proposals and the approval ledger
      Privacy.lua                      Visibility model and redaction
      Serializer.lua                   Dawnward's own export/import format with a checksum
    Platform/                          The only layer that calls WoW APIs
      Detect.lua                       Project ID, build and interface detection
      ClassicEra.lua                   Classic Era adapter
      Forever.lua                      Provisional stub, disabled until tested
      Events.lua  CombatQueue.lua      Event-driven dispatch, deferral during combat
    Integrations/TRP3/                 Separate adapter. Never touches TRP3 files.
      Capabilities.lua  Reader.lua  PublicWriter.lua  Backup.lua  ManualExport.lua
    UI/                                Popup, journal, copy box and options frames
    Locales/enUS.lua
    Content/Examples/                  Optional example story packs (data only)
  tests/                               Unit tests, a WoW API mock and a TRP3 public API fake. Not shipped.
  tools/                               Lint, test and package scripts
  docs/                                ARCHITECTURE, COMPATIBILITY, TESTING, TRP3_INTEGRATION, PRIVACY
  .github/                             Issue templates, PR template, CI workflow (lint and tests)
  README.md  LICENSE (MIT)  THIRD_PARTY_NOTICES.md  CHANGELOG.md  CONTRIBUTING.md
```

**Dependency rule:** `Core` depends on nothing. `Platform` and `Integrations` depend on `Core`. `UI` depends on all three. Nothing depends on TRP3 being installed.

**SavedVariables:**

- `DawnwardChroniclesDB` is account-wide, keyed by `Name-Realm`, and holds `schemaVersion`.
- `DawnwardChroniclesSimDB` is a **separate variable for simulation mode**, so test data cannot mix with real data and can be wiped with one command.
- `DawnwardChroniclesTRP3DB` holds the TRP3 integration's bindings, ledger and backups, kept apart so integration problems cannot corrupt the journal. This was added after approval; see `docs/ARCHITECTURE.md`.

**Growth limits (proposed defaults):**

- Journal: 500 entries per character (hard cap 2,000), oldest summarised first.
- TRP3 backups: 5 per profile.
- Pending popups: 20.
- Text fields: capped.

**Libraries:** none bundled in v0.1. Fewer licences to track and less to load. If a library is added later (LibStub or similar), its licence goes in `THIRD_PARTY_NOTICES.md`.

### Safety rules mapped to design

| Requirement | Where it is enforced |
|---|---|
| No automatic personality changes | `Personality.lua` only applies changes from the approval ledger. A proposal is inert until the player accepts it. |
| No fabricated gameplay events | Journal entries are created only by `Platform/Events` handlers and record their source event. Story text can only reference journal entries that exist. Simulation entries live in the separate SimDB. |
| No disclosure of secrets | `Privacy.lua` redacts before any TRP3 output or shareable export. Tests check that `secret` facts never appear in output. |
| No destructive TRP3 changes | Public setters only. Owned fields only. Backup → write → read-back → keep a rollback point. |
| Popups queued during combat | `CombatQueue` checks `InCombatLockdown()` and `PLAYER_REGEN_ENABLED`, and holds popups during cinematics, while dead and in the taxi map. |
| No polling | Event handlers only. No `OnUpdate` loops except short animations. |

---

## 9. Testing levels

Every claim in the changelog and in `docs/COMPATIBILITY.md` will name its level.

| Level | What it proves | Tool |
|---|---|---|
| L0 Static | The code parses and has no undefined globals | luacheck (`std = lua51` plus the WoW globals we use) |
| L1 Unit | Core logic is correct | busted on **Lua 5.1/LuaJIT**, the same language version as WoW |
| L2 Mocked integration | Adapters behave correctly against a WoW mock and a fake of TRP3's public API | busted |
| L3 In-game, Classic Era | The addon loads, events fire, and TRP3 interop works | Manual checklist in `docs/TESTING.md`, filled in by you, with results recorded |
| L4 In-game, Forever | The same on WoW Forever 1.60.1 | Later phase |

Tests must run on Lua 5.1, the WoW client's language. A 5.3 VM accepts syntax and library calls that fail in the client. (Resolved: see §12.)

---

## 10. Development workflow and versioning

- **SemVer** while pre-1.0: `0.MINOR.PATCH`. Each milestone is a minor version. Tags are `vX.Y.Z`. `CHANGELOG.md` follows Keep a Changelog, and each entry says what was tested and at which level.
- `main` stays releasable. Work happens on `feat/…` or `fix/…` branches and merges by PR once CI (lint and L1/L2 tests) passes. Commits are small.
- Release zips are built by `tools/package` from `DawnwardChronicles/` only, so tests and docs never ship.
- `.gitignore` excludes: `AddOns.zip`, any third-party addon folder, `*.bak`, local SavedVariables, `review/`, `.env` and editor files.

---

## 11. Phased plan

Each phase ends at a **review checkpoint**. I stop there and wait for your approval.

| Phase | Version | Contents | Checkpoint |
|---|---|---|---|
| **0** | none | This audit and plan | **Now: approve the plan** |
| 1 | none | Local git repo, docs, MIT licence, notices, changelog, contributing guide, issue templates, CI, gitignore | Show the exact file list and the `gh repo create` command → you approve → publish. Then the profile README diff → you approve → publish. |
| 2 | **v0.1** | TOC, namespace, platform detection, versioned SavedVariables with migrations, universal character and family-history model, `/dawnward` slash command (show and edit the profile), export and import of Dawnward data, simulation mode (SimDB), read-only TRP3 detection and status | L0–L2 green → **you install it and run the L3 checklist on Classic Era** → tag v0.1.0 |
| 3 | v0.2 | Milestone journal: level, quest turn-in, first zone visit, death, boss kills. Each event is checked in Classic Era. Capped. | L3 checklist |
| 4 | v0.3 | Decision popups, story-pack data format, combat and unsafe-state queue | L3 checklist |
| 5 | v0.4 | Personality proposals, the approval ledger and its history | L3 checklist |
| 6 | v0.5 | TRP3 Tier A (public setters, opt-in) and Tier B (manual copy). Backup and rollback. | **Before the first TRP3 write: show the exact fields and values** |
| 7 | later | Tier C proposal, only if you want it, with a separate risk sign-off | Explicit approval |
| 8 | later | Forever adapter and TRP3 3.5.3 audit, once a Forever client and that TRP3 version are available | L4 |

v0.1 deliberately does **not** include journal automation, popups, personality changes or any TRP3 write.

### Kyssarra
Kyssarra Dawnward is the first **test character**, entered as data through the same UI any player would use. Nothing about her is hardcoded, and her detailed backstory stays in the git-ignored `private/` folder.

---

## 12. Decisions (recorded)

1. **Plan:** approved.
2. **Test toolchain:** Lua 5.1 tooling approved and kept out of the addon distribution.
   - Installed: PUC Lua 5.1 through lupa, and luacheck 1.2.0, both in `.tooling/`.
   - busted was dropped because its C dependencies need a compiler. A small dependency-free harness replaces it.
3. **GitHub account:** `roryherriman`. Authentication and ownership are checked again before publishing.
4. **Kyssarra:** her detailed backstory is private development data. The addon supports any character.
5. **Pathwarden:** On Hold, described as an earlier experiment that taught lessons about scope, compatibility and testing.
6. **Additional requirements:**
   - Automatic TRP3 biography and personality sync stays a long-term goal. The research is in `docs/TRP3_INTEGRATION.md`; no unsupported writes yet.
   - TRP3 integration is isolated, with its own SavedVariable and only the public projection.
   - 3.4.1 and 3.5.3 are both design targets. Compatibility is claimed only after testing.
