# Compatibility

This matrix records **observed** results only. Levels are defined in [TESTING.md](TESTING.md).

| Level | Meaning |
|---|---|
| L0 | Static checks |
| L1 | Unit tests |
| L2 | Mocked integration tests |
| L3 | In game, Classic Era |
| L4 | In game, WoW Forever |
| — | Not tested |

## Clients

| Client | Interface | Role | Highest level reached |
|---|---|---|---|
| WoW Classic Era 1.15.9 | The TOC says `11509`. Not yet confirmed with `GetBuildInfo()`. | Primary development client | L3, partial (see below) |
| WoW Forever 1.60.1 | Believed to be 16001. **Unverified.** | Final deployment target | — (shown as "provisional", no client-specific features) |

### L3 results: Classic Era 1.15.9 (build 70003), Total RP 3 3.4.1, 2026-10-25

Test build `1fdb724`. The client build was read from the installed `.build.info`.

**Confirmed in game:**
- History entries: creating, editing and privacy labels
- Data kept through `/reload` and a full logout and login
- Backup export
- Backup import and restore, then undo and redo
- Corrupted backup rejected by the checksum
- Simulation mode keeps its data separate, and reset works
- Total RP 3 Default profile detected

**Found:** the export/import window was hard to read over Total RP 3. It is fixed in `15dbae1` and still needs re-testing.

**Not yet reported:**
- the interface number from `GetBuildInfo()`
- whether the AddOns list marks the addon "out of date"
- family member commands
- detection of a non-default Total RP 3 profile name
- the combat check

v0.1 uses no client-specific gameplay APIs, so the same code runs on any client that has the APIs below. That does **not** make it verified anywhere.

## Total RP 3

| Version | Source audited | Tier 0 (read) | Tier A (public setters) | Tier B (manual export) | Tier C (owned direct write) |
|---|---|---|---|---|---|
| 3.4.1 | Yes, see [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md) | L2 (fake built from the audited source) | Not built | Not built | Research only |
| 3.5.3 | No | Reported as "not audited", status only | — | — | — |
| Any other version | No | Read only, if capability checks pass | Off | — | Off |

Compatibility with 3.5.3 is **not claimed**, and won't be until its source has been audited and it has been tested at L3 or L4.

## Client APIs used in v0.1

Every name below is also in the per-directory lists in `.luacheckrc`. "Assumed" means it's believed to exist on that client but no Dawnward test has confirmed it yet.

| API | Used for | Classic Era | Forever |
|---|---|---|---|
| `GetBuildInfo`, `WOW_PROJECT_ID`, `WOW_PROJECT_CLASSIC` | Client detection | Assumed | — |
| `C_AddOns.GetAddOnMetadata`, with `GetAddOnMetadata` as fallback | Own version, TRP3 version | Assumed (either one) | — |
| `C_AddOns.IsAddOnLoaded`, with `IsAddOnLoaded` as fallback | Whether TRP3 is loaded | Assumed (either one) | — |
| `UnitName`, `GetNormalizedRealmName`, with `GetRealmName` as fallback | Character key `Name-Realm` | Assumed | — |
| `time` | Timestamps | Assumed | — |
| `CreateFrame`, `UIParent`, `DEFAULT_CHAT_FRAME`, `SlashCmdList` | Events, chat, `/dawnward` | Assumed | — |
| `ADDON_LOADED`, `PLAYER_LOGIN` events | Loading saved data and starting up | Assumed | — |
| `BackdropTemplateMixin` / `"BackdropTemplate"` (optional) | Copy window background | Assumed. The window still works without it. | — |
| `UIPanelCloseButton`, `UIPanelScrollFrameTemplate`, `UIPanelButtonTemplate` | Copy window | Assumed | — |
| `ChatFontNormal`, `GameFontNormal`, `GameFontHighlightSmall`, `UISpecialFrames`, `tinsert` | Copy window | Assumed | — |
| `AddOn_TotalRP3.Player.GetCurrentUser()` → `GetProfileName`, `IsProfileDefault`, `GetRoleplayingName` | TRP3 status (read only) | L2 against the 3.4.1 fake | — |

## Planned APIs (not used yet)

| API or event | Planned for |
|---|---|
| `InCombatLockdown`, `PLAYER_REGEN_ENABLED/DISABLED` | Combat queue (v0.3) |
| `PLAYER_LEVEL_UP`, `QUEST_TURNED_IN`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_DEAD`, `ENCOUNTER_END` / `BOSS_KILL` | Journal (v0.2) |
