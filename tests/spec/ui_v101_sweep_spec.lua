-- L2 (v0.10.1): whole-window sweeps. Every screen of the main window (every
-- section, Chronicle tab and New form, the Character readers and Showcase,
-- every Settings page, every Guide topic), the reaction card, a
-- confirmation dialog, the story import window and every setup page, with a
-- character that has every kind of record, and with a brand-new character
-- (every empty state). Mocked client: not in-game evidence.
--
--   Text size: no visible text under Style.MIN_TEXT (13).
--   Themes: switching to a theme with every screen built paints every
--     visible texture, line and font string exactly as a window that was
--     built in that theme from the start (no stale colour), and no switch
--     raises an error.
--   Scale: at window scale 0.7 and 1.4 every visible region keeps the same
--     anchors and size in layout units as at 1 (nothing re-flows, clips or
--     overlaps differently; the client scales the whole window).
local Sweep = require("support.sweep")

local THEMES = { "dawnward", "lightbound", "shadowbound" }

local function same(a, b)
	if a == nil or b == nil then return a == b end
	for i = 1, math.max(#a, #b) do
		if math.abs((a[i] or 1) - (b[i] or 1)) > 1e-6 then return false end
	end
	return true
end

-- Every visible region's anchors and size, by creation index.
local function geometry(mock)
	local out = {}
	for i, f in ipairs(mock.allFrames) do
		if f.__kind ~= "Font" and f.IsVisible and f:IsVisible() then
			local points = {}
			for _, p in ipairs(f.__points or {}) do
				local copy = {}
				for k, v in ipairs(p) do copy[k] = type(v) == "table" and tostring(v.__kind) or v end
				points[#points + 1] = table.concat(copy, ",")
			end
			out[i] = table.concat(points, ";") .. "|" .. tostring(f.__width) .. "x" .. tostring(f.__height)
		end
	end
	return out
end

return function(t, expect)
	t:describe("whole-window sweeps (v0.10.1, L2)", function()
		t:it("keeps every visible text at 13 or larger, with records and when empty", function()
			for _, start in ipairs({ Sweep.Sample, Sweep.Empty }) do
				local mock, _, ns = start()
				local small, screens = {}, 0
				Sweep.Walk(ns, function(name)
					screens = screens + 1
					for _, fs in ipairs(Sweep.VisibleText(mock)) do
						local size, why = Sweep.TextSize(ns, fs)
						if not size or size < ns.Style.MIN_TEXT then
							small[#small + 1] = name .. ": " .. tostring(size or why) .. " " .. fs.__text:sub(1, 40)
						end
					end
				end)
				expect.truthy(screens >= 30, "the walk visits every screen (" .. screens .. ")")
				expect.equal(#small, 0, table.concat(small, " | "))
			end
		end)

		t:it("never clips a button label or a one-line label of fixed width (estimated from the fonts)", function()
			for _, start in ipairs({ Sweep.Sample, Sweep.Empty }) do
				local mock, _, ns = start()
				local byName = Sweep.FontByName(ns)
				local clipped, buttons, labels = {}, 0, 0
				Sweep.Walk(ns, function(name)
					for _, f in ipairs(mock.allFrames) do
						if f:IsVisible() then
							local text = f.__text
							if f.__kind == "Button" and f.label and f.variant and f.variant ~= "choice"
								and f.label:IsShown() and type(text) == "string" and text ~= "" then
								buttons = buttons + 1
								local icon = f.icon and f.icon.size and true or false
								if not ns.Widgets.LabelFits(text, f:GetWidth(), f:GetHeight(), f.variant, icon) then
									clipped[#clipped + 1] = name .. ": button " .. text
								end
							elseif f.__kind == "FontString" and f.__wordWrap == false and (f.__width or 0) > 0
								and type(text) == "string" and text ~= "" then
								local obj = f.__fontObject
								local spec = byName[obj and obj.__name or f.__template]
								if spec then
									labels = labels + 1
									local size = Sweep.TextSize(ns, f)
									if ns.Style.TextWidth(text, spec.style) * size / spec.size > f.__width + 0.5 then
										clipped[#clipped + 1] = name .. ": label " .. text
									end
								end
							end
						end
					end
				end)
				expect.truthy(buttons > 300 and labels > 150, buttons .. " buttons, " .. labels .. " labels checked")
				expect.equal(#clipped, 0, table.concat(clipped, " | ", 1, math.min(#clipped, 20)))
			end
		end)

		for _, theme in ipairs(THEMES) do
			t:it("switching to " .. theme .. " with every screen built repaints everything (no stale colour)", function()
				local start = theme == "dawnward" and "shadowbound" or "dawnward"
				-- A: built in the theme from the start. B: built in another
				-- theme, every screen opened, then switched.
				local mA, _, nsA = Sweep.Sample({ theme = theme })
				local mB, _, nsB = Sweep.Sample({ theme = start })
				Sweep.Walk(nsA, function() end)
				Sweep.Walk(nsB, function() end)
				local ok, err = pcall(function()
					nsB.Actions.SetTheme(nsB.ctx, theme)
					nsB.MainWindow.Refresh()
				end)
				expect.truthy(ok, tostring(err))
				expect.equal(nsB.Style.Current().id, theme)
				local snaps = {}
				Sweep.Walk(nsA, function() snaps[#snaps + 1] = Sweep.Colours(mA) end)
				local i, stale, compared = 0, {}, 0
				Sweep.Walk(nsB, function(name)
					i = i + 1
					local b = Sweep.Colours(mB)
					for k, ra in pairs(snaps[i]) do
						local rb = b[k]
						if rb then
							compared = compared + 1
							if not (same(ra.color, rb.color) and same(ra.vertex, rb.vertex) and same(ra.text, rb.text)) then
								stale[#stale + 1] = name .. " #" .. k .. " " .. ra.kind .. " " .. tostring(ra.label)
							end
						end
					end
				end)
				expect.equal(#mA.allFrames, #mB.allFrames, "both windows hold the same regions")
				expect.truthy(compared > 10000, "compared " .. compared .. " visible regions")
				expect.equal(#stale, 0, table.concat(stale, " | ", 1, math.min(#stale, 20)))
			end)
		end

		t:it("cycles through every theme on every screen without an error", function()
			local _, _, ns = Sweep.Sample()
			Sweep.Walk(ns, function(name)
				for _, theme in ipairs(THEMES) do
					local ok, err = pcall(function()
						ns.Actions.SetTheme(ns.ctx, theme)
						ns.MainWindow.Refresh()
					end)
					expect.truthy(ok, name .. " / " .. theme .. ": " .. tostring(err))
				end
			end)
		end)

		t:it("keeps every screen's layout identical at window scale 0.7 and 1.4", function()
			for _, start in ipairs({ Sweep.Sample, Sweep.Empty }) do
				local mock, _, ns = start()
				local frame = ns.MainWindow.GetFrame()
				local differ = {}
				Sweep.Walk(ns, function(name)
					frame:SetScale(1)
					ns.MainWindow.Refresh()
					local base = geometry(mock)
					for _, scale in ipairs({ 0.7, 1.4 }) do
						frame:SetScale(scale)
						ns.MainWindow.Refresh()
						local now = geometry(mock)
						for k, g in pairs(base) do
							if now[k] ~= g then differ[#differ + 1] = name .. " @" .. scale .. " #" .. k end
						end
					end
					frame:SetScale(1)
				end, { noWizard = true })
				expect.equal(#differ, 0, table.concat(differ, " | ", 1, math.min(#differ, 20)))
			end
		end)
	end)
end
