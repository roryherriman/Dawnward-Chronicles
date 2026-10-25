-- Read-only Total RP 3 status.
--
-- Uses only the client's addon metadata functions and TRP3's documented
-- public API (AddOn_TotalRP3.Player.GetCurrentUser). It never calls a
-- setter, never keeps a reference to a TRP3 table, and copies out only
-- strings and booleans. Every TRP3 call is wrapped in pcall, so a TRP3
-- change or error can only ever produce an "error" status.
--
-- The environment is passed in (the real globals in game, a fake in tests),
-- so this file reads no globals itself.
local _, ns = ...
local VersionProfiles = ns.TRP3VersionProfiles

local Status = {}
ns.TRP3Status = Status

Status.ADDON = "totalRP3"

local function asString(v)
	if type(v) == "string" then
		return v
	end
	return nil
end

-- Calls user:method() safely; returns the result only if it has the expected type.
local function callMethod(user, method, expectedType)
	local fn = user[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, user)
	if ok and type(value) == expectedType then
		return value
	end
	return nil
end

local function addonApi(env)
	local c = type(env.C_AddOns) == "table" and env.C_AddOns or nil
	local isLoaded = (c and type(c.IsAddOnLoaded) == "function" and c.IsAddOnLoaded) or env.IsAddOnLoaded
	local getMeta = (c and type(c.GetAddOnMetadata) == "function" and c.GetAddOnMetadata) or env.GetAddOnMetadata
	return isLoaded, getMeta
end

local function read(env, result)
	local isLoaded, getMeta = addonApi(env)
	if type(getMeta) == "function" then
		result.version = asString(getMeta(Status.ADDON, "Version"))
	end
	if type(isLoaded) == "function" then
		result.loaded = isLoaded(Status.ADDON) and true or false
	end
	result.installed = result.loaded or result.version ~= nil
	if not result.loaded then
		return
	end

	result.versionProfile = VersionProfiles.Get(result.version)

	local api = env.AddOn_TotalRP3
	local player = type(api) == "table" and type(api.Player) == "table" and api.Player or nil
	result.api = { getCurrentUser = player ~= nil and type(player.GetCurrentUser) == "function" }
	if not result.api.getCurrentUser then
		return
	end

	local ok, user = pcall(player.GetCurrentUser)
	if not ok or type(user) ~= "table" then
		return
	end
	result.profile = {
		name = asString(callMethod(user, "GetProfileName", "string")),
		isDefault = callMethod(user, "IsProfileDefault", "boolean") == true,
		roleplayName = asString(callMethod(user, "GetRoleplayingName", "string")),
	}
end

--- Returns a fresh table: { installed, loaded, version, versionProfile, api, profile, error }.
function Status.Read(env)
	local result = { installed = false, loaded = false }
	local ok, err = pcall(read, env, result)
	if not ok then
		return { installed = result.installed, loaded = result.loaded, version = result.version, error = tostring(err) }
	end
	return result
end
