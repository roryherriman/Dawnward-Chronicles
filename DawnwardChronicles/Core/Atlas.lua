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
-- Candidates (Atlas.CANDIDATES) are a separate list: their names are
-- confirmed by the in-game scan, but not where they lie or what they are,
-- so they stay out of the place mapping and Atlas.Level calls them
-- unverified.
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

-- Owner-run in-game evidence (Classic Era 1.15.9.70576, enUS), kept
-- verbatim in tools/atlas/evidence/ with the SHA-256 published in #48
-- (tools/atlas/client_db.py selftest checks both):
--   export  /dawnward atlas export, 2026-10-28 (manual test M17): all 17
--           maps and 49 areas below matched the client's names, 66/0/0
--   scan    /dawnward atlas scan 1 5000, 2026-10-28 (M18): 1,081 area IDs
--           and names. It has no parent maps, so it confirms names only
Atlas.EVIDENCE = {
	export = { file = "classic_era_70576_atlas_export.txt", date = "2026-10-28",
		sha256 = "14ea7de6a4bc4e27d1934ac3d430cf9e9d765ceb3c7ebd3eea9957825a8ff668" },
	scan = { file = "classic_era_70576_atlas_scan_1-5000.txt", date = "2026-10-28",
		sha256 = "76d0959d352d9b52c7b10ff2caba9393708960f775bf849361ceff26b0400cb3" },
}

-- Owner-reported in-game confirmations (Classic Era 1.15.9, enUS):
-- id -> date. 2026-10-26: seen while playing (docs/COMPATIBILITY.md,
-- "L3 results ... (owner-reported)"); 2026-10-28: the atlas export above.
-- Listed one by one on purpose: a new EXPECTED entry is never confirmed
-- by default.
do
	local EXPORT = "2026-10-28"
	local maps, areas = { [1429] = "2026-10-26" }, { [9] = "2026-10-26", [87] = "2026-10-26" }
	for _, id in ipairs({ 1411, 1412, 1413, 1420, 1426, 1432, 1433, 1436, 1437, 1438, 1453, 1454, 1455, 1456, 1457,
		1458 }) do
		maps[id] = EXPORT
	end
	for _, id in ipairs({ 23, 24, 34, 59, 62, 63, 64, 69, 77, 107, 108, 109, 131, 132, 153, 154, 155, 156, 159, 165,
		186, 188, 219, 220, 221, 222, 256, 257, 358, 362, 363, 364, 365, 367, 380, 803, 916, 918, 1001, 1002, 1296,
		1297, 2101, 2104, 2117, 2119, 2979 }) do
		areas[id] = EXPORT
	end
	Atlas.CONFIRMED = { maps = maps, areas = areas }
end

-- Candidate settlements outside the starting zones (#48 analysis,
-- 2026-10-28). Each ID and name is confirmed by the in-game scan, exactly
-- as the client spells it (1997 and 1998 end in a space: data issue B).
-- Their parent map, kind and faction relevance are NOT verified, so they
-- are never classified, never prompt, and never change what Dawnward
-- records: Core/Places does not read this list. /dawnward atlas names a
-- candidate when you stand in it and shows the uiMap the client reports,
-- which is the evidence needed to promote it (add it to Places.DATA with
-- that map, then to EXPECTED and, once seen, CONFIRMED).
-- shared lists the other IDs the scan gives the same name (data issue C:
-- the Old Hillsbrad Foothills copies), so a name alone never picks the ID.
Atlas.CANDIDATES = {
	-- Eastern Kingdoms
	[42] = { name = "Darkshire" }, [35] = { name = "Booty Bay" }, [117] = { name = "Grom'gol Base Camp" },
	[99] = { name = "Rebel Camp" }, [75] = { name = "Stonard" }, [144] = { name = "Thelsamar" },
	[925] = { name = "Algaz Station" }, [150] = { name = "Menethil Harbor" },
	[271] = { name = "Southshore", shared = { 2369 } }, [272] = { name = "Tarren Mill", shared = { 2368 } },
	[320] = { name = "Refuge Pointe" }, [321] = { name = "Hammerfall" }, [348] = { name = "Aerie Peak" },
	[3317] = { name = "Revantusk Village" }, [340] = { name = "Kargath" }, [1446] = { name = "Thorium Point" },
	[2418] = { name = "Morgan's Vigil" }, [1438] = { name = "Nethergarde Keep" }, [228] = { name = "The Sepulcher" },
	[233] = { name = "Ambermill" }, [3197] = { name = "Chillwind Camp" }, [2268] = { name = "Light's Hope Chapel" },
	-- Kalimdor
	[392] = { name = "Ratchet" }, [378] = { name = "Camp Taurajo" }, [442] = { name = "Auberdine" },
	[415] = { name = "Astranaar" }, [431] = { name = "Splintertree Post" }, [2897] = { name = "Zoram'gar Outpost" },
	[460] = { name = "Sun Rock Retreat" }, [467] = { name = "Stonetalon Peak" }, [484] = { name = "Freewind Post" },
	[489] = { name = "Thalanaar" }, [608] = { name = "Nijel's Point" }, [2408] = { name = "Shadowprey Village" },
	[513] = { name = "Theramore Isle" }, [496] = { name = "Brackenwall Village" }, [1099] = { name = "Camp Mojache" },
	[1116] = { name = "Feathermoon Stronghold" }, [976] = { name = "Gadgetzan" }, [977] = { name = "Steamwheedle Port" },
	[541] = { name = "Marshal's Refuge" }, [1237] = { name = "Valormok" }, [2255] = { name = "Everlook" },
	[1997] = { name = "Bloodvenom Post " }, [1998] = { name = "Talonbranch Glade " },
	[2479] = { name = "Emerald Sanctuary" }, [3425] = { name = "Cenarion Hold" }, [702] = { name = "Rut'theran Village" },
	-- An inn inside a settlement: needs the same interior check as Lion's Pride Inn first.
	[403] = { name = "Shady Rest Inn" },
}

