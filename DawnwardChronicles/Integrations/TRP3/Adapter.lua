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

-- How TRP3 3.4.1 holds an unsaved About or characteristics draft
-- (RegisterAbout.lua, RegisterCharacteristics.lua, RegisterMain.lua,
-- MainStructure.lua). Editing sets isEditMode on the "player_main" page
-- context and shows the section's edit frame; Save or Cancel clears both.
-- Closing TRP3's window mid-edit keeps both, so that draft still blocks.
-- The edit frame's own "shown" flag is not enough on its own: the frames
-- are declared without hidden="true", so they read as shown after every
-- login and /reload until TRP3 first draws that tab (the About tab only
-- when the player views it). A draft is a Lua local, so a reload discards
-- it; and leaving the profile page replaces the context, after which TRP3
-- discards the draft before any new edit. So a draft that a later Save
-- could copy over the live section exists only when all of these hold.
Adapter.PROFILE_PAGE = "player_main"
Adapter.EDITOR_FRAMES = {
	about = { tab = "TRP3_RegisterAbout", edit = "TRP3_RegisterAbout_AboutPanel_Edit" },
	characteristics = { tab = "TRP3_RegisterCharact", edit = "TRP3_RegisterCharact_Edit_NamePanel" },
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

local function shownFlag(env, name)
	local frame = env[name]
	if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then
		return nil
	end
	local ok, shown = pcall(frame.IsShown, frame)
	if not ok then
		return nil
	end
	return shown and true or false
end

--- Raw editor signals for one section, read fresh. Never writes.
-- Returns { open, why, pageId, hasContext, editMode, tabShown, editShown }
-- where open is true (a draft exists), false (none) or nil (unknown).
function Adapter.EditorState(env, section)
	local names = Adapter.EDITOR_FRAMES[section]
	local state = {}
	if not names then
		state.why = "unknown section"
		return state
	end
	state.editShown = shownFlag(env, names.edit)
	state.tabShown = shownFlag(env, names.tab)
	local api = env.TRP3_API
	local nav = type(api) == "table" and type(api.navigation) == "table" and api.navigation.page or nil
	if type(nav) ~= "table" or type(nav.getCurrentPageID) ~= "function"
		or type(nav.getCurrentContext) ~= "function" then
		state.why = "Total RP 3's page state cannot be read"
		return state
	end
	if state.editShown == nil then
		state.why = "the Total RP 3 editor frame cannot be read"
		return state
	end
	local okPage, pageId = pcall(nav.getCurrentPageID)
	local okContext, context = pcall(nav.getCurrentContext)
	if not okPage or not okContext then
		state.why = "Total RP 3's page state cannot be read"
		return state
	end
	state.pageId = type(pageId) == "string" and pageId or nil
	state.hasContext = type(context) == "table"
	state.editMode = state.hasContext and context.isEditMode == true
	if state.pageId ~= Adapter.PROFILE_PAGE or not state.hasContext then
		state.open, state.why = false, "no Total RP 3 profile page is in use"
	elseif not state.editMode then
		state.open, state.why = false, "the Total RP 3 profile page is not in edit mode"
	elseif state.tabShown == false then
		state.open, state.why = false, "another Total RP 3 tab is being edited"
	elseif state.editShown then
		state.open, state.why = true, "the Total RP 3 editor holds unsaved changes"
	else
		state.open, state.why = false, "the Total RP 3 editor is closed"
	end
	return state
end

--- Everything a sync decision needs, read fresh. Never writes.
-- Returns { status, profile = { id, name, isDefault, characterId, sharedWith },
--   versionProfile, experimental = { allowed, reasons = {...} },
--   editorOpen = { about, characteristics } (nil = unknown),
--   editorState = { about, characteristics } (see EditorState) }.
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
		probe.editorOpen, probe.editorState = {}, {}
		for section in pairs(Adapter.EDITOR_FRAMES) do
			local state = Adapter.EditorState(env, section)
			probe.editorState[section] = state
			probe.editorOpen[section] = state.open
			if state.open == nil then
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

--- Read-only access for anything that only LOOKS at the player's profile
-- (differences, import, story import): the same validated deep copy as
-- ReadSection, but only when Total RP 3 is loaded and its version has been
-- audited (VersionProfiles), so an unaudited layout is never interpreted.
-- Writing is not required (the default profile is fine). Returns the copy,
-- or nil plus a reason suitable for the player.
function Adapter.ReadAudited(env, section)
	local status = Status.Read(env)
	if status.error then
		return nil, "Total RP 3 could not be read safely (" .. tostring(status.error) .. ")"
	end
	if not status.loaded then
		return nil, "Total RP 3 is not loaded"
	end
	if not VersionProfiles.Get(status.version).audited then
		return nil, "Total RP 3 " .. tostring(status.version) .. " has not been audited, so Dawnward does not "
			.. "read its profile"
	end
	return Adapter.ReadSection(env, section)
end

--- Whether a Total RP 3 hint concerns the player's own active profile.
-- TRP3 3.4.1 fires REGISTER_DATA_UPDATED as (unitID, profileID, section)
-- for every profile it touches: other players' profiles on receipt
-- (RegisterMain.lua saveInformation), MSP senders (RegisterMSP.lua),
-- register list edits (no arguments), companions; the player's own saves
-- pass Globals.player_id (RegisterAbout.lua, RegisterCharacteristics.lua)
-- or nil plus the edited profile ID (RegisterCharacteristics.lua 1150).
-- Its own listeners receive the registry owner first (function(_, unitID,
-- _, dataType), RegisterMSP.lua 662), so the arguments are matched by
-- value, not position: the hint is ours when any of them is our player ID
-- or the active profile ID. REGISTER_PROFILES_LOADED is always ours.
function Adapter.IsOwnHint(env, name, ...)
	if name == "REGISTER_PROFILES_LOADED" then
		return true
	end
	local ok, own = pcall(function(...)
		local api = env.TRP3_API
		local playerId = type(api) == "table" and type(api.globals) == "table" and api.globals.player_id or nil
		local user = currentUser(env)
		local profileId = user and call(user, "GetProfileID")
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "string" and (v == playerId or v == profileId) then
				return true
			end
		end
		return false
	end, ...)
	return ok and own == true
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
-- events are only hints: onHint(name, ...) receives TRP3's arguments so the
-- caller can drop hints about other players' profiles (IsOwnHint); every
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
				api.RegisterCallback(addon, addon.Events[name], function(...) onHint(name, ...) end)
				any = true
			end
		end
		return any
	end)
	return ok and registered == true
