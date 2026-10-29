# CurseForge description: final draft (2026-10-27)

Ready to paste into the description field of the existing **unlisted** project (Markdown mode). It replaces the long description in [`LISTING.md`](LISTING.md); the settings, FAQ, changelog template and sources there still apply.

**Before pasting:**
- Check the status labels against the README.
- Keep the Forever warning unless release gate #24 has passed.
- Use only images from [`BRANDING_GUIDE.md`](BRANDING_GUIDE.md) and real screenshots.

---

```markdown
![Dawnward Chronicles](BANNER_URL_AFTER_UPLOAD)

**Total RP 3 tells the world who your character is. Dawnward Chronicles helps you discover who they become.**

Dawnward Chronicles is a roleplaying companion. It notices what your character really does in the game: the quests they turn in, the places they reach, the falls they survive. At a calm moment it asks a quiet question: *how did that sit with them?* Your answers, never the addon, shape who they become. They turn into memories, story arcs and a private chronicle that you edit, approve and choose to share.

It works for every class, race and faction. A compassionate warlock, a ruthless paladin and a sceptical priest are all equally valid. Dawnward never decides who your character is from what they are.

> ⚠️ **Alpha. WoW Forever compatibility has not been verified yet.** Dawnward is developed and tested on WoW Classic Era 1.15.9. Back up your SavedVariables, expect rough edges, and please report what you find.

## Built to complement Total RP 3, not replace it

Total RP 3 is an essential part of the WoW roleplaying community. Dawnward Chronicles includes its own comprehensive character profile and storytelling tools, but it is not intended to replace Total RP 3's established public social roleplaying profile system. Dawnward helps players develop their characters through gameplay, while optional TRP3 integration lets them share approved public information with the broader roleplaying community.

- **Independent.** Not an official TRP3 extension, and not affiliated with or endorsed by the Total RP 3 authors. Thank you to the TRP3 team.
- **Optional.** Dawnward works without TRP3. Its TRP3 sync is experimental and off by default. When you turn it on, it shares only what you made public, backs up first, never writes while TRP3's editor is open, and can be rolled back.

## How it works

1. **You play.** Dawnward records only what the game reports. It never invents quest plots, enemies or outcomes.
2. **A quiet question.** Some moments ask, and never in combat. A beginning always asks. Your homeland and the places, people and goals you care about weigh most. Ordinary travel is logged quietly.
3. **Your answer.** Pick an answer or write your own. It may suggest a small change in personality, which applies only if you approve it.
4. **Your chronicle.** A private draft records what happened and how your character responded. Edit it, mark defining moments, and make public only what you choose.

## Features

| Feature | Status |
|---|---|
| Journal window: Journal, Character, Story and Chronicle, with three themes | Tested in game (Classic Era) |
| Character profile, family and history; everything public, private or secret | Tested in game (Classic Era) |
| Story moments from quests, levels, falls, places, dungeons, reputation and guild changes | Tested in game (Classic Era) |
| Memories, story arcs, goals with milestones, people, public stances and private convictions | Tested in game (Classic Era) |
| Places and homeland: towns and inns logged as you travel; mark the ones that matter | Tested in game (Elwynn Forest) |
| Personality development on six axes; you approve every change | Tested in game (Classic Era) |
| Forms for every record in the window, a first-run guide, searchable help and a minimap button | New; automated tests only |
| Total RP 3 sync (TRP3 3.4.1) | Experimental, opt-in |
| Letters, scrapbook, dungeon boss moments | Planned |

## Getting started

Type `/dawnward` or click the minimap button. A short guide opens the first time; reopen it from the **?** button. Everything you add is **private** until you change it. To experiment safely, turn on simulation mode in Settings.

## Privacy

- Everything starts private. Secrets stay secret.
- Only what you approve and make public can leave Dawnward.
- Dawnward never sends chat, emotes or whispers, and uses no internet or AI.

## Support

Bugs and ideas: https://github.com/roryherriman/Dawnward-Chronicles/issues. Please include the `/dawnward status` output and any Lua error.

<sub>Fan-made project. Not affiliated with or endorsed by Blizzard Entertainment or the Total RP 3 authors. World of Warcraft is a trademark of Blizzard Entertainment, Inc.</sub>
```

---

**Accuracy notes for the owner:**
- "Tested in game" means **your** 2026-10-26 results on Classic Era 1.15.9 (docs/COMPATIBILITY.md, owner-reported). Nothing has been tested on WoW Forever.
- "Story moments … dungeons, reputation and guild changes": those three event types have not been tested in game individually (TESTING.md, part K). If you prefer to be strict, move them to "automated tests only".
- Replace `BANNER_URL_AFTER_UPLOAD` with the image URL CurseForge gives after you upload the banner, or delete that line.
