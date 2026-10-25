-- The single place Dawnward touches Total RP 3 for sync. Everything else
-- (planning, the ledger, commands) works on copies this module returns.
--
-- Drivers, from most to least supported:
--   public        TRP3's documented AddOn_TotalRP3 setters. TRP3 3.4.1 has
--                 none for About or personality traits; when an official
--                 setter appears, it is added to PUBLIC_SECTION_WRITERS and
--                 takes precedence automatically.
--   manual        Dawnward shows the text; the player pastes it into TRP3.
--                 Always available; needs no TRP3 access at all.
--   experimental  Version-allowlisted internal write of the player's own
--                 live section, mirroring TRP3's own UpdateProfileField:
--                 replace contents, bump v, fire REGISTER_DATA_UPDATED.
--                 Off unless the TRP3 version is allowlisted AND the player
--                 opted in for this character and profile.
--
-- The environment is passed in (the real globals in game, a fake in tests).
-- Every TRP3 access is wrapped in pcall and type-checked.
local _, ns = ...
local Util, Status, VersionProfiles, Shape = ns.Util, ns.TRP3Status, ns.TRP3VersionProfiles, ns.TRP3Shape

local Adapter = {}
ns.TRP3Adapter = Adapter

Adapter.SECTIONS = { about = true, characteristics = true }

-- TRP3 frames whose own "shown" flag means an editor holds a draft that a
-- later Save would copy over the live section (RegisterAbout.lua save(),
-- RegisterCharacteristics.lua saveCharacteristics()). The flag stays set
-- even when TRP3's window is closed in the middle of editing.
Adapter.EDITOR_FRAMES = {
	about = "TRP3_RegisterAbout_AboutPanel_Edit",
	characteristics = "TRP3_RegisterCharact_Edit_NamePanel",
}

