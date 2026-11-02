-- Settings -> Total RP 3 -> Biography: how the About page is laid out
-- (v0.10.1). A self-contained panel the Total RP 3 page embeds in its
-- section card: ns.TRP3BiographyPanel.Build(parent, width, height) returns
-- a frame with :Refresh(view), where view is TRP3Commands.Overview(deps)
-- (only view.checks.about.section.TE, the About's current template, is
-- read from it; the rest comes from the character, read only).
--
-- Left: the choices, saved per character (char.story.prefs, through
-- Actions.SetStoryPref and TRP3Commands.SetAboutSection, i.e.
-- Actions.WithCharacter: read-only data is refused, and an opted-in sync
-- catches up through every guard):
--   Template   Keep (Total RP 3's own) · Text · Frames · Sections
--   Style      Neutral · Silver Hand · Arcane
--   Headings   the heading colour: the style's own or a chosen accent
--   Sections   in their order: shown or hidden, the title (editable),
--              Up / Down, and in the Frames template the frame's icon and
--              background (verified ones only, from a small picker)
-- Right: the live preview, drawn as Total RP 3 draws the About page
-- (TRP3Presentation.Display): headings white (RegisterAbout.lua
-- setupHTMLFonts), paragraphs in Total RP 3's own gold unless the text
-- carries a colour, frames with their icon and tiled background, template
-- 3's three titled parts. Nothing here writes to Total RP 3.
local _, ns = ...
local Widgets, Style = ns.Widgets, ns.Style

local Panel = {}
ns.TRP3BiographyPanel = Panel

Panel.GAP = 16          -- between the two columns
Panel.LEFT_MIN, Panel.LEFT_MAX = 300, 380
Panel.ROW = 30          -- a section row (Style.CONTROL.compact)
Panel.ROW_GAP = 6
Panel.EYEBROW = 18
Panel.BLOCK_GAP = 12
Panel.SWATCH = 24
Panel.PICK = 36         -- an icon in the picker
Panel.SCROLL_BAR = 10   -- room kept for a slim scroll bar

Panel.TEMPLATES = { { id = "current", label = "Keep" }, { id = "text", label = "Text" },
	{ id = "frames", label = "Frames" }, { id = "sections", label = "Sections" } }
Panel.STYLES = { { id = "neutral", label = "Neutral" }, { id = "silverhand", label = "Silver Hand" },
	{ id = "arcane", label = "Arcane" } }
Panel.HELP = {
	template = "Keep: the template your About page already uses. Text: one page. Frames: one framed section each. "
		.. "Sections: Total RP 3's physical, personality and history parts.",
	style = "Neutral: ivory text, plain headings. Silver Hand: parchment text, gold headings, marble frames. Arcane: "
		.. "cool ivory text, violet headings with section icons. Frames you restyled in Total RP 3 keep your icon "
		.. "and background.",
	empty = {
		overview = "Write a summary on the Character page to show it here.",
		biography = "Import your story to show it here.",
		appearance = "Describe the appearance on the Character page to show it here.",
		personality = "Dawnward has no personality description of its own yet, so this section stays hidden. Total "
			.. "RP 3's personality text is yours to write.",
		motivation = "Write a motivation on the Character page to show it here.",
		developments = "Defining moments the story does not already tell appear here: approve a journal entry and "
			.. "mark it as a defining moment.",
	},
}

-- Total RP 3's own colours in the About page (RegisterAbout.lua lines 67-75:
-- headings set to white; paragraphs keep the font's normal gold).
Panel.TRP3_HEADING = { 1, 1, 1 }
Panel.TRP3_PARAGRAPH = { 1, 0.82, 0 }
Panel.RENDER_STYLE = { h1 = "railName", h2 = "title", h3 = "label", p = "meta" }
Panel.RENDER_LINE = { h1 = 26, h2 = 22, h3 = 18, p = 17 }
Panel.RENDER_GAP = 6
Panel.RENDER_ICON = 32
Panel.RENDER_PAD = 10

local function hexColor(hex)
	hex = tostring(hex or "ffffff")
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end
Panel.HexColor = hexColor

local function realChar()
	local ctx = ns.ctx
	return ctx and ctx.store and ctx.store.real.characters[ctx.characterKey] or nil
end

local function say(message)
	if message and ns.MainWindow and ns.MainWindow.SetStatus then ns.MainWindow.SetStatus(message) end
end

--- The preview ------------------------------------------------------------------

local function textHeight(fs, text, kind, width)
	local h = fs.GetStringHeight and fs:GetStringHeight() or 0
	if h and h > 0 then return h end
	local plainText = text:gsub("|T.-|t", "WW"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local lines = 0
	for line in (plainText .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + math.max(1, math.ceil(Style.TextWidth(line, Panel.RENDER_STYLE[kind]) / width))
	end
	return lines * Panel.RENDER_LINE[kind]
end

local function newRenderer(parent, width, height)
	local r = { pools = { h1 = {}, h2 = {}, h3 = {}, p = {} }, frames = {}, order = {} }
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("TRP3BioPreview"), parent, "UIPanelScrollFrameTemplate")
	scroll:SetSize(width - Panel.SCROLL_BAR, height)
	r.scroll, r.width = scroll, width - Panel.SCROLL_BAR
	r.child = CreateFrame("Frame", nil, scroll)
	r.child:SetSize(r.width, 1)
	scroll:SetScrollChild(r.child)
	r.bar = Widgets.SlimScrollBar(scroll, 4)
	Widgets.WheelScroll(scroll)
	r.top = CreateFrame("Frame", nil, r.child)
	r.top:SetAllPoints(r.child)
	if r.top.SetFrameLevel and r.child.GetFrameLevel then
		r.top:SetFrameLevel((r.child:GetFrameLevel() or 0) + 3)
	end
	return r
end

local function acquireText(r, kind)
	r.used[kind] = r.used[kind] + 1
	local fs = r.pools[kind][r.used[kind]]
	if not fs then
		fs = Widgets.Label(r.top, Panel.RENDER_STYLE[kind], true, nil)
		r.pools[kind][r.used[kind]] = fs
	end
	local c = kind == "p" and Panel.TRP3_PARAGRAPH or Panel.TRP3_HEADING
	fs:SetTextColor(c[1], c[2], c[3])
	fs:SetJustifyH("LEFT")
	fs:Show()
	return fs
end

local function acquireFrame(r)
	r.usedFrames = r.usedFrames + 1
	local f = r.frames[r.usedFrames]
	if not f then
		f = CreateFrame("Frame", nil, r.child)
		if f.SetFrameLevel and r.child.GetFrameLevel then f:SetFrameLevel((r.child:GetFrameLevel() or 0) + 1) end
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetAllPoints(f)
		f.edges = Style.Edge(f, "BORDER")
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetSize(Panel.RENDER_ICON, Panel.RENDER_ICON)
		Style.Register(f, function(frame, theme) frame.edges:Paint(theme.edge, 1) end)
		r.frames[r.usedFrames] = f
	end
	f:Show()
	return f
end

--- Draws TRP3Presentation.Display blocks; returns the height drawn.
function Panel.Render(r, blocks)
	for _, pool in pairs(r.pools) do
		for _, fs in ipairs(pool) do fs:Hide() end
	end
	for _, f in ipairs(r.frames) do f:Hide() end
	r.used = { h1 = 0, h2 = 0, h3 = 0, p = 0 }
	r.usedFrames = 0
	r.order = {}
	local y, W, gap = 0, r.width, Panel.RENDER_GAP
	local function items(list, x, width)
		for _, item in ipairs(list) do
			local fs = acquireText(r, item.kind)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", r.top, "TOPLEFT", x, -y)
			fs:SetWidth(width)
			fs:SetText(item.text)
			r.order[#r.order + 1] = fs
			y = y + textHeight(fs, item.text, item.kind, width) + gap
		end
	end
	local P = Panel.RENDER_PAD
	for i, block in ipairs(blocks) do
		if block.kind == "frame" or block.kind == "part" then
			local f = acquireFrame(r)
			local top = y
			local bk = ns.TRP3Presentation.BACKGROUNDS[block.background or 1] or ns.TRP3Presentation.BACKGROUNDS[1]
			f.bg:SetTexture(bk.file, "REPEAT", "REPEAT")
			if f.bg.SetHorizTile then f.bg:SetHorizTile(true); f.bg:SetVertTile(true) end
			f.icon:ClearAllPoints()
			f.icon:SetTexture("Interface\\ICONS\\" .. tostring(block.icon or "inv_misc_questionmark"))
			y = y + P
			if block.kind == "part" then
				local title = acquireText(r, "h2")
				title:ClearAllPoints()
				title:SetPoint("TOPLEFT", r.top, "TOPLEFT", P, -y)
				title:SetWidth(W - 2 * P)
				local icon = "|TInterface\\ICONS\\" .. block.icon .. ":18|t"
				title:SetText(icon .. "  " .. block.title .. "  " .. icon)
				title:SetJustifyH("CENTER")
				r.order[#r.order + 1] = title
				y = y + Panel.RENDER_LINE.h2 + gap
				f.icon:Hide()
				items(block.items, P, W - 2 * P)
			else
				-- TRP3 alternates the icon left and right (showTemplate2).
				f.icon:Show()
				local left = (i % 2) == 1
				local textW = W - 3 * P - Panel.RENDER_ICON
				f.icon:SetPoint(left and "LEFT" or "RIGHT", f, left and "LEFT" or "RIGHT", left and P or -P, 0)
				items(block.items, left and (2 * P + Panel.RENDER_ICON) or P, textW)
			end
			y = math.max(y - gap + P, top + Panel.RENDER_ICON + 2 * P)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", r.child, "TOPLEFT", 0, -top)
			f:SetSize(W, y - top)
			y = y + 10
		else
			items(block.items, 0, W)
		end
	end
	r.child:SetHeight(math.max(1, y))
	r.height = y
	if r.bar and r.bar.UpdateThumb then r.bar.UpdateThumb() end
	return y
end

--- Building ---------------------------------------------------------------------

local function eyebrow(parent, text, width)
	local label = Widgets.TrackedLabel(parent, "eyebrow", "eyebrow")
	label:SetWidth(width)
	label:SetText(text)
	return label
end

-- A colour swatch button (the heading colour choices).
local function swatch(parent, accent, onPick)
	local b = Widgets.Button(parent, "", Panel.SWATCH, Panel.SWATCH, "segment")
	b.accentId = accent.id
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT", 5, -5)
	b.fill:SetPoint("BOTTOMRIGHT", -5, 5)
	b:SetScript("OnClick", function() onPick(accent.id) end)
	Widgets.Tooltip(b, "Headings: " .. accent.label, accent.hex and "Section and chapter titles in this colour."
		or "Section titles in the style's own colour.")
	return b
end

-- The icon and background picker: one small pooled popup.
local function buildPicker(panel)
	local pick = CreateFrame("Frame", nil, panel)
	pick:SetFrameStrata("DIALOG")
	pick.bg = Style.Solid(pick, "BACKGROUND")
	pick.bg:SetAllPoints(pick)
	pick.edges = Style.Edge(pick, "BORDER")
	Style.Register(pick, function(p, theme)
		Style.Color(p.bg, theme.panel)
		p.edges:Paint(Style.Tones(theme).selectedEdge, 1)
	end)
	pick.buttons = {}
	pick:Hide()
	function pick.Open(_, anchor, choices, current, onChoose)
		local size, pad = Panel.PICK, 6
		for i, choice in ipairs(choices) do
			local b = pick.buttons[i]
			if not b then
				b = Widgets.Button(pick, "", size, size, "segment")
				b.image = b:CreateTexture(nil, "ARTWORK")
				b.image:SetPoint("TOPLEFT", 3, -3)
				b.image:SetPoint("BOTTOMRIGHT", -3, 3)
				pick.buttons[i] = b
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", pad + (i - 1) * (size + 4), -pad)
			b.image:SetTexture(choice.texture)
			b:SetSelected(choice.id == current)
			b:SetScript("OnClick", function()
				pick:Hide()
				onChoose(choice.id)
			end)
			Widgets.Tooltip(b, choice.label, choice.hint)
			b:Show()
		end
		for i = #choices + 1, #pick.buttons do pick.buttons[i]:Hide() end
		pick:SetSize(2 * pad + #choices * (size + 4) - 4, 2 * pad + size)
		pick:ClearAllPoints()
		pick:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
		pick.anchor = anchor
		pick:Show()
	end
	return pick
end

-- One section row: shown/hidden, title, Up, Down, and (Frames) icon and background.
local function buildRow(panel, parent, width)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, Panel.ROW)
	row.toggle = Widgets.Button(row, "", Panel.ROW, Panel.ROW, "ghost")
	row.toggle:SetPoint("LEFT", 0, 0)
	row.toggle:SetScript("OnClick", function()
		local _, message = ns.TRP3Commands.SetAboutSection(ns.ctx, "on", row.id, not row.on)
		say(message)
		panel:Changed()
	end)
	row.down = Widgets.Button(row, "Down", 54, Panel.ROW, "ghost")
	row.up = Widgets.Button(row, "Up", 42, Panel.ROW, "ghost")
	row.background = Widgets.Button(row, "", Panel.ROW, Panel.ROW, "ghost")
	row.icon = Widgets.Button(row, "", Panel.ROW, Panel.ROW, "ghost")
	row.background.image = row.background:CreateTexture(nil, "ARTWORK")
	row.background.image:SetPoint("TOPLEFT", 4, -4)
	row.background.image:SetPoint("BOTTOMRIGHT", -4, 4)
	row.icon.image = row.icon:CreateTexture(nil, "ARTWORK")
	row.icon.image:SetPoint("TOPLEFT", 3, -3)
	row.icon.image:SetPoint("BOTTOMRIGHT", -3, 3)
	for _, which in ipairs({ "up", "down" }) do
		row[which]:SetScript("OnClick", function()
			local _, message = ns.TRP3Commands.SetAboutSection(ns.ctx, "move", row.id, which == "up" and -1 or 1)
			say(message)
			panel:Changed()
		end)
	end
	Widgets.Tooltip(row.up, "Move up", "Shows this section earlier on the About page.")
	Widgets.Tooltip(row.down, "Move down", "Shows this section later on the About page.")
	row.icon:SetScript("OnClick", function()
		local choices = {}
		for _, c in ipairs(ns.TRP3Presentation.ICON_CHOICES) do
			choices[#choices + 1] = { id = c.id, label = c.label, texture = "Interface\\ICONS\\" .. c.id }
		end
		panel.picker:Open(row.icon, choices, row.iconId, function(id)
			local _, message = ns.TRP3Commands.SetAboutSection(ns.ctx, "icon", row.id, id)
			say(message)
			panel:Changed()
		end)
	end)
	row.background:SetScript("OnClick", function()
		local choices = {}
		for _, c in ipairs(ns.TRP3Presentation.BACKGROUND_CHOICES) do
			choices[#choices + 1] = { id = c.id, label = c.label, texture = ns.TRP3Presentation.BACKGROUNDS[c.id].file }
		end
		panel.picker:Open(row.background, choices, row.backgroundId, function(id)
			local _, message = ns.TRP3Commands.SetAboutSection(ns.ctx, "background", row.id, id)
			say(message)
			panel:Changed()
		end)
	end)
	Widgets.Tooltip(row.icon, "Frame icon", "The icon of this section's frame in Total RP 3.")
	Widgets.Tooltip(row.background, "Frame background", "The background of this section's frame in Total RP 3.")
	row.title = Widgets.EditLine(row, ns.StorySchema.TRP3_SECTION_TITLE_MAX + 1, Panel.ROW)
	row.title:HookScript("OnEditFocusLost", function(self)
		local text = self:GetText() or ""
		if row.id and text ~= row.titleText then
			local _, message = ns.TRP3Commands.SetAboutSection(ns.ctx, "title", row.id, text)
			say(message)
			panel:Changed()
		end
	end)
	-- Places the controls; frames: whether the icon and background show.
	function row.Layout(self, frames)
		local right = 0
		for _, key in ipairs(frames and { "background", "icon", "down", "up" } or { "down", "up" }) do
			local b = self[key]
			b:ClearAllPoints()
			b:SetPoint("RIGHT", self, "RIGHT", -right, 0)
			right = right + b:GetWidth() + 4
		end
		self.icon:SetShown(frames)
		self.background:SetShown(frames)
		self.title:ClearAllPoints()
		self.title:SetPoint("LEFT", self.toggle, "RIGHT", 6, 0)
		self.title:SetWidth(width - Panel.ROW - 6 - right - 2)
		self.titleWidth = width - Panel.ROW - 6 - right - 2
	end
	return row
end

--- Builds the panel at width x height (layout units); place it yourself.
function Panel.Build(parent, width, height)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)
	panel.width, panel.height = width, height
	local leftW = math.max(Panel.LEFT_MIN, math.min(Panel.LEFT_MAX, math.floor(width * 0.46)))
	leftW = math.min(leftW, math.floor((width - Panel.GAP) / 2))
	local rightW = width - leftW - Panel.GAP
	panel.leftWidth, panel.rightWidth = leftW, rightW

	-- Left: the choices, in a scroll frame (a short card scrolls them).
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("TRP3BioChoices"), panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	scroll:SetSize(leftW - Panel.SCROLL_BAR, height)
	local content = CreateFrame("Frame", nil, scroll)
	local W = leftW - Panel.SCROLL_BAR - 4
	content:SetSize(W, 1)
	scroll:SetScrollChild(content)
	Widgets.SlimScrollBar(scroll, 2)
	Widgets.WheelScroll(scroll)
	panel.choices, panel.content, panel.contentWidth = scroll, content, W

	local y = 0
	local function place(region, h)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		y = y + h
	end
	panel.templateLabel = eyebrow(content, "TEMPLATE", W)
	place(panel.templateLabel, Panel.EYEBROW + 4)
	panel.template = Widgets.Segmented(content, Panel.TEMPLATES, W, Style.CONTROL.compact, function(id)
		local _, message = ns.Actions.SetStoryPref(ns.ctx, "trp3Layout", id)
		say(message)
		panel:Changed()
	end)
	place(panel.template.buttons[1], Style.CONTROL.compact + Panel.BLOCK_GAP)
	Widgets.Tooltip(panel.templateLabel, "Template", Panel.HELP.template)
	for _, b in ipairs(panel.template.buttons) do Widgets.Tooltip(b, "Template: " .. b:GetText(), Panel.HELP.template) end

	panel.styleLabel = eyebrow(content, "STYLE", W)
	place(panel.styleLabel, Panel.EYEBROW + 4)
	panel.style = Widgets.Segmented(content, Panel.STYLES, W, Style.CONTROL.compact, function(id)
		local _, message = ns.Actions.SetStoryPref(ns.ctx, "trp3Style", id)
		say(message)
		panel:Changed()
	end)
	place(panel.style.buttons[1], Style.CONTROL.compact + Panel.BLOCK_GAP)
	for _, b in ipairs(panel.style.buttons) do Widgets.Tooltip(b, "Style: " .. b:GetText(), Panel.HELP.style) end

	panel.accentLabel = eyebrow(content, "HEADING COLOUR", W)
	place(panel.accentLabel, Panel.EYEBROW + 4)
	panel.swatches = {}
	for i, accent in ipairs(ns.TRP3Presentation.ACCENTS) do
		local b = swatch(content, accent, function(id)
			local _, message = ns.TRP3Commands.SetAboutAccent(ns.ctx, id)
			say(message)
			panel:Changed()
		end)
		b:SetPoint("TOPLEFT", content, "TOPLEFT", (i - 1) * (Panel.SWATCH + 6), -y)
		panel.swatches[i] = b
	end
	y = y + Panel.SWATCH + Panel.BLOCK_GAP

	panel.sectionsLabel = eyebrow(content, "SECTIONS", W)
	place(panel.sectionsLabel, Panel.EYEBROW + 4)
	panel.rows = {}
	for i = 1, #ns.StorySchema.TRP3_SECTIONS do
		local row = buildRow(panel, content, W)
		place(row, Panel.ROW + Panel.ROW_GAP)
		panel.rows[i] = row
	end
	y = y + Panel.BLOCK_GAP - Panel.ROW_GAP
	panel.reset = Widgets.Button(content, "Reset sections", Widgets.ButtonWidth("Reset sections", Style.CONTROL.compact),
		Style.CONTROL.compact, "ghost")
	place(panel.reset, Style.CONTROL.compact)
	panel.reset:SetScript("OnClick", function()
		local _, message = ns.TRP3Commands.SetAboutSection(ns.ctx, "reset")
		say(message)
		panel:Changed()
	end)
	Widgets.Tooltip(panel.reset, "Reset sections", "Puts the sections, their titles, icons and backgrounds back to "
		.. "Dawnward's defaults. Your text is not changed.")
	content:SetHeight(y)
	panel.contentHeight = y

	-- Right: the live preview.
	panel.previewHead = eyebrow(panel, "HOW TOTAL RP 3 WILL SHOW IT", rightW)
	panel.previewHead:SetPoint("TOPLEFT", panel, "TOPLEFT", leftW + Panel.GAP, 0)
	panel.render = newRenderer(panel, rightW, height - Panel.EYEBROW - 8)
	panel.render.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", leftW + Panel.GAP, -(Panel.EYEBROW + 8))
	panel.empty = Widgets.Label(panel, "body", true, "muted")
	panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", leftW + Panel.GAP, -(Panel.EYEBROW + 8))
	panel.empty:SetWidth(rightW - Panel.SCROLL_BAR)
	panel.empty:SetText("Nothing to show yet. Write a summary on the Character page, or import your story.")
	panel.empty:Hide()

	panel.picker = buildPicker(panel)

	-- A change: read everything again (the embedding page may also refresh).
	function panel.Changed(self)
		self:Refresh(self.view)
		if self.onChange then self.onChange() end
	end

	function panel.Refresh(self, view)
		self.view = view
		local section = view and view.checks and view.checks.about and view.checks.about.section
		local model = ns.TRP3Commands.AboutModel(realChar(), type(section) == "table" and section.TE or nil)
		self.model = model
		local prefs = model.prefs
		self.template:Select(prefs.trp3Layout or "current")
		self.style:Select(prefs.trp3Style or "neutral")
		local accent = prefs.trp3Accent or "style"
		for _, b in ipairs(self.swatches) do
			local a = ns.TRP3Presentation.ACCENT_BY_ID[b.accentId]
			local hex = a.hex or ns.TRP3Presentation.Get(prefs.trp3Style).color or "ffffff"
			Style.Color(b.fill, hexColor(hex))
			b:SetSelected(b.accentId == accent)
		end
		local frames = model.template == 2
		for i, row in ipairs(self.rows) do
			local s = model.sections[i]
			row.id, row.on, row.iconId, row.backgroundId = s.id, s.on, s.icon, s.background
			row.titleText = s.title
			row:Layout(frames)
			if not row.title:HasFocus() then row.title:SetText(s.title) end
			row.toggle:SetIcon(s.on and "check" or nil)
			row.toggle:SetSelected(s.on)
			row.title:SetAlpha((s.on and s.available) and 1 or 0.55)
			Widgets.Tooltip(row.toggle, s.on and "Shown" or "Hidden", (s.on and "Click to hide " or "Click to show ")
				.. s.defaultTitle:lower() .. "." .. (s.available and "" or ("\n\n" .. Panel.HELP.empty[s.id])))
			Widgets.Tooltip(row.title, s.defaultTitle, "The title shown above this section in Total RP 3. Clear it "
				.. "to use \"" .. s.defaultTitle .. "\"." .. (s.available and "" or ("\n\n" .. Panel.HELP.empty[s.id])))
			row.up:SetEnabled(i > 1)
			row.down:SetEnabled(i < #model.sections)
			row.icon.image:SetTexture("Interface\\ICONS\\" .. s.icon)
			row.background.image:SetTexture(ns.TRP3Presentation.BACKGROUNDS[s.background].file)
		end
		if not frames then self.picker:Hide() end
		self.previewHead:SetText("HOW TOTAL RP 3 WILL SHOW IT · TEMPLATE " .. model.template)
		local blocks = model.blocks
		local nothing = #blocks == 0 or (#blocks == 1 and #blocks[1].items == 0)
		self.empty:SetShown(nothing)
		Panel.Render(self.render, nothing and {} or blocks)
	end

	--- The preview's text in reading order (tests and diagnostics).
	function panel.PreviewText(self)
		local out = {}
		for _, fs in ipairs(self.render.order) do out[#out + 1] = fs:GetText() or "" end
		return table.concat(out, "\n")
	end

	return panel
end
