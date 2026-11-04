-- What Dawnward knows about each Total RP 3 version (docs/TRP3_INTEGRATION.md).
--
-- A version is "audited" once its source has been read and documented, and
-- "verified" (with a level) only after testing in a real client. Unlisted
-- versions get read-only status and the manual copy-and-paste path: an
-- unknown version never gets a write, whatever its number looks like.
--
-- Where an audited version behaves differently from 3.4.1, its profile
-- carries "adapters" (read by the planners through VersionProfiles.Adapters)
-- and may make single rows read-only (readOnlyRows, blockedSetters). A
-- version without adapters behaves exactly as 3.4.1 does.
local _, ns = ...

local VersionProfiles = {}
ns.TRP3VersionProfiles = VersionProfiles

-- 3.4.1's behaviour: the defaults every planner falls back to.
VersionProfiles.BASE_ADAPTERS = {
	-- "name": TRP3 stores icons as bare file names (3.4.1 everywhere).
	iconStorage = "name",
	-- Trait icon allowlist and placeholder set (TraitPlan.ICON_SETS /
	-- TraitPlan.PLACEHOLDER_SETS).
	traitIcons = "classic",
	traitPlaceholders = "name",
	-- Allowlist for the About frame and heading icons and the At First Glance
	-- presets Dawnward writes (Presentation.IconSet, GlancePlan.Options).
	interfaceIcons = "classic",
	-- How TRP3 fills a new profile's first (and last) name: "unit" means
	-- FN = Globals.player (UnitNameUnmodified), no LN.
	nameDefaults = "unit",
}

