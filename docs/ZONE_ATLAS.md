# Zone Atlas (#48)

How Dawnward knows where a character is, how sure it is, and how to check it.

## Rules
- **Never invent an ID.** An area or map is classified only when its ID came from the client's own data. A place with no verified ID is logged as a visit and never classified (for example Lion's Pride Inn).
- **Evidence is labelled per entry** (`Core/Atlas.lua`, `Atlas.Level`):
  - `unverified`: no evidence for this client. Every WoW Forever entry is unverified today.
  - `source`: checked against the client's data tables for one build. For Classic Era that means PR #47, against wago.tools `UiMap` and `AreaTable` for 1.15.9.70576. It has not been re-checked since.
  - `in-game`: the running client returned the expected name. Owner-reported, with the date.
- **In-game evidence is kept verbatim** in `tools/atlas/evidence/`: the owner's `/dawnward atlas export` and `/dawnward atlas scan 1 5000` from Classic Era 1.15.9.70576 (2026-10-28, #48, manual tests M17 and M18). Their SHA-256 values match the ones published in #48, and `tools/atlas/client_db.py selftest` (run by `tools/check.py`) checks them. The scan has no parent maps, so it confirms names only.
- **WoW Forever is kept separate.** `Places.DATA` has no `forever` entry, so nothing is classified there. Issue #24 decides Forever compatibility; nothing here claims it.
- **Raw client database files never ship.** They may only live in `data/reference/client-db/` on the reference branch, once their provenance and redistribution rights are confirmed. `tools/check.py` refuses `.dbc`, `.db2` and `.scn` files inside `DawnwardChronicles/`, and `tools/package.py` packages only the addon folder.

## Checking in game: `/dawnward atlas`
Uses supported APIs only: `C_Map.GetAreaInfo`, `C_Map.GetMapInfo` and `C_Map.GetBestMapForUnit` (see COMPATIBILITY.md). It reads and reports, and never saves anything.

| Command | What it shows |
|---|---|
| `/dawnward atlas` | Zone, subzone, uiMap with its name and parent, and the resolved area ID with its evidence level. A subzone with no verified ID says so; a candidate settlement is named with its ID; a building the client reported as the zone is shown with that text |
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

Capitals (uiMap, whole zone): Stormwind City 1453, Orgrimmar 1454, Ironforge 1455, Thunder Bluff 1456, Darnassus 1457, Undercity 1458.

All 17 maps and 49 areas have `in-game` evidence: the 2026-10-28 atlas export matched every one (66 match, 0 renamed, 0 missing). Elwynn Forest 1429, Northshire Valley 9 and Goldshire 87 were also seen while playing on 2026-10-26.

