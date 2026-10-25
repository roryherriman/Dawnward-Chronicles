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

**Notes for the tester**

- TRP3 rewrites its own saved file at every logout. For example, it regenerates the default profile ID at each login. So comparing TRP3's SavedVariables file before and after is not a valid test for step 19. Check TRP3's pages in game instead.
- Dawnward's data is in `WTF\Account\<account>\SavedVariables\DawnwardChronicles.lua`. Don't post that file publicly: it contains your private character data.
