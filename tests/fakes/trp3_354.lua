-- Fake of Total RP 3 3.5.4 (tag 3.5.4, commit 2c921b0), the closest
-- available substitute for the build WoW Forever players run. It is not
-- TRP3 code. It starts from the 3.4.1 fake (fakes/trp3_341.lua) for every
-- API the 3.4.1 -> 3.5.4 source diff shows unchanged (docs/
-- TRP3_INTEGRATION.md, "Total RP 3 3.5.x"), and replaces what changed:
--   * TRP3_IconUtil.SerializeIcon (Core/IconUtil.lua 39-56): a name or ID
--     it can resolve becomes tostring(fileID); anything else is kept as
--     it is (it is "not a validation layer"). The name -> ID table below
--     stands in for LibRPMedia-1.2 (not in the 3.5.4 checkout): only
--     inv_misc_questionmark = 134400 is TRP3's own number
--     (Resources/InterfaceIcons.lua 7); the other numbers are made up for
--     the tests and mean nothing in game.
--   * CurrentUser:SetCustomIcon stores SerializeIcon(icon) (Core/Player.lua
--     458-460); the other setters are unchanged (409-490).
--   * TRP3_InterfaceIconIDs replaces TRP3_InterfaceIcons (numbers,
--     Resources/InterfaceIcons.lua 32-42), so GetMiscTypeInfo(type).icon is
--     a number (Core/ProfileUtil.lua 28-98, 157-160).
--   * At First Glance Apply stores SerializeIcon(ic) (RegisterMisc.lua 346).
--   * The characteristics editor's "new" custom trait gets LI = RI =
--     SerializeIcon(TRP3_InterfaceIconIDs.Default) = "134400"
--     (RegisterCharacteristics.lua 697-700); an icon picked in the editor is
--     SerializeIcon(iconInfo.id) (974-990); miscAdd stores SerializeIcon(IC)
--     (610-617).
--   * Globals.player_given_name / player_family_name (Core/Globals.lua
--     49-51) fill a new profile's FN and LN (RegisterCharacteristics.lua
--     48-50, Core/Profiles.lua 283-285). opts.regionalNames models a client
--     with RegionalUniqueNamesEnabled() (Core/NameUtil.lua 93-136, 284-305):
--     the character ID has no realm ("Given Family") and the name splits at
--     the surname separator.
--   * TRP3_API.profile.openCreateProfileFlow (Core/Profiles.lua 571-575) is
--     new; Dawnward does not use it (the fake records a call as an error).
-- The version is "3.5.4" unless opts.version says otherwise.

local Base = require("fakes.trp3_341")

local Fake = {}

Fake.DEFAULT_ICON_ID = 134400
-- Stand-in for LibRPMedia's icon database (see above): lower-case name -> ID.
Fake.ICON_IDS = {
	inv_misc_questionmark = 134400,
	spell_shadow_brainwash = 900001, ability_dualwield = 900002, inv_helmet_20 = 900003,
	spell_holy_healingaura = 900004, spell_fire_burningspeed = 900005,
	ability_warrior_improveddisciplines = 900006, ability_hunter_snipershot = 900007,
	spell_holy_auraoflight = 900008, trade_engineering = 900009, inv_shield_35 = 900010,
	ability_rogue_disguise = 900011, achievement_guildperk_everybodysfriend = 900012,
	spell_arcane_mindmastery = 900013, inv_misc_note_02 = 900014, inv_misc_bone_01 = 900015,
	inv_misc_kingsring1 = 900016, vas_namechange = 900017, inv_misc_book_09 = 900018,
}
local KNOWN_IDS = {}
for _, id in pairs(Fake.ICON_IDS) do KNOWN_IDS[id] = true end

-- LibRPMedia ResolveIconID, as far as the tests need it: an ID it knows, a
-- numeric string of one, or a name it knows; else nil.
function Fake.ResolveIconID(icon)
	if type(icon) == "number" then
		return KNOWN_IDS[icon] and icon or nil
	elseif type(icon) == "string" then
		local n = tonumber(icon)
		if n then
			return KNOWN_IDS[n] and n or nil
		end
		return Fake.ICON_IDS[icon:lower()]
	end
	return nil
end

-- TRP3_IconUtil.SerializeIcon (Core/IconUtil.lua 39-56).
function Fake.SerializeIcon(icon)
	if icon ~= nil then
		local iconID = Fake.ResolveIconID(icon)
		if iconID then
			icon = iconID
		end
		icon = tostring(icon)
	end
	return icon
end

-- Core/ProfileUtil.lua MiscInfoTypeData icons as TRP3_InterfaceIconIDs
-- numbers (enUS names as in the 3.4.1 fake).
local MISC_ICON_IDS = { 134400, 900016, 900101, 900102, 900103, 900104, 900017, 900105, 900106, 900107, 900108 }
local MISC_NAMES = {
	{ "Custom", "Name" }, { "House", "House name" }, { "Nickname", "Nickname" }, { "Motto", "Motto" },
	{ "FacialFeatures", "Facial features" }, { "Piercings", "Piercings" }, { "Pronouns", "Pronouns" },
	{ "GuildName", "Guild name" }, { "GuildRank", "Guild rank" }, { "Tattoos", "Tattoos" },
	{ "VoiceReference", "Voice reference" },
}

