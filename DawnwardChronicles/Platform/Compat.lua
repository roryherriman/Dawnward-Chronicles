-- Client API compatibility (WoW Classic Era 1.15.9 and WoW Forever 1.60.1).
--
-- Every gameplay or data API whose shape differs between the two clients
-- is reached through here, by feature detection (never by client ID):
-- the Classic Era function is used when the client has it, so Classic Era
-- behaviour is unchanged, and the retail-style replacement Forever ships
-- is used otherwise. A client with neither gets nil, the feature is
-- skipped, and the gap is recorded for /dawnward status (Compat.Missing).
--
-- Evidence (docs/COMPATIBILITY.md, "WoW Forever API compatibility"):
--   Forever = Gethe/wow-ui-source branch forever, 1.60.1 (70755), game type
--   camelot; Classic Era = branch classic_era, 1.15.9. Nothing here has run
--   in a Forever client yet: Pending Live Forever Verification.
--
--   need                 Classic Era 1.15.9                  Forever 1.60.1 (when the first is absent)
--   add-on metadata      C_AddOns.GetAddOnMetadata           same (GetAddOnMetadata as a last fallback)
--   quest level          GetQuestLogIndexByID +              C_QuestLog.GetLogIndexForQuestID +
--                        GetQuestLogTitle (2nd return)       C_QuestLog.GetInfo(index).level
--   quest title          C_QuestLog.GetQuestInfo             C_QuestLog.GetTitleForQuestID
--   reputation           GetNumFactions + GetFactionInfo     C_Reputation.GetNumFactions +
--                        (3rd standing, 9 header, 11 hasRep,  C_Reputation.GetFactionDataByIndex
--                        14 factionID)                       (.reaction, .isHeader, .isHeaderWithRep, .factionID)
--   secret values        (none)                              issecretvalue(v): a secret reads as nil here
local _, ns = ...

local Compat = {}
ns.Compat = Compat

local function results(ok, ...)
	if ok then return ... end
	return nil
end

--- Calls fn safely and passes every return value through; nil when fn is
-- not a function or raised an error.
function Compat.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return results(pcall(fn, ...))
end
local call = Compat.Call

-- Forever's engine can return "secret" values (12.x engine; issecretvalue
-- in FrameScriptDocumentation.lua) that addon code may not compare or
-- concatenate. Dawnward never needs one, so a secret reads as nil.
-- Classic Era has no issecretvalue, so this returns v unchanged there.
function Compat.Plain(v)
	if v ~= nil and type(issecretvalue) == "function" then
		local ok, secret = pcall(issecretvalue, v)
		if not ok or secret then return nil end
	end
	return v
end
local plain = Compat.Plain

-- The client function at path ("GetQuestLogTitle", "C_QuestLog.GetInfo"),
-- looked up at call time, or nil.
local function api(path)
	local space, name = path:match("^([%w_]+)%.([%w_]+)$")
	if space then
		local t = _G[space]
		local fn = type(t) == "table" and t[name] or nil
		return type(fn) == "function" and fn or nil
	end
	local fn = _G[path]
	return type(fn) == "function" and fn or nil
end
Compat.API = api

-- Features and the APIs that can provide them, in order of preference.
-- A feature is available when every API of one route exists.
Compat.FEATURES = {
	{ key = "metadata", label = "add-on metadata",
		routes = { { "C_AddOns.GetAddOnMetadata" }, { "GetAddOnMetadata" } } },
	{ key = "addonLoaded", label = "add-on load state",
		routes = { { "C_AddOns.IsAddOnLoaded" }, { "IsAddOnLoaded" } } },
	{ key = "zone", label = "zone names", routes = { { "GetRealZoneText", "GetSubZoneText" } } },
	{ key = "map", label = "map IDs", routes = { { "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo" } } },
	{ key = "areas", label = "area names", routes = { { "C_Map.GetAreaInfo" } } },
	{ key = "questLevel", label = "quest levels",
		routes = { { "GetQuestLogIndexByID", "GetQuestLogTitle" },
			{ "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetInfo" } } },
	{ key = "questTitle", label = "quest titles",
		routes = { { "C_QuestLog.GetQuestInfo" }, { "C_QuestLog.GetTitleForQuestID" } } },
	{ key = "questPanel", label = "quest reward panel", routes = { { "GetQuestID", "GetTitleText" } } },
	{ key = "reputation", label = "reputation",
		routes = { { "GetNumFactions", "GetFactionInfo" },
			{ "C_Reputation.GetNumFactions", "C_Reputation.GetFactionDataByIndex" } } },
	{ key = "guild", label = "guild", routes = { { "GetGuildInfo", "IsInGuild" } } },
	{ key = "instance", label = "instances", routes = { { "IsInInstance", "GetInstanceInfo" } } },
	{ key = "timers", label = "timers", routes = { { "C_Timer.After" } } },
	{ key = "combat", label = "combat state", routes = { { "InCombatLockdown" } } },
}

--- The route that provides a feature now: its index and API list, or nil.
function Compat.Route(key)
	for _, feature in ipairs(Compat.FEATURES) do
		if feature.key == key then
			for i, route in ipairs(feature.routes) do
				local all = true
				for _, path in ipairs(route) do
					if not api(path) then all = false break end
				end
				if all then return i, route end
			end
			return nil
		end
	end
	return nil
