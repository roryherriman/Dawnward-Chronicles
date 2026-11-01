-- The v0.6 component kit: labels, buttons, icon buttons, inputs, cards,
-- dividers, segmented controls and the confirmation dialog. Every
-- component paints itself through UI/Style.lua, so a theme change reaches
-- all of them and no module colours a control by hand.
--
-- Only plain frames, font strings and solid-colour textures are used (no
-- FrameXML button or input templates), so the look is the same on every
-- client. Scroll frames still use UIPanelScrollFrameTemplate.
local _, ns = ...
local Themes, Style = ns.Themes, ns.Style

local Widgets = {}
ns.Widgets = Widgets

local nameCounter = 0
--- Unique global names for frames that need one (scroll frames, inputs).
function Widgets.NextName(prefix)
	nameCounter = nameCounter + 1
	return "DawnwardChronicles" .. prefix .. nameCounter
end

Widgets.Solid = Style.Solid
Widgets.SetColor = Style.Color
Widgets.TextColor = Style.TextColor

--- Anchors region to the rectangle rect = { left, right, bottom, top },
-- measured from anchor's bottom-left corner.
function Widgets.Place(region, anchor, rect)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", rect.left, rect.bottom)
	region:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", rect.right, rect.top)
end

--- A font string. role (title, eyebrow, heading, body, reading, muted, small,
-- accent, danger) colours it from the theme automatically; without a role
-- the caller colours it. font is a game font template ("GameFontHighlight")
-- or a Style.FONTS style name ("reading", "meta", "button", ...).
function Widgets.Label(parent, font, wrap, role)
	local spec = role and Style.TEXT[role]
	font = font or (spec and spec.font) or "GameFontHighlight"
	local fs = parent:CreateFontString(nil, "OVERLAY", Style.FontFor(font))
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(wrap and true or false)
	if wrap and fs.SetNonSpaceWrap then
		fs:SetNonSpaceWrap(true)
	end
	if spec then
		fs.textRole = spec.color
		Style.Register(fs, function(f, theme) Style.TextColor(f, Style.Tone(theme, f.textRole)) end)
	end
	return fs
end

--- Sets a label's colour role ("muted", "accent", a Style.Tones key, ...),
-- so it follows theme changes. Pure painting; no layout change.
function Widgets.SetTextRole(fs, colorRole)
	fs.textRole = colorRole
	Style.Register(fs, function(f, theme) Style.TextColor(f, Style.Tone(theme, f.textRole)) end)
	return fs
end

--- Tooltips ------------------------------------------------------------------------

