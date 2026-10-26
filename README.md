<div align="center">

# 📜 Dawnward Chronicles

### *A living chronicle for your World of Warcraft character*

**Total RP 3 tells the world who your character is.<br>Dawnward Chronicles helps you discover who they become.**

[![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange)](#development-status)
[![Client: Classic Era 1.15.9](https://img.shields.io/badge/client-Classic%20Era%201.15.9-blue)](docs/COMPATIBILITY.md)
[![WoW Forever: pending verification](https://img.shields.io/badge/WoW%20Forever-pending%20verification-lightgrey)](docs/COMPATIBILITY.md)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-green)](LICENSE)

</div>

---

Dawnward Chronicles is a roleplaying companion addon. It notices what your character actually does in the game (quests turned in, levels reached, deaths survived) and turns some of those moments into quiet, optional questions: *how did that affect them?* Your answers, never the addon, shape your character's personality over time. They become entries in a private journal you can edit, approve and choose to share.

It works for **every class, race and faction**. A compassionate Warlock, a ruthless Paladin, a sceptical Priest and an honourable Rogue are all equally valid: class never decides personality, and nothing assumes your character is heroic, religious or loyal to anyone.

> **Status: pre-alpha, no public release yet.** v0.2 (the journal window) passed its in-game acceptance checklist on Classic Era. v0.3 and v0.4 are in development and verified by automated tests only. See [Development status](#development-status).

## Built to Complement Total RP 3 — Not Replace It

Dawnward Chronicles was created with one goal: to make roleplaying in World of Warcraft feel more alive.

We believe [Total RP 3](https://github.com/Total-RP/Total-RP-3) is an essential part of the WoW roleplaying community, and Dawnward is not here to compete with it or replace what it already does so well. Instead, Dawnward is designed to work alongside TRP3. It adds another layer of immersion by connecting your adventures, decisions, relationships and experiences to your character's evolving story.

While TRP3 gives you the tools to present your character to the world, Dawnward helps you discover who that character becomes along the way. Together, they can create a richer and more personal roleplaying experience.

- **TRP3 remains your public profile.** Dawnward focuses on development, memories and storytelling; it is not a profile system.
- **Dawnward is an independent companion project**, not an official TRP3 extension. It is not affiliated with or endorsed by the Total RP 3 authors, to whom we are grateful for their work.
- **The integration is optional and yours to control.** Dawnward works without TRP3. Writing to TRP3 is an experimental, opt-in feature: it changes only a section Dawnward created, backs up first, can be rolled back, and never touches what you wrote yourself.

## How it works

```
  ⚔️  You play          A quest is turned in, a level reached, a fall survived
        │                (only what the game verifiably reports)
        ▼
  💭  A quiet question  "How did it sit with them?" — at a calm moment, never in combat
        │                answer, write your own, keep it for later, or dismiss it
        ▼
  🧭  Your decision     proposes a small personality change (one step on a 0–20 axis)
        │                applied only when you approve it, always reversible
        ▼
  📖  The journal       a private draft in your character's chronicle: what happened,
        │                where, how they responded, what it may mean
        ▼
  🌐  Your choice       approve it, mark it a defining moment, make it public —
                         and, if you turned sync on, it appears in your TRP3 profile
```

Two players completing identical content will develop different characters, because the story comes from **their** choices.

## Features

Every feature is marked with the highest verification it has reached: ✅ **verified in game**, 🧪 **automated tests only** (awaiting in-game verification), 🚧 **experimental** (opt-in), 🗺️ **planned**.

| Feature | What it does | Status |
|---|---|---|
| **Journal window** | `/dawnward` opens a themed journal with Journal, Character and Story sections | ✅ v0.2 |
| **Character profile** | Name, title, race, class, faith, motivation and more; family and history; every item is public, private or secret | ✅ v0.2 |
| **Automatic milestones** | Level-ups recorded with time and place | ✅ v0.2 |
| **Backups and sharing** | Personal backups (private data, secrets on request) and share exports (public only), with an import undo | ✅ v0.2 |
| **Simulation mode** | Experiment on separate test data; real data is untouched | ✅ v0.2 |
| **Character canon** | Facts (origin, beliefs, fears, relationships…) and six personality axes: Courage, Compassion, Discipline, Faith (any belief or worldview, not one religion), Honour, Sociability | 🧪 v0.3 |
| **Gameplay events** | Quest turn-ins, deaths and level-ups become normalised records with time, place, verified details and confidence; never recorded twice | 🧪 v0.4 |
| **Story moments** | Authored, universal questions with answers in different moral and emotional directions, your own words, Later / Not now / Dismiss; paced and never shown in combat | 🧪 v0.4 |
| **Personality evolution** | Answers propose one-step changes; you approve, reject or reverse them; your own starting values are kept; daily limit | 🧪 v0.4 |
| **Living journal** | Private story drafts from what happened and how you answered; edit, approve, mark defining moments, search | 🧪 v0.4 |
| **TRP3 Chronicle sync** | Keeps a Dawnward-owned section of your TRP3 About page and Dawnward-owned personality traits up to date from **public** information only; backup, rollback, conflict and editor protection | 🚧 v0.3–v0.4, TRP3 3.4.1 only |
| **TRP3 presentation styles** | Neutral (default), Silver Hand and Arcane formatting for Dawnward's section, using only TRP3-supported markup | 🚧 🧪 v0.4 |
| **More events** | Exploration, dungeons and bosses, reputation | 🗺️ [#11](https://github.com/roryherriman/Dawnward-Chronicles/issues/11), [#18](https://github.com/roryherriman/Dawnward-Chronicles/issues/18) |
| **Arcs, goals and memory** | Long-term arcs, personal goals, context-aware storytelling | 🗺️ [#12](https://github.com/roryherriman/Dawnward-Chronicles/issues/12), [#19](https://github.com/roryherriman/Dawnward-Chronicles/issues/19), [#20](https://github.com/roryherriman/Dawnward-Chronicles/issues/20), [#25](https://github.com/roryherriman/Dawnward-Chronicles/issues/25), [#27](https://github.com/roryherriman/Dawnward-Chronicles/issues/27) |
| **Relationships and identity** | Player relationships, guilds, family trees, affiliations, public persona vs private convictions | 🗺️ [#28](https://github.com/roryherriman/Dawnward-Chronicles/issues/28), [#30](https://github.com/roryherriman/Dawnward-Chronicles/issues/30), [#33](https://github.com/roryherriman/Dawnward-Chronicles/issues/33), [#36](https://github.com/roryherriman/Dawnward-Chronicles/issues/36), [#37](https://github.com/roryherriman/Dawnward-Chronicles/issues/37) |
| **Immersive journal redesign** | A resizable, customisable fantasy journal | 🗺️ [#17](https://github.com/roryherriman/Dawnward-Chronicles/issues/17) |

> No screenshots yet: they will be added from real in-game captures once the v0.4 interface has been verified in game.

## Installation

Dawnward is not yet published on an addon site. To try a development build:

1. Close World of Warcraft completely.
2. Download this repository (or a zip built with `python tools/package.py`) and copy the **`DawnwardChronicles`** folder into your AddOns folder:

   ```
   World of Warcraft\_classic_era_\Interface\AddOns\DawnwardChronicles\DawnwardChronicles.toc
   ```

   The folder name must be exactly `DawnwardChronicles`.
3. *(Optional)* Install [Total RP 3](https://github.com/Total-RP/Total-RP-3) separately. Dawnward works without it.
4. Before upgrading a development build, back up `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua`.
5. Start the game, enable **Dawnward Chronicles** in the AddOns list, and type `/dawnward`.

| Requirement | |
|---|---|
| Game client | WoW Classic Era 1.15.9 (interface 11509) |
| Dependencies | None. Total RP 3 is an optional companion. |

## Getting started

1. **Name your character:** `/dawnward set name <name>` (or the Character section). Everything you add is **private** until you change it.
2. **Add who they are:** facts with `/dawnward fact add belief Trusts no one`, personality with `/dawnward personality set courage 6`. Choose what is public with the visibility buttons or `vis` commands.
3. **Play.** When a moment is waiting, you will see one chat line and a small card, never in combat. Open it with **Answer**, or later from the **Story** section (`/dawnward story`).
4. **Review your development:** approve or reject proposed personality changes in the Story section (`/dawnward develop`).
5. **Curate your chronicle:** in the Journal, edit drafts, **Approve** them, mark defining moments with `*`, and make public only what you want others to see.
6. **Try it safely first:** `/dawnward sim on`, then `/dawnward sim quest 1 A Practice Quest`, uses separate test data.

### Total RP 3 sync (experimental, opt-in)

Use a **spare, non-default TRP3 profile** first. `/dawnward trp3 help` lists the commands. `trp3 preview` shows exactly what would change without writing; `trp3 enable about confirm` turns biography sync on; `trp3 rollback confirm` undoes the last write. Sync is allowlisted for TRP3 3.4.1, never writes in combat or while TRP3's editor holds unsaved changes, and never publishes private or secret information. See [`docs/TRP3_INTEGRATION.md`](docs/TRP3_INTEGRATION.md).

## Customisation

| Option | Where | Choices |
|---|---|---|
| Journal theme (appearance only) | Settings (gear) or `/dawnward theme` | Neutral (default), Silver Hand, Arcane: open to every character |
| How often moments appear | Settings > Moments, or `/dawnward story set frequency` | off, rare, normal (default), frequent |
| Which events may become moments | Settings > Significance | 1 (any) to 3 (major only) |
| Personality approval | Settings > Changes | ask (default), auto (still reversible) |
| Journal drafts, reaction card, class flavour | Settings | on / off |
| Event tracking | Settings > Quests, or `/dawnward story track <quest/levelup/death> on/off` | on / off |
| TRP3 section style | Settings > TRP3 style | Neutral (default), Silver Hand, Arcane |

## Development status

| Version | Scope | Verification |
|---|---|---|
| **0.1** | Saved data and migrations, profile and family history, export/import, simulation, read-only TRP3 detection | ✅ in game, Classic Era 1.15.9 |
| **0.2** | Journal window, level-up milestones, themes | ✅ in-game acceptance checklist, Classic Era |
| **0.3** (PR [#9](https://github.com/roryherriman/Dawnward-Chronicles/pull/9)) | Facts, personality axes, biography sources, experimental TRP3 sync | 🧪 automated; in-game checks in progress |
| **0.4** (PR [#43](https://github.com/roryherriman/Dawnward-Chronicles/pull/43)) | The living chronicle: events, moments, decisions, personality evolution, story journal, TRP3 presentation | 🧪 automated; [in-game checklist](docs/TESTING.md#v04-in-game-checklist-l3-the-living-chronicle) pending |
| **Next** | Expanded events, arcs and goals, relationships, journal redesign, import wizard | 🗺️ [open issues](https://github.com/roryherriman/Dawnward-Chronicles/issues) |
| **Release gate** | WoW Forever compatibility and launch readiness | 🗺️ [#24](https://github.com/roryherriman/Dawnward-Chronicles/issues/24), not started |

### Compatibility

| Target | Status |
|---|---|
| WoW Classic Era 1.15.9 | Primary development client. v0.2 verified in game; v0.3/v0.4 APIs checked against Blizzard's 1.15.9 interface source, awaiting in-game verification. |
| WoW Forever | **Pending verification.** Recognised provisionally; nothing has been tested on a Forever client. |
| Total RP 3 3.4.1 | Read-only status verified in game. Experimental sync is source-audited and mock-tested only. |
| Total RP 3 on other versions | Read-only status only; sync refuses unlisted versions. |
| Multiplayer TRP3 propagation | Not yet verified with real clients ([#7](https://github.com/roryherriman/Dawnward-Chronicles/issues/7), [#15](https://github.com/roryherriman/Dawnward-Chronicles/issues/15)). |

Live details: [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) and [`docs/TESTING.md`](docs/TESTING.md).

## Principles

- **The player is the author.** Nothing changes your character without your approval; you can always postpone, dismiss, edit, reject or reverse.
- **Universal.** No class, race, faction or morality is assumed. Kyssarra Dawnward is a test character, not a template.
- **Private by default.** Generated suggestions and drafts are private; secrets stay secret; only what you approve and make public can leave Dawnward.
- **Verified, not invented.** Events record only what the game reports. Dawnward never invents quest plots, enemies or outcomes.
- **Never speaks for you.** Dawnward never sends chat, emotes or whispers.
- **Light on the client.** Event-driven, no polling, nothing heavy in combat, bounded saved data.

## Contributing and bug reports

- **Bugs:** open a [bug report](https://github.com/roryherriman/Dawnward-Chronicles/issues/new/choose). Include your game version, Dawnward version (`/dawnward status`) and any Lua error.
- **Compatibility results:** use the compatibility report template. Real in-game results are especially valuable.
- **Ideas:** open a feature request.
- **Code:** see [`CONTRIBUTING.md`](CONTRIBUTING.md). Run the checks before a pull request:

  ```bash
  python tools/check.py   # hygiene, TOC, luacheck and the Lua 5.1 test suite
  ```

Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) · Vision: [`docs/VISION.md`](docs/VISION.md) · Privacy: [`docs/PRIVACY.md`](docs/PRIVACY.md)

## Licence and credits

Original code is released under the [MIT licence](LICENSE). See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

**Thanks to the [Total RP 3](https://github.com/Total-RP/Total-RP-3) team** (Apache-2.0) for the profile system that so much of the WoW roleplaying community relies on. Dawnward includes none of TRP3's code or assets; it talks to TRP3 only in-game, where you enable it.

<sub>Fan-made project. Not affiliated with or endorsed by Blizzard Entertainment or the Total RP 3 authors. World of Warcraft is a trademark of Blizzard Entertainment, Inc.</sub>
