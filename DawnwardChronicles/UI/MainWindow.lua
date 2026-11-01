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
-- Every value is the approved Main.dc.html one (rail padding 20/18/16,
-- portrait 116 with a 2 px ring, navigation 44 high with 4 between, header
-- at 22 with the 36 px close button, content 772 wide).
MainWindow.LAYOUT = {
	width = 1100,
	height = 720,
	borderInset = 1,      -- the 1 px gold frame line
	railWidth = 272,
	railPad = 18,
	wordmarkTop = 20,
	wordmarkHeight = 18,
	portraitTop = 56,
	portraitSize = 116,   -- outer diameter of the gold ring
	ringWidth = 2,
	ringGap = 4,          -- dark gap between the ring and the portrait
	badgeHeight = 22,     -- level badge, overlapping the ring's bottom by 14
	badgeDrop = 8,
	nameTop = 190,        -- name block top (name, title, identity line, chips)
	nameLines = 2,
	identityGap = 4,
	chipGap = 10,         -- identity line to the homeland and privacy chips
	navTop = 344,         -- first navigation button top
	navHeight = 44,
	navGap = 4,
	navIconSize = 20,
	navIconLeft = 14,
	navLabelLeft = 46,
	navBadge = 22,
	tabCount = 4,
	trp3Bottom = 56,      -- Total RP 3 status line, above the bottom edge
	trp3Height = 18,
	statusDot = 8,
	railButtonHeight = 30,
	railButtonGap = 8,
	railButtonBottom = 16,
	pad = 28,             -- content column side padding
	headerTop = 22,       -- eyebrow top, below the top edge
	eyebrowHeight = 18,
	titleGap = 2,
	titleHeight = 38,     -- Cinzel 28
	iconSize = 36,
	contentTop = 96,      -- content area top, below the top edge
	contentBottom = 36,   -- content area bottom, above the bottom edge
	statusBottom = 10,
	statusHeight = 20,
	grip = 16,
}

--- Pure layout maths: rectangles relative to the window's bottom-left corner.
--- Resizing (bottom-right handle) -------------------------------------------------
-- The window keeps its approved 1100 x 720 layout and is resized by scaling
-- it (Frame:SetScale), the way Blizzard's own scalable panels work. Every
-- section is laid out once in UI units, so scaling keeps the proportions,
-- hierarchy and spacing of the approved design exactly; a native size
-- change would need every screen to lay itself out again for each size.
-- The trade-off is that text grows and shrinks with the window, so the
-- smallest scale (MIN_SCALE) is chosen to keep it readable.
MainWindow.MIN_SCALE = 0.7  -- body text stays at about 10.5 UI units or more
MainWindow.MAX_SCALE = 1.4
MainWindow.FIT_MARGIN = 40  -- UI units kept free around the window

--- The largest scale at which the window fits the screen. Pure.
function MainWindow.FitLimit(parentW, parentH)
	local L = MainWindow.LAYOUT
	local m = MainWindow.FIT_MARGIN
	if type(parentW) ~= "number" or type(parentH) ~= "number" or parentW <= 0 or parentH <= 0 then
		return 1
	end
	return math.min((parentW - m) / L.width, (parentH - m) / L.height)
end

--- The scale to use: the player's chosen scale (nil = the design's own
-- size, 1), kept between MIN_SCALE and MAX_SCALE, and never larger than the
-- screen allows. On a screen too small even for MIN_SCALE, fitting wins.
-- Pure.
function MainWindow.EffectiveScale(chosen, parentW, parentH)
	local scale = type(chosen) == "number" and chosen or 1
	scale = math.max(MainWindow.MIN_SCALE, math.min(MainWindow.MAX_SCALE, scale))
	return math.min(scale, MainWindow.FitLimit(parentW, parentH))
end

