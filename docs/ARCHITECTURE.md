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

**Character journey (v0.7.1, schema 5, additive):**
- `Core/StoryImport.lua` (#23, #16) is the first caller of `Sources.Capture` and `Interpretations.Propose`. It stores a pasted or Total RP 3 About text verbatim, splits it with `Sources.Paragraphs` and `Sources.Sentences` (rule-based; a piece longer than a fact is cut into parts at word boundaries, never reworded), and proposes each piece privately with its source ID, hash and position (`ref`, e.g. `p2 s1`). Approve is `Interpretations.Promote`, so canon still has only its two creation paths. Re-importing proposes only new pieces: approved and skipped keys are remembered, and pieces equal to an existing fact are not suggested. `StoryImport.AboutText` reads a copy of the About section returned by `TRP3Adapter.ReadSection`, leaving out Dawnward's owned block via `TRP3AboutBlock.WithoutOwned`. `UI/ImportWizard.lua` is the two-page window; `/dawnward biography` opens it.
- `Core/AxisMeanings.lua` (#21) holds `char.axisMeanings[axisId] = { left?, right?, meaning?, locked? }`: the player's own words for an axis and a lock. It is display and rules only: axis IDs, values, history and the Total RP 3 trait mapping are unchanged. `Evolution.Propose` refuses a locked axis. Cleaned on load by `Schema.NormalizeCharacter` (unknown axes and empty entries dropped; older data gets `{}`); carried in personal backups. The Character section's axis rows open a form for it.
- `Arcs.Reject` (#19) removes a waiting arc suggestion and remembers `arc-suggestion:<theme>` in `char.interpretationKeys`, so `Arcs.SuggestFromPattern` does not suggest that theme again; removing a waiting suggestion does the same.
- `Journal.PublicPreview` (#13) is the text of the confirmation shown before an entry becomes public.
- `Transfer` (#32): backups also carry `axisMeanings` and an `owner` key; `Transfer.Preview` lists record counts now and after a restore (computed on a merged copy, so nothing changes), and `Transfer.OwnerWarning` flags a backup from another character. `Projection.GetPublic` strips fact provenance to its origin.

**Origins and places (schema 5):** `Places` (Core) holds a small mapping checked against the Classic Era 1.15.9.70576 client data, the places log in `story.places`, and the planner that turns one location observation into at most one moment. `Platform/Observers` reads `GetRealZoneText`, `GetSubZoneText` and `C_Map.GetBestMapForUnit` on `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD`, and resolves a subzone to an area ID only when `C_Map.GetAreaInfo` returns exactly the client's own subzone text. The flow:

```
location event -> Observers.Location -> Actions.ObserveLocation -> Places.Observe (log visit; plan zone/place events,
                  most meaningful first) -> GameEvents.Record each -> Reactions.Consider (first only; shared location
                  cooldown, fold into or replace a moment queued moments ago, places on/fewer/off)
```

#### Gameplay time: the narrative clock

Story pacing runs on **gameplay time**, never on real time. A character does not need to be away for 48 real hours to get a return moment. Time offline never counts toward anything.

**What the client offers** (checked against Blizzard's Classic Era 1.15.9.70576 UI source, `Gethe/wow-ui-source` branch `classic_era`, commit `4192ac6`):

| API | What it is | Why it is not the narrative clock |
|---|---|---|
| `time()` | The computer's wall clock (Unix seconds) | Runs while offline, and the player can change it |
| `GetGameTime()` | The realm's time of day, as hours and minutes. Blizzard's clock (`Blizzard_TimeManager`) shows it as server time beside local time | Runs at real speed: there is **no accelerated in-game day** in Classic Era. It is the same for every character and runs offline |
| `RequestTimePlayed()` → `TIME_PLAYED_MSG(totalTimePlayed, timePlayedThisLevel)` | The server's `/played` totals for the character | Every chat frame prints the reply (`ChatFrameMixin:SystemEventHandler` → `ChatFrameUtil.DisplayTimePlayed`), so asking would spam chat, or would need Dawnward to tamper with Blizzard's chat handling |
| `GetTime()` | Seconds since the computer started, with millisecond precision | Meaningful only as differences within one session, which is exactly how Dawnward uses it |
| `UnitIsAFK("player")`, `PLAYER_FLAGS_CHANGED` | AFK state and its change event | Used to pause the clock |
| SavedVariables | Written at logout and `/reload` (`PLAYER_LOGOUT` fires first), never on a crash | The clock is saved with the character; a crash loses at most the unsaved session, which is the safe direction |

**The model** (`Core/NarrativeClock.lua`, fed by `Platform/PlayClock.lua`):

- **Storage:** each character has `story.clock = { v = 1, played = seconds }`. It is per character, additive, and cleaned on load; schema stays 5.
- **Counting:** while the character is logged in and not AFK, the time between two `GetTime()` readings is added. Readings happen at least once a minute (`C_Timer.NewTicker`), on every location and story event, and at `PLAYER_LOGOUT`.
- **Safety caps:** a reading that goes backwards adds nothing. A gap longer than 5 minutes, such as the computer sleeping or the game freezing, counts as 5 minutes at most. Changing the computer's date has no effect.
- **Narrative day:** a fixed amount of play, set by the **Story pace** setting (`/dawnward story set pace …`, or Settings → Story):

  | Pace | One narrative day |
  |---|---|
  | Brisk | 1 hour of play |
  | **Standard (default)** | **2 hours of play** |
  | Slow | 4 hours of play |

  Two hours is about one evening's session. "Come back another day" then means another evening of play, not another real day, and a narrative week is roughly a week of regular play.
- **Not changed by time passing:** the clock only gates *when* the Story Director may ask. Nothing in a character's history changes because time passes.

**What uses it:**

| Rule | Measured in |
|---|---|
| A return needs time away | 1 narrative day of play (`Places.RETURN_AFTER_DAYS`) |
| One return per place | per 7 narrative days of play (`Places.RETURN_REPEAT_DAYS`) |
| Story cooldowns, including the shared location cooldown | Seconds of play: Rare 2 h, Normal 45 min, Frequent 15 min |
| Waiting moments expire | After 7 narrative days of play (`Reactions.EXPIRY_DAYS`), counted at the pace in force when the moment was created (its own `expiresPlay` deadline), so changing the pace never removes a moment already waiting; the event itself stays recorded |

**Still real time (interruption control within a session):**
- notice spacing (when the card may appear);
- the two-minute window that folds a zone and its subzone into one moment;
- visit counting, where re-entering within 30 minutes is the same visit;
- every date shown to the player.

**Migration from v0.6 (additive, nothing is reset):**
- **Clock:** characters start at `played = 0`.
- **Old timestamps:** real timestamps (`last`, `returnedAt`, `pacing.lastByCategory`) are kept for display and never read as gameplay time.
- **Places without a reading:** a logged place with no `lastPlay` reports `"new"` on its next visit. Its absence starts counting from that visit, so an upgrade can never cause a burst of return moments.
- **Waiting moments:** one saved without `createdPlay` starts its expiry wait from the upgrade; one without `expiresPlay` gets its deadline from `createdPlay` the first time it is read.
- **Untouched:** places, marks, Homeland links and memories are not changed.
- **Restored backups:** if a place reading is ahead of the clock (an older backup was restored), it counts as no absence rather than an error.

#### Return visits: exact eligibility

A return to a place is recorded only when all of these hold. They are checked in `Places.ReturnTarget` and `Places.ReturnCheck`, and reported by `/dawnward dev story status`:

1. **Not the first location.** It is not the first location Dawnward ever recorded for the character, which gets the beginning or "first recorded" wording instead.
2. **A target exists.** It is the named area (subzone) if that is classified by the place mapping or tied to the character's story; otherwise the zone, if it is. A place never logged before is a first visit, not a return.
3. **A real absence, in play.** At least `Places.RETURN_AFTER_DAYS` (1 narrative day: 2 hours of play at Standard pace) since Dawnward last recorded the character there.
   - Every arrival re-stamps the place, so crossing a zone boundary back and forth never adds up to an absence.
   - Time offline does not count.
   - A place logged before the clock existed starts counting at its next visit.
   - A return too soon records nothing at all: no event, no prompt, and nothing in `/dawnward story events`.
4. **At most once a narrative week.** No return to the same place was recorded in the last `Places.RETURN_REPEAT_DAYS` (7 narrative days of play).
5. **It counts.** The place is a settlement, inn, capital or starting area, or it is tied to the character's story (`Places.Tie`):
   - **Homeland:** linked from the Places tab, or named by the Homeland field;
   - **marked meaningful:** `/dawnward place mark`, or the Places tab;
   - **a memory:** an established memory linked to it.

   Farms, roads and ruins never count by themselves.

An eligible return is a `place` event with `visit = "return"`, and it is listed by `/dawnward story events` like any other event. Whether it *asks* is decided by `Reactions.Consider` and `Director.LocationRelevance`:

- A plain return has weight 0 and is logged quietly.
- Each tie adds weight: Homeland +4, marked +3, memory +3, an active arc +2, an active goal +2, a person +2. The weight gives a chance of asking (1 = 20%, 2 = 40%, 3 = 60%, 4 = 80%).
- At weight 5 or more the return is **urgent**. It always asks and skips the shared location cooldown (45 minutes of play at the Normal frequency). The notice still waits for a calm moment.
- Setting a Homeland from the Places tab also marks the place meaningful, so it weighs 7.
- The Moments and Places settings (off or fewer) and the waiting-list limit still apply.

Class, race and faction tokens are stored on event records for optional flavour. They are never an input to significance or personality (tested). The one exception for template choice: the race token decides whether a low-level character's very first recorded location is its race's usual Classic Era starting area. That only switches between "the journey begins here" and the neutral "first recorded here" wording. It never changes the answers offered, and never says where a character comes from. See [planning/v0.4-plan.md](planning/v0.4-plan.md).

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
| Import text | 1,000,000 bytes (v0.4; was 200,000). A larger export is refused rather than produced |
| Facts / open suggestions / suggestion keys | 200 / 300 / 1,000 (oldest keys dropped first) |
| Biography versions | 3 × 16 KB (the current one is never dropped; larger text is refused) |
| Fact statement / excerpt | 300 / 300 bytes |
| TRP3 section backups | 20 (a section over 64 KB serialised is never written) |
| Dawnward biography section in TRP3 | 4,000 bytes |

## UI

See [UI_DIRECTION.md](UI_DIRECTION.md) for principles and [design/UI_DESIGN_V07.md](design/UI_DESIGN_V07.md) for the current design.

- **v0.7 interface** (built to the [approved mockups](design/mockups/README.md); automated tests only):
  - `UI/MainWindow.lua`: a 1100 × 720 window that scales down to fit the screen by width and height. A permanent character rail on the left holds the portrait, name, title, identity line, level, navigation (with a waiting-moments badge on Story), Guide, Settings and a Total RP 3 status line that opens the Total RP 3 page. Sections fill the content area on the right.
  - `UI/JournalView.lua`: the dashboard (counts, New entry, search, filters, the waiting-moment callout, entry cards, Active goals, Recent places).
  - `UI/CharacterView.lua`: grouped profile tiles, personality, family and relationships, and the public preview built from `Projection.GetPublic`.
  - `UI/Showcase.lua`: the portrait and the Character Showcase.
  - `UI/StoryView.lua` and `UI/ReactionCard.lua`: the Story Director screen and the pop-up card.
  - `UI/ChronicleView.lua` and `UI/ChroniclePlaces.lua`: Chronicle cards for every tab, and Places as list and detail.
  - `UI/SetupWizard.lua`: the setup wizard with its step rail.
  - `UI/TRP3Page.lua`: the Total RP 3 page inside Settings. It reads through `TRP3Commands.Overview` and writes only through the same guarded functions as the `/dawnward trp3` commands.
  - Shared components in `UI/Widgets.lua`: chips, panels, callouts, date blocks, progress bars and search boxes, alongside the v0.6 kit.
  - Fonts: Cinzel and Alegreya Sans (OFL) in `Media/Fonts`, mapped onto game font templates by `Style.Font`. Non-Latin clients keep the game's fonts.
  - **Character Showcase:**
    - A `PlayerModel` with `SetUnit("player")`, turned with `SetRotation` and zoomed with `SetPortraitZoom` (0–0.7, as Blizzard's own model frames).
    - The model is set only while shown and cleared on hide, and its events are registered only while shown.
    - The portrait choice is stored additively in `DawnwardChroniclesDB.ui.showcase[characterKey]` and cleaned by `Schema.NormalizeUi`.
    - Game identity (level, race, class, guild, realm) is read live and never stored.
- The notes below describe v0.5–v0.6 and still apply where not replaced above. Sizes and rows per page in them are from v0.6.

- **One window, four sections** (Journal, Character, Story, Chronicle), plus a settings panel behind a gear button and a guide behind a **?** button (#51). Neither panel is a section.
- **Design system (v0.6):**
  - `UI/Style.lua` holds the tokens, a theme registry (`Style.Register` and `Style.Apply`) and the frame chrome.
  - `UI/Widgets.lua` holds the component kit: buttons with variants and states, icon buttons, segmented controls, cards, dividers, inputs and the confirmation dialog.
  - Components paint themselves, and modules don't hand-colour controls.
  - Specification: [design/UI_DESIGN_V06.md](design/UI_DESIGN_V06.md), superseded visually by [design/UI_DESIGN_V07.md](design/UI_DESIGN_V07.md) and the [approved mockups](design/mockups/README.md).
- **First-time setup (v0.6):**
  - `Core/Onboarding.lua` holds the rules and saved state: `char.wizard`, plus drafts in `ui.wizardDrafts` keyed by character.
  - `UI/SetupWizard.lua` holds the six pages. It opens through `MainWindow.BeforeShow` for genuinely new characters only.
  - `Core/SetupCommands.lua` adds `/dawnward setup` and the developer commands, which only work in `-dev` builds.
- **Forms (v0.5):** `UI/Forms.lua` is one shared form (line, text area, cycle and number fields; Save, Cancel and a confirmed Remove) used for every record in the Chronicle and for family and history. Records no longer need slash commands.
- **Chronicle rows (v0.5, #46):** two lines per record. The text has the full width on the first; status and up to five buttons share the second. `ChronicleView.RowRects` is the single source of the row's rectangles, and a test checks none overlap. Lists are paged, six rows per page.
- **Minimap button (v0.5, #45):** `UI/MinimapButton.lua`; angle and hidden state are account-wide in `DawnwardChroniclesDB.ui.minimap`.
- **Layout:** every region comes from one layout table (`MainWindow.LAYOUT`). Tests check that regions don't overlap and that every region stays inside the opaque background. Text widths come from the layout, not from `GetWidth()`, which can be 0 before the first layout pass.
- **Layering:** the journal uses the MEDIUM layer and toplevel, like the game's own panels, so game dialogs and tooltips stay above it. The export/import window uses FULLSCREEN_DIALOG and opens above the journal.
- **Size and position:** the window is 620 × 520 UI units, small enough for the smallest UIParent the UI scale allows. It is kept on screen, and its position is saved account-wide (in real data only).
- **Themes:** themes are data in `Core/Themes.lua`: colours plus a border tint over the game's own dialog border art. Each theme is chosen per character, and new characters get Neutral. Every text colour is tested for at least 4.5:1 contrast on both surfaces.
- **Efficiency:** journal pages show 10 entries, so at most 10 row frames exist however large the journal grows. Rows are reused. Nothing redraws while the window is hidden.

## Story Director: location relevance (v0.5)

A zone or place event asks a question by weight, not by rule (`Director.LocationRelevance`, used by `Reactions.Consider`):

| Source | Points |
|---|---|
| A beginning in a known starting area | 10 (always asks) |
| The first place Dawnward records for an established character | 6 (always asks) |
| First visit: capital 3, town, inn or a starting area visited later 1, other places 0. A new zone: 1 (a capital zone 3) | |
| A return after days away | 0 |
| Homeland (the place linked from Places, or the Homeland field naming it) | +4 |
| Marked as meaningful, or tied to an established memory | +3 each |
| Named by an active established arc or goal, or by a person's relation or feelings | +2 each |
| `story set places fewer` | −2 (not for beginnings) |

Chance of asking: 1 point 20%, 2 points 40%, 3 points 60%, 4 points 80%, 5 or more always. At 5 or more the place also skips the shared location cooldown: the question is queued and announced at the next calm moment, under the normal notice pacing. Each event's roll is fixed by its key (`Director.Roll`), so a moment is never re-rolled. Zero points: the visit is logged quietly. `prompts off` and `places off` win over any weight. Only established records count, and the "why" text names the kind of tie (for example "one of your memories is tied to it"), never a record's private words.

## Runtime behaviour
- **Event-driven:** one frame for startup events and one for milestone events. There are no `OnUpdate` loops.
- **Combat:** the journal window is not secure UI and makes no protected calls, so it works during combat. (Story popups from v0.3 will be queued until combat ends.)

## Client detection
`Platform/Detect` identifies the client from `WOW_PROJECT_ID`, `GetBuildInfo()` and the interface number. Classic Era is the reference. Forever is recognised *provisionally* by interface number (16001, unverified), and anything else is reported as unknown. No client-specific gameplay code exists yet. Every API used is listed in [COMPATIBILITY.md](COMPATIBILITY.md) with its verification level.
