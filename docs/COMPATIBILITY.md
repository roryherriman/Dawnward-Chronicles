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
| WoW Classic Era 1.15.9 | The TOC says `11509`. The number from `GetBuildInfo()` has not been reported yet. | Primary development client | **L3**: the v0.2 acceptance checklist passed all mandatory items (see below and `TESTING.md`) |
| WoW Forever 1.60.1 | Believed to be 16001. **Unverified.** | Final deployment target | — (shown as "provisional", no client-specific features) |

### L3 results: v0.2 acceptance, Classic Era 1.15.9, 2026-10-25

Addon code `f973931`. **All 24 mandatory checklist items pass**:

- loading and the v1→v2 data upgrade;
- journal create, edit and delete;
- character fields and privacy;
- simulated level-up isolation, and a **real level-up**;
- backup, import and undo, and checksum rejection;
- share-export privacy;
- theme persistence;
- coexisting with TRP3 read-only, and TRP3 left unchanged;
- game dialogs above the journal, and no errors in combat.

Optional cosmetic checks (O1–O6, including UI scale) were not reported. The tester reported results by group; details are in `TESTING.md`. The interface number from `GetBuildInfo()` was not reported.

### L3 results: v0.1, Classic Era 1.15.9 (build 70003), Total RP 3 3.4.1, 2026-10-25

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

## Known issues

### KI-1: one-time return to character select after entering the world (v0.2 test session)
- **Status:** Unresolved. **Not reproduced.** **No confirmed connection to Dawnward.** It is **not** fixed.
- **Impact on development:** does **not** block development or the v0.2 merge. It becomes blocking only if it happens again, in which case investigation resumes before further release steps.
- **Seen:** 2026-10-25, Classic Era 1.15.9, Total RP 3 3.4.1, during the first v0.2 session. The game returned to character select about 21 seconds after entering the world (client logs: entered at 02:11:20, returned at 02:11:41). There was no error message, and the next session was stable.
- **What was checked (read-only):**
  - No installed addon (Dawnward, Total RP 3, RaiderIO, including bundled libraries) calls `Logout`, `Quit` or `ForceQuit`.
  - Dawnward sends no network traffic and has no timers or hooks.
  - The v1→v2 data upgrade completed correctly in that session.
  - The client's connection logs were empty.
- **Context:** the client process had been running since before three different Dawnward builds were installed under it. The incident followed a fresh account-level login.
- **If it happens again:** note the time, enable `/chatlog`, and compare runs with Dawnward enabled and disabled from cold client starts. A separate logout-diagnostic addon was proposed but not built.

## Total RP 3

| Version | Source audited | Tier 0 (read) | Tier A (public setters) | Tier B (manual export) | Tier C (owned direct write) |
|---|---|---|---|---|---|
| 3.4.1 | Yes, see [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md) | **L3**: v0.2 acceptance items M20–M22 confirmed the version and active-profile status, coexistence, and TRP3 left unchanged | Not built | Not built | Research only |
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
| `AddOn_TotalRP3.Player.GetCurrentUser()` → `GetProfileName`, `GetRoleplayingName` | TRP3 status (read only) | L3 (`GetProfileName`, from v0.2 M20); `GetRoleplayingName` is L2 only | — |

## Client APIs added in v0.2 (journal window)

**L3 (implied)** means a passed v0.2 acceptance item depends on the API; the item number is given. Anything not exercised by a passed item stays **assumed**.

| API or event | Used for | Classic Era | Forever |
|---|---|---|---|
| `PLAYER_LEVEL_UP` (arg 1 = new level) | Level-up milestones | L3 (M12, real level-up) | — |
| `GetRealZoneText`, `GetSubZoneText` | Zone and subzone on milestones | L3 (implied: M10, M12) | — |
| `date` | Entry dates in the journal | L3 (implied: M3) | — |
| `InputBoxTemplate` EditBox, `EditBox:SetMaxBytes` | Title and field editors | L3 (implied: M3, M7) | — |
| `StaticPopupDialogs` / `StaticPopup_Show` | Delete and reset confirmations | L3 (implied: M6, M9, M11) | — |
| `GameTooltip` | Visibility and settings tooltips | Assumed | — |
| `Frame:SetBackdropBorderColor` | Theme border tint | L3 (implied: M17) | — |
| `MEDIUM` strata with `SetToplevel`/`Raise` | Journal window layering below game dialogs | L3 (implied: M21, M23) | — |
| `SetUserPlaced`, `GetLeft`/`GetTop` | Remembered window position | Assumed (O2 not reported) | — |
| `FontString:GetStringHeight`, `SetWordWrap`, `SetNonSpaceWrap` (optional) | Variable-height journal rows | L3 (implied: M3–M7) | — |
| `Region:SetShown`, `Button:SetEnabled` | Showing and hiding controls | L3 (implied: M5, M17) | — |
| Icon texture `INV_Misc_Gear_01`, `ButtonHilight-Square` | Gear button | L3 (implied: M11, M17) | — |
| Icon texture `INV_Misc_Book_09` | Story empty state | Assumed (not part of a mandatory item) | — |
| `GameFontNormalLarge`, `GameFontHighlight` | Headings and body text | L3 (implied: M2–M7) | — |

