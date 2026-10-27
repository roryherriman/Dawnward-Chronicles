# Unverified WoW client database reference files

These files are **research inputs only** for the Zone Atlas (issue #48), not verified Classic Era 1.15.x or WoW Forever datasets.

## Files to add to this directory
- `areatable.dbc`
- `areatable.db2`
- `uimap.db2`
- `uimapassignment.db2`
- `wmoareatable.dbc`
- `wmoareatable.db2`
- `wmoareatable.scn`

The owner downloaded these files separately. The source URL, exact client build, extraction method, schema and licensing/redistribution rights **have not been established**. Do not import wholesale or mark IDs as Classic Era-verified based solely on these files. The DBC AreaTable includes later-expansion areas.

## Required handling
1. Establish file provenance, applicable build, and redistribution rights before committing binaries.
2. Inspect headers, record layouts, string tables and IDs with build-appropriate parsers.
3. Separate confirmed Classic Era entries from provisional records and WoW Forever-specific data.
4. Prefer runtime `C_Map` verification where possible; document API limitations.
5. Keep this reference data out of packaged addon releases.
6. Do not close issue #48 solely because files are present; never alter the protected release gate #24.

The binary source files are **not yet uploaded** by this commit.
