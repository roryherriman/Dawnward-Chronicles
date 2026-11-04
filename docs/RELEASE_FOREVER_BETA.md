# Private beta: two packages, installation and launch-night checks

Two packages are built from one source revision by `python tools/package.py`; only the TOC differs. Neither is published anywhere: this is a private beta.

| | Classic Era | WoW Forever |
|---|---|---|
| Zip | `DawnwardChronicles-ClassicEra-<version>.zip` | `DawnwardChronicles-Forever-v1.0.0-Beta.zip` |
| Name shown in game | Dawnward Chronicles `<version>` | Dawnward Chronicles 1.0.0 Beta |
| TOC version | the development version (0.10.x-dev) | `1.0.0-beta` (no developer commands) |
| Interface | 11509 (Classic Era 1.15.9, verified in game) | 16001 (Forever 1.60.1 build 70755: **static evidence only**, see below) |
| `## X-Dawnward-Target` | `classic` | `forever` |
| Total RP 3 writes | 3.4.1 (audited, used in play) | 3.5.4 (audited from source, provisional); any other version read-only |

Each zip has one root folder, `DawnwardChronicles`, and a `.sha256` and `.manifest.json` beside it naming the source commit.

## What is and is not verified

- **Classic Era:** L3 (in game) for the features listed in CHANGELOG up to 0.10.x; the Forever compatibility layer (`Platform/Compat.lua`) chooses the Classic functions whenever they exist, so Classic behaviour is unchanged (L2: the whole suite runs on the Classic mock).
- **WoW Forever:** **nothing has run in a Forever client.** The interface number, project id 18, and every API listed in [COMPATIBILITY.md](COMPATIBILITY.md) come from Blizzard's published UI source for Forever (`forever` branch, 1.60.1 build 70755) and are exercised against a mock that exposes only what that source shows (L2). Total RP 3 3.5.4 support comes from its source (Static) and a fake built from it (L2). See [FOREVER_LAUNCH_GATE.md](FOREVER_LAUNCH_GATE.md) for the issue #24 matrix.
- **Not known:** the exact Total RP 3 build on your Forever client, and your Forever installation folder. Run `tools/windows/Inspect-WoWForever.ps1` (read-only) and share its report.

## Before installing anything (both clients)

