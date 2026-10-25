-- A small window for copying export text and pasting import text.
-- Chat cannot hold long text, so exports and imports go through this box.
-- Uses only long-standing FrameXML templates; verified at L3 only.
local _, ns = ...

local CopyBox = {}
ns.CopyBox = CopyBox

local FRAME_NAME = "DawnwardChroniclesCopyBox"
local frame

local function setButton(button, text, onClick)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:Enable()
	button:Show()
end

local function build()
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	frame = CreateFrame("Frame", FRAME_NAME, UIParent, template)
	frame:SetSize(560, 380)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", 0, -18)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local scroll = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 22, -44)
	scroll:SetPoint("BOTTOMRIGHT", -42, 92)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(490)
	edit:SetScript("OnEscapePressed", function() frame:Hide() end)
	scroll:SetScrollChild(edit)
	frame.editBox = edit

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.status:SetPoint("BOTTOMLEFT", 22, 56)
	frame.status:SetPoint("BOTTOMRIGHT", -22, 56)
	frame.status:SetJustifyH("LEFT")

	frame.primary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.primary:SetSize(130, 22)
	frame.primary:SetPoint("BOTTOMRIGHT", -22, 22)

	frame.secondary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.secondary:SetSize(130, 22)
	frame.secondary:SetPoint("RIGHT", frame.primary, "LEFT", -8, 0)

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
	return frame
end

--- Shows read-only export text, selected for copying.
function CopyBox.ShowExport(title, text)
	local f = open(title)
	local edit = f.editBox
	edit:SetText(text)
	edit:SetFocus()
	edit:HighlightText()
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