end

--- Profiles (v0.9 setup) ---------------------------------------------------------
-- Dawnward never writes to Total RP 3's default profile. A player still on
-- it (every new character starts there) can, after confirming, have
-- Dawnward create a named profile for this character, or switch to one of
-- their own, through the functions TRP3 3.4.1 itself uses for that
-- (totalRP3/Core/Profiles.lua): isProfileNameAvailable (101),
-- createProfile (144; a copy of TRP3's blank template, never of another
-- profile), selectProfile (193; sets this character's profile and fires
-- REGISTER_PROFILES_LOADED and REGISTER_DATA_UPDATED) and getProfiles (76).
-- TRP3's own "Create profile" button on the default profile's page makes
-- exactly these calls (Modules/Register/Characters/RegisterMain.lua
-- 735-742). Nothing is ever deleted or renamed, no other profile is
-- changed, and the default profile is never touched. Only for versions
-- whose profile functions were audited (VersionProfiles tiers.profileTools).

Adapter.PROFILE_NAME_MAX = 50

-- TRP3_API.profile, or nil plus a reason.
local function profileApi(env)
	local status = Status.Read(env)
	if status.error or not status.loaded then
		return nil, "Total RP 3 is not loaded"
	end
	if not VersionProfiles.Get(status.version).tiers.profileTools then
		return nil, "Dawnward has not checked how Total RP 3 " .. tostring(status.version) .. " manages profiles"
	end
	local api = env.TRP3_API
	local profile = type(api) == "table" and type(api.profile) == "table" and api.profile or nil
	if not profile then
		return nil, "Total RP 3's profile functions are unavailable"
	end
	return profile
end

local function isDefaultId(id)
	return type(id) ~= "string" or id == "" or id:sub(-1) == "*"
end

--- What Dawnward may offer here: { create, select } (booleans). Read only.
function Adapter.ProfileTools(env)
	local ok, tools = pcall(function()
		local out = { create = false, select = false }
		local p = profileApi(env)
		if not p then
			return out
		end
		out.select = type(p.getProfiles) == "function" and type(p.selectProfile) == "function"
		out.create = out.select and type(p.createProfile) == "function" and type(p.isProfileNameAvailable) == "function"
		return out
	end)
	return ok and tools or { create = false, select = false }
end

--- The player's named profiles (never the default one), read only:
-- { { id, name, current, sharedWith }, ... } sorted by name, or nil when
-- they cannot be read. sharedWith: other characters using that profile.
function Adapter.ListProfiles(env)
	local ok, list = pcall(function()
		local p = profileApi(env)
		if not p or type(p.getProfiles) ~= "function" then
			return nil
		end
		local profiles = p.getProfiles()
		if type(profiles) ~= "table" then
			return nil
		end
		local user = currentUser(env)
		local currentId = user and call(user, "GetProfileID")
		local characterId = user and call(user, "GetCharacterID")
		local out = {}
		for id, profile in pairs(profiles) do
			if not isDefaultId(id) and type(profile) == "table" and type(profile.profileName) == "string" then
				out[#out + 1] = { id = id, name = profile.profileName, current = id == currentId,
					sharedWith = sharedCount(env, id, characterId) or 0 }
			end
		end
		table.sort(out, function(a, b)
			if a.name ~= b.name then return a.name < b.name end
			return a.id < b.id
		end)
		return out
	end)
	return ok and list or nil
