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

## Kinds of evidence

Not every row below rests on the same kind of check:

- **Source audit (S):** the API or behaviour is confirmed in Blizzard's or TRP3's own source code. This proves the client *knows* the function or event, not that Dawnward uses it correctly in play.
- **Mocked tests (L1/L2):** automated tests against a mocked client or the TRP3 3.4.1 fake.
- **In game (L3/L4):** someone ran it in a real client. Results reported by the owner are marked "owner-reported" and list exactly what was checked.

## Clients

| Client | Interface | Role | Highest level reached |
|---|---|---|---|
| WoW Classic Era 1.15.9 | The TOC says `11509`. The number from `GetBuildInfo()` has not been reported yet. | Primary development client | **L3**: the v0.2 acceptance checklist passed all mandatory items; v0.4 and the origins/places features were partly checked in game on 2026-10-26 (owner-reported, see below) |
| WoW Forever 1.60.1 (70755) | Believed to be 16001. **Unverified.** Project ID 18 (`WOW_PROJECT_CAMELOT`) from the forever UI source | Final deployment target | **L2** mocked only (see [WoW Forever API compatibility](#wow-forever-api-compatibility-1601-build-70755)); shown as "provisional". No runtime pass: Pending Live Forever Verification |

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

### L3 results: v0.4 and origins/places, Classic Era 1.15.9, Total RP 3 3.4.1, 2026-10-26 (owner-reported)

The owner tested the build of PR #9, PR #43 and PR #47 on a Human character in Elwynn Forest, using a disposable TRP3 profile for sync.

| Area | Result |
|---|---|
| Character data persistence across `/reload` | Pass |
| People and relationship records | Pass |
| Stances, privacy and contradiction review | Pass |
| Story arcs: creation, turning points, conclusion, reactivation, persistence | Pass |
| Goals: creation, milestones, achievement, invalid-state validation | Pass |
| Journal entries and memories | Pass |
| TRP3 opt-in sync, editor protection, backup and rollback | Pass |
| Place discovery and first-visit recording | Pass |
| Detection of Elwynn Forest, Northshire Valley, Goldshire and Lion's Pride Inn | Pass |
| Story Director location reactions recorded in the journal | Pass |
| Approved personality development | Pass |
| Meaningful place marking (Goldshire stayed marked after `/reload`) | Pass |
| Character Homeland field (Northshire Valley stayed saved after `/reload`) | Pass. This is the free-text profile field; it does not prove a dedicated Origins system. |

**Observations (not failures):**
- A location reaction that does not appear at once is usually pacing, not a bug: cooldowns, significance and the place's kind decide it. See `/dawnward story events`.
- Location prompts should depend on how relevant a place is to the character, rather than being guaranteed.
- Homeland is free text and is not yet linked to place records.
- Some Chronicle rows let long text overlap their buttons.
- Too many actions need slash commands.

**Not covered by this session:**
- quest-moment cards and combat deferral in play;
- reputation, guild and dungeon events;
- TRP3 presentation styles and defining moments in Dawnward's section;
- multiplayer propagation;
- other races' starting areas;
- localised clients;
- WoW Forever.

## WoW Forever API compatibility (1.60.1, build 70755)

**Pinned sources.** Forever: `Gethe/wow-ui-source` branch `forever`, commit `17ed2c3` "1.60.1 (70755)" (2026-11-03), game type `camelot`. Classic Era: branch `classic_era`, 1.15.9 (70576) generated API documentation, and the 1.15.9 (70003) FrameXML tree. Forever is a modern, Mainline-based client: its add-ons load by `AllowLoadGameType` rules, and `camelot` belongs to the `mainline` family (for example `Blizzard_UIPanels_Game.toc:44` loads `[Family]\CharacterFrame.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]`).

**Evidence levels** (as used below):
- **Static**: the forever-branch source shows it, either in `Blizzard_APIDocumentationGenerated` or in Blizzard Lua/XML that the TOC rules load for `camelot`. The file is named.
- **L2 mocked / automated**: `tests/spec/forever_client_spec.lua` runs the whole addon against a Forever mock that exposes only what the source shows (see below).
- **Pending Live Forever Verification**: needs the game. **No row below has been run in a Forever client.**

**How Dawnward behaves.** Shared code detects features at run time; it never branches on the client ID for an API. `Platform/Compat.lua` uses the Classic Era function when the client has it (so Classic Era behaves exactly as before) and the Forever replacement otherwise. A client with neither gets nothing for that feature: it is skipped, never a Lua error, and named once at login and in `/dawnward status` ("Client APIs not available, so these are skipped: …").

### Inventory (every client API Dawnward uses)

Method: every global read by `Platform/` and `UI/` (luacheck), every `C_*` call, every event registered, every widget method called, the templates, textures, widget types and TOC fields, checked against both trees by script (`Name =`/`LiteralName =` in the generated docs, and definitions and calls in files the TOC rules load for `camelot` or for Classic Era).

| Class | Count | Members |
|---|---|---|
| Present in both, same shape | 44 globals, 7 namespace functions, 30 events, 105 widget methods, 5 widget types, 1 template, 4 more font objects named as strings | below |
| Missing on Forever, replaced | 4 | `GetQuestLogTitle`, `GetNumFactions`, `GetFactionInfo`, `C_QuestLog.GetQuestInfo` |
| Missing on Forever, already only a fallback | 2 | global `GetAddOnMetadata`, global `IsAddOnLoaded` (`C_AddOns` is used first on both clients) |
| Forever-only replacements now used | 6 | `C_QuestLog.GetLogIndexForQuestID`, `C_QuestLog.GetInfo`, `C_QuestLog.GetTitleForQuestID`, `C_Reputation.GetNumFactions`, `C_Reputation.GetFactionDataByIndex`, `issecretvalue` |
| Unknown (no Forever evidence either way) | 1 API + 3 textures | `GetQuestLogIndexByID`; icons `INV_Misc_Book_09`, `INV_Misc_Map_01`, `INV_Misc_Gear_01` |
| Not used by Dawnward | — | CVars, `Settings`/`InterfaceOptions` panels, `UIDropDownMenu`/`Menu`, `LoadAddOn`, `SetBackdrop`, combat log, secure templates |

### Matrix: APIs that differ, or that Dawnward now handles differently

| API | Classic Era 1.15.9 | Forever 1.60.1 (70755) | Evidence (Forever) | Dawnward behaviour |
|---|---|---|---|---|
| `WOW_PROJECT_ID` | 2 (`WOW_PROJECT_CLASSIC`) | 18 (`WOW_PROJECT_CAMELOT`) | Static: `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` | `Platform/Detect.lua` recognises Forever by project 18 **or** interface 16001, labelled "provisional support", `verified = false`. L2. Pending Live Forever Verification |
| `GetBuildInfo()` 4th return | 11509 | believed 16001 | Not in the source (derived from the 1.60.1 version string; TRP3 3.5.4's TOC declares it) | Pending Live Forever Verification: `/dump select(4, GetBuildInfo())` |
| TOC `## X-Dawnward-Target` | — | — | Dawnward's own field (packaging) | `Detect.Target` reads it with `C_AddOns.GetAddOnMetadata`; a target that does not match the client prints one warning at login and a line in `/dawnward status`. Loading continues. L2 |
| `GetQuestLogIndexByID` + `GetQuestLogTitle` (2nd return = level) | present | `GetQuestLogTitle`: absent (no doc, no camelot-loaded caller). `GetQuestLogIndexByID`: unknown (only a fallback behind `C_QuestLog.GetLogIndexForQuestID` in `Blizzard_FrameXML/Mainline/TutorialFrame.lua:25`) | Static | `Compat.QuestLevel`: the Classic pair when both exist, else `C_QuestLog.GetLogIndexForQuestID` + `C_QuestLog.GetInfo(index).level` (`QuestLogDocumentation.lua`, `QuestInfo.level`). Neither: the quest is recorded without a level. L2 |
| `C_QuestLog.GetQuestInfo(questID)` | present | absent | Static (`QuestLogDocumentation.lua` has `GetTitleForQuestID`, not `GetQuestInfo`) | `Compat.QuestTitle`: `GetQuestInfo`, else `C_QuestLog.GetTitleForQuestID` (nilable). L2 |
| `GetNumFactions` + `GetFactionInfo(i)` | present | absent | Static: Forever's own reputation panel (`Blizzard_UIPanels_Game/Camelot/ReputationFrame.lua:165-166`) uses `C_Reputation` | `Compat.ReadFactions`: the Classic pair, else `C_Reputation.GetNumFactions` + `GetFactionDataByIndex` (`.reaction` 1–8 as standing, `.isHeader`, `.isHeaderWithRep`, `.factionID`; `ReputationInfoDocumentation.lua`). Neither: an empty reading, which changes no snapshot and records nothing. L2 |
| `issecretvalue(v)` and secret returns | absent | present (`FrameScriptDocumentation.lua`); `UnitName` is `SecretWhenUnitNameIdentityRestricted`, `UnitClass`/`UnitRace` `SecretWhenUnitIdentityRestricted`, `UnitIsAFK` `SecretInChatMessagingLockdown` (`UnitDocumentation.lua`) | Static | `Compat.Plain`: a secret value reads as nil, so it is never compared, concatenated or saved. On Classic Era it returns the value unchanged. L2 (mock secrets). Whether "player" queries are ever secret: Pending Live Forever Verification |
| global `GetAddOnMetadata`, `IsAddOnLoaded` | absent from docs (fallback only) | absent | Static (`AddOnsDocumentation.lua` documents `C_AddOns` only) | Already `C_AddOns` first (`Compat.AddOnMetadata`, `Integrations/TRP3/Status.lua`). L2 |
| `InCombatLockdown` | present (engine) | present (engine; e.g. `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua:375`) | Static | `Compat.InCombat(ifUnknown)`. Story cards and Total RP 3 writes treat an unknown combat state as combat; the setup launcher does not. L2 |
| `C_Timer.After` | present | present (`UITimerDocumentation.lua`) | Static | `Compat.After` returns false when missing: story checks run at the next calm event, TRP3 writes stay pending. L2 |
| `C_Map.GetBestMapForUnit`, `GetMapInfo`, `GetAreaInfo` | present | present, same signatures (`MapDocumentation.lua`) | Static | Missing functions, errors, non-table or wrongly typed replies read as "unknown". L2 |
| Classic Era uiMap and AreaTable IDs (`Core/Places.lua`, `Core/Atlas.lua`) | source-checked for 1.15.9.70576 | **not checked** | none | Never applied on Forever: `Places.Data("forever")` is nil, so no area resolves, nothing is classified and nothing counts as a starting area. Places are still logged by zone and subzone name with the uiMap ID. `/dawnward atlas` says the Classic data is evidence only. L2. Pending Live Forever Verification (`/dawnward atlas export`) |

### Present in both, same shape (Static for Forever)

- **Events (30), payloads identical in both generated docs:** `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_LOGOUT`, `PLAYER_ENTERING_WORLD`, `PLAYER_LEVEL_UP`, `QUEST_COMPLETE`, `QUEST_TURNED_IN`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST`, `PLAYER_REGEN_ENABLED`, `PLAYER_REGEN_DISABLED`, `PLAYER_UPDATE_RESTING`, `PLAYER_FLAGS_CHANGED`, `PLAYER_GUILD_UPDATE`, `UPDATE_FACTION`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA`, `CINEMATIC_START`, `CINEMATIC_STOP`, `LOADING_SCREEN_ENABLED`, `LOADING_SCREEN_DISABLED`, `ENCOUNTER_START`, `ENCOUNTER_END`, `BOSS_KILL`, `UNIT_MODEL_CHANGED`, `UNIT_PORTRAIT_UPDATE`, `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED`. The modern client rejects unknown events with an error; the Forever mock does too.
- **Documented global functions, same signature:** `GetInstanceInfo`, `IsInInstance`, `GetRealZoneText`, `GetSubZoneText`, `UnitClass`, `UnitName`, `UnitFactionGroup`, `UnitIsAFK`, `GetNormalizedRealmName`, `GetRealmName`, `InCinematic`, `GetCursorPosition`, `SetPortraitTexture`, `IsInGuild`, `GetLocale`; also documented on Forever: `UnitRace`, `UnitLevel`, `UnitIsDeadOrGhost`, `GetTime`, `IsShiftKeyDown`, `GetBuildInfo`.
- **Namespace functions, same signature:** `C_AddOns.GetAddOnMetadata`, `C_AddOns.IsAddOnLoaded`, `C_Map.GetBestMapForUnit`, `C_Map.GetMapInfo`, `C_Map.GetAreaInfo`, `C_Timer.After`, `C_Timer.NewTicker`.
- **Engine globals not in the generated docs, called by camelot-loaded Blizzard code:** `CreateFrame`, `CreateFont` (`Blizzard_SharedXML/FontableFrameMixin.lua:120`), `InCombatLockdown`, `GetQuestID` (`Blizzard_UIPanels_Game/Mainline/QuestInfo.lua:40`), `GetTitleText` (`Mainline/QuestFrame.lua:212`), `GetGuildInfo` (`Blizzard_FrameXML/Mainline/AlertFrameSystems.lua:355`), `date`, `time`, `tinsert`, `SlashCmdList`.
- **FrameXML values:** `UIParent`, `DEFAULT_CHAT_FRAME`, `GameTooltip` (`SetOwner`, `SetText`, `AddLine`, `Show`, `Hide`: `Blizzard_UIPanels_Game/Camelot/CharacterFrame.lua:350`), `Minimap` (`Blizzard_Minimap` loads `[Game]\Minimap.lua` for camelot), `UISpecialFrames`, `RAID_CLASS_COLORS`, `WOW_PROJECT_CLASSIC`, fonts `ChatFontNormal`, `GameFontNormal`, `GameFontNormalLarge`, `GameFontHighlight`, `GameFontHighlightSmall`.
- **Template:** `UIPanelScrollFrameTemplate` (`Blizzard_SharedXML/SecureScrollTemplates.xml:44`), with the same `ScrollBar`, `ScrollUpButton`, `ScrollDownButton` and `ThumbTexture` parent keys Dawnward restyles.
- **Widget types:** `Frame`, `Button`, `EditBox`, `ScrollFrame`, `PlayerModel` (used by `Blizzard_FrameXML/TalkingHeadUI.xml`); model methods `SetUnit`, `CanSetUnit`, `SetRotation`, `SetPortraitZoom` (`FrameAPICharacterModelBaseDocumentation.lua`), `ClearModel`, `GetModelFileID` (`SimpleModelAPIDocumentation.lua`).
- **Widget methods:** all 103 frame and region methods Dawnward calls are documented in both trees' `Simple*API` docs. The Forever mock's regions accept only Forever's documented methods (`tests/support/client_api_forever.lua`).
- **Textures:** `Interface\Minimap\MiniMap-TrackingBorder`, `UI-Minimap-ZoomButton-Highlight`, `Interface\Buttons\UI-CheckBox-Check`, `UI-RotationLeft/Right-Button-Up`, `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up`, `ButtonHilight-Square` are all referenced by Forever's own UI. Icons are game data, not UI source: a missing one shows a blank square, never an error.

### The Forever mock (L2)

`python tools/gen_client_api.py --forever <forever tree>` writes `tests/support/client_api_forever.lua`: Forever's region methods, its documented global functions, the functions of `C_AddOns`, `C_Map`, `C_QuestLog`, `C_Reputation` and `C_Timer`, and every documented event. `Boot.Start({ client = "forever" })` builds a mock with project 18, interface 16001, retail-style `C_QuestLog`/`C_Reputation`, `issecretvalue` and secret values (`mock.Secret`), without the Classic quest-log and faction globals. `Mock.CheckForever` fails the test run if the mock ever exposes a function the Forever source does not show (other than the listed engine globals). `tests/spec/forever_client_spec.lua` (21 tests) covers: load and login, the whole UI walk, level-up, quest, reputation and zone recording, `/reload`, duplicate and repeated startup events, nil and malformed replies, secret values, missing APIs, combat lockdown, the package-target warning, and Classic Era taking its old route.

### Pending Live Forever Verification

Each item needs a Forever client; none is claimed.

1. `select(4, GetBuildInfo())` is 16001 and `WOW_PROJECT_ID` is 18.
2. Dawnward loads with no Lua errors, and `/dawnward status` shows "WoW Forever (provisional support)" and no "Client APIs not available" line.
3. `C_QuestLog.GetInfo(index).level` gives the quest's level at `QUEST_COMPLETE`, and `GetQuestID`/`GetTitleText` work on Forever's reward panel.
4. `C_Reputation.GetFactionDataByIndex(i).reaction` uses the same 1–8 standings as Classic Era, and `UPDATE_FACTION` fires on a tier change.
5. `UnitName`, `UnitClass`, `UnitRace` and `UnitIsAFK` for `"player"` never return secret values in normal play (a secret would only blank optional flavour; a secret `UnitName` would make the character key "Unknown-Realm").
6. `ZONE_CHANGED*`, `GetRealZoneText`, `GetSubZoneText` and `C_Map.GetBestMapForUnit("player")` report Forever's zones; which uiMap and AreaTable IDs Forever uses (`/dawnward atlas export`).
7. `QUEST_TURNED_IN`, `PLAYER_LEVEL_UP`, `PLAYER_DEAD`, `PLAYER_GUILD_UPDATE` fire as on Classic Era.
8. `UIPanelScrollFrameTemplate`, `PlayerModel:SetUnit("player")` and the minimap button look and behave as on Classic Era (Forever's minimap is the Mainline one).
9. The icons `INV_Misc_Book_09`, `INV_Misc_Map_01` and `INV_Misc_Gear_01` exist in Forever's game data.
10. `GetQuestLogIndexByID` exists or not (Dawnward does not depend on it on Forever).
11. A package built with `## X-Dawnward-Target: forever` shows no mismatch warning on Forever, and a Classic package shows one.

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
| 3.4.1 | Yes (tag `3.4.1`, commit `4c25cb0`), see [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md) | **L3**: v0.2 acceptance items M20–M22 confirmed the version and active-profile status, coexistence, and TRP3 left unchanged | Not used: Title, Race and Class have public setters, but the five profile fields are written as one transaction through the editor's own path (see [Field mappings](TRP3_INTEGRATION.md#field-mappings)) | **L2**: `/dawnward trp3 paste` (biography, traits, every Public profile field) | **L2** (opt-in per mapping): biography block, traits since v0.3; Title→FT, Race→RA, Class→CL, Age→AG, Homeland→BP since v0.8; v0.9 adds First name→FN, Last name→LN, Title prefix→TI, Eye colour→EC, Height→HE, Build→WE, Residence→RE, Relationship status→RS (enum), additional information (Pronouns preset 7, Faith, Occupation, Allegiance) and the full-profile About page in templates 1, 2 and 3 (**L2 only**). v0.10 adds At First Glance (misc PE, opt-in), game-derived race/class/first name and axis-word trait names (**L2 only**). Biography and traits owner-reported L3 for v0.4; fields owner-observed syncing in 0.9; **the 0.9 About page was observed empty in game** (cause and fix in [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md#the-empty-about-page-found-in-game-09-and-its-fix-v010)); the v0.10 About page is **not yet tested in game**; two-client procedure in [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md#multiplayer-test-procedure-two-clients-not-yet-performed) |
| 3.5.3 | No | Reported as "not audited", status only | — | — | — |
| Any other version | No | Read only, if capability checks pass | Off | — | Off |

Compatibility with 3.5.3 is **not claimed**, and won't be until its source has been audited and it has been tested at L3 or L4.

## Client APIs used in v0.1

The Forever columns in this and the following per-version tables predate the Forever audit; [WoW Forever API compatibility](#wow-forever-api-compatibility-1601-build-70755) supersedes them.

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
| `PLAYER_REGEN_ENABLED` (event) | v0.8: a TRP3 sync run waiting for combat to end is released at once | S (`Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`), L2 | — |

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

## Widget APIs for the v0.6 design system and setup wizard

Checked on 2026-10-27 against `Gethe/wow-ui-source`, branch `classic_era` (commit `4192ac6`), `Blizzard_APIDocumentationGenerated`. The v0.6 controls use plain frames, font strings and solid textures, with no FrameXML button or input templates. Nothing below has been verified in game yet.

| API | Used for | Source evidence | Classic Era | Forever |
|---|---|---|---|---|
| `Button:SetFontString`, `SetText`, `Enable`, `Disable`, `SetEnabled`, `IsEnabled` | Template-free buttons (`Widgets.Button`) | `SimpleButtonAPIDocumentation.lua` | S, not L3 | — |
| `ScriptRegion:HookScript`, `SetScript`, `SetShown` | Hover and pressed styles added without replacing click handlers or tooltips | `SimpleScriptRegionAPIDocumentation.lua` | S, not L3 | — |
| `EditBox:SetFontObject`, `SetTextInsets`, `SetMaxBytes` (no `InputBoxTemplate`) | Styled one-line inputs | `SimpleEditBoxAPIDocumentation.lua` | S, not L3 | — |
| `Texture:SetColorTexture`, `SetVertexColor`, `SetDesaturated`, `SetTexCoord` | Chrome, fills, and the tinted header icons | `SimpleTextureBaseAPIDocumentation.lua`; Classic UI code | S, not L3 | — |
| Frame strata `HIGH` (setup wizard) and `DIALOG` (confirmations); `UISpecialFrames` | The wizard sits above the journal (MEDIUM), confirmations above both. Escape closes each | Classic UI code (`EquipmentFlyout.lua` uses `HIGH`) | S, not L3 | — |

## Client APIs for the Zone Atlas verifier (#48, v0.5)

Checked on 2026-10-27 against `Gethe/wow-ui-source`, branch `classic_era`, `Blizzard_APIDocumentationGenerated/MapDocumentation.lua`. `/dawnward atlas` only reads; it never saves anything. Nothing below has been run in game yet.

| API | Used for | Source evidence | Classic Era | Forever |
|---|---|---|---|---|
| `C_Map.GetAreaInfo(areaID)` | The client's own name for each expected AreaTable ID (`atlas verify`), and for any range (`atlas scan`) | `MapDocumentation.lua` | S, not L3 | — |
| `C_Map.GetMapInfo(uiMapID)` (`name`, `parentMapID`, `mapType`) | The client's name and parent for each expected uiMap ID, and for the current map | `MapDocumentation.lua` (`UiMapDetails`, `parentMapID` not nilable) | S, not L3 | — |
| `C_Map.GetBestMapForUnit("player")` | The current uiMap (as in v0.4 places) | `MapDocumentation.lua` | S, L3 owner-reported (1429 in Elwynn Forest) | — |

## Client APIs for the minimap button (#45, v0.5)

Checked on 2026-10-27 against `Gethe/wow-ui-source`, branch `classic_era`, `Interface/AddOns/Blizzard_Minimap/Classic/Minimap.lua` and `Minimap.xml`. Nothing below has been verified in game yet.

| API or asset | Used for | Source evidence | Classic Era | Forever |
|---|---|---|---|---|
| `Minimap` (frame) | Parent and centre of the button | `Minimap.xml` declares `<Minimap name="Minimap">` | S, not L3 | — |
| `GetCursorPosition()`, `frame:GetEffectiveScale()` | The angle while dragging the button | `Minimap.lua` uses the same pair (lines 131–133) | S, not L3 | — |
| `Interface\Minimap\MiniMap-TrackingBorder`, `Interface\Minimap\UI-Minimap-ZoomButton-Highlight` | Border and highlight of the button | Both used by `Minimap.xml` | S, not L3 | — |
| `Interface\Icons\INV_Misc_Book_09` | The button's icon | Not found in the UI source (icons are game data); a missing icon shows as a blank square, never an error | not checked | — |

## Client APIs and data for origins and places (#20, #11)

Checked against the same `classic_era` mirror at **1.15.9 (70576)**, and the client's own data tables for build **1.15.9.70576** (`UiMap`, `AreaTable`, `ChrRaces`, via wago.tools). Nothing below has been verified in game yet.

| API, event or data | Used for | Source evidence | Classic Era | Forever |
|---|---|---|---|---|
| `GetRealZoneText()` | The zone (unchanged from v0.4) | `ZoneScriptDocumentation.lua` | S, not L3 | — |
| `GetSubZoneText()` | The named area inside the zone; empty in open country | `ZoneScriptDocumentation.lua`; `Classic/ZoneText.lua` | S, not L3 | — |
| `GetZoneText()`, `GetMinimapZoneText()` | Not used: `GetRealZoneText` and `GetSubZoneText` are enough, and the minimap text mixes the two levels | `ZoneScriptDocumentation.lua` | — | — |
| `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD` | Location changes, event-driven (no polling). These are the events Blizzard's Classic zone text and minimap listen to | `Classic/ZoneText.lua`, `Classic/Minimap.lua` | S, not L3 | — |
| `C_Map.GetBestMapForUnit("player")` | The zone's uiMapID ("Only works for the player and party members") | `MapDocumentation.lua` | S, not L3 | — |
| `C_Map.GetAreaInfo(areaID)` | The client's own (localised) name for a mapped area, compared with `GetSubZoneText()` inside the same uiMap | `MapDocumentation.lua` | S, not L3 | — |
| `UiMap` IDs 1411–1458 (zones and capitals), `AreaTable` IDs (named areas) | The small mapping in `Core/Places.lua` | client data, build 1.15.9.70576 | data checked, not L3 | not checked |
| Race starting areas | Which areas count as the usual start for a race (`ChrRaces` file tokens) | Not in the client data (server-side). Classic Era convention; Human/Northshire matches the 2026-10-26 in-game observation | partly observed | not checked |

**What Dawnward records about a location:**
- zone name and uiMapID; subzone name, and its AreaTable ID only when it resolves through the mapping;
- the time, the character's level, first recorded visit versus return, source (`ZONE_CHANGED`) and confidence (`verified`: the client reported it);
- a classification only for mapped areas (starting area, settlement, inn, farmland, road, ruins, capital). Wilderness and dangerous areas have no verified entries, and dungeons are their own event category.

No coordinates are read or stored. Subzone names are never compared with English strings, so the mapping also works on localised clients, but this is untested.

**Limits:**
- `GetSubZoneText()` names the innermost area. In open country it is empty, and some areas share a name with their zone.
- The mapping is small and covers the starting zones, their first settlements and farms, Redridge, Westfall, a few inns and the six capitals. Every other area is "unknown": its visits are logged, it is never classified from its name, and it never prompts a question.
- "Starting area" needs the classic_era client, level 5 or lower, the first location Dawnward ever recorded for the character, and a matching map and area. Alternate starts, boosted or older characters and custom servers get neutral "first recorded" wording instead.
- **WoW Forever:** no place data applies until its UiMap and AreaTable IDs and starting areas are checked. Until then every place is unknown and nothing counts as a starting area.
- Battlegrounds and other non-dungeon instances are no longer recorded as zones.

**Known Classic Era limits for the story engine:**
- There is no "important quest" or story flag; significance comes from verified data only (quest level relative to the character, first quest in a zone, level milestones, first death).
- The quest tag (`GetQuestLogTitle` third return) is localised text, so it is not used.
- Repeatable quests are recorded once per character (the key is the quest ID).
- Achievements exist as an API but are not part of Classic Era play, so they are not used.
- Encounter events (`ENCOUNTER_END`, `BOSS_KILL`) are defined, but whether they fire for Classic dungeon bosses is unverified, so boss and dungeon-completion events are not built. Since v0.7.1 a session-only probe notes them (nothing is recorded), so an in-game run can settle it.
- The combat log is not read (cost, and the restriction risk).
- Factions under a collapsed header in the reputation panel are not listed by `GetFactionInfo`; their snapshot simply waits until they are listed again.
- Zone and instance "first visits" are the first ones Dawnward recorded, not necessarily the character's first ever (the client keeps no such history).
- Standing names in story text use English fallbacks for now (localisation is planned).

## Client APIs for verified events and calm moments (#11, #14, #48, v0.7.1)

Checked on 2026-10-30 against `Gethe/wow-ui-source`, branch `classic_era`, **1.15.9 (70576)** (commit `4192ac6`). **Source-verified, not yet tested in game.**

| API or event | Used for | Source evidence | Classic Era | Forever |
|---|---|---|---|---|
| `C_Map.GetMapInfo(uiMapID)` `.name`, `.mapType` (3 = `Enum.UIMapType.Zone`) | A building the client reports as the zone (data issue A) is recorded as a place inside the uiMap's zone | `MapDocumentation.lua`; `MapConstantsDocumentation.lua` (`UIMapType`, `Zone` = 3) | S, not L3 | — |
| `UnitIsAFK("player")`, `PLAYER_FLAGS_CHANGED` (unit) | No story notice while AFK; a waiting one is checked again when the player is back | `UnitDocumentation.lua`; `Classic/FriendsFrame.lua` registers `PLAYER_FLAGS_CHANGED` | S, not L3 (the narrative clock already uses both, L2) | — |
| `IsInInstance()` (2nd return `"party"`/`"raid"`) | No story notice inside a dungeon or raid; it waits until the instance is left | Classic UI code (already used for instance entries) | S, not L3 | — |
| `UISpecialFrames` | Escape hides the reaction card (the moment keeps waiting) | Classic UI code; used by the copy window since v0.1 | S, not L3 | — |
| `ENCOUNTER_START`, `ENCOUNTER_END` (encounterID, encounterName, difficultyID, groupSize, success), `BOSS_KILL` (encounterID, encounterName) | **Unverified probe only:** noted for the session and shown by `/dawnward dev story status`. Nothing is saved, recorded or asked | `EncounterInfoDocumentation.lua` defines them. **No Blizzard Classic Era UI code registers them**, so whether they fire for Classic bosses is unknown | S (defined only), not L3 | — |

## Planned APIs (not used yet)

| API or event | Planned for |
|---|---|
| `ENCOUNTER_END` / `BOSS_KILL` as story events | Dungeon and boss moments, once the session probe (`/dawnward dev story status`) shows them firing in game (issue #11) |
