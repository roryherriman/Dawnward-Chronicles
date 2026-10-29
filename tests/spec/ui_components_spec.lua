-- L2: the v0.7 shared components (chips, panels, callouts, date blocks,
-- progress bars, search boxes) against the WoW mock.
local Boot = require("support.boot")

return function(t, expect)
	local function load()
		local mock, env, ns = Boot.Start()
		return mock, env, ns
	end

	t:describe("v0.7 components", function()
		t:it("a chip shows its text in its tone and sizes itself", function()
			local _, env, ns = load()
			local parent = env.CreateFrame("Frame")
			local chip = ns.Widgets.Chip(parent, "Defining", "accent")
			expect.equal(chip.label:GetText(), "Defining")
			expect.truthy(chip:GetWidth() > 18)
			chip:SetChip("Secret", "secret")
			expect.equal(chip.tone, "secret")
			local r = chip.label.__textColor or { chip.label:GetTextColor() }
			expect.truthy(r ~= nil)
		end)

		t:it("a date block shows day and month, or ? when unknown", function()
			local _, env, ns = load()
			local block = ns.Widgets.DateBlock(env.CreateFrame("Frame"))
			block:SetDate(1761609600) -- 28 Oct 2025 00:00 UTC
			expect.equal(block.day:GetText(), "28")
			expect.equal(block.month:GetText(), "OCT")
			block:SetDate(0)
			expect.equal(block.day:GetText(), "?")
		end)

		t:it("a progress bar clamps its value", function()
			local _, env, ns = load()
			local bar = ns.Widgets.ProgressBar(env.CreateFrame("Frame"), 200, 4)
			bar:SetValue(0.5)
			expect.equal(bar.value, 0.5)
			bar:SetValue(3)
			expect.equal(bar.value, 1)
			bar:SetValue(nil)
			expect.equal(bar.value, 0)
			expect.falsy(bar.fill:IsShown())
		end)

		t:it("a search box reports trimmed text and hides its placeholder", function()
			local _, env, ns = load()
			local seen
			local box = ns.Widgets.SearchBox(env.CreateFrame("Frame"), 200, "Search the journal", function(text) seen = text end)
			box:SetText("  lantern ")
			box:GetScript("OnTextChanged")(box)
			expect.equal(seen, "lantern")
			expect.falsy(box.placeholder:IsShown())
			box:SetText("")
			box:GetScript("OnTextChanged")(box)
			expect.equal(seen, "")
			expect.truthy(box.placeholder:IsShown())
		end)

		t:it("panels and callouts carry an eyebrow title and an inner area", function()
			local _, env, ns = load()
			local panel = ns.Widgets.Panel(env.CreateFrame("Frame"), "Active goals")
			expect.equal(panel.title:GetText(), "ACTIVE GOALS")
			expect.truthy(panel.inner ~= nil)
			local callout = ns.Widgets.Callout(env.CreateFrame("Frame"), "A moment awaits")
			expect.truthy(callout.callout)
		end)

		t:it("a tooltip on a plain frame turns its mouse input on, so the tooltip can show", function()
			local _, env, ns = load()
			local area = env.CreateFrame("Frame")
			expect.falsy(area:IsMouseEnabled())
			ns.Widgets.Tooltip(area, "Title", "Text")
			expect.truthy(area:IsMouseEnabled())
		end)
	end)
end
