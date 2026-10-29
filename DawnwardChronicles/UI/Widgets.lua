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

--- A font string. role (title, eyebrow, heading, body, muted, small, accent,
-- danger) colours it from the theme automatically; without a role the
-- caller colours it.
function Widgets.Label(parent, font, wrap, role)
	local spec = role and Style.TEXT[role]
	local fs = parent:CreateFontString(nil, "OVERLAY", Style.Font(font or (spec and spec.font) or "GameFontHighlight"))
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(wrap and true or false)
	if wrap and fs.SetNonSpaceWrap then
		fs:SetNonSpaceWrap(true)
	end
	if spec then
		fs.textRole = spec.color
		Style.Register(fs, function(f, theme) Style.TextColor(f, theme[f.textRole]) end)
	end
	return fs
end

--- Tooltips ------------------------------------------------------------------------

local function showTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title)
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
	hook(frame, "OnEnter", function(self) showTooltip(self, self.tooltipTitle, self.tooltipText) end)
	hook(frame, "OnLeave", function() GameTooltip:Hide() end)
end

--- Buttons --------------------------------------------------------------------------
-- Variants: default (surface), primary (accent fill), ghost (no fill until
-- hovered), danger (danger text), choice (a left-aligned answer card).
-- States: hover, pressed, disabled and selected (segmented controls).

local function paintButton(b, theme)
	local enabled = b:IsEnabled() and true or false
	local hover = enabled and b.hover
	local v = b.variant
	local fill, fillAlpha, edge, edgeAlpha, text
	if b.selected then
		fill, fillAlpha, edge, edgeAlpha, text = theme.surfaceHover, 1, theme.accent, 1, theme.accent
	elseif v == "primary" and enabled then
		fill, fillAlpha = hover and Style.Lighten(theme.accent, 0.15) or theme.accent, 1
		edge, edgeAlpha, text = theme.accent, 1, theme.accentText
	elseif v == "ghost" or v == "danger" then
		fill, fillAlpha = theme.surfaceHover, hover and 1 or 0
		edge, edgeAlpha = v == "danger" and hover and theme.danger or theme.edge, hover and 1 or 0
		text = v == "danger" and theme.danger or (hover and theme.accent or theme.text)
	else
		fill, fillAlpha = hover and theme.surfaceHover or theme.surface, 1
		edge, edgeAlpha, text = hover and theme.accent or theme.edge, 1, theme.text
	end
	if not enabled and not b.selected then
		text = theme.muted
		if v == "primary" then fill, edge = theme.surface, theme.edge end
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

