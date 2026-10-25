-- A small window for copying export text and pasting import text.
-- Chat cannot hold long text, so exports and imports go through this box.
-- Uses only long-standing FrameXML templates; verified at L3 only.
--
-- Readability rules (the window is often opened over other addons, such as
-- Total RP 3, whose popups use the DIALOG strata):
--  * FULLSCREEN_DIALOG strata, toplevel, raised on every open
--  * fully opaque background; the stock dialog background is translucent
--  * every region placed from one layout table, so text, status line and
--    buttons can never overlap (checked by tests/spec/ui_copybox_spec.lua)
local _, ns = ...

local CopyBox = {}
ns.CopyBox = CopyBox

local FRAME_NAME = "DawnwardChroniclesCopyBox"
local frame

CopyBox.STRATA = "FULLSCREEN_DIALOG"

-- All sizes in pixels. Regions are laid out bottom-up from the buttons.
CopyBox.LAYOUT = {
	width = 600,
	height = 440,
	borderInset = 8,     -- background starts inside the border art
	pad = 24,            -- content margin from the frame edge
	titleTop = 18,       -- title baseline offset from the top
	contentTop = 48,     -- text well starts this far below the top
	buttonBottom = 20,
	buttonHeight = 22,
	buttonWidth = 130,
	buttonGap = 8,
	statusHeight = 40,   -- room for three lines of small text
	gap = 10,            -- vertical space between regions
	wellPad = 6,         -- dark well around the scrolling text
	scrollBarWidth = 26, -- UIPanelScrollFrameTemplate draws its bar outside the frame
	textInset = 6,
	minTextHeight = 160,
}

CopyBox.COLORS = {
	background = { 0.06, 0.06, 0.08, 1 },
	well = { 0, 0, 0, 1 },
}

--- Pure layout maths: rectangles relative to the frame's bottom-left corner.
function CopyBox.ComputeLayout(L)
	local r = {}
	r.buttons = { bottom = L.buttonBottom, top = L.buttonBottom + L.buttonHeight }
	r.status = {
		left = L.pad, right = L.width - L.pad,
		bottom = r.buttons.top + L.gap,
		top = r.buttons.top + L.gap + L.statusHeight,
	}
	r.well = {
		left = L.pad - L.wellPad,
		right = L.width - L.pad + L.wellPad,
		bottom = r.status.top + L.gap,
		top = L.height - L.contentTop + L.wellPad,
	}
	r.scroll = {
		left = L.pad,
		right = L.width - L.pad - L.scrollBarWidth,
		bottom = r.well.bottom + L.wellPad,
		top = L.height - L.contentTop,
	}
	r.background = {
		left = L.borderInset, right = L.width - L.borderInset,
		bottom = L.borderInset, top = L.height - L.borderInset,
	}
	r.editWidth = r.scroll.right - r.scroll.left
	r.textHeight = r.scroll.top - r.scroll.bottom
	return r
end

local function setButton(button, text, onClick)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:Enable()
	button:Show()
end

local function place(region, rect)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", rect.left, rect.bottom)
	region:SetPoint("TOPRIGHT", frame, "BOTTOMLEFT", rect.right, rect.top)
end

local function solidTexture(layer, sublevel, color)
	local tex = frame:CreateTexture(nil, layer, nil, sublevel)
	if tex.SetColorTexture then
		tex:SetColorTexture(color[1], color[2], color[3], color[4])
	else
		tex:SetTexture("Interface\\Buttons\\WHITE8X8")
		tex:SetVertexColor(color[1], color[2], color[3], color[4])
	end
	return tex
end

-- Keeps the caret visible while typing or moving through long text.
local function followCursor(scroll, _, y, _, cursorHeight)
	local offset = scroll:GetVerticalScroll()
	local visible = scroll:GetHeight()
	y = -y
	if y < offset then
		scroll:SetVerticalScroll(y)
	elseif y + cursorHeight > offset + visible then
		scroll:SetVerticalScroll(y + cursorHeight - visible)
	end
end

