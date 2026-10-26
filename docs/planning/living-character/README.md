# Living Character System: master plan

Status: **overall direction approved (2026-10-25), subject to implementation review. Nothing here is implemented.** This plan builds on the merged v0.2 (`main` at `71fa999`), the approved v0.3 decisions (`../v0.3-proposal.md`) and the TRP3 audit (`../../TRP3_INTEGRATION.md`).

## Review decisions (2026-10-25)

| # | Decision |
|---|---|
| 1 | **Six-layer character architecture approved**, subject to implementation review |
| 2 | **Early TRP3 Currently write test in v0.3 approved:** disposable TRP3 profile, supported public APIs only, and **explicit authorisation before the test is run** |
| 3 | **Drafting an upstream TRP3 API proposal approved.** Do **not** submit it or contact TRP3 maintainers without separate approval. Draft: [`trp3-upstream-proposal.md`](trp3-upstream-proposal.md). |
| 4 | **Automatic biography synchronisation remains a core long-term requirement.** Paste-assisted updates are an interim fallback, not the final experience. |
| 5 | **Implementation planning starts with v0.3 M1** (character foundations). The TRP3 write test follows once the foundation data model is ready. |
| 6 | **Before the personality system is finalised** (before v0.5 work starts), present the six leanings, nine moods and publication categories, with examples of how each affects prompts and public profile information |

**Standing requirements:**
- preserve the original TRP3 biography;
- never automatically expose private or secret information;
- keep personality changes gradual and grounded in player decisions;
- support characters with no TRP3 profile;
- avoid excessive prompts and complicated UI;
- keep the TRP3 integration modular, so newly supported APIs slot in later.

**Implementation** of anything in this plan still needs explicit authorisation. The current detailed scope is [`../v0.3-m1-scope.md`](../v0.3-m1-scope.md).

## Documents

| # | Deliverable | File |
|---|---|---|
| 1 | Core product vision | [`../../VISION.md`](../../VISION.md) |
| 2 | System and data architecture | [`architecture.md`](architecture.md) |
| 3 | First-time setup wizard | [`setup-wizard.md`](setup-wizard.md) |
| 4 | Gameplay event feasibility matrix | [`event-feasibility.md`](event-feasibility.md) |
| 5 | Story prompt and decision engine | [`story-engine.md`](story-engine.md) |
| 6 | Character evolution model | [`evolution-model.md`](evolution-model.md) |
| 7, 8 | TRP3 3.4.1 compatibility matrix and synchronisation feasibility | [`trp3-sync.md`](trp3-sync.md) |
| 9, 10 | Roadmap, risks, limitations and first milestone | [`roadmap.md`](roadmap.md) |

## Evidence labels used throughout

| Label | Meaning |
|---|---|
| **S** | **Confirmed from source.** Read in the TRP3 3.4.1 source, in TRP3's upstream `main` (3.5.3), or in Blizzard's 1.15.9 (70003) interface code and generated API documentation. Not run in game. |
| **G** | **Confirmed in game** (L3) by the v0.1 or v0.2 acceptance tests |
| **F** | **Feasible but unverified.** The API exists, but behaviour (does it fire, when, with what data) has to be proven in game. |
| **X** | **Unsupported or not allowed:** not exposed to addons, or only possible by writing undocumented TRP3 internals, which this project rules out |

**Sources consulted (read-only):**
- the installed TRP3 3.4.1 (audited earlier);
- `Total-RP/Total-RP-3` `main` and its 3.5.0–3.5.3 release notes;
- the `Gethe/wow-ui-source` branch `classic_era`, which is exactly **1.15.9 (70003)**, your installed build: Blizzard's generated API documentation and their own Classic Era UI code.

None of it was copied into this repository.

## Key findings (summary)
1. **TRP3 has no supported way to change the biography (About), personality traits, misc fields, glances, or details such as age and residence**, in 3.4.1 or in upstream `main`. **S** The supported public setters cover: Currently, OOC info, first and last name, title, full title, icon, custom race, custom class and class colour, RP status, walk-up and roleplay experience, plus selecting an existing profile. **S**
2. Therefore **automatic sync is feasible for the "living" short fields**: Currently (what the character is going through now), title and full title. **S** for the API, **F** for behaviour. **Biography and trait updates need one player action per update** (a prepared paste into TRP3's own editor) **unless TRP3 gains a public API.** Proposing such an API upstream is the supported path; it is an outward-facing step that needs your approval.
3. **Most of the meaningful gameplay events are exposed in 1.15.9:**
   - levels, quest turn-ins (with quest ID), zone changes, deaths, instance entry;
   - encounter start, end and boss kill (with name and success);
   - reputation and skill changes (by comparing snapshots);
   - combat state, resting, taxi, cinematics and loading screens, which together let Dawnward pick safe moments.

   All are **S** as definitions. Only level-ups are **G**. Encounter events firing on Classic Era is **F** and must be checked in game.
4. **New risk:** 1.15.9 contains "secret value" infrastructure (`issecretvalue`) and `C_CombatLog.IsCombatLogRestricted`. **S** TRP3 3.5.2 and 3.5.3 fixed errors caused by secret names during instance encounters, so Dawnward must not depend on unit names or combat-log details during encounters.
5. **Without AI**, a curated, conditioned and weighted template library can produce varied, personal prompts and a readable, somewhat formulaic biography draft. It cannot produce unrestricted prose, and the plan doesn't promise it.