end

--- A name Total RP 3 accepts for a new profile (no markup, at most
-- PROFILE_NAME_MAX bytes), or nil. Pure.
function Adapter.CleanProfileName(name)
	local clean = Util.CleanText(name, Adapter.PROFILE_NAME_MAX)
	return clean ~= "" and clean or nil
end

local function nameAvailable(p, name)
	local ok, available = pcall(p.isProfileNameAvailable, name)
	return ok and available == true
end

--- The name Dawnward would give a new profile for this character: base
-- itself when free, else "base 2" ... "base 9". Read only. nil when none
-- is free or the profile functions are unavailable.
function Adapter.SuggestProfileName(env, base)
	local clean = Adapter.CleanProfileName(base)
	if not clean or not Adapter.ProfileTools(env).create then
		return nil
	end
	local p = profileApi(env)
	if nameAvailable(p, clean) then
		return clean
	end
	for n = 2, 9 do
		local candidate = Util.TruncateUtf8(clean, Adapter.PROFILE_NAME_MAX - 2) .. " " .. n
		if nameAvailable(p, candidate) then
			return candidate
		end
	end
	return nil
end

-- Whether an unsaved Total RP 3 editor draft is open (switching then could
-- carry it to another profile).
local function draftOpen(env)
	for section in pairs(Adapter.EDITOR_FRAMES) do
		if Adapter.EditorState(env, section).open == true then
			return true
		end
	end
	return false
end

local function activeId(env)
	local user = currentUser(env)
	return user and call(user, "GetProfileID")
end

--- Makes profile id this character's active Total RP 3 profile (the
-- player confirmed first). Refuses the default profile, an unknown ID and
-- an open editor draft. Returns id (and true when it was already active),
-- or nil plus a reason. Writes no profile data.
function Adapter.SelectProfile(env, id)
	if isDefaultId(id) then
		return nil, "Dawnward never switches to the default profile"
	end
	local ok, result, err = pcall(function()
		local p, why = profileApi(env)
		if not p then
			return nil, why
		end
		if not Adapter.ProfileTools(env).select then
			return nil, "Total RP 3's profile functions are unavailable"
		end
		local profiles = p.getProfiles()
		if type(profiles) ~= "table" or type(profiles[id]) ~= "table" then
			return nil, "Total RP 3 has no such profile"
		end
		if activeId(env) == id then
			return id, true
		end
		if draftOpen(env) then
			return nil, "the Total RP 3 editor holds unsaved changes; save or cancel them first"
		end
		-- selectProfile switches first, then fires TRP3's events: an error
		-- from some other listener does not undo the switch, so the result
		-- is what TRP3 now reports.
		local called, callErr = pcall(p.selectProfile, id)
		if activeId(env) ~= id then
			return nil, called and "Total RP 3 did not switch profiles"
				or ("Total RP 3 behaved unexpectedly (" .. tostring(callErr) .. ")")
		end
		return id
	end)
	if not ok then
		return nil, "Total RP 3 behaved unexpectedly (" .. tostring(result) .. ")"
	end
	return result, err
end

--- Creates a profile named name from Total RP 3's blank template and makes
-- it this character's active profile (the player confirmed first). Never
-- copies, changes or deletes another profile. Returns the new profile ID,
-- or nil plus a reason.
function Adapter.CreateProfile(env, name)
	local clean = Adapter.CleanProfileName(name)
	if not clean then
		return nil, "the new profile needs a name"
	end
	local ok, result, err = pcall(function()
		local p, why = profileApi(env)
		if not p then
			return nil, why
		end
		if not Adapter.ProfileTools(env).create then
			return nil, "Total RP 3's profile functions are unavailable"
		end
		if draftOpen(env) then
			return nil, "the Total RP 3 editor holds unsaved changes; save or cancel them first"
		end
		if not nameAvailable(p, clean) then
			return nil, "Total RP 3 already has a profile named \"" .. clean .. "\""
		end
		local id = p.createProfile(clean)
		local profiles = p.getProfiles()
		if isDefaultId(id) or type(profiles) ~= "table" or type(profiles[id]) ~= "table" then
			return nil, "Total RP 3 did not create the profile"
		end
		return id
	end)
	if not ok then
		return nil, "Total RP 3 behaved unexpectedly (" .. tostring(result) .. ")"
	end
	if not result then
		return nil, err
	end
	local selected, why = Adapter.SelectProfile(env, result)
	if not selected then
		return nil, "the profile \"" .. clean .. "\" was created, but Dawnward could not switch to it (" .. tostring(why)
			.. "); select it in Total RP 3 > Profiles"
	end
	return result
end