--- A styled button. API-compatible with the v0.5 buttons (SetText, GetText,
-- SetEnabled, Enable, Disable, GetFontString), plus SetSelected and SetVariant.
function Widgets.Button(parent, text, width, height, variant)
	local b = CreateFrame("Button", nil, parent)
	height = height or Style.SIZE.button
	b:SetSize(width or 100, height)
	b.variant = variant or "default"
	b.textInset = b.variant == "choice" and 12 or 4
	b.bg = Style.Solid(b, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.edges = Style.Edge(b, "BORDER")
	b.label = b:CreateFontString(nil, "OVERLAY", Style.Font(height < Style.SIZE.button and "GameFontHighlightSmall"
		or "GameFontHighlight"))
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

--- A small square button with a text glyph ("?", "x", "<", ">").
function Widgets.IconButton(parent, glyph, title, text)
	local b = Widgets.Button(parent, glyph, Style.SIZE.icon, Style.SIZE.icon, "ghost")
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
		local b = Widgets.Button(parent, item.label, each - 2, height or Style.SIZE.segment)
		b.segmentId = item.id
		b:SetScript("OnClick", function() onSelect(item.id) end)
		seg.buttons[i] = b
		if i > 1 then
			b:SetPoint("LEFT", seg.buttons[i - 1], "RIGHT", 2, 0)
		end
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
-- or any of its buttons highlights the whole unit (lighter fill and an
-- accent bar on the left). SetPlain(true) makes the frame an unboxed line,
-- for headings and hints in lists that reuse rows.
Widgets.ENTRY = { pad = 8, gap = 6 }

--- An entry panel (a "card"). Paints itself; :SetRowHover(on), :SetPlain(on).
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
		Style.Color(c.bg, c.hover and theme.surfaceHover or theme.surface, boxed and 1 or 0)
		c.edges:Paint(c.highlight and theme.accent or theme.edge, boxed and 1 or 0)
		c.bar:SetShown(boxed and (c.hover or c.highlight) and true or false)
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

--- A small button showing Public / Private / Secret in its fixed colour.
-- Clicking cycles the level and calls onChange(newLevel); the caller saves.
function Widgets.VisibilityButton(parent, onChange)
	local button = Widgets.Button(parent, "Private", 72, Style.SIZE.compact, "ghost")
	button.level = "private"
	function button:SetLevel(level)
		self.level = level
		self:SetText(Themes.VISIBILITY_LABELS[level] or level)
		self.textColor = Themes.VISIBILITY_COLORS[level] or Themes.VISIBILITY_COLORS.private
		Style.Repaint(self)
	end
	button:SetLevel("private")
	button:SetScript("OnClick", function(self)
		onChange(CYCLE[self.level] or "private", self)
	end)
	Widgets.Tooltip(button, "Visibility", Widgets.VISIBILITY_HELP)
	return button
end

--- Text input --------------------------------------------------------------------

-- Field states, shared by one-line inputs and text areas. Focus is shown by
-- a lighter fill, an accent edge and a 3 px bar on the left; an invalid
-- field uses the danger colour for both, so focus and errors are visible
-- without relying on colour alone (the error message also starts with "!").
local function paintField(box, theme, fill, edges, bar, edit)
	local state = box.invalid and theme.danger or box.focused and theme.accent or nil
	Style.Color(fill, box.focused and theme.surfaceHover or theme.surface)
	edges:Paint(state or theme.edge, 1)
	bar:SetShown(state ~= nil)
	if state then Style.Color(bar, state) end
	edit:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
end

local function focusBar(frame)
	local bar = Style.Solid(frame, "ARTWORK")
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", 0, 0)
	bar:SetWidth(3)
	bar:Hide()
	return bar
end

local function inputFrame(edit)
	edit.bg = Style.Solid(edit, "BACKGROUND", -1)
	edit.bg:SetAllPoints(edit)
	edit.edges = Style.Edge(edit, "BORDER")
	edit.focusBar = focusBar(edit)
	hook(edit, "OnEditFocusGained", function(self) self.focused = true; Style.Repaint(self) end)
	hook(edit, "OnEditFocusLost", function(self) self.focused = nil; Style.Repaint(self) end)
	return Style.Register(edit, function(e, theme)
		paintField(e, theme, e.bg, e.edges, e.focusBar, e)
	end)
end

--- A one-line input on a surface well (no FrameXML template).
function Widgets.EditLine(parent, maxBytes)
	local edit = CreateFrame("EditBox", Widgets.NextName("Line"), parent)
	edit:SetAutoFocus(false)
	edit:SetHeight(Style.SIZE.input)
	edit:SetFontObject(Style.FontObject("ChatFontNormal") or ChatFontNormal)
	edit:SetTextInsets(6, 6, 0, 0)
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
	edit:SetTextInsets(4, 4, 4, 4)
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
	local fs = Widgets.Label(region:GetParent(), "GameFontHighlightSmall", true, "danger")
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
	d.cancel = Widgets.Button(d, "Cancel", 100, 22)
	d.cancel:SetPoint("BOTTOMRIGHT", -16, 16)
	d.cancel:SetScript("OnClick", function() d:Hide() end)
	d.accept = Widgets.Button(d, "Confirm", 120, 22, "danger")
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

--- Formats a stored timestamp for display (WoW's date(); 0 means unknown).
function Widgets.FormatDate(timestamp)
	if type(timestamp) ~= "number" or timestamp <= 0 then
		return "Unknown date"
	end
	return date("%d %b %Y, %H:%M", timestamp)
end