-- Official setters for whole sections, by name on CurrentUser. Empty: TRP3
-- 3.4.1 and main have none (docs/TRP3_INTEGRATION.md, issue #8).
Adapter.PUBLIC_SECTION_WRITERS = {}

local function currentUser(env)
	local api = env.AddOn_TotalRP3
	local player = type(api) == "table" and type(api.Player) == "table" and api.Player or nil
	if not player or type(player.GetCurrentUser) ~= "function" then
		return nil, "the Total RP 3 public API is unavailable"
	end
	local ok, user = pcall(player.GetCurrentUser)
	if not ok or type(user) ~= "table" then
		return nil, "the Total RP 3 current user could not be read"
	end
	return user
end

local function call(user, method)
	local fn = user[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, user)
	if ok then
		return value
	end
	return nil
end

-- Live player table (internal: the public GetProfile returns TRP3's own table).
local function livePlayer(env)
	local user, err = currentUser(env)
	if not user then
		return nil, err
	end
	local player = call(user, "GetProfile")
	if type(player) ~= "table" then
		return nil, "the Total RP 3 profile could not be read"
	end
	return player, user
end

-- Number of other characters linked to this profile (read-only, internal
-- TRP3_Characters), or nil when unknown.
local function sharedCount(env, profileId, characterId)
	local chars = env.TRP3_Characters
	if type(chars) ~= "table" or type(profileId) ~= "string" then
		return nil
	end
	local n = 0
	for id, info in pairs(chars) do
		if id ~= characterId and type(info) == "table" and info.profileID == profileId then
			n = n + 1
		end
	end
	return n
end

local function eventApi(env)
	local addon = env.TRP3_Addon
	local api = env.TRP3_API
	if type(addon) ~= "table" or type(addon.TriggerEvent) ~= "function" or type(addon.Events) ~= "table"
		or type(addon.Events.REGISTER_DATA_UPDATED) ~= "string" then
		return nil
	end
	local globals = type(api) == "table" and type(api.globals) == "table" and api.globals or nil
	if not globals or type(globals.player_id) ~= "string" then
		return nil
	end
	return addon, globals.player_id
end

--- Everything a sync decision needs, read fresh. Never writes.
-- Returns { status, profile = { id, name, isDefault, characterId, sharedWith },
--   versionProfile, experimental = { allowed, reasons = {...} },
--   editorOpen = { about, characteristics } (nil = unknown) }.
function Adapter.Probe(env)
	local probe = { status = Status.Read(env), experimental = { allowed = false, reasons = {} } }
	local reasons = probe.experimental.reasons
	local status = probe.status
	if status.error then
		reasons[#reasons + 1] = "Total RP 3 could not be read safely (" .. status.error .. ")"
		return probe
	end
	if not status.loaded then
		reasons[#reasons + 1] = status.installed and "Total RP 3 is installed but not loaded" or "Total RP 3 is not installed"
		return probe
	end
	probe.versionProfile = VersionProfiles.Get(status.version)
	if not probe.versionProfile.tiers.experimentalWrite then
		reasons[#reasons + 1] = "Total RP 3 " .. tostring(status.version)
			.. " is not on the list of versions Dawnward may write to (" .. probe.versionProfile.label .. ")"
	end
	local ok, err = pcall(function()
		local user, userErr = currentUser(env)
		if not user then
			reasons[#reasons + 1] = userErr
			return
		end
		local id = call(user, "GetProfileID")
		probe.profile = {
			id = type(id) == "string" and id or nil,
			name = type(call(user, "GetProfileName")) == "string" and call(user, "GetProfileName") or nil,
			isDefault = call(user, "IsProfileDefault") == true,
			characterId = type(call(user, "GetCharacterID")) == "string" and call(user, "GetCharacterID") or nil,
		}
		probe.profile.sharedWith = sharedCount(env, probe.profile.id, probe.profile.characterId)
		if not probe.profile.id then
			reasons[#reasons + 1] = "the active Total RP 3 profile has no ID"
		elseif probe.profile.isDefault or probe.profile.id:sub(-1) == "*" then
			reasons[#reasons + 1] = "the active Total RP 3 profile is the default profile (Dawnward never writes to it)"
		end
		if type(call(user, "GetProfile")) ~= "table" then
			reasons[#reasons + 1] = "the Total RP 3 profile data could not be read"
		end
		if not eventApi(env) then
			reasons[#reasons + 1] = "Total RP 3's update notification is unavailable, so other players would not see changes"
		end
		probe.editorOpen = {}
		for section, frameName in pairs(Adapter.EDITOR_FRAMES) do
			local frame = env[frameName]
			if type(frame) == "table" and type(frame.IsShown) == "function" then
				local shownOk, shown = pcall(frame.IsShown, frame)
				if shownOk then
					probe.editorOpen[section] = shown and true or false
				end
			end
			if probe.editorOpen[section] == nil then
				reasons[#reasons + 1] = "Dawnward cannot tell whether the Total RP 3 editor is open"
			end
		end
	end)
	if not ok then
		reasons[#reasons + 1] = "Total RP 3 behaved unexpectedly (" .. tostring(err) .. ")"
	end
	probe.experimental.allowed = #reasons == 0
	return probe
end

--- Deep copy of a live section after a shape check, or nil plus a reason.
function Adapter.ReadSection(env, section)
	if not Adapter.SECTIONS[section] then
		return nil, "unknown section"
	end
	local ok, result, err = pcall(function()
		local player, perr = livePlayer(env)
		if not player then
			return nil, perr
		end
		local data = player[section]
		local valid, why = Shape.BY_SECTION[section](data)
		if not valid then
			return nil, why
		end
		return Util.DeepCopy(data)
	end)
	if not ok then
		return nil, "Total RP 3 behaved unexpectedly (" .. tostring(result) .. ")"
	end
	return result, err
end

--- Which driver would write a section: "public", "experimental" or "manual".
function Adapter.DriverFor(env, section, probe)
	local user = currentUser(env)
	local setter = Adapter.PUBLIC_SECTION_WRITERS[section]
	if user and setter and type(user[setter]) == "function" then
		return "public"
	end
	if probe and probe.experimental.allowed then
		return "experimental"
	end
	return "manual"
end

-- Fires TRP3's update notification separately from the write, so a failing
-- listener is reported as "not notified" rather than "not written".
-- Returns nil, or an error message.
local function notify(addon, playerId, profileId, section)
	local ok, err = pcall(addon.TriggerEvent, addon, addon.Events.REGISTER_DATA_UPDATED, playerId, profileId, section)
	if not ok then
		return "Total RP 3 could not be notified (" .. tostring(err) .. ")"
	end
	return nil
end

--- Experimental driver: replaces the player's live section with data,
-- giving it a new version, then fires TRP3's update notification exactly as
-- TRP3's own setters do. Refuses unless the active profile is still
-- expectedProfileId and data passes the shape check. Returns the version
-- written (plus, third, an error if TRP3 could not be notified), or nil plus
-- a reason. Callers must have taken a backup.
function Adapter.WriteSection(env, section, data, expectedProfileId)
	if not Adapter.SECTIONS[section] then
		return nil, "unknown section"
	end
	local ok, result, err, addon, playerId = pcall(function()
		local player, user = livePlayer(env)
		if not player then
			return nil, user
		end
		if call(user, "GetProfileID") ~= expectedProfileId or call(user, "IsProfileDefault") == true then
			return nil, "the active Total RP 3 profile changed"
		end
		local live = player[section]
		if type(live) ~= "table" then
			return nil, "the Total RP 3 section is missing"
		end
		local addon, playerId = eventApi(env)
		if not addon then
			return nil, "Total RP 3's update notification is unavailable"
		end
		local copy = Util.DeepCopy(data)
		copy.v = Shape.DawnwardVersion(live.v)
		local valid, why = Shape.BY_SECTION[section](copy)
		if not valid then
			return nil, "refused to write: " .. why
		end
		-- Replace contents in place, as TRP3's editors do (wipe + copy), so
		-- TRP3 keeps its own table.
		for k in pairs(live) do
			live[k] = nil
		end
		for k, v in pairs(copy) do
			live[k] = v
		end
		return copy.v, nil, addon, playerId
	end)
	if not ok then
		return nil, "Total RP 3 behaved unexpectedly while writing (" .. tostring(result) .. ")"
	end
	if not result then
		return nil, err
	end
	return result, nil, notify(addon, playerId, expectedProfileId, section)
end

--- Asks TRP3 to tell us about profile switches and profile edits. The
-- events are only hints (the callback arguments are never relied on); every
-- sync re-reads everything. Returns true if registered.
function Adapter.Listen(env, onHint)
	local ok, registered = pcall(function()
		local addon, api = env.TRP3_Addon, env.TRP3_API
		if type(addon) ~= "table" or type(addon.Events) ~= "table" or type(api) ~= "table"
			or type(api.RegisterCallback) ~= "function" then
			return false
		end
		local any = false
		for _, name in ipairs({ "REGISTER_PROFILES_LOADED", "REGISTER_DATA_UPDATED" }) do
			if type(addon.Events[name]) == "string" then
				api.RegisterCallback(addon, addon.Events[name], function() onHint(name) end)
				any = true
			end
		end
		return any
	end)
	return ok and registered == true
end
