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
| 5 | `/dawnward vis name public`, `/dawnward set summary Some text`, `/dawnward show profile` | v0.10: `vis` replies "Per-item visibility is no longer used" and changes nothing; `show profile` lists what Total RP 3 receives (everything once the profile is published; before `/dawnward publish confirm` an older character lists only what it marked Public) | |
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
| A3 | `/dawnward fact add belief Protect those who cannot protect themselves`, `/dawnward fact list`, `/dawnward fact vis 1 public` | Added, listed under Belief with no visibility tag; `fact vis` replies that per-item visibility is no longer used (v0.10) |
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
| M16 | `/dawnward set homeland <a town you have never visited>` (for example Lakeshire), then visit it for the first time | It asks, even shortly after another place moment; the notice waits for a calm moment. **Clarified in v0.6:** a place you have already visited (marked, or set as Homeland from the Places tab) asks only on a *return*. Since v0.7-dev that needs one narrative day of **play** away (2 hours at Standard pace), never real days; going back sooner records nothing. Use `/dawnward dev story simulate <place>` (part P) to check a return without waiting |
| M17 | `/dawnward atlas` in Goldshire and in Lion's Pride Inn; `/dawnward atlas verify`; `/dawnward atlas export` | Goldshire: area 87, settlement, in-game evidence. Lion's Pride Inn: no verified area ID. Verify: count of matches. **Paste the export into #48** |
| M18 | `/dawnward atlas scan 1 5000` | A copy window with named areas. **Paste it into #48** (it lets coverage grow from the client's own data) |

### v0.6 in-game checklist (L3): visual overhaul and first-time setup

#### Part N: v0.6 design, setup wizard, themes, developer commands (branch `feat/v0.6-ui-overhaul`)

Build: **0.6.0-dev**, schema 5 (unchanged). Everything below has passed mocked tests (L2) only. The design is described in [docs/design/UI_DESIGN_V06.md](design/UI_DESIGN_V06.md).

**Before you start:** close the game. Back up `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua`, then install the branch build.

**Characters you need:**
- **New:** a character that has never used Dawnward, either a fresh one or one with no Dawnward record.
- **Established:** your usual test character, with v0.5 data.

Turn on `/console scriptErrors 1` and note any Lua error with its text.

**Setup wizard: new character**

| # | Steps | Pass when |
|---|---|---|
| N1 | On the **new** character, type `/dawnward` (or click the minimap button) | The setup wizard opens on **1 Welcome**, *instead of* the journal. The eyebrow reads "FIRST-TIME SETUP". There is a step indicator with six steps |
| N2 | **Next**. On Character, check the Name box | Your in-game name is pre-filled as a suggestion. Type a Title and a Homeland |
| N3 | **Next**, change "How often" and "Place moments"; then **< Back** | Back on Character, your Title and Homeland are still there. Forward again, your story choices are kept |
| N4 | Continue to **Privacy** | It explains Private, Secret and Public, says Total RP 3 sync stays off, and shows your TRP3 status read-only. There is no button that turns sync on |
| N5 | **Appearance:** click each theme | The wizard recolours at once (live preview). Pick **Shadowbound** and set Minimap button to *Hide* |
| N6 | Press **Escape** (or click X) on any page, then `/dawnward` again in the same session | The wizard closes. This time the journal opens (the wizard opens by itself only once per session). `/dawnward dev setup status` shows "Draft: saved, page N" |
| N7 | `/reload`, then `/dawnward` | The wizard reopens on the same page, with your answers still filled in |
| N8 | Go to **Finish**, read the review, click **Finish** | The journal opens on the Journal tab, in Shadowbound. Character shows your Name, Title and Homeland, all **Private**. The minimap button is hidden. Fields you left empty were not created |
| N9 | `/reload`, then `/dawnward` twice | The journal opens and closes normally. The wizard does not return |

**Setup wizard: established character**

| # | Steps | Pass when |
|---|---|---|
| N10 | Log in on the **established** character, `/dawnward` | The journal opens directly. **No wizard** |
| N11 | Settings (gear) → General → **Run setup**. On Character, empty the Homeland box and change the Title. **Finish** | Homeland is **unchanged**, because an empty box never erases. The Title is updated. Journal, memories, arcs, goals and places are exactly as before |

**Developer commands (0.6.0-dev only)**

| # | Steps | Pass when |
|---|---|---|
| N12 | `/dawnward dev setup status` | Shows complete or not, "Current wizard version: 1", the draft state, and whether the character counts as new |
| N13 | `/dawnward dev setup` on the character from N8 | The wizard opens even though setup is complete. The eyebrow reads "PREVIEW - TEST MODE". There is no "Set up later" |
| N14 | In the preview, change the Title, go to Finish, click **Close preview** | Nothing changed (check the Character tab). `dev setup status` still says complete |
| N15 | `/dawnward dev setup` again, change the Title, click **Save choices** | The Title changes. `dev setup status` still says complete with the same date: setup status did not change |
| N16 | `/dawnward dev setup reset` | It explains what will be reset and asks for `confirm`. **Nothing changed** |
| N17 | `/dawnward dev setup reset confirm`, then `dev setup status` | "Setup: not complete." Profile, journal and story are unchanged. Because the character now has data, the wizard does **not** open by itself |

**Themes and the redesigned interface**

| # | Steps | Pass when |
|---|---|---|
| N18 | Settings → General: click Classic Dawnward, Lightbound and Shadowbound in turn | The whole window recolours: frame line, corner brackets, buttons, inputs, cards and text. The current theme tile is highlighted. Text is readable on each |
| N19 | Pick Neutral, Silver Hand and Arcane (the v0.2 themes) | Still selectable. An established character that used one keeps it after the upgrade |
| N20 | Log in on another character | It keeps its own theme. New characters start on Classic Dawnward |
| N21 | Visit every tab: Journal (cards; New entry, Edit, Delete, Approve, Defining), Character (Edit, Add), Story (answer cards; Later, Not now, Dismiss), Chronicle (segmented tabs; New, Edit, Remove), Settings (General, Story, Data, Total RP 3 pages) | Nothing overlaps or is cut off. Buttons highlight on hover, and disabled buttons look disabled. Every v0.5 action still works |
| N22 | Delete a journal entry | A Dawnward-styled confirmation appears above the window. **Cancel** and **Escape** do nothing; **Delete** deletes |
| N23 | Wait for a story moment out of combat | The reaction card uses the same frame style. Answer, Later and Dismiss work; enter combat and it hides |
| N24 | Settings → Data → Export backup | The copy window uses the new style; Ctrl+C copies and Escape closes |
| N25 | Set the game's UI scale to its largest, then `/reload`, then open the journal and the wizard | Both fit on screen. If the screen is too small, the window scales itself down |
| N26 | Check tooltips on the ?, gear and X buttons, the visibility buttons and a Settings button | Each tooltip shows, and hovering still highlights the control |

