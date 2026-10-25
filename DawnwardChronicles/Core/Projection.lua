-- The only way character data leaves the core (docs/PRIVACY.md).
-- Projections are freshly built deep copies containing only allowed levels,
-- so callers can never reach or change the stored character through them.
local _, ns = ...
local Util, Privacy = ns.Util, ns.Privacy

local Projection = {}
ns.Projection = Projection

local ITEM_LISTS = { "family", "history", "journal" }

--- allowed = { public = bool, private = bool, secret = bool }
-- The cosmetic theme is always included; journal event keys never are.
function Projection.Filter(char, allowed)
	local out = { fields = {}, family = {}, history = {}, journal = {}, theme = char.theme }
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
function Projection.GetPublic(char)
	return Projection.Filter(char, Privacy.PUBLIC_ONLY)
end

Projection.ITEM_LISTS = ITEM_LISTS
