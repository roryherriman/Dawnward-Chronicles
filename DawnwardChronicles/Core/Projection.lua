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
	-- A public fact shares its statement, not where it came from: the quoted
	-- source excerpt and source links stay private (#32 "no hidden metadata";
	-- a fact approved from an imported story would otherwise carry the
	-- original sentence along even after the player reworded it).
	for _, fact in ipairs(out.facts) do
		local p = fact.provenance
		fact.provenance = type(p) == "table" and { origin = p.origin, interpreted = p.interpreted == true } or nil
	end
	out.stances = (char.story and ns.Identity) and ns.Identity.Public(char) or {}
	-- The biography (v0.9): the current version's text, exactly as stored,
	-- only when the player made the biography itself Public. Earlier
	-- versions and where it came from are never included.
	local current = char.sources and ns.Sources and ns.Sources.Current(char)
	if current and ns.Sources.Visibility(char) == Privacy.PUBLIC then
		out.biography = { text = current.text, hash = current.hash }
	end
	return out
end

Projection.ITEM_LISTS = ITEM_LISTS
