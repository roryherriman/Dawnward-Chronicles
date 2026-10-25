# Dawnward Chronicles

**An in-game storytelling engine for World of Warcraft roleplayers.** It keeps a journal of your character's real adventures, offers you roleplay decisions, grows their personality only with your approval, and shares the parts you choose with [Total RP 3](https://github.com/Total-RP/Total-RP-3).

> **Status: pre-alpha.** v0.2.0 (the journal window) has passed its in-game acceptance checklist on Classic Era. There is no published release yet. See the [roadmap](#roadmap).

## Using Dawnward (v0.2, pre-release)

Type `/dawnward` (or `/dwc`) to open your journal. It has three sections:

- **Journal:** write entries in your character's voice. Level-ups are added automatically.
- **Character:** your profile, family and history.
- **Story:** where story decisions will appear in a future version.

The gear icon holds the settings: your journal's theme (Neutral, Silver Hand or Arcane), backup and import, simulation mode, and the Total RP 3 status. Everything you write is **private** until you mark it otherwise.

Slash commands remain for quick changes and troubleshooting:

| Command | What it does |
|---|---|
| `/dawnward status` | Diagnostic report (version, client, saved data, Total RP 3) |
| `/dawnward journal add Arrived in Goldshire` | Adds a journal entry. Use `journal list`, `journal edit <#> <text>`, `journal vis <#> public`, `journal remove <#> confirm`. |
| `/dawnward theme arcane` | Changes this character's journal theme (appearance only) |
| `/dawnward set name Aelin Brightwater` | Sets a profile field. `/dawnward fields` lists them all. |
| `/dawnward vis name public` | Sets a field's visibility to `public`, `private` or `secret` |
| `/dawnward family add mother Ilsa` | Adds a family member. Use `family list`, `family set <#> status deceased`, `family vis <#> secret`. |
| `/dawnward history add Took the oath` | Adds a history entry. Use `history set <#> when Year 12`. |
| `/dawnward show` / `show public` | Shows your full profile, or only what could ever be shared |
| `/dawnward export backup` | Opens a window with a personal backup (private facts, no secrets). Add `secrets` to include them. |
| `/dawnward export share` | Exports public facts only |
| `/dawnward import` | Paste a backup, press **Check**, then **Import**. `/dawnward import undo` reverts it. |
| `/dawnward sim on` / `off` | Simulation mode: experiment on separate test data. `sim levelup <n>` adds a simulated level-up. |
| `/dawnward trp3` | Total RP 3 status. Dawnward never changes your TRP3 profile unless you turn on the experimental sync below. |

**In development (v0.3.0-dev, not yet tested in game):**

| Command | What it does |
|---|---|
| `/dawnward fact add belief Protect the weak` | Adds a fact to your character's canon (private). Use `fact list`, `fact vis <#> public`, `fact remove <#> confirm`. |
| `/dawnward personality set courage 15` | Sets a personality axis (0–20). Use `personality list`, `personality vis <axis> public`. |
| `/dawnward trp3 help` | **Experimental, off by default:** keeps a Dawnward "Chronicle" section and Dawnward personality traits up to date in your own Total RP 3 profile (TRP3 3.4.1, never the default profile). Backed up before every write; `trp3 rollback confirm` undoes it. Try it on a spare TRP3 profile first. |

Anything that deletes or replaces data asks you to add `confirm`.

## What it will do

| Feature | Description |
|---|---|
| Character profile & family history | A universal model for any race, class, background or motivation. Nothing about a particular character is hardcoded. |
| Adventure journal | Records milestones that actually happened in game, such as levels, quests, first visits to a zone and boss kills. Events are never invented, and the journal's size is capped. |
| Story decisions | On-screen roleplay choices, held back while you are in combat or another unsafe UI state. |
| Personality development | Decisions *propose* trait changes. Nothing changes until you approve it. |
| Total RP 3 sync | Shares only information you have marked **public**. It never touches profile content Dawnward didn't create, and it makes a backup first. |
| Export / import | Versioned saved data with migrations, plus a text export you can back up. |
| Simulation mode | Lets you try story content on test data that is kept separate from your real character. |

## Principles

- **The player is in control.** Every personality change needs approval, and writing to Total RP 3 is opt-in.
- **Private stays private.** Each fact about your character is `public`, `private` or `secret`, and only `public` facts can leave Dawnward.
- **Honest testing.** Every claim says whether it was checked statically, unit-tested, mock-tested or verified in game.
- **Light on the client.** It reacts to game events instead of polling, does no heavy work in combat, and keeps saved data bounded.
- **Separate layers.** A pure-Lua core sits apart from the client-specific adapters and the Total RP 3 adapter.

## Compatibility

See [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) for the live matrix and [`docs/TESTING.md`](docs/TESTING.md) for in-game results.

| Target | Role | Status |
|---|---|---|
| WoW Classic Era 1.15.9 | Primary development client | v0.2 passed its in-game acceptance checklist (all mandatory items). UI scaling untested. |
| WoW Forever 1.60.1 | Final deployment target | Provisional. Its adapter is isolated until it can be tested. |
| Total RP 3 3.4.1 | Integration target | Source audited. Read-only status and coexistence tested in game; Dawnward never writes to it. |
| Total RP 3 3.5.3 | Intended Forever version | Not yet audited or tested |

Total RP 3 is optional. Dawnward works without it.

### About Total RP 3 biography sync
Total RP 3 3.4.1 has public setters for small fields such as Currently, OOC, names and titles, but **none for the About/biography page or personality traits**. Until a safe, version-checked approach has been tested, Dawnward will create biography and trait text for you to paste into Total RP 3's own editor. Automatic sync is a long-term goal, and [`docs/TRP3_INTEGRATION.md`](docs/TRP3_INTEGRATION.md) explains the limitation and the research plan.

## Roadmap

> A revised plan for v0.3–v0.6, the **Living Character System**, is under review: [`docs/VISION.md`](docs/VISION.md) and [`docs/planning/living-character/`](docs/planning/living-character/). The table below is the original roadmap.

| Version | Milestone |
|---|---|
| 0.1 | Foundation: saved data and migrations, character and family-history model, export/import, simulation mode, read-only Total RP 3 detection |
| 0.2 | Milestone journal and a simple themed journal window (Journal, Character, Story). See [UI direction](docs/UI_DIRECTION.md). |
| 0.3 | Story decision popups and combat-safe queue |
| 0.4 | Personality proposals and approval ledger |
| 0.5 | Total RP 3 sync: public setters (opt-in) and copy-and-paste export, with backup and rollback |
| Later | Forever adapter, Total RP 3 3.5.3 support, and research into automatic biography sync |

## Development

```bash
python tools/check.py
```

This runs the hygiene check, luacheck and the Lua 5.1 tests. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup, and [`docs/`](docs/) for architecture, testing and workflow.

## Licence

Original code is released under the [MIT licence](LICENSE). See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for third-party software and trademarks.

<sub>Fan-made project. Not affiliated with or endorsed by Blizzard Entertainment or the Total RP 3 authors. World of Warcraft is a trademark of Blizzard Entertainment, Inc.</sub>
