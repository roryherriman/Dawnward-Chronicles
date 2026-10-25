# Testing

## Levels

Every changelog entry, PR and compatibility claim names the highest level it reached. "Compiles" and "passes mocks" never count as "works in game".

| Level | Proves | How |
|---|---|---|
| **L0** Static | The code parses and has no accidental globals or unused variables | luacheck, `std = lua51` |
| **L1** Unit | Core logic is correct | `tests/spec/*_spec.lua` on PUC Lua 5.1 |
| **L2** Mocked integration | Platform and TRP3 adapters behave correctly against a WoW API mock and a fake of TRP3's public API (shaped to match the audited 3.4.1 source) | Same runner |
| **L3** In game, Classic Era | The addon loads, events fire, the UI behaves, TRP3 works alongside it | Manual checklist below. Results are recorded in COMPATIBILITY.md. |
| **L4** In game, Forever | The same on WoW Forever | The same checklist on a Forever client |

A mock or fake is only as good as our understanding of the real thing. That is why the TRP3 fake is built from the audited source of a **specific** TRP3 version, and why L2 can never stand in for L3 or L4.

## Running locally

```bash
python tools/check.py
```

This runs the hygiene scan, then luacheck, then every `tests/**/*_spec.lua` on Lua 5.1. The runner refuses to run on any other Lua version, because WoW is 5.1, and code that passes on 5.3 can break in the client.

Runtime lookup order:

1. `lua5.1` on `PATH`
2. `.tooling/venv` with lupa (embedded PUC Lua 5.1)

luacheck lookup order:

1. `luacheck` on `PATH`
2. `.tooling/bin/luacheck.exe`

A missing tool is a failure, never a silent skip.

## Writing tests

A spec file returns a function that receives the harness and the assertion helpers:

```lua
return function(t, expect)
	t:describe("journal", function()
		t:it("caps entries", function()
			expect.equal(#journal.entries, 500)
		end)
	end)
end
```

The assertion helpers are `equal`, `deepEqual`, `truthy`, `falsy` and `errors(fn, pattern)`.

## In-game checklist (L3/L4)

This checklist will be filled in for each release from v0.1 onward. For each run, record:

- the client build (`/dump GetBuildInfo()`);
- the TRP3 version;
- the date;
- pass, fail or n/a for each item.

### v0.1 checklist

**Setup**

