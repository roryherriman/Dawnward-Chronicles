-- Identifies the running client. The environment is passed in so this can be
-- unit-tested; in game it is _G.
--
-- Nothing here is assumed from another client: Classic Era is the reference,
-- Forever is recognised provisionally by interface number only (unverified),
-- and anything else is reported as unknown.
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
Detect.CLASSIC_PROJECT_ID = 2   -- WOW_PROJECT_CLASSIC

local function classify(env, interface)
	if interface == Detect.FOREVER_INTERFACE then
		return "forever"
	end
	local project = env.WOW_PROJECT_ID
	local classic = env.WOW_PROJECT_CLASSIC or Detect.CLASSIC_PROJECT_ID
	if project == classic and type(interface) == "number" and interface >= 11300 and interface < 20000 then
		return "classic_era"
	end
	return "unknown"
end

--- Returns { id, label, verified, provisional, version, build, interface }.
function Detect.Client(env)
	local version, build, interface
	if type(env.GetBuildInfo) == "function" then
		local ok, v, b, _, i = pcall(env.GetBuildInfo)
		if ok then
			version, build, interface = v, b, i
		end
	end
	local id = classify(env, interface)
	local spec = Detect.CLIENTS[id]
	return {
		id = id,
		label = spec.label,
		verified = spec.verified,
		provisional = spec.provisional == true,
		version = version,
		build = build,
		interface = interface,
	}
end
