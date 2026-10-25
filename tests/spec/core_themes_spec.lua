-- L1: themes are cosmetic, complete and readable.
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Themes")
	local Themes = ns.Themes

	t:describe("themes", function()
		t:it("ships Neutral (default), Silver Hand and Arcane", function()
			expect.equal(Themes.DEFAULT, "neutral")
			local ids = {}
			for _, theme in ipairs(Themes.LIST) do ids[#ids + 1] = theme.id end
			expect.deepEqual(ids, { "neutral", "silverhand", "arcane" })
		end)

		t:it("defines every colour role for every theme", function()
			for _, theme in ipairs(Themes.LIST) do
				for _, role in ipairs({ "background", "panel", "text", "muted", "accent", "border" }) do
					local c = theme[role]
					expect.truthy(type(c) == "table" and #c == 3, theme.id .. "." .. role)
					for i = 1, 3 do
						expect.truthy(c[i] >= 0 and c[i] <= 1, theme.id .. "." .. role)
					end
				end
				expect.truthy(type(theme.name) == "string" and type(theme.description) == "string")
			end
		end)

		t:it("keeps all text at a contrast of at least 4.5:1 on both surfaces", function()
			for _, theme in ipairs(Themes.LIST) do
				for _, surface in ipairs({ "background", "panel" }) do
					for _, role in ipairs({ "text", "muted", "accent" }) do
						local ratio = Themes.Contrast(theme[role], theme[surface])
						expect.truthy(ratio >= 4.5,
							string.format("%s %s on %s is %.2f:1", theme.id, role, surface, ratio))
					end
				end
			end
		end)

		t:it("keeps visibility labels readable on every theme", function()
			for _, theme in ipairs(Themes.LIST) do
				for level, color in pairs(Themes.VISIBILITY_COLORS) do
					for _, surface in ipairs({ "background", "panel" }) do
						local ratio = Themes.Contrast(color, theme[surface])
						expect.truthy(ratio >= 4.5, string.format("%s %s on %s is %.2f:1", theme.id, level, surface, ratio))
					end
				end
			end
		end)

		t:it("computes WCAG contrast correctly", function()
			expect.truthy(math.abs(Themes.Contrast({ 1, 1, 1 }, { 0, 0, 0 }) - 21) < 1e-9)
			expect.truthy(math.abs(Themes.Contrast({ 0.5, 0.5, 0.5 }, { 0.5, 0.5, 0.5 }) - 1) < 1e-9)
		end)

		t:it("falls back to Neutral for unknown IDs", function()
			expect.equal(Themes.Get("paladin").id, "neutral")
			expect.equal(Themes.Get(nil).id, "neutral")
			expect.falsy(Themes.IsValid("paladin"))
		end)

		t:it("contains no class or race mapping", function()
			for key in pairs(Themes) do
				expect.falsy(tostring(key):lower():find("class") or tostring(key):lower():find("race"),
					"themes must not be chosen from class or race: " .. tostring(key))
			end
		end)
	end)
end
