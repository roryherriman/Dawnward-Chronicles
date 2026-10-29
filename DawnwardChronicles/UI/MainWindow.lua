-- The journal window (v0.7 shell, docs/design/UI_DESIGN_V07.md): a
-- permanent character rail on the left (portrait, name, title, identity,
-- the four sections, Total RP 3 status, Guide and Settings) and the content
-- column on the right (section eyebrow and heading, close button, content,
-- status line). The approved mockups in docs/design/mockups are the target.
--
-- Layering: MEDIUM strata and toplevel, like the game's own panels, so game
-- dialogs (DIALOG) and tooltips stay above it. The export/import window uses
-- FULLSCREEN_DIALOG and therefore opens on top of this one.
--
-- Sections register themselves (MainWindow.RegisterSection) and receive a
-- "view" on every refresh: { ctx, char, theme, contentWidth, setStatus(text),
-- refresh() }.
local _, ns = ...
local Widgets, Themes, Actions, Style = ns.Widgets, ns.Themes, ns.Actions, ns.Style

local MainWindow = {}
ns.MainWindow = MainWindow

local FRAME_NAME = "DawnwardChroniclesJournal"
MainWindow.STRATA = "MEDIUM"

-- Sizes in UI units: the approved 1100 x 720 design. On screens with less
-- room (a large UI scale or a small resolution) the window scales itself
-- down to fit both ways (Style.FitScale).
MainWindow.LAYOUT = {
	width = 1100,
	height = 720,
	borderInset = 4,
	railWidth = 272,
	railPad = 18,
	wordmarkTop = 20,
	portraitTop = 52,
	portraitSize = 112,
	nameTop = 182,        -- name block top (name, title, identity line)
	navTop = 292,         -- first navigation button top
	navHeight = 44,
	navGap = 4,
	tabCount = 4,
	trp3Bottom = 58,      -- Total RP 3 status line, above the bottom edge
	railButtonHeight = 30,
	railButtonBottom = 16,
	pad = 28,             -- content column side padding
	headerTop = 22,       -- eyebrow top, below the top edge
	iconSize = 36,
	contentTop = 96,      -- content area top, below the top edge
	contentBottom = 36,   -- content area bottom, above the bottom edge
	statusBottom = 10,
	statusHeight = 20,
}

--- Pure layout maths: rectangles relative to the window's bottom-left corner.
function MainWindow.ComputeLayout(L)
	local r = {}
	r.background = { left = L.borderInset, right = L.width - L.borderInset,
		bottom = L.borderInset, top = L.height - L.borderInset }
	-- The rail.
	r.rail = { left = L.borderInset, right = L.railWidth, bottom = L.borderInset, top = L.height - L.borderInset }
	local railLeft, railRight = L.railPad, L.railWidth - L.railPad
	local centre = L.railWidth / 2
	r.wordmark = { left = railLeft, right = railRight, bottom = L.height - L.wordmarkTop - 18,
		top = L.height - L.wordmarkTop }
	r.portrait = { left = centre - L.portraitSize / 2, right = centre + L.portraitSize / 2,
		bottom = L.height - L.portraitTop - L.portraitSize, top = L.height - L.portraitTop }
	r.name = { left = railLeft, right = railRight, bottom = L.height - L.navTop + 12, top = L.height - L.nameTop }
	r.tabs = {}
	for i = 1, L.tabCount do
		local top = L.height - L.navTop - (i - 1) * (L.navHeight + L.navGap)
		r.tabs[i] = { left = railLeft - 4, right = railRight + 4, bottom = top - L.navHeight, top = top }
	end
	local half = (railRight - railLeft - 8) / 2
	r.help = { left = railLeft, right = railLeft + half, bottom = L.railButtonBottom,
		top = L.railButtonBottom + L.railButtonHeight }
	r.gear = { left = railRight - half, right = railRight, bottom = L.railButtonBottom,
		top = L.railButtonBottom + L.railButtonHeight }
	r.trp3 = { left = railLeft, right = railRight, bottom = L.trp3Bottom, top = L.trp3Bottom + 18 }
	-- The content column.
	local left, right = L.railWidth + L.pad, L.width - L.pad
	local top = L.height - L.headerTop
	r.close = { left = right - L.iconSize, right = right, bottom = top - L.iconSize, top = top }
	r.eyebrow = { left = left, right = r.close.left - 12, bottom = top - 14, top = top }
	r.title = { left = left, right = r.close.left - 12, bottom = top - 50, top = top - 18 }
	r.content = { left = left, right = right, bottom = L.contentBottom, top = L.height - L.contentTop }
	r.status = { left = left, right = right, bottom = L.statusBottom, top = L.statusBottom + L.statusHeight }
	return r
