-- The journal window: one shared layout with four sections (Journal,
-- Character, Story, Chronicle), a header with the guide (?) and settings
-- buttons, and a status footer. See docs/design/UI_DESIGN_V06.md.
--
-- Layering: MEDIUM strata and toplevel, like the game's own panels, so game
-- dialogs (DIALOG) and tooltips stay above it. The export/import window uses
-- FULLSCREEN_DIALOG and therefore opens on top of this one.
--
-- Sections register themselves (MainWindow.RegisterSection) and receive a
-- "view" on every refresh: { ctx, char, theme, setStatus(text), refresh() }.
local _, ns = ...
local Widgets, Themes, Actions, Style = ns.Widgets, ns.Themes, ns.Actions, ns.Style

local MainWindow = {}
ns.MainWindow = MainWindow

local FRAME_NAME = "DawnwardChroniclesJournal"
MainWindow.STRATA = "MEDIUM"

-- Sizes in UI units. 640 x 540 fits the smallest UIParent the game allows
-- (about 668 units tall at the maximum UI scale); on smaller screens the
-- window scales itself down (Style.FitScale).
MainWindow.LAYOUT = {
	width = 640,
	height = 540,
	borderInset = 4,
	pad = 20,
	emblemSize = 34,
	headerTop = 14,       -- emblem and title block top, below the top edge
	tabTop = 58,          -- navigation row top, below the top edge
	tabHeight = 28,
	tabWidth = 112,
	tabCount = 4,
	tabGap = 4,
	iconSize = 22,
	iconGap = 6,
	contentTop = 92,      -- content area top, below the top edge
	contentBottom = 36,   -- content area bottom, above the bottom edge
	statusBottom = 10,
	statusHeight = 20,
}

--- Pure layout maths: rectangles relative to the window's bottom-left corner.
function MainWindow.ComputeLayout(L)
	local r = {}
	r.background = { left = L.borderInset, right = L.width - L.borderInset,
		bottom = L.borderInset, top = L.height - L.borderInset }
	local top = L.height - L.headerTop
	r.emblem = { left = L.pad, right = L.pad + L.emblemSize, bottom = top - L.emblemSize, top = top }
	r.close = { left = L.width - L.pad - L.iconSize, right = L.width - L.pad, bottom = top - L.iconSize, top = top }
	r.gear = { left = r.close.left - L.iconGap - L.iconSize, right = r.close.left - L.iconGap,
		bottom = r.close.bottom, top = top }
	r.help = { left = r.gear.left - L.iconGap - L.iconSize, right = r.gear.left - L.iconGap,
		bottom = r.close.bottom, top = top }
	r.eyebrow = { left = r.emblem.right + 12, right = r.help.left - 12, bottom = top - 12, top = top }
	r.title = { left = r.emblem.right + 12, right = r.help.left - 12, bottom = top - 34, top = top - 14 }
	r.tabs = {}
	for i = 1, L.tabCount do
		local left = L.pad + (i - 1) * (L.tabWidth + L.tabGap)
		r.tabs[i] = { left = left, right = left + L.tabWidth,
			bottom = L.height - L.tabTop - L.tabHeight, top = L.height - L.tabTop }
	end
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

local function paintTab(tab, theme)
	local selected = tab.selected
	Style.TextColor(tab.label, (selected or tab.hover) and theme.accent or theme.muted)
	tab.underline:SetShown(selected and true or false)
	Style.Color(tab.underline, theme.accent)
end

local function tabColors()
	for _, tab in ipairs(frame.tabs) do
		tab.selected = (not settingsOpen) and tab.id == currentSection
		Style.Repaint(tab)
	end
end

local function applyTheme(theme)
	appliedTheme = theme
	Style.Apply(theme)
	for _, def in ipairs(sections) do
		if def.instance and def.instance.ApplyTheme then
			def.instance:ApplyTheme(theme)
		end
	end
	if MainWindow.settings and MainWindow.settings.ApplyTheme then
		MainWindow.settings:ApplyTheme(theme)
	end
	if MainWindow.guide then
		MainWindow.guide:ApplyTheme(theme)
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
	if theme ~= appliedTheme or Style.Current() ~= theme then
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
		tabColors()
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
		tabColors()
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
	tab.underline:SetPoint("BOTTOMLEFT", 10, 0)
	tab.underline:SetPoint("BOTTOMRIGHT", -10, 0)
	tab:SetScript("OnClick", function() showSection(def.id) end)
	tab:SetScript("OnEnter", function(self) self.hover = true; Style.Repaint(self) end)
	tab:SetScript("OnLeave", function(self) self.hover = nil; Style.Repaint(self) end)
	return Style.Register(tab, paintTab)
end

