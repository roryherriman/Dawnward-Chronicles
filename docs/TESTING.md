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

### v0.2 acceptance checklist (journal window)

**Merge rule:** every **Mandatory** item must pass before v0.2 is merged. An item marked *may be deferred* can instead be recorded as **untested**, and the release notes must then say so. **Optional** items never block the merge; their findings become issues for later.

**Before you start**

1. Fully exit Classic Era, then launch it. A `/reload` isn't enough after an install.
2. Type `/console scriptErrors 1` and `/chatlog`.
3. Type `/dump select(4, GetBuildInfo())` and note the number.
4. Write down the exact text of any Lua error and which step caused it. **Any Lua error fails the step it happened in.**

#### Mandatory (release-blocking)

| # | Area | Steps | Pass when |
|---|---|---|---|
| M1 | **Migration and load** | Log in on a character with v0.1 data. Run `/dawnward show`, then `/dawnward status`. | No errors at login. All v0.1 fields, family, history and visibilities are unchanged. Status says 0.2.0. |
| M2 | **Open and close** | Run `/dawnward`, then `/dawnward`, then `/dwc`, then press Escape | It opens on Journal, closes, opens again, then closes with Escape |
| M3 | **Journal: create** | **New entry**: add a title and text, click visibility to **Public**, then **Save** | The entry is at the top with a date, title, text and "Public" |
| M4 | **Journal: validation** | **New entry** with empty text, then **Save** | Refused with a message, and the editor stays open |
| M5 | **Journal: edit** | **Edit** the M3 entry, change the text, **Save** | The new text shows, and the date line says "edited" |
| M6 | **Journal: delete** | **Delete** an entry, **Cancel**, then **Delete** again and confirm | Cancel keeps it. Confirming removes it. |
| M7 | **Character: fields** | **Character** tab: **Edit** Name (one line), **Edit** Summary (multi-line, two lines of text) | Both save. Name updates the window title. The line break shows in Summary. |
| M8 | **Character: privacy** | Click Name's visibility until **Public**, leave Summary **Private**, then run `/dawnward show public` | Only Name is listed. Summary is not. (Public journal entries are checked in M16.) |
| M9 | **Character: clear** | **Edit** a set field, **Clear**, confirm | Asks first; then the value is gone |
| M10 | **Simulated level-up** | `/dawnward sim on`, `/dawnward sim levelup 5`, `/dawnward sim levelup 5`, `/dawnward sim off` | The first records "Reached level 5 in <zone>" in the simulated journal. The second says duplicate prevented. After `sim off`, the **real** journal doesn't show it. |
| M11 | **Simulation reset** | Gear → simulation **Turn on**, **Reset test data**, confirm, **Turn off** | Asks first. The real journal and fields are unchanged afterwards. |
| M12 | **Real level-up** *(may be deferred if no character can level)* | Gain a level on any character | One automatic entry with level, zone (subzone), date and "recorded automatically". No Edit/Delete; visibility can change. |
| M13 | **Backup integrity** | Gear → **Export backup**, copy the text (Ctrl+C). Change Name and delete a journal entry. Gear → **Import backup**, paste, **Check**, **Import**. | Name, journal entries, family, history and theme are restored exactly as before the changes |
| M14 | **Import undo** | `/dawnward import undo`, then `/dawnward import undo` | The first brings back the changed state, the second restores the backup again |
| M15 | **Damaged import** | **Import backup**, paste the backup with a few characters deleted from the middle, **Check** | Rejected with a checksum message, and no Import button appears |
| M16 | **Share export privacy** | Gear → **Export for sharing** | Contains the public Name and public entry only. No private Summary, no secrets. |
| M17 | **Theme persistence** | Gear → **Arcane**, `/reload`, open the journal. Log out to character select and back in, then open it again. | Arcane is still applied both times, and the button for the current theme is greyed out |
| M18 | **Theme per character** | Log in on a different character and open the journal | It uses its own theme (Neutral if never set) |
| M19 | **Reload persistence** | `/reload`, then log out fully and back in. Open the journal and Character. | All entries, fields and visibilities from M3–M9 are still there |
| M20 | **TRP3 read-only status** | Gear → Total RP 3 section | Shows 3.4.1, "source audited, not yet tested in game", the active profile name, and a Default profile warning if that profile is active |
| M21 | **TRP3 coexistence** | Open TRP3's main window and the journal together. Click each one, then open **Export backup**. | Both work. Clicking one brings it to the front. The export window is above both. |
| M22 | **TRP3 untouched** | After all the steps above, open TRP3's profile pages (characteristics, About, personality) | Nothing in TRP3 has changed |
| M23 | **Game dialogs on top** | With the journal open, trigger a game dialog (for example, try to delete an item, then cancel) | The game dialog appears above the journal |
| M24 | **Combat** | Open the journal and add an entry during combat | No errors and no "action blocked" messages |

#### Optional (cosmetic and comfort, never blocking)

| # | Check | Notes to record |
|---|---|---|
| O1 | Theme readability: Neutral, Silver Hand, Arcane | Any text that is hard to read, and where |
| O2 | Window position: drag the window, `/reload`, reopen | Whether it reopens in the same place |
| O3 | Screen edge: drag the window partly off screen | Whether it is held on screen |
| O4 | Paging: add 12 or more entries (`/dawnward journal add Test 1` and so on) | Whether Older/Newer and "Page x of y" feel right |
| O5 | UI scale: `/console useUiScale 1`, then `/console uiScale 0.8` and `1.0`, then restore yours (`/dump GetCVar("uiScale")` before you start) | Overlaps, clipping, or a window that doesn't fit. **Untested is acceptable.** |
| O6 | Spacing, fonts, wording, tooltips, the Story empty state | Anything that feels cluttered, unclear or out of place |

**Known issue during testing:** KI-1 (a one-time return to character select) is unresolved and not reproduced. If it happens again, note the time and stop. It then becomes blocking (see `COMPATIBILITY.md`).

**Report format:** the build number, the TRP3 version, and then for each item **Pass**, **Fail** (with what happened) or **Untested**.

### v0.2 acceptance results: Classic Era (build not reported), 2026-10-25

Reported by the tester in groups. Addon code under test: `f973931`, unchanged since installation. The interface number and TRP3 version were not reported in this round.

| Group | Items | Result |
|---|---|---|
| Loading and navigation | M1–M2 | **Pass** |
| Journal | M3–M6 | **Pass** |
| Character and privacy | M7–M9 | **Pass** |
| Simulation | M10–M11 | **Pass** |
| Real level-up | M12 | **Pass** |
| Backup and import | M13–M15 | **Pass** |
| Sharing privacy | M16 | **Pass** |
| Themes and persistence | M17–M19 | **Pass** |
| TRP3 compatibility | M20–M22 | **Pass**. First reported as untested, then as pass in an updated report the same day. |
| UI safety | M23–M24 | **Pass** |
| Optional | O1–O6 | Not reported |

**Outcome:** all 24 mandatory items pass, so v0.2 meets the merge rule. Optional items O1–O6 (including UI scale) remain unreported, which does not block the merge.

Notes from the tester: none. No Lua errors were reported. KI-1 did not recur.
