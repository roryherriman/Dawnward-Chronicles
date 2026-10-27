# Zone Atlas (#48)

How Dawnward knows where a character is, how sure it is, and how to check it.

## Rules
- **Never invent an ID.** An area or map is classified only when its ID came from the client's own data. A place with no verified ID is logged as a visit and never classified (for example Lion's Pride Inn).
- **Evidence is labelled per entry** (`Core/Atlas.lua`, `Atlas.Level`):
  - `unverified`: no evidence for this client. Every WoW Forever entry is unverified today.
  - `source`: checked against the client's data tables for one build. For Classic Era that means PR #47, against wago.tools `UiMap` and `AreaTable` for 1.15.9.70576. It has not been re-checked since.
  - `in-game`: the running client returned the expected name. Owner-reported, with the date.
- **WoW Forever is kept separate.** `Places.DATA` has no `forever` entry, so nothing is classified there. Issue #24 decides Forever compatibility; nothing here claims it.
- **Raw client database files never ship.** They may only live in `data/reference/client-db/` on the reference branch, once their provenance and redistribution rights are confirmed. `tools/check.py` refuses `.dbc`, `.db2` and `.scn` files inside `DawnwardChronicles/`, and `tools/package.py` packages only the addon folder.

## Checking in game: `/dawnward atlas`
Uses supported APIs only: `C_Map.GetAreaInfo`, `C_Map.GetMapInfo` and `C_Map.GetBestMapForUnit` (see COMPATIBILITY.md). It reads and reports, and never saves anything.

| Command | What it shows |
|---|---|
| `/dawnward atlas` | Zone, subzone, uiMap with its name and parent, and the resolved area ID with its evidence level. A subzone with no verified ID says so |
| `/dawnward atlas verify` | Every expected map and area ID compared with the client's own names: match, renamed (often a localised client) or missing |
| `/dawnward atlas scan <from> <to>` | The client's name for every area ID in the range (up to 5,000 at a time), in a copy window. This is an in-client extraction through a supported API |
| `/dawnward atlas export` | The location and the full verify list in a copy window, to paste into #48 |

On any client other than Classic Era it first says the results are evidence only.

## Offline: `tools/atlas/client_db.py`
For the reference files the owner is staging on `data/client-db-reference-import`. Nothing is downloaded or modified.
- `inspect <files>`: header report for WDBC, WDB2, WDB5/6 and WDC1–5. It gives record and field counts, record size, string block size, and the table and layout hashes that identify a schema and build family. Unknown formats (for example `.scn`) are reported by their first bytes.
- `areatable <areatable.dbc> --out report.json`: parses a WDBC AreaTable and finds string columns by inspection. It sorts records into Classic world (maps 0 and 1), later-expansion worlds (530, 571, …) and instances or other maps, and compares every Dawnward expected name with the file. The id, map and parent columns follow the 1.x–3.x layout and must be checked against WoWDBDefs for the file's build.
- `selftest`: run by `tools/check.py`.

A file's agreement is **corroborating evidence only**. An ID becomes `in-game` only when the running Classic Era client confirms it.

## Coverage (Classic Era)

Capitals (uiMap, whole zone): Stormwind City 1453, Orgrimmar 1454, Ironforge 1455, Thunder Bluff 1456, Darnassus 1457, Undercity 1458. All have `source` evidence. Elwynn Forest 1429 has `in-game` evidence.

