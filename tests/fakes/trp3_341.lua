-- Fake of Total RP 3 3.4.1, shaped after the audited source
-- (docs/TRP3_INTEGRATION.md). It is not TRP3 code. Behaviour mirrored:
--   * GetProfile/GetCharacteristics return live tables (so mutation is detectable)
--   * setters exist; here they raise, so any call from Dawnward fails the test
--   * TRP3_Addon:TriggerEvent / TRP3_API.RegisterCallback (events recorded)
--   * the About and characteristics editors work on a draft copied when the
--     editor opens; Save wipes the live table, copies the draft back and sets
--     v = draft.v + 1 (wrapping at 100), then fires REGISTER_DATA_UPDATED
--     with a nil profile ID (RegisterAbout.lua save())
--   * the MSP bridge rebuilds its description only when REGISTER_DATA_UPDATED
--     names the player's own unit ID (RegisterMSP.lua)
--   * other clients only re-fetch a section whose version number differs
--     from the one they cached (pull-only exchange)
--
-- Usage: local fake = Fake.new{ profileName = "Main", isDefault = false }
--        fake.env      -> environment to pass to TRP3Status.Read
--        fake.snapshot -> deep copy of the profile for "unchanged" checks

local Fake = {}

local SETTERS = {
	"SetRoleplayStatus", "SetOutOfCharacterInfo", "SetCurrentlyText", "SetWalkup",
	"SetFirstName", "SetLastName", "SetCustomIcon", "SetTitle", "SetFullTitle",
	"SetCustomClass", "SetCustomClassColor", "SetCustomRace", "SetRoleplayExperience", "SetProfileID",
}

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deepCopy(x) end
	return out
end

