-- The journal window: one shared layout with three sections (Journal,
-- Character, Story) and a gear button for the small settings panel.
-- See docs/UI_DIRECTION.md.
--
-- Layering: MEDIUM strata and toplevel, like the game's own panels, so game
-- dialogs (DIALOG) and tooltips stay above it. The export/import window uses
-- FULLSCREEN_DIALOG and therefore opens on top of this one.
--
-- Sections register themselves (MainWindow.RegisterSection) and receive a
-- "view" on every refresh: { ctx, char, theme, setStatus(text), refresh() }.
local _, ns = ...
local Widgets, Themes, Actions = ns.Widgets, ns.Themes, ns.Actions

local MainWindow = {}
ns.MainWindow = MainWindow

local FRAME_NAME = "DawnwardChroniclesJournal"
MainWindow.STRATA = "MEDIUM"

-- Sizes in UI units. 620 x 520 fits the smallest UIParent the game allows
-- (about 668 units tall at the maximum UI scale).
MainWindow.LAYOUT = {
	width = 620,
	height = 520,
	borderInset = 8,
	pad = 20,
	titleTop = 18,        -- title baseline below the top edge
	tabTop = 46,          -- tab row top, below the top edge
	tabHeight = 24,
	tabWidth = 120,
	tabGap = 6,
	iconSize = 24,
	contentTop = 80,      -- content area top, below the top edge
	contentBottom = 40,   -- content area bottom, above the bottom edge
	statusBottom = 14,
	statusHeight = 20,
}

--- Pure layout maths: rectangles relative to the window's bottom-left corner.
function MainWindow.ComputeLayout(L)
	local r = {}
	r.background = { left = L.borderInset, right = L.width - L.borderInset,
		bottom = L.borderInset, top = L.height - L.borderInset }
	r.title = { left = L.pad, right = L.width - L.pad - 2 * L.iconSize - 16,
		bottom = L.height - L.titleTop - 18, top = L.height - L.titleTop + 2 }
	r.tabs = {}
	for i = 1, 3 do
		local left = L.pad + (i - 1) * (L.tabWidth + L.tabGap)
		r.tabs[i] = { left = left, right = left + L.tabWidth,
			bottom = L.height - L.tabTop - L.tabHeight, top = L.height - L.tabTop }
	end
	r.gear = { left = L.width - L.pad - L.iconSize, right = L.width - L.pad,
		bottom = L.height - L.tabTop - L.tabHeight, top = L.height - L.tabTop - L.tabHeight + L.iconSize }
	r.content = { left = L.pad, right = L.width - L.pad, bottom = L.contentBottom, top = L.height - L.contentTop }
	r.status = { left = L.pad, right = L.width - L.pad,
		bottom = L.statusBottom, top = L.statusBottom + L.statusHeight }
	return r
end

local sections = {}
local frame, layout, currentSection, settingsOpen, appliedTheme

