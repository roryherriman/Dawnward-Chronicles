-- Architecture rules checked against the source text of Core/.
--
-- Canon may only be created by the player (Facts.Add, called from Actions)
-- or by explicit promotion (Interpretations.Promote, which calls
-- Facts.AddFromInterpretation). These scans catch new code that writes into
-- a facts list some other way. They are pattern checks, so the scanner is
-- itself tested against planted violations below.
local Loader = require("support.loader")

local function read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

-- Strips comments so documentation can mention the rules freely.
local function code(text)
	text = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	return (text:gsub("%-%-[^\n]*", ""))
end

local RULES = {
	{ name = "index assignment into a facts list", pattern = "facts%s*%[[^%]]*%]%s*=[^=]", allowed = { "Facts.lua" } },
	{ name = "table.insert into a facts list", pattern = "table%.insert%s*%(%s*[%w_%.]*facts", allowed = { "Facts.lua" } },
	{ name = "table.remove from a facts list", pattern = "table%.remove%s*%(%s*[%w_%.]*facts", allowed = { "Facts.lua" } },
	{ name = "whole facts list assignment", pattern = "%.facts%s*=[^=]",
		-- Schema normalises loaded canon, Migrations adds the empty container,
		-- Projection builds filtered copies for display and export.
		allowed = { "Schema.lua", "Migrations.lua", "Projection.lua" } },
	{ name = "Facts.AddFromInterpretation call", pattern = "Facts%.AddFromInterpretation%s*%(",
		allowed = { "Facts.lua", "Interpretations.lua" } },
	{ name = "Facts.Add call", pattern = "Facts%.Add%s*%(", allowed = { "Facts.lua", "Actions.lua" } },
	{ name = "Facts.Restore call", pattern = "Facts%.Restore%s*%(", allowed = { "Facts.lua", "Transfer.lua" } },
}

local function violations(fileName, text)
	local found = {}
	local body = code(text)
	for _, rule in ipairs(RULES) do
		local ok = false
		for _, allowed in ipairs(rule.allowed) do
			if allowed == fileName then ok = true end
		end
		if not ok and body:find(rule.pattern) then
			found[#found + 1] = fileName .. ": " .. rule.name
		end
	end
	return found
end

return function(t, expect)
	t:describe("architecture: single entry point into canon", function()
		t:it("no Core module writes facts except through Facts.Add or Interpretations.Promote", function()
			local all = {}
			for _, rel in ipairs(Loader.CORE) do
				local fileName = rel:match("([^/]+)$")
				for _, v in ipairs(violations(fileName, read(Loader.ROOT .. rel))) do
					all[#all + 1] = v
				end
			end
			expect.equal(table.concat(all, "; "), "")
		end)

		t:it("the scanner catches planted violations", function()
			local planted = {
				"char.facts[#char.facts + 1] = { statement = 'x' }",
				"table.insert(char.facts, f)",
				"table.remove(char.facts, 1)",
				"result.facts = {}",
				"ns.Facts.AddFromInterpretation(char, v, p)",
				"Facts.Add(char, v)",
				"Facts.Restore(char, f)",
			}
			for _, line in ipairs(planted) do
				expect.truthy(#violations("Journal.lua", line) > 0, "not caught: " .. line)
			end
			expect.equal(#violations("Journal.lua", "-- char.facts[1] = x (comment)\nif a.facts[1] == b then end"), 0)
		end)

		t:it("Interpretations never calls Facts.Add directly", function()
			local text = code(read(Loader.ROOT .. "Core/Interpretations.lua"))
			expect.falsy(text:find("Facts%.Add%s*%("))
		end)
	end)
end
