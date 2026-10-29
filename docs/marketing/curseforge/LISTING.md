# CurseForge listing: Dawnward Chronicles (WoW Forever), prepared and NOT published

Prepared for issue [#44](https://github.com/roryherriman/Dawnward-Chronicles/issues/44). Nothing here has been posted to CurseForge. See [`docs/handoffs/CURSEFORGE_STATUS.md`](../../handoffs/CURSEFORGE_STATUS.md) for the project's status, and [`PUBLICATION_CHECKLIST.md`](PUBLICATION_CHECKLIST.md) for what must happen before anything is created.

All feature claims below match the repository at the time of writing. Labels:

- **In game (Classic Era):** verified in game on Classic Era.
- **Automated tests:** passes the automated suite, not yet verified in game.
- **Experimental:** opt-in.
- **Planned:** not built.

**Nothing has been tested on WoW Forever.**

---

## Project settings (to enter when the owner creates the project)

| Field | Value |
|---|---|
| Game | World of Warcraft |
| Game flavour / version | **WoW Forever, 1.60.1** (CurseForge lists Forever addons under game version 1.60.1; see Sources). Do **not** choose Retail or Classic Era as a substitute. |
| Project name | Dawnward Chronicles |
| Summary (short description, one line) | A living chronicle for your character: your adventures, your choices, who they become. A companion to Total RP 3. |
| Primary category | Roleplay |
| Additional categories | Quests & Leveling (records quest turn-ins as story moments); Chat & Communication is **not** appropriate (Dawnward never sends chat) |
| Dependencies | **Optional:** Total RP 3. Do not mark it required: Dawnward works without it. |
| License | MIT (as in the repository's `LICENSE`) |
| Source / issues / wiki links | Source: https://github.com/roryherriman/Dawnward-Chronicles · Issues: https://github.com/roryherriman/Dawnward-Chronicles/issues |
| Release type for the first file | **Alpha** (never "Release" until the Forever release gate, issue #24, has passed) |

## Long description (CurseForge supports Markdown or WYSIWYG; paste as Markdown)

```markdown
# Dawnward Chronicles

**Total RP 3 tells the world who your character is. Dawnward Chronicles helps you discover who they become.**

Dawnward Chronicles is a roleplaying companion. It notices what your character actually does in the game (quests turned in, levels reached, falls survived, places reached, standings earned) and, at a calm moment, asks a quiet question: *how did that affect them?* Your answers, never the addon, shape their personality over time, and become entries in a private chronicle you can edit, approve and choose to share.

It works for every class, race and faction. A compassionate warlock, a ruthless paladin, a sceptical priest and an honourable rogue are all equally valid. Class never decides who your character is.

> ⚠️ **Alpha. WoW Forever compatibility has not been verified yet.** Dawnward is developed on WoW Classic Era 1.15.9. This Forever build has not been tested on a Forever client. Back up your SavedVariables and expect rough edges. Please report what you find.

## Built to complement Total RP 3, not replace it

Dawnward Chronicles was created with one goal: to make roleplaying in World of Warcraft feel more alive. Total RP 3 is an essential part of the WoW roleplaying community, and Dawnward is not here to compete with it or replace what it already does so well.

- **Its own profile, TRP3's public stage.** Dawnward Chronicles includes its own comprehensive character profile and storytelling tools, but it is not intended to replace Total RP 3's established public social roleplaying profile system. Dawnward helps players develop their characters through gameplay, while optional TRP3 integration lets them share approved public information with the broader roleplaying community.
- **Independent project.** Dawnward is not an official TRP3 extension and is not affiliated with or endorsed by the Total RP 3 authors. Thank you to the TRP3 team for their work.
- **Optional, opt-in integration.** Dawnward works without TRP3. If you turn it on, Dawnward keeps only *its own* section of your TRP3 profile up to date from information you approved and made public. It backs up first, can be rolled back, and never edits what you wrote yourself.

## How it works

1. **You play.** Dawnward records only what the game reports, and never invents quest plots, enemies or outcomes.
2. **A quiet question.** It appears at a calm moment and never in combat. Answer it, write your own answer, keep it for later or dismiss it.
3. **Your decision.** It proposes a small personality change, applied only when you approve it, and always reversible.
4. **The chronicle.** A private journal draft records what happened, where, how they responded, and what it may mean.
5. **Your choice to share.** Approve it, mark it a defining moment, and make it public if you wish.

## Features

| Feature | Status |
|---|---|
| Journal window (Journal, Character, Story, Chronicle) with themes | Journal window verified in game on Classic Era; newer sections pass automated tests |
| Character profile, family and history, each item public, private or secret | Verified in game on Classic Era |
| Personal backups and share exports | Verified in game on Classic Era |
| Story moments from quests, level-ups, deaths, first zone visits, dungeon entries, reputation tiers and guild changes | Automated tests |
| Personality evolution on six axes (you approve every change) | Automated tests |
| Memories, long-term arcs, personal goals, public persona vs private convictions, people your character knows | Automated tests |
| Continuity review (Dawnward points out contradictions and asks; it never rewrites your story) | Automated tests |
| TRP3 Chronicle section and personality traits (TRP3 3.4.1 only) | Experimental, opt-in |
| Immersive journal redesign, story import wizard, letters and alternate formats | Planned |

## Getting started

Type `/dawnward` to open the journal, or `/dawnward help` for commands. Everything you add is **private** until you change it. To try things safely first: `/dawnward sim on`.

## Privacy

- Generated suggestions and drafts are private.
- Secrets stay secret.
- Only what you approve and make public can ever leave Dawnward.
- Dawnward never sends chat, emotes or whispers.

## Support

Bug reports and ideas: https://github.com/roryherriman/Dawnward-Chronicles/issues. Please include `/dawnward status` output and any Lua error.
```

## Installation instructions (for the listing and the file description)

1. Close the game.
2. Use the CurseForge app, or extract the zip so that this file exists:
   `World of Warcraft\<Forever client folder>\Interface\AddOns\DawnwardChronicles\DawnwardChronicles.toc`.
   The Forever client folder name must be confirmed on a real Forever installation before publication.
3. Before updating, back up `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua`.
4. *(Optional)* Install Total RP 3 for WoW Forever separately.

## FAQ

**Does Dawnward replace Total RP 3?**
No. TRP3 is your public profile. Dawnward helps your character develop through play. They are designed to be used together, and Dawnward also works on its own.

**Will Dawnward change my TRP3 profile?**
Only if you turn on the experimental sync, and only Dawnward's own section and traits, from information you made public. It backs up first and can roll back. It never touches TRP3's default profile.

**Does my class decide my personality?**
Never. Class can add one optional, flavoured answer. Every character gets the same universal choices.

**Will it interrupt combat?**
No. Questions wait for a calm moment, and you can turn the card off or make moments rare.

**Does it use AI or the internet?**
No. Everything runs inside the game, from authored text and your own words.

**Is it compatible with WoW Forever?**
Not verified yet. It is built and tested on Classic Era 1.15.9. Forever testing is the final release gate.

## Changelog template (for each uploaded file)

```markdown
## Dawnward Chronicles <version> (<date>)

**Tested on:** <client and build, or "automated tests only">. **Total RP 3:** <version or "not tested">.

### Added
- …

### Changed
- …

### Fixed
- …

### Known issues
- …
```

## Media plan

Every screenshot must be a real in-game capture from a disposable test character. No fabricated or edited UI, and no Blizzard or TRP3 artwork beyond what appears naturally in a screenshot.

| # | Screenshot | Caption |
|---|---|---|
| 1 | The journal window, Story section, with a waiting moment and its answers | "After a quest: a quiet question, and answers that pull in different directions." |
| 2 | The reaction card at the top of the screen, out of combat | "Moments wait for a calm moment, never combat." |
| 3 | A story draft in the Journal with Approve and the defining-moment star | "Your answers become private drafts you approve and choose to share." |
| 4 | The Chronicle section (memories with provenance, status and visibility) | "Memories, arcs, goals: the player is always the author." |
| 5 | A disposable TRP3 profile's About page showing Dawnward's section below the player's own text | "Optional: only Dawnward's own section, from what you made public." |
| 6 | Settings: story moments and themes | "Rare or frequent, card or chat line: your choice." |

| Asset | Specification |
|---|---|
| Project icon (avatar) | Square PNG, at least 400 × 400 px. An original design: an open book or a sunrise over a horizon, warm gold on deep night. No Blizzard or TRP3 artwork. |
| Banner / header (optional) | Wide PNG or JPG (e.g. 1920 × 480), original artwork only, with the title and the tagline. |
| Screenshots | PNG or JPG, native resolution, UI scale noted in the caption file. |

## Sources (search results, 2026-10-26)

CurseForge pages could not be opened directly from the preparation environment, so these findings come from search results. The owner should confirm them in the CurseForge author console.

- Forever addons listed under game version 1.60.1:
  - [WoW Forever Addons](https://www.curseforge.com/wow/addons/wow-forever-addons)
  - [GearQuest Forever](https://www.curseforge.com/wow/addons/gearquest-forever)
  - [ForeverUI](https://www.curseforge.com/wow/addons/foreverui)
  - [Forever Move](https://www.curseforge.com/wow/addons/forever-move)
  - [CurseForge search filtered by `gameVersionTypeId=88568`](https://www.curseforge.com/wow/search?class=addons&page=1&pageSize=20&sortBy=latest+update&gameVersionTypeId=88568)
- Forever addons use Interface **16001** in their TOC:
  - [Resonance v1.14.0](https://www.curseforge.com/wow/addons/resonance/files/8935517)
  - [ForeverQuest](https://www.curseforge.com/wow/addons/foreverquest)
  - [Classic Portrait Forever](https://www.curseforge.com/wow/addons/classicportrait)
  - [TOGT file note on a wrong Interface line](https://www.curseforge.com/wow/addons/togt/files/8994308)
- Creating a project and moderation:
  - [Creating and Submitting a Project](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project)
  - [Project Statuses 101](https://support.curseforge.com/support/solutions/articles/9000197905-project-statuses-101)
  - [How To Become A CurseForge Author](https://blog.curseforge.com/how-to-become-a-curseforge-author/)
  - Community notes on moderation: [CF-I-6875](https://curseforge-ideas.overwolf.com/ideas/CF-I-6875) and [CF-I-5178](https://curseforge-ideas.overwolf.com/ideas/CF-I-5178)
