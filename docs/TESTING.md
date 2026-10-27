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

### v0.3 in-game checklist (L3)

This covers v0.3 M1 (character foundations) and the **experimental** Total RP 3 sync (issues #3–#7). Nothing here has been run yet. Everything built so far reached **L2** (mocked) only.

**Guardrails:**
- Run the TRP3 write tests (Part C onward) **only on a disposable, non-default TRP3 profile** created for this purpose.
- Don't enable sync on your real profile until Parts C–F pass and you've approved it.
- If anything unexpected happens:
  1. Run `/dawnward trp3 rollback confirm`.
  2. If that fails, restore the saved-variable backups from step A1.

**Before you start**

1. Fully exit Classic Era, then launch it.
2. Type `/console scriptErrors 1` and `/chatlog`.
3. Record `/dump select(4, GetBuildInfo())` and the TRP3 version (`/dawnward trp3`).
4. Any Lua error fails the step it happened in. Write down the exact text.

#### Part A: Upgrade and character foundations (M1, acceptance criterion 19)

| # | Steps | Pass when |
|---|---|---|
| A1 | With the game closed, back up `WTF/Account/<account>/SavedVariables/DawnwardChronicles.lua` and `totalRP3.lua` (copy them somewhere safe). Install the build. | Copies exist |
| A2 | Log in on the character with v0.2 data. `/dawnward status`, `/dawnward show`, open the journal. | No errors. Status says 0.3.0-dev and shows `Foundations: 0 facts, 0 suggestions, biography stored: no`. All v0.2 data unchanged. Chat may say "upgraded from schema 2". |
| A3 | `/dawnward fact add belief Protect those who cannot protect themselves`, `/dawnward fact list`, `/dawnward fact vis 1 public` | Added as private, listed under Belief, then public |
| A4 | `/reload`, then `/dawnward fact list`; log out and in, then list again | The fact and its visibility persist |
| A5 | `/dawnward export share`, then `/dawnward export backup` | Share contains the public fact. Backup contains it, and the window title has **no** "(with stored biography)". |
| A6 | `/dawnward fact remove 1`, then `/dawnward fact remove 1 confirm` | Asks first, then removes it |
| A7 | `/dawnward personality set courage 15`, `/dawnward personality vis courage public`, `/dawnward personality list` | Shows `courage: Cautious 15/20 Bold [public]` |
| A8 | v0.2 spot check: add a journal entry, edit a character field, `/dawnward sim on` then `sim off` | All behave as before |

#### Part B: Adapter and safe fallback (issue #3)

| # | Steps | Pass when |
|---|---|---|
| B1 | On the TRP3 **default** profile: `/dawnward trp3 enable about confirm` | Refused: "default profile". `/dawnward trp3 backups` shows none. |
| B2 | `/dawnward trp3 preview` | "biography: off …", and nothing written |
| B3 | `/dawnward trp3 paste` | A window shows the Chronicle section and suggested traits (public data only) |
| B4 | *(optional)* Disable TRP3 at the character screen, log in, `/dawnward trp3 enable about confirm` | Refused: "not loaded". No Lua errors. |

#### Part C: Disposable-profile biography test (issues #4 and #5)

Create a new TRP3 profile named for example "Dawnward Test" and switch to it.
- Give it some About text on **template 1**, with a heading and two paragraphs.
- Screenshot the About page.

| # | Steps | Pass when |
|---|---|---|
| C1 | Add two public facts (Part A commands). `/dawnward trp3 enable about` | Shows the EXPERIMENTAL warning and asks for confirm. Nothing written. |
| C2 | `/dawnward trp3 enable about confirm`, wait about 10 s | Chat: "Updated your Total RP 3 biography (insert)". The About page shows your text unchanged, followed by **Chronicle** and the two facts. |
| C3 | `/dawnward trp3 backups`, `/dawnward trp3 log` | One backup (#1 about); the log shows `insert (version N …)` |
| C4 | `/dawnward status` twice, wait 10 s | No new "Updated" message; the log shows no new write (no-op) |
| C5 | Add another public fact, wait 10 s | The section updates in place. Your own text is unchanged. |
| C6 | `/reload`, then log out and in. Open the About page. | Your text plus the section persist |
| C7 | Open TRP3's About **editor** (don't save). Add a public fact. Wait 40 s. | No write while the editor is open (`/dawnward trp3 preview` says the editor holds unsaved changes; `/dawnward trp3 diagnose` shows `about editor: draft yes`) |
| C7a | With the editor still open, close TRP3's window (Escape or X). `/dawnward trp3 preview` | Still waiting: the unsaved draft is protected |
| C7b | `/reload` **without** opening TRP3. `/dawnward trp3 preview` and `/dawnward trp3 diagnose` | Biography is **not** waiting (reload discarded the draft); diagnose shows `page nil, context no` for both editors. Copy the diagnose output into the report. |
| C8 | Cancel the editor, wait about 30 s | The pending update is written |
| C9 | In TRP3's editor, change one word **inside** the Chronicle section and save. Add a public fact. Wait 10 s. | Chat says sync is paused (conflict). Your edit is **kept**, nothing else changes. The message is shown once. |
| C10 | `/dawnward trp3 resolve about reclaim`, wait 10 s | Your edited section stays, and a fresh Chronicle section is appended below it |
| C11 | Open the editor, then **Save** without changes | The section is still there |
| C12 | Switch template to **2** in the editor and save; add a public fact | Conflict ("template was changed"); nothing written |
| C13 | `/dawnward trp3 rollback confirm` | Restores the About page as it was before the last Dawnward write. Compare with your screenshots. |
| C14 | `/dawnward trp3 rollback <# of the "before rollback" backup> confirm` | Undoes the rollback |
| C15 | `/dawnward trp3 release about confirm` | Dawnward's section is removed; your text is exactly as before C2 |

#### Part D: Disposable-profile personality test (issue #6)

Give the test profile two personality traits of your own: one preset and one custom.

| # | Steps | Pass when |
|---|---|---|
| D1 | Set two axes public (`personality set` / `vis`). `/dawnward trp3 enable traits confirm`, wait 10 s | Two new custom traits (for example Cautious/Bold) appear **after** yours. Your traits are unchanged. Slider positions match (15 toward Bold shows 5 on the Cautious side). |
| D2 | Change one axis, wait 10 s | Only that slider moves |
| D3 | `/dawnward status`, wait 10 s | No new write (no-op) |
| D4 | Move a Dawnward slider yourself in TRP3's editor and save; change that axis in Dawnward | Conflict; your slider position is kept |
| D5 | `/dawnward trp3 resolve traits reclaim`, wait | Dawnward updates its own traits again |
| D6 | Set an axis back to private, wait | Its trait is removed; others stay |
| D7 | `/reload` and relog | Traits persist |
| D8 | `/dawnward trp3 release traits confirm` | Only Dawnward's traits are removed |

#### Part E: Profile switching, shared profiles, combat, simulation

| # | Steps | Pass when |
|---|---|---|
| E1 | With sync on for the test profile, switch to another TRP3 profile and add a public fact | Chat: sync paused (not the profile it was enabled for). The other profile is unchanged. |
| E2 | Switch back | Sync resumes and writes the pending update |
| E3 | Enter combat (for example attack a training dummy) and add a public fact | No write until combat ends (retry within about 30 s after) |
| E4 | `/dawnward sim on`, add a public fact | Nothing is published; `/dawnward trp3 preview` says simulation mode |
| E5 | *(optional)* Link an alt to the test profile, then opt in again | The enable message names the shared character |

#### Part F: Multiplayer propagation (issue #7) — needs a second player or account

| # | Steps | Pass when |
|---|---|---|
| F1 | Player 2 (TRP3 installed) mouses over or targets you and opens your TRP3 profile | They see your current About page and traits |
| F2 | You add a public fact; wait for "Updated…"; player 2 waits 15 s, then mouses over or targets you again | Player 2 sees the new Chronicle line without either of you reloading |
| F3 | Repeat F2 for a personality change | Player 2 sees the moved slider |
| F4 | You run `/dawnward status` several times; player 2 re-targets you | No new download (TRP3's request indicator stays idle) |
| F5 | *(optional)* Player 2 uses MyRolePlay or XRP instead of TRP3 | They see the updated description (and traits, if their addon shows them) |
| F6 | You open TRP3's About editor before a Dawnward write, close the window without saving, let Dawnward wait, then save in the editor | Player 2 sees **your saved** version (not a stale one) after re-targeting |

**Record:** pass, fail or n/a per item, screenshots or `/chatlog` excerpts, and any difference outside Dawnward's section (that is a release blocker: roll back and report).

### Results recorded so far for v0.4 and origins/places (owner-reported, 2026-10-26)

Recorded in [COMPATIBILITY.md](COMPATIBILITY.md#l3-results-v04-and-originsplaces-classic-era-1159-total-rp-3-341-2026-10-26-owner-reported).

| Checklist part | Coverage |
|---|---|
| J1–J3, J4, J6, J8 | Passed in substance: memories, arcs (including turning points, conclusion and reactivation), goals with milestones, stances with contradiction review, people |
| L1–L4, L8 | Passed in substance: Northshire, Goldshire and Lion's Pride Inn detection, first visits, a location reaction in the journal, a marked place persisting across `/reload` |
| TRP3 sync (v0.3 parts C, D, E-subset) | Opt-in, editor protection, backup and rollback passed |
| G (quest moment), H (pacing), I (presentation), K3–K4 (reputation, guild), L5–L11 | **Not yet reported.** Still to do |

### v0.4 in-game checklist (L3): the living chronicle

Build: `0.4.0-dev`. Use a test character, and keep TRP3 sync on the **disposable** test profile only. Back up `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua` before installing. Everything below has passed mocked tests (L2) only.

#### Part G: Upgrade and quest moment (the vertical slice)

| # | Steps | Pass when |
|---|---|---|
| G1 | Install over v0.3 and log in | Chat: "Saved data upgraded from schema 3." Journal, facts and personality are unchanged; nothing new is public |
| G2 | `/dawnward status` | A "Story:" line: 0 events, 0 moments waiting |
| G3 | Turn in any quest (reward panel shown) | No popup during the turn-in. Within a few seconds out of combat: one chat line "A moment for your story: ..." naming the quest and zone, and a small card |
| G4 | `/dawnward story events` | The quest, with its real title and zone, `verified`, `queued` |
| G5 | Click **Answer** on the card | The journal opens on the Story section with that question and 5 or 6 answers (the last is "Nothing worth remembering.") |
| G6 | Click an answer that moves an axis (for example the first) | Status: "Decision recorded ... waiting for your approval". The Story section shows the change with Approve / Reject. Personality is **unchanged** so far |
| G7 | Approve it | `/dawnward personality list` shows the axis moved by exactly 1 (a new axis starts at 10, private) |
| G8 | Journal section | A **draft** entry with the quest title, what happened, your answer and the development line; Approve button visible |
| G9 | Click the visibility button on the draft | Status explains it must be approved first; it stays Private |
| G10 | Approve, click `*` (defining moment), then make it Public | Meta line says "story - defining moment"; visibility Public |
| G11 | Turn in two more quests in the same zone quickly | No second notice; `/dawnward story events` shows them folded into the waiting moment, or recorded during the cooldown |
| G12 | `/reload`, then `/dawnward story events` | The same events; none recorded twice |

#### Part H: Calm moments and pacing

| # | Steps | Pass when |
|---|---|---|
| H1 | Turn in a quest and immediately enter combat | No card or notice in combat. After combat ends, the notice appears |
| H2 | Die (safely) | No notice while dead or as a ghost. After reviving, a death moment may appear (first death: always) |
| H3 | Card visible, then enter combat | The card hides |
| H4 | Settings (gear) > Moments: off; turn in a quest | Recorded (`story events`) but no moment |
| H5 | Settings > Card: off; next moment | A chat line only, no card |
| H6 | `story <#> later`, `notnow`, `dismiss` | Later: kept, marked "kept for later". Not now: stays, no reminder. Dismiss: gone; the event stays `dismissed` |
| H7 | Write your own answer in the Story section and Save | Draft says "In <name>'s own words: ..."; no personality change proposed |

#### Part I: TRP3 presentation (disposable profile, experimental sync on for biography)

| # | Steps | Pass when |
|---|---|---|
| I1 | After G10, wait about 10 s (or `/dawnward trp3 sync`) | The About page shows your text unchanged, then Chronicle with "Defining moments:" and the entry's title |
| I2 | Make the entry Private again, wait | The moment disappears; your own text is unchanged |
| I3 | `/dawnward story set trp3Style arcane`, wait, open the About page | Violet heading with a book icon. Screenshot it. Repeat with `silverhand` and `neutral` |
| I4 | `/dawnward trp3 release about confirm` | Your About text is exactly as before Dawnward's first write |

**Record:** pass, fail or n/a per item, screenshots of G5, G8, I1 and I3, and any Lua error (BugSack or `/console scriptErrors 1`).

#### Part J: Chronicle, memories, arcs, goals and identity

| # | Steps | Pass when |
|---|---|---|
| J1 | Open the **Chronicle** tab. Type a memory in the line at the bottom, then click Add memory | A row shows it, labelled `player, established, private` |
| J2 | Answer a notable moment (the first quest in a new zone) | A **suggested** memory appears (`suggested, proposed, private`) with an Accept button. Clicking Private → Public on it is refused until you accept it |
| J3 | Answer three moments with the same kind of answer (for example the first answer each time), in different zones | Arcs tab: a suggested arc "A thread of …" |
| J4 | `/dawnward goal add Become a master smith`, then `/dawnward goal level <#> <your level + 1>`. Level up | `goal list` shows the level reached; the goal stays **active** until you change it |
| J5 | With an active goal, turn in a quest and open the moment | An extra answer "It mattered to their goal: …"; the universal answers are unchanged |
| J6 | `/dawnward stance add <a faction>; Loyal; Privately resents them` | The Review tab asks about the contradiction; answer "secret" and the private side becomes secret |
| J7 | Make the stance's public side Public (with biography sync on the disposable TRP3 profile) | The About section shows "Where they stand: …" with the public stance only, never the private conviction |
| J8 | `/dawnward person add npc <name>; <relation>`, `person add player Name-Realm; <relation>` | Listed in the People tab; a second record for the same Name-Realm is refused |

#### Part K: World events and storytelling

| # | Steps | Pass when |
|---|---|---|
| K1 | Travel to a zone you have not been to since installing v0.4 | `story events` shows "First recorded visit" for it; no prompt in combat |
| K2 | Enter a dungeon | "First recorded entry" with the dungeon's name |
| K3 | Gain a reputation tier (or watch `story events` after one) | Only the change is recorded, never your existing standings at login |
| K4 | Join or leave a guild on a test character | One guild event; nothing at login |
| K5 | `/dawnward moment Swore an oath at the shrine` | Recorded as a player moment (`confidence player`) with a question to reflect on |
| K6 | `/dawnward timeline` | Newest first; your history entries are listed as undated |
| K7 | Keep a moment for later, then click **Reflect** in the Story section | It comes back to "waiting" without a new reminder |

#### Part L: Origins and places (#20, #11, #14)

Build: schema 5. Everything below has passed mocked tests (L2) only. Use **a brand-new character** for L1–L4 and an established one for L5. Turn on `/chatlog`, and after each step copy the `/dawnward story events` lines into the report.

| # | Steps | Pass when |
|---|---|---|
| L0 | Back up `DawnwardChronicles.lua`, install, log in on an existing character | Chat: "Saved data upgraded from schema 4." Approved journal entries read exactly as before. An older story draft's "Development:" line now shows the change's real status (for example "(approved)") |
| L1 | Create a new **Human** (any class). In Northshire, set your name and pronouns (`/dawnward set name …`, `/dawnward set pronouns she/her`), then `/reload` | One notice. The question reads "Every story begins somewhere. As <name>'s journey begins in <Northshire subzone>, what occupies her thoughts?" `story events` shows "Journey begins: … (starting area)" and nothing says "arrived" |
| L2 | `/dump GetSubZoneText()`, `/dump C_Map.GetBestMapForUnit("player")`, `/dump C_Map.GetAreaInfo(9)`, `/dump C_Map.GetAreaInfo(24)` | Record all four outputs. Expect a Northshire name, `1429`, "Northshire Valley" and "Northshire Abbey" |
| L3 | Answer it, approve the change, open the Journal | The draft starts "The journey begins in …, Elwynn Forest, at level 1 (a known starting area)." Its "Development:" line says "(approved)", not "waiting" |
| L4 | Walk to Goldshire, then to a farm (The Stonefield Farm or The Maclure Vineyards), then back and forth a few times | At most one moment for Goldshire ("<name> reaches Goldshire. What draws her attention?") and one for the farm. Going back and forth adds no events and no notices. `/dawnward places` lists them with "(settlement)" and "(farmland)" |
| L5 | On an **established** character above level 5 that has never recorded a location, `/reload` in any zone | "Your chronicle first records <name> in <zone>. What does this place mean to …?" Nothing says it began, arrived or was born there |
| L6 | Turn in a quest in Goldshire within two minutes of first arriving | The quest's moment replaces the Goldshire one: one notice, about the task |
| L7 | Enter a new zone, then its first town within two minutes (for example Redridge, then Lakeshire) | One moment, about the town ("… reaches Lakeshire. What is her first impression of this new place?") |
| L8 | `/dawnward place mark Goldshire`, `/dawnward places` | Goldshire shows `*`. No memory, fact or journal entry was created |
| L9 | `/dawnward story set places fewer`, visit a new farm; then `story set places off`, visit a new town | Fewer: the farm is recorded but not asked about. Off: the town is recorded but not asked about. Set it back to `on` |
| L10 | Enter a battleground, then a dungeon | The battleground is not recorded; the dungeon is "First recorded entry" as before |
| L11 | Check Total RP 3 on the disposable profile (sync on) after the steps above | No place names, starting area or journey text appear in Dawnward's section |

Returns (two or more days away from Goldshire, then back) need real time to pass. Test them later and record the date. Expect "… has returned to Goldshire. Does this place feel any different now?", at most once a week.

> **Changed in v0.5 (PR #52):** place moments are now weighted (see Part M and ARCHITECTURE.md). On a v0.5 build, a farm (L4) and a plain return to Goldshire are logged quietly instead of asking. A return asks only when the place is tied to the character's story: marked, Homeland, a memory, an active arc or goal, or a person.

**Not covered yet:** other races' starting areas in game, localised clients, and WoW Forever (no place data applies there yet).

#### Part M: v0.5 window, guide, minimap, weighted moments, atlas (PR #52)

Build: schema 5, unchanged. Everything below has passed mocked tests (L2) only. Back up `DawnwardChronicles.lua` first. Use an existing character unless a step says otherwise.

| # | Steps | Pass when |
|---|---|---|
| M1 | Log in. Check the minimap | A book-icon button sits on the minimap rim. Its tooltip says click / right-click / drag (and how many moments are waiting, if any) |
| M2 | Click it, then click it again; right-click it | The journal opens and closes; right-click opens the Story section |
| M3 | Drag it around the minimap, `/reload` | It stays where you dropped it |
| M4 | Settings → **Minimap button: shown**, then `/reload`, then `/dawnward minimap show` | It hides and stays hidden after the reload; the command brings it back |
| M5 | On a character that has never closed the guide, open the journal | The guide opens on Welcome. Next and Back move through the topics. **Close guide** closes it, and it does not open by itself again (also after `/reload`) |
| M6 | Click **?** beside the gear; search "goal level"; Settings → **Open the guide**; `/dawnward guide` | Each opens the guide. The search lists the goal level command |
| M7 | `/dawnward help`, `/dawnward help story`, `/dawnward help all`, `/dawnward goal milestone Find a ship` | Short help; the story topic; the full list; an explanation with the example `/dawnward goal milestone 12 Find a ship` |
| M8 | Chronicle → Memories: **New memory**, fill in Title and What happened, **Save** | One row: the text on the first line, `player, established, private` and the buttons on the second. **Nothing overlaps (#46)** |
| M9 | Add 7+ memories | Page 1 of 2; **Next >** shows the rest |
| M10 | Arcs: New, then **Edit** (title, state Concluded), then **Turn** | Saved; the row shows the state and "1 turning point" |
| M11 | Goals: New with Target level 20; **Steps**, add a step; **Steps**, tick it; **Edit**, clear the target, state Achieved | Milestones 1/1; the level objective is gone; Achieved |
| M12 | Stances and People: New, then Edit. Try saving a stance with both sides empty, and a player character without a realm | Saved; the two invalid saves are refused with a reason, and the form stays open |
| M13 | Places tab: **Mark** Goldshire; **Homeland** → confirm; **Memory** | "meaningful to you", then "homeland" appear. Character → Homeland reads Goldshire, with its visibility unchanged. The memory is saved with the place |
| M14 | Character → Family: **Add**, Edit, the visibility button, then Remove (confirm). The same for History | Each works without chat commands; Remove asks first |
| M15 | Visit a new farm, then a new town (for example in Westfall). Over several sessions, note which places ask | Farms and roads never ask. A new town asks only sometimes. `/dawnward story events` shows each visit as recorded |
| M16 | Set your Homeland to a town you will visit later (or mark a place), then visit it | It asks, even shortly after another place moment; the notice waits for a calm moment |
| M17 | `/dawnward atlas` in Goldshire and in Lion's Pride Inn; `/dawnward atlas verify`; `/dawnward atlas export` | Goldshire: area 87, settlement, in-game evidence. Lion's Pride Inn: no verified area ID. Verify: count of matches. **Paste the export into #48** |
| M18 | `/dawnward atlas scan 1 5000` | A copy window with named areas. **Paste it into #48** (it lets coverage grow from the client's own data) |