function Fake.new(opts)
	opts = opts or {}
	local fake = { setterCalls = {} }

	local profile = {
		profileName = opts.profileName or "Main",
		player = {
			characteristics = opts.characteristics or { v = 3, FN = opts.firstName or "Aelin", LN = "Brightwater", PS = {} },
			about = opts.about or { v = 2, TE = 1, BK = 1, T1 = { TX = "Private about text" } },
			character = { v = 1, RP = 1, CU = "" },
		},
	}
	fake.profile = profile
	fake.profileId = opts.profileId or (opts.isDefault and "1700000000ABCD*" or "1700000000ABCDE")
	fake.events = {}
	fake.callbacks = {}
	fake.msp = { DE = nil }
	fake.playerId = opts.playerId or "Testchar-TestRealm"

	local user = {}
	function user:GetProfileName() return profile.profileName end
	function user:GetProfileID() return fake.profileId end
	function user:GetCharacterID() return fake.playerId end
	function user:IsProfileDefault() return opts.isDefault == true end
	function user:GetProfile() return profile.player end
	function user:GetCharacteristics() return profile.player.characteristics end
	function user:GetFirstName() return profile.player.characteristics.FN end
	function user:GetRoleplayingName()
		return profile.player.characteristics.FN .. " " .. profile.player.characteristics.LN
	end
	for _, name in ipairs(SETTERS) do
		user[name] = function()
			fake.setterCalls[#fake.setterCalls + 1] = name
			error("Dawnward must not call TRP3 setter " .. name)
		end
	end
	if opts.override then
		for k, v in pairs(opts.override) do user[k] = v end
	end

	local api = {
		Player = { GetCurrentUser = function() return user end },
		Enums = {},
	}
	if opts.noPlayerApi then
		api.Player = nil
	end

	local function increment(v)
		local n = v + 1
		if n >= 100 then n = 1 end
		return n
	end

	local function fire(event, ...)
		fake.events[#fake.events + 1] = { event = event, args = { ... } }
		for _, cb in ipairs(fake.callbacks[event] or {}) do
			cb(...)
		end
	end

	local addon = {
		Events = { REGISTER_DATA_UPDATED = "REGISTER_DATA_UPDATED", REGISTER_PROFILES_LOADED = "REGISTER_PROFILES_LOADED" },
	}
	function addon:TriggerEvent(event, ...)
		if opts.triggerFails then error("TriggerEvent exploded") end
		fire(event, ...)
	end
	local trp3api = {
		globals = { player_id = fake.playerId },
		RegisterCallback = function(registry, event, fn)
			assert(registry == addon, "callbacks are registered on TRP3_Addon")
			fake.callbacks[event] = fake.callbacks[event] or {}
			table.insert(fake.callbacks[event], fn)
		end,
	}
	if opts.noEvents then
		addon = nil
	end

	-- MSP bridge: rebuilds DE when the player's own data changes.
	local function rebuildMsp()
		local about = profile.player.about
		if about.TE == 1 then
			fake.msp.DE = about.T1 and about.T1.TX
		elseif about.TE == 2 then
			local parts = {}
			for _, frame in ipairs(about.T2 or {}) do parts[#parts + 1] = frame.TX or "" end
			fake.msp.DE = table.concat(parts, "\n\n")
		else
			fake.msp.DE = about.T3 and about.T3.PH and about.T3.PH.TX
		end
		fake.msp.rebuilds = (fake.msp.rebuilds or 0) + 1
	end
	if addon then
		trp3api.RegisterCallback(addon, "REGISTER_DATA_UPDATED", function(unitID)
			if unitID == fake.playerId then rebuildMsp() end
		end)
	end

	-- Editors: draft copied on open, Save copies it back with v = draft.v + 1.
	local editorFrames = {}
	local drafts = {}
	local FRAME = { about = "TRP3_RegisterAbout_AboutPanel_Edit", characteristics = "TRP3_RegisterCharact_Edit_NamePanel" }
	for section, name in pairs(FRAME) do
		local frame = { shown = false }
		function frame:IsShown() return self.shown end
		editorFrames[name] = frame
		fake[section .. "Editor"] = frame
	end
	function fake.openEditor(section)
		drafts[section] = deepCopy(profile.player[section])
		fake[section .. "Editor"].shown = true
		return drafts[section]
	end
	function fake.closeEditorWindow(section)
		-- Closing TRP3's window mid-edit leaves the panel's own shown flag set.
		fake[section .. "Editor"].shown = true
	end
	function fake.saveEditor(section)
		local live = profile.player[section]
		for k in pairs(live) do live[k] = nil end
		for k, v in pairs(drafts[section]) do live[k] = deepCopy(v) end
		live.v = increment(live.v)
		fake[section .. "Editor"].shown = false
		fire("REGISTER_DATA_UPDATED", fake.playerId, nil, section)
	end
	function fake.cancelEditor(section)
		fake[section .. "Editor"].shown = false
	end
	-- What another client that cached these versions would re-fetch.
	function fake.remoteRefetch(cached)
		local out = {}
		for _, section in ipairs({ "about", "characteristics" }) do
			if cached[section] ~= profile.player[section].v then out[#out + 1] = section end
		end
		return out
	end
	function fake.switchProfile(id, name, data)
		fake.profileId = id
		profile.profileName = name or profile.profileName
		if data then profile.player = data end
		fire("REGISTER_PROFILES_LOADED", profile)
	end

	local version = opts.version or "3.4.1"
	fake.env = {
		AddOn_TotalRP3 = api,
		TRP3_Addon = addon,
		TRP3_API = trp3api,
		TRP3_Characters = opts.characters or { [fake.playerId] = { profileID = fake.profileId } },
		C_AddOns = {
			IsAddOnLoaded = function(name) return name == "totalRP3" and not opts.notLoaded end,
			GetAddOnMetadata = function(name, field)
				if name == "totalRP3" and field == "Version" and not opts.notInstalled then
					return version
				end
				return nil
			end,
		},
	}
	if opts.notInstalled then
		fake.env.AddOn_TotalRP3 = nil
		fake.env.C_AddOns.IsAddOnLoaded = function() return false end
	end
	if not opts.noEditorFrames then
		for name, frame in pairs(editorFrames) do fake.env[name] = frame end
	end
	fake.snapshot = function() return deepCopy(profile) end
	return fake
end

return Fake
