-- Deterministic fuzz corpus generators (issue #24 adversarial gate).
--
-- Everything here is seeded: the same seed always gives the same input on
-- every machine (no math.random, whose sequence differs between Lua builds).
-- The generators build disposable test inputs only; nothing here touches a
-- real profile or real saved variables.
local Fuzz = {}

--- A Park-Miller "minimal standard" generator. Exact in Lua 5.1 doubles
-- (16807 * (2^31 - 2) < 2^53), so every platform gives the same sequence.
function Fuzz.Rng(seed)
	local state = (math.floor(tonumber(seed) or 1) % 2147483646) + 1
	local rng = {}
	--- An integer in [lo, hi] (or [1, lo] when hi is nil).
	function rng.int(lo, hi)
		if not hi then lo, hi = 1, lo end
		state = (state * 16807) % 2147483647
		return lo + (state % (hi - lo + 1))
	end
	function rng.pick(list) return list[rng.int(1, #list)] end
	function rng.chance(n) return rng.int(1, n) == 1 end
	return rng
end

-- TRP3 and WoW markup: colour codes, textures, hyperlinks, TRP3's own tags
-- (totalRP3/Core/Utils.lua convertTextTags: {h1}, {col:...}, {icon:...},
-- {link*...}), escape sequences and stray pipes.
Fuzz.MARKUP = {
	"|cffff0000", "|cFF00FF00", "|r", "|cnRED_FONT_COLOR:", "||", "|", "|n",
	"|TInterface\\ICONS\\inv_misc_questionmark:18|t", "|TInterface\\ICONS\\:0|t", "|T", "|t",
	"|Hitem:19019::::::::60:::::|h[Thunderfury]|h", "|Hplayer:Someone|h[Someone]|h", "|H", "|h",
	"|A:raceicon-human-female:16:16|a", "|K12345|k", "|4singular:plural;",
	"{icon:inv_misc_questionmark:20}", "{icon:}", "{icon:../../evil:9999}", "{col:ff0000}", "{col:zz}", "{/col}",
	"{h1}", "{/h1}", "{h2:c}", "{/h2}", "{h3:r}", "{p:c}", "{/p}", "{link*https://example.invalid*click}",
	"{twitter*x*y}", "{", "}", "{{}}",
	"<!-- dawnward -->", "<!-- dawnward:end -->", "[Dawnward]", "## Dawnward ##", "%s", "%d", "%%", "\\n",
}

-- Unicode and byte-level oddities, including invalid UTF-8.
Fuzz.UNICODE = {
	"\195\134lin", "Kael'thas", "\230\151\165\230\156\172\232\170\158", "\240\159\153\130",
	"\217\133\216\177\216\173\216\168\216\167",
	"\226\128\174reversed", "e\204\129", "\239\187\191BOM", "\255\254", "\226\128", "\192\128", "\0",
	"\t", "\r", "\r\n", "\n\n\n", "   ", "\194\160", "\226\128\139",
}

Fuzz.WORDS = {
	"the", "lantern", "Stormwind", "oath", "she", "they", "kept", "a", "secret", "blade", "Lordaeron",
	"born", "in", "fire", "and", "ash", "Aelin", "never", "forgave", "her", "brother", "PRIVATE", "SECRET",
}

--- A random word or fragment (plain, markup or unicode).
function Fuzz.Token(rng)
	local roll = rng.int(1, 10)
	if roll <= 5 then return rng.pick(Fuzz.WORDS) end
	if roll <= 8 then return rng.pick(Fuzz.MARKUP) end
	return rng.pick(Fuzz.UNICODE)
end

--- A line of up to maxTokens tokens.
function Fuzz.Line(rng, maxTokens)
	local parts = {}
	for i = 1, rng.int(1, maxTokens or 12) do
		parts[i] = Fuzz.Token(rng)
	end
	return table.concat(parts, rng.chance(4) and "" or " ")
end

--- A multi-paragraph biography with markup, unicode and odd line breaks.
function Fuzz.Biography(rng, maxParagraphs)
	local paragraphs = {}
	for p = 1, rng.int(1, maxParagraphs or 6) do
		local lines = {}
		for l = 1, rng.int(1, 4) do
			lines[l] = Fuzz.Line(rng, 16)
		end
		paragraphs[p] = table.concat(lines, rng.pick({ "\n", " ", "\r\n", "|n" }))
	end
	return table.concat(paragraphs, rng.pick({ "\n\n", "\n\n\n", "\r\n\r\n", "\n \n" }))
end

--- Text of exactly n bytes (repeating a markup-heavy pattern, cut anywhere,
-- so it may end inside a colour code or a multi-byte character).
function Fuzz.Oversized(n, seed)
	local rng = Fuzz.Rng(seed or 7)
	local parts, size = {}, 0
	while size < n do
		local piece = Fuzz.Token(rng) .. " "
		parts[#parts + 1] = piece
		size = size + #piece
	end
	return table.concat(parts):sub(1, n)
end

--- Odd values of every Lua type a SavedVariables file (or a client API)
-- can hand back.
function Fuzz.OddValue(rng)
	return rng.pick({
		function() return nil end,
		function() return false end,
		function() return true end,
		function() return 0 end,
		function() return -1 end,
		function() return 2 ^ 53 end,
		function() return math.huge end,
		function() return -math.huge end,
		function() return 1.5 end,
		function() return "" end,
		function() return "garbage" end,
		function() return "42" end,
		function() return Fuzz.Oversized(300, rng.int(1, 1000)) end,
		function() return {} end,
		function() return { 1, 2, 3 } end,
		function() return { garbage = true } end,
	})()
end

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[deepCopy(k)] = deepCopy(x) end
	return out
end
Fuzz.DeepCopy = deepCopy

-- Every path (list of keys) in t, in a stable order (sorted by key text),
-- so the same seed always mutates the same place.
local function paths(t, prefix, out, seen)
	out, prefix, seen = out or {}, prefix or {}, seen or {}
	if seen[t] then return out end
	seen[t] = true
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then return ta < tb end
		if ta == "number" or ta == "string" then return a < b end
		return tostring(a) < tostring(b)
	end)
	for _, k in ipairs(keys) do
		local path = {}
		for i, p in ipairs(prefix) do path[i] = p end
		path[#path + 1] = k
		out[#out + 1] = path
		if type(t[k]) == "table" then paths(t[k], path, out, seen) end
	end
	return out
end
Fuzz.Paths = paths

local function setPath(root, path, value)
	local t = root
	for i = 1, #path - 1 do
		t = t[path[i]]
		if type(t) ~= "table" then return false end
	end
	t[path[#path]] = value
	return true
end

--- Returns a mutated deep copy of t and a log of what changed: count
-- random deletions, type swaps and truncations (a table cut to half its
-- keys, as a SavedVariables file cut short might leave it). opts.within
-- limits mutations to paths starting with that prefix (a list of keys).
function Fuzz.Mutate(t, seed, count, opts)
	opts = opts or {}
	local rng = Fuzz.Rng(seed)
	local copy = deepCopy(t)
	local log = {}
	for _ = 1, count or 3 do
		local all = paths(copy)
		local candidates = {}
		for _, p in ipairs(all) do
			local ok = true
			for i, k in ipairs(opts.within or {}) do
				if p[i] ~= k then ok = false break end
			end
			if ok and #p > #(opts.within or {}) then candidates[#candidates + 1] = p end
		end
		if #candidates == 0 then break end
		local path = rng.pick(candidates)
		local how = rng.pick({ "delete", "swap", "swap", "truncate" })
		local label = {}
		for i, k in ipairs(path) do label[i] = tostring(k) end
		if how == "truncate" then
			local parentPath = { unpack(path, 1, #path - 1) }
			local holder = copy
			for _, k in ipairs(parentPath) do holder = holder[k] end
			local target = holder[path[#path]]
			if type(target) == "table" then
				local keys = {}
				for k in pairs(target) do keys[#keys + 1] = k end
				table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
				for i = math.floor(#keys / 2) + 1, #keys do target[keys[i]] = nil end
			else
				how = "delete"
			end
		end
		if how == "delete" then
			setPath(copy, path, nil)
		elseif how == "swap" then
			setPath(copy, path, Fuzz.OddValue(rng))
		end
		log[#log + 1] = how .. " " .. table.concat(label, ".")
	end
	return copy, log
end

return Fuzz