end

local sections = {}
local frame, layout, currentSection, settingsOpen, appliedTheme

--- def = { id, label, order, heading?, icon?, create(parent) -> section }
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

-- Rail navigation buttons: icon, label, optional count badge.
local function paintTab(tab, theme)
	local on = tab.selected
	Style.Color(tab.bg, theme.surfaceHover, on and 1 or (tab.hover and 0.6 or 0))
	tab.edges:Paint(theme.border or theme.ornament, on and 1 or 0)
	tab.underline:SetShown(on and true or false)
	Style.Color(tab.underline, theme.accent)
	Style.TextColor(tab.label, (on or tab.hover) and theme.accent or theme.text)
	if tab.icon then
		local tint = (on or tab.hover) and theme.accent or theme.muted
		tab.icon:SetVertexColor(tint[1], tint[2], tint[3])
	end
	Style.Color(tab.badgeBg, theme.accent)
	Style.TextColor(tab.badge, theme.accentText)
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

--- The journal heading. Stored names never contain "|" (Util.CleanText), so
-- adding our own colour code for the simulation marker is safe.
function MainWindow.TitleFor(char, simulation)
	local name = char and char.fields.name and char.fields.name.value
	local title = name and (name .. "'s Journal") or "Dawnward Chronicles"
	return simulation and (title .. SIM_SUFFIX) or title
end

--- The heading over a section: the journal is titled with the character's
-- name; the others with their own heading. Simulation is always flagged.
function MainWindow.HeadingFor(def, char, simulation)
	if not def or (def.id == "journal" and not def.heading) then
		return MainWindow.TitleFor(char, simulation)
	end
	local heading = def.heading or def.label
	return simulation and (heading .. SIM_SUFFIX) or heading
end

--- Width of the content area. Sections size their text from this rather than
-- GetWidth(), which the client may report as 0 before the first layout pass.
function MainWindow.ContentWidth()
	local L = MainWindow.LAYOUT
	return L.width - L.railWidth - 2 * L.pad
end

--- Height of the content area.
function MainWindow.ContentHeight()
	local L = MainWindow.LAYOUT
	return L.height - L.contentTop - L.contentBottom
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

--- The Total RP 3 line in the rail: availability only (read-only). Pure.
function MainWindow.TRP3Line(status)
	if type(status) ~= "table" or not status.installed then
		return "Total RP 3 · not installed (optional)"
	end
	if not status.loaded then
		return "Total RP 3 · installed, not loaded"
	end
	local profile = status.profile and status.profile.name
	return profile and ("Total RP 3 · profile \"" .. profile .. "\"") or ("Total RP 3 " .. (status.version or ""))
end

-- The rail's character block, from the profile and the game's own data.
local function refreshIdentity(char)
	local game = ns.Showcase.GameIdentity()
	local name = char and char.fields.name and char.fields.name.value
	if not name then
		local ok, unitName = pcall(UnitName, "player")
		name = ok and unitName or "Your character"
	end
	frame.charName:SetText(name)
	local title = char and char.fields.title and char.fields.title.value
	frame.charTitle:SetText(title or "")
	frame.charLine:SetText(ns.Showcase.IdentityLine(game, char))
	frame.level:SetText(game.level and tostring(game.level) or "")
	frame.levelBadge:SetShown(game.level ~= nil)
end

local function refreshRail(char)
	refreshIdentity(char)
	local waiting = char and ns.Reactions and #ns.Reactions.List(char, ctx().now()) or 0
	for _, tab in ipairs(frame.tabs) do
		local count = tab.id == "story" and waiting or 0
		tab.badge:SetText(count > 0 and tostring(count) or "")
		tab.badgeBg:SetShown(count > 0)
	end
	local status = ctx().trp3Status and ctx().trp3Status() or nil
	frame.trp3:SetText(MainWindow.TRP3Line(status))
end

