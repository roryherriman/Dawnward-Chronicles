<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/branding/png/dawnward-lockup-dark.png">
  <img src="assets/branding/png/dawnward-lockup-light.png" alt="Dawnward Chronicles" width="560">
</picture>

### *A living chronicle for your World of Warcraft character*

**Total RP 3 tells the world who your character is.<br>Dawnward Chronicles helps you discover who they become.**

[How it works](#how-it-works) · [Features](#features) · [Install](#installation) · [Getting started](#getting-started) · [Status](#development-status) · [Docs](#documentation)

[![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange)](#development-status)
[![Client: Classic Era 1.15.9](https://img.shields.io/badge/client-Classic%20Era%201.15.9-blue)](docs/COMPATIBILITY.md)
[![WoW Forever: pending verification](https://img.shields.io/badge/WoW%20Forever-pending%20verification-lightgrey)](docs/COMPATIBILITY.md)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-green)](LICENSE)

</div>

---

Dawnward Chronicles is a standalone roleplaying companion for World of Warcraft Classic Era. It keeps a living journal of your character: who they are, where they have been, what they remember and what they want. A quiet Story Director notices what your character actually does in the game and, now and then, asks how it affected them. Your answers, never the addon, shape your character over time.

**The problem it solves:** a roleplay profile describes a character at one moment, but characters change through what they live through. Dawnward connects your real adventures (quests, places, levels, close calls) to your character's story, and keeps that story private until you choose to share it. [Total RP 3](https://github.com/Total-RP/Total-RP-3) remains the public face of your character; Dawnward is where they grow.

It works for **every class, race and faction**. Class never decides personality, and nothing assumes your character is heroic, religious or loyal to anyone.

> **Status: pre-alpha, no public release.** See [Development status](#development-status) for what is designed, what is implemented, what is still in development and what has been verified in game.

![Journal dashboard (design concept)](docs/design/mockups/journal-dashboard.png)

<sub>**Design concept, not an in-game screenshot.** This is the approved visual direction for the redesigned interface, and the in-game interface is being built towards it in stages. The character, entries and places shown are invented sample data for the mockup, not game lore.</sub>

## Features

- **Living character journal:** a journal of what your character did and felt. Level-ups and other verified events are recorded automatically. Story drafts come from your answers, and you can write your own entries, edit them, approve them and mark defining moments.
- **Character profiles:** name, title, pronouns, homeland, faith, appearance, summary, motivation and more. Every field is **Private**, **Public** or **Secret**, and only what you make public can ever leave Dawnward.
- **Story Director:** optional, paced questions at calm moments, never in combat. You can answer, write your own words, keep a moment for later or dismiss it. Pacing follows **gameplay time** (time you actually play), so the story moves with your play and not with the calendar.
- **Memories and meaningful moments:** memories linked to what happened and where, suggested memories you accept or reject, and defining moments.
- **Goals and personal development:** six personality axes that change only when you approve, one step at a time and always reversible. Also long-term arcs, and personal goals with verified progress such as level targets and reputation.
- **Places and travel history:** where your character has been, with starting areas, settlements and capitals recognised from the game's own data. Mark the places that matter or set your Homeland; returning after real time away (in play) can become a moment.
- **Family and relationships:** family members, people your character knows (NPCs and other players' characters), with private feelings, and a public persona kept apart from private convictions.
- **First-time setup:** a six-step guided setup for a new character (Welcome, Character, Story, Privacy, Appearance, Finish), which you can resume, skip or rerun at any time.
- **Optional Total RP 3 integration:** Dawnward works fully without Total RP 3. With it, an experimental, opt-in sync keeps a Dawnward-owned part of your TRP3 profile up to date from **public** information only. It previews every change, backs up before writing, can roll back, and never overwrites what you wrote yourself.

## Visual previews (design concepts)

These are the approved designs that the in-game interface is being built towards. **They are concepts, not screenshots.** Real in-game screenshots will replace them once the interface has been implemented and checked in game.

| Character | Story |
|---|---|
| ![Character (concept)](docs/design/mockups/character-profile.png) | ![Story Director (concept)](docs/design/mockups/story-director.png) |
| **Chronicle** | **First-time setup** |
| ![Chronicle: Memories (concept)](docs/design/mockups/chronicle-memories.png) | ![First-time setup (concept)](docs/design/mockups/first-time-setup.png) |

The complete gallery, with Places, the design system, two proposals still awaiting approval (Total RP 3 sync and the Character Showcase) and the sources the images were rendered from, is in [`docs/design/mockups`](docs/design/mockups/README.md).

## Built to complement Total RP 3, not replace it

We believe [Total RP 3](https://github.com/Total-RP/Total-RP-3) is an essential part of the WoW roleplaying community. Dawnward is not here to compete with it: TRP3 presents your character to the world, and Dawnward helps you discover who that character becomes.

- **TRP3 remains your public profile.** Dawnward focuses on development, memories and storytelling. It is not a profile system.
- **Fully usable without TRP3.** Nothing in Dawnward requires it.
- **Sync is optional and yours to control.** It is opt-in per character and per TRP3 profile, and only writes after you approve a preview.
  - **What it writes:** only public information, and only into a section Dawnward owns.
  - **Before and after each write:** it backs up first, reads the result back, and undoes the write at once if anything differs.
  - **Conflicts:** it stops and asks when you have edited something in TRP3.
  - **Never shared:** private and secret information.
- **An independent companion project,** not an official TRP3 extension, and not affiliated with or endorsed by the Total RP 3 authors, to whom we are grateful.

## How it works

```
  You play            a quest is turned in, a level reached, a place revisited
     |                (only what the game verifiably reports)
     v
  A quiet question    "How did it sit with them?" at a calm moment, never in combat
     |                answer, write your own, keep it for later, or dismiss it
     v
  Your decision       may propose a small personality change (one step on a 0-20 axis)
     |                applied only when you approve it, always reversible
     v
  The journal         a private draft: what happened, where, how they responded
     |
     v
  Your choice         approve it, mark it defining, make it public, and, if you
                      turned sync on, preview and approve it for Total RP 3
```

Two players completing identical content will develop different characters, because the story comes from **their** choices.

## Development status

Four separate things, never mixed up:

| | What it covers | Where |
|---|---|---|
| 🎨 **Approved designs** | The visual direction for the next interface: journal, character, story, chronicle memories and places, first-time setup, design system (approved 2026-10-29) | [`docs/design/mockups`](docs/design/mockups/README.md) |
| 🧪 **Implemented, automated tests only** | Everything in the table below marked 🧪: code exists and passes the automated suite, but is not yet checked in game | `python tools/check.py` |
| 🚧 **In development** | Rebuilding each section to match the approved designs (the new window shell, character rail and Character Showcase are in place; section layouts are next), the Total RP 3 sync screen, the redesigned setup wizard | [`docs/design/UI_DESIGN_V07.md`](docs/design/UI_DESIGN_V07.md) |
| ✅ **Verified in game** | Only what has passed a recorded in-game check on Classic Era | [`docs/TESTING.md`](docs/TESTING.md) |

| Version | Scope | Verification |
|---|---|---|
| **0.1** | Saved data and migrations, profile and family history, export and import, simulation mode, read-only TRP3 detection | ✅ in game, Classic Era 1.15.9 |
| **0.2** | Journal window, level-up milestones, themes | ✅ in-game acceptance checklist, Classic Era |
| **0.3 to 0.5** (merged) | Facts and personality axes, the living chronicle (events, story moments, decisions, personality evolution, story journal), memories, arcs, goals, persona and convictions, people, world events, places and origins, forms, minimap button, guide, Zone Atlas | 🧪 automated; in-game checklists partly reported. The Zone Atlas checks (66 of 66 IDs matching the 1.15.9 client) passed in game |
| **0.6** (draft PR [#54](https://github.com/roryherriman/Dawnward-Chronicles/pull/54)) | First design system and themes (Classic Dawnward, Lightbound, Shadowbound), first-time setup wizard, keyboard navigation, inline validation, entry rows, developer diagnostics | 🧪 automated; [in-game checklist](docs/TESTING.md) not yet run |
| **0.7-dev** (this development branch) | Gameplay-time Story Director (returns and cooldowns count play, never time offline), the approved mockups, the new window shell with a permanent character rail, the Character Showcase (live 3D model), bundled fonts | 🧪 automated; [in-game checklist](docs/TESTING.md) parts Q and R pending |
| **Release gate** | WoW Forever compatibility and launch readiness | 🗺️ [#24](https://github.com/roryherriman/Dawnward-Chronicles/issues/24), not started |

### Compatibility

| Target | Status |
|---|---|
| WoW Classic Era 1.15.9 | Primary development client. v0.2 verified in game. Later APIs are checked against Blizzard's 1.15.9 interface source and await in-game verification. |
| WoW Forever | **Pending verification.** Nothing has been tested on a Forever client, and no compatibility is claimed. |
| Total RP 3 3.4.1 | Read-only status verified in game. The experimental sync is source-audited and tested against a mock only. |
| Total RP 3, other versions | Read-only status only; sync refuses versions not on its list. |

Live details: [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) and [`docs/TESTING.md`](docs/TESTING.md).

## Installation

Dawnward is not yet published on an addon site. To try a development build:

1. Close World of Warcraft completely.
2. Back up `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua`.
3. Build a zip with `python tools/package.py` (or download this repository), and copy the **`DawnwardChronicles`** folder into your AddOns folder:

   ```
   World of Warcraft\_classic_era_\Interface\AddOns\DawnwardChronicles\DawnwardChronicles.toc
   ```

   The folder name must be exactly `DawnwardChronicles`.
4. *(Optional)* Install [Total RP 3](https://github.com/Total-RP/Total-RP-3) separately.
5. Start the game, enable **Dawnward Chronicles** in the AddOns list, and type `/dawnward`.

| Requirement | |
|---|---|
| Game client | WoW Classic Era 1.15.9 (interface 11509) |
| Dependencies | None. Total RP 3 is an optional companion. |

## Getting started

1. **Open Dawnward** with `/dawnward` or the minimap button. A new character is offered the first-time setup; everything you add starts **private**.
2. **Add who they are:** in the Character section, or with commands such as `/dawnward set name <name>` and `/dawnward personality set courage 6`.
3. **Play.** Story moments start once a character has a Dawnward profile, so your other characters are never recorded. A waiting moment shows one chat line and a small card, never in combat.
4. **Review your development:** approve or reject proposed personality changes in the Story section.
5. **Curate your chronicle:** in the Journal, edit drafts, approve them, mark defining moments, and make public only what you want others to see.
6. **Try it safely first:** `/dawnward sim on` uses separate test data; your real data is untouched.

### Total RP 3 sync (experimental, opt-in)

Use a **spare, non-default TRP3 profile** first. `/dawnward trp3 help` lists the commands:
- `trp3 preview` shows exactly what would change, without writing;
- `trp3 enable about confirm` turns biography sync on;
- `trp3 rollback confirm` undoes the last write.

Sync is allowlisted for TRP3 3.4.1, never writes in combat or while TRP3's editor holds unsaved changes, and never publishes private or secret information. See [`docs/TRP3_INTEGRATION.md`](docs/TRP3_INTEGRATION.md).

## Customisation

| Option | Where | Choices |
|---|---|---|
| Theme (appearance only) | Settings → General | Classic Dawnward (default), Lightbound, Shadowbound, plus Neutral, Silver Hand and Arcane |
| How often moments appear | Settings → Story, or `/dawnward story set frequency` | off, rare, normal (default), frequent |
| Story pace (how much play makes a narrative day) | Settings → Story, or `/dawnward story set pace` | brisk (1 h), standard (2 h, default), slow (4 h) |
| Place moments | Settings → Story | on, fewer, off |
| Personality approval | Settings → Story | ask (default), auto (still reversible) |
| TRP3 section style | Settings → Story | Neutral (default), Silver Hand, Arcane |

## Principles

- **The player is the author.** Nothing changes your character without your approval; you can always postpone, dismiss, edit, reject or reverse.
- **Universal.** No class, race, faction or morality is assumed.
- **Private by default.** Suggestions and drafts are private, and secrets stay secret. Only what you approve and make public can leave Dawnward.
- **Verified, not invented.** Events record only what the game reports. Dawnward never invents quest plots, places, people or outcomes.
- **Time you play, not time away.** Story pacing counts gameplay only, and nothing in your history changes just because time passes.
- **Never speaks for you.** Dawnward never sends chat, emotes or whispers.
- **Light on the client.** Event-driven, nothing heavy in combat, nothing rendered while the journal is closed, and bounded saved data.

## Contributing and bug reports

- **Bugs:** open a [bug report](https://github.com/roryherriman/Dawnward-Chronicles/issues/new/choose). Include your game version, Dawnward version (`/dawnward status`) and any Lua error.
- **Compatibility results:** use the compatibility report template. Real in-game results are especially valuable.
- **Code:** see [`CONTRIBUTING.md`](CONTRIBUTING.md). Run the checks before a pull request:

  ```bash
  python tools/check.py   # hygiene, TOC, luacheck, the Lua 5.1 test suite and the atlas tools
  ```

## Documentation

| | |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Layers, saved data, UI, Story Director weighting, the narrative clock |
| [UI design v0.7](docs/design/UI_DESIGN_V07.md) · [mockups](docs/design/mockups/README.md) | The approved visual direction and the build stages |
| [Testing](docs/TESTING.md) | Automated levels and the in-game checklists |
| [Compatibility](docs/COMPATIBILITY.md) | Every client API used, with its evidence |
| [Zone Atlas](docs/ZONE_ATLAS.md) | Place data, evidence levels and `/dawnward atlas` |
| [Privacy](docs/PRIVACY.md) · [Vision](docs/VISION.md) | What stays private, and why Dawnward exists |
| [TRP3 integration](docs/TRP3_INTEGRATION.md) | The experimental sync and its safeguards |
| [Brand guide](docs/BRANDING_GUIDE.md) | Logo, palette and typography (proposal) |

## Licence and credits

Original code is released under the [MIT licence](LICENSE). The bundled fonts, Cinzel and Alegreya Sans, are under the SIL Open Font License 1.1 (`DawnwardChronicles/Media/Fonts`). See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

**Thanks to the [Total RP 3](https://github.com/Total-RP/Total-RP-3) team** (Apache-2.0) for the profile system that so much of the WoW roleplaying community relies on. Dawnward includes none of TRP3's code or assets; it talks to TRP3 only in game, where you enable it.

<sub>Fan-made project. Not affiliated with or endorsed by Blizzard Entertainment or the Total RP 3 authors. World of Warcraft is a trademark of Blizzard Entertainment, Inc.</sub>
