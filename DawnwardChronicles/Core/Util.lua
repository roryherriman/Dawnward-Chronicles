-- Small pure-Lua helpers shared by every layer. No WoW API use allowed here.
local _, ns = ...

local Util = {}
ns.Util = Util

--- Deep-copies plain data. Metatables are not copied; cycles are preserved.
function Util.DeepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do
		out[Util.DeepCopy(k, seen)] = Util.DeepCopy(v, seen)
	end
	return out
end

--- Shortens s to at most maxBytes without splitting a UTF-8 sequence.
function Util.TruncateUtf8(s, maxBytes)
	if #s <= maxBytes then
		return s
	end
	local cut = maxBytes
	-- Step back while the byte after the cut is a continuation byte (10xxxxxx).
	while cut > 0 do
		local nextByte = s:byte(cut + 1)
		if nextByte < 0x80 or nextByte >= 0xC0 then
			break
		end
		cut = cut - 1
	end
	return s:sub(1, cut)
end

function Util.Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Normalises player-entered text before it is stored.
--
-- WoW UI escape sequences (colours, links, textures) are removed and any
-- remaining "|" is dropped, so stored text never carries markup into chat,
-- frames, exports or TRP3. Control characters are removed; newlines are kept
-- only for multi-line fields. Returns nil for non-strings.
function Util.CleanText(s, maxBytes, multiline)
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("||", "|")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", "")
	s = s:gsub("|H.-|h(.-)|h", "%1")
	s = s:gsub("|[TA].-|[ta]", "")
	s = s:gsub("|K.-|k", "")
	s = s:gsub("|n", "\n")
	s = s:gsub("|", "")
	s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
	s = s:gsub("[%z\1-\9\11-\31\127]", "")
	if not multiline then
		s = s:gsub("\n", " ")
	end
	s = Util.Trim(s)
	if maxBytes then
		s = Util.TruncateUtf8(s, maxBytes)
	end
	return s
end

--- Splits off the first whitespace-delimited word. Returns word, rest (both possibly "").
function Util.NextWord(s)
	s = s or ""
	local word, rest = s:match("^%s*(%S+)%s*(.-)$")
	return word or "", rest or ""
end

function Util.IsPositiveInteger(n)
	return type(n) == "number" and n >= 1 and n == math.floor(n) and n < 2 ^ 31
end

--- Adler-32 as 8 hex digits. Formatted as two halves because %x on numbers
-- above 2^31 is not portable across Lua 5.1 builds. Used for export
-- checksums and biography content hashes; not a security measure.
function Util.Checksum(text)
	local a, b = 1, 0
	local len = #text
	local i = 1
	while i <= len do
		local chunkEnd = math.min(i + 3999, len)
		local bytes = { text:byte(i, chunkEnd) }
		for j = 1, #bytes do
			a = (a + bytes[j]) % 65521
			b = (b + a) % 65521
		end
		i = chunkEnd + 1
	end
	return string.format("%04x%04x", b, a)
end

function Util.CountKeys(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end
