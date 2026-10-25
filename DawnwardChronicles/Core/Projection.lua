-- The only way character data leaves the core (docs/PRIVACY.md).
-- Projections are freshly built deep copies containing only allowed levels,
-- so callers can never reach or change the stored character through them.
local _, ns = ...
local Util, Schema, Privacy = ns.Util, ns.Schema, ns.Privacy

local Projection = {}
ns.Projection = Projection

--- allowed = { public = bool, private = bool, secret = bool }
function Projection.Filter(char, allowed)
	local out = { fields = {}, family = {}, history = {} }
	for key, entry in pairs(char.fields) do
		if Privacy.Allows(allowed, entry.visibility) then
			out.fields[key] = Util.DeepCopy(entry)
		end
	end
	for listName in pairs(Schema.LISTS) do
		for _, item in ipairs(char[listName]) do
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
