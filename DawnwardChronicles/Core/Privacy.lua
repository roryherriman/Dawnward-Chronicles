-- Visibility levels for every stored fact. See docs/PRIVACY.md.
local _, ns = ...

local Privacy = {}
ns.Privacy = Privacy

Privacy.PUBLIC = "public"
Privacy.PRIVATE = "private"
Privacy.SECRET = "secret"

-- Making something public must always be an explicit choice.
Privacy.DEFAULT = Privacy.PRIVATE

local VALID = {
	[Privacy.PUBLIC] = true,
	[Privacy.PRIVATE] = true,
	[Privacy.SECRET] = true,
}

function Privacy.IsValid(level)
	return VALID[level] == true
end

--- Returns level if valid, otherwise the safe default.
function Privacy.Normalize(level)
	if VALID[level] then
		return level
	end
	return Privacy.DEFAULT
end

--- Whether an item with this level passes a filter.
-- allowed = { public = bool, private = bool, secret = bool }
function Privacy.Allows(allowed, level)
	return allowed[Privacy.Normalize(level)] == true
end

Privacy.PUBLIC_ONLY = { public = true }
