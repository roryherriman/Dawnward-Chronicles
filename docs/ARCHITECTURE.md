# Architecture

Status: **v0.2 (journal window) implemented and mock-tested (L0–L2). Not yet tested in game.** v0.1 reached partial L3; see [COMPATIBILITY.md](COMPATIBILITY.md).

## Layers

```
            ┌────────────────────────────── UI ───────────────────────────────┐
            │ journal window (Journal · Character · Story) · settings · copy box│
            └──────┬───────────────────────┬────────────────────────┬──────────┘
                   │ Actions / Commands     │                        │ status only
            ┌──────▼──────┐          ┌──────▼──────┐          ┌──────▼──────────────┐
            │  Platform   │ observed │    Core     │  copies  │ Integrations/TRP3   │
            │ WoW events, ├─────────►│ pure Lua    │◄─────────┤ read-only, version- │
            │ saved vars, │ facts    │ 5.1, no WoW │          │ checked, pcall-     │
            │ slash cmds  │          │ globals     │          │ wrapped             │
            └─────────────┘          └─────────────┘          └─────────────────────┘
```

| Layer | May call WoW APIs | May call TRP3 | Depends on |
|---|---|---|---|
| `Core/` | No (enforced by luacheck) | No | nothing |
| `Platform/` | Yes | No | Core |
| `Integrations/TRP3/` | No; it receives its environment as a parameter | Yes, read-only, through capability checks | Core (version profiles) |
| `UI/` | Yes | No (TRP3 status comes through the integration) | Core, Platform |

`Core` is pure Lua 5.1, so all of the game logic is unit-tested (L1) without a client. The UI never writes saved data directly: every change goes through `Core/Actions.lua` (or `Core/Commands.lua` for slash commands, which share the same rules).

## Addon layout (v0.2)

```
DawnwardChronicles/
  DawnwardChronicles.toc
  Core/          Util, Privacy, Themes, Schema, Migrations, Character, Journal,
                 Milestones, Projection, Serializer, Transfer, Store, Actions, Commands
  Integrations/TRP3/
                 VersionProfiles, Status (read-only)
  Platform/      Detect, Events (milestones), Bootstrap (saved data, slash commands)
  UI/            Widgets, CopyBox, MainWindow, JournalView, CharacterView,
                 StoryView, SettingsPanel
```

**Planned, not built:**

- the story and personality modules (v0.3+);
- `CombatQueue` for popups (v0.3);
- TRP3 writers and `DawnwardChroniclesTRP3DB` (v0.5);
- a Forever adapter (once a Forever client can be tested);
- locale files.

The Kyssarra Dawnward test character is entered through the normal UI. Her details stay in the git-ignored `private/` folder, and nothing about her is hardcoded.

## Saved data

| Variable | Owner | Contents |
|---|---|---|
| `DawnwardChroniclesDB` | Core | `schemaVersion` (2); per character: profile fields, family, history, journal, journal milestone keys, theme; import undo slots; account-wide window position |
| `DawnwardChroniclesSimDB` | Core, simulation mode | The same schema, with test data only. It can be wiped with one command. |
| `DawnwardChroniclesTRP3DB` | TRP3 integration (v0.5) | Not created yet. It will hold profile bindings, the sync ledger and backups. |

**Isolation:** the TRP3 adapter only reads. It copies out strings and booleans and never receives a reference to Dawnward's saved tables. A TRP3 failure becomes an `error` status, and the journal carries on.

**Real versus simulated events:** milestones observed in the game always go to the *real* character, even while simulation mode is on. Simulation is for trying things out, not for hiding real events. To test milestones, `/dawnward sim levelup <n>` writes simulated ones to simulation data only.