--- The scale for a drag of the resize handle: the window's top-left corner
-- stays where it is (left, top in UIParent units) and the bottom-right
-- corner follows the cursor (cx, cy). Kept inside the limits and inside the
-- screen from that corner. Pure.
function MainWindow.DragScale(left, top, cx, cy, parentW, parentH)
	local L = MainWindow.LAYOUT
	local byWidth = (cx - left) / L.width
	local byHeight = (top - cy) / L.height
	local scale = math.max(byWidth, byHeight)
	scale = math.max(MainWindow.MIN_SCALE, math.min(MainWindow.MAX_SCALE, scale))
	-- Never past the right or bottom edge of the screen.
	if type(parentW) == "number" and parentW > 0 then
		scale = math.min(scale, (parentW - left) / L.width)
	end
	if type(top) == "number" then
		scale = math.min(scale, top / L.height)
	end
	return math.min(scale, MainWindow.FitLimit(parentW, parentH))
end

function MainWindow.ComputeLayout(L)
	local r = {}
	r.background = { left = L.borderInset, right = L.width - L.borderInset,
		bottom = L.borderInset, top = L.height - L.borderInset }
	-- The rail.
	r.rail = { left = L.borderInset, right = L.railWidth, bottom = L.borderInset, top = L.height - L.borderInset }
	local railLeft, railRight = L.railPad, L.railWidth - L.railPad
	local centre = L.railWidth / 2
	r.wordmark = { left = railLeft, right = railRight, bottom = L.height - L.wordmarkTop - L.wordmarkHeight,
		top = L.height - L.wordmarkTop }
	r.portrait = { left = centre - L.portraitSize / 2, right = centre + L.portraitSize / 2,
		bottom = L.height - L.portraitTop - L.portraitSize, top = L.height - L.portraitTop }
	local badgeWidth = 40
	r.levelBadge = { left = centre - badgeWidth / 2, right = centre + badgeWidth / 2,
		bottom = r.portrait.bottom - L.badgeDrop, top = r.portrait.bottom - L.badgeDrop + L.badgeHeight }
	r.name = { left = railLeft, right = railRight, bottom = L.height - L.navTop + 12, top = L.height - L.nameTop }
	r.tabs = {}
	for i = 1, L.tabCount do
		local top = L.height - L.navTop - (i - 1) * (L.navHeight + L.navGap)
		r.tabs[i] = { left = railLeft, right = railRight, bottom = top - L.navHeight, top = top }
	end
	local half = (railRight - railLeft - L.railButtonGap) / 2
	r.help = { left = railLeft, right = railLeft + half, bottom = L.railButtonBottom,
		top = L.railButtonBottom + L.railButtonHeight }
	r.gear = { left = railRight - half, right = railRight, bottom = L.railButtonBottom,
		top = L.railButtonBottom + L.railButtonHeight }
	r.trp3 = { left = railLeft + 4, right = railRight - 4, bottom = L.trp3Bottom, top = L.trp3Bottom + L.trp3Height }
	-- The content column.
	local left, right = L.railWidth + L.pad, L.width - L.pad
	local top = L.height - L.headerTop
	r.close = { left = right - L.iconSize, right = right, bottom = top - L.iconSize, top = top }
	r.eyebrow = { left = left, right = r.close.left - 12, bottom = top - L.eyebrowHeight, top = top }
	local titleTop = r.eyebrow.bottom - L.titleGap
	r.title = { left = left, right = r.close.left - 12, bottom = titleTop - L.titleHeight, top = titleTop }
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

-- Rail navigation buttons (Main.dc.html .navbtn): icon, label, optional
-- count badge. Selected: a filled panel (raised colour) with a 1 px gold
-- edge and bright gold text; hovered: half that fill; otherwise quiet text.
-- tab.underline is the selected fill (the selection marker callers test).
local function paintTab(tab, theme)
	local tones = Style.Tones(theme)
	local on = tab.selected
	Style.Color(tab.bg, theme.surfaceHover, (not on and tab.hover) and 0.5 or 0)
	tab.edges:Paint(theme.border, on and 1 or 0)
	tab.underline:SetShown(on and true or false)
	Style.Color(tab.underline, theme.surfaceHover)
	Style.TextColor(tab.label, on and tones.accentBright or (tab.hover and theme.text or tones.navText))
	if tab.icon then
		local tint = on and tones.accentBright or (tab.hover and theme.text or tones.navText)
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

