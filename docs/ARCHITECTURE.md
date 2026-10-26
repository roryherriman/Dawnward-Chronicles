# Architecture

Status: **v0.2 (journal window) implemented, tested at L0–L2, and passed its L3 acceptance checklist on Classic Era** (all mandatory items; UI scaling untested). See [COMPATIBILITY.md](COMPATIBILITY.md).

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

## Addon layout (v0.3.0-dev)

```
DawnwardChronicles/
  DawnwardChronicles.toc
  Core/          Util, Privacy, Themes, Schema, Migrations, Character, Journal,
                 Milestones, Facts, Sources, Interpretations, Personality,
                 Projection, Serializer, Transfer, Store, Actions, Commands
  Integrations/TRP3/
                 VersionProfiles, Status (read-only), Ledger, AboutBlock, TraitPlan,
                 Shape, Adapter (the only module touching TRP3 for sync), Sync, Commands
  Platform/      Detect, Events (milestones), TRP3Bridge (sync scheduling),
                 Bootstrap (saved data, slash commands)
  UI/            Widgets, CopyBox, MainWindow, JournalView, CharacterView,
                 StoryView, SettingsPanel
```

**Character foundations (v0.3 M1):** `Facts` is canon, and only the player creates it (`Facts.Add` from `Actions`, or `Interpretations.Promote`); `tests/spec/architecture_spec.lua` scans `Core/` to enforce this. `Sources` stores biographies verbatim. `Interpretations` holds suggestions with stable keys and key memory. `Personality` holds axis values. The core plugs the TRP3 commands in through `ctx.trp3`, so `Core/` never references TRP3.

**Living chronicle (v0.4):** `StorySchema` (the per-character `story` table), `GameEvents` (normalised gameplay records), `ReactionLibrary` (authored, universal questions), `Reactions` (the paced queue), `Decisions` (answers), `Evolution` (approved personality changes), `Narrative` (journal drafts) and `StoryCommands`. `Platform/Observers` turns quest, death and level-up events into records; `Platform/SafeTime` decides when a waiting moment may be announced; `UI/StoryView` and `UI/ReactionCard` present them; `Integrations/TRP3/Presentation` formats public content. The flow:

```
WoW event -> Observers -> Actions.RecordRealEvent -> GameEvents.Record (dedupe, significance)
          -> Reactions.Consider (threshold, cooldown, coalescing, queue)  -- queued, private
SafeTime (calm moment) -> chat line + card -> Story section
player answer -> Decisions.Decide -> Evolution.Propose (pending) -> player approves -> Personality.Set
                                  -> Narrative.Draft -> Journal.AddStoryDraft (private draft)
player approves draft, marks it a defining moment, makes it public
          -> Projection.GetPublic -> TRP3 AboutBlock (opt-in experimental sync, all v0.3 guards)
```

**Narrative records (v0.4):** `Records` defines one contract for memories, arcs, goals, identity statements and people: provenance (observed / player / suggested), canon status (proposed / established / disputed / superseded) and visibility, kept apart. `RecordTypes` holds their shapes; `Memories`, `Arcs`, `Goals`, `Identity`, `People` their behaviour; `Director` builds context for reactions from established records only; `Continuity` finds contradictions and records the player's answers; `Observed` compares reputation and guild snapshots; `Timeline` is a view, not a store. All of it lives in the character's `story` table. Only established, public identity personas (and approved, public defining moments) can reach the public projection.

Class, race and faction tokens are stored on event records for optional flavour only. They are never an input to significance, template choice or personality (tested). See [planning/v0.4-plan.md](planning/v0.4-plan.md).

**TRP3 sync** is described in [TRP3_INTEGRATION.md](TRP3_INTEGRATION.md#the-sync-design-as-built).

**Planned, not built:**

- the setup wizard (v0.3 M3);
- more event categories (dungeons, bosses, exploration, reputation; issues #11 and #18);
- a Forever adapter (once a Forever client can be tested);
- locale files.

The Kyssarra Dawnward test character is entered through the normal UI. Her details stay in the git-ignored `private/` folder, and nothing about her is hardcoded.

## Saved data

| Variable | Owner | Contents |
|---|---|---|
| `DawnwardChroniclesDB` | Core | `schemaVersion` (4); (v4) a `story` table per character (events, event keys, reactions, decisions, personality changes, baselines, story settings, pacing); per character: profile fields, family, history, journal, journal milestone keys, theme, and (v3) biography sources, suggestions, suggestion key memory, facts, personality, wizard; import undo slots; account-wide window position |
| `DawnwardChroniclesSimDB` | Core, simulation mode | The same schema, with test data only. It can be wiped with one command. |
| `DawnwardChroniclesTRP3DB` | TRP3 integration (v0.3, experimental) | Its own `schemaVersion` (1); per-character opt-ins bound to a TRP3 profile ID, per-profile ownership records and conflicts, up to 20 serialised section backups, a short log. A ledger from a newer build is left untouched and pauses sync. |

**Isolation:** the TRP3 status reader only reads. The sync works from the public projection and writes nothing to Dawnward's character data. Every TRP3 access is wrapped in `pcall`, so a TRP3 failure becomes a status or a blocked sync, and the journal carries on.

**Real versus simulated events:** milestones observed in the game always go to the *real* character, even while simulation mode is on. Simulation is for trying things out, not for hiding real events. To test milestones, `/dawnward sim levelup <n>` writes simulated ones to simulation data only.

### Versioning and migrations
- Migrations are ordered functions (`n → n+1`) that work on a **copy**. The saved table is replaced only after the migration *and* normalisation succeed.
- A failed migration, unversioned data, or data from a **newer** schema switches the addon to read-only for the session and leaves the saved table untouched.
- `Schema.NormalizeDatabase` is the single gate for loaded, migrated and imported data. It drops unknown keys, cleans text, caps sizes and repairs IDs. Loading data twice gives the same result (tested).
- **1 → 2 (v0.2):** additive only. It adds an empty journal, empty journal keys and the Neutral theme to every character and import backup, plus an empty `ui` table. Fields, family, history, visibility, timestamps and IDs are untouched (tested). After upgrading, v0.1 treats the data as newer and opens it read-only rather than damaging it.

- **3 → 4 (v0.4):** additive only. It adds an empty `story` table to every character and import backup. Journal entries, personality values and every visibility are untouched (tested), so an upgrade never publishes anything.
- **2 → 3 (v0.3):** additive only. It adds empty sources, suggestions, suggestion keys, facts, personality and wizard tables to every character and import backup. Every v2 value is untouched (tested against a full v2 fixture). Schema v3 is frozen when v0.3 is released; until then later v0.3 milestones may add fields within v3.

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
| Facts / open suggestions / suggestion keys | 200 / 300 / 1,000 (oldest keys dropped first) |
| Biography versions | 3 × 16 KB (the current one is never dropped; larger text is refused) |
| Fact statement / excerpt | 300 / 300 bytes |
| TRP3 section backups | 20 (a section over 64 KB serialised is never written) |
| Dawnward biography section in TRP3 | 4,000 bytes |

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
