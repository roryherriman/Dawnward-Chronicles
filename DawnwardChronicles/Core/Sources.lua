-- Verbatim biography sources (for example a TRP3 About text or a paste).
--
-- Text is stored exactly as given: only its size is checked, nothing is
-- cleaned or truncated. StripTags, Paragraphs and Sentences are display
-- helpers; they return new strings and never change what is stored.
local _, ns = ...
local Schema, Util = ns.Schema, ns.Util

local Sources = {}
ns.Sources = Sources

--- Stores a new biography version and makes it current.
-- kind: trp3 | paste | written | answers. meta: { profile?, version?, note? }.
-- Returns version, "stored" | "unchanged"; or nil plus a reason. Text that
-- is identical to the current version stores nothing new.
function Sources.Capture(char, kind, text, meta, now)
	if not Schema.SOURCE_KINDS[kind] then
		return nil, "unknown source kind '" .. tostring(kind) .. "'"
	end
	if type(text) ~= "string" or text == "" then
		return nil, "the biography is empty"
	end
	if #text > Schema.FOUNDATION.bioBytes then
		return nil, string.format("the biography is %d bytes; the limit is %d. Nothing was stored "
			.. "(it is never shortened automatically).", #text, Schema.FOUNDATION.bioBytes)
	end
	local sources = char.sources
	local current = Sources.Current(char)
	if current and current.text == text then
		return current, "unchanged"
	end
	local version = {
		id = sources.nextId,
		kind = kind,
		text = text,
		hash = Schema.SourceHash(text),
		meta = Schema.CleanSourceMeta(meta),
		capturedAt = now or 0,
	}
	sources.nextId = sources.nextId + 1
	sources.versions[#sources.versions + 1] = version
	sources.current = version.id
	Schema.RotateSources(sources)
	if now then
		char.updatedAt = now
	end
	return version, "stored"
end

function Sources.Get(char, id)
	for _, version in ipairs(char.sources.versions) do
		if version.id == id then
			return version
		end
	end
	return nil
end

function Sources.Current(char)
	local current = char.sources.current
	return current and Sources.Get(char, current) or nil
end

--- Stored versions, oldest first (a new list of the stored records).
function Sources.Versions(char)
	local out = {}
	for i, version in ipairs(char.sources.versions) do
		out[i] = version
	end
	return out
end

--- Display helpers -------------------------------------------------------------

--- Removes TRP3 text tags for display. Link text is kept; images, icons and
-- unknown {...} tags are removed; closing heading and paragraph tags become
-- line breaks. A lone brace with no closing brace is left alone. Known
-- limit: a literal "{word}" in prose is indistinguishable from a tag and is
-- removed too.
function Sources.StripTags(text)
	if type(text) ~= "string" then
		return ""
	end
	local s = text
	-- Icons and images first, so links that contain an icon keep their text.
	s = s:gsub("{icon:[^{}]*}", "")
	s = s:gsub("{img:[^{}]*}", "")
	s = s:gsub("{link%*[^%*{}]*%*([^{}]*)}", "%1")
	s = s:gsub("{twitter%*[^%*{}]*%*([^{}]*)}", "%1")
	s = s:gsub("{/h%d}", "\n")
	s = s:gsub("{/p}", "\n")
	s = s:gsub("{[^{}]*}", "")
	return s
end

--- Splits text into trimmed, non-empty paragraphs (one per line).
function Sources.Paragraphs(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	for line in text:gmatch("[^\n]+") do
		line = Util.Trim(line)
		if line ~= "" then
			out[#out + 1] = line
		end
	end
	return out
end

-- Words that end in a full stop without ending a sentence (lower case, no dots).
local ABBREVIATIONS = {
	st = true, mr = true, mrs = true, ms = true, dr = true, lt = true, sgt = true, capt = true, cpt = true,
	gen = true, col = true, jr = true, sr = true, mt = true, ft = true, vs = true, eg = true, ie = true,
}

local ELLIPSIS = "\226\128\166" -- U+2026
local CJK_ENDS = { ["\227\128\130"] = true, ["\239\188\129"] = true, ["\239\188\159"] = true } -- 。！？
local CLOSERS = { ['"'] = true, ["'"] = true, [")"] = true, ["]"] = true,
	["\226\128\157"] = true, ["\226\128\153"] = true, ["\227\128\141"] = true, ["\227\128\143"] = true }

-- Returns the index of the last byte of any closing quotes or brackets after i.
local function skipClosers(s, i)
	while true do
		local one, three = s:sub(i + 1, i + 1), s:sub(i + 1, i + 3)
		if CLOSERS[one] then
			i = i + 1
		elseif CLOSERS[three] then
			i = i + 3
		else
			return i
		end
	end
end

local function isAbbreviation(before)
	local word = before:match("([%a%.]+)$")
	if not word then
		return false
	end
	word = word:gsub("%.", ""):lower()
	return ABBREVIATIONS[word] == true or #word == 1
end

--- Approximate sentence split for display and for quoting excerpts.
-- A sentence ends at . ! ? or an ellipsis (repeats allowed, closing quotes
-- included) followed by whitespace and then anything but a lower-case ASCII
-- letter, or at the end of the text; or right after CJK 。！？. A full stop
-- after a known abbreviation or a single letter does not end a sentence.
-- Known limits (pinned by tests): lower-case sentence starts are joined to
-- the previous sentence, and unlisted abbreviations split.
function Sources.Sentences(paragraph)
	local out = {}
	if type(paragraph) ~= "string" then
		return out
	end
	local s = Util.Trim(paragraph)
	local len = #s
	local start, i = 1, 1
	local function emit(last)
		local sentence = Util.Trim(s:sub(start, last))
		if sentence ~= "" then
			out[#out + 1] = sentence
		end
		start = last + 1
	end
	while i <= len do
		local c = s:sub(i, i)
		if CJK_ENDS[s:sub(i, i + 2)] then
			local last = skipClosers(s, i + 2)
			emit(last)
			i = last + 1
		elseif c == "." or c == "!" or c == "?" or s:sub(i, i + 2) == ELLIPSIS then
			local first = i
			local last = i
			if s:sub(i, i + 2) == ELLIPSIS then
				last = i + 2
			end
			-- Absorb repeated terminators ("?!", "...", "!…").
			while true do
				local n = s:sub(last + 1, last + 1)
				if n == "." or n == "!" or n == "?" then
					last = last + 1
				elseif s:sub(last + 1, last + 3) == ELLIPSIS then
					last = last + 3
				else
					break
				end
			end
			last = skipClosers(s, last)
			local boundary = false
			if last >= len then
				boundary = true
			else
				local nextChar = s:sub(last + 1):match("^%s+(.)")
				if nextChar and not nextChar:match("%l") then
					boundary = not (c == "." and last == first and isAbbreviation(s:sub(start, first - 1)))
				end
			end
			if boundary then
				emit(last)
			end
			i = last + 1
		else
			i = i + 1
		end
	end
	if start <= len then
		emit(len)
	end
	return out
end
