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
| WoW Classic Era | 11509 (listed in the TRP3 3.4.1 TOC, still to be confirmed with `GetBuildInfo()` in game) | Primary development client | — |
| WoW Forever 1.60.1 | Believed to be 16001. **Unverified.** | Final deployment target | — (adapter disabled) |

## Total RP 3

| Version | Source audited | Tier 0 (read) | Tier A (public setters) | Tier B (manual export) | Tier C (owned direct write) |
|---|---|---|---|---|---|
| 3.4.1 | Yes, see [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md) | — | — | — | Research only |
| 3.5.3 | No | — | — | — | — |
| Any other version | No | Read only, if capability checks pass | Off | Available | Off |

Compatibility with 3.5.3 is **not claimed**, and won't be until its source has been audited and it has been tested at L3 or L4.

## Client API assumptions (to verify per client)

| API or event | Used for | Classic Era | Forever |
|---|---|---|---|
| `GetBuildInfo`, `WOW_PROJECT_ID` | Client detection | — | — |
| `C_AddOns.GetAddOnMetadata` / `GetAddOnMetadata` | Reading the TRP3 version without touching TRP3 internals | — | — |
| `InCombatLockdown`, `PLAYER_REGEN_ENABLED/DISABLED` | Combat queue | — | — |
| `PLAYER_LEVEL_UP` | Journal (v0.2) | — | — |
| `QUEST_TURNED_IN` | Journal (v0.2) | — | — |
| `ZONE_CHANGED_NEW_AREA` | Journal (v0.2) | — | — |
| `PLAYER_DEAD` | Journal (v0.2) | — | — |
| `ENCOUNTER_END` / `BOSS_KILL` | Journal (v0.2) | — | — |
| `C_EncodingUtil` | Not used by Dawnward. TRP3 3.4.1 needs it for its own import and export. | — | — |

Rows are added as features start using new APIs.