local function build()
	local L = CopyBox.LAYOUT
	local r = CopyBox.ComputeLayout(L)
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	frame = CreateFrame("Frame", FRAME_NAME, UIParent, template)
	frame:SetSize(L.width, L.height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata(CopyBox.STRATA)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		-- Border art only: the stock dialog background texture is translucent.
		frame:SetBackdrop({
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end

	frame.background = solidTexture("BACKGROUND", -8, CopyBox.COLORS.background)
	place(frame.background, r.background)
	frame.well = solidTexture("BACKGROUND", -7, CopyBox.COLORS.well)
	place(frame.well, r.well)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", 0, -L.titleTop)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local scroll = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll", frame, "UIPanelScrollFrameTemplate")
	place(scroll, r.scroll)
	frame.scroll = scroll

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(ChatFontNormal)
	edit:SetTextInsets(L.textInset, L.textInset, L.textInset, L.textInset)
	edit:SetWidth(r.editWidth)
	edit:SetHeight(r.textHeight)
	edit:SetScript("OnEscapePressed", function() frame:Hide() end)
	edit:SetScript("OnCursorChanged", function(_, x, y, w, h) followCursor(scroll, x, y, w, h) end)
	scroll:SetScrollChild(edit)
	-- Keep the text width matched to the visible area, and let a click
	-- anywhere in the well focus the text.
	scroll:SetScript("OnSizeChanged", function(_, width) edit:SetWidth(width) end)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	frame.editBox = edit

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	place(frame.status, r.status)
	frame.status:SetJustifyH("LEFT")
	frame.status:SetJustifyV("TOP")
	frame.status:SetWordWrap(true)

	frame.primary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.primary:SetSize(L.buttonWidth, L.buttonHeight)
	frame.primary:SetPoint("BOTTOMRIGHT", -L.pad, L.buttonBottom)

	frame.secondary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.secondary:SetSize(L.buttonWidth, L.buttonHeight)
	frame.secondary:SetPoint("RIGHT", frame.primary, "LEFT", -L.buttonGap, 0)

	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and frame.onUserEdit then
			frame.onUserEdit(self)
		end
	end)

	-- Escape closes the window like other dialogs.
	tinsert(UISpecialFrames, FRAME_NAME)
	frame:Hide()
end

local function open(title)
	if not frame then
		build()
	end
	frame.title:SetText(title)
	frame.status:SetText("")
	frame.onUserEdit = nil
	frame:Show()
	frame:Raise()
	return frame
end

--- Shows read-only export text, selected for copying.
function CopyBox.ShowExport(title, text)
	local f = open(title)
	local edit = f.editBox
	edit:SetText(text)
	edit:SetFocus()
	edit:SetCursorPosition(0)
	edit:HighlightText()
	f.scroll:SetVerticalScroll(0)
	-- Keep the export intact: undo any typing and reselect.
	f.onUserEdit = function(box)
		box:SetText(text)
		box:HighlightText()
	end
	f.status:SetText("Press Ctrl+C to copy, then Escape to close.")
	setButton(f.primary, "Select all", function()
		edit:SetFocus()
		edit:HighlightText()
	end)
	f.secondary:Hide()
end

--- Shows an empty box for pasting.
-- check(text) -> ok, message   validates and stages the import
-- confirm()                     applies the staged import
-- invalidate()                  called when the text changes after a check
function CopyBox.ShowImport(check, confirm, invalidate)
	local f = open("Import a Dawnward Chronicles backup")
	local edit = f.editBox
	edit:SetText("")
	edit:SetFocus()
	f.scroll:SetVerticalScroll(0)
	f.status:SetText("Paste a backup (Ctrl+V), then press Check.")
	f.secondary:Hide()

	f.onUserEdit = function()
		if f.secondary:IsShown() then
			f.secondary:Hide()
			f.status:SetText("Text changed - press Check again.")
			invalidate()
		end
	end
	setButton(f.primary, "Check", function()
		local ok, message = check(edit:GetText())
		f.status:SetText(message or "")
		if ok then
			setButton(f.secondary, "Import", function()
				confirm()
				f:Hide()
			end)
		else
			f.secondary:Hide()
		end
	end)
end

--- For tests and diagnostics only.
function CopyBox.GetFrame()
	return frame
end
