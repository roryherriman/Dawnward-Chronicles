# System and data architecture

This document extends the v0.2 layering (Core → Platform → Integrations → UI) and the approved **Source / Interpretation / Canon** model. Every new module is small, has one job, and can be tested on its own (L1 for Core, L2 for Platform, Integrations and UI).

## The six layers of a character

| # | Layer | What it holds | Who creates it | Can it change by itself? |
|---|---|---|---|---|
| 1 | **Experiences** (Source) | Observed game events (level, quest, zone, encounter, death…), imported TRP3 data, original biographies | The game, the TRP3 reader, the player (paste) | No: experiences are facts, recorded once |
| 2 | **Decisions** | The player's answer to a story moment, with its context | The player | No (the last one can be undone) |
| 3 | **Emotional state** | One current mood with intensity, which fades over time | Decisions and experiences | Yes, it decays. It **never** becomes a trait by itself. |
| 4 | **Tendencies** | Long-term personality leanings (for example cautious ↔ bold) | Accumulated decisions, with small, diminishing nudges | Only through decisions or player adjustment |
| 5 | **Canon** | Approved facts (origin, relationships, beliefs, traits…) | Player approval, or a decision's labelled direct effect | No |
| 6 | **Public narrative** | The subset of canon and development the player allows to be public: Currently text, titles, a biography draft | Projection from 2–5 through the publication policy | Recomputed. Published only per policy. |

**Interpretations** sit alongside these layers. They are proposals: candidate facts, insights ("she has grown more cautious, make it canon?") and story opportunities, and they never cross into canon without the player.

## Module map

```
Core/ (pure Lua 5.1, L1)
  existing: Util Privacy Themes Schema Migrations Character Journal Milestones Projection
            Serializer Transfer Store Actions Commands
  v0.3:     Sources  Interpretations  Facts  Questions  Wizard
  v0.4:     Moments (queue, coalescing, rate limits)  Prompts (library + selector)  Decisions
  v0.5:     Evolution (tendencies, mood, insights)  Narrative (biography + Currently composer)
  v0.6:     Publication (policy → public items)  SyncPlan (desired TRP3 field values, diffing)

Platform/ (WoW APIs, L2)
  existing: Detect Events Bootstrap
  v0.4:     Observers (quest, zone, encounter, death, reputation, skill)  SafeTime (when a prompt may show)

Integrations/TRP3/ (read-only except Writer, L2)
  existing: VersionProfiles Status
  v0.3:     Reader (public getters + 3.4.1-gated About adapter)  Writer spike (public setters only)
  v0.6:     Writer (full) + SyncLedger (in DawnwardChroniclesTRP3DB)

UI/
  existing: Widgets CopyBox MainWindow JournalView CharacterView StoryView SettingsPanel
  v0.3:     WizardOverlay (inside the main window; not a tab)  Foundations (in Character)
  v0.4:     StoryPrompt (small in-world card)  Story section: pending moments + decision history
  v0.5:     Development (in Character): tendencies in words, mood, recent decisions
Content/ (data only)
  Questions/   Prompts/   Narrative/ (sentence fragments)
```

**Dependencies flow one way:** Content → Core ← Platform/Integrations ← UI. `Core` never calls WoW or TRP3, and `Integrations/TRP3/Writer` is the **only** code that may call a TRP3 setter.

## Data model

Additive migrations continue the v1→v2 pattern: copy first, normalise, idempotent, newer data opened read-only.