VersionProfiles.KNOWN = {
	["3.4.1"] = {
		audited = true,
		verified = nil, -- set to "L3"/"L4" only after in-game testing
		-- experimentalWrite: the About and characteristics layouts, the save
		-- path, the version rule and the update event were audited from the
		-- 3.4.1 source (docs/TRP3_INTEGRATION.md). It only makes the
		-- experimental driver *available*: each character must still opt in,
		-- and every write re-checks the layout and the functions it uses.
		-- profileTools: creating and selecting the player's own profiles
		-- through TRP3_API.profile (Core/Profiles.lua: isProfileNameAvailable
		-- 101, createProfile 144, selectProfile 193, getProfiles 76, the same
		-- calls TRP3's own "Create profile" button makes in RegisterMain.lua
		-- 735-742). Used only after the player confirms (Adapter.CreateProfile,
		-- Adapter.SelectProfile).
		-- publicSetters (v0.10.1): CurrentUser's SetCurrentlyText,
		-- SetOutOfCharacterInfo, SetRoleplayStatus, SetWalkup, SetCustomIcon
		-- and SetCustomClassColor (Core/Player.lua 413-494, UpdateProfileField),
		-- used for the player's status and look (StatusPlan.lua).
		tiers = { read = true, publicSetters = true, manualExport = true, experimentalWrite = true,
			profileTools = true },
	},
	-- 3.5.4 (tag 3.5.4, commit 2c921b0): the newest upstream release, used
	-- as the closest available substitute for the build WoW Forever players
	-- run (provisional: the build on a Forever client is not known yet).
	-- Audited against 3.4.1 file by file (docs/TRP3_INTEGRATION.md, "Total
	-- RP 3 3.5.x"). Unchanged: the About, characteristics, misc and
	-- character layouts; the About/characteristics save path (wipe, copy,
	-- incrementNumber(v, 2), REGISTER_DATA_UPDATED: RegisterAbout.lua
	-- 706-718, RegisterCharacteristics.lua 1065-1078); the editor frames
	-- (RegisterUIAbout.xml 191, RegisterUIMain.xml 45-51, RegisterUIMisc.xml
	-- 239); the page and menu IDs (RegisterMain.lua 476, 773); the events
	-- (Core/Events.lua identical); the profile functions (Core/Profiles.lua
	-- 77, 102, 145, 194: one line lower); CurrentUser's setters
	-- (Core/Player.lua 409-490). Changed, with an adapter each:
	--   * icons: every icon TRP3 itself stores goes through
	--     TRP3_IconUtil.SerializeIcon (Core/IconUtil.lua 39-56), which turns
	--     a name it can resolve into a stringified file ID ("134400") and
	--     keeps anything else as it is. So SetCustomIcon (Core/Player.lua
	--     458-460) stores something other than what it was given: the
	--     profile icon row is read-only here (a write could never read back);
	--   * a new custom trait gets LI = RI = SerializeIcon(TRP3_InterfaceIconIDs
	--     .Default) = "134400" (RegisterCharacteristics.lua 697-700), not
	--     "INV_Misc_QuestionMark": both count as TRP3's placeholder;
	--   * TRP3_InterfaceIcons (names) became TRP3_InterfaceIconIDs (numbers,
	--     Resources/InterfaceIcons.lua 9-42), so GetMiscTypeInfo(type).icon
	--     is a number; a new entry gets tostring of it, as TRP3's miscAdd
	--     does (RegisterCharacteristics.lua 610-617);
	--   * trait icons, About frame and heading icons and At First Glance
	--     presets: only icons 3.5.4 lists as the single candidate of an
	--     interface icon (so every client 3.5.4 loads on, Forever included,
	--     must have them) are written; the rest fall back;
	--   * an icon Dawnward wrote by name and TRP3 later re-stored as its file
	--     ID (At First Glance Apply, RegisterMisc.lua 346; an icon picked in
	--     an editor) is the same icon when TRP3's read-only resolver says so
	--     (IconEquivalence below), not a change by the player;
	--   * a new profile starts with FN = Globals.player_given_name and LN =
	--     Globals.player_family_name (RegisterCharacteristics.lua 48-50,
	--     Core/Globals.lua 49-51), which count as TRP3's own defaults.
	["3.5.4"] = {
		audited = true,
		verified = nil, -- Pending Live Forever Verification
		provisional = "substitute: upstream 3.5.4",
		tiers = { read = true, publicSetters = true, manualExport = true, experimentalWrite = true,
			profileTools = true },
		adapters = {
			iconStorage = "id",
			traitIcons = "trp354",
			traitPlaceholders = "id",
			interfaceIcons = "trp354",
			nameDefaults = "given_family",
		},
		readOnlyRows = {
			icon = "Total RP 3 3.5.4 stores a profile icon as a file number, not as the name Dawnward sets "
				.. "(Core/Player.lua SetCustomIcon), so the profile icon is read-only here; set it in Total RP 3",
		},
		blockedSetters = { SetCustomIcon = true },
	},
}

-- Families Dawnward recognises without having audited every build: a build
-- of these gets read-only status with an explanation, never writes.
VersionProfiles.FAMILIES = {
	["3.5"] = "only 3.5.4 of the 3.5 series has been audited",
}

local function familyOf(version)
	if type(version) ~= "string" then
		return nil
	end
	local family = version:match("^(%d+%.%d+)%.")
	return family and VersionProfiles.FAMILIES[family] and family or nil
end

function VersionProfiles.Get(version)
	local known = type(version) == "string" and VersionProfiles.KNOWN[version]
	if not known then
		local family = familyOf(version)
		return {
			known = false,
			audited = false,
			family = family,
			tiers = { read = true, manualExport = true },
			label = family and ("a " .. family .. ".x build Dawnward has not audited (" .. VersionProfiles.FAMILIES[family]
				.. ") - status only, no writes") or "not audited - status only",
			adapters = VersionProfiles.BASE_ADAPTERS,
			readOnlyRows = {},
			blockedSetters = {},
		}
	end
	local label
	if known.verified then
		label = "verified in game (" .. known.verified .. ")"
	elseif known.provisional then
		label = "source audited (" .. known.provisional .. "), not yet tested in game"
	else
		label = "source audited, not yet tested in game"
	end
	local adapters = {}
	for k, v in pairs(VersionProfiles.BASE_ADAPTERS) do adapters[k] = v end
	for k, v in pairs(known.adapters or {}) do adapters[k] = v end
	return {
		known = true,
		audited = known.audited,
		verified = known.verified,
		provisional = known.provisional,
		tiers = known.tiers,
		label = label,
		adapters = adapters,
		readOnlyRows = known.readOnlyRows or {},
		blockedSetters = known.blockedSetters or {},
	}
end

--- The version profile of the Total RP 3 in env (through TRP3Status), or
-- the unknown-version profile when it cannot be read. Read only.
function VersionProfiles.ForEnv(env)
	local Status = ns.TRP3Status
	local ok, status = pcall(function() return Status and env and Status.Read(env) or nil end)
	local version = ok and type(status) == "table" and not status.error and status.loaded and status.version or nil
	return VersionProfiles.Get(version)
end

--- The adapters for the Total RP 3 in env (3.4.1's when unknown).
function VersionProfiles.Adapters(env)
	return VersionProfiles.ForEnv(env).adapters
end

--- How Dawnward tells that an icon TRP3 holds is one Dawnward wrote, for a
-- Total RP 3 version that re-stores icons as file IDs (adapters.iconStorage
-- = "id"). Returns function(stored, mine) -> boolean, or nil for every
-- other version: they compare exactly, as 3.4.1 always did.
--
-- The same icon: the same name, or a stored stringified file ID (what
-- TRP3_IconUtil.SerializeIcon makes, 3.5.4 Core/IconUtil.lua 39-56) that
-- TRP3's own TRP3_IconUtil.GetIconID (Core/IconUtil.lua 16-18: a
-- LibRPMedia lookup, which reads only) gives for Dawnward's name. Nothing is
-- ever written to resolve it. A missing or failing resolver, or anything
-- else, is "not the same", so the caller keeps treating it as the player's
-- change (a conflict: safe).
function VersionProfiles.IconEquivalence(env, adapters)
	if not (adapters and adapters.iconStorage == "id") then
		return nil
	end
	return function(stored, mine)
		if stored == mine then
			return stored ~= nil
		end
		if type(stored) ~= "string" or type(mine) ~= "string" or not stored:match("^%d+$") or #stored > 10 then
			return false
		end
		local ok, id = pcall(function()
			local util = env and env.TRP3_IconUtil
			local get = type(util) == "table" and util.GetIconID
			if type(get) ~= "function" then
				return nil
			end
			return get(mine)
		end)
		return ok and type(id) == "number" and id > 0 and id == math.floor(id) and id < 2 ^ 31
			and string.format("%d", id) == stored or false
	end
end
