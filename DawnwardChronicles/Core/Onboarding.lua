-- First-time setup (v0.6): the onboarding state, the rule for when the
-- wizard opens by itself, draft cleaning, and applying the choices. Pure:
-- UI/SetupWizard.lua draws the pages, Core/Actions.lua saves.
--
-- Saved state (additive; schema stays 5):
--   char.wizard                      { done, version, doneAt } once Finish is chosen
--   db.ui.wizardDrafts[characterKey] { page, values } while unfinished
-- Drafts live account-wide by character key, so an unfinished wizard never
-- creates a character record (and never starts story recording) early.
-- Nothing here writes to Total RP 3 or changes visibility.
local _, ns = ...
local Util = ns.Util

local Onboarding = {}
ns.Onboarding = Onboarding

Onboarding.VERSION = 1
Onboarding.MAX_DRAFTS = 50
Onboarding.PAGES = {
	{ id = "welcome", title = "Welcome" },
	{ id = "character", title = "Character" },
	{ id = "story", title = "Story" },
	{ id = "privacy", title = "Privacy" },
	{ id = "appearance", title = "Appearance" },
	{ id = "finish", title = "Finish" },
}

-- Profile fields the wizard asks for (keys of Schema.FIELDS), with limits.
Onboarding.FIELDS = {
	{ key = "name", label = "Name", max = 100 },
	{ key = "title", label = "Title", max = 100 },
	{ key = "pronouns", label = "Pronouns", max = 100 },
	{ key = "homeland", label = "Homeland", max = 100 },
	-- A long field: the wizard edits it in a text area at its full stored size.
	{ key = "summary", label = "About them", max = 2000, multiline = true },
}

-- Story preferences the wizard offers: { key, label, values = { {value, label} } }.
Onboarding.PREFS = {
	{ key = "frequency", label = "How often", values = { { "normal", "Normal" }, { "rare", "Rarely" },
		{ "frequent", "Often" }, { "off", "Never (events are still recorded)" } } },
	{ key = "places", label = "Place moments", values = { { "on", "On" }, { "fewer", "Fewer" },
		{ "off", "Off (places are still logged)" } } },
	{ key = "card", label = "Moment card", values = { { true, "Show a small card at a calm moment" },
		{ false, "Chat line only" } } },
	{ key = "approval", label = "Personality changes", values = { { "ask", "Ask me first" },
		{ "auto", "Apply at once (still reversible)" } } },
}

local function validPref(pref, value)
	for _, v in ipairs(pref.values) do
		if v[1] == value then return true end
	end
	return false
end

local function timestamp(v)
	return type(v) == "number" and v >= 0 and v == math.floor(v) and v or nil
end

--- Saved completion state: { done = true?, version?, doneAt? }. Unknown keys dropped.
function Onboarding.Clean(raw)
	if type(raw) ~= "table" or raw.done ~= true then
		return {}
	end
	local version = raw.version
	return {
		done = true,
		version = type(version) == "number" and version >= 1 and version == math.floor(version) and version or nil,
		doneAt = timestamp(raw.doneAt),
	}
end