**Edge cases**

| # | Steps | Pass when |
|---|---|---|
| N27 | Create a fresh character, reach level 2, *then* type `/dawnward` for the first time | The wizard still opens: an automatic level-up entry doesn't count as "established" |
| N28 | On the established character: `/dawnward sim on`, then Settings → General → **Run setup** | The eyebrow reads "SIMULATION MODE: PREVIEW ONLY", and Finish is disabled. Close it, then `/dawnward sim off`. `/dawnward dev setup status` shows no draft |
| N29 | Give a character a Summary of several paragraphs (Character tab), then run setup and click Next to Finish without touching it | The Summary is unchanged, with its line breaks intact |
| N30 | Start setup, change the Title, choose "Set up later". In Settings change the theme and Moments. Run setup again and Finish | The Title is saved, and the theme and Moments keep your newer choices |
| N31 | Open the journal, delete an entry, and press **Escape** on the confirmation | Only the confirmation closes; the journal stays open |

#### Part O: keyboard, inline validation and entry rows (same build)

Automated: `tests/spec/ui_forms_keyboard_spec.lua` and `tests/spec/ui_entry_rows_spec.lua` (L2). Check these by eye in the game.

**Keyboard**

| # | Steps | Pass when |
|---|---|---|
| O1 | Chronicle → People → **New** | The cursor is in the first box (Name) and that box has an accent edge and bar. No click needed |
| O2 | Press **Tab** repeatedly, then **Shift+Tab** | Focus moves through the text boxes in order and wraps; Shift+Tab goes back. Choice buttons and hidden fields are skipped |
| O3 | In a one-line box that is not the last, press **Enter** | Focus moves to the next box; the form is **not** saved |
| O4 | Memories → New, type in "What happened", press **Enter** | A new line is added; the form is not saved |
| O5 | Fill the last one-line box, press **Enter** | The form saves (or shows an inline error, see O9) |
| O6 | Open any form, type something, press **Escape** | A confirmation asks to discard. **Cancel** keeps the form and the text; confirming closes it |
| O7 | Open a form, type nothing, press **Escape** | It closes at once, without a question |
| O8 | Close every Dawnward form, press **Enter** and type in chat; press **Escape** with nothing open | Chat works normally; Escape opens the game menu as usual |
| O8a | Repeat O1–O7 in Character → Edit (Name, Summary), Family and History forms, the journal editor and the setup wizard's Character page | Same behaviour. In the wizard, Enter on the last box goes to the next page |

**Inline validation**

| # | Steps | Pass when |
|---|---|---|
| O9 | People → New, leave Name empty, **Save** | "! …" in red appears directly under Name, the box has a red edge and has focus. The form stays open; anything typed elsewhere is kept |
| O10 | Type a name | The message and red edge disappear as you type, and the rows below move back up |
| O11 | Goals → New, type letters in **Target level**, **Save** | "Enter a whole number, or leave it empty" under that field |
| O12 | Character → Edit Title, empty it, **Save** | The message is under the box, not in the status bar. Nothing was saved |
| O13 | Trigger an error in the longest form (Goals or Arcs) at your largest UI scale | The message doesn't overlap the next row or the Save and Cancel buttons and is readable on every theme |

**Entry rows (each action belongs to its record)**

| # | Steps | Pass when |
|---|---|---|
| O14 | Character tab with a long Title and Summary, two family members and two history entries | Each field, family member and history entry is its own panel; its **Edit** and visibility buttons sit inside it, on its first line. There's a visible gap between panels |
| O15 | Hover a panel, then hover its Edit button | The whole panel lights up with an accent bar on its left; only that panel, never its neighbour |
| O16 | Chronicle → Places with at least three places; make one Homeland and mark one meaningful | The status (HOMELAND, MEANINGFUL) shows in accent capitals at the top right of that place, apart from the buttons below. The Homeland row has no "Set as homeland". The "Mark meaningful" button changes to "Unmark meaningful" |
| O17 | Memories, Goals, Arcs, Stances and People with several records, including one with a very long title | Text wraps inside its own panel; buttons stay right-aligned inside the same panel and never sit nearer the next one. Page through with Next > |
| O18 | Journal with several long entries; scroll | Each entry is a card with its own Edit, Delete and Defining buttons; scrolling never separates buttons from their entry |
| O19 | Story → pending personality changes | Each change is a panel with its own Approve and Reject |
| O20 | Repeat O14–O17 at the smallest and largest UI scale | Nothing overlaps or leaves its panel |

#### Part P: Story Director place diagnostics (development builds only)