1. **Exit the game completely** (both clients) and wait until no `Wow*.exe` is running.
2. **Inspect (read-only):** in PowerShell, from the repository's `tools\windows` folder:
   `powershell -ExecutionPolicy Bypass -File .\Inspect-WoWForever.ps1`
   It lists your game flavour folders (Classic Era is `_classic_era_`; note the Forever folder's exact name), each client's build, every installed addon's TOC (Total RP 3 version and TOC hash) and which Dawnward / Total RP 3 SavedVariables exist. It writes nothing inside the WoW folder. The report is saved in `Desktop\Coding Projects\Dawnward Backups`.
3. **Back up each flavour separately:**
   `powershell -ExecutionPolicy Bypass -File .\Backup-DawnwardData.ps1 -Flavour _classic_era_`
   and, if the Forever folder already has Dawnward or Total RP 3 data, again with `-Flavour <Forever folder name>`.
   It refuses to run while the game runs, copies the `DawnwardChronicles` and `totalRP3*` addon folders and every `DawnwardChronicles*` / `totalRP3*` SavedVariables file (`.lua` and `.lua.bak`, account-wide and per character) into a new dated folder, and checks every copy against its original by SHA-256 (`manifest.csv`). Install only when it ends with "Every copy matches its original".
   (The scripts were reviewed but could not be run from the development environment; if one fails, back up by hand: copy those folders and files into a dated folder and compare `Get-FileHash` of each original and copy.)
4. **Check the zip:** `Get-FileHash .\<zip> -Algorithm SHA256` must equal the checksum given with the build.

## Installing

**Classic Era:** replace `World of Warcraft\_classic_era_\Interface\AddOns\DawnwardChronicles` with the folder from the Classic Era zip (delete the old folder, then extract so that `...\AddOns\DawnwardChronicles\DawnwardChronicles.toc` exists). Never touch `WTF`.

**WoW Forever:** extract the Forever zip into **the Forever folder's** `Interface\AddOns` (create `Interface\AddOns` if it does not exist yet), so that `...\<Forever folder>\Interface\AddOns\DawnwardChronicles\DawnwardChronicles.toc` exists. Make sure there is exactly one `DawnwardChronicles` folder there. Install Total RP 3 for Forever from its usual source; do not copy the Classic Era Total RP 3 folder.

- Each client keeps its own SavedVariables under its own `WTF` folder. **Do not copy Classic Era SavedVariables into Forever**: a Forever character starts fresh, and its own first-login setup runs.
- Use a **disposable test character and a new, non-default Total RP 3 profile** for the first Forever session (issue #24 forbids destructive testing on real profiles).

## Rolling back

Exit the game, delete the installed `DawnwardChronicles` folder of that flavour, and copy back the addon folder and SavedVariables files from the dated backup folder (same relative paths). Compare hashes with `manifest.csv`.

## Launch-night checks: WoW Forever (disposable character and profile)

Record for each: pass / fail, a screenshot on failure, and the output of `/dawnward status`, `/dawnward trp3 diagnose` and `/dawnward trp3 log`.

| # | Steps | Pass when |
|---|---|---|
| F1 | Character select > AddOns: Dawnward Chronicles is listed and not "out of date"; log in | Loads with no Lua error (enable `/console scriptErrors 1` first) |
| F2 | `/dump select(4, GetBuildInfo())` and `/dump WOW_PROJECT_ID` | 16001 and 18. **If not 16001, stop and report the number:** the package must be rebuilt |
| F3 | `/dawnward status` | "Dawnward Chronicles 1.0.0 Beta"; client "WoW Forever (provisional support)"; no "Package: built for" warning; no missing-API line (if there is one, copy it) |
| F4 | Open and close the window (minimap button, `/dawnward`), visit every screen | Nothing overlaps or is cut off; fonts and line icons draw |
| F5 | Character > Showcase: live model, rotate, portrait toggle | Model and portrait show |
| F6 | First login: setup opens by itself; fill details; Import a story (paste a short test story) | Setup completes; the story shows in Character |
| F7 | `/dawnward trp3 diagnose` | The installed Total RP 3 version; "3.5.4 … provisional" with writes allowed, or "read-only for Dawnward: nothing is written" for another version (then the TRP3 items below are expected to stay read-only: report the version) |
| F8 | Setup's Total RP 3 stage: **Create a profile…** (new, disposable); Connect | TRP3 > Profiles shows it, active; the default profile unchanged |
| F9 | TRP3 About, Characteristics (personality bars and their end icons), Miscellaneous | Story present once, in order; trait bars match; no green or question-mark icons |
| F10 | At First Glance suggestion: accept one | It appears in TRP3 At First Glance; your own slots untouched |
| F11 | Currently and OOC: set both in Dawnward | TRP3 shows them |
| F12 | Complete a quest; gain a level; enter a new zone | Each appears in the Journal / Story |
| F13 | Wait for a Story Director moment | A relevant card appears on screen (not in combat) |
| F14 | Answer it; approve a personality change; reverse it | Value moves one step and back; no "tomorrow" message |
| F15 | Chronicle > Memories | Verified events are "Recorded" ("Verified by the game"); interpretations are "Suggested" until accepted |
| F16 | `/reload` | Everything above is still there; TRP3 log shows no repeated write |
| F17 | Log out and back in | Same |
| F18 | Chronicle > Places | The zones you visited are listed (no Classic atlas classification is expected on Forever) |
| F19 | Throughout | No Lua error, no taint warning ("action blocked by an addon") |
| F20 | (Second client, if possible) view the test profile from another character | About, traits and status show; nothing private or unapproved |

## Classic Era regression (after installing the new Classic Era package)

`/dawnward status` shows the new version and "WoW Classic Era"; Kyssarra's journal, memories, pending suggestions and TRP3 profile are unchanged after login and `/reload`; one quest and one Story moment work as before; `/dawnward trp3 diagnose` still reports 3.4.1 as supported.