--- Re-reads data and redraws the visible parts. Cheap when hidden.
function MainWindow.Refresh()
	if not frame or not frame:IsShown() or not ctx() then
		return
	end
	local char = Actions.Character(ctx())
	local theme = Actions.ThemeOf(char)
	-- While the setup wizard previews a theme, leave its preview alone.
	local previewing = ns.SetupWizard and ns.SetupWizard.IsShown()
	if theme ~= appliedTheme or (Style.Current() ~= theme and not previewing) then
		applyTheme(theme)
	end
	local def
	for _, d in ipairs(sections) do
		if d.id == currentSection then def = d end
	end
	frame.eyebrow:SetText(settingsOpen and "SETTINGS" or (def and def.label:upper() or ""))
	frame.title:SetText(settingsOpen and "Settings"
		or MainWindow.HeadingFor(def, char, ctx().store:IsSimulation()))
	refreshRail(char)
	local view = makeView(theme, char)
	if settingsOpen and MainWindow.settings then
		MainWindow.settings:Refresh(view)
		return
	end
	if def and def.instance then
		def.instance:Refresh(view)
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
	tab.bg = Widgets.Solid(tab, "BACKGROUND")
	tab.bg:SetAllPoints(tab)
	tab.edges = Style.Edge(tab, "BORDER")
	-- Selection marker (kept under its v0.6 name for callers and tests).
	tab.underline = Widgets.Solid(tab, "ARTWORK")
	tab.underline:SetWidth(3)
	tab.underline:SetPoint("TOPLEFT", 1, -8)
	tab.underline:SetPoint("BOTTOMLEFT", 1, 8)
	if def.icon then
		tab.icon = tab:CreateTexture(nil, "ARTWORK")
		tab.icon:SetSize(22, 22)
		tab.icon:SetPoint("LEFT", 14, 0)
		tab.icon:SetTexture(def.icon)
		tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if tab.icon.SetDesaturated then tab.icon:SetDesaturated(true) end
	end
	tab.label = tab:CreateFontString(nil, "OVERLAY", Style.Font("GameFontHighlight"))
	tab.label:SetPoint("LEFT", def.icon and 46 or 16, 0)
	tab.label:SetText(def.label)
	tab.badgeBg = Widgets.Solid(tab, "ARTWORK")
	tab.badgeBg:SetSize(24, 20)
	tab.badgeBg:SetPoint("RIGHT", -12, 0)
	tab.badge = tab:CreateFontString(nil, "OVERLAY", Style.Font("GameFontHighlightSmall"))
	tab.badge:SetPoint("CENTER", tab.badgeBg, "CENTER", 0, 0)
	tab.badgeBg:Hide()
	tab:SetScript("OnClick", function() showSection(def.id) end)
	tab:SetScript("OnEnter", function(self) self.hover = true; Style.Repaint(self) end)
	tab:SetScript("OnLeave", function(self) self.hover = nil; Style.Repaint(self) end)
	return Style.Register(tab, paintTab)
end