MainWindow.TRP3_HELP = "Optional. Open the Total RP 3 page to see its status, preview what would be shared "
	.. "and manage sync."

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

--- color lightened just enough to read at 4.5:1 on background (class
-- colours such as the Shaman's blue are too dark on the navy rail). Pure.
function MainWindow.ReadableColor(color, background)
	local c = color
	for step = 1, 10 do
		if Themes.Contrast(c, background) >= 4.5 then return c end
		c = Style.Lighten(color, step * 0.1)
	end
	return c
end

local function hexOf(color)
	return string.format("%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5))
end

--- The identity line under the name: "Human · Paladin · she/her", the class
-- in its class colour (made readable on the rail) as the design shows it.
-- Pure apart from the game identity passed in.
function MainWindow.IdentityLine(game, char, railColor)
	local line = ns.Showcase.IdentityLine(game, char)
	if game.className and game.classColor and railColor then
		local color = MainWindow.ReadableColor(game.classColor, railColor)
		local coloured = "|cff" .. hexOf(color) .. game.className .. "|r"
		local s, e = line:find(game.className, 1, true)
		if s then line = line:sub(1, s - 1) .. coloured .. line:sub(e + 1) end
	end
	return line
end

--- The homeland chip's text: the Homeland profile field, or nil. Pure.
function MainWindow.HomelandOf(char)
	local field = char and char.fields and char.fields.homeland
	local value = field and field.value
	return type(value) == "string" and value ~= "" and value or nil
end

--- The privacy chip under the identity: how much of the profile is Public,
-- from the profile fields' own visibility. nil when no field is set (there
-- is nothing to summarise). Returns { text, tone, tooltip }. Pure.
function MainWindow.PrivacySummary(char)
	if not (char and char.fields) then return nil end
	local set, public = 0, 0
	for _, entry in pairs(char.fields) do
		local value = entry.value
		if value ~= nil and value ~= "" then
			set = set + 1
			if entry.visibility == "public" then public = public + 1 end
		end
	end
	if set == 0 then return nil end
	local fields = set == 1 and "field" or "fields"
	if public == 0 then
		return { text = "Private", tone = "private", tooltip = "None of your " .. set .. " profile " .. fields
			.. " is Public, so nothing from your profile is shared." }
	end
	local shared = "may be shared (share exports, and Total RP 3 if you turned sync on)."
	if public == set then
		return { text = "Public", tone = "public", tooltip = "All " .. set .. " profile " .. fields .. " are Public: they "
			.. shared }
	end
	return { text = public .. " of " .. set .. " public", tone = "public", tooltip = public .. " of your " .. set
		.. " profile fields are Public: only those " .. shared }
end

-- Lays out the homeland and privacy chips, centred under the identity line
-- and never wider than the rail.
local function layoutChips(char)
	local L = layout
	local width = L.railWidth - 2 * L.railPad
	local homeland, privacy = MainWindow.HomelandOf(char), MainWindow.PrivacySummary(char)
	local chips, gap = {}, 6
	local privacyChip, homeChip = frame.privacyChip, frame.homelandChip
	privacyChip:SetShown(privacy ~= nil)
	if privacy then
		privacyChip:SetChip(privacy.text, privacy.tone)
		Widgets.Tooltip(privacyChip, "Profile visibility", privacy.tooltip)
	end
	homeChip:SetShown(homeland ~= nil)
	if homeland then
		local room = width - (privacy and (privacyChip:GetWidth() + gap) or 0)
		homeChip.maxWidth = room
		homeChip:SetChip(homeland, "accent")
		chips[#chips + 1] = homeChip
	end
	if privacy then chips[#chips + 1] = privacyChip end
	local total = 0
	for i, chip in ipairs(chips) do total = total + chip:GetWidth() + (i > 1 and gap or 0) end
	local x = -total / 2
	for _, chip in ipairs(chips) do
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", frame.chipRow, "TOP", x, 0)
		x = x + chip:GetWidth() + gap
	end
	frame.chipRow.total = total
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
	frame.charLine:SetText(MainWindow.IdentityLine(game, char, Style.Current().panel))
	frame.level:SetText(game.level and tostring(game.level) or "")
	frame.levelBadge:SetShown(game.level ~= nil)
	layoutChips(char)
	-- Cut short (a very long name or title): the full text on hover.
	local cut = (frame.charName.IsTruncated and frame.charName:IsTruncated())
		or (frame.charTitle.IsTruncated and frame.charTitle:IsTruncated())
	frame.identityHover.tooltipTitle = cut and name or nil
	frame.identityHover.tooltipText = cut and title or nil
	-- Mouse input only while there is something to show, so the name area
	-- still drags the window otherwise.
	frame.identityHover:EnableMouse(cut and true or false)
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
	local line = MainWindow.TRP3Line(status)
	frame.trp3:SetText(line)
	frame.trp3Dot.active = type(status) == "table" and status.loaded and true or nil
	Style.Repaint(frame.trp3Dot)
	frame.trp3Link.tooltipTitle = "Total RP 3"
	frame.trp3Link.tooltipText = line .. "\n" .. MainWindow.TRP3_HELP
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
	-- A section with its own controls in the header row (def.titleInset px at
	-- the right) gets a shorter title, which the client cuts with "...".
	local inset = (not settingsOpen and def and def.titleInset) or 0
	local rect = frame.titleRect
	Widgets.Place(frame.title, frame, { left = rect.left, right = rect.right - inset, bottom = rect.bottom,
		top = rect.top })
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
	-- Mark the selection now: also on the very first open, before the
	-- character's theme has been applied (it used to show no selection).
	tabColors()
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
	tabColors()
	MainWindow.Refresh()
end

local function parentSize()
	return UIParent.GetWidth and UIParent:GetWidth(), UIParent.GetHeight and UIParent:GetHeight()
end

--- Sets the window's scale (from the player's saved choice) and position.
-- A frame's point offsets are in its own (scaled) units, so a position saved
-- at another scale is converted.
local function restorePosition()
	local pw, ph = parentSize()
	local scale = MainWindow.EffectiveScale(ctx() and Actions.WindowScale(ctx()), pw, ph)
	frame:SetScale(scale)
	frame:ClearAllPoints()
	local position = ctx() and Actions.WindowPosition(ctx())
	if position then
		local factor = (position.scale or scale) / scale
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", position.left * factor, position.top * factor)
	else
		frame:SetPoint("CENTER")
	end
end
MainWindow.RestorePosition = function() if frame then restorePosition() end end

local function savePosition()
	frame:StopMovingOrSizing()
	-- We remember the position ourselves; keep the client's layout cache out of it.
	if frame.SetUserPlaced then
		frame:SetUserPlaced(false)
	end
	if ctx() then
		Actions.SaveWindowPosition(ctx(), frame:GetLeft(), frame:GetTop(), frame:GetScale())
	end
end

--- The resize handle in the bottom-right corner: the chat frame's own size
-- grabber art (FloatingChatFrame.xml, UI-ChatIM-SizeGrabber), tinted gold.
-- Work happens only while the button is held (an OnUpdate set on mouse down
-- and removed on mouse up), and only when the cursor has moved.
local function buildResizeHandle()
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	Style.Register(grip, function(g, theme)
		for _, tex in ipairs({ g:GetNormalTexture(), g:GetPushedTexture() }) do
			if tex and tex.SetVertexColor then tex:SetVertexColor(theme.ornament[1], theme.ornament[2], theme.ornament[3]) end
		end
	end)
	Widgets.Tooltip(grip, "Resize", "Drag to make the window larger or smaller. Settings → General → "
		.. "Reset window size returns it to its design size.")
	local level = frame.GetFrameLevel and frame:GetFrameLevel()
	if type(level) == "number" and grip.SetFrameLevel then grip:SetFrameLevel(level + 20) end

	local drag
	local function cursor()
		local x, y = GetCursorPosition()
		local s = UIParent:GetEffectiveScale()
		return x / s, y / s
	end
	local function step()
		local cx, cy = cursor()
		if drag.cx == cx and drag.cy == cy then return end
		drag.cx, drag.cy = cx, cy
		local pw, ph = parentSize()
		local scale = MainWindow.DragScale(drag.left, drag.top, cx, cy, pw, ph)
		if math.abs(scale - frame:GetScale()) < 0.002 then return end
		frame:SetScale(scale)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", drag.left / scale, drag.top / scale)
	end
	local function stop()
		grip:SetScript("OnUpdate", nil)
		if not drag then return end
		drag = nil
		if ctx() then Actions.SaveWindowScale(ctx(), frame:GetScale()) end
		savePosition()
	end
	grip:SetScript("OnMouseDown", function()
		local scale = frame:GetScale()
		drag = { left = frame:GetLeft() * scale, top = frame:GetTop() * scale }
		grip:SetScript("OnUpdate", step)
	end)
	grip:SetScript("OnMouseUp", stop)
	grip:SetScript("OnHide", stop)
	frame.resizeHandle = grip
	return grip
end

--- Settings → General → Reset window size.
function MainWindow.ResetSize()
	if ctx() then Actions.SaveWindowScale(ctx(), nil) end
	if frame then
		local left, top = frame:GetLeft(), frame:GetTop()
		local old = frame:GetScale()
		local pw, ph = parentSize()
		local scale = MainWindow.EffectiveScale(nil, pw, ph)
		frame:SetScale(scale)
		if left and top then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
		end
		savePosition()
	end
end

local function buildTab(index, def, r)
	local tab = CreateFrame("Button", nil, frame)
	Widgets.Place(tab, frame, r.tabs[index])
	tab.id = def.id
	local L = layout
	tab.bg = Widgets.Solid(tab, "BACKGROUND")
	tab.bg:SetAllPoints(tab)
	tab.edges = Style.Edge(tab, "BORDER")
	-- Selection marker (kept under its v0.6 name for callers and tests): the
	-- selected item's filled panel, inside its gold edge.
	tab.underline = Widgets.Solid(tab, "BACKGROUND", 1)
	tab.underline:SetAllPoints(tab)
	if def.icon then
		tab.icon = tab:CreateTexture(nil, "ARTWORK")
		tab.icon:SetSize(L.navIconSize, L.navIconSize)
		tab.icon:SetPoint("LEFT", L.navIconLeft, 0)
		tab.icon:SetTexture(def.icon)
		tab.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if tab.icon.SetDesaturated then tab.icon:SetDesaturated(true) end
	end
	tab.label = tab:CreateFontString(nil, "OVERLAY", Style.FontFor("nav"))
	tab.label:SetPoint("LEFT", def.icon and L.navLabelLeft or 16, 0)
	tab.label:SetText(def.label)
	-- Count badge: a round gold disc (a pill for two digits) with dark text.
	tab.badgeBg = Style.Disc(tab, "ARTWORK", 0, L.navBadge)
	tab.badgeBg:SetPoint("RIGHT", -L.navIconLeft, 0)
	tab.badge = tab:CreateFontString(nil, "OVERLAY", Style.FontFor("badge"))
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

	-- Wordmark: a small gold jewel (a square turned 45 degrees; the design's
	-- four-point star needs vector art) and DAWNWARD in Cinzel.
	frame.jewel = Widgets.Solid(frame, "ARTWORK")
	frame.jewel:SetSize(8, 8)
	local jewelY = -(layout.wordmarkTop + layout.wordmarkHeight / 2)
	frame.jewel:SetPoint("CENTER", frame, "TOPLEFT", r.wordmark.left + 12, jewelY)
	if frame.jewel.SetRotation then frame.jewel:SetRotation(math.pi / 4) end
	Style.Register(frame.jewel, function(t, theme) Style.Color(t, theme.accent) end)
	frame.wordmark = Widgets.Label(frame, nil, false, "eyebrow")
	Widgets.SetTextRole(frame.wordmark, "accent")
	Widgets.Place(frame.wordmark, frame, { left = r.wordmark.left + 26, right = r.wordmark.right,
		bottom = r.wordmark.bottom, top = r.wordmark.top })
	frame.wordmark:SetJustifyV("MIDDLE")
	frame.wordmark:SetText("DAWNWARD")

	-- Portrait: the game's round portrait inside a 2 px gold ring with a dark
	-- gap, drawn as masked discs (ring, gap, portrait well). Where masks are
	-- not available, the Showcase portrait keeps its tinted tracking ring.
	local L = layout
	frame.portrait = ns.Showcase.Portrait(frame, L.portraitSize)
	Widgets.Place(frame.portrait, frame, r.portrait)
	local ring = {}
	ring.outer = Style.Disc(frame.portrait, "BACKGROUND", 0, L.portraitSize)
	ring.gap = Style.Disc(frame.portrait, "BACKGROUND", 1, L.portraitSize - 2 * L.ringWidth)
	ring.well = Style.Disc(frame.portrait, "BACKGROUND", 2, L.portraitSize - 2 * (L.ringWidth + L.ringGap))
	for _, disc in pairs(ring) do disc:SetPoint("CENTER", frame.portrait, "CENTER", 0, 0) end
	ring.round = ring.outer.round and ring.gap.round and ring.well.round
	for _, key in ipairs({ "outer", "gap", "well" }) do ring[key]:SetShown(ring.round and true or false) end
	if ring.round and frame.portrait.ring then frame.portrait.ring:Hide() end
	Style.Register(ring, function(rg, theme)
		Style.Color(rg.outer, theme.accent)
		Style.Color(rg.gap, theme.panel)
		Style.Color(rg.well, theme.surfaceHover)
	end)
	frame.portraitRing = ring

	-- Level badge: a pill on the ring's bottom edge (a square badge where
	-- round shapes are not available).
	frame.levelBadge = CreateFrame("Frame", nil, frame)
	Widgets.Place(frame.levelBadge, frame, r.levelBadge)
	frame.levelBadge:SetSize(r.levelBadge.right - r.levelBadge.left, L.badgeHeight)
	if frame.levelBadge.SetFrameLevel and frame.portrait.GetFrameLevel then
		local level = frame.portrait:GetFrameLevel()
		if type(level) == "number" then frame.levelBadge:SetFrameLevel(level + 2) end
	end
	frame.levelBadge.bg = Widgets.Solid(frame.levelBadge, "BACKGROUND")
	frame.levelBadge.bg:SetAllPoints(frame.levelBadge)
	frame.levelBadge.edges = Style.Edge(frame.levelBadge, "BORDER")
	frame.levelBadge.pill = Style.Pill(frame.levelBadge, L.badgeHeight)
	Style.Register(frame.levelBadge, function(b, theme)
		if b.pill then
			b.pill:Paint(theme.background, theme.border)
			b.bg:Hide()
			b.edges:SetShown(false)
		else
			Style.Color(b.bg, theme.background)
			b.edges:Paint(theme.border, 1)
		end
	end)
	frame.level = Widgets.Label(frame.levelBadge, "badge", false, "accent")
	Widgets.SetTextRole(frame.level, "accentBright")
	frame.level:SetPoint("CENTER", 0, 0)
	frame.level:SetJustifyH("CENTER")

	-- Name (Cinzel 21, at most two lines), title (one line, warm gold),
	-- race · class · pronouns (14, muted, class in its colour), then the
	-- homeland and privacy chips.
	local width = L.railWidth - 2 * L.railPad
	frame.charName = Widgets.Label(frame, "railName", true, "body")
	frame.charName:SetPoint("TOP", frame, "TOPLEFT", L.railWidth / 2, -L.nameTop)
	frame.charName:SetWidth(width)
	frame.charName:SetJustifyH("CENTER")
	if frame.charName.SetMaxLines then frame.charName:SetMaxLines(L.nameLines) end
	frame.charTitle = Widgets.Label(frame, "GameFontHighlight", false, "body")
	Widgets.SetTextRole(frame.charTitle, "label")
	frame.charTitle:SetPoint("TOP", frame.charName, "BOTTOM", 0, -L.identityGap)
	frame.charTitle:SetWidth(width)
	frame.charTitle:SetJustifyH("CENTER")
	frame.charLine = Widgets.Label(frame, "meta", false, "muted")
	frame.charLine:SetPoint("TOP", frame.charTitle, "BOTTOM", 0, -L.identityGap)
	frame.charLine:SetWidth(width)
	frame.charLine:SetJustifyH("CENTER")
	frame.chipRow = CreateFrame("Frame", nil, frame)
	frame.chipRow:SetSize(width, Widgets.CHIP_HEIGHT)
	frame.chipRow:SetPoint("TOP", frame.charLine, "BOTTOM", 0, -L.chipGap)
	frame.homelandChip = Widgets.Chip(frame.chipRow, "", "accent")
	frame.homelandChip:SetBase("panel")
	frame.privacyChip = Widgets.Chip(frame.chipRow, "", "private")
	frame.privacyChip:SetBase("panel")
	-- Hover area over the name and title: the full text when either is cut.
	frame.identityHover = CreateFrame("Frame", nil, frame)
	frame.identityHover:SetPoint("TOPLEFT", frame.charName, "TOPLEFT", 0, 0)
	frame.identityHover:SetPoint("BOTTOMRIGHT", frame.charTitle, "BOTTOMRIGHT", 0, 0)
	Widgets.Tooltip(frame.identityHover, nil)

	-- Total RP 3 status: a dot and one line, which opens the Total RP 3 page
	-- (Settings → Total RP 3).
	frame.trp3Dot = Style.Disc(frame, "ARTWORK", 0, L.statusDot)
	frame.trp3Dot:SetPoint("LEFT", frame, "BOTTOMLEFT", r.trp3.left, (r.trp3.bottom + r.trp3.top) / 2)
	Style.Register(frame.trp3Dot, function(t, theme)
		Style.Color(t, t.active and theme.accent or Style.Tones(theme).dot)
	end)
	frame.trp3 = Widgets.Label(frame, "GameFontHighlightSmall", false, "muted")
	Widgets.Place(frame.trp3, frame, { left = r.trp3.left + L.statusDot + 8, right = r.trp3.right,
		bottom = r.trp3.bottom, top = r.trp3.top })
	frame.trp3:SetJustifyV("MIDDLE")
	frame.trp3Link = CreateFrame("Button", nil, frame)
	Widgets.Place(frame.trp3Link, frame, r.trp3)
	frame.trp3Link:SetScript("OnClick", function()
		if ns.SettingsPanel and ns.SettingsPanel.OpenPage then ns.SettingsPanel.OpenPage("trp3") end
	end)
	Widgets.Tooltip(frame.trp3Link, "Total RP 3", MainWindow.TRP3_HELP)
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
	-- The wheel over the window never zooms the camera: scroll frames in it
	-- scroll (Widgets.WheelScroll), everywhere else it does nothing.
	Widgets.SwallowWheel(frame)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", savePosition)
	-- The gold frame line and the top-left ornament; the bottom-right corner
	-- holds the resize grip, which takes the ornament's place there.
	Style.Chrome(frame, "background", { corners = { "TOPLEFT" } })
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
	frame.titleRect = r.title
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

	buildResizeHandle()
	-- A new UI scale or resolution: fit the window to the screen again.
	frame:RegisterEvent("UI_SCALE_CHANGED")
	frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
	frame:SetScript("OnEvent", function()
		if frame:IsShown() then restorePosition() end
	end)

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