## Client APIs added in v0.3 (experimental TRP3 sync)

| API | Used for | Classic Era | Forever |
|---|---|---|---|
| `C_Timer.After` | Merging sync requests and retrying after an open editor or combat | Assumed | — |
| `InCombatLockdown` | No TRP3 writes in combat (also used by the copy window since v0.1) | Assumed | — |

TRP3 internals used by the experimental sync (TRP3 3.4.1 only) are listed with their risks in [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md#internal-dependencies-and-their-risk). The sync is allowlisted for TRP3 3.4.1 by source audit only. It has **not** been tested in game.

## Client APIs added in v0.4 (living chronicle)

Checked against Blizzard's Classic Era interface source for **1.15.9 (70003)** (the `Gethe/wow-ui-source` mirror, branch `classic_era`). **S** = defined in the generated API documentation or called by Blizzard's own Classic Era UI code; nothing below has been verified in game yet.

| API or event | Used for | Source evidence | Classic Era | Forever |
|---|---|---|---|---|
| `QUEST_COMPLETE` | The reward panel opened: cache the quest ID, title and level | `QuestLogDocumentation.lua`; `Classic/QuestFrame.lua` | S, not L3 | — |
| `QUEST_TURNED_IN(questID, xpReward, moneyReward)` | A quest was turned in | `QuestLogDocumentation.lua` (payload) | S, not L3 | — |
| `GetQuestID`, `GetTitleText` | Quest ID and title on the reward panel | `Vanilla/QuestInfo.lua` | S, not L3 | — |
| `GetQuestLogIndexByID`, `GetQuestLogTitle` (2nd return = level) | Quest level, while the quest is still in the log | `Vanilla/QuestLogFrame.lua` | S, not L3 | — |
| `C_QuestLog.GetQuestInfo(questID)` | Title fallback when the reward panel was not seen | `QuestLogDocumentation.lua` | S, not L3 | — |
| `PLAYER_DEAD` | A death (the cause is not recorded) | `DeathInfoDocumentation.lua` | S, not L3 | — |
| `PLAYER_ALIVE`, `PLAYER_UNGHOST`, `PLAYER_REGEN_ENABLED/DISABLED`, `PLAYER_UPDATE_RESTING`, `ZONE_CHANGED_NEW_AREA` | Calm moments to check for a waiting story moment; the card hides when combat starts | generated docs | S, not L3 | — |
| `CINEMATIC_START/STOP`, `LOADING_SCREEN_ENABLED/DISABLED` | Never announce during a cinematic or loading screen | generated docs | S, not L3 | — |
| `UnitLevel`, `UnitClass` (2nd return: class file), `UnitRace` (2nd return: race file), `UnitFactionGroup` | Character context on event records, used only for optional class flavour | `UnitDocumentation.lua`; Classic UI code | S, not L3 | — |
| `UnitIsDeadOrGhost` | No announcements while dead or a ghost | Classic UI code | S, not L3 | — |

| `UPDATE_FACTION`, `GetNumFactions`, `GetFactionInfo(index)` (3rd return: standing 1–8; 14th: faction ID) | Reputation tier changes against a snapshot; the first reading is a silent baseline | `PaperDollInfoDocumentation.lua`; `Vanilla/ReputationFrame.lua` | S, not L3 | — |
| `ZONE_CHANGED_NEW_AREA`, `IsInInstance`, `GetInstanceInfo` | First recorded zone visit; first recorded party/raid instance entry | `MapDocumentation.lua`, `InstanceDocumentation.lua`; Classic UI code | S, not L3 | — |
| `PLAYER_GUILD_UPDATE`, `GetGuildInfo("player")`, `IsInGuild` | Joining or leaving a guild (rank changes only update the snapshot); inconclusive readings at login are ignored | `GuildInfoDocumentation.lua`; `Vanilla/PaperDollFrame.lua`, `Classic/MainMenuBarMicroButtons.lua` | S, not L3 | — |

**Known Classic Era limits for the story engine:**
- There is no "important quest" or story flag; significance comes from verified data only (quest level relative to the character, first quest in a zone, level milestones, first death).
- The quest tag (`GetQuestLogTitle` third return) is localised text, so it is not used.
- Repeatable quests are recorded once per character (the key is the quest ID).
- Achievements exist as an API but are not part of Classic Era play, so they are not used.
- Encounter events (`ENCOUNTER_END`, `BOSS_KILL`) are defined, but whether they fire for Classic dungeon bosses is unverified, so boss detection is not built yet.
- The combat log is not read (cost, and the restriction risk).
- Factions under a collapsed header in the reputation panel are not listed by `GetFactionInfo`; their snapshot simply waits until they are listed again.
- Zone and instance "first visits" are the first ones Dawnward recorded, not necessarily the character's first ever (the client keeps no such history).
- Standing names in story text use English fallbacks for now (localisation is planned).

## Planned APIs (not used yet)

| API or event | Planned for |
|---|---|
| `ENCOUNTER_END` / `BOSS_KILL`, `IsInInstance`, `GetInstanceInfo` | Dungeon and boss moments, after an in-game probe confirms they fire (issue #11) |
