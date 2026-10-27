-- The Zone Atlas (#48): where Dawnward's place data came from, how sure we
-- are of each entry, and the logic of the in-game verifier
-- (/dawnward atlas, Platform/AtlasProbe.lua). Pure: the client is reached
-- only through functions passed in, so this is tested without a game.
--
-- Evidence levels, weakest to strongest:
--   unverified   no evidence for this client (every WoW Forever entry today)
--   source       checked against the client's own data tables for one build
--                (Classic Era: PR #47, wago.tools UiMap and AreaTable,
--                1.15.9.70576; not re-checked since)
--   in-game      the running client returned the expected name for the ID
--                (owner-reported, with the date)
-- Expected names are the enUS client's. A different name on a localised
-- client is reported as such, never treated as a failure of the ID.
-- Nothing here claims WoW Forever compatibility (issue #24 decides that).
local _, ns = ...

local Atlas = {}
ns.Atlas = Atlas

Atlas.SOURCES = {
	classic_era = {
		build = "1.15.9.70576",
		source = "client tables UiMap and AreaTable via wago.tools, checked by PR #47 (not re-checked since)",
		level = "source",
	},
	forever = {
		source = "none yet: no Forever client data has been checked",
		level = "unverified",
	},
}

-- Expected enUS names, by uiMapID and AreaTable ID (Classic Era only).
Atlas.EXPECTED = {
	maps = {
		[1411] = "Durotar",
		[1412] = "Mulgore",
		[1413] = "The Barrens",
		[1420] = "Tirisfal Glades",
		[1426] = "Dun Morogh",
		[1429] = "Elwynn Forest",
		[1432] = "Loch Modan",
		[1433] = "Redridge Mountains",
		[1436] = "Westfall",
		[1437] = "Wetlands",
		[1438] = "Teldrassil",
		[1453] = "Stormwind City",
		[1454] = "Orgrimmar",
		[1455] = "Ironforge",
		[1456] = "Thunder Bluff",
		[1457] = "Darnassus",
		[1458] = "Undercity",
	},
	areas = {
		[9] = "Northshire Valley",
		[23] = "Northshire River",
		[24] = "Northshire Abbey",
		[34] = "Echo Ridge Mine",
		[59] = "Northshire Vineyards",
		[62] = "Brackwell Pumpkin Patch",
		[63] = "The Stonefield Farm",
		[64] = "The Maclure Vineyards",
		[69] = "Lakeshire",
		[77] = "Anvilmar",
		[87] = "Goldshire",
		[107] = "Saldean's Farm",
		[108] = "Sentinel Hill",
		[109] = "Furlbrow's Pumpkin Farm",
		[131] = "Kharanos",
		[132] = "Coldridge Valley",
		[153] = "Ruins of Lordaeron",
		[154] = "Deathknell",
		[155] = "Night Web's Hollow",
		[156] = "Solliden Farmstead",
		[159] = "Brill",
		[165] = "Balnir Farmstead",
		[186] = "Dolanaar",
		[188] = "Shadowglen",
		[219] = "Alexston Farmstead",
		[220] = "Red Cloud Mesa",
		[221] = "Camp Narache",
		[222] = "Bloodhoof Village",
		[256] = "Aldrassil",
		[257] = "Shadowthread Cave",
		[358] = "Brambleblade Ravine",
		[362] = "Razor Hill",
		[363] = "Valley of Trials",
		[364] = "The Den",
		[365] = "Burning Blade Coven",
		[367] = "Sen'jin Village",
		[380] = "The Crossroads",
		[803] = "Amberstill Ranch",
		[916] = "The Jansen Stead",
		[918] = "The Molsen Farm",
		[1001] = "Lakeridge Highway",
		[1002] = "Three Corners",
		[1296] = "Rocktusk Farm",
		[1297] = "Jaggedswine Farm",
		[2101] = "Stoutlager Inn",
		[2104] = "Deepwater Tavern",
		[2117] = "Shadow Grave",
		[2119] = "Gallows' End Tavern",
		[2979] = "Tor'kren Farm",
	},
}

-- Owner-reported in-game confirmations (Classic Era 1.15.9, enUS):
-- id -> date. See docs/COMPATIBILITY.md, "L3 results ... (owner-reported)".
Atlas.CONFIRMED = {
	maps = { [1429] = "2026-10-26" },          -- Elwynn Forest
	areas = { [9] = "2026-10-26", [87] = "2026-10-26" }, -- Northshire Valley, Goldshire
}

-- Names seen in game that have no verified ID yet. Logged as visits, never
-- classified, until an ID is confirmed.
Atlas.KNOWN_UNMAPPED = {
	{ zone = "Elwynn Forest", subzone = "Lion's Pride Inn", seen = "2026-10-26",
		note = "detected in game; no AreaTable ID verified, so it is logged but not classified" },
}

--- Evidence level for one entry: "in-game", "source" or "unverified".
function Atlas.Level(client, what, id)
	local source = Atlas.SOURCES[client]
	if not source or source.level == "unverified" then
		return "unverified"
	end
	if Atlas.CONFIRMED[what] and Atlas.CONFIRMED[what][id] then
		return "in-game"
	end
	if Atlas.EXPECTED[what] and Atlas.EXPECTED[what][id] then
		return source.level
	end
	return "unverified"
end

local function sortedIds(t)
	local ids = {}
	for id in pairs(t) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

--- Checks every expected entry against the running client.
-- probe = { areaName(id) -> string|nil, mapInfo(id) -> { name, parentMapID, mapType }|nil }.
-- Returns { rows = { { what, id, expected, got, result, parentOk } }, counts = { match, renamed, missing } }.
-- result: "match", "renamed" (a name, but not the enUS one: a localised
-- client, or a changed area) or "missing" (the client knows no such ID).
function Atlas.Verify(probe, client)
	local rows, counts = {}, { match = 0, renamed = 0, missing = 0 }
	local data = ns.Places.Data(client or "classic_era") or ns.Places.Data("classic_era")
	local function add(what, id, expected, got, parentOk)
		local result = not got and "missing" or (got == expected and "match" or "renamed")
		counts[result] = counts[result] + 1
		rows[#rows + 1] = { what = what, id = id, expected = expected, got = got, result = result, parentOk = parentOk }
	end
	for _, id in ipairs(sortedIds(Atlas.EXPECTED.maps)) do
		local info = probe.mapInfo(id)
		add("maps", id, Atlas.EXPECTED.maps[id], info and info.name)
	end
	for _, id in ipairs(sortedIds(Atlas.EXPECTED.areas)) do
		local area = data and data.areas[id]
		add("areas", id, Atlas.EXPECTED.areas[id], probe.areaName(id), area and area.map ~= nil or nil)
	end
	return { rows = rows, counts = counts }
end

--- Names of every AreaTable ID in [from, to] the client knows, at most
-- limit IDs per scan: { { id, name }, ... }. Reads only; stores nothing.
Atlas.SCAN_LIMIT = 5000
function Atlas.Scan(probe, from, to)
	local out = {}
	from = math.max(1, math.floor(from or 1))
	to = math.min(math.floor(to or from), from + Atlas.SCAN_LIMIT - 1)
	for id = from, to do
		local name = probe.areaName(id)
		if type(name) == "string" and name ~= "" then out[#out + 1] = { id = id, name = name } end
	end
	return out, from, to
end

--- Plain-text report for the copy window (paste it into issue #48).
function Atlas.Report(client, here, verify, scan)
	local lines = { "Dawnward Zone Atlas report", "client: " .. tostring(client.id) .. " " .. tostring(client.version)
		.. " (" .. tostring(client.build) .. ", interface " .. tostring(client.interface) .. ")",
		"data: " .. ((Atlas.SOURCES[client.id] or Atlas.SOURCES.forever).source) }
	if here then
		lines[#lines + 1] = string.format("here: zone=%s subzone=%s uiMap=%s (%s, parent %s) areaId=%s level=%s",
			tostring(here.zone), tostring(here.subzone), tostring(here.mapId), tostring(here.mapName),
			tostring(here.parentMapId), tostring(here.areaId), here.areaId and Atlas.Level(client.id, "areas",
			here.areaId) or "-")
	end
	if verify then
		local c = verify.counts
		lines[#lines + 1] = string.format("verify: %d match, %d renamed, %d missing", c.match, c.renamed, c.missing)
		for _, r in ipairs(verify.rows) do
			lines[#lines + 1] = string.format("%s %s %d expected=%q got=%s", r.result, r.what == "maps" and "map" or "area",
				r.id, r.expected, r.got and string.format("%q", r.got) or "nil")
		end
	end
	if scan then
		lines[#lines + 1] = string.format("scan: %d named areas", #scan)
		for _, s in ipairs(scan) do
			lines[#lines + 1] = string.format("area %d %q", s.id, s.name)
		end
	end
	return table.concat(lines, "\n")
end