| Area ID | Name (enUS) | Zone (uiMap) | Kind | Starting races | Evidence |
|---|---|---|---|---|---|
| 362 | Razor Hill | Durotar (1411) | town | — | source (PR #47) |
| 363 | Valley of Trials | Durotar (1411) | start | Orc, Troll | source (PR #47) |
| 364 | The Den | Durotar (1411) | start | Orc, Troll | source (PR #47) |
| 365 | Burning Blade Coven | Durotar (1411) | start | Orc, Troll | source (PR #47) |
| 367 | Sen'jin Village | Durotar (1411) | town | — | source (PR #47) |
| 1296 | Rocktusk Farm | Durotar (1411) | farm | — | source (PR #47) |
| 1297 | Jaggedswine Farm | Durotar (1411) | farm | — | source (PR #47) |
| 2979 | Tor'kren Farm | Durotar (1411) | farm | — | source (PR #47) |
| 220 | Red Cloud Mesa | Mulgore (1412) | start | Tauren | source (PR #47) |
| 221 | Camp Narache | Mulgore (1412) | start | Tauren | source (PR #47) |
| 222 | Bloodhoof Village | Mulgore (1412) | town | — | source (PR #47) |
| 358 | Brambleblade Ravine | Mulgore (1412) | start | Tauren | source (PR #47) |
| 380 | The Crossroads | The Barrens (1413) | town | — | source (PR #47) |
| 153 | Ruins of Lordaeron | Tirisfal Glades (1420) | ruins | — | source (PR #47) |
| 154 | Deathknell | Tirisfal Glades (1420) | start | Scourge | source (PR #47) |
| 155 | Night Web's Hollow | Tirisfal Glades (1420) | start | Scourge | source (PR #47) |
| 156 | Solliden Farmstead | Tirisfal Glades (1420) | farm | — | source (PR #47) |
| 159 | Brill | Tirisfal Glades (1420) | town | — | source (PR #47) |
| 165 | Balnir Farmstead | Tirisfal Glades (1420) | farm | — | source (PR #47) |
| 2117 | Shadow Grave | Tirisfal Glades (1420) | start | Scourge | source (PR #47) |
| 2119 | Gallows' End Tavern | Tirisfal Glades (1420) | inn | — | source (PR #47) |
| 77 | Anvilmar | Dun Morogh (1426) | start | Dwarf, Gnome | source (PR #47) |
| 131 | Kharanos | Dun Morogh (1426) | town | — | source (PR #47) |
| 132 | Coldridge Valley | Dun Morogh (1426) | start | Dwarf, Gnome | source (PR #47) |
| 803 | Amberstill Ranch | Dun Morogh (1426) | farm | — | source (PR #47) |
| 9 | Northshire Valley | Elwynn Forest (1429) | start | Human | in-game (owner, 2026-10-26) |
| 23 | Northshire River | Elwynn Forest (1429) | start | Human | source (PR #47) |
| 24 | Northshire Abbey | Elwynn Forest (1429) | start | Human | source (PR #47) |
| 34 | Echo Ridge Mine | Elwynn Forest (1429) | start | Human | source (PR #47) |
| 59 | Northshire Vineyards | Elwynn Forest (1429) | start | Human | source (PR #47) |
| 62 | Brackwell Pumpkin Patch | Elwynn Forest (1429) | farm | — | source (PR #47) |
| 63 | The Stonefield Farm | Elwynn Forest (1429) | farm | — | source (PR #47) |
| 64 | The Maclure Vineyards | Elwynn Forest (1429) | farm | — | source (PR #47) |
| 87 | Goldshire | Elwynn Forest (1429) | town | — | in-game (owner, 2026-10-26) |
| 2101 | Stoutlager Inn | Loch Modan (1432) | inn | — | source (PR #47) |
| 69 | Lakeshire | Redridge Mountains (1433) | town | — | source (PR #47) |
| 1001 | Lakeridge Highway | Redridge Mountains (1433) | road | — | source (PR #47) |
| 1002 | Three Corners | Redridge Mountains (1433) | road | — | source (PR #47) |
| 107 | Saldean's Farm | Westfall (1436) | farm | — | source (PR #47) |
| 108 | Sentinel Hill | Westfall (1436) | town | — | source (PR #47) |
| 109 | Furlbrow's Pumpkin Farm | Westfall (1436) | farm | — | source (PR #47) |
| 219 | Alexston Farmstead | Westfall (1436) | farm | — | source (PR #47) |
| 916 | The Jansen Stead | Westfall (1436) | farm | — | source (PR #47) |
| 918 | The Molsen Farm | Westfall (1436) | farm | — | source (PR #47) |
| 2104 | Deepwater Tavern | Wetlands (1437) | inn | — | source (PR #47) |
| 186 | Dolanaar | Teldrassil (1438) | town | — | source (PR #47) |
| 188 | Shadowglen | Teldrassil (1438) | start | NightElf | source (PR #47) |
| 256 | Aldrassil | Teldrassil (1438) | start | NightElf | source (PR #47) |
| 257 | Shadowthread Cave | Teldrassil (1438) | start | NightElf | source (PR #47) |
**Known gaps:**
- Lion's Pride Inn was seen in game and is logged, but it has no verified ID.
- Most settlements outside the starting zones are not mapped: Stormwind's districts, Menethil Harbor, Thelsamar, Darkshire, Southshore, Tarren Mill, Astranaar, Auberdine, Ratchet, Camp Taurajo and others.
- No wilderness or danger classifications: nothing in the client data marks an area as either.
- Localised clients: names differ, and `atlas verify` reports them as renamed.
- WoW Forever: no data at all.

**To widen coverage safely:** run `/dawnward atlas scan 1 5000` on Classic Era 1.15.x and paste the result into #48. Then add only IDs whose client name and parent zone match, as `in-game`.
