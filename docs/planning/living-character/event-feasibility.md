# Gameplay event feasibility: WoW Classic Era 1.15.9 (70003)

Checked against Blizzard's generated API documentation and their own Classic Era interface code for **1.15.9 (70003)**, and against our v0.1/v0.2 in-game results. Labels: **S** source-confirmed definition, **G** confirmed in game, **F** feasible but unverified behaviour, **X** unsupported. See `README.md` for the full legend.

**Important:** a definition (S) proves the client *knows* the event. It doesn't prove the event *fires* on Classic Era realms, or when. Blizzard's shared definitions also include systems Classic Era doesn't have, such as achievements and pet battles. Every event marked F gets an in-game probe before it is relied on; the client's built-in `/etrace` (Blizzard_EventTrace, **S**) can show live events without custom code.

## Experience events

| Experience | How it can be observed | Data available | Label | Story value | Default handling |
|---|---|---|---|---|---|
| **Level up** | `PLAYER_LEVEL_UP` (level, deltas…) | level, zone (`GetRealZoneText`, `GetSubZoneText`) | **G** | Medium; high at round levels and the cap | Record always. Moment at chosen levels (for example 10, 20, … and max level). |
| **Quest completed** | `QUEST_TURNED_IN(questID, xpReward, moneyReward)`, with the title cached earlier from the quest log (`GetQuestLogTitle`, used by Blizzard's UI) or `C_QuestLog.GetQuestInfo(questID)` | quest ID and title, XP, money, zone | **S** / **F** | Low individually. Classic exposes no "story quest" flag. | Record (coalesced). Moments only for **dungeon or elite quests** (quest tags, **F**), quest chains (**F**), or quests the player pins as important. |
| **Quest accepted / abandoned** | `QUEST_ACCEPTED`, `QUEST_REMOVED` | quest ID | **S** | Low | Used only to cache titles |
| **New zone (first visit)** | `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED` plus Dawnward's own first-visit memory; map ID from `C_Map.GetBestMapForUnit` | zone, subzone, map ID | **S** / **F** | Medium for major zones | Record first visits to zones. Moments for notable regions (from a curated list in Content, not inferred). |
| **"Discovered: …" exploration message** | `UI_INFO_MESSAGE` or `CHAT_MSG_SYSTEM` text | localised text only | **F** | — | **Not used.** Our own first-visit memory is more reliable and doesn't depend on language. |
| **Entered a dungeon or raid** | `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)` + `IsInInstance()` + `GetInstanceInfo()` | instance name, type | **S** / **F** | Medium | Record. A moment on the first entry to each instance (optional). |
| **Boss defeated** | `ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)`, `BOSS_KILL(encounterID, encounterName)` | encounter name, success | **S** / **F** (whether these fire for Classic dungeon bosses is unverified) | **High** | Record. Moment after combat ends (the Plaguelands victory example). Without encounter events there is no reliable fallback (see the combat log row). |
| **Wipe or failed encounter** | `ENCOUNTER_END` with `success = 0` | encounter name | **S** / **F** | Medium (failure) | Record. Occasional moment ("What did you take from that defeat?"). |
| **Death** | `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` | zone and time; the cause isn't reliably known | **S** / **F** | Medium; high for a first death or repeated deaths | Record. A moment **after** reviving, rate-limited (no prompt for every death). |
| **Notable kill** (elite or rare) | Combat log `PARTY_KILL` through `C_CombatLog.GetCurrentEventInfo()` (the global `CombatLogGetCurrentEventInfo` is only a deprecated alias in 1.15.9), plus classification cached from `UnitClassification(target)` when targeting | creature name, classification (only if it was targeted) | **F** with restriction risk | High, if reliable | **Deferred.** The combat log may be restricted (`C_CombatLog.IsCombatLogRestricted`), and secret values exist in 1.15.9. Considered after an in-game probe. |
| **Reputation milestone** | `UPDATE_FACTION` + `GetNumFactions` / `GetFactionInfo(index)` (used by Blizzard's UI), comparing standings against a stored snapshot | faction, new standing | **S** / **F** | Medium (Friendly, Honored, Revered, Exalted) | Record standing changes. Moments at Honored and above. `CHAT_MSG_COMBAT_FACTION_CHANGE` text isn't used, because it's localised. |
| **Profession milestone** | `SKILL_LINES_CHANGED` + `GetNumSkillLines` / `GetSkillLineInfo` (used by Blizzard's UI), compared against a snapshot | skill, rank | **S** / **F** | Low–medium (75/150/225/300) | Record tier crossings. Optional moment. |
| **PvP kill / duel** | `PLAYER_PVP_KILLS_CHANGED`, `DUEL_FINISHED(playerName)` | counts, or a duel opponent | **S** / **F** | Low–medium | Duels: record only, off by default. PvP: deferred. |
| **Achievement** | `ACHIEVEMENT_EARNED` is defined | — | **X** for Classic Era play (the system isn't part of Classic Era gameplay) | — | Not used |
| **Roleplay experience** | Player-written journal entry, or "Record a moment" | anything | Always available | High | A player-created moment can trigger a prompt immediately if the player wants one |

## Safety and timing signals

| Signal | API | Label |
|---|---|---|
| In combat | `InCombatLockdown()`, `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` | **S** |
| In an encounter | `ENCOUNTER_START` … `ENCOUNTER_END` | **S** / **F** |
| Cinematic | `CINEMATIC_START`, `CINEMATIC_STOP` | **S** |
| Loading | `LOADING_SCREEN_ENABLED`, `LOADING_SCREEN_DISABLED` | **S** |
| Dead or ghost | `UnitIsDeadOrGhost("player")` | **S** |
| Resting (inn or city) | `IsResting()`, `PLAYER_UPDATE_RESTING` | **S** |
| On a flight path | `UnitOnTaxi("player")` (used widely in Blizzard's UI) | **S** |
| In an instance | `IsInInstance()` | **S** |

## Constraints this imposes
- **"Meaningful" can't be read from the game.** There is no lore flag on quests or kills. Significance comes from **rules and curated content lists** (levels, first visits, encounter success, standing tiers) plus **player pins**, never from guessing.
- **Names during encounters may be unavailable** (secret values; TRP3 3.5.3 fixed exactly that). Observers must tolerate missing names and record what they can later.
- **Localised chat text is never parsed** for detection.
- **Every F row gets an in-game probe** using `/etrace` and a hidden debug log, before its moment templates are written.
