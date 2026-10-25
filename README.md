# Dawnward Chronicles

**An in-game storytelling engine for World of Warcraft roleplayers.** It keeps a journal of your character's real adventures, offers you roleplay decisions, grows their personality only with your approval, and shares the parts you choose with [Total RP 3](https://github.com/Total-RP/Total-RP-3).

> **Status: pre-alpha. There is no installable release yet.**
> This repository currently holds the project foundation: architecture, compatibility research, tooling and tests. The first addon build will be v0.1.0. See the [roadmap](#roadmap).

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

Nothing has been verified in game yet. See [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) for the live matrix.

| Target | Role | Status |
|---|---|---|
| WoW Classic Era | Primary development client | Planned for v0.1 |
| WoW Forever 1.60.1 | Final deployment target | Provisional. Its adapter is isolated until it can be tested. |
| Total RP 3 3.4.1 | Integration target | Source audited. Not yet tested in game. |
| Total RP 3 3.5.3 | Intended Forever version | Not yet audited or tested |

Total RP 3 is optional. Dawnward works without it.

### About Total RP 3 biography sync
Total RP 3 3.4.1 has public setters for small fields such as Currently, OOC, names and titles, but **none for the About/biography page or personality traits**. Until a safe, version-checked approach has been tested, Dawnward will create biography and trait text for you to paste into Total RP 3's own editor. Automatic sync is a long-term goal, and [`docs/TRP3_INTEGRATION.md`](docs/TRP3_INTEGRATION.md) explains the limitation and the research plan.

## Roadmap

| Version | Milestone |
|---|---|
| 0.1 | Foundation: saved data and migrations, character and family-history model, export/import, simulation mode, read-only Total RP 3 detection |
| 0.2 | Milestone journal |
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
