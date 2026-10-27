-- Places: where a character is, in the client's own terms, and the little
-- Dawnward may verifiably say about it (#11, #20).
--
-- Two levels, never confused:
--   zone     the broad region GetRealZoneText() names ("Elwynn Forest"),
--            with its uiMapID from C_Map.GetBestMapForUnit("player")
--   subzone  the named area GetSubZoneText() names inside it ("Goldshire");
--            empty in open country. Its AreaTable ID is known only when it
--            resolves through the mapping below: C_Map.GetAreaInfo(id) must
--            return exactly the client's own subzone text, inside the same
--            uiMap. Names are never matched against English strings.
--
-- Classifications come only from the small mapping below, keyed by IDs from
-- the Classic Era 1.15.9.70576 client tables (UiMap, AreaTable). A place
-- that is not listed is unknown: its visits are logged, it is never
-- classified from its name, and it never prompts a question by itself.
-- The mapping applies to the classic_era client only. On any other client
-- (WoW Forever, unknown) every place is unknown and nothing counts as a
-- starting area until that client's data is checked.
--
-- Starting areas: the client data does not say where a race begins (that is
-- server data), so a character counts as beginning its journey only when all
-- of these hold: the classic_era client, level START_MAX_LEVEL or lower, the
-- first location Dawnward ever recorded for the character, and the observed
-- map and area match the race's usual starting area. Anything else gets
-- neutral "first recorded" wording, so alternate starts, boosted or older
-- characters and custom servers are never told where they began.
--
-- Nothing here infers birthplace, home, upbringing, loyalty or feelings.
-- A place matters to a character only when the player says so (Mark) or
-- links an established memory to it.
local _, ns = ...
local Util = ns.Util

local Places = {}
ns.Places = Places

-- Narrative categories. Only some have verified entries so far: wilderness
-- and danger have none (nothing in the client data says an area is either),
-- and dungeons are their own event category (IsInInstance).
Places.KINDS = { start = true, town = true, inn = true, farm = true, road = true, ruins = true, capital = true,
	wilderness = true, danger = true }
Places.KIND_LABELS = { start = "starting area", town = "settlement", inn = "inn", farm = "farmland", road = "road",
	ruins = "ruins", capital = "capital city", wilderness = "wilderness", danger = "dangerous area" }

Places.START_MAX_LEVEL = 5
Places.RETURN_AFTER = 2 * 24 * 3600   -- away at least this long before a return can be a moment
Places.RETURN_REPEAT = 7 * 24 * 3600  -- and at most one return moment per place per week
Places.VISIT_GAP = 30 * 60            -- re-entering within this counts as the same visit
Places.LIMIT = 200                    -- logged places per character
-- Kinds whose returns may become a moment. Farms, roads and ruins never do
-- by themselves, so travelling back and forth around a town stays quiet.
Places.RETURN_KINDS = { start = true, town = true, inn = true, capital = true }
Places.SETTLEMENT_KINDS = { town = true, inn = true, capital = true }

-- Classic Era (interface 11xxx), checked against the 1.15.9.70576 client
-- tables UiMap and AreaTable (wago.tools, build 1.15.9.70576). Each area is
-- { map = uiMapID it lies in, kind, races = start races }.
Places.DATA = {
	classic_era = {
		build = "1.15.9.70576",
		-- uiMapID -> kind, for whole zones.
		zones = {
			[1453] = "capital", -- Stormwind City
			[1454] = "capital", -- Orgrimmar
			[1455] = "capital", -- Ironforge
			[1456] = "capital", -- Thunder Bluff
			[1457] = "capital", -- Darnassus
			[1458] = "capital", -- Undercity
		},
		-- AreaTable ID -> area. Starting areas list the races (UnitRace file
		-- tokens) Classic Era usually starts there.
		areas = {
			-- Elwynn Forest (1429): Northshire
			[9] = { map = 1429, kind = "start", races = { "Human" } },    -- Northshire Valley
			[23] = { map = 1429, kind = "start", races = { "Human" } },   -- Northshire River
			[24] = { map = 1429, kind = "start", races = { "Human" } },   -- Northshire Abbey
			[34] = { map = 1429, kind = "start", races = { "Human" } },   -- Echo Ridge Mine
			[59] = { map = 1429, kind = "start", races = { "Human" } },   -- Northshire Vineyards
			[87] = { map = 1429, kind = "town" },                          -- Goldshire
			[62] = { map = 1429, kind = "farm" },                          -- Brackwell Pumpkin Patch
			[63] = { map = 1429, kind = "farm" },                          -- The Stonefield Farm
			[64] = { map = 1429, kind = "farm" },                          -- The Maclure Vineyards
			-- Dun Morogh (1426): Coldridge Valley
			[132] = { map = 1426, kind = "start", races = { "Dwarf", "Gnome" } }, -- Coldridge Valley
			[77] = { map = 1426, kind = "start", races = { "Dwarf", "Gnome" } },  -- Anvilmar
			[131] = { map = 1426, kind = "town" },                         -- Kharanos
			[803] = { map = 1426, kind = "farm" },                         -- Amberstill Ranch
			-- Teldrassil (1438): Shadowglen
			[188] = { map = 1438, kind = "start", races = { "NightElf" } }, -- Shadowglen
			[256] = { map = 1438, kind = "start", races = { "NightElf" } }, -- Aldrassil
			[257] = { map = 1438, kind = "start", races = { "NightElf" } }, -- Shadowthread Cave
			[186] = { map = 1438, kind = "town" },                         -- Dolanaar
			-- Durotar (1411): Valley of Trials
			[363] = { map = 1411, kind = "start", races = { "Orc", "Troll" } }, -- Valley of Trials
			[364] = { map = 1411, kind = "start", races = { "Orc", "Troll" } }, -- The Den
			[365] = { map = 1411, kind = "start", races = { "Orc", "Troll" } }, -- Burning Blade Coven
			[362] = { map = 1411, kind = "town" },                         -- Razor Hill
			[367] = { map = 1411, kind = "town" },                         -- Sen'jin Village
			[1296] = { map = 1411, kind = "farm" },                        -- Rocktusk Farm
			[1297] = { map = 1411, kind = "farm" },                        -- Jaggedswine Farm
			[2979] = { map = 1411, kind = "farm" },                        -- Tor'kren Farm
			-- Mulgore (1412): Camp Narache
			[221] = { map = 1412, kind = "start", races = { "Tauren" } },   -- Camp Narache
			[220] = { map = 1412, kind = "start", races = { "Tauren" } },   -- Red Cloud Mesa
			[358] = { map = 1412, kind = "start", races = { "Tauren" } },   -- Brambleblade Ravine
			[222] = { map = 1412, kind = "town" },                         -- Bloodhoof Village
			-- Tirisfal Glades (1420): Deathknell
			[154] = { map = 1420, kind = "start", races = { "Scourge" } },  -- Deathknell
			[155] = { map = 1420, kind = "start", races = { "Scourge" } },  -- Night Web's Hollow
			[2117] = { map = 1420, kind = "start", races = { "Scourge" } }, -- Shadow Grave
			[159] = { map = 1420, kind = "town" },                         -- Brill
			[2119] = { map = 1420, kind = "inn" },                         -- Gallows' End Tavern
			[153] = { map = 1420, kind = "ruins" },                        -- Ruins of Lordaeron
			[156] = { map = 1420, kind = "farm" },                         -- Solliden Farmstead
			[165] = { map = 1420, kind = "farm" },                         -- Balnir Farmstead
			-- Westfall (1436)
			[108] = { map = 1436, kind = "town" },                         -- Sentinel Hill
			[107] = { map = 1436, kind = "farm" },                         -- Saldean's Farm
			[109] = { map = 1436, kind = "farm" },                         -- Furlbrow's Pumpkin Farm
			[219] = { map = 1436, kind = "farm" },                         -- Alexston Farmstead
			[916] = { map = 1436, kind = "farm" },                         -- The Jansen Stead
			[918] = { map = 1436, kind = "farm" },                         -- The Molsen Farm
			-- Redridge Mountains (1433)
			[69] = { map = 1433, kind = "town" },                          -- Lakeshire
			[1001] = { map = 1433, kind = "road" },                        -- Lakeridge Highway
			[1002] = { map = 1433, kind = "road" },                        -- Three Corners
			-- Elsewhere
			[380] = { map = 1413, kind = "town" },                         -- The Crossroads (The Barrens)
			[2101] = { map = 1432, kind = "inn" },                         -- Stoutlager Inn (Loch Modan)
			[2104] = { map = 1437, kind = "inn" },                         -- Deepwater Tavern (Wetlands)
		},
	},
}

-- Each race's starting map, derived from the areas above.
for _, data in pairs(Places.DATA) do
	data.startMaps = {}
	for _, area in pairs(data.areas) do
		for _, race in ipairs(area.races or {}) do
			data.startMaps[race] = area.map
		end
	end
end

function Places.Data(client)
	return client and Places.DATA[client] or nil
end

--- Mapped area IDs inside a uiMap, in ID order (for name resolution).
function Places.AreasIn(client, mapId)
	local data, out = Places.Data(client), {}
	if not data or not mapId then
		return out
	end
	for id, area in pairs(data.areas) do
		if area.map == mapId then out[#out + 1] = id end
	end
	table.sort(out)
	return out
end

--- The AreaTable ID of the client's subzone text, or nil. areaName(id)
-- returns the client's localised name for an area (C_Map.GetAreaInfo).
function Places.ResolveArea(client, mapId, subzone, areaName)
	if type(subzone) ~= "string" or subzone == "" or type(areaName) ~= "function" then
		return nil
	end
	for _, id in ipairs(Places.AreasIn(client, mapId)) do
		if areaName(id) == subzone then
			return id
		end
	end
	return nil
end

--- The verified kind of an area (only when it lies in the observed map).
function Places.AreaKind(client, mapId, areaId)
	local data = Places.Data(client)
	local area = data and areaId and data.areas[areaId]
	if area and area.map == mapId then
		return area.kind
	end
	return nil
end

function Places.ZoneKind(client, mapId)
	local data = Places.Data(client)
	return data and mapId and data.zones[mapId] or nil
end

local function listed(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

--- True only when a character of this race and level, seen here for the
-- first time, is where Classic Era usually begins that race's journey. A
-- resolved area must be one of the race's starting areas. With no resolved
-- area (open country, or names that did not resolve) only a level 1
-- character on the race's starting map counts.
function Places.IsStart(client, race, mapId, areaId, level)
	local data = Places.Data(client)
	if not data or type(race) ~= "string" or type(level) ~= "number" or level > Places.START_MAX_LEVEL then
		return false
	end
	if areaId then
		local area = data.areas[areaId]
		return area ~= nil and area.kind == "start" and area.map == mapId and listed(area.races, race)
	end
	return level == 1 and mapId ~= nil and data.startMaps[race] == mapId
end

function Places.Key(zone, subzone)
	if subzone then
		return zone .. " / " .. subzone
	end
	return zone
end

--- True before Dawnward has recorded any location for the character.
function Places.IsFirstLocation(story)
	if next(story.places) ~= nil then
		return false
	end
	for k in pairs(story.eventKeys) do
		if k:sub(1, 5) == "zone:" or k:sub(1, 6) == "place:" or k:sub(1, 9) == "instance:" then
			return false
		end
	end
	for _, e in ipairs(story.events) do
		if e.category == "zone" or e.category == "place" or e.category == "instance" then
			return false
		end
	end
	return true
end

--- Whether an established memory is tied to this place: it was suggested
-- from an event there, or (for a whole zone) it names the zone.
function Places.Linked(story, entry)
	local placeKey = "place:" .. Places.Key(entry.zone, entry.subzone)
	for _, m in ipairs(story.memories or {}) do
		if m.status == "established" then
			for _, k in ipairs(m.links and m.links.events or {}) do
				if k == placeKey or (not entry.subzone and k == "zone:" .. entry.zone) then
					return true
				end
				local e = ns.GameEvents.Find({ story = story }, k)
				if e and e.zone == entry.zone and (not entry.subzone or e.subzone == entry.subzone) then
					return true
				end
			end
			if not entry.subzone and m.zone == entry.zone then
				return true
			end
		end
	end
	return false
end

-- Saved shape of one logged place.
function Places.CleanEntry(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local zone = Util.CleanText(raw.zone, 100)
	if not zone or zone == "" then
		return nil
	end
	local subzone = Util.CleanText(raw.subzone, 100)
	if subzone == "" then subzone = nil end
	local function int(v, hi)
		return type(v) == "number" and v >= 0 and v == math.floor(v) and v <= hi and v or nil
	end
	return {
		zone = zone, subzone = subzone,
		mapId = int(raw.mapId, 2 ^ 31), areaId = int(raw.areaId, 2 ^ 31),
		kind = Places.KINDS[raw.kind] and raw.kind or nil,
		first = int(raw.first, 2 ^ 40) or 0, last = int(raw.last, 2 ^ 40) or 0,
		visits = int(raw.visits, 2 ^ 31) or 1, level = int(raw.level, 1000),
		returnedAt = int(raw.returnedAt, 2 ^ 40),
		meaningful = raw.meaningful == true or nil,
		homeland = raw.homeland == true or nil,
	}
end

--- A cleaned copy of a places table (key -> entry), at most LIMIT entries.
function Places.CleanAll(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, entry in pairs(raw) do
		local clean = Places.CleanEntry(entry)
		if clean then
			out[Places.Key(clean.zone, clean.subzone)] = clean
		end
	end
	Places.Prune(out)
	return out
end

--- Keeps at most LIMIT places: unclassified, least recently visited go
-- first; places the player marked as meaningful are always kept.
function Places.Prune(places)
	local list = {}
	for key, entry in pairs(places) do
		if not entry.meaningful then
			list[#list + 1] = { key = key, entry = entry }
		end
	end
	local total = 0
	for _ in pairs(places) do total = total + 1 end
	if total <= Places.LIMIT then
		return 0
	end
	table.sort(list, function(a, b)
		local ak, bk = a.entry.kind ~= nil, b.entry.kind ~= nil
		if ak ~= bk then return not ak end
		if a.entry.last ~= b.entry.last then return a.entry.last < b.entry.last end
		return a.key < b.key
	end)
	local removed = 0
	for _, item in ipairs(list) do
		if total - removed <= Places.LIMIT then break end
		places[item.key] = nil
		removed = removed + 1
	end
	return removed
end

local function logVisit(places, zone, subzone, obs, kind, areaId, now)
	local key = Places.Key(zone, subzone)
	local entry = places[key]
	if not entry then
		entry = { zone = zone, subzone = subzone, first = now, last = now, visits = 1, level = obs.level }
		places[key] = entry
	elseif now - entry.last >= Places.VISIT_GAP then
		entry.visits = entry.visits + 1
	end
	entry.last = now
	entry.mapId = obs.mapId or entry.mapId
	entry.areaId = areaId or entry.areaId
	entry.kind = kind or entry.kind
	return entry
end

local function context(obs, subzone)
	return { zone = obs.zone, subzone = subzone, level = obs.level, class = obs.class, race = obs.race,
		faction = obs.faction, source = obs.source or "ZONE_CHANGED", mapId = obs.mapId }
end

local function with(data, extra)
	for k, v in pairs(extra) do data[k] = v end
	return data
end

-- A return may become a moment only after a real absence, at most once a
-- week per place, and only for a settlement, a starting area, a capital,
-- or a place the player tied to their story.
local function returnStep(story, entry, kind, obs, subzone, now)
	if not entry or now - entry.last < Places.RETURN_AFTER then
		return nil
	end
	if entry.returnedAt and now - entry.returnedAt < Places.RETURN_REPEAT then
		return nil
	end
	local linked = Places.Linked(story, entry)
	if not (entry.meaningful or linked or (kind and Places.RETURN_KINDS[kind])) then
		return nil
	end
	entry.returnedAt = now
	return {
		category = "place", priority = (entry.meaningful or linked) and 70 or 35,
		data = with(context(obs, subzone), { place = entry.subzone or entry.zone, visit = "return", placeKind = kind,
			areaId = entry.areaId, meaningful = entry.meaningful and 1 or nil, linked = linked and 1 or nil }),
	}
end

--- Logs a location observation and plans the events it may produce, most
-- meaningful first: { { category, data, priority }, ... }. Only the first
-- should be considered for a moment; the others are records only, so a zone
-- entry and its subzone produce at most one question.
-- obs: { zone, subzone, mapId, areaId, level, class, race, faction, client }.
function Places.Observe(char, obs, now)
	local story = char.story
	local zone = type(obs.zone) == "string" and obs.zone ~= "" and obs.zone or nil
	if not zone then
		return {}
	end
	local tracking = story.prefs.tracking
	if tracking.zone == false and tracking.place == false then
		return {}
	end
	local subzone = obs.subzone
	if subzone == "" or subzone == zone then subzone = nil end
	local client = obs.client
	local areaId = subzone and obs.areaId or nil
	local areaKind = areaId and Places.AreaKind(client, obs.mapId, areaId) or nil
	if not areaKind then areaId = nil end
	local zoneKind = Places.ZoneKind(client, obs.mapId)

	local first = Places.IsFirstLocation(story)
	local origin = first and (Places.IsStart(client, obs.race, obs.mapId, areaId, obs.level) and "start"
		or "firstseen") or nil
	local zoneEntry = story.places[zone]
	local placeEntry = subzone and story.places[Places.Key(zone, subzone)] or nil
	local steps = {}

	local zoneIsNew = not zoneEntry and not story.eventKeys["zone:" .. zone]
	if zoneIsNew then
		local priority = origin == "start" and 90 or origin == "firstseen" and 80 or zoneKind and 40 or 30
		steps[#steps + 1] = { category = "zone", priority = priority,
			data = with(context(obs, subzone), { visit = origin or "first", placeKind = zoneKind }) }
	end

	if areaKind then
		local key = Places.Key(zone, subzone)
		if not placeEntry and not story.eventKeys["place:" .. key] then
			local visit, priority
			if origin == "start" and areaKind == "start" then
				visit, priority = "start", 100
			elseif origin then
				visit, priority = "firstseen", 10
			else
				visit = "first"
				priority = Places.SETTLEMENT_KINDS[areaKind] and (zoneIsNew and 65 or 60) or 50
			end
			steps[#steps + 1] = { category = "place", priority = priority,
				data = with(context(obs, subzone), { place = subzone, visit = visit, placeKind = areaKind, areaId = areaId,
					newRegion = zoneIsNew and visit == "first" and 1 or nil }) }
		end
	end

	-- A return: to the named place if it is classified or meaningful, else to the zone.
	if not origin then
		local step
		if placeEntry and (areaKind or placeEntry.meaningful) then
			step = returnStep(story, placeEntry, areaKind, obs, subzone, now)
		elseif zoneEntry and (zoneKind or zoneEntry.meaningful) then
			step = returnStep(story, zoneEntry, zoneKind, obs, nil, now)
		end
		steps[#steps + 1] = step
	end

	logVisit(story.places, zone, nil, obs, zoneKind, nil, now)
	if subzone then
		logVisit(story.places, zone, subzone, obs, areaKind, areaId, now)
	end
	Places.Prune(story.places)

	table.sort(steps, function(a, b) return a.priority > b.priority end)
	return steps
end

--- Logged places, most recently visited first.
function Places.List(char)
	local out = {}
	for _, entry in pairs(char.story.places) do
		out[#out + 1] = entry
	end
	table.sort(out, function(a, b)
		if a.last ~= b.last then return a.last > b.last end
		return Places.Key(a.zone, a.subzone) < Places.Key(b.zone, b.subzone)
	end)
	return out
end

--- Finds a logged place by name (a subzone, or a zone on its own),
-- ignoring case. Returns entry, or nil plus a reason.
function Places.FindByName(char, name)
	local needle = Util.Trim(name or ""):lower()
	if needle == "" then
		return nil, "name a place you have visited"
	end
	local zoneMatch
	for _, entry in pairs(char.story.places) do
		if entry.subzone and entry.subzone:lower() == needle then
			return entry
		end
		if not entry.subzone and entry.zone:lower() == needle then
			zoneMatch = entry
		end
	end
	if zoneMatch then
		return zoneMatch
	end
	return nil, "no visited place called '" .. Util.Trim(name) .. "' (see /dawnward places)"
end

--- The player marks a place as meaningful to their character (or unmarks
-- it). Only the player establishes this; Dawnward never does.
function Places.Mark(char, name, on)
	local entry, err = Places.FindByName(char, name)
	if not entry then
		return nil, err
	end
	entry.meaningful = on and true or nil
	return entry
end

--- The player names a visited place as their character's homeland: the
-- Homeland profile field is set to the place's name (private unless the
-- player already made it public) and the place is linked as the homeland,
-- replacing any earlier link. A homeland is only ever the player's choice.
function Places.SetHomeland(char, entry, now)
	local ok, err = ns.Character.SetField(char, "homeland", entry.subzone or entry.zone, now)
	if not ok then
		return nil, err
	end
	for _, other in pairs(char.story.places) do
		other.homeland = nil
	end
	entry.homeland = true
	entry.meaningful = true
	return entry
end

--- The place linked as the homeland, if any.
function Places.Homeland(char)
	for _, entry in pairs(char.story.places) do
		if entry.homeland then return entry end
	end
	return nil
end

function Places.Label(entry)
	local name = entry.subzone and (entry.subzone .. ", " .. entry.zone) or entry.zone
	return name
end