local function copyOpts(opts)
	local out = {}
	for k, v in pairs(opts or {}) do out[k] = v end
	return out
end

function Fake.new(opts)
	opts = copyOpts(opts)
	opts.version = opts.version or "3.5.4"
	local given, family = opts.givenName or "Testchar", opts.familyName
	if opts.regionalNames then
		family = family or "Brightwater"
		opts.playerId = opts.playerId or (given .. " " .. family)
	end
	local fake = Base.new(opts)
	fake.serializeIcon = Fake.SerializeIcon
	local env = fake.env
	local api = env.TRP3_API

	-- Core/Globals.lua 49-51, 102.
	if api then
		api.globals.player_given_name = given
		api.globals.player_family_name = family
		-- Core/ProfileUtil.lua 157-160: a copy of the type's data, icon a number.
		api.GetMiscTypeInfo = function(miscType)
			local t = MISC_NAMES[miscType]
			if not t then return nil end
			return { type = miscType, englishName = t[2], localizedName = t[2], icon = MISC_ICON_IDS[miscType] }
		end
	end
	env.TRP3_InterfaceIconIDs = { Default = Fake.DEFAULT_ICON_ID, Unknown = Fake.DEFAULT_ICON_ID,
		TraitSection = 900013 }
	env.TRP3_IconUtil = {
		SerializeIcon = Fake.SerializeIcon,
		GetIconID = Fake.ResolveIconID,
		IsValidIcon = function(icon) return icon ~= nil and Fake.ResolveIconID(icon) ~= nil end,
	}

	-- CurrentUser:SetCustomIcon (Core/Player.lua 458-460): UpdateProfileField
	-- (415-432) with the serialised icon.
	local user = env.AddOn_TotalRP3 and env.AddOn_TotalRP3.Player and env.AddOn_TotalRP3.Player.GetCurrentUser()
	if user and not (opts.override and opts.override.SetCustomIcon) then
		user.SetCustomIcon = function(self, icon)
			fake.setterCalls[#fake.setterCalls + 1] = "SetCustomIcon"
			fake.setterLog[#fake.setterLog + 1] = { name = "SetCustomIcon", value = icon }
			if opts.settersRaise then error("Dawnward must not call TRP3 setter SetCustomIcon") end
			if self:IsProfileDefault() then return end
			local section = fake.profile.player.characteristics
			local value = Fake.SerializeIcon(icon)
			if section.IC == value then return end
			section.IC = value
			local n = (section.v or 1) + 1
			if n >= 100 then n = 1 end
			section.v = n
			fake.fire("REGISTER_DATA_UPDATED", fake.playerId, fake.profileId, "characteristics")
		end
	end

	-- At First Glance Apply (RegisterMisc.lua 332-357): the icon is serialised.
	local baseApply = fake.applyPeekSlot
	function fake.applyPeekSlot(slot, ic, ac, ti, tx)
		return baseApply(slot, Fake.SerializeIcon(ic), ac, ti, tx)
	end

	-- The characteristics editor (draft from fake.openEditor("characteristics")):
	-- psychoAdd("new") (RegisterCharacteristics.lua 693-702), an icon picked
	-- for one end (974-990), miscAdd (610-617).
	function fake.addCustomTrait(draft, lt, rt)
		draft.PS = draft.PS or {}
		local trait = { LT = lt, RT = rt, V2 = 10,
			LI = Fake.SerializeIcon(Fake.DEFAULT_ICON_ID), RI = Fake.SerializeIcon(Fake.DEFAULT_ICON_ID) }
		table.insert(draft.PS, trait)
		return trait
	end
	function fake.pickTraitIcon(trait, side, icon)
		trait[side == "left" and "LI" or "RI"] = Fake.SerializeIcon(Fake.ResolveIconID(icon) or icon)
	end
	function fake.addMisc(draft, id, na, va, ic)
		draft.MI = draft.MI or {}
		table.insert(draft.MI, { ID = id, NA = na, VA = va, IC = Fake.SerializeIcon(ic) })
	end

	-- A new profile (Core/Profiles.lua 145-148 from PR_DEFAULT_PROFILE, which
	-- 3.5.4 fills with the given and family name: RegisterCharacteristics.lua
	-- 44-51) and the new creation flow, which Dawnward must not use.
	if api and api.profile then
		local baseCreate = api.profile.createProfile
		api.profile.createProfile = function(name, isDefaultProfile)
			local id = baseCreate(name, isDefaultProfile)
			local ch = fake.profiles[id].player.characteristics
			ch.FN, ch.LN = given, family
			ch.IC = Fake.SerializeIcon(ch.IC)
			return id
		end
		api.profile.openCreateProfileFlow = function()
			error("Dawnward must not open Total RP 3's profile creation flow")
		end
	end
	return fake
end

return Fake
