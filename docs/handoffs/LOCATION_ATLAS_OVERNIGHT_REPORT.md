# Zone Atlas: overnight report (2026-10-27), issue #48

**Status:** increment delivered on `feat/v0.5-overhaul`. Issue #48 stays **open**.

## Client database reference files
- Branch `data/client-db-reference-import` was checked twice tonight (start and mid-session). Each time it held only `data/reference/client-db/README.md` (commit `aa2af12`). It had none of `areatable.dbc`, `areatable.db2`, `uimap.db2`, `uimapassignment.db2`, `wmoareatable.dbc`, `wmoareatable.db2` or `wmoareatable.scn`.
- So no binary was inspected, and nothing tonight comes from those files. Their provenance, client build and redistribution rights are still unknown.
- The reference branch was **not merged**. It must not be merged until provenance and redistribution rights are confirmed.

## What was built
1. **`Core/Atlas.lua`:** a provenance and evidence model.
   - Per client source: Classic Era is "PR #47, wago.tools UiMap and AreaTable, 1.15.9.70576, not re-checked"; Forever is "none".
   - Expected enUS names for all 49 mapped areas and 17 maps.
   - Owner-reported in-game confirmations: Elwynn Forest 1429, Northshire Valley 9, Goldshire 87.
   - Lion's Pride Inn is listed as seen but unmapped.
   - Every entry has an evidence level: `in-game`, `source` or `unverified`.
2. **`/dawnward atlas`** (`Platform/AtlasProbe.lua`): in-game verification through supported APIs only (`C_Map.GetAreaInfo`, `C_Map.GetMapInfo`, `C_Map.GetBestMapForUnit`, checked in Blizzard's Classic Era API documentation).
   - `atlas`: where you are and how sure the data is.
   - `atlas verify`: every expected ID against the client's own names (match, renamed or missing).
   - `atlas scan <from> <to>`: in-client extraction of area names, up to 5,000 IDs at a time.
   - `atlas export`: copies a report for this issue.
   - It is read-only and never creates a character record.
3. **`tools/atlas/client_db.py`:** a reusable offline pipeline for when the files arrive.
   - Header inspection for WDBC, WDB2, WDB5/6 and WDC1–5: counts, string block, and the table and layout hashes for identifying the build.
   - Full WDBC parsing, with string columns found by inspection.
   - AreaTable report: Classic world, later-expansion worlds or instance; agreement with Dawnward's expected names; IDs absent from the file.
   - A self-test runs in `tools/check.py`.
4. **Guards:**
   - `tools/check.py` refuses `.dbc`, `.db2` and `.scn` files inside the addon.
   - Packaging includes only `DawnwardChronicles/`.
   - Forever has no place data.
5. **Docs:**
   - `docs/ZONE_ATLAS.md`: rules, commands, pipeline and a coverage matrix of every mapped ID with its evidence.
   - `docs/COMPATIBILITY.md`: new API rows.

## Verified tonight
- The Atlas data agrees with `Places.DATA`: every mapped area and capital has an expected name, and every name has a mapped area (test).
- No new IDs were added. Nothing was promoted to `in-game` beyond the owner's 2026-10-26 results.

## Remaining gaps (acceptance criteria not yet met)
- No in-game run of `/dawnward atlas verify` or `scan` yet.
- No mapping for most settlements outside the starting zones, and none for wilderness or danger areas.
- Localised clients are untested.
- WoW Forever has no data at all.
- The reference binaries' provenance and redistribution rights are unknown.

## Morning steps
1. In Classic Era, run `/dawnward atlas` in Goldshire and in Lion's Pride Inn. Then run `/dawnward atlas verify` and `/dawnward atlas export`, and paste the export into #48.
2. Run `/dawnward atlas scan 1 5000` and paste it into #48. That dump can widen coverage with IDs the client itself confirms.
3. If the reference files are uploaded, run `python tools/atlas/client_db.py inspect data/reference/client-db/*` and then `python tools/atlas/client_db.py areatable data/reference/client-db/areatable.dbc --out areatable-report.json`. Record where the files came from and whether they may be redistributed.