| Area ID | Name (enUS) | Zone (uiMap) | Kind | Starting races | Evidence |
|---|---|---|---|---|---|
| 362 | Razor Hill | Durotar (1411) | town | — | in-game (atlas export, 2026-10-28) |
| 363 | Valley of Trials | Durotar (1411) | start | Orc, Troll | in-game (atlas export, 2026-10-28) |
| 364 | The Den | Durotar (1411) | start | Orc, Troll | in-game (atlas export, 2026-10-28) |
| 365 | Burning Blade Coven | Durotar (1411) | start | Orc, Troll | in-game (atlas export, 2026-10-28) |
| 367 | Sen'jin Village | Durotar (1411) | town | — | in-game (atlas export, 2026-10-28) |
| 1296 | Rocktusk Farm | Durotar (1411) | farm | — | in-game (atlas export, 2026-10-28) |
| 1297 | Jaggedswine Farm | Durotar (1411) | farm | — | in-game (atlas export, 2026-10-28) |
| 2979 | Tor'kren Farm | Durotar (1411) | farm | — | in-game (atlas export, 2026-10-28) |
| 220 | Red Cloud Mesa | Mulgore (1412) | start | Tauren | in-game (atlas export, 2026-10-28) |
| 221 | Camp Narache | Mulgore (1412) | start | Tauren | in-game (atlas export, 2026-10-28) |
| 222 | Bloodhoof Village | Mulgore (1412) | town | — | in-game (atlas export, 2026-10-28) |
| 358 | Brambleblade Ravine | Mulgore (1412) | start | Tauren | in-game (atlas export, 2026-10-28) |
| 380 | The Crossroads | The Barrens (1413) | town | — | in-game (atlas export, 2026-10-28) |
| 153 | Ruins of Lordaeron | Tirisfal Glades (1420) | ruins | — | in-game (atlas export, 2026-10-28) |
| 154 | Deathknell | Tirisfal Glades (1420) | start | Scourge | in-game (atlas export, 2026-10-28) |
| 155 | Night Web's Hollow | Tirisfal Glades (1420) | start | Scourge | in-game (atlas export, 2026-10-28) |
| 156 | Solliden Farmstead | Tirisfal Glades (1420) | farm | — | in-game (atlas export, 2026-10-28) |
| 159 | Brill | Tirisfal Glades (1420) | town | — | in-game (atlas export, 2026-10-28) |
| 165 | Balnir Farmstead | Tirisfal Glades (1420) | farm | — | in-game (atlas export, 2026-10-28) |
| 2117 | Shadow Grave | Tirisfal Glades (1420) | start | Scourge | in-game (atlas export, 2026-10-28) |
| 2119 | Gallows' End Tavern | Tirisfal Glades (1420) | inn | — | in-game (atlas export, 2026-10-28) |
| 77 | Anvilmar | Dun Morogh (1426) | start | Dwarf, Gnome | in-game (atlas export, 2026-10-28) |
| 131 | Kharanos | Dun Morogh (1426) | town | — | in-game (atlas export, 2026-10-28) |
| 132 | Coldridge Valley | Dun Morogh (1426) | start | Dwarf, Gnome | in-game (atlas export, 2026-10-28) |
| 803 | Amberstill Ranch | Dun Morogh (1426) | farm | — | in-game (atlas export, 2026-10-28) |
| 9 | Northshire Valley | Elwynn Forest (1429) | start | Human | in-game (owner, 2026-10-26) |
| 23 | Northshire River | Elwynn Forest (1429) | start | Human | in-game (atlas export, 2026-10-28) |
| 24 | Northshire Abbey | Elwynn Forest (1429) | start | Human | in-game (atlas export, 2026-10-28) |
| 34 | Echo Ridge Mine | Elwynn Forest (1429) | start | Human | in-game (atlas export, 2026-10-28) |
| 59 | Northshire Vineyards | Elwynn Forest (1429) | start | Human | in-game (atlas export, 2026-10-28) |
| 62 | Brackwell Pumpkin Patch | Elwynn Forest (1429) | farm | — | in-game (atlas export, 2026-10-28) |
| 63 | The Stonefield Farm | Elwynn Forest (1429) | farm | — | in-game (atlas export, 2026-10-28) |
| 64 | The Maclure Vineyards | Elwynn Forest (1429) | farm | — | in-game (atlas export, 2026-10-28) |
| 87 | Goldshire | Elwynn Forest (1429) | town | — | in-game (owner, 2026-10-26) |
| 2101 | Stoutlager Inn | Loch Modan (1432) | inn | — | in-game (atlas export, 2026-10-28) |
| 69 | Lakeshire | Redridge Mountains (1433) | town | — | in-game (atlas export, 2026-10-28) |
| 1001 | Lakeridge Highway | Redridge Mountains (1433) | road | — | in-game (atlas export, 2026-10-28) |
| 1002 | Three Corners | Redridge Mountains (1433) | road | — | in-game (atlas export, 2026-10-28) |
| 107 | Saldean's Farm | Westfall (1436) | farm | — | in-game (atlas export, 2026-10-28) |
| 108 | Sentinel Hill | Westfall (1436) | town | — | in-game (atlas export, 2026-10-28) |
| 109 | Furlbrow's Pumpkin Farm | Westfall (1436) | farm | — | in-game (atlas export, 2026-10-28) |
| 219 | Alexston Farmstead | Westfall (1436) | farm | — | in-game (atlas export, 2026-10-28) |
| 916 | The Jansen Stead | Westfall (1436) | farm | — | in-game (atlas export, 2026-10-28) |
| 918 | The Molsen Farm | Westfall (1436) | farm | — | in-game (atlas export, 2026-10-28) |
| 2104 | Deepwater Tavern | Wetlands (1437) | inn | — | in-game (atlas export, 2026-10-28) |
| 186 | Dolanaar | Teldrassil (1438) | town | — | in-game (atlas export, 2026-10-28) |
| 188 | Shadowglen | Teldrassil (1438) | start | NightElf | in-game (atlas export, 2026-10-28) |
| 256 | Aldrassil | Teldrassil (1438) | start | NightElf | in-game (atlas export, 2026-10-28) |
| 257 | Shadowthread Cave | Teldrassil (1438) | start | NightElf | in-game (atlas export, 2026-10-28) |
## Candidate settlements (`Atlas.CANDIDATES`)
49 settlements outside the starting zones, from the #48 analysis: Darkshire 42, Booty Bay 35, Grom'gol Base Camp 117, Rebel Camp 99, Stonard 75, Thelsamar 144, Algaz Station 925, Menethil Harbor 150, Southshore 271, Tarren Mill 272, Refuge Pointe 320, Hammerfall 321, Aerie Peak 348, Revantusk Village 3317, Kargath 340, Thorium Point 1446, Morgan's Vigil 2418, Nethergarde Keep 1438, The Sepulcher 228, Ambermill 233, Chillwind Camp 3197, Light's Hope Chapel 2268, Ratchet 392, Camp Taurajo 378, Auberdine 442, Astranaar 415, Splintertree Post 431, Zoram'gar Outpost 2897, Sun Rock Retreat 460, Stonetalon Peak 467, Freewind Post 484, Thalanaar 489, Nijel's Point 608, Shadowprey Village 2408, Theramore Isle 513, Brackenwall Village 496, Camp Mojache 1099, Feathermoon Stronghold 1116, Gadgetzan 976, Steamwheedle Port 977, Marshal's Refuge 541, Valormok 1237, Everlook 2255, Bloodvenom Post 1997, Talonbranch Glade 1998, Emerald Sanctuary 2479, Cenarion Hold 3425, Rut'theran Village 702 and the Shady Rest Inn 403.

