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
| WoW Classic Era | The TOC says `11509` (taken from the TRP3 3.4.1 TOC). Confirm with `GetBuildInfo()` at L3. | Primary development client | L2 (mocked) |
| WoW Forever 1.60.1 | Believed to be 16001. **Unverified.** | Final deployment target | — (shown as "provisional", no client-specific features) |

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
