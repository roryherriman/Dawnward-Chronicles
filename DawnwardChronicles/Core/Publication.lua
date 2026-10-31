-- The publication model (v0.9, docs/PRIVACY.md "Publication model").
--
-- New characters set up with the v0.9 wizard use the profile model from the
-- start (Publication.Adopt): what describes the character to others starts
-- Public, ready for Total RP 3, so nothing has to be classified item by
-- item. Characters created before v0.9 keep the original model (everything
-- starts Private) until the player chooses the one-time transition here.
--
-- The transition never publishes anything silently:
--   * Preview lists, per category, how many items are Private, Secret and
--     already Public; nothing changes until Transition is called with the
--     categories the player ticked
--   * only Private items of the chosen categories become Public
--   * Secret items are never changed: they stay Secret
--   * the journal, memories, story records and private convictions are not
--     part of it (they keep their own visibility)
-- Pure Lua; Core/Actions.lua saves.
local _, ns = ...
local Privacy = ns.Privacy

local Publication = {}
ns.Publication = Publication

-- Categories the transition offers, in display order.
Publication.CATEGORIES = {
	{ id = "fields", label = "Profile details" },
	{ id = "biography", label = "Biography" },
	{ id = "facts", label = "Facts about the character" },
	{ id = "personality", label = "Personality values" },
	{ id = "stances", label = "Public personas (stances)" },
	{ id = "family", label = "Family" },
	{ id = "history", label = "History" },
}
Publication.CATEGORY_IDS = {}
for _, c in ipairs(Publication.CATEGORIES) do
	Publication.CATEGORY_IDS[c.id] = true
end

-- Every item of a category, as { get = fn() -> level, set = fn(level) }.
local function items(char, id)
	local out = {}
	local function add(get, set)
		out[#out + 1] = { get = get, set = set }
	end
	if id == "fields" then
		for _, entry in pairs(char.fields or {}) do
			add(function() return entry.visibility end, function(level) entry.visibility = level end)
		end
	elseif id == "biography" then
		if ns.Sources.Current(char) then
			add(function() return ns.Sources.Visibility(char) end,
				function(level) char.sources.visibility = level end)
		end
	elseif id == "personality" then
		for _, entry in pairs(char.personality or {}) do
			add(function() return entry.visibility end, function(level) entry.visibility = level end)
		end
	elseif id == "stances" then
		for _, i in ipairs(char.story and char.story.identity or {}) do
			-- Only established stances with a persona; suggestions stay Private.
			if i.status == "established" and i.persona then
				add(function() return i.visibility end, function(level) i.visibility = level end)
			end
		end
	else
		for _, item in ipairs(char[id] or {}) do
			add(function() return item.visibility end, function(level) item.visibility = level end)
		end
	end
	return out
end

function Publication.IsProfile(char)
	return Privacy.ProfileModel(char)
end

--- Counts per category: { [id] = { public = n, private = n, secret = n } }.
function Publication.Preview(char)
	local out = {}
	for _, c in ipairs(Publication.CATEGORIES) do
		local counts = { public = 0, private = 0, secret = 0 }
		for _, item in ipairs(items(char, c.id)) do
			local level = Privacy.Normalize(item.get())
			counts[level] = counts[level] + 1
		end
		out[c.id] = counts
	end
	return out
end

--- Starts the profile model for a character with nothing to convert (the
-- v0.9 wizard's Finish, before its values are applied).
function Publication.Adopt(char, now)
	if not Privacy.ProfileModel(char) then
		char.publication = { mode = "profile", since = now or 0 }
	end
	return char.publication
end

--- The one-time transition. choices = { [categoryId] = true } for the
-- categories whose Private items should become Public. Secret items are
-- never changed. Returns { [categoryId] = number made Public }, or nil plus
-- a reason (nothing changes then).
function Publication.Transition(char, choices, now)
	if Privacy.ProfileModel(char) then
		return nil, "this character already uses the profile model"
	end
	choices = type(choices) == "table" and choices or {}
	for id in pairs(choices) do
		if not Publication.CATEGORY_IDS[id] then
			return nil, "unknown category '" .. tostring(id) .. "'"
		end
	end
	local changed = {}
	for _, c in ipairs(Publication.CATEGORIES) do
		changed[c.id] = 0
		if choices[c.id] then
			for _, item in ipairs(items(char, c.id)) do
				if Privacy.Normalize(item.get()) == Privacy.PRIVATE then
					item.set(Privacy.PUBLIC)
					changed[c.id] = changed[c.id] + 1
				end
			end
		end
	end
	char.publication = { mode = "profile", since = now or 0, transitionedAt = now or 0 }
	if now then
		char.updatedAt = now
	end
	return changed
end

--- One line per category for a confirmation: what the transition would do.
function Publication.PreviewLines(char, choices)
	local preview = Publication.Preview(char)
	local lines = {}
	for _, c in ipairs(Publication.CATEGORIES) do
		local n = preview[c.id]
		if n.private + n.secret + n.public > 0 then
			local action
			if choices and choices[c.id] and n.private > 0 then
				action = string.format("%d Private become Public", n.private)
			elseif n.private > 0 then
				action = string.format("%d stay Private", n.private)
			else
				action = "nothing to change"
			end
			if n.secret > 0 then
				action = action .. string.format("; %d Secret stay Secret", n.secret)
			end
			lines[#lines + 1] = string.format("%s: %s (%d already Public)", c.label, action, n.public)
		end
	end
	return lines
end