1. Run `python tools/package.py`.
2. Extract `dist/DawnwardChronicles-0.1.0.zip` into `World of Warcraft\_classic_era_\Interface\AddOns\`, so that you have `AddOns\DawnwardChronicles\DawnwardChronicles.toc`.
3. Turn on Lua errors with `/console scriptErrors 1`.
4. Use a test character if possible.

**Record before you start**

- `/dump GetBuildInfo()`. The 4th value is the interface number. The TOC says `11509`; note the real value.
- The TRP3 version shown in its settings.

| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Open the AddOns list at character select | Dawnward Chronicles is listed and not marked out of date (if it is, note the interface number) | |
| 2 | Log in | No Lua errors. No chat messages from Dawnward unless something needed repairing. | |
| 3 | `/dawnward` | Status: version 0.1.0, "WoW Classic Era", real data, "Profile: none yet", a TRP3 line | |
| 4 | `/dawnward set name <name>`, then `/dawnward show` | Name shown as `[private]` | |
| 5 | `/dawnward vis name public`, `/dawnward set summary Some text`, `/dawnward show public` | Only the name is listed | |
| 6 | `/dawnward family add mother Test Name`, `/dawnward family set 1 status living`, `/dawnward family list` | `#1 mother: Test Name (living) [private]` | |
| 7 | `/dawnward history add Joined the guard`, `/dawnward history set 2 when Year 3` | Listed as `#2 Year 3: Joined the guard` | |
| 8 | `/dawnward family remove 1` | Asks for `confirm` and nothing is removed. Then `... remove 1 confirm` removes it. | |
| 9 | `/reload`, then `/dawnward show` | Everything is still there | |
| 10 | Log out fully and back in, then `/dawnward show` | Everything is still there | |
| 11 | `/dawnward export backup` | A window opens with selected text starting `!DWC1!B!`. Ctrl+C copies it. Typing in the box doesn't change it. Escape closes it. | |
| 12 | `/dawnward set name Changed`, `/dawnward import`, paste, **Check** | Shows "Ready to import" with your original name. The Import button appears. | |
| 13 | Press **Import**, then `/dawnward show` | The original name is back | |
| 14 | `/dawnward import undo`, then `/dawnward show` | Shows "Changed" again. Run undo once more to swap back. | |
| 15 | Paste a damaged export (delete a few characters), then **Check** | Rejected with a checksum message. No Import button. | |
| 16 | `/dawnward sim on`, `/dawnward set name Sim`, `/dawnward sim off`, `/dawnward show` | The real name is unchanged | |
| 17 | `/dawnward sim reset confirm` | Reports that simulation data was wiped. Real data is unchanged. | |
| 18 | With TRP3 enabled: `/dawnward trp3` | Shows `3.4.1`, "source audited, not yet tested in game", the active TRP3 profile name, and flags the TRP3 default profile if it is active | |
| 19 | Open TRP3's own profile pages after steps 3–18 | Nothing in TRP3 has changed | |
| 20 | Disable TRP3, `/reload`, `/dawnward trp3` | "installed but not loaded" (or "not installed"). No errors. | |
| 21 | Fight a mob while using a few `/dawnward` commands and the export window | No errors and no "action blocked" messages | |
| 22 | `/dwc status` | Same output as `/dawnward` | |
| 23 | Open Total RP 3's main window, then `/dawnward export backup` on top of it | The window is fully opaque, Total RP 3 doesn't show through, and the window is in front | |
| 24 | With the window open, click Total RP 3's window, then click the Dawnward window | Clicking the Dawnward window brings it back to the front | |
| 25 | `/dawnward import`, then paste a long backup | The text is padded inside a dark area, wraps within the box, and scrolls with the scroll bar or mouse wheel. Nothing draws outside the box. | |
| 26 | Press **Check** | The status message wraps above the buttons without overlapping them | |
| 27 | Repeat 23–26 at a different UI scale: `/console useUiScale 1`, then `/console uiScale 0.8`, then try `1.0`. Afterwards, restore your original values; `/dump GetCVar("uiScale")` shows the current one. | Still readable, nothing overlaps, and the window stays on screen | |

### v0.1 results: Classic Era 1.15.9 (build 70003), Total RP 3 3.4.1, 2026-10-25

Two sessions: the first test (build `1fdb724`) and the copy window re-test (build `14669c3`).

| Result | Steps |
|---|---|
| **Pass** | 7 (history and privacy labels), 9 (`/reload`), 10 (full logout and login), 11 (export), 12–14 (import check, import, undo/redo), 15 (damaged import rejected), 16–17 (simulation isolation and reset), 23 (no bleed-through over TRP3), 25 (long text and scrolling), 26 (no overlapping text) |
| **Partial** | 18: the TRP3 default profile was detected. Version and profile-name output weren't reported. |
| **Fail, then fixed** | First session: the copy window was hard to read over TRP3. Fixed in `15dbae1`, and the fix passed steps 23, 25 and 26. |
| **Untested** | 27 (UI scale). No scale option was found during the session. This is neither passed nor failed. |
| **Not reported** | 1–6, 8, 19–22 and 24. Run these on the next in-game pass. |

No Lua errors were seen during the re-test session.

**Notes for the tester**

- TRP3 rewrites its own saved file at every logout. For example, it regenerates the default profile ID at each login. So comparing TRP3's SavedVariables file before and after is not a valid test for step 19. Check TRP3's pages in game instead.
- Dawnward's data is in `WTF\Account\<account>\SavedVariables\DawnwardChronicles.lua`. Don't post that file publicly: it contains your private character data.

### v0.2 checklist (journal window)

**Setup**

1. Back up your saved data first. The v0.2 installation steps do this for you.
2. Run `/console scriptErrors 1`.
3. Note the result of `/dump select(4, GetBuildInfo())`.

Your existing v0.1 data is upgraded to schema 2 the first time v0.2 loads.

