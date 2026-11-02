-- The live status and look the player sets for Total RP 3 (v0.10.1): the
-- "Currently" text, the out-of-character note, the roleplay status, walk-up,
-- the profile icon and class colour, and (only for the preferences the
-- player hands to Dawnward) the six roleplay style preferences.
--
-- Everything here is written by the player, in Dawnward, for Total RP 3.
-- Nothing is ever inferred or filled in automatically: Suggest only drafts a
-- Currently text for the editor, and only when the player asks; it is saved
-- only by the player's own Save. Total RP 3 receives a value only while the
-- player lets Dawnward keep it in sync (Integrations/TRP3/StatusPlan.lua,
-- StylePlan.lua), and never over a value the player wrote in Total RP 3.
--
-- Stored per character as char.trp3status = { currently?, ooc?, rpStatus?,
-- walkup?, icon?, classColor?, style = { [styleKey] = value } }. A text set
-- to "" means "cleared in Dawnward" (Total RP 3's copy is emptied on the
-- next sync, if Dawnward wrote it); nil means "never set" (nothing is sent).
--
-- Value sets verified in the Total RP 3 3.4.1 source:
--   * character.RP: AddOn_TotalRP3.Enums.ROLEPLAY_STATUS IN_CHARACTER = 1,
--     OUT_OF_CHARACTER = 2 (Core/Enums.lua 25-28); labels DB_STATUS_RP_IC /
--     DB_STATUS_RP_OOC (Locales/enUS.lua 836, 838)
--   * character.WU: Enums.WALKUP NO = 1, YES = 2 (Core/Enums.lua 50-53); the
--     status menu labels them CM_DO_NOT_SHOW and CM_YES (Dashboard/
--     StatusPanel.lua 95-104), the field DB_STATUS_WU "Walkup friendly"
--   * character.CU / CO: free multi-line text (Dashboard/Currently.lua,
--     RegisterMisc.lua 387-409: Utils.str.sanitize(text, true), no length
--     limit; DB_STATUS_CURRENTLY_COMMON: other players' tooltips show the
--     first 140 characters by default)
--   * characteristics.IC: an icon file name; characteristics.CH: a six-digit
--     hex colour (Core/Player.lua 478-490 SetCustomClassColor)
--   * misc.ST: the six style preferences (RegisterMisc.lua 28-100
--     STYLE_FIELDS; nil reads as 0, "Do not show", line 160)
-- Loaded before Core/Schema.lua, which cleans this table on load.
local _, ns = ...
local Util = ns.Util

local RPStatus = {}
ns.RPStatus = RPStatus

-- Dawnward's own cap on the two texts (Total RP 3 has none); TOOLTIP is
-- how much other players' tooltips show by default.
RPStatus.LIMITS = { text = 1000, icon = 64 }
RPStatus.TOOLTIP_CHARS = 140

RPStatus.IN_CHARACTER, RPStatus.OUT_OF_CHARACTER = 1, 2
RPStatus.WALKUP_NO, RPStatus.WALKUP_YES = 1, 2

-- Each value the player can set: its kind and, for a choice, its options
-- with Total RP 3's own enUS labels.
RPStatus.FIELDS = {
	{ id = "currently", kind = "text", label = "Currently" },
	{ id = "ooc", kind = "text", label = "Other information (OOC)" },
	{ id = "rpStatus", kind = "choice", label = "Character status",
		options = { { value = 1, label = "In character" }, { value = 2, label = "Out of character" } } },
	{ id = "walkup", kind = "choice", label = "Walkup friendly",
		options = { { value = 2, label = "Yes" }, { value = 1, label = "Do not show" } } },
	{ id = "icon", kind = "icon", label = "Profile icon" },
	{ id = "classColor", kind = "color", label = "Class colour" },
}
RPStatus.BY_ID = {}
for _, f in ipairs(RPStatus.FIELDS) do RPStatus.BY_ID[f.id] = f end

