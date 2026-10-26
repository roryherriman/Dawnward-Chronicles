# Revised roadmap, risks and first milestone

## Changes from the suggested roadmap, and why
1. **The TRP3 Writer moves into v0.3.** Automatic sync is central, so v0.3 proves it early with a narrow **write spike**: the public setter for **Currently**, plus the full safety design (profile guard, compare-and-set, read-back, backup and release). It runs on a test TRP3 profile you create, gated behind an explicit opt-in. v0.6 then generalises a mechanism that has already been tested in game.
2. **The upstream TRP3 API proposal is raised in v0.3** (if you approve), because only TRP3 can make biography and trait sync supported, and their release cycle takes time.
3. **Mood moves into v0.4** (simple form only), because prompts need something to react to. Tendencies and insights stay in v0.5.
4. **Event probes come before templates.** v0.4 starts with an in-game probe of every **F** event before any prompt content is written for it.

## Phases

### v0.3: Character Foundations (scope approved earlier, plus the wizard and write spike)

| # | Milestone | Done when |
|---|---|---|
| M1 | **Schema v3 and canon engine:** Sources, Interpretations, Facts, limits as constants, privacy, simulation isolation, exports | L1: additive and idempotent v2→v3 migration; v0.2 data unchanged; no secret, private or source data in share exports |
| M2 | **Review flow:** approve, edit, reject or skip; rejected keys remembered | L1/L2: the only path into canon is a player action |
| M3 | **Setup wizard shell:** overlay, progress, Back/Continue/Skip/Finish, saved per character, Revisit setup | L2: progress survives `/reload`; dismissed never interrupts |
| M4 | **Path C and Path B:** questions, starting leanings (stored for v0.5), draft biography from answers only | L1 test: the draft contains no words beyond the answers and fixed connecting phrases |
| M5 | **Path A:** TRP3 read (public getters plus the 3.4.1 About adapter), linking, paste path, sentence list | L2 against an extended 3.4.1 fake; unknown version, default profile or wrong profile → paste path |
| M6 | **TRP3 write spike:** Writer for **Currently** only, with ledger, backup, compare-and-set, read-back and release; off by default | L2 plus a guarded **L3 test on a throwaway TRP3 profile, with your approval** |
| M7 | Story prompts prototype (approved): 1–3 writing prompts from canon | Deterministic; canon only |
| M8 | Docs, acceptance checklist, test build | — |

Upstream TRP3 API proposal: drafted in v0.3, **sent only with your approval**.

### v0.4: Living Story Moments
| # | Milestone |
|---|---|
| M1 | **Event probes** (`/etrace` plus a hidden debug log): confirm each F event fires on Classic Era, and when |
| M2 | Observers for the confirmed events (quests, first zone visits, instance entry, encounters, deaths, reputation and skill tiers) |
| M3 | SafeTime gate and the Moments queue (coalescing, expiry, frequency, cooldowns, mute) |
| M4 | Prompt engine (template format, filter, score, seeded pick), plus the first content pack (~40–60 templates) |
| M5 | StoryPrompt card (small, themed, Later / Dismiss / Fewer like this) and the Story section (pending moments, history) |
| M6 | Decisions: journal event and reaction, simple mood, undo last, plus labelled canon effects |
| M7 | Acceptance: prompts never appear in combat, encounters, cinematics or loading screens |

### v0.5: Character Evolution
- Tendencies (6 axes, diminishing nudges, daily caps), insights leading to canon, and the Development area (words, adjust, lock).
- Adaptive prompts (relevance from canon, mood and history; callbacks).
- Biography composer (sections, player edits win, proposed additions) and a Currently composer.

### v0.6: TRP3 Living Profile
- Publication policy UI (categories, the "Public" badge on options).
- Writer generalised to Currently, Title and Full title; conflict UI; profile-link management; recovery at login.
- Paste-assisted biography and trait updates ("changes since last applied").
- TRP3 **3.5.3 audit** and allowlist update, and an upstream API integration if TRP3 has added one.
- A compatibility test pass.

## Risks and limitations

| # | Risk / limitation | Impact | Mitigation |
|---|---|---|---|
| 1 | **TRP3 has no supported write for biography, traits, misc or glances** (3.4.1 and `main`) | Core goal only partly automatic | Automatic for Currently and titles; one-paste assist for biography and traits; upstream proposal |
| 2 | TRP3 setters silently do nothing on the default profile | Silent sync failure | Profile guard plus read-back |
| 3 | Player edits in TRP3 vs Dawnward writes | Overwriting the player's text | Compare-and-set ledger; conflict stops management |
| 4 | Encounter or boss events may not fire for Classic dungeon bosses | Fewer "victory" moments | v0.4 M1 probe; fall back to dungeon completion via instance exit plus kills only if reliable |
| 5 | Secret values and combat log restrictions in 1.15.9 | Missing names; restricted combat data | Don't depend on names during encounters; combat-log features deferred and opt-in |
| 6 | "Meaningful" isn't exposed by the game | Generic prompts | Rules plus curated lists plus player pins; never guessing |
| 7 | Template text repeats over long play | Fatigue | Variants, novelty penalties, cooldowns, frequency setting, content packs |
| 8 | Composed biography reads as formulaic | Disappointment | Framed as a draft; player edits win; honest wording in UI and docs |
| 9 | Prompt fatigue or intrusiveness | Players disable it | Safe-time gate, "Rare" setting, mute per category, never during combat or encounters |
| 10 | Saved data growth | Load time, file size | Existing caps plus new caps (moments 20, decisions 500), retention like the journal |
| 11 | **KI-1** (one-time return to character select) is unresolved | Unknown | Not linked to Dawnward; watched during every L3 pass |
| 12 | WoW Forever and TRP3 3.5.3 untested | Later target | Forever stays a separate target; adapters gated by version |
| 13 | Scope creep | Delays | Each version has milestones with "done when"; nothing starts without your approval |

**What can't be done inside WoW without AI:**
- understanding arbitrary biography text;
- generating unrestricted prose;
- detecting story significance that the game doesn't expose;
- writing TRP3 fields that have no public setter.

## Recommended first implementation milestone
**v0.3 M1: schema v3 and the canon engine** (Sources, Interpretations, Facts).

Everything else depends on it, it is already approved in detail, it is pure Core (fully L1-testable), and it changes no UI or TRP3 behaviour.

**Immediately after** comes **v0.3 M6, the TRP3 write spike**, moved ahead of the wizard UI if you prefer. It de-risks the central sync goal early, using only public setters, on a test profile, with your approval for the in-game trial.

## Decisions needed before implementation

> **Settled on 2026-10-25** (see `README.md`, "Review decisions"):
> - 1, 2 and 5: approved. M1 comes first; the Currently write test follows once the data model is ready.
> - 3: drafting approved; submission needs separate approval.
> - 4: deferred to a presentation with examples before v0.5.
>
> The original list is kept below for the record.
1. Approve this architecture and roadmap, including moving the TRP3 write spike into v0.3.
2. Approve **Currently**, **Title** and **Full title** as the automatically managed fields, each opt-in, and the paste-assisted approach for biography and traits.
3. May I draft (not send) the upstream TRP3 API proposal? Sending it is a separate approval.
4. The initial tendency axes (6), the mood set (9), and the publication categories as listed.
5. Start with v0.3 M1, or with the M6 write spike?