-- Title in the design's bright gold, body lines in white and wrapped. A
-- frame whose tooltip was cleared (title nil) shows none.
local function showTooltip(owner, title, text)
	if not title then return end
	local gold = Style.Tones(Style.Current()).accentBright
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, gold[1], gold[2], gold[3])
	if text then
		GameTooltip:AddLine(text, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

-- Hooked, not set: a tooltip never removes a control's hover style.
local function hook(frame, script, fn)
	if frame.HookScript and frame:GetScript(script) then
		frame:HookScript(script, fn)
	else
		frame:SetScript(script, fn)
	end
end

function Widgets.Tooltip(frame, title, text)
	frame.tooltipTitle, frame.tooltipText = title, text
	if frame.tooltipHooked then
		return
	end
	frame.tooltipHooked = true
	-- A plain Frame receives OnEnter only when mouse input is on (buttons
	-- already have it); hover-only areas need it for their tooltip.
	if frame.EnableMouse and frame.GetObjectType and frame:GetObjectType() == "Frame" then
		frame:EnableMouse(true)
	end
	hook(frame, "OnEnter", function(self) showTooltip(self, self.tooltipTitle, self.tooltipText) end)
	hook(frame, "OnLeave", function() GameTooltip:Hide() end)
end

--- Buttons --------------------------------------------------------------------------
-- Variants of the design system (DesignSystem.dc.html "Buttons"):
--   default   "secondary": raised fill, stronger edge, text colour
--   primary   gold fill, bright gold edge, dark text (one per panel)
--   ghost     no fill, a quiet 1 px edge, softer text ("Later", "Guide")
--   danger    no fill, a dark red edge, light red text ("Delete")
--   choice    a left-aligned answer card (regular text, not bold)
--   segment   an item of a segmented control: no edge until selected
-- States: hover (lighter fill, gold edge), pressed (label nudged), disabled
-- (dimmed, muted text, as the design's 45 % opacity) and selected (the
-- segmented control's raised item).
-- Labels: Alegreya Sans Bold, 15 on standard (34 px and taller), 14 below.
Widgets.BUTTON = { insetChoice = 12, inset = 6, standardFrom = 34, disabledAlpha = 0.45 }

local function paintButton(b, theme)
	local tones = Style.Tones(theme)
	local enabled = b:IsEnabled() and true or false
	local hover = enabled and b.hover
	local v = b.variant
	local fill, fillAlpha, edge, edgeAlpha, text
	if b.selected then
		fill, fillAlpha, edge, edgeAlpha, text = tones.selectedFill, 1, tones.selectedEdge, 1, tones.heading
	elseif v == "primary" then
		fill, fillAlpha = hover and Style.Lighten(theme.accent, 0.12) or theme.accent, 1
		edge, edgeAlpha, text = tones.accentBright, 1, theme.accentText
	elseif v == "ghost" or v == "danger" or v == "segment" then
		fill, fillAlpha = theme.surfaceHover, hover and (v == "segment" and 0.6 or 1) or 0
		if v == "danger" then
			edge, text = hover and theme.danger or tones.dangerEdge, tones.dangerText
		else
			edge, text = hover and theme.border or theme.edge, hover and tones.heading or tones.ghostText
		end
		edgeAlpha = (v == "segment" and not hover) and 0 or 1
	else
		fill, fillAlpha = hover and tones.selectedFill or theme.surfaceHover, 1
		edge, edgeAlpha, text = hover and theme.border or tones.edgeStrong, 1, theme.text
		if v == "choice" then fill = hover and theme.surfaceHover or theme.surface end
	end
	if not enabled and not b.selected then
		text = theme.muted
		fillAlpha, edgeAlpha = fillAlpha * Widgets.BUTTON.disabledAlpha, edgeAlpha * Widgets.BUTTON.disabledAlpha
	end
	Style.Color(b.bg, fill, fillAlpha)
	b.edges:Paint(edge, edgeAlpha)
	if b.textColor then text = b.textColor end
	Style.TextColor(b.label, text)
end

local function placeLabel(b, pressed)
	local d = pressed and 1 or 0
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", b.textInset + d, -d)
	b.label:SetPoint("RIGHT", -b.textInset + d, -d)
end

--- The font style a button of height and variant uses. Pure.
function Widgets.ButtonFontStyle(height, variant)
	if variant == "choice" then
		return height >= Style.SIZE.button and "body" or "small"
	end
	return height >= Widgets.BUTTON.standardFrom and "button" or "buttonSmall"
end

--- Whether text fits a button of width and height (estimated with the
-- bundled font's real advance widths, Style.TextWidth). Pure.
function Widgets.LabelFits(text, width, height, variant)
	local inset = variant == "choice" and Widgets.BUTTON.insetChoice or Widgets.BUTTON.inset
	return Style.TextWidth(text, Widgets.ButtonFontStyle(height, variant)) <= width - 2 * inset
end

--- A styled button. API-compatible with the v0.5 buttons (SetText, GetText,
-- SetEnabled, Enable, Disable, GetFontString), plus SetSelected and SetVariant.
-- height: a Style.CONTROL height (compact 30, standard 36) for the design
-- system's sizes; smaller heights still work.
function Widgets.Button(parent, text, width, height, variant)
	local b = CreateFrame("Button", nil, parent)
	height = height or Style.SIZE.button
	b:SetSize(width or 100, height)
	b.variant = variant or "default"
	b.textInset = b.variant == "choice" and Widgets.BUTTON.insetChoice or Widgets.BUTTON.inset
	b.bg = Style.Solid(b, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.edges = Style.Edge(b, "BORDER")
	b.fontStyle = Widgets.ButtonFontStyle(height, b.variant)
	b.label = b:CreateFontString(nil, "OVERLAY", Style.FontFor(b.fontStyle))
	b.label:SetJustifyH(b.variant == "choice" and "LEFT" or "CENTER")
	b.label:SetWordWrap(false)
	placeLabel(b, false)
	if b.SetFontString then
		b:SetFontString(b.label)
	end
	b:SetText(text or "")

	local enable, disable, setEnabled = b.Enable, b.Disable, b.SetEnabled
	function b.Enable(self) enable(self); Style.Repaint(self) end
	function b.Disable(self) disable(self); Style.Repaint(self) end
	function b.SetEnabled(self, on) setEnabled(self, on); Style.Repaint(self) end
	function b.SetSelected(self, on) self.selected = on and true or nil; Style.Repaint(self) end
	function b.SetVariant(self, v) self.variant = v; Style.Repaint(self) end
	function b.GetFontString(self) return self.label end

	-- Hovering a button inside a record highlights that record too.
	local function rowOf(self)
		local p = self.GetParent and self:GetParent()
		return p and p.SetRowHover and p or nil
	end
	hook(b, "OnEnter", function(self)
		self.hover = true
		Style.Repaint(self)
		local row = rowOf(self)
		if row then row:SetRowHover(true) end
	end)
	hook(b, "OnLeave", function(self)
		self.hover = nil
		placeLabel(self, false)
		Style.Repaint(self)
		local row = rowOf(self)
		if row then row:SetRowHover(false) end
	end)
	hook(b, "OnMouseDown", function(self) if self:IsEnabled() then placeLabel(self, true) end end)
	hook(b, "OnMouseUp", function(self) placeLabel(self, false) end)
	return Style.Register(b, paintButton)
end

-- Glyphs drawn larger than a label: Close is the multiplication sign of the
-- design's icon button (Alegreya Sans has it; so do the game fonts).
Widgets.GLYPHS = { X = "\195\151", x = "\195\151" }

--- A small square button with a text glyph ("?", "X", "<", ">"): a ghost
-- button with a visible 1 px edge, as the design's icon button. "X" is
-- drawn as a large multiplication sign. Size it with Style.CONTROL.icon (36).
function Widgets.IconButton(parent, glyph, title, text)
	local shown = Widgets.GLYPHS[glyph]
	local b = Widgets.Button(parent, shown or glyph, Style.SIZE.icon, Style.SIZE.icon, "ghost")
	b.glyph = glyph
	if shown and Style.UsesBundledFont("glyph") then
		b.label:SetFontObject(Style.fontObjects[Style.FontFor("glyph")])
	end
	if title then
		Widgets.Tooltip(b, title, text)
	end
	return b
end

--- Segmented control: joined buttons, one selected. items = { { id, label } }.
-- Returns { buttons, selected, Select(id) }; onSelect(id) on click.
function Widgets.Segmented(parent, items, width, height, onSelect)
	local seg = { buttons = {} }
	local each = math.floor(width / #items)
	for i, item in ipairs(items) do
		local b = Widgets.Button(parent, item.label, each - 2, height or Style.SIZE.segment, "segment")
		b.segmentId = item.id
		b:SetScript("OnClick", function() onSelect(item.id) end)
		seg.buttons[i] = b
		if i > 1 then
			b:SetPoint("LEFT", seg.buttons[i - 1], "RIGHT", 2, 0)
		end
	end
	-- The design's segmented control sits in a panel-coloured track; it spans
	-- the buttons exactly, so it never needs more room than the caller gave.
	local first, last = seg.buttons[1], seg.buttons[#seg.buttons]
	if first then
		seg.track = Style.Solid(parent, "BACKGROUND", -1)
		seg.track:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
		seg.track:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
		Style.Register(seg.track, function(t, theme) Style.Color(t, theme.panel) end)
	end
	function seg.Select(_, id)
		seg.selected = id
		for _, b in ipairs(seg.buttons) do
			b:SetSelected(b.segmentId == id)
		end
	end
	return seg
end

--- Cards and dividers ------------------------------------------------------------

-- Entry rows: one record = one visual unit. A record's title, metadata,
-- status and actions all sit inside its own panel (surface fill, 1 px
-- edge, ENTRY.pad inside); panels are ENTRY.gap apart, so a button is always
-- inside its own record and never nearer the next one. Hovering the record
-- or any of its buttons highlights the whole unit (a lighter fill and a
-- stronger edge, as the design's featured card); a highlighted record (a
-- suggestion) has a gold edge and an accent bar on the left.
-- SetPlain(true) makes the frame an unboxed line,
-- for headings and hints in lists that reuse rows.
Widgets.ENTRY = { pad = 8, gap = 6 }

--- An entry panel (a "card"). Paints itself; :SetRowHover(on), :SetPlain(on).
--- The design's slim scroll bar (v0.8 Journal, shared since v0.9): restyles
-- a UIPanelScrollFrameTemplate's bar into a width-px track offset px right
-- of the scroll frame, with a proportional thumb and no arrow buttons (the
-- mouse wheel and dragging the thumb scroll). It follows the scroll range by
-- itself. Returns the bar, or nil where the template has none (nothing
-- changes then: the stock bar stays usable).
Widgets.SLIM_BAR = { width = 6, thumbMin = 30 }

--- Thumb height for a view of viewH showing total. Pure.
function Widgets.SlimThumbHeight(viewH, total)
	if not total or not viewH or total <= viewH or viewH <= 0 then
		return viewH or 0
	end
	return math.max(Widgets.SLIM_BAR.thumbMin, math.floor(viewH * viewH / total))
end

function Widgets.SlimScrollBar(scroll, offset, width)
	width = width or Widgets.SLIM_BAR.width
	local bar = type(scroll) == "table" and scroll.ScrollBar or nil -- parentKey in the 1.15.9 template
	if type(bar) ~= "table" or not bar.ClearAllPoints then
		return nil
	end
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", offset or 0, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", offset or 0, 0)
	bar:SetWidth(width)
	for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
		local arrow = type(bar[key]) == "table" and bar[key] or nil
		if arrow then
			arrow:SetAlpha(0)
			if arrow.EnableMouse then arrow:EnableMouse(false) end
			arrow:SetSize(1, 1)
		end
	end
	bar.track = Style.Solid(bar, "BACKGROUND")
	bar.track:SetAllPoints(bar)
	local thumb = type(bar.ThumbTexture) == "table" and bar.ThumbTexture or nil
	bar.thumb = thumb
	if thumb then
		thumb:SetTexture(nil)
		thumb:SetTexCoord(0, 1, 0, 1)
		thumb:SetSize(width, 90)
	end
	Style.Register(bar, function(b, theme)
		local tones = Style.Tones(theme)
		Style.Color(b.track, Style.Mix(theme.background, theme.panel, 0.6))
		if b.thumb then Style.Color(b.thumb, tones.edgeStrong) end
	end)
	-- Follow the scroll range: a proportional thumb, hidden when nothing scrolls.
	local function update()
		local ok, range = pcall(scroll.GetVerticalScrollRange, scroll)
		local viewH = scroll.GetHeight and scroll:GetHeight() or 0
		range = ok and type(range) == "number" and range or 0
		if bar.thumb then bar.thumb:SetSize(width, math.max(1, Widgets.SlimThumbHeight(viewH, viewH + range))) end
		bar:SetShown(range > 0)
	end
	if scroll.HookScript then
		scroll:HookScript("OnScrollRangeChanged", update)
	end
	bar.UpdateThumb = update
	return bar
end

--- Mouse wheel ---------------------------------------------------------------------
-- The client gives the wheel to the topmost frame under the cursor that has
-- it enabled; with none, it zooms the camera. Scroll frames scroll by a
-- fixed step (clamped to their range); the window swallows the rest, so the
-- wheel never reaches the game world while the journal is under the cursor.
Widgets.WHEEL_STEP = 60

--- How far scroll can move (0 when nothing scrolls or the client cannot say).
function Widgets.ScrollRange(scroll)
	local ok, range = pcall(scroll.GetVerticalScrollRange, scroll)
	range = ok and type(range) == "number" and range or 0
	return math.max(0, math.floor(range))
end

--- Scrolls to value, clamped to the range; returns where it went. Through
-- the template's bar where there is one (its OnValueChanged moves the view),
-- so the thumb and the view stay together.
function Widgets.ScrollTo(scroll, value)
	value = math.max(0, math.min(Widgets.ScrollRange(scroll), value or 0))
	local bar = scroll.ScrollBar
	if type(bar) == "table" and bar.SetValue then
		bar:SetValue(value)
	end
	if scroll:GetVerticalScroll() ~= value then scroll:SetVerticalScroll(value) end
	return value
end

--- The wheel scrolls scroll by step (default WHEEL_STEP) per notch.
function Widgets.WheelScroll(scroll, step)
	step = step or Widgets.WHEEL_STEP
	if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
	scroll:SetScript("OnMouseWheel", function(self, delta)
		Widgets.ScrollTo(self, self:GetVerticalScroll() - (delta or 0) * step)
	end)
end

--- The wheel over frame does nothing (and so never zooms the camera).
function Widgets.SwallowWheel(frame)
	if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
	frame:SetScript("OnMouseWheel", function() end)
end

function Widgets.Card(parent)
	local card = CreateFrame("Frame", nil, parent)
	card.bg = Style.Solid(card, "BACKGROUND", -2)
	card.bg:SetAllPoints(card)
	card.edges = Style.Edge(card, "BORDER")
	card.bar = Style.Solid(card, "ARTWORK")
	card.bar:SetPoint("TOPLEFT", 0, 0)
	card.bar:SetPoint("BOTTOMLEFT", 0, 0)
	card.bar:SetWidth(2)
	card.bar:Hide()
	function card.SetRowHover(self, on)
		self.hover = on and true or nil
		Style.Repaint(self)
	end
	function card.SetPlain(self, on)
		self.plain = on and true or nil
		Style.Repaint(self)
	end
	if card.EnableMouse then card:EnableMouse(true) end
	hook(card, "OnEnter", function(self) self:SetRowHover(true) end)
	hook(card, "OnLeave", function(self) self:SetRowHover(false) end)
	Style.Register(card, function(c, theme)
		local boxed = not c.plain
		local tones = Style.Tones(theme)
		Style.Color(c.bg, c.hover and tones.cardHover or theme.surface, boxed and 1 or 0)
		local edge = c.highlight and theme.accent or (c.hover and tones.selectedEdge or theme.edge)
		c.edges:Paint(edge, boxed and 1 or 0)
		c.bar:SetShown(boxed and c.highlight and true or false)
		Style.Color(c.bar, theme.accent)
	end)
	return card
end
Widgets.EntryRow = Widgets.Card

--- A 1 px line in the theme's edge colour. Anchor it yourself.
function Widgets.Divider(parent, layer)
	local line = Style.Solid(parent, layer or "ARTWORK")
	line:SetHeight(1)
	return Style.Register(line, function(l, theme) Style.Color(l, theme.edge) end)
end

--- Visibility -------------------------------------------------------------------

local CYCLE = { private = "public", public = "secret", secret = "private" }

Widgets.VISIBILITY_HELP = "Public: may be shared (share exports, and Total RP 3 if you turned sync on).\n"
	.. "Private: only you; included in your personal backups.\n"
	.. "Secret: only you; left out of backups unless you ask.\nClick to change."

-- Chip tints: a chip's fill and edge are its text colour mixed into the
-- surface it sits on (opaque, so round ends can be layered). The design
-- system's Private chip is #B4C6EA on #1B2436 with a #3A4D73 edge.
Widgets.CHIP_TINT = { fill = 0.12, edge = 0.36, hoverFill = 0.2, hoverEdge = 0.7 }

--- Fill and edge colours of a chip of color on base (default theme.surface). Pure.
function Widgets.ChipColors(color, theme, base, hover)
	base = base or theme.surface
	local T = Widgets.CHIP_TINT
	return Style.Mix(base, color, hover and T.hoverFill or T.fill), Style.Mix(base, color, hover and T.hoverEdge or T.edge)
end

-- Keeps a pill's round ends the height of its frame.
local function followHeight(frame, pill)
	hook(frame, "OnSizeChanged", function(self, _, height)
		height = height or self:GetHeight()
		if type(height) == "number" and height > 2 then pill:Resize(height) end
	end)
end

-- Paints a visibility button as a chip in its fixed colour. Called directly
-- (not only through the registry) so the chip stays right even where a
-- screen registers its own painter for the button.
local function paintVisibilityChip(b, theme)
	theme = theme or Style.Current()
	local color = Themes.VISIBILITY_COLORS[b.level] or Themes.VISIBILITY_COLORS.private
	local hover = b.hover and b:IsEnabled()
	local fill, edge = Widgets.ChipColors(color, theme, b.chipBase and Style.Tone(theme, b.chipBase), hover)
	if b.pill then
		b.pill:Paint(fill, edge)
		b.bg:Hide()
		b.edges:SetShown(false)
	else
		Style.Color(b.bg, fill)
		b.edges:Paint(edge, 1)
	end
	Style.TextColor(b.label, b:IsEnabled() and color or theme.muted)
end

--- A visibility chip showing Public / Private / Secret in its fixed colour
-- (a pill with round ends where the client can draw them). It stays a
-- button: clicking cycles the level and calls onChange(newLevel); the caller
-- saves. :SetChipBase(role) names the surface it sits on (default surface).
function Widgets.VisibilityButton(parent, onChange)
	local button = Widgets.Button(parent, "Private", 72, Style.SIZE.compact, "ghost")
	button.pill = Style.Pill(button, Style.SIZE.compact)
	if button.pill then followHeight(button, button.pill) end
	button.level = "private"
	function button:SetLevel(level)
		self.level = level
		self:SetText(Themes.VISIBILITY_LABELS[level] or level)
		self.textColor = Themes.VISIBILITY_COLORS[level] or Themes.VISIBILITY_COLORS.private
		paintVisibilityChip(self)
		Style.Repaint(self)
	end
	function button:SetChipBase(role)
		self.chipBase = role
		paintVisibilityChip(self)
	end
	Style.Register(button, paintVisibilityChip)
	hook(button, "OnEnter", function(self) paintVisibilityChip(self) end)
	hook(button, "OnLeave", function(self) paintVisibilityChip(self) end)
	button:SetLevel("private")
	button:SetScript("OnClick", function(self)
		onChange(CYCLE[self.level] or "private", self)
	end)
	Widgets.Tooltip(button, "Visibility", Widgets.VISIBILITY_HELP)
	return button
end

--- Text input --------------------------------------------------------------------

-- Field states, shared by one-line inputs and text areas (design system
-- "Inputs and validation"): a dark well with a 1 px edge; focused, a 2 px
-- gold edge and a slightly lighter well; invalid, a 2 px danger edge. The
-- 2 px ring (twice the resting edge) shows focus and errors without
-- relying on colour alone; the error message also starts with "!". The
-- focus bar is the ring's left side, kept as its own texture for callers.
Widgets.FIELD = { textInset = 10 }

local function paintField(box, theme, fill, edges, bar, edit)
	local tones = Style.Tones(theme)
	local state = box.invalid and theme.danger or box.focused and theme.accent or nil
	Style.Color(fill, box.focused and tones.fieldFocus or tones.field)
	edges:Paint(state or tones.fieldEdge, 1)
	box.ring:SetShown(state ~= nil)
	if state then box.ring:Paint(state, 1) end
	bar:SetShown(state ~= nil)
	if state then Style.Color(bar, state) end
	edit:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
end

local function focusBar(frame)
	local bar = Style.Solid(frame, "ARTWORK")
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", 0, 0)
	bar:SetWidth(2)
	bar:Hide()
	return bar
end

-- The second pixel of the 2 px focus and error ring.
local function focusRing(frame)
	local ring = Style.Edge(frame, "BORDER", 1)
	ring:SetShown(false)
	return ring
end

local function inputFrame(edit)
	edit.bg = Style.Solid(edit, "BACKGROUND", -1)
	edit.bg:SetAllPoints(edit)
	edit.edges = Style.Edge(edit, "BORDER")
	edit.ring = focusRing(edit)
	edit.focusBar = focusBar(edit)
	hook(edit, "OnEditFocusGained", function(self) self.focused = true; Style.Repaint(self) end)
	hook(edit, "OnEditFocusLost", function(self) self.focused = nil; Style.Repaint(self) end)
	return Style.Register(edit, function(e, theme)
		paintField(e, theme, e.bg, e.edges, e.focusBar, e)
	end)
end

--- A one-line input on a dark well (no FrameXML template). height defaults
-- to the v0.6 size; Style.CONTROL.input (36) is the design system's.
function Widgets.EditLine(parent, maxBytes, height)
	local edit = CreateFrame("EditBox", Widgets.NextName("Line"), parent)
	edit:SetAutoFocus(false)
	edit:SetHeight(height or Style.SIZE.input)
	edit:SetFontObject(Style.FontObject("ChatFontNormal") or ChatFontNormal)
	edit:SetTextInsets(Widgets.FIELD.textInset, Widgets.FIELD.textInset, 0, 0)
	edit:SetMaxBytes(maxBytes or 100)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return inputFrame(edit)
end

-- Keeps the caret visible while typing in a scrolling text area.
local function followCursor(scroll, y, cursorHeight)
	local offset = scroll:GetVerticalScroll()
	local visible = scroll:GetHeight()
	y = -y
	if y < offset then
		scroll:SetVerticalScroll(y)
	elseif y + cursorHeight > offset + visible then
		scroll:SetVerticalScroll(y + cursorHeight - visible)
	end
end

--- Multi-line text area on a surface well. Returns { frame, scroll, edit, well }.
-- Place area.frame; the text inside follows its size. width is the area's
-- expected width, used until the client reports the real size.
function Widgets.TextArea(parent, maxBytes, width)
	local area = {}
	area.frame = CreateFrame("Frame", nil, parent)
	area.well = Style.Solid(area.frame, "BACKGROUND", -6)
	area.well:SetAllPoints(area.frame)
	area.edges = Style.Edge(area.frame, "BORDER")

	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("Scroll"), area.frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -26, 4)
	area.scroll = scroll

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxBytes(maxBytes or 2000)
	edit:SetFontObject(Style.FontObject("ChatFontNormal") or ChatFontNormal)
	edit:SetTextInsets(6, 6, 4, 4)
	edit:SetWidth(math.max(100, (width or 230) - 30)) -- minus scroll bar and padding
	edit:SetHeight(100)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnCursorChanged", function(_, _, y, _, h) followCursor(scroll, y, h) end)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnSizeChanged", function(_, newWidth, newHeight)
		edit:SetWidth(newWidth)
		edit:SetHeight(newHeight)
	end)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	area.edit = edit
	area.followCursor = followCursor
	area.ring = focusRing(area.frame)
	area.focusBar = focusBar(area.frame)
	-- The edit box is what forms and focus chains hold; its state is drawn
	-- on the area around it.
	edit.multiline = true
	edit.paintTarget = area
	edit.anchorRegion = area.frame
	hook(edit, "OnEditFocusGained", function(self) self.focused = true; area.focused = true; Style.Repaint(area) end)
	hook(edit, "OnEditFocusLost", function(self) self.focused = nil; area.focused = nil; Style.Repaint(area) end)
	Style.Register(area, function(a, theme)
		a.invalid = a.edit.invalid
		paintField(a, theme, a.well, a.edges, a.focusBar, a.edit)
	end)
	return area
end

--- Field errors (inline validation) -------------------------------------------------

Widgets.ERROR_PREFIX = "! "

--- Turns a core refusal ("Not changed: a stance needs a subject") into an
-- inline message ("A stance needs a subject."). Pure.
function Widgets.ErrorText(message)
	local text = tostring(message or ""):gsub("^Not changed:%s*", "")
	text = text:gsub("^%l", string.upper)
	if text ~= "" and not text:find("[%.!?]$") then text = text .. "." end
	return text
end

--- Gives an input (an EditLine, or a TextArea's edit) an error line directly
-- beneath it, width wide. The error clears itself as soon as the player
-- changes the field. Returns the label.
function Widgets.FieldError(input, width)
	local region = input.anchorRegion or input
	local fs = Widgets.Label(region:GetParent(), "meta", true, "danger")
	fs:SetPoint("TOPLEFT", region, "BOTTOMLEFT", 0, -3)
	fs:SetWidth(width or 300)
	fs:Hide()
	input.errorLabel = fs
	hook(input, "OnTextChanged", function(self, userInput)
		if userInput and self.invalid then
			Widgets.SetFieldError(self, nil)
		end
	end)
	return fs
end

--- Marks input invalid with message (nil clears it). Highlights the field
-- and shows the message beneath it; onChange(input) lets a form make room.
function Widgets.SetFieldError(input, message)
	input.invalid = message and true or nil
	local label = input.errorLabel
	if label then
		label:SetText(message and (Widgets.ERROR_PREFIX .. Widgets.ErrorText(message)) or "")
		label:SetShown(message ~= nil)
	end
	Style.Repaint(input.paintTarget or input)
	if input.onErrorChanged then input.onErrorChanged(input) end
end

--- Height an error line takes under its field (0 when there is none).
function Widgets.ErrorHeight(input)
	local label = input.errorLabel
	if not (input.invalid and label) then return 0 end
	return math.max(12, label.GetStringHeight and label:GetStringHeight() or 12) + 4
end

--- Keyboard navigation ---------------------------------------------------------------
-- A focus chain links a form's editable fields, in order:
--   Tab / Shift+Tab   next / previous usable field (wraps; skips fields that are
--                     hidden, inside a hidden frame, or disabled)
--   Enter             in a one-line field: the next field; on the last one,
--                     opts.onSubmit (the form validates, so nothing incomplete
--                     is saved). Multi-line fields keep Enter for new lines.
--   Escape            opts.onEscape(dirty): the form cancels or closes, asking
--                     first when typed changes would be lost
-- Only Dawnward's own edit boxes take part and nothing captures the keyboard,
-- so chat and key bindings behave as usual once a field loses focus.

local function usable(box)
	return box:IsVisible() and (not box.IsEnabled or box:IsEnabled() ~= false)
end

function Widgets.FocusChain(opts)
	local chain = { fields = {}, onSubmit = opts and opts.onSubmit, onEscape = opts and opts.onEscape }

	--- The usable fields, in order.
	function chain.Usable()
		local out = {}
		for _, box in ipairs(chain.fields) do
			if usable(box) then out[#out + 1] = box end
		end
		return out
	end

	--- Moves focus from box by step (1 or -1), wrapping. Returns the new field.
	function chain.Move(box, step)
		local list = chain.Usable()
		if #list == 0 then return nil end
		local at = 0
		for i, b in ipairs(list) do
			if b == box then at = i end
		end
		local target = list[(at - 1 + step) % #list + 1]
		target:SetFocus()
		return target
	end

	function chain.FocusFirst()
		local first = chain.Usable()[1]
		if first then first:SetFocus() end
		return first
	end

	--- Whether any field's text differs from when the chain was set.
	function chain.IsDirty()
		for _, box in ipairs(chain.fields) do
			if (box:GetText() or "") ~= (chain.snapshot[box] or "") then return true end
		end
		return false
	end

	function chain.Escape(box)
		if box then box:ClearFocus() end
		if chain.onEscape then chain.onEscape(chain.IsDirty()) end
	end

	--- Sets the fields (in Tab order) and remembers their current text.
	function chain.SetFields(list)
		chain.fields, chain.snapshot = list, {}
		for _, box in ipairs(list) do
			chain.snapshot[box] = box:GetText() or ""
			box:SetScript("OnTabPressed", function(self)
				chain.Move(self, IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
			end)
			box:SetScript("OnEscapePressed", function(self) chain.Escape(self) end)
			if not box.multiline then
				box:SetScript("OnEnterPressed", function(self)
					local usableList = chain.Usable()
					if usableList[#usableList] == self then
						self:ClearFocus()
						if chain.onSubmit then chain.onSubmit() end
					else
						chain.Move(self, 1)
					end
				end)
			end
		end
	end

	--- Asks before discarding typed changes; otherwise calls cancel at once.
	function chain.ConfirmDiscard(dirty, cancel)
		if dirty then
			Widgets.Confirm("Discard the changes you typed?", "Discard", cancel)
		else
			cancel()
		end
	end

	return chain
end

--- Confirmation -------------------------------------------------------------------

Widgets.DIALOG_NAME = "DawnwardChroniclesConfirm"
Widgets.DIALOG_STRATA = "DIALOG"

local function buildDialog()
	local d = CreateFrame("Frame", Widgets.DIALOG_NAME, UIParent)
	d:SetSize(380, 150)
	d:SetPoint("CENTER", 0, 80)
	d:SetFrameStrata(Widgets.DIALOG_STRATA)
	d:SetToplevel(true)
	d:EnableMouse(true)
	d:SetClampedToScreen(true)
	Style.Chrome(d)
	d.eyebrow = Widgets.Label(d, nil, false, "eyebrow")
	d.eyebrow:SetPoint("TOPLEFT", 18, -16)
	d.eyebrow:SetText("DAWNWARD CHRONICLES")
	d.text = Widgets.Label(d, nil, true, "body")
	d.text:SetPoint("TOPLEFT", 18, -36)
	d.text:SetWidth(344)
	d.cancel = Widgets.Button(d, "Cancel", 100, Style.CONTROL.compact, "ghost")
	d.cancel:SetPoint("BOTTOMRIGHT", -16, 16)
	d.cancel:SetScript("OnClick", function() d:Hide() end)
	d.accept = Widgets.Button(d, "Confirm", 120, Style.CONTROL.compact, "danger")
	d.accept:SetPoint("RIGHT", d.cancel, "LEFT", -8, 0)
	d.accept:SetScript("OnClick", function()
		local fn = d.onAccept
		d.onAccept = nil
		d:Hide()
		if fn then fn() end
	end)
	d:SetScript("OnHide", function(self) self.onAccept = nil end)
	-- Escape cancels the dialog only. (UISpecialFrames would also close the
	-- journal or wizard beneath it.) Other keys pass through to the game.
	d:EnableKeyboard(true)
	d:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
			self:Hide()
		elseif self.SetPropagateKeyboardInput then
			self:SetPropagateKeyboardInput(true)
		end
	end)
	d:Hide()
	return d
end

--- Asks the player to confirm an action in the Dawnward dialog. onAccept
-- runs only after the accept button is clicked; Cancel or Escape do nothing.
function Widgets.Confirm(text, acceptLabel, onAccept)
	local d = Widgets.dialog or buildDialog()
	Widgets.dialog = d
	d.text:SetText(text)
	d.accept:SetText(acceptLabel or "Confirm")
	local height = 36 + (d.text.GetStringHeight and d.text:GetStringHeight() or 30) + 60
	d:SetHeight(math.max(130, height))
	d:Show()
	d.onAccept = onAccept
	if d.Raise then d:Raise() end
	return d
end

--- v0.7 components (docs/design/UI_DESIGN_V07.md) ----------------------------------
-- Shared by every section so the screens stay consistent with the approved
-- design system: status chips, panels with an eyebrow title, a callout, a
-- date block, a progress bar and a search box.

-- Chips (design system "Chips"): 24 high, 10 px side padding, 13 px text,
-- round ends where the client can draw them. Tones:
--   accent    gold ("Defining", "Homeland")         waiting  amber ("Waiting for approval")
--   muted     neutral tag ("Recorded event")         danger   red
--   public / private / secret  the fixed visibility colours, whatever the theme
Widgets.CHIP_HEIGHT = 24
Widgets.CHIP_PAD = 10

--- Text, fill and edge colours of a chip tone on base (a colour). Pure.
function Widgets.ChipTone(tone, theme, base)
	base = base or theme.surface
	local tones = Style.Tones(theme)
	if Themes.VISIBILITY_COLORS[tone] then
		local color = Themes.VISIBILITY_COLORS[tone]
		local fill, edge = Widgets.ChipColors(color, theme, base)
		return color, fill, edge
	end
	if tone == "waiting" then
		local color = Themes.STATUS_COLORS.waiting
		local fill, edge = Widgets.ChipColors(color, theme, base)
		return color, fill, edge
	end
	if tone == "danger" then
		local fill, edge = Widgets.ChipColors(theme.danger, theme, base)
		return tones.dangerText, fill, edge
	end
	if tone == "muted" then
		return Style.Mix(theme.muted, theme.text, 0.3), Style.Mix(base, theme.edge, 0.3), theme.edge
	end
	return tones.accentBright, Style.Mix(base, theme.accent, 0.1), theme.border
end

--- A small status pill ("Defining", "Homeland", "Waiting for your approval").
-- tone: accent (default), waiting, muted, danger, public, private or secret.
-- height: Widgets.CHIP_HEIGHT (24) by default; Style.CONTROL.chipSmall (20)
-- for dense lists. Sizes itself to its text; :SetChip(text, tone) changes
-- it, :SetMaxWidth(w) caps it (the full text then shows as a tooltip) and
-- :SetBase(role) names the surface it sits on (default "surface").
function Widgets.Chip(parent, text, tone, height)
	local chip = CreateFrame("Frame", nil, parent)
	height = height or Widgets.CHIP_HEIGHT
	chip:SetHeight(height)
	chip.bg = Style.Solid(chip, "BACKGROUND")
	chip.bg:SetAllPoints(chip)
	chip.edges = Style.Edge(chip, "BORDER")
	chip.pill = Style.Pill(chip, height)
	if chip.pill then
		chip.bg:Hide()
		chip.edges:SetShown(false)
		followHeight(chip, chip.pill)
	end
	chip.label = chip:CreateFontString(nil, "OVERLAY", Style.FontFor("small"))
	chip.label:SetPoint("CENTER", 0, 0)
	chip.label:SetWordWrap(false)
	chip.base = "surface"
	function chip.SetChip(self, t, newTone)
		self.tone = newTone or self.tone or "accent"
		self.text = t or ""
		-- Measure the text unconstrained: a width left from an earlier, shorter
		-- text would make GetStringWidth report the cut width. 1.15.9 also has
		-- GetUnboundedStringWidth (SimpleFontStringAPIDocumentation), which
		-- ignores any width; it is preferred when present.
		if self.maxWidth then self.label:SetWidth(0) end
		self.label:SetText(self.text)
		local fs = self.label
		local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth())
			or (fs.GetStringWidth and fs:GetStringWidth()) or 0
		if type(w) ~= "number" or w <= 0 then w = Style.TextWidth(self.text, "small") end
		w = math.ceil(w)
		local full = w + 2 * Widgets.CHIP_PAD
		if self.maxWidth and full > self.maxWidth then
			full = self.maxWidth
			self.label:SetWidth(full - 2 * Widgets.CHIP_PAD)
			self.truncated = true
		else
			if self.maxWidth then self.label:SetWidth(w + 1) end
			self.truncated = nil
		end
		self:SetWidth(math.max(full, self:GetHeight()))
		if self.truncated then
			Widgets.Tooltip(self, self.text)
			if self.EnableMouse then self:EnableMouse(true) end
			-- Hovering a cut chip inside a card keeps the card highlighted.
			if not self.rowHoverHooked and self.HookScript then
				self.rowHoverHooked = true
				self:HookScript("OnEnter", function(c)
					local row = c:GetParent()
					if row and row.SetRowHover then row:SetRowHover(true) end
				end)
				self:HookScript("OnLeave", function(c)
					local row = c:GetParent()
					if row and row.SetRowHover then row:SetRowHover(false) end
				end)
			end
		elseif self.tooltipHooked then
			self.tooltipTitle, self.tooltipText = nil, nil
			-- A chip that fits takes no mouse input, so it never steals the card's hover.
			if self.EnableMouse then self:EnableMouse(false) end
		end
		Style.Repaint(self)
	end
	function chip.SetMaxWidth(self, w)
		self.maxWidth = w
		self:SetChip(self.text, self.tone)
	end
	function chip.SetBase(self, role)
		self.base = role
		Style.Repaint(self)
	end
	Style.Register(chip, function(c, theme)
		local color, fill, edge = Widgets.ChipTone(c.tone, theme, Style.Tone(theme, c.base))
		if c.pill then
			c.pill:Paint(fill, edge)
		else
			Style.Color(c.bg, fill)
			c.edges:Paint(edge, 1)
		end
		Style.TextColor(c.label, color)
	end)
	chip:SetChip(text, tone)
	return chip
end

--- A panel (the design's card): a surface with a 1 px edge, an optional
-- eyebrow title (Cinzel, ornament colour) and an inner content area at
-- panel.inner (pad 14). Used for the right-hand columns and grouped sections.
Widgets.PANEL_PAD = 14
function Widgets.Panel(parent, title)
	local panel = CreateFrame("Frame", nil, parent)
	panel.bg = Style.Solid(panel, "BACKGROUND", -3)
	panel.bg:SetAllPoints(panel)
	panel.edges = Style.Edge(panel, "BORDER")
	local top = Widgets.PANEL_PAD
	if title then
		panel.title = Widgets.Label(panel, "GameFontNormalSmall", false, "eyebrow")
		panel.title:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -Widgets.PANEL_PAD)
		panel.title:SetText(title:upper())
		top = top + 22
	end
	panel.inner = CreateFrame("Frame", nil, panel)
	panel.inner:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -top)
	panel.inner:SetPoint("BOTTOMRIGHT", -Widgets.PANEL_PAD, Widgets.PANEL_PAD)
	function panel.SetTitle(self, t)
		if self.title then self.title:SetText((t or ""):upper()) end
	end
	Style.Register(panel, function(p, theme)
		Style.Color(p.bg, p.callout and Style.Tones(theme).calloutFill or theme.surface)
		p.edges:Paint(p.callout and theme.border or theme.edge, 1)
	end)
	return panel
end

--- A callout: a panel with a gold edge and a warm dark fill, for the one
-- thing waiting on the player ("A moment awaits", "Needs your approval").
function Widgets.Callout(parent, title)
	local panel = Widgets.Panel(parent, title)
	panel.callout = true
	panel.glow = Style.Solid(panel, "BACKGROUND", -2)
	panel.glow:SetAllPoints(panel)
	Style.Register(panel.glow, function(t, theme) Style.Color(t, theme.accent, 0.03) end)
	Style.Repaint(panel)
	return panel
end

--- A date block: the day large (Cinzel 24, bright gold) over a short month
-- (Cinzel 13, muted), for entry cards. :SetDate(timestamp) shows "?" when
-- the date is unknown.
function Widgets.DateBlock(parent)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(56, 46)
	block.day = Widgets.Label(block, "day", false, "title")
	Widgets.SetTextRole(block.day, "accentBright")
	block.day:SetPoint("TOP", 0, 0)
	block.day:SetJustifyH("CENTER")
	block.month = Widgets.Label(block, "GameFontNormalSmall", false, "muted")
	block.month:SetPoint("TOP", block.day, "BOTTOM", 0, -2)
	block.month:SetJustifyH("CENTER")
	function block.SetDate(self, timestamp)
		if type(timestamp) == "number" and timestamp > 0 then
			self.day:SetText(tostring(tonumber(date("%d", timestamp))))
			self.month:SetText(date("%b", timestamp):upper())
		else
			self.day:SetText("?")
			self.month:SetText("")
		end
	end
	return block
end

--- A thin progress bar (design: 6 high, a dark track, a gold fill).
-- :SetValue(fraction 0..1).
function Widgets.ProgressBar(parent, width, height)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetSize(width or 200, height or 4)
	bar.track = Style.Solid(bar, "BACKGROUND")
	bar.track:SetAllPoints(bar)
	bar.fill = Style.Solid(bar, "ARTWORK")
	bar.fill:SetPoint("TOPLEFT")
	bar.fill:SetPoint("BOTTOMLEFT")
	function bar.SetValue(self, fraction)
		fraction = type(fraction) == "number" and math.max(0, math.min(1, fraction)) or 0
		self.value = fraction
		local w = self:GetWidth() or 0
		self.fill:SetWidth(math.max(1, w * fraction))
		self.fill:SetShown(fraction > 0)
	end
	Style.Register(bar, function(b, theme)
		Style.Color(b.track, Style.Tones(theme).track)
		Style.Color(b.fill, theme.accent)
	end)
	bar:SetValue(0)
	return bar
end

--- A search box: a one-line input with a placeholder. onChange(text) runs
-- as the player types (text trimmed; "" when cleared). height defaults to
-- the v0.6 size; Style.CONTROL.input (36) is the design system's.
function Widgets.SearchBox(parent, width, placeholder, onChange, height)
	local box = Widgets.EditLine(parent, 60, height)
	box:SetWidth(width or 200)
	box.placeholder = Widgets.Label(box, "GameFontHighlightSmall", false, "muted")
	box.placeholder:SetPoint("LEFT", Widgets.FIELD.textInset, 0)
	box.placeholder:SetText(placeholder or "Search")
	local function update(self)
		local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
		self.placeholder:SetShown(text == "" and not self.focused)
		if onChange then onChange(text) end
	end
	hook(box, "OnTextChanged", update)
	hook(box, "OnEditFocusGained", function(self) self.placeholder:Hide() end)
	hook(box, "OnEditFocusLost", function(self)
		self.placeholder:SetShown((self:GetText() or "") == "")
	end)
	return box
end

--- Formats a stored timestamp for display (WoW's date(); 0 means unknown).
function Widgets.FormatDate(timestamp)
	if type(timestamp) ~= "number" or timestamp <= 0 then
		return "Unknown date"
	end
	return date("%d %b %Y, %H:%M", timestamp)
end
