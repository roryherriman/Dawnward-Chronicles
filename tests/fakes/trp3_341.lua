-- Fake of Total RP 3 3.4.1's public surface, shaped after the audited source
-- (docs/TRP3_INTEGRATION.md). It is not TRP3 code. Behaviour mirrored:
--   * GetProfile/GetCharacteristics return live tables (so mutation is detectable)
--   * setters exist; here they raise, so any call from Dawnward fails the test
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
			characteristics = { v = 3, FN = opts.firstName or "Aelin", LN = "Brightwater", PS = {} },
			about = { v = 2, TE = 1, T1 = { TX = "Private about text" } },
			character = { v = 1, RP = 1, CU = "" },
		},
	}
	fake.profile = profile

	local user = {}
	function user:GetProfileName() return profile.profileName end
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

	local version = opts.version or "3.4.1"
	fake.env = {
		AddOn_TotalRP3 = api,
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
	fake.snapshot = function() return deepCopy(profile) end
	return fake
end

return Fake