Automated: `tests/spec/story_diagnostics_spec.lua` (L1/L2). The rules being checked are in [ARCHITECTURE.md](ARCHITECTURE.md#return-visits-exact-eligibility).

| # | Steps | Pass when |
|---|---|---|
| P1 | Repeat the v0.5 M16 report: visit Goldshire, Places → **Mark meaningful** and **Set as homeland**, go to Stormwind, come back to Goldshire. Then `/dawnward dev story status` | No prompt, and no new line in `story events` (expected). Status shows the location as "Goldshire, Elwynn Forest (map 1429, area 87): settlement" and "Homeland: yes. Marked meaningful: yes". It shows the narrative clock and day. It says the return was not recorded because you were away only minutes of play, and a return counts after 2 h of play away (with the play still needed). It also shows the Director weight (urgent) and the cooldown in play time |
| P2 | `/dawnward dev story simulate` in Goldshire | It says it is simulating a return after about 2 h of play away, with the event, weight and roll. The result is "a moment was queued", followed by the question ("… has returned to Goldshire …") and the answers. The last line says nothing was saved |
| P3 | After P2: `/dawnward story events`, Story tab, Journal, `/dawnward places`, then `dev story status` | Nothing changed: no new event, 0 waiting moments, no journal entry, the same visit count, and the same cooldown as before P2 |
| P4 | `/dawnward dev story simulate The Stonefield Farm` (unmarked) | "Result: no event", saying returns count only for settlements and for places tied to your story |
| P5 | `/dawnward dev story simulate Lakeshire` before ever visiting it | "Not simulated: no visited place called 'Lakeshire'" |
| P6 | Enter a new zone, then `dev story status` | "Last arrival this session" names the new zone and says what was recorded and why it did or did not ask (for example "suppressed: the shared location cooldown") |
| P7 | Play elsewhere for at least 2 hours (Standard pace), then return to Goldshire | It asks, even shortly after another place moment, and `story events` lists "returned to Goldshire". Record how long you played |
| P8 | On a release package (version without `-dev`): `/dawnward dev story status` | "Developer commands are only available in development builds." `help all` doesn't list them |

#### Part Q: gameplay time (the narrative clock, v0.7-dev)

Automated: `tests/spec/narrative_clock_spec.lua` (L1/L2). The model is in [ARCHITECTURE.md](ARCHITECTURE.md#gameplay-time-the-narrative-clock). Use `/dawnward dev story status` to read the clock.

| # | Steps | Pass when |
|---|---|---|
| Q1 | Upgrade from v0.6, log in, `/dawnward dev story status` | "Narrative clock: … of play · narrative day 1". No error. Places, marks, Homeland and memories are all still there (Chronicle → Places, Memories) |
| Q2 | Stand in a place you already had logged before the upgrade, then `dev story status` | The last arrival says it was logged before gameplay time was tracked, and that time away starts counting from this visit. **No** burst of return moments after the upgrade |
| Q3 | Play for 10 minutes, then `dev story status` | The clock went up by about 10 minutes |
| Q4 | Note the clock, type `/afk`, run `dev story status`, wait 5 minutes, clear AFK, run it again | While AFK it says "The clock is paused: you are AFK." Afterwards the clock has not gained the AFK minutes |
| Q5 | Note the clock, `/reload`, then `dev story status` | The same value (plus seconds), not reset |
| Q6 | Note the clock, log out for at least an hour, log back in, then `dev story status` | The clock did **not** jump by the hour offline |
| Q7 | Log in on another character, then `dev story status` | Its own clock, not the first character's |
| Q8 | Cross between two zones every few minutes for 20 minutes | No return moments and no "returned to" lines in `story events` |
| Q9 | `/dawnward dev story simulate time 90m Goldshire`, then `… time 1d Goldshire` | 90 minutes: "no event", with the play still needed. 1 narrative day: a return, and for a marked place a moment is queued. Afterwards `dev story status` shows the clock unchanged |
| Q10 | Settings → Story → **Story pace**: Brisk, then `dev story status`; set it back to Standard | The narrative day becomes 1 h of play, and returns need less play accordingly |
| Q11 | Change the computer's date or time forward a day, `/reload`, then `dev story status`; set it back | The narrative clock is unaffected |

#### Part R: v0.7 window shell, Character Showcase and fonts (stage A)

Automated: `tests/spec/ui_shell_spec.lua` (L2) proves the wiring only. Compare each screen with its approved mockup in [design/mockups](design/mockups/README.md); differences that Classic Era cannot avoid are listed in [UI_DESIGN_V07.md](design/UI_DESIGN_V07.md#3-classic-era-limits-and-the-closest-alternatives). Part R checks the shell, rail and fonts; the screens themselves are in part S.

| # | Steps | Pass when |
|---|---|---|
| R1 | Upgrade from v0.6, `/dawnward` | The window opens with a rail on the left. No Lua error. Every section, entry and setting from v0.6 is still there |
| R2 | Look at the rail on a character with a profile name and title | Your profile name and title, then race · class · pronouns, and your real level. With no profile name, your character's name |
| R3 | Compare the rail with the mockups | Same order: portrait, name, title, identity line, level, navigation, Guide and Settings at the bottom |
| R4 | Look at the portrait | Your own portrait, round, inside a gold ring that sits centred on it (not cut off or offset) |
| R5 | Look at the four navigation icons | Each shows an icon (no green square or blank). Click each: the section changes and the selected one is marked |
| R6 | Leave a moment unanswered, then look at Story in the rail | A badge with the number waiting |
| R7 | Character → **Showcase** | Your character in the gear you are wearing. ‹ and › turn it; dragging turns it (more in S4) |
| R8 | Change a piece of gear with the journal open on Character | The model updates |
| R9 | Character → Profile fields, Edit a field, then cancel | The section's header buttons hide while editing and come back afterwards |
| R10 | Close the journal | The model is gone; frame rate is the same as with the addon closed |
| R11 | Read text in every section | Titles in Cinzel, text in Alegreya Sans; nothing clipped or overlapping. (On a non-English client: the game's fonts, and nothing missing) |
| R12 | Set UI scale to the smallest and largest values, and try a 1366×768 window | The whole window fits on screen in every case |
| R13 | Switch theme to each of the six themes (Settings → General → Appearance) | Every theme repaints the rail, header and Showcase frame |
| R14 | With Total RP 3 off, and then on; click the rail line | The rail line says "not installed (optional)" or names your TRP3 profile, and opens the Total RP 3 page. Nothing is written to Total RP 3 |

#### Part S: the integrated v0.7 build (every screen), in priority order

Build: **0.7.0-dev** from `main`. Everything here has passed automated tests (L2) only. Compare each screen with its mockup in [design/mockups](design/mockups/README.md); known, accepted differences are in [UI_DESIGN_V07.md](design/UI_DESIGN_V07.md#4-audit-each-screen-against-its-mockup). Before you start: close the game, back up `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua` (and Total RP 3's), then install the package.

**S1. Startup and Lua errors** (do this first; stop and report if it fails)

| # | Check |
|---|---|
| S1.1 | Turn on Lua errors (`/console scriptErrors 1`). Log in on a character that used v0.6: no Lua error at login, and `/dawnward status` reports 0.7.0-dev |
| S1.2 | `/dawnward` opens the window; open every section and every Chronicle tab and Settings page once: no Lua error |
| S1.3 | `/reload` with the window open: no error, and it opens again cleanly |

**S2. Window scaling and layout:** part R, steps R11 to R13 (fonts, UI scale, 1366×768, themes). No overlapping or clipped text anywhere.

**S3. Character rail:** part R, steps R2 to R6 and R14.

**S4. Character profile and Showcase**

| # | Check |
|---|---|
| S4.1 | Character: three left panels (Identity, Background & biography, Summary & motivation), tiles three to a row; Personality and Family & relationships on the right; each set field has a visibility chip and Edit inside its tile. |
| S4.2 | Click a chip to cycle; Edit a field: Enter saves, Escape cancels, empty value shows its error under the field; Add opens the editor on an empty field. |
| S4.3 | Answer a moment that proposes a personality change (approval "ask"): "1 change waits…", per-axis note; "Review in Story" opens Story. |
| S4.4 | v0.10: no visibility chips and no "Preview public view". An older character shows the one-line callout with "Publish whole profile…"; confirming publishes the whole profile and the callout goes. |
| S4.5 | "Total RP 3…" opens Settings → Total RP 3. |
| S4.6 | "Showcase": live model in current gear; turn with < >, drag, wheel; zoom - +; equip another item and the model updates. |
| S4.7 | "In game": level, race, class (class colour), guild (or "No guild"), realm; "Your character": only what you wrote, with visibility chips. |
| S4.8 | "Show portrait instead", /reload, reopen Showcase: choice kept. Switch back to the live model. |
| S4.9 | Close the journal with the Showcase open: no frame-rate cost; reopen: model reloads. |
| S4.10 | Chips and knobs layer correctly over the model; the portrait ring is aligned. |

**S5. Journal dashboard**

| # | Check |
|---|---|
| S5.1 | /dawnward on Journal: heading "The road so far"; subline shows real entry count, defining moments, "last entry today". |
| S5.2 | + New entry, title+text, save: card at top with date block and "Your words". Edit changes it; Delete asks first. |
| S5.3 | Type your current subzone in search: only entries recorded there remain. Clear it. |
| S5.4 | Defining / Story / Events / All: only matching entries show. |
| S5.5 | Raise a moment (complete a quest): "A moment awaits · 1 of 1" with the question. Later hides it (still in Story). Raise another, Answer opens Story on it. |
| S5.6 | Story draft card: "Waiting for your approval" chip; Approve then Defining update the chips; Public only after approval. |
| S5.7 | Goal with a level target: shows in Active goals with bar and "Level X of N · verified"; All opens Chronicle → Goals. |
| S5.8 | New subzone appears at the top of Recent places; Homeland/Meaningful chips after marking in Chronicle → Places. |
| S5.9 | No overlap/clipping at your UI scale; pager appears beyond 10 entries. |

**S6. Chronicle**

| # | Check |
|---|---|
| S6.1 | Chronicle: heading CHRONICLE / Memories; tabs show counts. |
| S6.2 | Memories → + New memory, save: card with Ordinary, Today, title, text, "Your words", "Established", Private chip; click it to cycle Private → Public → Secret. |
| S6.3 | Answer a moment that suggests a memory: gold-edged card "Suggested · needs your call"; Accept → Established; Remove asks first. |
| S6.4 | Search filters cards, count "x of y"; no match → "Nothing matches…"; switching tab clears the search. |
| S6.5 | Goals: add a goal, Steps → two milestones, tick one: bar half full, "1/2 milestones"; target level shows "level a/b". |
| S6.6 | Arcs, Stances, People, Review: cards, actions (Turn, Inner, Edit), empty-state text on a fresh character. |
| S6.7 | Places: list with zone · kind and visits; select one: first visit, Last here, Next return moment. Mark meaningful: star in list, chip in detail. Set as homeland: confirm, hearthstone icon renders, button greys out, note shows the Homeland field's visibility. |
| S6.8 | Write a memory here: appears under Tied memories and in Memories. |
| S6.9 | Text fits at UI scale 1.0 and smaller; long text cuts off inside the card; buttons and chips stay inside. |

**S7. Story Director**

| # | Check |
|---|---|
| S7.1 | Story with nothing waiting: empty-state text, summary, "Nothing is waiting.", growth note; eyebrow "STORY". |
| S7.2 | Turn in a quest: card "A MOMENT FOR YOUR STORY" with "Quest completed · <zone>". Answer: Story opens on it, eyebrow "STORY · MOMENT 1 OF 1", chips place / Quest completed / Level N. |
| S7.3 | "Why now" readable; two columns of numbered choice cards with hints; no overlap at your UI scale. |
| S7.4 | Save answer with an empty text field: red inline error, moment stays. Type an answer and save: moment gone, status confirms. |
| S7.5 | Two moments waiting: click an "Also waiting" row and the ‹ › arrows; Later ("kept for later"), Not now, Reflect, Dismiss. |
| S7.6 | Answer a choice with a personality hint: under "Growth to approve" check the reason, Approve, then Reverse + Confirm (value steps back). Reject another. |
| S7.7 | Settings approval = automatic, answer a moment: change applies at once and shows under Applied with Reverse. |
| S7.8 | Return moment at your homeland or a place with an established memory: tie chip and "<Name> remembers: …" appear. |
| S7.9 | Switch themes: card, chips, labels, buttons repaint. |

**S8. First-time setup**

| # | Check |
|---|---|
| S8.1 | Brand-new character, open Dawnward: wizard opens, rail with Welcome current, "STEP 1 OF 6", "Next: Character". |
| S8.2 | Next: Character stage shows your portrait and "Name · Level N · race · class", Name suggested from the game. |
| S8.3 | Paste >100 characters into Title and press Next: red error under Title, wizard stays. Shorten: error clears, Next works. |
| S8.4 | Done stages show a check mark; click "Story" in the rail to jump there. |
| S8.5 | Privacy: three chips (Public green, Private grey, Secret salmon); TRP3 chip matches installed/loaded state. |
| S8.6 | Appearance: pick a theme (restyles at once). Escape, /reload, /dawnward setup: resumes on the same stage with answers. |
| S8.7 | Finish: two review panels; Finish opens the journal; Total RP 3 unchanged. |
| S8.8 | UI scale 0.64 with a small window: wizard fits on screen. |
| S8.9 | /dawnward dev setup: rail note and eyebrow say Preview; Save choices / Close preview behave as before. |

**S9. Gameplay-time progression:** part Q (Q1 to Q11). Q2 (no burst of return moments after upgrading) and Q6 (an hour offline adds nothing) matter most.

**S10. Total RP 3 sync and rollback** (a spare, non-default TRP3 profile only)

| # | Check |
|---|---|
| S10.1 | Without Total RP 3: Settings → Total RP 3 (or click the TRP3 line in the rail) says it is optional and Dawnward works fully without it. |
| S10.2 | TRP3 3.4.1, one Public fact: "Installed · 3.4.1 · supported", profile name with "not linked", Biography "Sync off", the public text in the preview. |
| S10.3 | Make a fact Private and one Secret: neither statement appears anywhere; only counts under Never shared. |
| S10.4 | Enable syncing biography… then Cancel: nothing changes. Enable + accept: chip "Needs your approval" (unless the automatic run already wrote). Approve and write: TRP3 About has the Chronicle block, your own text unchanged, a backup row appears. |
| S10.5 | In combat, and with the TRP3 About editor open: chip Waiting, Approve disabled. |
| S10.6 | Edit the Dawnward block in TRP3 and add a Public fact: Conflict callout, Approve disabled. Keep yours leaves your text and turns sync off. |
| S10.7 | Select a backup, Roll back…: Cancel does nothing; accept restores and names the safety backup. |
| S10.8 | Traits: make an axis Public, enable traits, check the preview line and proposed changes. |

**S11. SavedVariables persistence**

| # | Check |
|---|---|
| S11.1 | Make a change in each section (an entry, a field, a memory, a goal milestone, a marked place, the story pace, the Showcase portrait choice). Log out fully, log back in: every change is still there |
| S11.2 | Compare your SavedVariables backup with the new file (optional): nothing from v0.6 is missing |

**S12. Privacy and cross-character isolation**

| # | Check |
|---|---|
| S12.1 | Make one field Private and one Secret. They appear in no public preview, no share export (`/dawnward export share`) and nowhere on the Total RP 3 page except as counts |
| S12.2 | Log in on a second character: its rail, journal, places, narrative clock (`/dawnward dev story status`) and Showcase choice are its own; nothing from the first character shows |
| S12.3 | `/dawnward sim on`, change something, `/dawnward sim off`: the real character is unchanged |

#### Part T: fixes from the first in-game inspection (0.7.1-dev)

Run these first on the new build. Report each step as pass or fail, with any Lua error.

| # | Check | Pass when |
|---|---|---|
| T1 | Character → Showcase, wearing normal gear | Within a few seconds the chip says **Live model** and your character is shown in your gear. If it does not, run `/dawnward dev showcase` and send the four lines it prints |
| T2 | Turn (‹ ›, drag) and zoom (− +, mouse wheel) | The model turns and zooms; your equipment is unchanged |
| T3 | Click **Show portrait instead**, then **Show the live model**, three times | It switches every time; the chip says Portrait (your choice), then Live model |
| T4 | Choose the portrait, `/reload`, reopen the Showcase | Still the portrait; Show the live model brings the model back |
| T5 | Change a piece of gear with the Showcase open | The model updates |
| T6 | Close and reopen the journal on the Showcase; go through a loading screen (hearth, instance) and reopen | The live model comes back each time |
| T7 | Drag the gold grip in the bottom-right corner larger and smaller | The window scales smoothly, the top-left corner stays put, text stays readable, it never goes off screen, nothing overlaps |
| T8 | `/reload`, then log out and in | The window keeps the size you chose |
| T9 | Settings → General → **Reset window size** | Back to the design size (smaller only if your screen needs it) |
| T10 | Change the game's UI scale (System → Interface) with the window open | The window still fits the screen |
| T11 | Chronicle → Review with a finding | The five answers look like buttons; hovering each explains it |
| T12 | Chronicle → Goals with a long goal name | Hovering the cut-off title shows it in full |
| T13 | Settings → Total RP 3 with backups | Each backup shows its name, and its full date on a second line, without crowding |
| T14 | Settings → Story | Each button reads like "Moments: Normal  ›"; clicking moves to the next option; the tooltip lists all options with the current one in [brackets] |

#### Part U: the first full playthrough (0.8.0-dev, pre-playthrough candidate)

Build: **0.8.0-dev** from `main`. Everything below passed automated tests (L2) only.

**Before you start:**
- Close the game. Back up `Interface\AddOns\DawnwardChronicles` and `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua`, plus Total RP 3's saved files.
- Install the new package.
- Use a **new character** for U1, and your existing test character for the rest.
- For Total RP 3, use a **spare, non-default profile**.
- Turn on Lua errors (`/console scriptErrors 1`) and report every error with its text.

Parts **T** (the 0.7.1 fixes) and **Q** (gameplay time) still apply; the steps below refer to them where they cover the same ground.

| # | Area | Steps | Pass when |
|---|---|---|---|
| U1 | New-character onboarding | Log in on a brand-new character | The setup wizard opens by itself once. Go through all six steps, and on the Character step use **Import a story...** with a short backstory. Close it mid-way, `/reload`: it resumes where you left off. Finish: the journal opens; nothing is sent to Total RP 3 |
| U2 | Character profile | Character: fill name, title, pronouns, homeland, faith, summary | Tiles and cards show the value and Edit only; no Public / Private / Secret anywhere; an older character shows the "Publish whole profile…" callout until confirmed |
| U3 | Story import | `/dawnward biography`: approve one piece (edited), skip one, keep one for later; approve one as Public | Only approved pieces become facts (Private by default). Public asks first and shows the exact text. Re-saving the same story suggests only new sentences |
| U4 | Character Showcase | Character → **Showcase** | The live model in your gear (else run `/dawnward dev showcase` and send the lines). Portrait ↔ live model switches every time (part T1–T6) |
| U5 | Resizable window | Drag the gold grip; `/reload`; Settings → General → Reset window size | Part T7–T10 |
| U6 | Journal and memories | Level up, complete quests, write an entry, answer moments | Entries appear with date, place and level. Search and filters work. Making an entry Public asks first. Memories show in Chronicle |
| U7 | Story Director | Play normally for an hour or two | Moments appear at calm moments only: never in combat, while AFK, or inside a dungeon. "Why now" reads true. The same question about the same place is not asked again within 3 narrative days. `/dawnward dev story status` explains every suppression |
| U8 | Narrative gameplay time | `/dawnward dev story status` now and after an hour offline | The clock counts play only (part Q). Story pace in Settings → Story changes the day length |
| U9 | Goals and arcs | Add a level goal and a reputation goal; get an arc suggestion and remove it | Progress follows verified level-ups and standing changes, and "why now" mentions the goal. No goal completes by itself. A removed arc suggestion is not suggested again |
| U10 | Personality development | Answer a moment that proposes a change; approve one, reject one, reverse one. Lock an axis (click it in Character → Personality) | Nothing changes without your approval. A locked axis is never proposed. Your own axis words show |
| U11 | Location returns | Mark a place meaningful or set your Homeland; leave for one narrative day of play; come back | One return moment. Crossing back and forth again asks nothing. Lion's Pride Inn is logged under Elwynn Forest (see #48 steps) |
| U12 | Automatic Total RP 3 sync | Settings → Total RP 3 → **Mappings**: set Race to Dawnward (Race Public in Dawnward), **Authorize…** | The preview names exactly what is written. After authorising, TRP3 shows the value within a few seconds and updates by itself when you change it in Dawnward. A field you edited in TRP3 is never overwritten |
| U13 | TRP3 conflicts and rollback | Edit the managed Race in TRP3, then change it in Dawnward; then roll back a backup | A conflict notice, with your TRP3 value kept; Keep yours / Use Dawnward's works. The rollback preview lists anything no longer Public. The default rollback never makes it visible again |
| U14 | Cross-character isolation | Log in on a second character | Its own journal, places, clock, Showcase choice and TRP3 mappings. Nothing from the first character shows. A shared TRP3 profile shows a warning |
| U15 | Logout and reload persistence | Change something in every section, log out fully, log back in | Everything is still there; no new Total RP 3 write or conflict on login |
| U16 | Import/export recovery | `/dawnward export backup`; add a memory; `/dawnward import` the backup | The preview lists "now → after" per record type. Confirm, then `/dawnward import undo` restores the memory |

**Also report:** for any moment that felt repetitive, wrong or badly timed, its text and what you were doing. Then send screenshots of each screen beside its mockup, for the v0.8 visual comparison.

#### Part V: v0.8 visual acceptance (compare each screen with its approved rendering)

Do this after part U. For each screen:
- open it in game at your normal UI scale, beside its mockup in [design/mockups](design/mockups/README.md);
- follow the numbered acceptance steps at the end of its audit;
- then repeat a quick look at window scale 0.7 (drag the grip smaller) and in one other theme.

| # | Screen | Mockup | Steps |
|---|---|---|---|
| V1 | Window, rail, design system | journal-dashboard.png, design-system.png | [shell-and-components.md](design/audit/shell-and-components.md) section 5 |
| V2 | Journal | journal-dashboard.png | [journal.md](design/audit/journal.md) section 10 |
| V3 | Character and Showcase | character-profile.png, proposed-character-showcase.png | [character.md](design/audit/character.md) section 6 |
| V4 | Story Director | story-director.png | [story.md](design/audit/story.md), last section |
| V5 | Chronicle and Places | chronicle-memories.png, chronicle-places.png | [chronicle.md](design/audit/chronicle.md) section 8 |
| V6 | Settings, setup, Total RP 3 page, import | first-time-setup.png, proposed-trp3-sync.png | [settings-setup-trp3.md](design/audit/settings-setup-trp3.md) section 8 |

**Pass when:**
- nothing overlaps;
- no important text is cut off without a way to read it in full (hover or Read);
- round shapes are round, or tidy squares if masks are unsupported;
- every control works by mouse and keyboard;
- each theme repaints everything.

**Report:** a screenshot of each screen beside its mockup, and the differences you would still like closed, in order.

**Screenshots requested:** Journal, Character (profile and Showcase), Story, Chronicle (Memories and Places), setup and the Total RP 3 page, at your normal UI scale, so they can be compared side by side with the mockups and, once approved, replace the concepts in the README. Crop or blur anything you would rather not share.

**Report:**
- Which steps passed, with your game version, UI scale and resolution.
- Every Lua error, with its text.
- Any screen that looks wrong: describe it, or attach a screenshot if you're happy to share one.

**Not covered yet:**
- Scroll bars keep the stock Blizzard style.
- Localised clients are untested.
- Nothing has been tested on WoW Forever.

### v0.9 in-game checklist (L3): first login and the complete Total RP 3 profile

Build: **0.9.0-dev**. Everything below has passed mocked tests (L2) only. Turn on Lua errors (`/console scriptErrors 1`) first and report every error with its text.

**Before you start:**
- Close the game. Back up `Interface\AddOns\DawnwardChronicles` and `WTF\Account\<account>\SavedVariables\DawnwardChronicles*.lua` and `totalRP3*.lua` (with their `.bak` files).
- For every Total RP 3 step, use a **spare, non-default Total RP 3 profile**.

#### Part W: first login and setup (automated: `tests/spec/first_login_spec.lua`, `publication_spec.lua`)

| # | Steps | Pass when |
|---|---|---|
| W1 | Create a brand-new character and enter the world. Do **not** type anything | After the intro cinematic, and a few seconds after the world appears, the setup wizard opens by itself (eyebrow "FIRST-TIME SETUP"). Not during the cinematic or the loading screen |
| W2 | On W1's character, check the step rail | Welcome, Character, Story, Appearance, Total RP 3 (only with Total RP 3 installed), Finish. **No Privacy stage.** "STEP n OF m" counts only the stages shown |
| W3 | Close the wizard at the Story stage (X), `/reload` | It does **not** open by itself again. A chat line says setup is unfinished, and a dialog asks "Continue setting up …?". **Resume** opens it on Story with your answers kept |
| W4 | Log out and back in (W3 still unfinished) | The offer appears again (once per session); nothing opens by itself |
| W5 | Enter combat (attack a training dummy or a critter) on a second new character right as you enter the world | The wizard waits; it opens a few seconds after combat ends |
| W6 | Finish setup with a Name and Homeland | The journal opens. Character tab: Name and Homeland are **Public** (no classification needed). Write a journal entry: it is **Private** |
| W7 | `/reload`, log out and in | The wizard never opens by itself again; `/dawnward dev setup status` says "Setup: complete (wizard version 2…)" and "Publication model: profile" |
| W8 | On your established v0.8 character, log in | Nothing opens. Its items keep their visibility. `/dawnward publish` previews counts per category and changes nothing |
| W9 | `/dawnward publish fields,biography confirm` on W8's character | Only Private profile fields and the biography become Public; Secret ones stay Secret; the journal is unchanged |
| W10 | A character on another realm with the same name | Gets its own first-login wizard; the first character's choice does not carry over |
| W11 | Total RP 3 stage, default TRP3 profile active | "Cannot connect right now: … default profile …"; the choice is disabled; Finish completes setup without connecting |
| W12 | Total RP 3 stage, spare profile active, Connect, Keep | Finish: chat confirms the authorisation; a few seconds later Dawnward writes (part X). Your own TRP3 text is untouched |

#### Part X: the complete Total RP 3 profile (automated: `trp3_profile_fields_spec.lua`, `trp3_about_doc_spec.lua`, `trp3_connected_profile_spec.lua`)

Use a **spare, non-default** Total RP 3 profile. Note the time of each step so it can be matched to `/dawnward trp3 log`.

| # | Steps | Pass when |
|---|---|---|
| X1 | Import a long backstory with headings (`# The fall of Lordaeron` on its own line), via the setup Story stage or `/dawnward biography`. For the owner: use Kyssarra Dawnward's complete backstory | Saved word for word; `/dawnward biography status` says "public" on a character set up with v0.9 |
| X2 | Settings > Total RP 3 > Overview > **Connect everything…**, confirm | Within a few seconds Total RP 3's About page shows your own text first, then Dawnward's sections; every paragraph of the story is there, in order, under your own headings |
| X3 | Open Total RP 3's characteristics | First name, last name, title, race, class, age, birthplace, residence, eye colour, height, body shape, relationship status hold your Public values; Pronouns, Faith, Occupation, Allegiance appear under additional information; personality bars match your Public axes |
| X4 | Edit one paragraph of the story in Dawnward (Load saved story, change, Save) | Total RP 3 updates the paragraph in place; nothing appears twice |
| X5 | Overview > Template: **Frames**, then **Sections**, then **Keep** | Frames: one frame per section with icons; Sections: appearance under physical description, history holds the story; your own text in the old template untouched |
| X6 | Overview > Style: **Arcane** | Violet headings with section icons; icons render (no green squares) |
| X7 | In Total RP 3, edit a sentence inside Dawnward's section and Save | Overview shows a conflict; Dawnward never overwrites it until you choose |
| X8 | Make Faith Private in Dawnward | It disappears from Total RP 3's additional information within seconds |
| X9 | Overview > **Preview profile** | A copy window lists the About page, fields and traits; nothing is written (`trp3 log` unchanged) |
| X10 | Roll back the newest backup (Roll back…) | Your own text returns; Dawnward's part is rebuilt from what is Public now |
| X11 | `/reload`, then wait | Nothing is written again (no duplicate, `trp3 log` shows no new write) |
| X12 | Second client (or a friend) targets you after X2 | They see the About page and fields after Total RP 3's normal refresh (at most every 10 s per target) |
| X13 | Character created before v0.9: Overview > **Use the profile model…** | The confirmation counts Private, Secret and Public items per category; Secret stays Secret |

#### Part Y: the complete-biography regression (automated: `trp3_biography_regression_spec.lua`)

The automated run (L2, TRP3 3.4.1 fake) imports one long backstory of plain paragraphs and checks fifteen guarantees in templates 1, 2 and 3. It always runs a public stand-in with the same shape (`tests/fixtures/backstory_paragraphs.lua`). It also runs the owner's real backstory when a private copy is at `private/fixtures/kyssarra_backstory.txt` (git-ignored, never committed); CI does not have that copy.

| # | Guarantee | Automated (L2) | Still needs the game (L3) |
|---|---|---|---|
| 1 | The whole biography imports into Dawnward | Byte for byte; reviewing it in pieces leaves the source unchanged | Paste into the 16 KB import box: Y1 |
| 2 | Every paragraph intact | Same paragraphs, same order, one blank line between each | Y1 |
| 3 | Nothing truncated or rewritten | Stored length equals the original; every sentence published | Y2 |
| 4 | It appears in TRP3 About after authorisation | Written on the first sync after Authorize | Y2 |
| 5 | Template 1 shows the whole text | Every paragraph once, after the player's own text | How TRP3 renders a long text: Y2 |
| 6 | Template 2 frames lose no sentence | Every sentence across the frames; each frame within size limit | Y3 |
| 7 | Template 3 puts content in the right section | The story in the history; the player's appearance and notes kept first | Y3 |
| 8 | Formatting, icons and backgrounds | TRP3 heading tags; each Dawnward frame has an icon and background; the player's frame unchanged | Icons render (no green squares): Y3 |
| 9 | An edit updates Dawnward's part | Only Dawnward's part changes; the player's text outside it is kept | Y4 |
| 10 | A second sync duplicates nothing | No-op, and the first paragraph appears once | Y5 |
| 11 | Unrelated TRP3 content untouched | Characteristics and character info are deep-equal before and after | Y6 |
| 12 | Conflicts | A hand edit inside Dawnward's part pauses sync; the edit is kept | Y6 |
| 13 | Backup and rollback | Backup before the first write; preview changes nothing; rollback restores the player's text | Y7 |
| 14 | Persists across reload | After a SavedVariables round trip the record survives and the next sync is a no-op | Y8 |
| 15 | Stays with its character and profile | Another character can't take the profile's About page; another TRP3 profile is never written | Y9 |

**In game.** Use a **new test character** and a **spare, non-default Total RP 3 profile**. Do not test on Kyssarra's real profile. Back up `WTF` first.

| # | Steps | Pass when |
|---|---|---|
| Y1 | Setup's Story stage (or Character > Import a story), paste the complete backstory, Save | `/dawnward biography status` says stored; Load saved story shows every paragraph with its blank lines |
| Y2 | Total RP 3 > Overview > Connect everything…, template 1 | The About page shows your own text, then the whole story, every paragraph, nothing cut at the end |
| Y3 | Template Frames, then Sections | Frames: no sentence missing across frames, icons and backgrounds show; Sections: the story is in History |
| Y4 | Change one sentence in Dawnward, Save | TRP3 updates that sentence in place within seconds |
| Y5 | Wait, then `/dawnward trp3 log` | No second write; nothing duplicated |
| Y6 | In TRP3, edit a sentence inside Dawnward's section; also check name, race and traits | A conflict is shown; your edit stays; other TRP3 fields unchanged |
| Y7 | Roll back… the newest backup | Preview first; after confirming, your own About text returns |
| Y8 | `/reload` | No new write; the About page is unchanged |
| Y9 | Log in another character on the same TRP3 profile | It can't take the About page; switching TRP3 profiles pauses sync |

### v0.10 in-game acceptance gate (L3): release-blocking before the first playthrough

**Nothing below is passed until the owner has done it in Classic Era 1.15.9 with Total RP 3 3.4.1 and recorded the result.** Automated tests (L2) passing is not this gate.

**Before you start**
1. Close WoW. Back up `Interface\AddOns\DawnwardChronicles` and `WTF\Account\<account>\SavedVariables\` (DawnwardChronicles*.lua and totalRP3*.lua).
2. Install the build. Check `/dawnward status` shows 0.10.0-dev.
3. Use a **new test character** for Z1–Z3. For Z4 onwards, use either that character or Kyssarra with a **spare, non-default** TRP3 profile created in Z3 (never Kyssarra's real profile).

**How to report a failure:** the step number, what you saw (a screenshot), and the output of `/dawnward trp3 diagnose` and `/dawnward trp3 log`. The diagnose output never contains your story text.

#### Part Z: v0.10 acceptance (each item release-blocking)

| # | Steps | Pass when |
|---|---|---|
| Z1 | Log in a brand-new character; wait in the world | Setup opens by itself within a few seconds (not during combat or a loading screen) |
| Z2 | Fill in name, title and other details; Story stage: **Import a story…**, paste the complete backstory, Save; reach Finish; `/reload` | The review page lists your details; after Finish and `/reload` setup does not open again; Character page shows your details |
| Z3 | Run setup on a character whose TRP3 profile is the default one; at the Total RP 3 stage: **Create a profile…** (or Switch profile…), confirm; **Refresh connection**; Finish with Connect | TRP3 > Profiles lists the new profile, active for this character; the default profile is unchanged; the stage shows Connect available before Finish |
| Z4 | After Z3, open TRP3 > your profile > **About** (close and reopen the tab if it was open) | The complete story is there, every paragraph in order, nothing cut at the end, nothing twice. `/dawnward trp3 diagnose`: "biography in the profile Dawnward publishes: yes", "last read-back: matched what was written" |
| Z4b | **Kyssarra (updated from 0.9):** `/dawnward trp3 diagnose`, then **Publish whole profile…** (Total RP 3 page or Character page) or `/dawnward publish confirm` | Diagnose says "waiting for your one-time confirmation" first; after confirming, the About page shows the story within seconds |
| Z5 | `/reload`, reopen the About tab; `/dawnward trp3 log` | The About page is unchanged; the log shows no new About write |
| Z6 | Change one sentence of the story in Dawnward (Character > Import a story > Load saved story, edit, Save) | Within seconds the About page shows the changed sentence in place; nothing duplicated |
| Z7 | Open TRP3 Characteristics and Miscellaneous | Name, title, race, class, age, birthplace, residence, eye colour, height, weight, relationship status hold your Dawnward values; Race and Class match the game if you never wrote them; Pronouns, Faith, Occupation, Allegiance appear as additional information with icons, each once |
| Z8 | Character > Personality: change an axis value; rename an axis's words | The matching TRP3 personality bar moves the same way (a high Dawnward value leans right); the trait's names change in place; your own TRP3 traits are untouched |
| Z9 | Dawnward Settings > Total RP 3 > Biography: try template Frames, then Sections, then Text; style Silver Hand and Arcane; compare the Dawnward preview with TRP3's About page | Frames: one frame per section with icons and backgrounds; Sections: the story under History; headings coloured; no green squares (missing icons) |
| Z10 | Visit every Dawnward screen (Journal, Character, Story, every Chronicle tab, Settings pages, Total RP 3 page, setup, Import a story) | No Public / Private / Secret badges, toggles or "only Public…" wording anywhere |
| Z11 | Compare the Journal, memories, goals, story answers and Character details with before the update | Every record is still there |
| Z12 | Before and after Z4–Z9, compare TRP3 parts Dawnward does not manage (your own About text above Dawnward's part, your own traits, Notes, RP status and style) | Unchanged |
| Z13 | Drag the gold resize grip to both limits; Settings > General > Reset Window Size; scroll the Character left column, the Chronicle list and Read view, and the Journal with the wheel | The window scales; nothing overlaps or disappears; the wheel never zooms the camera over the window |
| Z14 | Character > Showcase: live model loads; rotate; zoom; switch to portrait and back; `/reload` | The model fills its card; the toggle works both ways; the choice is remembered; equipment is unchanged |
| Z15 | Screenshot every screen and compare side by side with `docs/design/mockups/`; check line icons, tracked eyebrows and the new fonts render (no squares, no overlapping letters) in all three themes | The owner judges each screen against its rendering; record differences against `docs/design/UI_DESIGN_V10.md` |