--- def = { id, label, order, create(parent) -> section }
-- section: { frame, Refresh(self, view), ApplyTheme(self, theme), OnHide(self)? }
function MainWindow.RegisterSection(def)
	sections[#sections + 1] = def
	table.sort(sections, function(a, b) return a.order < b.order end)
end

function MainWindow.Sections()
	return sections
end

local function ctx()
	return ns.ctx
end

local function setStatus(text)
	if frame then
		frame.status:SetText(text or "")
	end
end

local function tabColors(theme)
	for _, tab in ipairs(frame.tabs) do
		local selected = (not settingsOpen) and tab.id == currentSection
		Widgets.TextColor(tab.label, selected and theme.accent or theme.muted)
		tab.underline:SetShown(selected)
		Widgets.SetColor(tab.underline, theme.accent)
	end
end

local function applyTheme(theme)
	appliedTheme = theme
	Widgets.SetColor(frame.background, theme.background)
	Widgets.SetColor(frame.contentWell, theme.panel)
	if frame.SetBackdropBorderColor then
		frame:SetBackdropBorderColor(theme.border[1], theme.border[2], theme.border[3], 1)
	end
	Widgets.TextColor(frame.title, theme.accent)
	Widgets.TextColor(frame.status, theme.muted)
	tabColors(theme)
	for _, def in ipairs(sections) do
		if def.instance and def.instance.ApplyTheme then
			def.instance:ApplyTheme(theme)
		end
	end
	if MainWindow.settings and MainWindow.settings.ApplyTheme then
		MainWindow.settings:ApplyTheme(theme)
	end
end

local SIM_COLOR = Themes.VISIBILITY_COLORS.secret
local SIM_SUFFIX = string.format("  |cff%02x%02x%02x(simulation - test data)|r",
	math.floor(SIM_COLOR[1] * 255), math.floor(SIM_COLOR[2] * 255), math.floor(SIM_COLOR[3] * 255))

--- Window title. Stored names never contain "|" (Util.CleanText), so adding
-- our own colour code for the simulation marker is safe.
function MainWindow.TitleFor(char, simulation)
	local name = char and char.fields.name and char.fields.name.value
	local title = name and (name .. "'s Journal") or "Dawnward Chronicles"
	return simulation and (title .. SIM_SUFFIX) or title
end

--- Width of the content area. Sections size their text from this rather than
-- GetWidth(), which the client may report as 0 before the first layout pass.
function MainWindow.ContentWidth()
	local L = MainWindow.LAYOUT
	return L.width - 2 * L.pad
end

local function makeView(theme, char)
	return {
		ctx = ctx(),
		char = char,
		theme = theme,
		contentWidth = MainWindow.ContentWidth(),
		setStatus = setStatus,
		refresh = MainWindow.Refresh,
	}
end

--- Re-reads data and redraws the visible parts. Cheap when hidden.
function MainWindow.Refresh()
	if not frame or not frame:IsShown() or not ctx() then
		return
	end
	local char = Actions.Character(ctx())
	local theme = Actions.ThemeOf(char)
	if theme ~= appliedTheme then
		applyTheme(theme)
	end
	frame.title:SetText(MainWindow.TitleFor(char, ctx().store:IsSimulation()))
	local view = makeView(theme, char)
	if settingsOpen and MainWindow.settings then
		MainWindow.settings:Refresh(view)
		return
	end
	for _, def in ipairs(sections) do
		if def.id == currentSection and def.instance then
			def.instance:Refresh(view)
		end
	end
end

local function showSection(id)
	settingsOpen = false
	if MainWindow.settings then
		MainWindow.settings.frame:Hide()
	end
	currentSection = id
	for _, def in ipairs(sections) do
		if def.instance then
			if def.id == id then
				def.instance.frame:Show()
			else
				def.instance.frame:Hide()
			end
		end
	end
	setStatus("")
	if appliedTheme then
		tabColors(appliedTheme)
	end
	MainWindow.Refresh()
end

function MainWindow.Select(id)
	if not frame then
		return
	end
	showSection(id)
end

function MainWindow.CurrentSection()
	return settingsOpen and "settings" or currentSection
end

function MainWindow.ToggleSettings()
	if not frame or not MainWindow.settings then
		return
	end
	if settingsOpen then
		showSection(currentSection)
		return
	end
	settingsOpen = true
	for _, def in ipairs(sections) do
		if def.instance then
			def.instance.frame:Hide()
		end
	end
	MainWindow.settings.frame:Show()
	setStatus("")
	if appliedTheme then
		tabColors(appliedTheme)
	end
	MainWindow.Refresh()
end

local function restorePosition()
	frame:ClearAllPoints()
	local position = ctx() and Actions.WindowPosition(ctx())
	if position then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", position.left, position.top)
	else
		frame:SetPoint("CENTER")
	end
end

local function savePosition()
	frame:StopMovingOrSizing()
	-- We remember the position ourselves; keep the client's layout cache out of it.
	if frame.SetUserPlaced then
		frame:SetUserPlaced(false)
	end
	if ctx() then
		Actions.SaveWindowPosition(ctx(), frame:GetLeft(), frame:GetTop())
	end
end

local function buildTab(index, def, r)
	local tab = CreateFrame("Button", nil, frame)
	Widgets.Place(tab, frame, r.tabs[index])
	tab.id = def.id
	tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tab.label:SetPoint("CENTER", 0, 1)
	tab.label:SetText(def.label)
	tab.underline = Widgets.Solid(tab, "ARTWORK")
	tab.underline:SetHeight(2)
	tab.underline:SetPoint("BOTTOMLEFT", 8, 0)
	tab.underline:SetPoint("BOTTOMRIGHT", -8, 0)
	tab:SetScript("OnClick", function() showSection(def.id) end)
	return tab
end

local function build()
	layout = MainWindow.LAYOUT
	local r = MainWindow.ComputeLayout(layout)
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	frame = CreateFrame("Frame", FRAME_NAME, UIParent, template)
	frame:SetSize(layout.width, layout.height)
	frame:SetFrameStrata(MainWindow.STRATA)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", savePosition)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	frame.background = Widgets.Solid(frame, "BACKGROUND", -8)
	Widgets.Place(frame.background, frame, r.background)
	frame.contentWell = Widgets.Solid(frame, "BACKGROUND", -7)
	Widgets.Place(frame.contentWell, frame, r.content)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	Widgets.Place(frame.title, frame, r.title)
	frame.title:SetJustifyH("LEFT")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local gear = CreateFrame("Button", nil, frame)
	Widgets.Place(gear, frame, r.gear)
	gear:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
	gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	gear:SetScript("OnClick", MainWindow.ToggleSettings)
	Widgets.Tooltip(gear, "Settings", "Theme, backup and import, simulation mode, Total RP 3 status.")
	frame.gear = gear

	frame.content = CreateFrame("Frame", nil, frame)
	Widgets.Place(frame.content, frame, r.content)

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	Widgets.Place(frame.status, frame, r.status)
	frame.status:SetJustifyH("LEFT")
	frame.status:SetWordWrap(false)

	frame.tabs = {}
	for index, def in ipairs(sections) do
		frame.tabs[index] = buildTab(index, def, r)
		def.instance = def.create(frame.content)
		def.instance.frame:SetAllPoints(frame.content)
		def.instance.frame:Hide()
	end
	if MainWindow.createSettings then
		MainWindow.settings = MainWindow.createSettings(frame.content)
		MainWindow.settings.frame:SetAllPoints(frame.content)
		MainWindow.settings.frame:Hide()
	end

	frame:SetScript("OnHide", function()
		for _, def in ipairs(sections) do
			if def.instance and def.instance.OnHide then
				def.instance:OnHide()
			end
		end
	end)

	tinsert(UISpecialFrames, FRAME_NAME)
	frame:Hide()
	currentSection = sections[1] and sections[1].id
end

function MainWindow.Show()
	if not frame then
		build()
	end
	restorePosition()
	frame:Show()
	frame:Raise()
	showSection(currentSection)
end

function MainWindow.Hide()
	if frame then
		frame:Hide()
	end
end

function MainWindow.Toggle()
	if frame and frame:IsShown() then
		MainWindow.Hide()
	else
		MainWindow.Show()
	end
end

function MainWindow.IsShown()
	return frame ~= nil and frame:IsShown()
end

--- For tests and diagnostics only.
function MainWindow.GetFrame()
	return frame
end

function MainWindow.SetStatus(text)
	setStatus(text)
end
