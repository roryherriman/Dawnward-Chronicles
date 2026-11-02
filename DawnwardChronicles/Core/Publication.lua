-- The publication model (v0.10, docs/PRIVACY.md "Publication model").
--
-- A character's profile is what Dawnward publishes once Total RP 3 is
-- connected: profile details, the biography, family, history, facts,
-- personality, the public persona of established stances and the defining
-- moments the player approved. There is no per-item visibility any more;
-- what is a draft (unapproved suggestions, journal notes, story answers, a
-- stance's inner conviction) is simply never part of the profile.
--
-- char.publication:
--   {}                                   the original (pre-v0.9) model:
--                                        only items marked Public publish
--   { mode = "profile" }                 the v0.9 model: still filtered by
--                                        each item's old visibility
--   { mode = "profile", version = 2 }    the v0.10 model: the whole profile
--                                        publishes, old visibility ignored
--
-- Moving to version 2 never publishes anything silently:
--   * a new character set up with the wizard starts on version 2 (Adopt)
--   * a v0.9 character with nothing hidden moves by itself (Upgrade): it
--     publishes exactly what it already did
--   * any other character needs the player's one-time confirmation
--     (Transition), which first lists what would become part of the profile
--   * old visibility values are kept untouched, so Revert puts the character
--     back exactly as it was
-- Pure Lua; Core/Actions.lua saves.
local _, ns = ...
local Privacy = ns.Privacy

local Publication = {}
ns.Publication = Publication

Publication.VERSION = 2

-- Categories of profile content, in display order.
Publication.CATEGORIES = {
	{ id = "fields", label = "Profile details" },
	{ id = "biography", label = "Biography" },
	{ id = "facts", label = "Facts about the character" },
	{ id = "personality", label = "Personality values" },
	{ id = "stances", label = "Stance personas" },
	{ id = "family", label = "Family" },
	{ id = "history", label = "History" },
	{ id = "moments", label = "Defining moments" },
}
Publication.CATEGORY_IDS = {}
for _, c in ipairs(Publication.CATEGORIES) do
	Publication.CATEGORY_IDS[c.id] = true
end

-- The old visibility of every profile item of a category (a list of levels).
local function levels(char, id)
	local out = {}
	if id == "fields" then
		for _, entry in pairs(char.fields or {}) do out[#out + 1] = entry.visibility end
	elseif id == "biography" then
		if ns.Sources.Current(char) then out[#out + 1] = ns.Sources.Visibility(char) end
	elseif id == "personality" then
		for _, entry in pairs(char.personality or {}) do out[#out + 1] = entry.visibility end
	elseif id == "stances" then
		for _, i in ipairs(char.story and char.story.identity or {}) do
			if i.status == "established" and i.persona then out[#out + 1] = i.visibility end
		end
	elseif id == "moments" then
		for _, e in ipairs(char.journal or {}) do
			if e.kind == "story" and e.status == "approved" and e.important then out[#out + 1] = e.visibility end
		end
	else
		for _, item in ipairs(char[id] or {}) do out[#out + 1] = item.visibility end
	end
	return out
end

--- Whether the whole profile publishes (the v0.10 model).
function Publication.IsComplete(char)
	local p = type(char) == "table" and char.publication
	return type(p) == "table" and p.mode == "profile" and (tonumber(p.version) or 1) >= Publication.VERSION
end

function Publication.IsProfile(char)
	return Privacy.ProfileModel(char)
end

--- Counts per category: { [id] = { public = n, private = n, secret = n } },
-- by the items' old visibility.
function Publication.Preview(char)
	local out = {}
	for _, c in ipairs(Publication.CATEGORIES) do
		local counts = { public = 0, private = 0, secret = 0 }
		for _, level in ipairs(levels(char, c.id)) do
			level = Privacy.Normalize(level)
			counts[level] = counts[level] + 1
		end
		out[c.id] = counts
	end
	return out
end

--- How many profile items are not published yet (old Private or Secret).
function Publication.HiddenCount(char)
	if Publication.IsComplete(char) then return 0 end
	local n = 0
	for _, counts in pairs(Publication.Preview(char)) do
		n = n + counts.private + counts.secret
	end
	return n
end

--- "profile" (the whole profile publishes), "pending" (the player's
-- one-time confirmation is needed before older content publishes) or
-- "empty" (nothing to publish and nothing to confirm).
function Publication.Status(char)
	if Publication.IsComplete(char) then return "profile" end
	if Publication.HiddenCount(char) > 0 then return "pending" end
	return Privacy.ProfileModel(char) and "profile" or "empty"
end

--- A new character (the wizard's Finish): the v0.10 model from the start.
function Publication.Adopt(char, now)
	if not Publication.IsComplete(char) then
		char.publication = { mode = "profile", version = Publication.VERSION, since = now or 0 }
	end
	return char.publication
end

--- Load-time upgrade (idempotent): a v0.9 character whose profile items are
-- all Public already publishes everything, so it moves to version 2 without
-- asking. Returns true when it changed.
function Publication.Upgrade(char)
	if type(char) ~= "table" or Publication.IsComplete(char) or not Privacy.ProfileModel(char) then
		return false
	end
	if Publication.HiddenCount(char) > 0 then
		return false
	end
	char.publication.version = Publication.VERSION
	char.publication.upgraded = true
	return true
end

--- The one-time confirmation: the whole profile publishes from now on,
-- including items an older version kept Private or Secret. Old visibility
-- values are not changed (Revert undoes this exactly). Returns
-- { [categoryId] = number now published that was not before }, or nil plus
-- a reason.
function Publication.Transition(char, _, now)
	if Publication.IsComplete(char) then
		return nil, "this character's whole profile is already published"
	end
	local changed = {}
	for _, c in ipairs(Publication.CATEGORIES) do
		local counts = Publication.Preview(char)[c.id]
		changed[c.id] = counts.private + counts.secret
	end
	local previous = ns.Util.DeepCopy(char.publication or {})
	char.publication = { mode = "profile", version = Publication.VERSION, since = now or 0,
		transitionedAt = now or 0, previous = previous }
	if now then
		char.updatedAt = now
	end
	return changed
end

--- Undoes Transition: the character is back on the model it had before.
function Publication.Revert(char, now)
	local p = type(char) == "table" and char.publication
	if type(p) ~= "table" or type(p.previous) ~= "table" then
		return nil, "there is no earlier publication model to go back to"
	end
	char.publication = p.previous
	if now then
		char.updatedAt = now
	end
	return true
end

--- One line per category with content not yet published, for a confirmation.
function Publication.PreviewLines(char)
	local preview = Publication.Preview(char)
	local lines = {}
	for _, c in ipairs(Publication.CATEGORIES) do
		local n = preview[c.id]
		local hidden = n.private + n.secret
		if hidden > 0 then
			lines[#lines + 1] = string.format("%s: %d more to publish (%d already published)", c.label, hidden,
				n.public)
		end
	end
	return lines
end
