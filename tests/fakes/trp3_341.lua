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
--   * v0.9: the misc section (RegisterMisc.lua default { v = 1, PE = {},
--     ST = {} }) and its At First Glance editor, which has no draft: Apply
--     writes the slot straight into the live section, bumps v by one
--     (incrementNumber(v, 2)) and fires REGISTER_DATA_UPDATED(player_id,
--     profileID, "misc") (applyPeekSlot); the editor frame is declared
--     hidden="true" (RegisterUIMisc.xml)
--   * TRP3_API.MiscInfoType and GetMiscTypeInfo as in Core/ProfileUtil.lua
--     (enUS names; the icons are the first TRP3_InterfaceIcons candidates)
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
			misc = opts.misc or { v = 1, PE = {}, ST = {} },
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
	-- CurrentUser:IsProfileDefault compares with the default_profile_id
	-- config value (Core/Player.lua).
	function user:IsProfileDefault() return fake.profileId == fake.defaultProfileId end
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
	-- Core/ProfileUtil.lua MiscInfoType and MiscInfoTypeData (enUS).
	local MISC_TYPES = {
		{ "Custom", "Name", "Name", "inv_misc_questionmark" },
		{ "House", "House name", "House name", "inv_misc_kingsring1" },
		{ "Nickname", "Nickname", "Nickname", "ability_hunter_beastcall" },
		{ "Motto", "Motto", "Motto", "inv_inscription_scrollofwisdom_01" },
		{ "FacialFeatures", "Facial features", "Facial features", "spell_shadow_mindsteal" },
		{ "Piercings", "Piercings", "Piercings", "inv_jewelry_ring_14" },
		{ "Pronouns", "Pronouns", "Pronouns", "vas_namechange" },
		{ "GuildName", "Guild name", "Guild name", "vas_guildnamechange" },
		{ "GuildRank", "Guild rank", "Guild rank", "achievement_guildperk_honorablemention_rank2" },
		{ "Tattoos", "Tattoos", "Tattoos", "inv_inscription_inkblack01" },
		{ "VoiceReference", "Voice reference", "Voice reference", "spell_holy_silence" },
	}
	local miscInfoType = {}
	for i, t in ipairs(MISC_TYPES) do miscInfoType[t[1]] = i end
	local trp3api = {
		MiscInfoType = miscInfoType,
		GetMiscTypeInfo = function(miscType)
			local t = MISC_TYPES[miscType]
			if not t then return nil end
			return { type = miscType, englishName = t[2], localizedName = t[3], icon = t[4] }
		end,
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

	-- Editors, as RegisterMain/RegisterAbout/RegisterCharacteristics and
	-- MainStructure.lua do them:
	--   * the tab and edit frames are declared without hidden="true", so
	--     they read as shown after login or /reload until TRP3 draws the tab
	--   * opening the player's profile page creates a fresh context and
	--     selects the characteristics tab (its edit frame is hidden; the
	--     About edit frame keeps its load-time flag until About is viewed)
	--   * Edit sets context.isEditMode and shows the section's edit frame
	--     over a draft copied from the live section; Save or Cancel shows the
	--     tab again (isEditMode false, edit frame hidden)
	--   * closing TRP3's window mid-edit changes nothing of that
	local FRAME = { about = "TRP3_RegisterAbout_AboutPanel_Edit", characteristics = "TRP3_RegisterCharact_Edit_NamePanel" }
	local TAB = { about = "TRP3_RegisterAbout", characteristics = "TRP3_RegisterCharact" }
	local frames, drafts = {}, {}
	local nav = { pageId = nil, context = nil }
	local function newFrame()
		local frame = { shown = true }
		function frame:IsShown() return self.shown end
		return frame
	end
	for section in pairs(FRAME) do
		frames[FRAME[section]] = newFrame()
		frames[TAB[section]] = newFrame()
		fake[section .. "Editor"] = frames[FRAME[section]]
		fake[section .. "Tab"] = frames[TAB[section]]
	end
	fake.nav = nav
	trp3api.navigation = { page = {
		getCurrentPageID = function() return nav.pageId end,
		getCurrentContext = function() return nav.context end,
	} }
	if opts.noNavigation then
		trp3api.navigation = nil
	end
	function fake.showTab(section)
		for other in pairs(TAB) do frames[TAB[other]].shown = false end
		frames[TAB[section]].shown = true
		nav.context.isEditMode = false
		frames[FRAME[section]].shown = false
	end
	function fake.openProfilePage()
		nav.pageId, nav.context = "player_main", { source = "player", isPlayer = true }
		fake.showTab("characteristics")
	end
	function fake.openOtherPage(pageId)
		nav.pageId, nav.context = pageId or "player_profiles", nil
	end
	function fake.openEditor(section)
		if nav.pageId ~= "player_main" then fake.openProfilePage() end
		fake.showTab(section)
		drafts[section] = deepCopy(profile.player[section])
		nav.context.isEditMode = true
		frames[FRAME[section]].shown = true
		return drafts[section]
	end
	function fake.closeEditorWindow()
		-- Hides TRP3_MainFrame only; the page, its context and draft stay.
		fake.mainFrameShown = false
	end
	function fake.saveEditor(section)
		local live = profile.player[section]
		for k in pairs(live) do live[k] = nil end
		for k, v in pairs(drafts[section]) do live[k] = deepCopy(v) end
		live.v = increment(live.v)
		if nav.context then fake.showTab(section) end
		frames[FRAME[section]].shown = false
		fire("REGISTER_DATA_UPDATED", fake.playerId, nil, section)
	end
	function fake.cancelEditor(section)
		fake.showTab(section)
	end
	-- /reload: Lua state (drafts, page, context) is gone; frames are rebuilt
	-- from XML; saved profile data stays.
	function fake.reload()
		for _, frame in pairs(frames) do frame.shown = not frame.hiddenInXml end
		for k in pairs(drafts) do drafts[k] = nil end
		nav.pageId, nav.context = nil, nil
	end
	-- At First Glance (RegisterMisc.lua): the editor frame (hidden until a
	-- slot is opened) and Apply, which writes the live slot directly.
	local glanceEditor = newFrame()
	glanceEditor.shown, glanceEditor.hiddenInXml = false, true
	frames.TRP3_AtFirstGlanceEditor = glanceEditor
	fake.glanceEditor = glanceEditor
	function fake.openGlanceEditor() glanceEditor.shown = true end
	function fake.closeGlanceEditor() glanceEditor.shown = false end
	function fake.applyPeekSlot(slot, ic, ac, ti, tx)
		glanceEditor.shown = false
		local dataTab = profile.player.misc
		dataTab.PE = dataTab.PE or {}
		dataTab.PE[slot] = dataTab.PE[slot] or {}
		local peek = dataTab.PE[slot]
		peek.IC, peek.AC, peek.TI, peek.TX = ic, ac, ti, tx
		dataTab.v = increment(dataTab.v)
		fire("REGISTER_DATA_UPDATED", fake.playerId, fake.profileId, "misc")
	end
	-- getMiscExchangeData: what other players receive (inactive slots dropped).
	function fake.miscExchange()
		local data = deepCopy(profile.player.misc)
		for i = 1, 5 do
			local key = tostring(i)
			if data.PE and data.PE[key] and data.PE[key].AC == false then data.PE[key] = nil end
		end
		return data
	end

	-- What another client that cached these versions would re-fetch.
	-- The misc section is compared only when the caller cached it.
	function fake.remoteRefetch(cached)
		local out = {}
		for _, section in ipairs({ "about", "characteristics", "misc" }) do
			if (section ~= "misc" or cached.misc ~= nil) and cached[section] ~= profile.player[section].v then
				out[#out + 1] = section
			end
		end
		return out
	end
	function fake.switchProfile(id, name, data)
		fake.profiles[fake.profileId] = nil
		fake.profileId = id
		profile.profileName = name or profile.profileName
		if data then profile.player = data end
		fake.profiles[id] = profile
		fire("REGISTER_PROFILES_LOADED", profile)
	end

	-- Profiles (Core/Profiles.lua): TRP3_Profiles keyed by profile ID, the
	-- default profile's ID ending in "*", TRP3_Characters[player].profileID
	-- naming the character's profile. opts.profiles adds named profiles
	-- ({ [id] = { profileName, player } }); opts.isDefault makes the active
	-- profile the default one.
	fake.profiles = { [fake.profileId] = profile }
	fake.defaultProfileId = opts.isDefault and fake.profileId or "1690000000DFLT*"
	if not fake.profiles[fake.defaultProfileId] then
		fake.profiles[fake.defaultProfileId] = { profileName = "Default profile",
			player = { characteristics = { v = 2, FN = "Testchar", MI = {}, PS = {} },
				about = { v = 1, TE = 1, T1 = {}, T2 = {}, T3 = { PH = {}, PS = {}, HI = {} } },
				character = { v = 1, RP = 2, WU = 2 } } }
	end
	for id, p in pairs(opts.profiles or {}) do
		fake.profiles[id] = p
	end
	local characters = opts.characters or { [fake.playerId] = { profileID = fake.profileId } }
	fake.characters = characters
	fake.created = {}
	local nextId = 0
	-- PR_DEFAULT_PROFILE as the Register modules fill it (RegisterCharacteristics.lua 44,
	-- RegisterAbout.lua 95, RegisterMisc.lua 18, Dashboard.lua 30).
	local function template()
		return { player = {
			characteristics = { v = 1, RA = "Human", CL = "Paladin", FN = "Testchar",
				IC = "Achievement_Character_Human_Female", MI = {}, PS = {} },
			about = { v = 1, TE = 1, T1 = {}, T2 = {}, T3 = { PH = {}, PS = {}, HI = {} } },
			misc = { v = 1, PE = {}, ST = {} },
			character = { v = 1, RP = 2, WU = 2 },
		} }
	end
	local function isNameAvailable(name)
		assert(type(name) == "string" and name ~= "", "Invalid profile name.")
		for id, p in pairs(fake.profiles) do
			if p.profileName == name then return false, id end
		end
		return true, nil
	end
	local function selectProfile(id)
		local p = fake.profiles[id]
		assert(p, "Unknown profile id: " .. tostring(id))
		profile = p
		fake.profile = p
		fake.profileId = id
		characters[fake.playerId] = characters[fake.playerId] or {}
		characters[fake.playerId].profileID = id
		fake.selected = (fake.selected or 0) + 1
		fire("REGISTER_PROFILES_LOADED", p)
		fire("REGISTER_DATA_UPDATED", fake.playerId, id)
	end
	trp3api.profile = {
		getProfiles = function() return fake.profiles end,
		isProfileNameAvailable = isNameAvailable,
		createProfile = function(name, isDefaultProfile)
			assert(type(name) == "string" and name ~= "", "Invalid profile name.")
			assert(isNameAvailable(name), "Unavailable profile name: " .. tostring(name))
			nextId = nextId + 1
			local id = string.format("17100000%02dNEWID", nextId)
			if isDefaultProfile then id = id:sub(1, -2) .. "*" end
			local p = template()
			p.profileName = name
			fake.profiles[id] = p
			fake.created[#fake.created + 1] = id
			return id
		end,
		selectProfile = selectProfile,
		getPlayerCurrentProfileID = function() return fake.profileId end,
		isDefaultProfile = function(id) return type(id) == "string" and id:sub(-1) == "*" end,
	}
	if opts.noProfileApi then
		trp3api.profile = nil
	end

	local version = opts.version or "3.4.1"
	fake.env = {
		AddOn_TotalRP3 = api,
		TRP3_Addon = addon,
		TRP3_API = trp3api,
		TRP3_Characters = characters,
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
		for name, frame in pairs(frames) do fake.env[name] = frame end
	end
	fake.snapshot = function() return deepCopy(profile) end
	return fake
end

return Fake
