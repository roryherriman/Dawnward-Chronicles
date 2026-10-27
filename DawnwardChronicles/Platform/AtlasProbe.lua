-- /dawnward atlas (#48): checks Dawnward's place data against the running
-- client with supported APIs only (C_Map.GetAreaInfo, C_Map.GetMapInfo,
-- C_Map.GetBestMapForUnit, GetRealZoneText, GetSubZoneText). It reads and
-- reports; it never changes saved data or place classifications.
--
--   atlas            where you are: zone, subzone, uiMap (and its parent), area ID and its evidence level
--   atlas verify     every expected map and area ID, compared with the client's own names
--   atlas scan a b   names of every area ID from a to b (at most 5000 at a time)
--   atlas export     where you are plus verify, in a copy window to paste into issue #48
local _, ns = ...
local Commands, Atlas = ns.Commands, ns.Atlas

local AtlasProbe = {}
ns.AtlasProbe = AtlasProbe

local function results(ok, ...)
	if ok then return ... end
	return nil
end

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return results(pcall(fn, ...))
end

local function cmap(name)
	return type(C_Map) == "table" and C_Map[name] or nil
end

--- The live client, wrapped for Core/Atlas.
AtlasProbe.probe = {
	areaName = function(id)
		local name = call(cmap("GetAreaInfo"), id)
		return type(name) == "string" and name ~= "" and name or nil
	end,
	mapInfo = function(id)
		local info = call(cmap("GetMapInfo"), id)
		return type(info) == "table" and info or nil
	end,
}

--- Where the player is, as the client reports it.
function AtlasProbe.Here()
	local data = ns.Observers.Location()
	local info = data.mapId and AtlasProbe.probe.mapInfo(data.mapId)
	data.mapName = info and info.name
	data.parentMapId = info and info.parentMapID
	return data
end

local function client()
	return ns.Detect.Client(_G)
end

Commands.Register("atlas", function(ctx, rest)
	local out = Commands.Out
	local word, tail = ns.Util.NextWord(rest or "")
	word = word:lower()
	local c = client()
	if c.id ~= "classic_era" then
		out(ctx, "Atlas: this client is " .. c.label .. ". Dawnward has no verified place data for it; results "
			.. "below compare it with the Classic Era data and are evidence only, not a compatibility claim.")
	end
	if word == "" or word == "here" then
		local here = AtlasProbe.Here()
		out(ctx, string.format("Atlas: %s / %s - uiMap %s (%s, parent %s)", tostring(here.zone),
			tostring(here.subzone or "-"), tostring(here.mapId), tostring(here.mapName), tostring(here.parentMapId)))
		if here.areaId then
			out(ctx, string.format("  area %d, %s (%s evidence)", here.areaId,
				ns.Places.KIND_LABELS[ns.Places.AreaKind(c.id, here.mapId, here.areaId)] or "?",
				Atlas.Level(c.id, "areas", here.areaId)))
		elseif here.subzone then
			out(ctx, "  this subzone has no verified area ID: it is logged as a visit, not classified.")
		end
		out(ctx, "More: /dawnward atlas verify | atlas scan <from> <to> | atlas export")
	elseif word == "verify" then
		local v = Atlas.Verify(AtlasProbe.probe, c.id)
		out(ctx, string.format("Atlas verify: %d match, %d renamed, %d missing (of %d).", v.counts.match,
			v.counts.renamed, v.counts.missing, #v.rows))
		for _, r in ipairs(v.rows) do
			if r.result ~= "match" then
				out(ctx, string.format("  %s %s %d: expected %s, client says %s", r.result, r.what == "maps" and "map"
					or "area", r.id, r.expected, tostring(r.got)))
			end
		end
		out(ctx, "Renamed can mean a localised client. /dawnward atlas export gives the full list to copy.")
	elseif word == "scan" then
		local a, b = ns.Util.NextWord(tail)
		local from, to = tonumber(a), tonumber((ns.Util.NextWord(b)))
		if not from then
			out(ctx, "Usage: /dawnward atlas scan <from> <to>   (at most " .. Atlas.SCAN_LIMIT .. " IDs at a time)")
			return
		end
		local found, f, t = Atlas.Scan(AtlasProbe.probe, from, to or from)
		local text = Atlas.Report(c, nil, nil, found)
		out(ctx, string.format("Atlas scan %d-%d: %d named areas.", f, t, #found))
		if ctx.ui and ctx.ui.ShowExport then ctx.ui.ShowExport("Dawnward Atlas scan", text) end
	elseif word == "export" then
		local text = Atlas.Report(c, AtlasProbe.Here(), Atlas.Verify(AtlasProbe.probe, c.id))
		if ctx.ui and ctx.ui.ShowExport then
			ctx.ui.ShowExport("Dawnward Atlas report", text)
		else
			out(ctx, text)
		end
	else
		out(ctx, "Usage: /dawnward atlas | atlas verify | atlas scan <from> <to> | atlas export")
	end
end)
