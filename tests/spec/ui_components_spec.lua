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

		t:it("has no visibility chip widget any more (v0.10); fixed-colour chip tones stay", function()
			local _, env, ns = load()
			expect.equal(ns.Widgets.VisibilityButton, nil)
			expect.equal(ns.Widgets.VISIBILITY_HELP, nil)
			-- The Total RP 3 page still paints its "Connected" chip in the fixed green.
			local chip = ns.Widgets.Chip(env.CreateFrame("Frame"), "Connected", "public")
			local green = ns.Themes.VISIBILITY_COLORS.public
			expect.equal(chip.label.__textColor[1], green[1])
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

	t:describe("v0.10 components (design-system.png, Main.dc.html)", function()
		t:it("stores a tooltip on a font string or texture without hooking it (no mouse scripts there)", function()
			local _, env, ns = load()
			local parent = env.CreateFrame("Frame")
			local fs = parent:CreateFontString(nil, "OVERLAY")
			local tex = parent:CreateTexture(nil, "ARTWORK")
			for _, region in ipairs({ fs, tex }) do
				local hooked = false
				region.HookScript = function() hooked = true end
				region.SetScript = function() hooked = true end
				expect.falsy(ns.Widgets.CanHaveTooltip(region))
				ns.Widgets.Tooltip(region, "Title", "Text")
				expect.equal(region.tooltipTitle, "Title", "the text is kept for the caller")
				expect.falsy(hooked, "no script is set or hooked on a " .. region:GetObjectType())
				expect.falsy(region.tooltipHooked)
			end
			expect.falsy(ns.Widgets.CanHaveTooltip(nil))
			local frame = env.CreateFrame("Frame")
			expect.truthy(ns.Widgets.CanHaveTooltip(frame))
			ns.Widgets.Tooltip(frame, "Title")
			expect.truthy(frame:GetScript("OnEnter") ~= nil, "frames still get their tooltip")
		end)

		t:it("draws line icons from the design's strokes, inside their box, recoloured by the theme", function()
			local _, env, ns = load()
			local S = ns.Style
			local parent = env.CreateFrame("Frame")
			for name in pairs(S.ICONS) do
				local icon = S.LineIcon(parent, name, 20)
				expect.truthy(icon ~= nil, name)
				expect.truthy(#icon.lines > 0, name .. " has strokes")
				for _, line in ipairs(icon.lines) do
					for _, p in ipairs({ line.__start, line.__end }) do
						expect.equal(p[1], "TOPLEFT")
						expect.truthy(p[3] >= -0.01 and p[3] <= 20.01 and -p[4] >= -0.01 and -p[4] <= 20.01,
							name .. " stays inside its 20 px box")
					end
					expect.truthy(line.__thickness >= 1, "strokes at least 1 px")
				end
				icon:SetColor({ 1, 0, 0 })
				expect.deepEqual(icon.lines[1].__color, { 1, 0, 0, 1 })
			end
			expect.equal(S.LineIcon(parent, "no such icon", 20), nil)
			-- A client without line regions: nil, so callers keep their text.
			local bare = env.CreateFrame("Frame")
			local createFrame = env.CreateFrame
			env.CreateFrame = function(...)
				local f = createFrame(...)
				f.CreateLine = false
				return f
			end
			expect.equal(S.LineIcon(bare, "close", 18), nil)
			local b = ns.Widgets.Button(bare, "New entry", 120, 36, "primary")
			expect.falsy(b:SetIcon("plus"), "SetIcon reports that no icon is drawn")
			env.CreateFrame = createFrame
		end)

		t:it("centres a button's icon and label together and colours the icon with the label", function()
			local _, env, ns = load()
			local W, S = ns.Widgets, ns.Style
			local b = W.Button(env.CreateFrame("Frame"), "Edit", W.ButtonWidth("Edit", 30, true), 30)
			expect.truthy(b:SetIcon("edit"))
			expect.equal(b.icon.size, W.BUTTON_ICON.compact)
			local text = S.TextWidth("Edit", "buttonSmall")
			local group = W.BUTTON_ICON.compact + W.BUTTON_ICON.gap + text
			local p = b.icon.__points[#b.icon.__points]
			expect.equal(p[3], "CENTER")
			expect.equal(p[4], math.floor(-group / 2 + 0.5), "the group is centred on the button")
			expect.equal(b.label.__points[1][2], W.BUTTON.inset + W.BUTTON_ICON.compact + W.BUTTON_ICON.gap)
			expect.deepEqual(b.icon.lines[1].__color, { b.label.__textColor[1], b.label.__textColor[2],
				b.label.__textColor[3], 1 })
			expect.truthy(W.LabelFits("Edit", b:GetWidth(), 30, nil, true))
			expect.equal(W.ButtonWidth("Edit", 30, true), math.ceil(group + 24), "12 px padding on compact buttons")
			expect.equal(W.ButtonWidth("New entry", 36, true), math.ceil(S.TextWidth("New entry", "button") + 16 + 8
				+ 32), "16 px padding and a 16 px icon on standard buttons")
			-- The close button: the design's line X, the glyph kept as its text.
			local close = W.IconButton(env.CreateFrame("Frame"), "X", "Close")
			expect.equal(close.icon.name, "close")
			expect.falsy(close.label:IsShown())
			close:SetSize(36, 36)
			expect.equal(close.icon.__scale, 1)
		end)

		t:it("sets eyebrows in tracked capitals that keep the text and fit their box", function()
			local _, env, ns = load()
			local W, S = ns.Widgets, ns.Style
			local label = W.TrackedLabel(env.CreateFrame("Frame"), "eyebrow", "eyebrow")
			label:SetText("ACTIVE GOALS")
			expect.equal(label:GetText(), "ACTIVE GOALS")
			local plain = S.TextWidth("ACTIVE GOALS", "eyebrow")
			local tracked = plain + 11 * W.TRACKING * S.FONT_BY_STYLE.eyebrow.size
			expect.truthy(math.abs(label:GetStringWidth() - tracked) < 0.01, "0.16 em between letters")
			-- Each letter after the first starts its advance plus the tracking further on.
			local a, b = label.letters[1].__points[1][4], label.letters[2].__points[1][4]
			expect.truthy(math.abs(b - a - S.TextWidth("A", "eyebrow") - W.TRACKING * 13) < 0.01)
			-- A narrow box tightens the tracking rather than cutting letters.
			label:SetWidth(plain + 4)
			expect.truthy(label:GetStringWidth() <= plain + 4.01)
			expect.falsy(label:IsTruncated())
			-- Centred in its box (date months).
			label:SetWidth(200)
			label:SetJustifyH("CENTER")
			expect.truthy(math.abs(label.letters[1].__points[1][4] - math.floor((200 - label:GetStringWidth()) / 2))
				< 0.01)
			-- Colour follows the theme role.
			ns.Style.Apply(ns.Themes.Get("shadowbound"))
			expect.equal(label.letters[1].__textColor[1], S.Tones(ns.Themes.Get("shadowbound")).eyebrowText[1])
			for _, theme in ipairs(ns.Themes.LIST) do
				expect.truthy(ns.Themes.Contrast(S.Tones(theme).eyebrowText, theme.surfaceHover) >= 4.5,
					theme.id .. " eyebrows readable")
			end
			expect.deepEqual(S.Tones(ns.Themes.Get("dawnward")).eyebrowText, ns.Themes.Get("dawnward").ornament,
				"unchanged where already readable")
			-- Shorter text hides the letters it no longer uses.
			label:SetText("AB")
			expect.falsy(label.letters[3]:IsShown())
			-- Panels and callouts use it for their titles.
			local panel = W.Panel(env.CreateFrame("Frame"), "Recent places", { padX = 16 })
			expect.equal(panel.title:GetText(), "RECENT PLACES")
			expect.equal(panel.title.__points[1][2], 16, "the title follows the side padding")
			expect.equal(panel.inner.__points[1][2], 16)
		end)

		t:it("sizes segmented items to their words on a framed, padded track", function()
			local _, env, ns = load()
			local W = ns.Widgets
			local items = { { id = "all", label = "All" }, { id = "defining", label = "Defining" } }
			local seg = W.Segmented(env.CreateFrame("Frame"), items, 200, 30, function() end, { fit = true, framed = true })
			local widths = W.SegmentWidths(items, 30, true)
			expect.equal(seg.buttons[1]:GetWidth(), widths[1])
			expect.truthy(widths[1] < widths[2])
			expect.equal(seg.width, widths[1] + widths[2] + W.SEGMENT.gap + 2 * (W.SEGMENT.pad + 1))
			expect.equal(seg.height, 30 + 2 * (W.SEGMENT.pad + 1))
			expect.equal(seg.buttons[1]:GetParent(), seg.frame)
			for i, item in ipairs(items) do
				expect.truthy(W.LabelFits(item.label, seg.buttons[i]:GetWidth(), 30, "segment"))
			end
			-- Without options: the v0.9 equal widths (other screens rely on them).
			local old = W.Segmented(env.CreateFrame("Frame"), items, 200, 30, function() end)
			expect.equal(old.buttons[1]:GetWidth(), 98)
			expect.equal(old.frame, nil)
		end)

		t:it("gives chips an optional icon, cards a featured state and progress bars round ends", function()
			local _, env, ns = load()
			local W, S = ns.Widgets, ns.Style
			local chip = W.Chip(env.CreateFrame("Frame"), "Goldshire", "accent")
			local before = chip:GetWidth()
			expect.truthy(chip:SetIcon("home"))
			expect.equal(chip:GetWidth(), before + W.CHIP_ICON + W.CHIP_ICON_GAP)
			expect.equal(chip.label.__template, S.FontFor("chip"), "chip text: Alegreya Sans Medium 13")
			local theme = S.Current()
			local color, fill, edge = W.ChipTone("accent", theme)
			expect.deepEqual(fill, S.Tones(theme).accentWell, "gold chips on the design's dark gold")
			expect.deepEqual(edge, theme.border)
			expect.truthy(ns.Themes.Contrast(color, fill) >= 4.5)
			local card = W.Card(env.CreateFrame("Frame"))
			card:SetFeatured(true)
			expect.equal(card.bg.__color[1], S.Tones(theme).cardHover[1], "featured: the lifted fill")
			expect.equal(card.edges.top.__color[1], S.Tones(theme).selectedEdge[1])
			card:SetRowHover(true)
			expect.equal(card.edges.top.__color[1], theme.border[1], "hovered featured: the gold edge")
			-- Round ends where the client has masks (stubbed as in ui_shell_spec).
			S.NewMask = function(f) return f:CreateTexture() end
			local bar = W.ProgressBar(env.CreateFrame("Frame"), 200, 6)
			expect.truthy(bar.trackPill ~= nil and bar.fillPill ~= nil)
			bar:SetValue(0.5)
			expect.equal(bar.fillFrame:GetWidth(), 100)
			bar:SetValue(0.01)
			expect.equal(bar.fillFrame:GetWidth(), 6, "never narrower than its round ends")
			bar:SetValue(0)
			expect.falsy(bar.fillFrame:IsShown())
		end)

		t:it("puts the magnifier in the search box and the placeholder in the input size", function()
			local _, env, ns = load()
			local W = ns.Widgets
			local box = W.SearchBox(env.CreateFrame("Frame"), 230, "Search the journal", nil, 36)
			expect.equal(box.icon.name, "search")
			expect.equal(box.__insets[1], W.SEARCH.textLeft, "text starts after the icon")
			expect.equal(box.placeholder.__points[1][2], W.SEARCH.textLeft)
			expect.equal(box.placeholder.__template, ns.Style.FontFor("placeholder"))
			expect.equal(ns.Style.FONT_BY_STYLE.placeholder.size, 15)
		end)

		t:it("keeps gold, edges and fills close to the design's values (Classic Dawnward)", function()
			local _, _, ns = load()
			local S = ns.Style
			local tones = S.Tones(ns.Themes.Get("dawnward"))
			local function near(c, hex, tol)
				for i = 1, 3 do
					local v = tonumber(hex:sub(2 * i - 1, 2 * i), 16) / 255
					if math.abs(c[i] - v) > (tol or 6) / 255 then return false end
				end
				return true
			end
			expect.truthy(near(tones.accentBright, "F0D08E"), "bright gold, not greyed")
			expect.truthy(near(tones.edgeStrong, "3E4C66"))
			expect.truthy(near(tones.selectedEdge, "4A5874"))
			expect.truthy(near(tones.selectedFill, "2A3346"))
			expect.truthy(near(tones.fieldEdge, "33405A"))
			expect.truthy(near(tones.dot, "6E7891"))
			expect.truthy(near(tones.calloutFill, "1A1A17"))
			expect.truthy(near(tones.accentWell, "2A2213"))
		end)
	end)
end
