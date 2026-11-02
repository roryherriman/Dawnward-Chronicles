-- L2 (v0.10): Character Edit buttons are drawn as the mockup's pencil (a line
-- icon, the word in the tooltip); the same pooled button shows plain text
-- for every other use ("+ Add", "Read full story").
local Boot = require("support.boot")

return function(t, expect)
	t:describe("character profile: pencil Edit buttons (L2)", function()
		t:it("draws Edit as a pencil and other labels as text, on the same reused button", function()
			local mock, _, ns = Boot.Start()
			mock.Slash("set name Aelin")
			ns.MainWindow.Show(true)
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			local pencils, adds = 0, 0
			for _, row in ipairs(section.rows) do
				if row:IsShown() and row.edit and row.edit:IsShown() then
					if row.edit:GetText() == "Edit" then
						pencils = pencils + 1
						expect.truthy(row.edit.icon and row.edit.icon.name == "edit", "a pencil")
						expect.equal(row.edit.label:GetText(), "", "no word beside the pencil")
						expect.truthy((row.edit.tooltipTitle or "") ~= "", "the pencil explains itself on hover")
					elseif row.edit:GetText() == ns.CharacterView.ADD_LABEL then
						adds = adds + 1
						expect.falsy(row.edit.icon, "an Add shows its words, no pencil")
					end
				end
			end
			expect.truthy(pencils >= 1, "the name tile has a pencil")
			expect.truthy(adds >= 1, "an empty field shows + Add")
		end)
	end)
end
