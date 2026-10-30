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

		t:it("width estimates count wide (CJK) characters as full width", function()
			local _, _, ns = load()
			local wide = ns.Style.TextWidth("\228\184\173\230\150\135\229\173\151", "reading")
			local latin = ns.Style.TextWidth("abc", "reading")
			expect.truthy(wide > latin, "three CJK characters are wider than three Latin letters")
		end)

		t:it("a Chronicle card offers its full view when the client cut text the estimate thought fits", function()
			local _, _, ns = load()
			local CV = ns.ChronicleView
			local cut = { IsTruncated = function() return true end }
			local whole = { IsTruncated = function() return false end }
			expect.truthy(CV.ClientCut({ text = cut, meta = whole }, { text = {}, meta = {} }))
			expect.falsy(CV.ClientCut({ text = whole, meta = whole }, { text = {}, meta = {} }))
			expect.falsy(CV.ClientCut({ text = cut }, { text = {}, truncated = true }), "Read already shows")
			expect.falsy(CV.ClientCut({ text = {} }, { text = {} }), "no IsTruncated: no claim")
		end)

		t:it("panels and callouts carry an eyebrow title and an inner area", function()
			local _, env, ns = load()
			local panel = ns.Widgets.Panel(env.CreateFrame("Frame"), "Active goals")
			expect.equal(panel.title:GetText(), "ACTIVE GOALS")
			expect.truthy(panel.inner ~= nil)
			local callout = ns.Widgets.Callout(env.CreateFrame("Frame"), "A moment awaits")
			expect.truthy(callout.callout)
		end)

		t:it("chips follow the design system: 24 high, padded, tinted in their tone, readable on every theme", function()
			local _, env, ns = load()
			local W, Themes, Style = ns.Widgets, ns.Themes, ns.Style
			local chip = W.Chip(env.CreateFrame("Frame"), "Waiting for approval", "waiting")
			expect.equal(chip:GetHeight(), 24)
			expect.truthy(chip:GetWidth() >= Style.TextWidth("Waiting for approval", "small") + 2 * W.CHIP_PAD)
			expect.equal(chip.label.__textColor[1], Themes.STATUS_COLORS.waiting[1])
			local small = W.Chip(env.CreateFrame("Frame"), "Homeland", "accent", Style.CONTROL.chipSmall)
			expect.equal(small:GetHeight(), 20)
			for _, theme in ipairs(Themes.LIST) do
				for _, tone in ipairs({ "accent", "waiting", "muted", "danger", "public", "private", "secret" }) do
					for _, base in ipairs({ "background", "panel", "surface", "surfaceHover" }) do
						local text, fill = W.ChipTone(tone, theme, theme[base])
						local ratio = Themes.Contrast(text, fill)
						expect.truthy(ratio >= 4.5, string.format("%s %s chip on %s: %.2f:1", theme.id, tone, base, ratio))
					end
				end
			end
			-- The design system's Private chip: #B4C6EA on about #1B2436.
			local _, fill = W.ChipTone("private", Themes.Get("dawnward"), Themes.Get("dawnward").background)
			expect.truthy(math.abs(fill[3] * 255 - 0x36) < 8 and math.abs(fill[1] * 255 - 0x1B) < 8)
		end)

		t:it("a chip with a maximum width cuts its text and shows it whole on hover", function()
			local _, env, ns = load()
			local chip = ns.Widgets.Chip(env.CreateFrame("Frame"), "Short", "accent")
			chip:SetMaxWidth(80)
			expect.falsy(chip.truncated)
			chip:SetChip("A place with a very long name indeed")
			expect.equal(chip:GetWidth(), 80)
			expect.truthy(chip.truncated)
			expect.equal(chip.tooltipTitle, "A place with a very long name indeed")
			chip:SetChip("Short")
			expect.falsy(chip.truncated)
			expect.equal(chip.tooltipTitle, nil, "no tooltip once it fits")
		end)

		t:it("paints the button variants of the design system", function()
			local _, env, ns = load()
			local W, Style = ns.Widgets, ns.Style
			local theme = Style.Current()
			local tones = Style.Tones(theme)
			local parent = env.CreateFrame("Frame")
			local primary = W.Button(parent, "Save answer", 130, Style.CONTROL.standard, "primary")
			expect.equal(primary.bg.__color[1], theme.accent[1])
			expect.equal(primary.edges.top.__color[1], tones.accentBright[1], "a bright gold edge")
			expect.equal(primary.label.__textColor[1], theme.accentText[1])
			local secondary = W.Button(parent, "Edit", 80, Style.CONTROL.compact)
			expect.equal(secondary.bg.__color[1], theme.surfaceHover[1], "raised fill")
			expect.equal(secondary.edges.top.__color[1], tones.edgeStrong[1])
			local ghost = W.Button(parent, "Later", 80, Style.CONTROL.standard, "ghost")
			expect.equal(ghost.bg.__color[4], 0, "no fill")
			expect.equal(ghost.edges.top.__color[4], 1, "but a visible edge, as in the design")
			expect.equal(ghost.label.__textColor[1], tones.ghostText[1])
			local danger = W.Button(parent, "Delete", 80, Style.CONTROL.compact, "danger")
			expect.equal(danger.edges.top.__color[1], tones.dangerEdge[1])
			expect.equal(danger.label.__textColor[1], tones.dangerText[1])
			danger:Disable()
			expect.truthy(danger.edges.top.__color[4] < 1, "disabled is dimmed")
			expect.equal(danger.label.__textColor[1], theme.muted[1])
			-- Bold labels, 15 on standard buttons and 14 on compact ones.
			expect.equal(primary.fontStyle, "button")
			expect.equal(secondary.fontStyle, "buttonSmall")
			expect.equal(W.Button(parent, "An answer", 200, 26, "choice").fontStyle, "body", "answers stay regular")
		end)

		t:it("a segmented control sits on a track; only the selected item is raised", function()
			local _, env, ns = load()
			local theme = ns.Style.Current()
			local seg = ns.Widgets.Segmented(env.CreateFrame("Frame"), { { id = "a", label = "All" },
				{ id = "b", label = "Defining" } }, 200, 30, function() end)
			seg:Select("a")
			expect.truthy(seg.track ~= nil)
			expect.equal(seg.track.__color[1], theme.panel[1])
			expect.equal(seg.buttons[1].bg.__color[1], ns.Style.Tones(theme).selectedFill[1])
			expect.equal(seg.buttons[2].edges.top.__color[4], 0, "an unselected item has no edge")
			expect.equal(seg.buttons[2].bg.__color[4], 0)
		end)

		t:it("an input shows focus and errors with a 2 px ring and a dark well", function()
			local _, env, ns = load()
			local theme = ns.Style.Current()
			local tones = ns.Style.Tones(theme)
			local line = ns.Widgets.EditLine(env.CreateFrame("Frame"), 50, ns.Style.CONTROL.input)
			expect.equal(line:GetHeight(), 36)
			expect.equal(line.bg.__color[1], tones.field[1])
			expect.falsy(line.ring.top:IsShown())
			line:SetFocus()
			expect.truthy(line.ring.top:IsShown(), "a second pixel of edge")
			expect.equal(line.ring.top.__color[1], theme.accent[1])
			expect.equal(line.bg.__color[1], tones.fieldFocus[1])
			ns.Widgets.SetFieldError(line, "Not changed: a title is needed")
			expect.equal(line.ring.top.__color[1], theme.danger[1])
			expect.equal(line.__insets[1], ns.Widgets.FIELD.textInset)
		end)

		t:it("a visibility button looks like its chip and keeps cycling", function()
			local _, env, ns = load()
			local seen
			local vis = ns.Widgets.VisibilityButton(env.CreateFrame("Frame"), function(level, b)
				seen = level
				b:SetLevel(level)
			end)
			local secret = ns.Themes.VISIBILITY_COLORS.secret
			vis:SetLevel("secret")
			expect.equal(vis.label.__textColor[1], secret[1])
			local fill = ns.Widgets.ChipColors(secret, ns.Style.Current())
			expect.equal(vis.bg.__color[1], fill[1], "tinted fill")
			vis:GetScript("OnClick")(vis)
			expect.equal(seen, "private")
			expect.equal(vis:GetText(), "Private")
		end)

		t:it("draws pills with round ends where masks exist, following the frame's height", function()
			local _, env, ns = load()
			ns.Style.NewMask = function(f) return f:CreateTexture() end
			local chip = ns.Widgets.Chip(env.CreateFrame("Frame"), "Defining", "accent")
			expect.truthy(chip.pill ~= nil)
			expect.falsy(chip.bg:IsShown())
			expect.equal(chip.pill.capL:GetWidth(), 24)
			chip:SetHeight(20)
			chip:GetScript("OnSizeChanged")(chip, chip:GetWidth(), 20)
			expect.equal(chip.pill.capL:GetWidth(), 20)
			expect.equal(chip.pill.innerL:GetWidth(), 18, "1 px edge all round")
			local tone, fill, edge = ns.Widgets.ChipTone("accent", ns.Style.Current())
			expect.truthy(tone ~= nil)
			expect.equal(chip.pill.mid.__color[1], fill[1])
			expect.equal(chip.pill.capL.__color[1], edge[1])
			local vis = ns.Widgets.VisibilityButton(env.CreateFrame("Frame"), function() end)
			expect.truthy(vis.pill ~= nil)
			expect.falsy(vis.bg:IsShown())
		end)

		t:it("draws Close as a large multiplication sign in a bordered icon button", function()
			local _, env, ns = load()
			local close = ns.Widgets.IconButton(env.CreateFrame("Frame"), "X", "Close")
			expect.equal(close:GetText(), "\195\151")
			expect.equal(close.glyph, "X")
			expect.equal(close.edges.top.__color[4], 1)
			expect.equal(ns.Widgets.IconButton(env.CreateFrame("Frame"), ">", "Next"):GetText(), ">")
		end)

		t:it("keeps every derived text tone readable on every theme", function()
			local _, _, ns = load()
			for _, theme in ipairs(ns.Themes.LIST) do
				local tones = ns.Style.Tones(theme)
				for _, name in ipairs({ "heading", "reading", "label", "ghostText", "navText", "accentBright", "dangerText" }) do
					for _, surface in ipairs({ "background", "panel", "surface", "surfaceHover" }) do
						local ratio = ns.Themes.Contrast(tones[name], theme[surface])
						expect.truthy(ratio >= 4.5, string.format("%s %s on %s: %.2f:1", theme.id, name, surface, ratio))
					end
				end
				expect.truthy(ns.Themes.Contrast(tones.heading, tones.selectedFill) >= 4.5, theme.id .. " selected segment")
				expect.truthy(ns.Themes.Contrast(theme.text, tones.field) >= 4.5, theme.id .. " input text")
				expect.truthy(ns.Themes.Contrast(tones.accentBright, theme.background) >= 4.5, theme.id .. " level badge")
			end
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