--- The candidate whose client name is this subzone, or nil: id, entry.
-- areaName(id) is the client's name (C_Map.GetAreaInfo). Only candidates
-- are tried, and a match is reported, never recorded.
function Atlas.Candidate(subzone, areaName)
	local want = ns.Places.Bare(subzone)
	if not want or type(areaName) ~= "function" then
		return nil
	end
	local ids = {}
	for k in pairs(Atlas.CANDIDATES) do ids[#ids + 1] = k end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if ns.Places.Bare(areaName(id)) == want then
			return id, Atlas.CANDIDATES[id]
		end
	end
	return nil
end

-- Area IDs never to be classified (#48 analysis, buckets by name plus a
-- short review list). 133 of the 1,081 scanned IDs fall in these buckets;
-- battlegrounds are left out here because Dawnward never records them as
-- places (IsInInstance), except Arathi Basin's generic names, which must
-- never match a farm or mine elsewhere.
Atlas.QUARANTINE = {
	patterns = { "unused", "delete me", "not used", "%*%*%*on map dungeon%*%*%*" },
	seas = { ["The Great Sea"] = true, ["The Veiled Sea"] = true, ["The Forbidding Sea"] = true, ["South Seas"] = true },
	ids = {
		-- test or development
		[22] = "test", [81] = "test", [82] = "test", [83] = "test", [84] = "test", [151] = "test", [876] = "test",
		[1218] = "test", [2877] = "test",
		-- unreleased or odd: review before any use
		[21] = "review", [30] = "review", [32] = "review", [616] = "review", [676] = "review", [1397] = "review",
		[2366] = "review", [2367] = "review", [3459] = "review",
		-- Arathi Basin's generic names
		[3420] = "battleground", [3421] = "battleground", [3422] = "battleground", [3423] = "battleground",
		[3424] = "battleground",
	},
}

--- Why an area must never be classified ("unused", "test", "review",
-- "battleground", "sea"), or nil.
function Atlas.Quarantined(id, name)
	local q = Atlas.QUARANTINE
	if q.ids[id] then
		return q.ids[id]
	end
	local lower = type(name) == "string" and name:lower() or ""
	for _, pattern in ipairs(q.patterns) do
		if lower:find(pattern) then
			return "unused"
		end
	end
	if q.seas[ns.Places.Bare(name) or ""] then
		return "sea"
	end
	return nil
end

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
		if here.rawZone then
			lines[#lines + 1] = string.format("here-raw: the client's zone text was %q (an interior, recorded as a "
				.. "subzone)", here.rawZone)
		end
		if here.candidateId then
			lines[#lines + 1] = string.format("candidate: area %d %q in uiMap %s (name confirmed by the scan; this "
				.. "map is the parent evidence)", here.candidateId, Atlas.CANDIDATES[here.candidateId].name,
				tostring(here.mapId))
		end
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
