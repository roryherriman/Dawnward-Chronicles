# Architecture

Status: **design**. Only `tests/` and `tools/` exist so far. The addon folder arrives with v0.1. Everything below the tooling is planned, not implemented.

## Layers

```
            ┌──────────────────────────── UI ────────────────────────────┐
            │ popups · journal · copy box · options                      │
            └──────┬──────────────────────┬───────────────────┬──────────┘
                   │                      │                   │
            ┌──────▼──────┐        ┌──────▼──────┐     ┌──────▼──────────────┐
            │  Platform   │        │    Core     │     │ Integrations/TRP3   │
            │ WoW APIs,   ├───────►│ pure Lua    │◄────┤ capability-gated,   │
            │ events,     │ facts  │ 5.1, no WoW │ pub │ sees only the       │
            │ combat queue│        │ globals     │ view│ public projection   │
            └─────────────┘        └─────────────┘     └─────────────────────┘
```

| Layer | May call WoW APIs | May call TRP3 | Depends on |
|---|---|---|---|
| `Core/` | No | No | nothing |
| `Platform/` | Yes | No | Core |
| `Integrations/TRP3/` | Only to detect TRP3 and to check combat | Yes, through capability checks | the Core public projection |
| `UI/` | Yes | No (goes through the integration) | all of the above |

`Core` is pure Lua 5.1, so all of the game logic can be unit-tested (L1) without a client.

## Planned addon layout

```
DawnwardChronicles/
  DawnwardChronicles.toc
  Core/          Namespace, Util, Log, Schema, Migrations, Character, Family,
                 Journal, Story, Personality, Privacy, Serializer, Projection
  Platform/      Detect, ClassicEra, Forever (provisional), Events, CombatQueue
  Integrations/TRP3/
                 Capabilities, VersionProfiles, Reader, PublicWriter,
                 Backup, ManualExport
  UI/
  Locales/enUS.lua
```

Story packs are **data**, not code. The Kyssarra Dawnward test character is entered through the normal UI and stored in `private/`. Nothing about her is hardcoded.

## Saved data

There are three separate SavedVariables, so that a failure in one cannot damage the others:

| Variable | Owner | Contents |
|---|---|---|
| `DawnwardChroniclesDB` | Core | `schemaVersion`, per-character profile, family history, journal, story state, approval ledger |
| `DawnwardChroniclesSimDB` | Core, simulation mode | The same schema, test data only. It can be wiped with one command. |
| `DawnwardChroniclesTRP3DB` | TRP3 integration | Profile bindings, sync ledger, backups of TRP3 fields before each write |

**Isolation rule:** the TRP3 integration never receives a reference to `DawnwardChroniclesDB`. It gets a fresh, deep-copied **public projection** (see [PRIVACY.md](PRIVACY.md)) and writes only to `DawnwardChroniclesTRP3DB`. Each integration entry point runs inside `pcall`. After an error, the integration turns itself off for the rest of the session and records the reason, and the core and journal carry on unaffected.

### Versioning and migrations
- Each variable has its own `schemaVersion`.
- Migrations are ordered pure functions (`n → n+1`), covered by L1 tests with fixture data.
- Before migrating, a copy of the previous data is kept in memory until the migration succeeds. A failed migration leaves the data untouched and switches the addon to read-only mode.
- Data from a newer schema (a downgrade) is never modified. The addon refuses to write and tells the player.

### Growth limits (defaults, configurable within bounds)

| Item | Default | Hard cap |
|---|---|---|
| Journal entries per character | 500 | 2,000 (the oldest are rolled up into summaries) |
| Pending popups | 20 | 50 |
| TRP3 backups per profile | 5 | 10 |
| Free-text field | 2,000 characters | 8,000 |
| Generated TRP3 biography block | 4,000 characters | — |

## Runtime behaviour

- **Event-driven:** one event frame per layer, and handlers register only while their feature is enabled. There are no `OnUpdate` polling loops.
- **Combat-safe:** `CombatQueue` holds popups and any TRP3 work while `InCombatLockdown()` is true. It also holds them while dead, during cinematics, and while on a taxi, and releases them on the matching event (for example `PLAYER_REGEN_ENABLED`).
- **Cheap in combat:** a journal entry recorded in combat captures only the minimum; text formatting is deferred.

## Client adapters

`Platform/Detect` identifies the client from `WOW_PROJECT_ID`, `GetBuildInfo()` and the interface number. `ClassicEra.lua` is the reference adapter.

`Forever.lua` exists only as a stub and is **disabled** until it has been tested on a Forever client. Every API the adapters use is listed in [COMPATIBILITY.md](COMPATIBILITY.md) with its verification level. An API is never assumed to exist just because it exists in another client.