```
DawnwardChroniclesDB.characters[key]                              (schema version)
  fields, family, history, journal, journalKeys, theme, nextId    (v2, existing)
  sources[]           verbatim biographies + imported fields, ≤3 versions × 16 KB      (v3)
  interpretations[]   candidates, insights, opportunities; status open|rejected|promoted (v3)
  facts[]             canon: category, statement, provenance, visibility              (v3)
  wizard              { path, step, answers, updatedAt, dismissed }                    (v3)
  moments[]           pending story moments (queue), ≤20, with expiry                 (v4)
  decisions[]         { id, momentId, templateId, optionId, at, context, effects }, ≤500 (v4)
  storyPrefs          { frequency, mutedCategories, lastPromptAt }                     (v4)
  evolution           { tendencies = { axis = value }, mood = { id, intensity, at } }  (v5)
  narrative           { draft, edited, sections, composedAt }                          (v5)
  publication         { categories = { [category] = "never"|"ask"|"auto" } }          (v6)

DawnwardChroniclesTRP3DB.characters[key]                          (separate variable, v0.3 spike / v0.6)
  link          { profileId, profileName, confirmedAt }
  ledger        { [field] = { lastWritten, writtenAt, managed, conflict } }
  backups       { [field] = previous value before Dawnward first managed it }
  pending       { [field] = { value, intentAt } }   -- write intent, for recovery

DawnwardChroniclesSimDB   same schema as DawnwardChroniclesDB; TRP3 writes are disabled in simulation
```

### Limits
The approved limits are unchanged:

| Item | Limit |
|---|---|
| Journal entries | 500 |
| Approved facts | 200 |
| Pending suggestions | 300 |
| Biography versions | 3 × 16 KB |

New limits, each a named constant:

| Item | Limit |
|---|---|
| Pending story moments | 20 (the "pending popups" figure from the original architecture) |
| Decision history | 500, oldest first. Decisions referenced by canon facts or journal entries keep a short record. |
| Mood | One active mood |
| Tendency axes | 6 to start (see `evolution-model.md`) |
| TRP3 ledger | One entry per managed field |

## Flows

### Gameplay to story moment
```
WoW event → Observer (Platform) → Experience recorded (Journal, Source)
          → Moments.Consider(experience)   significance rules, coalescing, cooldowns, frequency
          → queued Moment (expires)        SafeTime decides *when*
          → Prompts.Select(moment, character) deterministic, weighted, conditioned
          → StoryPrompt shown → player: choose | postpone | dismiss | mute category
          → Decisions.Apply(choice)         journal entry, mood, tendency nudges, labelled canon effects
          → Evolution.Check()               threshold crossed → Insight (interpretation) for approval
          → Narrative.Recompose()           draft biography + Currently suggestion
          → Publication.Project()           public items allowed by policy
          → SyncPlan → TRP3 Writer          at a safe time, only managed fields, compare-and-set
```

### Safety gates (all must pass before a prompt is shown)
- not `InCombatLockdown()`;
- not during an encounter (between `ENCOUNTER_START` and `ENCOUNTER_END`);
- not during a cinematic or loading screen;
- not dead or a ghost (`UnitIsDeadOrGhost`), except for death-reflection moments, which are shown after reviving;
- the player has not muted prompts;
- the rate limit allows it.

**Preferred moments:** resting (`IsResting`), on a taxi (`UnitOnTaxi`), or idle out of combat for N seconds. (**S** for the APIs, **F** for the behaviour.)

### Privacy and isolation
- Everything new defaults to **private**.
- Publication is decided per category (`never` / `ask` / `auto`). `auto` applies only to developments the player made through a decision whose prompt **showed that the result is public**. That decision is the informed authorisation.
- **Secret** items are never published, and are excluded from backups unless requested (existing rule). Biographies need explicit opt-in for backups (approved rule).
- **Simulation** has its own database for every layer. The TRP3 Writer refuses to run while simulation is on.

### Performance
- Observers are event-driven and cheap: they record a small table and return. Selection, composition and sync run later, out of combat.
- No `OnUpdate` loops. A single deferred check runs on `PLAYER_REGEN_ENABLED`, `PLAYER_UPDATE_RESTING` or the end of a loading screen.
- The combat log is **not** parsed continuously in v0.4. Any combat-log-based detection (notable kills) is opt-in and limited to cheap filters, because of cost and the restriction risk.
