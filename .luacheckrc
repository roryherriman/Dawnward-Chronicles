-- Static analysis config. WoW runs Lua 5.1, so the standard library is lua51.
std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
	".tooling/",
	"private/",
	"review/",
	"dist/",
}

-- The WoW client has no os/io libraries and no module loading. Addon code
-- must never use them; tests may.
local NOT_IN_WOW = { "os", "io", "require", "dofile", "loadfile", "module", "package", "debug" }

-- Core/ is pure Lua: no WoW globals at all, so anything else is an error.
files["DawnwardChronicles/Core/"] = {
	not_globals = NOT_IN_WOW,
}

-- Client-facing layers: only the WoW API names they are known to use.
-- Every name here must also appear in docs/COMPATIBILITY.md.
local WOW_READ = {
	"CreateFrame", "UIParent", "GetBuildInfo", "WOW_PROJECT_ID", "WOW_PROJECT_CLASSIC",
	"C_AddOns", "GetAddOnMetadata", "IsAddOnLoaded", "UnitName", "GetRealmName",
	"GetNormalizedRealmName", "time", "DEFAULT_CHAT_FRAME", "BackdropTemplateMixin",
	"UISpecialFrames", "tinsert", "ChatFontNormal", "GameFontNormal", "GameFontHighlightSmall",
	"InCombatLockdown",
	-- v0.2 journal window and milestones
	"GameTooltip", "StaticPopup_Show", "date", "GetRealZoneText", "GetSubZoneText",
	"GameFontNormalLarge", "GameFontHighlight",
	-- v0.3 TRP3 sync scheduling
	"C_Timer",
	-- v0.4 living chronicle observers and safe-time checks (docs/COMPATIBILITY.md)
	"GetQuestID", "GetTitleText", "GetQuestLogIndexByID", "GetQuestLogTitle", "C_QuestLog", "C_Map",
	"UnitLevel", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitIsDeadOrGhost",
	"GetNumFactions", "GetFactionInfo", "IsInInstance", "GetInstanceInfo", "GetGuildInfo", "IsInGuild",
	-- v0.5 minimap button
	"Minimap", "GetCursorPosition",
	-- v0.6 keyboard navigation (Shift+Tab)
	"IsShiftKeyDown", "GetTime", "UnitIsAFK", "RAID_CLASS_COLORS", "SetPortraitTexture", "CreateFont", "GetLocale",
}

files["DawnwardChronicles/Platform/"] = {
	not_globals = NOT_IN_WOW,
	read_globals = WOW_READ,
	globals = {
		"DawnwardChroniclesDB", "DawnwardChroniclesSimDB", "DawnwardChroniclesTRP3DB",
		"SLASH_DAWNWARD1", "SLASH_DAWNWARD2", "SlashCmdList",
	},
}

files["DawnwardChronicles/UI/"] = {
	not_globals = NOT_IN_WOW,
	read_globals = WOW_READ,
	-- Our confirmation dialog is registered in the shared StaticPopupDialogs table.
	globals = { "StaticPopupDialogs" },
}

-- The TRP3 adapter receives its environment explicitly; it reads no globals itself.
files["DawnwardChronicles/Integrations/"] = {
	not_globals = NOT_IN_WOW,
}

-- Tests run outside WoW and may use the full standard library.
-- Fakes mirror method-style APIs, so an unused `self` is expected there.
files["tests/"] = { read_globals = { "arg", "jit", "setfenv" }, self = false }
