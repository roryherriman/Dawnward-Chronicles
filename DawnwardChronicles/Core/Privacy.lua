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

--- The publication model (v0.9, docs/PRIVACY.md). A character set up with
-- the v0.9 wizard, or moved over with the one-time transition
-- (Core/Publication.lua), has char.publication.mode == "profile": what
-- describes the character to others (profile fields, family, history,
-- facts, personality, the public persona of a stance, the biography)
-- starts Public, so it can reach Total RP 3 without classifying every item.
-- The journal, private convictions, story records and answers keep their
-- own defaults (Private). Every other character keeps the original model:
-- everything starts Private.
Privacy.PROFILE_KINDS = { field = true, family = true, history = true, fact = true, personality = true,
	stance = true, biography = true }

function Privacy.ProfileModel(char)
	return type(char) == "table" and type(char.publication) == "table" and char.publication.mode == "profile"
end

--- The starting visibility of a new item of this kind on this character.
function Privacy.DefaultFor(char, kind)
	if Privacy.PROFILE_KINDS[kind] and Privacy.ProfileModel(char) then
		return Privacy.PUBLIC
	end
	return Privacy.DEFAULT
end
