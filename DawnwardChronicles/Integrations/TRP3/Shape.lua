-- Read-only shape checks for the TRP3 sections Dawnward may write
-- (layouts audited from TRP3 3.4.1 source; see docs/TRP3_INTEGRATION.md).
-- Unknown extra fields are allowed and preserved; anything that contradicts
-- the audited layout fails closed, so an unexpected TRP3 change can only
-- stop sync, never corrupt a profile. Pure Lua.
local _, ns = ...

local Shape = {}
ns.TRP3Shape = Shape

Shape.TRAIT_MIN, Shape.TRAIT_MAX = 0, 20

local function optionalString(v)
	return v == nil or type(v) == "string"
end

local function isVersion(v)
	return type(v) == "number" and v == math.floor(v) and v >= 0 and v < 1000
end

local function textHolder(t)
	return t == nil or (type(t) == "table" and optionalString(t.TX))
end

--- Returns true, or nil plus a reason.
function Shape.About(about)
	if type(about) ~= "table" then
		return nil, "the About section is missing"
	end
	if not isVersion(about.v) then
		return nil, "the About section has no valid version"
	end
	if about.TE ~= 1 and about.TE ~= 2 and about.TE ~= 3 then
		return nil, "unknown About template " .. tostring(about.TE)
	end
	if not textHolder(about.T1) then
		return nil, "template 1 has an unexpected layout"
	end
	if about.T2 ~= nil then
		if type(about.T2) ~= "table" then
			return nil, "template 2 has an unexpected layout"
		end
		for _, frame in ipairs(about.T2) do
			if not textHolder(frame) then
				return nil, "a template 2 frame has an unexpected layout"
			end
		end
	end
	if about.T3 ~= nil then
		if type(about.T3) ~= "table" then
			return nil, "template 3 has an unexpected layout"
		end
		for _, part in ipairs({ "PH", "PS", "HI" }) do
			if not textHolder(about.T3[part]) then
				return nil, "template 3 has an unexpected layout"
			end
		end
	end
	return true
end

local function validTrait(trait)
	if type(trait) ~= "table" then
		return false
	end
	local v = trait.V2
	if v ~= nil and (type(v) ~= "number" or v ~= math.floor(v) or v < Shape.TRAIT_MIN or v > Shape.TRAIT_MAX) then
		return false
	end
	if trait.ID ~= nil and type(trait.ID) ~= "number" then
		return false
	end
	return optionalString(trait.LT) and optionalString(trait.RT)
end

--- Returns true, or nil plus a reason.
function Shape.Characteristics(characteristics)
	if type(characteristics) ~= "table" then
		return nil, "the characteristics section is missing"
	end
	if not isVersion(characteristics.v) then
		return nil, "the characteristics section has no valid version"
	end
	local list = characteristics.PS
	if list ~= nil then
		if type(list) ~= "table" then
			return nil, "personality traits have an unexpected layout"
		end
		local n = 0
		for _ in pairs(list) do n = n + 1 end
		if n ~= #list then
			return nil, "personality traits are not a plain list"
		end
		for _, trait in ipairs(list) do
			if not validTrait(trait) then
				return nil, "a personality trait has an unexpected layout or value"
			end
		end
	end
	return true
end

Shape.BY_SECTION = { about = Shape.About, characteristics = Shape.Characteristics }

--- TRP3's section version rule (Utils.math.incrementNumber(v, 2)): +1, and
-- 100 wraps to 1. A missing version counts as 1, as TRP3's setters do.
function Shape.NextVersion(v)
	local n = (type(v) == "number" and v or 1) + 1
	if n >= 100 then
		n = 1
	end
	return n
end

--- Dawnward bumps by two steps. TRP3's editors save draft.v + 1, where the
-- draft was copied when the editor opened; skipping a number means a save
-- from an older draft can never land on the version other clients already
-- fetched from Dawnward (they only re-fetch when the number differs).
function Shape.DawnwardVersion(v)
	return Shape.NextVersion(Shape.NextVersion(v))
end