-- The rail: wordmark, portrait and level, name block, Total RP 3 line,
-- Guide and Settings.
local function buildRail(r)
	frame.railFill = Style.Fill(frame, "panel", "BACKGROUND", -7)
	Widgets.Place(frame.railFill, frame, r.rail)
	frame.railLine = Widgets.Solid(frame, "BORDER")
	frame.railLine:SetWidth(1)
	frame.railLine:SetPoint("TOPLEFT", layout.railWidth, -layout.borderInset)
	frame.railLine:SetPoint("BOTTOMLEFT", layout.railWidth, layout.borderInset)
	Style.Register(frame.railLine, function(t, theme) Style.Color(t, theme.edge) end)

	frame.wordmark = Widgets.Label(frame, nil, false, "eyebrow")
	Widgets.Place(frame.wordmark, frame, r.wordmark)
	frame.wordmark:SetText("DAWNWARD")
	frame.portrait = ns.Showcase.Portrait(frame, layout.portraitSize)
	Widgets.Place(frame.portrait, frame, r.portrait)
	frame.levelBadge = CreateFrame("Frame", nil, frame)
	frame.levelBadge:SetSize(34, 20)
	frame.levelBadge:SetPoint("TOP", frame.portrait, "BOTTOM", 0, 8)
	frame.levelBadge.bg = Style.Fill(frame.levelBadge, "background", "BACKGROUND")
	frame.levelBadge.bg:SetAllPoints(frame.levelBadge)
	frame.levelBadge.edges = Style.Edge(frame.levelBadge, "BORDER")
	Style.Register(frame.levelBadge.edges, function(e, theme) e:Paint(theme.border or theme.ornament, 1) end)
	frame.level = Widgets.Label(frame.levelBadge, "GameFontHighlightSmall", false, "accent")
	frame.level:SetPoint("CENTER", 0, 0)
	frame.level:SetJustifyH("CENTER")

	local width = layout.railWidth - 2 * layout.railPad
	frame.charName = Widgets.Label(frame, "GameFontHighlightLarge", true, "body")
	frame.charName:SetPoint("TOP", frame, "TOPLEFT", layout.railWidth / 2, -layout.nameTop)
	frame.charName:SetWidth(width)
	frame.charName:SetJustifyH("CENTER")
	frame.charTitle = Widgets.Label(frame, "GameFontHighlight", true, "accent")
	frame.charTitle:SetPoint("TOP", frame.charName, "BOTTOM", 0, -4)
	frame.charTitle:SetWidth(width)
	frame.charTitle:SetJustifyH("CENTER")
	frame.charLine = Widgets.Label(frame, "GameFontHighlightSmall", true, "muted")
	frame.charLine:SetPoint("TOP", frame.charTitle, "BOTTOM", 0, -4)
	frame.charLine:SetWidth(width)
	frame.charLine:SetJustifyH("CENTER")

	frame.trp3 = Widgets.Label(frame, "GameFontHighlightSmall", false, "muted")
	Widgets.Place(frame.trp3, frame, r.trp3)
	-- The status line opens the Total RP 3 page (Settings → Total RP 3).
	frame.trp3Link = CreateFrame("Button", nil, frame)
	Widgets.Place(frame.trp3Link, frame, r.trp3)
	frame.trp3Link:SetScript("OnClick", function()
		if ns.SettingsPanel and ns.SettingsPanel.OpenPage then ns.SettingsPanel.OpenPage("trp3") end
	end)
	Widgets.Tooltip(frame.trp3Link, "Total RP 3", "Optional. Open the Total RP 3 page to see its status, "
		.. "preview what would be shared and manage sync.")
	frame.help = Widgets.Button(frame, "Guide", r.help.right - r.help.left, layout.railButtonHeight, "ghost")
	Widgets.Place(frame.help, frame, r.help)
	frame.help:SetScript("OnClick", function()
		if MainWindow.guide and MainWindow.guide:IsOpen() then
			MainWindow.guide:Close()
		elseif MainWindow.guide then
			MainWindow.guide:Show(1)
		end
	end)
	Widgets.Tooltip(frame.help, "Guide and help", "A short tour of Dawnward, and a search for any feature or command.")
	frame.gear = Widgets.Button(frame, "Settings", r.gear.right - r.gear.left, layout.railButtonHeight, "ghost")
	Widgets.Place(frame.gear, frame, r.gear)
	frame.gear:SetScript("OnClick", function() MainWindow.ToggleSettings() end)
	Widgets.Tooltip(frame.gear, "Settings",
		"Theme, story moments and pace, backup and import, simulation mode, Total RP 3 status.")
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
	-- The content column reads on the window ground; the rail on the panel colour.
	frame.contentWell = Style.Fill(frame, "background", "BACKGROUND", -7)
	Widgets.Place(frame.contentWell, frame, r.content)
	buildRail(r)

	-- Content column header: eyebrow, heading, close.
	frame.eyebrow = Widgets.Label(frame, nil, false, "eyebrow")
	Widgets.Place(frame.eyebrow, frame, r.eyebrow)
	frame.title = Widgets.Label(frame, "GameFontNormalHuge", false, "title")
	Widgets.Place(frame.title, frame, r.title)
	frame.close = Widgets.IconButton(frame, "X", "Close", "Close the journal (Escape also works).")
	Widgets.Place(frame.close, frame, r.close)
	frame.close:SetScript("OnClick", function() MainWindow.Hide() end)

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
	frame:SetScale(Style.FitScale(layout.height, UIParent.GetHeight and UIParent:GetHeight(), nil,
		layout.width, UIParent.GetWidth and UIParent:GetWidth()))
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