### Versioning and migrations
- Migrations are ordered functions (`n → n+1`) that work on a **copy**. The saved table is replaced only after the migration *and* normalisation succeed.
- A failed migration, unversioned data, or data from a **newer** schema switches the addon to read-only for the session and leaves the saved table untouched.
- `Schema.NormalizeDatabase` is the single gate for loaded, migrated and imported data. It drops unknown keys, cleans text, caps sizes and repairs IDs. Loading data twice gives the same result (tested).
- **1 → 2 (v0.2):** additive only. It adds an empty journal, empty journal keys and the Neutral theme to every character and import backup, plus an empty `ui` table. Fields, family, history, visibility, timestamps and IDs are untouched (tested). After upgrading, v0.1 treats the data as newer and opens it read-only rather than damaging it.

### Journal retention
- At most **500 entries per character**.
- When the journal is full, the **oldest automatic entry** (a milestone) is removed to make room, and the player is told.
- **Entries the player wrote are never removed automatically.** If all 500 entries are player-written, adding another is refused with an explanation (delete or export older entries). A milestone that arrives then isn't recorded, and its key isn't marked as seen.
- **Milestone keys** (for example `levelup:23`) outlive their entries, so a pruned milestone is never recorded twice. They are capped at 1,000, oldest first.
- Hand-edited or imported data larger than 500 entries is trimmed on load in the same order: automatic entries first, then the oldest written entries only if the written entries alone exceed the cap. Each trim is reported.

### Milestones
`Core/Milestones.lua` keeps a registry of milestone types. Each type has a `build(data)` function that validates its data and returns an event with a stable de-duplication `key`. `Platform/Events.lua` maps game events to types. Adding quests or discoveries later means registering a type and a handler; the journal itself doesn't change.

| Type | Game event | Key | Stored |
|---|---|---|---|
| `levelup` | `PLAYER_LEVEL_UP` (new level) | `levelup:<level>` | level, zone, subzone, source, time |

Automatic entries can change visibility, but they can't be edited or deleted, so the record of what happened stays intact.

### Growth limits

| Item | Limit |
|---|---|
| Journal entries per character | 500 (retention policy above) |
| Milestone keys per character | 1,000 |
| Family / history entries | 100 / 200 |
| Characters per database | 200 |
| Short / long text | 100 / 2,000 bytes |
| Import text | 200,000 bytes |

## UI

See [UI_DIRECTION.md](UI_DIRECTION.md).

- **One window, three sections** (Journal, Character, Story), plus a settings panel behind a gear button. The panel isn't a fourth section.
- **Layout:** every region comes from one layout table (`MainWindow.LAYOUT`). Tests check that regions don't overlap and that every region stays inside the opaque background. Text widths come from the layout, not from `GetWidth()`, which can be 0 before the first layout pass.
- **Layering:** the journal uses the MEDIUM layer and toplevel, like the game's own panels, so game dialogs and tooltips stay above it. The export/import window uses FULLSCREEN_DIALOG and opens above the journal.
- **Size and position:** the window is 620 × 520 UI units, small enough for the smallest UIParent the UI scale allows. It is kept on screen, and its position is saved account-wide (in real data only).
- **Themes:** themes are data in `Core/Themes.lua`: colours plus a border tint over the game's own dialog border art. Each theme is chosen per character, and new characters get Neutral. Every text colour is tested for at least 4.5:1 contrast on both surfaces.
- **Efficiency:** journal pages show 10 entries, so at most 10 row frames exist however large the journal grows. Rows are reused. Nothing redraws while the window is hidden.

## Runtime behaviour
- **Event-driven:** one frame for startup events and one for milestone events. There are no `OnUpdate` loops.
- **Combat:** the journal window is not secure UI and makes no protected calls, so it works during combat. (Story popups from v0.3 will be queued until combat ends.)

## Client detection
`Platform/Detect` identifies the client from `WOW_PROJECT_ID`, `GetBuildInfo()` and the interface number. Classic Era is the reference. Forever is recognised *provisionally* by interface number (16001, unverified), and anything else is reported as unknown. No client-specific gameplay code exists yet. Every API used is listed in [COMPATIBILITY.md](COMPATIBILITY.md) with its verification level.
