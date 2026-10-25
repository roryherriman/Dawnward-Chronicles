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

**Found:** the export/import window was hard to read over Total RP 3. It was fixed in `15dbae1`.

### L3 re-test: copy window fix, same client and Total RP 3 version, 2026-10-25

Test build `14669c3`.

**Confirmed in game:**
- No Total RP 3 bleed-through and no overlapping text
- The export and import windows display correctly
- Text stays readable
- Long text and scrolling behave correctly
- No Lua errors during these tests

**Untested (neither passed nor failed):**
- **UI scaling** (checklist step 27). The tester couldn't find a scale option during this session.

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
| 3.4.1 | Yes, see [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md) | L3, partial: the default profile was detected. Profile name and version output weren't reported. Full behaviour is L2. | Not built | Not built | Research only |
| 3.5.3 | No | Reported as "not audited", status only | — | — | — |
| Any other version | No | Read only, if capability checks pass | Off | — | Off |

Compatibility with 3.5.3 is **not claimed**, and won't be until its source has been audited and it has been tested at L3 or L4.

## Client APIs used in v0.1

Every name below is also in the per-directory lists in `.luacheckrc`.

- **"Assumed"** means the API is believed to exist on that client, but no Dawnward test has confirmed it.
- **"L3 (implied)"** means a confirmed in-game result depends on it working, even though the API wasn't checked on its own.

| API | Used for | Classic Era | Forever |
|---|---|---|---|
| `GetBuildInfo`, `WOW_PROJECT_ID`, `WOW_PROJECT_CLASSIC` | Client detection | Assumed (the status line wasn't reported) | — |
| `C_AddOns.GetAddOnMetadata`, with `GetAddOnMetadata` as fallback | Own version, TRP3 version | Assumed (version output wasn't reported) | — |
| `C_AddOns.IsAddOnLoaded`, with `IsAddOnLoaded` as fallback | Whether TRP3 is loaded | L3 (implied: the TRP3 default profile was detected) | — |
| `UnitName`, `GetNormalizedRealmName`, with `GetRealmName` as fallback | Character key `Name-Realm` | L3 (implied: data persisted per character) | — |
| `time` | Timestamps | L3 (implied: no errors when saving) | — |
| `CreateFrame`, `UIParent`, `DEFAULT_CHAT_FRAME`, `SlashCmdList` | Events, chat, `/dawnward` | L3 (implied) | — |
| `ADDON_LOADED`, `PLAYER_LOGIN` events | Loading saved data and starting up | L3 (implied: data persisted through relog) | — |
| `BackdropTemplateMixin` / `"BackdropTemplate"`, `SetColorTexture`, `FULLSCREEN_DIALOG` strata, `SetToplevel`/`Raise` | Copy window border, background and layering | L3 (the window displayed correctly over Total RP 3) | — |
| `UIPanelCloseButton`, `UIPanelScrollFrameTemplate`, `UIPanelButtonTemplate`, multi-line `EditBox` | Copy window | L3 | — |
| `ChatFontNormal`, `GameFontNormal`, `GameFontHighlightSmall`, `UISpecialFrames`, `tinsert` | Copy window | L3 | — |
| `AddOn_TotalRP3.Player.GetCurrentUser()` → `IsProfileDefault` | TRP3 default-profile warning | L3 (TRP3 3.4.1) | — |
| `AddOn_TotalRP3.Player.GetCurrentUser()` → `GetProfileName`, `GetRoleplayingName` | TRP3 status (read only) | L2 against the 3.4.1 fake. The in-game name output wasn't reported. | — |

## Client APIs added in v0.2 (journal window)

All of these are **assumed** until the v0.2 checklist runs in game.

| API or event | Used for | Classic Era | Forever |
|---|---|---|---|
| `PLAYER_LEVEL_UP` (arg 1 = new level) | Level-up milestones | Assumed | — |
| `GetRealZoneText`, `GetSubZoneText` | Zone and subzone on milestones | Assumed | — |
| `date` | Entry dates in the journal | Assumed | — |
| `InputBoxTemplate` EditBox, `EditBox:SetMaxBytes` | Title and field editors | Assumed | — |
| `StaticPopupDialogs` / `StaticPopup_Show` | Delete and reset confirmations | Assumed | — |
| `GameTooltip` | Visibility and settings tooltips | Assumed | — |
| `Frame:SetBackdropBorderColor` | Theme border tint | Assumed | — |
| `MEDIUM` strata with `SetToplevel`, `SetUserPlaced`, `GetLeft`/`GetTop` | Journal window layering and remembered position | Assumed | — |
| `FontString:GetStringHeight`, `SetWordWrap`, `SetNonSpaceWrap` (optional) | Variable-height journal rows | Assumed | — |
| `Region:SetShown`, `Button:SetEnabled` | Showing and hiding controls | Assumed | — |
| Icon textures `INV_Misc_Gear_01`, `INV_Misc_Book_09`; `ButtonHilight-Square` | Gear button, Story empty state | Assumed | — |
| `GameFontNormalLarge`, `GameFontHighlight` | Headings and body text | Assumed | — |

## Planned APIs (not used yet)

| API or event | Planned for |
|---|---|
| `InCombatLockdown`, `PLAYER_REGEN_ENABLED/DISABLED` | Combat queue for story popups (v0.3) |
| `QUEST_TURNED_IN`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_DEAD`, `ENCOUNTER_END` / `BOSS_KILL` | More milestone types (later; each needs a registered type and an L3 check) |
