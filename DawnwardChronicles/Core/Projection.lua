-- The only way character data leaves the core (docs/PRIVACY.md).
-- Projections are freshly built deep copies containing only allowed levels,
-- so callers can never reach or change the stored character through them.
local _, ns = ...
local Util, Privacy = ns.Util, ns.Privacy

local Projection = {}
ns.Projection = Projection

local ITEM_LISTS = { "family", "history", "journal", "facts" }

--- allowed = { public = bool, private = bool, secret = bool }
-- The cosmetic theme is always included. Journal event keys, biography
-- sources, interpretations and their key memory never are.
function Projection.Filter(char, allowed)
	local out = { fields = {}, family = {}, history = {}, journal = {}, facts = {}, personality = {},
		theme = char.theme }
	for axisId, entry in pairs(char.personality or {}) do
		if Privacy.Allows(allowed, entry.visibility) then
			out.personality[axisId] = Util.DeepCopy(entry)
		end
	end
	for key, entry in pairs(char.fields) do
		if Privacy.Allows(allowed, entry.visibility) then
			out.fields[key] = Util.DeepCopy(entry)
		end
	end
	for _, listName in ipairs(ITEM_LISTS) do
		for _, item in ipairs(char[listName] or {}) do
			if Privacy.Allows(allowed, item.visibility) then
				local list = out[listName]
				list[#list + 1] = Util.DeepCopy(item)
			end
		end
	end
	return out
end

--- Public facts only: what TRP3 and shareable exports may ever see.
-- From the story records, only established public identity statements
-- (the public persona, and a conviction only if it is itself public) are
-- added; memories, arcs, goals, decisions and answers never are.
function Projection.GetPublic(char)
	local out = Projection.Filter(char, Privacy.PUBLIC_ONLY)
	out.stances = (char.story and ns.Identity) and ns.Identity.Public(char) or {}
	return out
end

Projection.ITEM_LISTS = ITEM_LISTS