end

--- Features this client cannot provide: { { key, label, needs = "A + B or C + D" }, ... }.
function Compat.Missing()
	local out = {}
	for _, feature in ipairs(Compat.FEATURES) do
		if not Compat.Route(feature.key) then
			local alternatives = {}
			for _, route in ipairs(feature.routes) do
				alternatives[#alternatives + 1] = table.concat(route, " + ")
			end
			out[#out + 1] = { key = feature.key, label = feature.label, needs = table.concat(alternatives, " or ") }
		end
	end
	return out
end

--- One status line naming what this client lacks, or nil when nothing is missing.
function Compat.Summary()
	local missing = Compat.Missing()
	if #missing == 0 then return nil end
	local parts = {}
	for _, m in ipairs(missing) do
		parts[#parts + 1] = m.label .. " (needs " .. m.needs .. ")"
	end
	return "Client APIs not available, so these are skipped: " .. table.concat(parts, "; ")
end

--- An add-on's TOC metadata field, or nil.
function Compat.AddOnMetadata(addon, field)
	local fn = api("C_AddOns.GetAddOnMetadata") or api("GetAddOnMetadata")
	local value = plain(call(fn, addon, field))
	return type(value) == "string" and value or nil
end

--- Zone and subzone text (nil when the client has none, or it is not text).
function Compat.ZoneText()
	local zone = plain(call(api("GetRealZoneText")))
	local subzone = plain(call(api("GetSubZoneText")))
	if type(zone) ~= "string" or zone == "" then zone = nil end
	if type(subzone) ~= "string" or subzone == "" then subzone = nil end
	return zone, subzone
end

--- The level of a quest still in the quest log, or nil.
function Compat.QuestLevel(questId)
	if type(questId) ~= "number" then return nil end
	local route = Compat.Route("questLevel")
	local level
	if route == 1 then
		local index = plain(call(api("GetQuestLogIndexByID"), questId))
		if type(index) == "number" and index > 0 then
			local _, l = call(api("GetQuestLogTitle"), index)
			level = plain(l)
		end
	elseif route == 2 then
		local index = plain(call(api("C_QuestLog.GetLogIndexForQuestID"), questId))
		if type(index) == "number" and index > 0 then
			local info = call(api("C_QuestLog.GetInfo"), index)
			level = type(info) == "table" and plain(info.level) or nil
		end
	end
	if type(level) == "number" and level > 0 then return level end
	return nil
end

--- A quest's title from the client's quest cache, or nil.
function Compat.QuestTitle(questId)
	if type(questId) ~= "number" then return nil end
	local fn = api("C_QuestLog.GetQuestInfo") or api("C_QuestLog.GetTitleForQuestID")
	local title = plain(call(fn, questId))
	if type(title) == "string" and title ~= "" then return title end
	return nil
end

--- Reputation standings as listed by the client: { { id, name, standing }, ... }.
-- Factions under a collapsed header are not listed (both clients).
-- standing: 1 (Hated) to 8 (Exalted); Forever's FactionData.reaction is
-- the same 1-based index (ReputationInfoDocumentation.lua: luaIndex).
function Compat.ReadFactions()
	local out = {}
	local route = Compat.Route("reputation")
	if route == 1 then
		local n = plain(call(api("GetNumFactions")))
		for i = 1, type(n) == "number" and n or 0 do
			local name, _, standing, _, _, _, _, _, isHeader, _, hasRep, _, _, factionId =
				call(api("GetFactionInfo"), i)
			name, standing, factionId = plain(name), plain(standing), plain(factionId)
			if name and type(factionId) == "number" and type(standing) == "number" and (not isHeader or hasRep) then
				out[#out + 1] = { id = factionId, name = name, standing = standing }
			end
		end
	elseif route == 2 then
		local n = plain(call(api("C_Reputation.GetNumFactions")))
		local get = api("C_Reputation.GetFactionDataByIndex")
		for i = 1, type(n) == "number" and n or 0 do
			local d = call(get, i)
			if type(d) == "table" then
				local name, standing, factionId = plain(d.name), plain(d.reaction), plain(d.factionID)
				if type(name) == "string" and name ~= "" and type(factionId) == "number" and type(standing) == "number"
					and (not d.isHeader or d.isHeaderWithRep) then
					out[#out + 1] = { id = factionId, name = name, standing = standing }
				end
			end
		end
	end
	return out
end

--- Runs fn after delay seconds. Returns false (and runs nothing) when the
-- client has no timer, so callers can fall back to the next event.
function Compat.After(delay, fn)
	local after = api("C_Timer.After")
	if not after then return false end
	local ok = pcall(after, delay, fn)
	return ok
end

--- Whether the player is in combat. When the client cannot say,
-- returns ifUnknown (callers that write choose true: wait, never risk it).
function Compat.InCombat(ifUnknown)
	local fn = api("InCombatLockdown")
	if not fn then return ifUnknown end
	local ok, v = pcall(fn)
	if not ok then return ifUnknown end
	v = plain(v)
	if v == nil then return ifUnknown and true or false end
	return v and true or false
end

--- A unit query ("player" only in Dawnward) with secrets and errors read as nil.
function Compat.Unit(fnName, unit)
	return plain(call(api(fnName), unit or "player"))
end