| # | Step | Expected | Result |
|---|---|---|---|
| A1 | Log in on a character that has v0.1 data, then `/dawnward show` | Every v0.1 field, family member, history entry and visibility is unchanged | |
| A2 | `/dawnward` | The journal window opens on **Journal**. The title reads "<Name>'s Journal" (or "Dawnward Chronicles" if no name is set). | |
| A3 | `/dawnward` again, then `/dwc` | Closes, then opens again | |
| A4 | Press Escape | The window closes | |
| A5 | `/dawnward status` | The same diagnostic report as v0.1, now saying version 0.2.0 | |
| B1 | **New entry**: enter a title and text, click visibility to make it **Public**, then **Save** | The entry appears at the top with today's date, its title, its text and "Public" | |
| B2 | **Edit** on that entry, change the text, **Save** | The text is updated and the date line says "edited" | |
| B3 | **New entry** with empty text, then **Save** | The editor stays open and the status line explains why | |
| B4 | **Delete** on an entry | A confirmation dialog appears. Cancel keeps the entry; Delete removes it. | |
| B5 | Add 12 or more entries (for example `/dawnward journal add Test 1`, `... Test 2` and so on) | The list shows 10 per page. **Older** and **Newer** move between pages, and "Page x of y" is correct. | |
| C1 | `/dawnward sim on`, then `/dawnward sim levelup 5` | A journal line reads "Simulated journal: Reached level 5 in <zone>". The window title shows "(simulation - test data)". The entry has no Edit or Delete, but its visibility can change. | |
| C2 | `/dawnward sim levelup 5` again | "duplicate prevented". No second entry appears. | |
| C3 | `/dawnward sim off` | The simulated entry is gone from the real journal view | |
| C4 | **If you can level up a character:** gain a level | A chat line reads "Journal: Reached level N in <zone>", and one automatic entry appears with level, zone (subzone) and "recorded automatically" | |
| D1 | **Character** tab | Twelve profile fields with their values (empty ones say "Not set"), then Family and History in readable form | |
| D2 | **Edit** on Name, change it, **Save** | Saved; the window title updates | |
| D3 | **Edit** on Summary | A larger text box opens. Multi-line text saves and displays with line breaks. | |
| D4 | Click a field's visibility button | It cycles Private → Public → Secret. `/dawnward show public` matches. | |
| D5 | **Edit** on a set field, then **Clear** | A confirmation dialog appears. Confirming removes the value. | |
| E1 | **Story** tab | An empty-state message only, with no buttons | |
| F1 | Gear icon | The settings panel replaces the section. No tab is highlighted. **Done** returns to Journal. | |
| F2 | Settings: **Silver Hand**, then **Arcane**, then **Neutral** | Colours change. Text stays readable on each. The current theme's button is greyed out. | |
| F3 | `/reload` | The theme chosen in F2 is still applied | |
| F4 | Log in to a different character, open the journal | It uses its own theme (Neutral if never set) | |
| F5 | Settings: **Export backup**, **Export for sharing**, **Import backup** | The v0.1 copy window opens on top of the journal and still works (the v0.1 steps 11–15 still pass) | |
| F6 | Settings: simulation **Turn on**, then **Reset test data** | Reset asks for confirmation. Real data is unchanged. | |
| F7 | Settings: Total RP 3 section | Shows version 3.4.1, the active profile name, and a Default profile warning if that profile is active | |
| G1 | Drag the window somewhere, then `/reload` and open it | It reopens where you left it | |
| G2 | Drag it partly off screen | It is held inside the screen | |
| G3 | Open TRP3's main window, then the journal | Both are usable. Clicking one brings it to the front. The export window opens above both. | |
| G4 | During a game dialog (for example a logout countdown or a "delete item" prompt) | The game dialog appears above the journal | |
| G5 | Change the UI scale: `/console useUiScale 1`, then `/console uiScale 0.8`, then `1.0` (restore yours afterwards) | Readable, no overlaps, fits on screen | |
| G6 | Use the journal during combat | No errors and no "action blocked" messages | |
| H1 | Open TRP3's pages afterwards | Nothing in TRP3 has changed | |

Write down any Lua error text exactly, and which step it happened in.
