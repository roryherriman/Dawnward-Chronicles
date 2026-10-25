-- Small shared building blocks for the journal window. Only long-standing
-- FrameXML templates are used; everything else is plain frames, fonts and
-- solid colour textures, so themes need no art files.
local _, ns = ...
local Themes = ns.Themes

local Widgets = {}
ns.Widgets = Widgets

local nameCounter = 0
--- Unique global names for templates that need one (scroll frames, input boxes).
function Widgets.NextName(prefix)
	nameCounter = nameCounter + 1
	return "DawnwardChronicles" .. prefix .. nameCounter
end

function Widgets.Solid(parent, layer, sublevel)
	return parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
end

function Widgets.SetColor(texture, color, alpha)
	local a = alpha or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(color[1], color[2], color[3], a)
	else
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
		texture:SetVertexColor(color[1], color[2], color[3], a)
	end
end

function Widgets.TextColor(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
end

--- Anchors region to the rectangle rect = { left, right, bottom, top },
-- measured from anchor's bottom-left corner.
function Widgets.Place(region, anchor, rect)
	region:ClearAllPoints()
	region:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", rect.left, rect.bottom)
	region:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", rect.right, rect.top)
end

function Widgets.Label(parent, font, wrap)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(wrap and true or false)
	if wrap and fs.SetNonSpaceWrap then
		fs:SetNonSpaceWrap(true)
	end
	return fs
end

function Widgets.Button(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 100, height or 22)
	button:SetText(text)
	return button
end

local function showTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title)
	if text then
		GameTooltip:AddLine(text, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

function Widgets.Tooltip(frame, title, text)
	frame:SetScript("OnEnter", function(self) showTooltip(self, title, text) end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--- Visibility -------------------------------------------------------------------

local CYCLE = { private = "public", public = "secret", secret = "private" }

Widgets.VISIBILITY_HELP = "Public: may be shared (share exports, and Total RP 3 in a later version).\n"
	.. "Private: only you; included in your personal backups.\n"
	.. "Secret: only you; left out of backups unless you ask.\nClick to change."

--- A small button showing Public / Private / Secret. Clicking cycles the level
-- and calls onChange(newLevel); the caller saves and refreshes.
function Widgets.VisibilityButton(parent, onChange)
	local button = Widgets.Button(parent, "Private", 72, 20)
	button.level = "private"
	function button:SetLevel(level)
		self.level = level
		self:SetText(Themes.VISIBILITY_LABELS[level] or level)
		local fs = self:GetFontString()
		if fs then
			Widgets.TextColor(fs, Themes.VISIBILITY_COLORS[level] or Themes.VISIBILITY_COLORS.private)
		end
	end
	button:SetScript("OnClick", function(self)
		onChange(CYCLE[self.level] or "private", self)
	end)
	Widgets.Tooltip(button, "Visibility", Widgets.VISIBILITY_HELP)
	return button
end

--- Text input ---------------------------------------------------------------------

function Widgets.EditLine(parent, maxBytes)
	local edit = CreateFrame("EditBox", Widgets.NextName("Line"), parent, "InputBoxTemplate")
	edit:SetAutoFocus(false)
	edit:SetHeight(20)
	edit:SetMaxBytes(maxBytes or 100)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return edit
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

--- Multi-line text area on an opaque well. Returns { frame, scroll, edit, well }.
-- Place area.frame; the text inside follows its size.
function Widgets.TextArea(parent, maxBytes)
	local area = {}
	area.frame = CreateFrame("Frame", nil, parent)
	area.well = Widgets.Solid(area.frame, "BACKGROUND", -6)
	area.well:SetAllPoints(area.frame)

	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("Scroll"), area.frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -26, 4)
	area.scroll = scroll

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxBytes(maxBytes or 2000)
	edit:SetFontObject(ChatFontNormal)
	edit:SetTextInsets(4, 4, 4, 4)
	edit:SetWidth(200)
	edit:SetHeight(100)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnCursorChanged", function(_, _, y, _, h) followCursor(scroll, y, h) end)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnSizeChanged", function(_, width, height)
		edit:SetWidth(width)
		edit:SetHeight(height)
	end)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	area.edit = edit
	area.followCursor = followCursor
	return area
end

--- Confirmation ---------------------------------------------------------------------

local POPUP = "DAWNWARD_CHRONICLES_CONFIRM"

--- Asks the player to confirm a destructive action with the standard dialog.
function Widgets.Confirm(text, acceptLabel, onAccept)
	StaticPopupDialogs[POPUP] = {
		text = "%s",
		button1 = acceptLabel or "Confirm",
		button2 = "Cancel",
		OnAccept = function(_, data) data() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show(POPUP, text, nil, onAccept)
end

--- Formats a stored timestamp for display (WoW's date(); 0 means unknown).
function Widgets.FormatDate(timestamp)
	if type(timestamp) ~= "number" or timestamp <= 0 then
		return "Unknown date"
	end
	return date("%d %b %Y, %H:%M", timestamp)
end