-- The six roleplay style preferences, in Total RP 3's order (RegisterMisc.lua
-- STYLE_FIELDS: id, name, values), with the enUS labels (Locales/enUS.lua
-- 142-158, 996; NO and YES are the game's own "No" and "Yes").
local CONSENT = { { value = 0, label = "Do not show" }, { value = 2, label = "No" },
	{ value = 3, label = "With player permission" }, { value = 1, label = "Yes" } }
RPStatus.STYLE = {
	{ id = "styleInjury", key = "2", label = "Accept character injury", options = CONSENT,
		help = "Whether you are comfortable with your character getting injured." },
	{ id = "styleDeath", key = "3", label = "Accept character death", options = CONSENT,
		help = "Whether you are comfortable with your character dying." },
	{ id = "styleRomance", key = "4", label = "Accept character romance", options = CONSENT,
		help = "Whether you are comfortable with your character being romanced." },
	{ id = "styleCrime", key = "7", label = "Accept criminal activity", options = CONSENT,
		help = "Whether you are comfortable with your character being subjected to criminal activity, such as "
			.. "being mugged." },
	{ id = "styleControl", key = "8", label = "Accept loss of control", options = CONSENT,
		help = "Whether you are comfortable with your character being temporarily imprisoned or mind controlled." },
	{ id = "styleGuild", key = "6", label = "Guild membership", options = { { value = 0, label = "Do not show" },
		{ value = 2, label = "OOC membership" }, { value = 1, label = "IC membership" } },
		help = "The roleplay status of your membership within your guild." },
}
RPStatus.STYLE_BY_ID, RPStatus.STYLE_BY_KEY = {}, {}
for _, s in ipairs(RPStatus.STYLE) do
	RPStatus.STYLE_BY_ID[s.id] = s
	RPStatus.STYLE_BY_KEY[s.key] = s
end

--- The label of a choice's value ("Out of character"), or nil.
function RPStatus.OptionLabel(options, value)
	for _, o in ipairs(options or {}) do
		if o.value == value then return o.label end
	end
	return nil
end

--- A Currently or OOC text as Total RP 3 keeps it unchanged: escape codes
-- and "|" removed (Utils.str.sanitize would strip them), trimmed, capped.
-- "" stays "" (a deliberate clear). nil when not a string.
function RPStatus.CleanText(v)
	if type(v) ~= "string" then
		return nil
	end
	return Util.CleanText(v, RPStatus.LIMITS.text, true) or ""
end

--- A six-digit hex colour, lower case ("c41f3b"), or nil.
function RPStatus.CleanColor(v)
	if type(v) ~= "string" then
		return nil
	end
	v = v:gsub("^#", ""):lower()
	if not v:match("^%x%x%x%x%x%x$") then
		return nil
	end
	return v
end

--- One value checked for its field: the clean value, or nil plus a reason.
function RPStatus.Check(id, value)
	local f = RPStatus.BY_ID[id]
	if not f then
		return nil, "unknown status field"
	end
	if f.kind == "text" then
		local clean = RPStatus.CleanText(value)
		if not clean then return nil, "write some text, or clear it" end
		return clean
	elseif f.kind == "choice" then
		if RPStatus.OptionLabel(f.options, value) then return value end
		return nil, "choose one of the offered options"
	elseif f.kind == "icon" then
		local icon = ns.Glance.CleanIcon(value)
		if not icon then return nil, "an icon is a Total RP 3 icon name such as inv_misc_questionmark" end
		return icon
	elseif f.kind == "color" then
		local color = RPStatus.CleanColor(value)
		if not color then return nil, "a colour is six hex digits, such as c41f3b" end
		return color
	end
	return nil, "unknown status field"
end

--- Cleans char.trp3status on load: unknown keys and invalid values dropped.
function RPStatus.Clean(raw)
	local out = { style = {} }
	if type(raw) ~= "table" then
		return out
	end
	for _, f in ipairs(RPStatus.FIELDS) do
		if raw[f.id] ~= nil then
			out[f.id] = RPStatus.Check(f.id, raw[f.id])
		end
	end
	if type(raw.style) == "table" then
		for _, s in ipairs(RPStatus.STYLE) do
			local v = raw.style[s.key]
			if RPStatus.OptionLabel(s.options, v) then out.style[s.key] = v end
		end
	end
	return out
end

local function store(char)
	char.trp3status = char.trp3status or { style = {} }
	char.trp3status.style = char.trp3status.style or {}
	return char.trp3status
end

local function touch(char, now)
	if now then char.updatedAt = now end
end

--- Sets one value (checked). Returns the clean value, or nil plus a reason.
function RPStatus.Set(char, id, value, now)
	local clean, why = RPStatus.Check(id, value)
	if clean == nil then
		return nil, why
	end
	store(char)[id] = clean
	touch(char, now)
	return clean
end

--- Clears one value: a text becomes "" (emptied in Total RP 3 on the next
-- sync, if Dawnward wrote it there); any other value is forgotten (Total
-- RP 3 keeps what it shows). Returns true, or nil plus a reason.
function RPStatus.Clear(char, id, now)
	local f = RPStatus.BY_ID[id]
	if not f then
		return nil, "unknown status field"
	end
	store(char)[id] = f.kind == "text" and "" or nil
	touch(char, now)
	return true
end

--- Sets (or, with nil, forgets) one style preference by its Total RP 3
-- key. Returns true, or nil plus a reason.
function RPStatus.SetStyle(char, key, value, now)
	local s = RPStatus.STYLE_BY_KEY[key]
	if not s then
		return nil, "unknown roleplay style preference"
	end
	if value ~= nil and not RPStatus.OptionLabel(s.options, value) then
		return nil, "choose one of the offered options"
	end
	store(char).style[key] = value
	touch(char, now)
	return true
end

--- The player's values (a copy; never nil): { currently, ooc, rpStatus,
-- walkup, icon, classColor, style = { [key] = value } }.
function RPStatus.Get(char)
	return Util.DeepCopy(RPStatus.Clean(char and char.trp3status))
end
RPStatus.Published = RPStatus.Get

--- A draft Currently text from what Dawnward already knows: the zone the
-- player is in and their established active goal. Only ever put in the
-- editor for the player to change and save; never saved by itself. Returns
-- the text, or nil when there is nothing to suggest. Pure (zone is given).
function RPStatus.Suggest(char, zone)
	local parts = {}
	if type(zone) == "string" and zone ~= "" then
		parts[#parts + 1] = "In " .. Util.CleanText(zone, 80, false) .. "."
	end
	local goals = char and char.story and ns.Goals.Active(char) or {}
	local goal = goals[1]
	if goal and type(goal.title) == "string" and goal.title ~= "" then
		parts[#parts + 1] = "Working towards: " .. Util.CleanText(goal.title, 120, false) .. "."
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " ")
end