--- A cleaned draft { page, values } or nil.
function Onboarding.CleanDraft(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local page = raw.page
	local values = {}
	local rawValues = type(raw.values) == "table" and raw.values or {}
	for _, field in ipairs(Onboarding.FIELDS) do
		local v = rawValues[field.key]
		if type(v) == "string" then
			values[field.key] = Util.CleanText(v, field.max, field.multiline)
		end
	end
	for _, pref in ipairs(Onboarding.PREFS) do
		if validPref(pref, rawValues[pref.key]) then
			values[pref.key] = rawValues[pref.key]
		end
	end
	if ns.Themes.IsValid(rawValues.theme) then values.theme = rawValues.theme end
	if type(rawValues.minimap) == "boolean" then values.minimap = rawValues.minimap end
	return {
		page = type(page) == "number" and page >= 1 and page <= #Onboarding.PAGES and page == math.floor(page)
			and page or 1,
		values = values,
	}
end

--- Cleans the account's drafts table (characterKey -> draft), at most MAX_DRAFTS.
function Onboarding.CleanDrafts(raw)
	local out, n = {}, 0
	if type(raw) ~= "table" then
		return out
	end
	local keys = {}
	for key in pairs(raw) do
		if type(key) == "string" and #key <= 100 then keys[#keys + 1] = key end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local draft = Onboarding.CleanDraft(raw[key])
		if draft and n < Onboarding.MAX_DRAFTS then
			out[key] = draft
			n = n + 1
		end
	end
	return out
end

function Onboarding.IsComplete(char)
	return char ~= nil and type(char.wizard) == "table" and char.wizard.done == true
end

-- A record holding only what Dawnward recorded by itself (level-ups,
-- places, events) still counts as new for this long after it was created,
-- so a fresh character that levelled before opening Dawnward gets the
-- wizard, while an old record never does.
Onboarding.NEW_WINDOW = 7 * 24 * 3600

--- Whether a character already has Dawnward data of its own. Anything the
-- player wrote or answered counts at once. Data Dawnward recorded by itself
-- counts once the record is older than NEW_WINDOW (now is the current
-- time; without it, automatic data always counts). Established characters
-- never get the wizard automatically; it stays available from Settings.
function Onboarding.IsEstablished(char, now)
	if not char then
		return false
	end
	if next(char.fields or {}) or next(char.personality or {}) then
		return true
	end
	for _, list in ipairs({ "family", "history", "facts" }) do
		if char[list] and #char[list] > 0 then return true end
	end
	local automatic = false
	for _, entry in ipairs(char.journal or {}) do
		if entry.kind == "event" then automatic = true else return true end
	end
	local story = char.story or {}
	for _, list in ipairs({ "decisions", "memories", "arcs", "goals", "identity", "people" }) do
		if story[list] and #story[list] > 0 then return true end
	end
	if (story.events and #story.events > 0) or (story.places and next(story.places)) then
		automatic = true
	end
	if not automatic then
		return false
	end
	local created = type(char.createdAt) == "number" and char.createdAt or 0
	return not now or now - created > Onboarding.NEW_WINDOW
end

--- Whether the wizard should open by itself for this character.
function Onboarding.ShouldAutoLaunch(char, now)
	return not Onboarding.IsComplete(char) and not Onboarding.IsEstablished(char, now)
end

--- Starting values: the character's saved data where it exists (never
-- blanked), otherwise safe defaults. suggestedName (the in-game name) only
-- fills an empty name, as a suggestion the player can change.
function Onboarding.DefaultValues(char, suggestedName, minimapShown)
	local values = {}
	for _, field in ipairs(Onboarding.FIELDS) do
		local entry = char and char.fields[field.key]
		values[field.key] = entry and entry.value or ""
	end
	if values.name == "" and type(suggestedName) == "string" then
		values.name = Util.CleanText(suggestedName, 100) or ""
	end
	local prefs = char and char.story.prefs or ns.StorySchema.DEFAULT_PREFS
	for _, pref in ipairs(Onboarding.PREFS) do
		values[pref.key] = validPref(pref, prefs[pref.key]) and prefs[pref.key] or pref.values[1][1]
	end
	values.theme = char and ns.Themes.IsValid(char.theme) and char.theme or ns.Themes.DEFAULT
	values.minimap = minimapShown ~= false
	return values
end

--- Applies the wizard's values to char. Only keys the player changed in
-- the wizard are applied when opts.only (a set of keys) is given, so
-- settings changed elsewhere since a draft are never undone. Profile fields
-- are written only when non-empty and different from what is saved:
-- nothing is cleared or blanked. Returns { fields = { changed keys },
-- prefs = n, theme = id }. opts.complete marks onboarding complete (never
-- in test mode).
function Onboarding.Apply(char, values, now, opts)
	opts = opts or {}
	local only = opts.only
	local function wanted(key) return not only or only[key] end
	local changed = { fields = {}, prefs = 0 }
	for _, field in ipairs(Onboarding.FIELDS) do
		local v = values[field.key]
		v = type(v) == "string" and Util.Trim(v) or ""
		local entry = char.fields[field.key]
		if wanted(field.key) and v ~= "" and (not entry or entry.value ~= v) then
			if ns.Character.SetField(char, field.key, v, now) then
				changed.fields[#changed.fields + 1] = field.key
			end
		end
	end
	for _, pref in ipairs(Onboarding.PREFS) do
		local v = values[pref.key]
		if wanted(pref.key) and validPref(pref, v) and char.story.prefs[pref.key] ~= v then
			char.story.prefs[pref.key] = v
			changed.prefs = changed.prefs + 1
		end
	end
	if wanted("theme") and ns.Themes.IsValid(values.theme) and char.theme ~= values.theme then
		char.theme = values.theme
		changed.theme = values.theme
	end
	if opts.complete then
		char.wizard = { done = true, version = Onboarding.VERSION, doneAt = now or 0 }
	end
	return changed
end

local function labelOf(pref, value)
	for _, v in ipairs(pref.values) do
		if v[1] == value then return v[2] end
	end
	return tostring(value)
end

--- Review lines for the Finish page. Pure.
function Onboarding.Summary(values)
	local lines = {}
	for _, field in ipairs(Onboarding.FIELDS) do
		local v = values[field.key]
		if type(v) == "string" and v:match("%S") then
			-- One line each: long text is shortened here only, never when saved.
			v = v:gsub("%s+", " ")
			if #v > 70 then v = Util.TruncateUtf8(v, 70) .. "..." end
		else
			v = "(not set; you can add it later)"
		end
		lines[#lines + 1] = string.format("%s: %s", field.label, v)
	end
	for _, pref in ipairs(Onboarding.PREFS) do
		lines[#lines + 1] = string.format("%s: %s", pref.label, labelOf(pref, values[pref.key]))
	end
	lines[#lines + 1] = "Theme: " .. ns.Themes.Get(values.theme).name
	lines[#lines + 1] = "Minimap button: " .. (values.minimap == false and "hidden" or "shown")
	return lines
end
