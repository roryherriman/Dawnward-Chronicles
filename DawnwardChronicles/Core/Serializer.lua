-- Plain-data serializer with a hand-written parser.
--
-- Import text is untrusted (players paste it from anywhere), so it is never
-- passed to loadstring. The parser accepts only tables, strings, numbers and
-- booleans, with limits on size and nesting.
--
-- Format: {k=v,...} where keys are "quoted strings" or numbers, and values
-- are tables, "strings", numbers, true or false. Output is deterministic
-- (sorted keys), so the same data always produces the same text.
local _, ns = ...

local Serializer = {}
ns.Serializer = Serializer

Serializer.MAX_DEPTH = 16
Serializer.MAX_INPUT = 200000 -- bytes

local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
	s = s:gsub('[\\"\n\r\t]', ESCAPES)
	s = s:gsub("[%z\1-\31\127]", function(c)
		return string.format("\\%03d", c:byte())
	end)
	return '"' .. s .. '"'
end

local function encodeNumber(n)
	if n ~= n or n == math.huge or n == -math.huge then
		error("cannot serialize non-finite number", 0)
	end
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return string.format("%.0f", n)
	end
	return string.format("%.17g", n)
end

local function keyOrder(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta == "number" -- numbers first
	end
	return a < b
end

local encodeValue

local function encodeTable(t, depth, seen)
	if depth > Serializer.MAX_DEPTH then
		error("data is nested too deeply", 0)
	end
	if seen[t] then
		error("cannot serialize a table that contains itself", 0)
	end
	seen[t] = true
	local keys = {}
	for k in pairs(t) do
		local kt = type(k)
		if kt ~= "string" and kt ~= "number" then
			error("unsupported key type " .. kt, 0)
		end
		keys[#keys + 1] = k
	end
	table.sort(keys, keyOrder)
	local parts = {}
	for i, k in ipairs(keys) do
		local keyText = type(k) == "string" and encodeString(k) or encodeNumber(k)
		parts[i] = keyText .. "=" .. encodeValue(t[k], depth + 1, seen)
	end
	seen[t] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

encodeValue = function(v, depth, seen)
	local vt = type(v)
	if vt == "table" then
		return encodeTable(v, depth, seen)
	elseif vt == "string" then
		return encodeString(v)
	elseif vt == "number" then
		return encodeNumber(v)
	elseif vt == "boolean" then
		return v and "true" or "false"
	end
	error("unsupported value type " .. vt, 0)
end

--- Returns text, or nil plus an error message.
function Serializer.Encode(value)
	local ok, result = pcall(encodeValue, value, 0, {})
	if not ok then
		return nil, result
	end
	return result
end

--- Parser -------------------------------------------------------------------

local UNESCAPE = { n = "\n", r = "\r", t = "\t", ["\\"] = "\\", ['"'] = '"' }

local Parser = {}
Parser.__index = Parser

function Parser:fail(message)
	error(string.format("%s at position %d", message, self.pos), 0)
end

function Parser:peek()
	return self.text:sub(self.pos, self.pos)
end

function Parser:expect(char)
	if self:peek() ~= char then
		self:fail("expected '" .. char .. "'")
	end
	self.pos = self.pos + 1
end

function Parser:parseString()
	self:expect('"')
	local text = self.text
	local buffer = {}
	while true do
		local start = self.pos
		local stop = text:find('[\\"]', start)
		if not stop then
			self:fail("unterminated string")
		end
		buffer[#buffer + 1] = text:sub(start, stop - 1)
		local c = text:sub(stop, stop)
		if c == '"' then
			self.pos = stop + 1
			return table.concat(buffer)
		end
		local esc = text:sub(stop + 1, stop + 1)
		if UNESCAPE[esc] then
			buffer[#buffer + 1] = UNESCAPE[esc]
			self.pos = stop + 2
		else
			local digits = text:match("^%d%d%d", stop + 1)
			local code = digits and tonumber(digits)
			if not code or code > 255 then
				self.pos = stop
				self:fail("invalid escape")
			end
			buffer[#buffer + 1] = string.char(code)
			self.pos = stop + 4
		end
	end
end

function Parser:parseNumber()
	local token = self.text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", self.pos)
	local n = token and tonumber(token)
	if not n then
		self:fail("invalid number")
	end
	self.pos = self.pos + #token
	return n
end

function Parser:parseValue(depth)
	local c = self:peek()
	if c == "{" then
		return self:parseTable(depth + 1)
	elseif c == '"' then
		return self:parseString()
	elseif c == "-" or c:match("%d") then
		return self:parseNumber()
	elseif self.text:sub(self.pos, self.pos + 3) == "true" then
		self.pos = self.pos + 4
		return true
	elseif self.text:sub(self.pos, self.pos + 4) == "false" then
		self.pos = self.pos + 5
		return false
	end
	self:fail("unexpected character")
end

function Parser:parseTable(depth)
	if depth > Serializer.MAX_DEPTH then
		self:fail("data is nested too deeply")
	end
	self:expect("{")
	local t = {}
	if self:peek() == "}" then
		self.pos = self.pos + 1
		return t
	end
	while true do
		local key
		if self:peek() == '"' then
			key = self:parseString()
		else
			key = self:parseNumber()
		end
		if t[key] ~= nil then
			self:fail("duplicate key")
		end
		self:expect("=")
		t[key] = self:parseValue(depth)
		local c = self:peek()
		if c == "}" then
			self.pos = self.pos + 1
			return t
		end
		self:expect(",")
	end
end

--- Returns the decoded value, or nil plus an error message.
function Serializer.Decode(text)
	if type(text) ~= "string" then
		return nil, "input is not text"
	end
	if #text > Serializer.MAX_INPUT then
		return nil, "input is too large"
	end
	local parser = setmetatable({ text = text, pos = 1 }, Parser)
	local ok, result = pcall(function()
		local value = parser:parseValue(0)
		if parser.pos <= #text then
			parser:fail("unexpected trailing data")
		end
		return value
	end)
	if not ok then
		return nil, result
	end
	return result
end
