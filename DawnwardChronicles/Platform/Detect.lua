-- Identifies the running client. The environment is passed in so this can be
-- unit-tested; in game it is _G.
--
-- Nothing here is assumed from another client: Classic Era is the reference,
-- and anything unrecognised is reported as unknown. WoW Forever is
-- recognised provisionally (unverified in game), by either signal:
--   * WOW_PROJECT_ID == 18 (WOW_PROJECT_CAMELOT). Static evidence:
--     Gethe/wow-ui-source branch forever, 1.60.1 (70755),
--     Blizzard_ProjectConstants/Camelot/ProjectConstants.lua sets
--     WOW_PROJECT_CAMELOT = 18 and WOW_PROJECT_ID = WOW_PROJECT_CAMELOT.
--   * interface 16001, derived from the 1.60.1 version string and declared
--     by Total RP 3 3.5.4's TOC; not yet read from a Forever client.
-- Both are Pending Live Forever Verification (/dump select(4, GetBuildInfo())
-- and /dump WOW_PROJECT_ID in game).
--
-- Package target: a packaged build may declare which client it was built
-- for in its TOC (## X-Dawnward-Target: classic | forever). A mismatch with
-- the detected client is reported (Detect.TargetWarning), never fatal.
local _, ns = ...

local Detect = {}
ns.Detect = Detect

-- verified flips to true per client only after the L3/L4 checklist passes.
Detect.CLIENTS = {
	classic_era = { label = "WoW Classic Era", verified = false },
	forever = { label = "WoW Forever (provisional support)", verified = false, provisional = true },
	unknown = { label = "Unrecognised client", verified = false },
}

Detect.FOREVER_INTERFACE = 16001 -- believed value, not yet confirmed in a Forever client
Detect.CLASSIC_PROJECT_ID = 2    -- WOW_PROJECT_CLASSIC
Detect.CAMELOT_PROJECT_ID = 18   -- WOW_PROJECT_CAMELOT (Forever): static evidence only
Detect.ADDON = "DawnwardChronicles"

-- TOC target names and the client each one is built for.
Detect.TARGETS = { classic = "classic_era", forever = "forever" }

-- Platform/Compat.lua loads after this file; by the time anything calls
-- Detect it is there, and a secret value (Forever) reads as nil.
local function plain(v)
	local compat = ns.Compat
	if compat then return compat.Plain(v) end
	return v
end

local function classify(env, interface)
	local project = plain(env.WOW_PROJECT_ID)
	local camelot = type(env.WOW_PROJECT_CAMELOT) == "number" and env.WOW_PROJECT_CAMELOT or Detect.CAMELOT_PROJECT_ID
	if interface == Detect.FOREVER_INTERFACE or (project ~= nil and project == camelot) then
		return "forever"
	end
	local classic = env.WOW_PROJECT_CLASSIC or Detect.CLASSIC_PROJECT_ID
	if project == classic and type(interface) == "number" and interface >= 11300 and interface < 20000 then
		return "classic_era"
	end
	return "unknown"
end

--- The package target the TOC declares ("classic", "forever"), the raw
-- value when it is something else, or nil when the TOC declares none.
function Detect.Target(env, addon)
	local get
	local c = type(env.C_AddOns) == "table" and env.C_AddOns or nil
	if c and type(c.GetAddOnMetadata) == "function" then
		get = c.GetAddOnMetadata
	elseif type(env.GetAddOnMetadata) == "function" then
		get = env.GetAddOnMetadata
	end
	if not get then return nil end
	local ok, value = pcall(get, addon or Detect.ADDON, "X-Dawnward-Target")
	value = ok and plain(value) or nil
	if type(value) ~= "string" then return nil end
	value = value:match("^%s*(.-)%s*$"):lower()
	return value ~= "" and value or nil
end

--- Returns { id, label, verified, provisional, version, build, interface,
-- project, target, targetMismatch }.
function Detect.Client(env, addon)
	local version, build, interface
	if type(env.GetBuildInfo) == "function" then
		local ok, v, b, _, i = pcall(env.GetBuildInfo)
		if ok then
			version, build, interface = plain(v), plain(b), plain(i)
		end
	end
	local id = classify(env, interface)
	local spec = Detect.CLIENTS[id]
	local target = Detect.Target(env, addon)
	local project = plain(env.WOW_PROJECT_ID)
	return {
		id = id,
		label = spec.label,
		verified = spec.verified,
		provisional = spec.provisional == true,
		version = version,
		build = build,
		interface = interface,
		project = type(project) == "number" and project or nil,
		target = target,
		-- A declared target that is not this client's (or that Dawnward does not know).
		targetMismatch = target ~= nil and Detect.TARGETS[target] ~= id or false,
	}
end

--- One warning line when the package was built for another client, or nil.
function Detect.TargetWarning(client)
	if not client or not client.targetMismatch then return nil end
	local built = Detect.TARGETS[client.target]
	local builtLabel = built and Detect.CLIENTS[built].label or ("an unknown target \"" .. tostring(client.target) .. "\"")
	return "This copy of Dawnward was packaged for " .. builtLabel .. ", but this client looks like " .. client.label
		.. " (interface " .. tostring(client.interface) .. ", project " .. tostring(client.project) .. "). It will "
		.. "keep running and skip anything this client lacks; install the package built for this client if you have it."
end