-- A square header button holding a desaturated game icon, tinted by the theme.
local function iconButton(rect, icon, title, text, onClick)
	local b = CreateFrame("Button", nil, frame)
	Widgets.Place(b, frame, rect)
	b.bg = Widgets.Solid(b, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.edges = Style.Edge(b, "BORDER")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	if icon then
		b.icon:SetTexture(icon)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
	else
		b.glyph = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.glyph:SetPoint("CENTER", 0, 0)
		b.glyph:SetText("X")
	end
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self) self.hover = true; Style.Repaint(self) end)
	b:SetScript("OnLeave", function(self) self.hover = nil; Style.Repaint(self) end)
	Widgets.Tooltip(b, title, text)
	return Style.Register(b, function(self, theme)
		local tint = self.hover and theme.accent or theme.muted
		Style.Color(self.bg, theme.surfaceHover, self.hover and 1 or 0)
		self.edges:Paint(self.hover and theme.accent or theme.edge, 1)
		if self.glyph then
			Style.TextColor(self.glyph, tint)
		else
			self.icon:SetVertexColor(tint[1], tint[2], tint[3])
		end
	end)
end

local function build()
	layout = MainWindow.LAYOUT
	local r = MainWindow.ComputeLayout(layout)
	frame = CreateFrame("Frame", FRAME_NAME, UIParent)
	frame:SetSize(layout.width, layout.height)
	frame:SetFrameStrata(MainWindow.STRATA)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", savePosition)
	Style.Chrome(frame, "background")
	frame.background = frame.chrome.fill
	frame.contentWell = Style.Fill(frame, "panel", "BACKGROUND", -7)
	Widgets.Place(frame.contentWell, frame, r.content)
	-- Dividers under the navigation and above the status line.
	frame.navLine = Widgets.Divider(frame)
	frame.navLine:SetPoint("TOPLEFT", layout.pad, -(layout.contentTop - 1))
	frame.navLine:SetPoint("TOPRIGHT", -layout.pad, -(layout.contentTop - 1))
	frame.footLine = Widgets.Divider(frame)
	frame.footLine:SetPoint("BOTTOMLEFT", layout.pad, layout.contentBottom)
	frame.footLine:SetPoint("BOTTOMRIGHT", -layout.pad, layout.contentBottom)

	-- Header: emblem, eyebrow, title, then ?, settings and close.
	frame.emblem = frame:CreateTexture(nil, "ARTWORK")
	Widgets.Place(frame.emblem, frame, r.emblem)
	frame.emblem:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	frame.emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.emblemFrame = CreateFrame("Frame", nil, frame)
	Widgets.Place(frame.emblemFrame, frame, { left = r.emblem.left - 2, right = r.emblem.right + 2,
		bottom = r.emblem.bottom - 2, top = r.emblem.top + 2 })
	frame.emblemEdge = Style.Edge(frame.emblemFrame, "OVERLAY")
	Style.Register(frame.emblemEdge, function(e, theme) e:Paint(theme.ornament, 1) end)

	frame.eyebrow = Widgets.Label(frame, nil, false, "eyebrow")
	Widgets.Place(frame.eyebrow, frame, r.eyebrow)
	frame.eyebrow:SetText("DAWNWARD CHRONICLES")
	frame.title = Widgets.Label(frame, "GameFontNormalLarge", false, "title")
	Widgets.Place(frame.title, frame, r.title)

	frame.close = iconButton(r.close, nil, "Close", "Close the journal (Escape also works).", function()
		MainWindow.Hide()
	end)
	frame.gear = iconButton(r.gear, "Interface\\Icons\\INV_Misc_Gear_01", "Settings",
		"Theme, story moments, backup and import, simulation mode, Total RP 3 status.", function()
			MainWindow.ToggleSettings()
		end)
	frame.help = iconButton(r.help, "Interface\\Icons\\INV_Misc_QuestionMark", "Guide and help",
		"A short tour of Dawnward, and a search for any feature or command.", function()
			if MainWindow.guide and MainWindow.guide:IsOpen() then
				MainWindow.guide:Close()
			elseif MainWindow.guide then
				MainWindow.guide:Show(1)
			end
		end)

	frame.content = CreateFrame("Frame", nil, frame)
	Widgets.Place(frame.content, frame, r.content)

	frame.status = Widgets.Label(frame, "GameFontHighlightSmall", false, "muted")
	Widgets.Place(frame.status, frame, r.status)
	frame.status:SetJustifyV("MIDDLE")

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
	if MainWindow.createGuide then
		MainWindow.guide = MainWindow.createGuide(frame.content)
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

--- Called before the journal opens; returns true when something else (the
-- first-time setup wizard) takes the player's attention instead.
MainWindow.BeforeShow = nil

--- Opens the journal. force skips BeforeShow (the wizard's own Finish).
function MainWindow.Show(force)
	if not force and MainWindow.BeforeShow and MainWindow.BeforeShow() then
		return
	end
	if not frame then
		build()
	end
	restorePosition()
	frame:SetScale(Style.FitScale(layout.height, UIParent.GetHeight and UIParent:GetHeight()))
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