- **What is verified:** each ID and its name, exactly as the in-game scan spells it (a test compares every candidate with the evidence file).
- **What is not:** the parent map, the kind and the faction relevance. The repository holds no client data with parent maps, so none of them is in `Places.DATA`. They are logged as ordinary visits, never classified, and never ask a question by themselves. `Atlas.Level` reports them as `unverified`.
- **To promote one:** stand in it and run `/dawnward atlas` (or `atlas export`). It names the candidate and the uiMap the client reports, which is the parent-map evidence. Then add it to `Places.DATA` with that map and a kind, to `EXPECTED`, and to `CONFIRMED` with the date.

## Data issues found in the evidence (#48 analysis)
- **A. Interiors reported as the zone (fixed, L2 only).** In Lion's Pride Inn the client's zone text was the inn and the subzone was empty, while the uiMap was Elwynn Forest. When there is no subzone and the zone text differs from the name of the zone-type uiMap (`C_Map.GetMapInfo`, `mapType` 3), Dawnward now records the map's name as the zone and the building as a place inside it (`Places.NormalizeLocation`). Without a zone-type map (continents, dungeon maps, no map) the text is kept as given. Places logged before keep their names. `/dawnward atlas` shows the client's own zone text when this happens. This rests on one observation, so the `/dump` checks in #48 (an inn, a Stormwind building, an Ironforge interior) are still wanted.
- **B. Trailing spaces (fixed).** Three client names end in a space (1221, 1997, 1998). Zone and subzone text is trimmed before logging, and area names compare without surrounding spaces, so a place is never logged twice under two spellings (saved keys were already trimmed on load). The data keeps the client's exact spelling.
- **C. One name, several IDs (guarded).** 46 names cover 123 IDs in the scan (40 names and 89 IDs once quarantined IDs are left out, as the #48 analysis counts them). Places resolves an area only among the IDs mapped for the observed uiMap. Candidates whose name has other IDs list them (`shared`: Southshore 271 and 2369, Tarren Mill 272 and 2368), and a test keeps that list equal to the scan.

## Quarantine (`Atlas.QUARANTINE`)
These IDs must never be classified, and a test checks that no mapped area is among them. On the 2026-10-28 scan the rules quarantine 93 IDs:
- 43 unused, deleted or placeholder names (`UNUSED`, `DELETE ME`, `Not Used`, `***On Map Dungeon***`);
- 9 test or development areas (22, 81–84, 151, 876, 1218, 2877);
- 9 to review before any use (21, 30, 32, 616, 676, 1397, 2366, 2367, 3459);
- 27 open-sea areas (The Great Sea, The Veiled Sea, The Forbidding Sea, South Seas);
- 5 of Arathi Basin's generic names (3420–3424: Farm, Blacksmith, Lumber Mill, Gold Mine, Stables), so they can never match a farm or mine elsewhere.

The other battleground areas (the analysis counts 45 in all) are not listed: Dawnward never records battlegrounds as places (`IsInInstance`).

**Known gaps:**
- Lion's Pride Inn was seen in game and is logged (now inside Elwynn Forest), but it has no AreaTable ID.
- Settlements outside the starting zones are candidates only (above): their parent maps are unverified.
- No wilderness or danger classifications: nothing in the client data marks an area as either.
- Localised clients: names differ, and `atlas verify` reports them as renamed.
- WoW Forever: no data at all.

**To widen coverage safely:** visit a candidate and run `/dawnward atlas export`, then paste it into #48. Add only IDs whose client name and parent uiMap are both confirmed, as `in-game`.
