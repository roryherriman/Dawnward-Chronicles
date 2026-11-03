-- Pronouns (v0.10.3): the one place generated text learns how to refer to
-- the character. Every generator (Story Director questions and answers,
-- echoes, journal drafts, memories, development reasons, profile
-- suggestions) writes {they}, {them}, {their}, {theirs} and {themselves}
-- where it means the character, plus verb tokens that agree with them:
--   {are} {were} {have} {do}   are/is, were/was, have/has, do/does
--   {s} {es}                   a present-tense ending: "keep{s}" -> keeps
-- A capitalised token ({They}) is capitalised; so is any pronoun token at
-- the start of the text or of a sentence. Unknown tokens are left as they
-- are (Reactions fills the event's own tokens afterwards).
--
-- Forms come only from the profile's Pronouns field, never from race,
-- class, name or the player: "She/Her", "she/her/hers", "he/him",
-- "they/them", "it/its", a mixed "she/they" (the first set), or a complete
-- custom set of five ("xe/xem/xyr/xyrs/xemself"); object first
-- ("Her/She") too, and a note after a bracket, comma or dash is ignored.
-- Anything else, or no field at all, falls back to the character's whole
-- name ("Kyssarra Dawnward's strength", reflexive "themselves"), or "your
-- character" without a name; never to a guess.
--
-- Only newly generated text is rendered: the player's own words and texts
-- already stored are never rewritten.
local _, ns = ...

local Pronouns = {}
ns.Pronouns = Pronouns

-- subject, object, possessive determiner, possessive pronoun, reflexive.
Pronouns.SETS = {
	she = { they = "she", them = "her", their = "her", theirs = "hers", themselves = "herself" },
	he = { they = "he", them = "him", their = "his", theirs = "his", themselves = "himself" },
	they = { they = "they", them = "them", their = "their", theirs = "theirs", themselves = "themselves",
		plural = true },
	it = { they = "it", them = "it", their = "its", theirs = "its", themselves = "itself" },
}
Pronouns.FORMS = { "they", "them", "their", "theirs", "themselves" }

-- Every word that belongs to a known set (for "she/her/hers" and the like).
local MEMBERS = {}
for id, set in pairs(Pronouns.SETS) do
	for _, form in ipairs(Pronouns.FORMS) do
		MEMBERS[set[form]] = MEMBERS[set[form]] or {}
		MEMBERS[set[form]][id] = true
	end
end
MEMBERS.themself = { they = true }

-- Verb tokens: { plural (they), singular (she, he, a name) }.
local VERBS = { are = { "are", "is" }, were = { "were", "was" }, have = { "have", "has" }, ["do"] = { "do", "does" },
	s = { "", "s" }, es = { "", "es" } }

-- An em or en dash (UTF-8) starts a note too.
local DASHES = { "\226\128\147", "\226\128\148" }

local function words(value)
	local out = {}
	-- Anything after a bracket, a comma or a dash is a note, not a pronoun
	-- ("she/her (Kyss)", "she/her, ask me", "he/him - any").
	local text = value:lower()
	for _, dash in ipairs(DASHES) do
		local at = text:find(dash, 1, true)
		if at then text = text:sub(1, at - 1) end
	end
	text = text:match("^([^%(%[,%-]*)") or ""
	for w in text:gmatch("%a+") do
		out[#out + 1] = w
		if #out > 8 then return nil end
	end
	return out
end

--- The pronoun set a Pronouns field names, or nil when it is missing or
-- cannot be read safely. Returns a copy { they, them, their, theirs,
-- themselves, plural }. Pure.
function Pronouns.Parse(value)
	if type(value) ~= "string" then return nil end
	local w = words(value)
	if not w or #w == 0 then return nil end
	local set = Pronouns.SETS[w[1]]
	-- Object first ("Her/She", "him/he"): a word that belongs to one set only.
	if not set and MEMBERS[w[1]] then
		local only
		for id in pairs(MEMBERS[w[1]]) do
			if only then only = nil; break end
			only = id
		end
		set = only and Pronouns.SETS[only]
	end
	if set then
		-- Every other word must be a pronoun too: "she/her/hers", "she/they".
		for i = 2, #w do
			if not MEMBERS[w[i]] then return nil end
		end
		local out = {}
		for k, v in pairs(set) do out[k] = v end
		return out
	end
	-- A complete custom set: five distinct forms, the last one reflexive.
	if #w == 5 and w[5]:match("self$") then
		for i = 1, 5 do
			if MEMBERS[w[i]] then return nil end
		end
		return { they = w[1], them = w[2], their = w[3], theirs = w[4], themselves = w[5] }
	end
	return nil
end

local function shown(field, public)
	if type(field) ~= "table" or type(field.value) ~= "string" or field.value == "" then return nil end
	if public and field.visibility == ns.Privacy.SECRET then return nil end
	return field.value
end

--- How generated text refers to char: { they, them, their, theirs,
-- themselves, plural, known (from the profile), name }. opts.public: a
-- name or pronouns kept secret are not used. opts.neutral: without
-- readable pronouns, singular "they" instead of the name.
function Pronouns.For(char, opts)
	opts = opts or {}
	local fields = type(char) == "table" and type(char.fields) == "table" and char.fields or {}
	local name = shown(fields.name, opts.public)
	name = name and ns.Util.Trim((name:gsub("[{}%%]", ""))) or nil
	if name == "" then name = nil end
	local set = Pronouns.Parse(shown(fields.pronouns, opts.public))
	if set then
		set.known, set.name = true, name
		return set
	end
	if opts.neutral then
		local out = Pronouns.Parse("they/them")
		out.name = name
		return out
	end
	-- No readable pronouns: the whole name stands in for them (never its
	-- first word: "Sir Marcus Vale" is not "Sir"), and the reflexive is the
	-- neutral "themselves" (a name cannot be one).
	local who = name or "your character"
	return { they = who, them = who, their = who .. "'s", theirs = who .. "'s", themselves = "themselves",
		name = name, named = true }
end

local function capital(s)
	return (s:gsub("^%l", string.upper))
end

-- True when position i of text starts a sentence.
local function sentenceStart(text, i)
	local before = text:sub(1, i - 1)
	return before:match("^%s*$") ~= nil or before:match("[%.!%?]%s+$") ~= nil or before:match("\n%s*$") ~= nil
		or before:match("[%.!%?]\"%s+$") ~= nil
end

--- Renders the pronoun and verb tokens of text for forms (Pronouns.For) or
-- a character. Other {tokens} are left as they are. Pure.
function Pronouns.Render(text, forms)
	if type(text) ~= "string" then return text end
	if forms == nil or forms.they == nil then forms = Pronouns.For(forms) end
	return (text:gsub("(){(%a+)}", function(at, token)
		local lower = token:lower()
		local value
		if forms[lower] and lower ~= "plural" and lower ~= "known" and lower ~= "name" and lower ~= "named" then
			value = forms[lower]
			if token ~= lower or sentenceStart(text, at) then value = capital(value) end
			return value
		end
		local verb = VERBS[token]
		if verb then
			return forms.plural and verb[1] or verb[2]
		end
		return nil
	end))
end

--- Renders text for a character (a shortcut for Render(text, For(char, opts))).
function Pronouns.Text(char, text, opts)
	return Pronouns.Render(text, Pronouns.For(char, opts))
end

--- The character's name for generated text, or "Your character".
function Pronouns.Name(char, opts)
	return Pronouns.For(char, opts).name or "Your character"
end
