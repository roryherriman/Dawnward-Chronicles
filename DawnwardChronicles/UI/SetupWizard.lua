-- The first-time setup wizard (v0.6 rules, v0.7 look, v0.9 stages):
-- Welcome, Character, Story, Appearance, Total RP 3 (only when Total RP 3
-- is installed), Finish. Rules (docs/design/UI_DESIGN_V06.md, section 5,
-- and docs/design/UI_DESIGN_V09.md):
--
--   * it opens by itself after a genuinely new character first enters the
--     world (Platform/SetupLaunch.lua), and otherwise once per session when
--     a new character opens Dawnward (MainWindow.BeforeShow)
--   * values are kept while moving between pages; what the player changed
--     is saved as a draft on every step and on close, so it resumes where
--     it was left (only changed keys are kept and applied, so settings
--     changed elsewhere meanwhile are never undone)
--   * nothing is written to the character, and setup is not marked
--     complete, until Finish; Finish never clears an existing value
--   * v0.9: no routine privacy step. A new character's details start
--     Public (the profile model, Core/Publication.lua). The Total RP 3
--     stage is the single authorisation: with "Connect" chosen, Finish
--     links the active Total RP 3 profile (ConnectAll); nothing is sent
--     before Finish, and the sync's own guards still apply to every write
--   * test mode (/dawnward dev setup) is a clearly marked preview: no
--     draft, no completion, and choices are saved only on "Save choices"
--   * in simulation mode or on read-only data it is a preview that cannot
--     save, so real and test data never mix
--
-- Layout (docs/design/mockups/first-time-setup.png, v0.7): an 820 x 600
-- dialog in the main window's design language. A left step rail lists the
-- stages (done / current / upcoming; click one to go there), the right
-- side shows "STEP n OF m", the stage title and subtitle, the stage's
-- grouped panels, and a footer with Set up later, Back and Next. The step
-- numbers sit in round badges (Style.Disc; square where the client has no
-- masks) and the done mark is the game's own check texture. Sizes follow
-- SetupWizard.dc.html: steps 44 high with 26 px badges, a Cinzel 28 stage
-- title, 36 px inputs and buttons. The dialog scales down to fit small
-- screens (Style.FitScale), like the main window.
local _, ns = ...
local Widgets, Style, Actions, Onboarding, Themes, MainWindow =
	ns.Widgets, ns.Style, ns.Actions, ns.Onboarding, ns.Themes, ns.MainWindow

local SetupWizard = {}
ns.SetupWizard = SetupWizard

SetupWizard.FRAME_NAME = "DawnwardChroniclesSetup"
SetupWizard.STRATA = "HIGH" -- above the journal (MEDIUM), below game dialogs
-- rail: step rail width; pad: content padding; bodyTop: where a stage's
-- panels start; footer: the button strip; button: footer button height.
SetupWizard.LAYOUT = { width = 820, height = 600, rail = 236, pad = 30, top = 26, bodyTop = 118, footer = 70,
	button = 36, step = 44, stepGap = 4, stepsTop = 92, field = 36, badge = 26, fieldRow = 80, portrait = 48,
	area = 80, cycle = 30, cycleRow = 40, tile = 40 }

local L = SetupWizard.LAYOUT
local BODY_WIDTH = L.width - L.rail - 2 * L.pad
L.bodyWidth = BODY_WIDTH
L.bodyHeight = L.height - L.bodyTop - L.footer - 8
local INNER_WIDTH = BODY_WIDTH - 2 * Widgets.PANEL_PAD
local LABEL_WIDTH = 150
local COLUMN_GAP = 16
local COLUMN_WIDTH = math.floor((BODY_WIDTH - COLUMN_GAP) / 2)

-- "Interface\Buttons\UI-CheckBox-Check": the game's own check mark, used by
-- the Classic Era ReputationFrame.xml and QuestLogFrame.xml (Vanilla) in the
-- 1.15.9 UI source.
SetupWizard.CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"

-- Subtitles under each stage's title (the mockup's one-line explanations).
SetupWizard.SUBTITLES = {
	welcome = "Where your character is created and grows. This takes about two minutes.",
	character = "Fill in what you know. Anything left empty can be added later.",
	story = "Bring in your backstory, and choose how often Dawnward asks about your travels.",
	appearance = "Choose how this character's journal looks.",
	trp3 = "Connect once; Dawnward keeps your Total RP 3 profile up to date.",
	finish = "Review your choices. Finish saves them for this character.",
}

-- What connecting does (the Total RP 3 stage).
SetupWizard.TRP3_NOTE = "Connecting writes your name, titles, race, class, other details, your backstory (as the "
	.. "About text) and personality to the active Total RP 3 profile, and keeps them in step as your character "
	.. "grows. A backup is taken before every write, and any write can be rolled back from Settings > Total RP 3. "
	.. "Anything you make Private in Dawnward is never sent. Nothing is sent before Finish."

-- The Character stage's note (v0.9: the profile model; no classification).
SetupWizard.PROFILE_NOTE = "This is your character's profile. If you connect Total RP 3, it is what other "
	.. "players see. Keep any detail to yourself later with its Private button."

local wizard           -- the frame and its parts, built once
local autoShown = {}   -- characters the wizard opened for by itself this session

--- Pieces ------------------------------------------------------------------------------

local function pageFrame(id)
	local p = CreateFrame("Frame", nil, wizard)
	p:SetPoint("TOPLEFT", L.rail + L.pad, -L.bodyTop)
	p:SetPoint("BOTTOMRIGHT", -L.pad, L.footer + 8)
	p:Hide()
	wizard.pages[id] = p
	return p
end

local function paragraph(parent, x, y, width, text, role)
	local fs = Widgets.Label(parent, nil, true, role or "body")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetWidth(width)
	fs:SetText(text)
	return fs
end

-- A titled panel at (x, y) inside a page, width w and height h.
local function panel(parent, title, x, y, w, h, callout)
	local p = (callout and Widgets.Callout or Widgets.Panel)(parent, title)
	p:SetPoint("TOPLEFT", x, y)
	p:SetSize(w, h)
	return p
end

-- A labelled cycle button for one of Onboarding.PREFS (or any { key, label, values }).
-- The button names the value in use; a "›" at its right edge and the
-- tooltip (every option, the current one marked) say a click moves on.
local function cycleRow(parent, y, spec, width)
	local label = Widgets.Label(parent, "GameFontNormal", false, "heading")
	label:SetPoint("TOPLEFT", 0, y - 7)
	label:SetWidth(LABEL_WIDTH - 8)
	label:SetText(spec.label)
	local b = Widgets.Button(parent, "", width - LABEL_WIDTH, L.cycle, "choice")
	b:SetPoint("TOPLEFT", LABEL_WIDTH, y)
	b.chevron = Widgets.Label(b, "glyph", false, "accent")
	b.chevron:SetPoint("RIGHT", -10, 1)
	b.chevron:SetText("\226\128\186")
	b.spec = spec
	b:SetScript("OnClick", function(self)
		local values = self.spec.values
		local current = wizard.values[self.spec.key]
		local nextValue = values[1][1]
		for i, v in ipairs(values) do
			if v[1] == current then nextValue = values[i % #values + 1][1] end
		end
		wizard.values[self.spec.key] = nextValue
		wizard.edited[self.spec.key] = true
		SetupWizard.Refresh()
	end)
	Widgets.Tooltip(b, spec.label, "Click to change.")
	function b.Update(self)
		local options = {}
		for _, v in ipairs(self.spec.values) do
			local on = v[1] == wizard.values[self.spec.key]
			if on then self:SetText(v[2]) end
			options[#options + 1] = on and ("[" .. v[2] .. "]") or v[2]
		end
		Widgets.Tooltip(self, self.spec.label, "Options: " .. table.concat(options, " · ") .. "\nClick for the next option.")
	end
	wizard.cycles[#wizard.cycles + 1] = b
	return b
end

-- One profile field of the Character stage: a bold label, the input, and a
-- hint line that gives way to the inline error when there is one.
-- The boxes accept a little more than a field's limit (OVERFLOW bytes), so
-- an over-long answer is named inline instead of being cut off silently;
-- Next and Finish stay on the stage until it fits.
SetupWizard.OVERFLOW = 64

local function fieldBox(parent, field, x, y, width, height, hint)
	local maxBytes = field.max + 1 + SetupWizard.OVERFLOW
	local label = Widgets.Label(parent, "GameFontNormal", false, "heading")
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(field.label)
	local input
	if field.multiline then
		-- Long text keeps its full size and line breaks.
		local area = Widgets.TextArea(parent, maxBytes, width)
		area.frame:SetPoint("TOPLEFT", x, y - 22)
		area.frame:SetSize(width, height)
		input = area.edit
	else
		input = Widgets.EditLine(parent, maxBytes, height)
		input:SetPoint("TOPLEFT", x, y - 22)
		input:SetWidth(width)
	end
	input.fieldKey, input.field = field.key, field
	Widgets.FieldError(input, width)
	if hint then
		local region = input.anchorRegion or input
		input.hint = Widgets.Label(parent, "GameFontHighlightSmall", true, "muted")
		input.hint:SetPoint("TOPLEFT", region, "BOTTOMLEFT", 0, -4)
		input.hint:SetWidth(width)
		input.hint:SetText(hint)
	end
	input.onErrorChanged = function(self)
		if self.hint then self.hint:SetShown(not self.invalid) end
	end
	wizard.inputs[#wizard.inputs + 1] = input
	return input
end

--- Pages ---------------------------------------------------------------------------

local function buildWelcome()
	local p = pageFrame("welcome")
	local a = panel(p, "Your chronicle", 0, 0, BODY_WIDTH, 100)
	paragraph(a.inner, 0, 0, INNER_WIDTH, "Dawnward Chronicles keeps a living chronicle of your character: what "
		.. "happens on their travels, the choices you make about it, and who they slowly become.")
	local b = panel(p, "Alongside Total RP 3", 0, -114, BODY_WIDTH, 100)
	paragraph(b.inner, 0, 0, INNER_WIDTH, "Dawnward is where your character develops; Total RP 3, if you use it, is "
		.. "where the world sees them. Connect it once and Dawnward keeps it up to date.")
	local c = panel(p, "This setup", 0, -228, BODY_WIDTH, 100)
	paragraph(c.inner, 0, 0, INNER_WIDTH, "Everything is optional, and you can change any of it later in Settings. "
		.. "Close it at any time: your answers are kept.", "muted")
	paragraph(p, 0, -346, BODY_WIDTH, "Next: who your character is.", "accent")
end

local function buildCharacter()
	local p = pageFrame("character")
	-- The player's own portrait and the game's identity line: read live,
	-- never stored, nothing invented.
	wizard.portrait = ns.Showcase.Portrait(p, L.portrait)
	wizard.portrait:SetPoint("TOPLEFT", 0, 0)
	local idX = L.portrait + 14
	wizard.identity = Widgets.Label(p, "GameFontNormal", false, "heading")
	wizard.identity:SetPoint("TOPLEFT", idX, -6)
	wizard.identity:SetWidth(BODY_WIDTH - idX)
	wizard.identityNote = Widgets.Label(p, "GameFontHighlightSmall", false, "muted")
	wizard.identityNote:SetPoint("TOPLEFT", idX, -26)
	wizard.identityNote:SetWidth(BODY_WIDTH - idX)
	wizard.identityNote:SetText("From the game. Existing details are kept; an empty box never erases anything.")

	wizard.inputs = {}
	local F = Onboarding.FIELDS
	local hints = { name = "Suggested from the game; change it freely.",
		pronouns = "Used in story questions." }
	-- Two columns of one-line fields (label, 36 px input, hint or error), then
	-- the long field across the full width (SetupWizard.dc.html grid).
	local top = -(L.portrait + 12)
	for i = 1, 4 do
		local field = F[i]
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		fieldBox(p, field, col * (COLUMN_WIDTH + COLUMN_GAP), top - row * L.fieldRow, COLUMN_WIDTH, L.field,
			hints[field.key])
	end
	for i = 5, #F do
		fieldBox(p, F[i], 0, top - 2 * L.fieldRow - (i - 5) * 112, BODY_WIDTH, L.area, hints[F[i].key])
	end
	-- Keyboard: Tab / Shift+Tab between the fields, Enter on a one-line field
	-- moves on (and after the last, to the next page), Escape closes setup
	-- (what was typed is kept in the draft, so nothing is lost).
	wizard.chain = Widgets.FocusChain({
		onSubmit = function() SetupWizard.Next() end,
		onEscape = function() SetupWizard.Close() end,
	})
	wizard.chain.SetFields(wizard.inputs)
	-- The profile note (v0.9): what these details are for. No privacy
	-- classification here; a detail can be made Private later.
	local note = panel(p, nil, 0, -346, BODY_WIDTH, 46)
	wizard.profileNote = note
	wizard.profileNoteText = paragraph(note.inner, 0, 0, INNER_WIDTH - 160, SetupWizard.PROFILE_NOTE, "small")
	wizard.profileNoteText:SetPoint("TOPLEFT", 0, 3)
	-- A story the player already wrote (#23): its own window, saved only
	-- when they choose Save there; this setup is not affected.
	wizard.importStory = Widgets.Button(note.inner, "Import a story...", 150, Style.CONTROL.compact)
	wizard.importStory:SetPoint("RIGHT", 0, 0)
	wizard.importStory:SetScript("OnClick", function() ns.ImportWizard.Open({ from = "setup" }) end)
	Widgets.Tooltip(wizard.importStory, "Import a story", "Already wrote a backstory, or have one in Total RP 3? "
		.. "Paste or read it in; it is kept exactly as written, and you approve each piece before it becomes "
		.. "part of your character.")
end

local function buildStory()
	local p = pageFrame("story")
	-- The backstory (v0.9): the complete story, kept word for word; with
	-- Total RP 3 connected it becomes the profile's About text.
	local bio = panel(p, "Backstory", 0, 0, BODY_WIDTH, 86)
	wizard.storyState = paragraph(bio.inner, 0, 0, INNER_WIDTH - 170, "", "small")
	wizard.storyImport = Widgets.Button(bio.inner, "Import a story...", 156, Style.CONTROL.compact)
	wizard.storyImport:SetPoint("TOPRIGHT", 0, 2)
	wizard.storyImport:SetScript("OnClick", function() ns.ImportWizard.Open({ from = "setup" }) end)
	Widgets.Tooltip(wizard.storyImport, "Import a story", "Paste your character's whole backstory, or read it from "
		.. "Total RP 3. It is kept exactly as written, paragraphs and all.")
	local top = -100
	local qH = 36 + #Onboarding.PREFS * L.cycleRow + 4
	local q = panel(p, "Story questions", 0, top, BODY_WIDTH, qH)
	for i, pref in ipairs(Onboarding.PREFS) do
		cycleRow(q.inner, -(i - 1) * L.cycleRow, pref, INNER_WIDTH)
	end
	paragraph(p, 0, top - qH - 10, BODY_WIDTH, "Dawnward may ask a quiet question when something worth remembering "
		.. "happens, never in combat. Your homeland and the places, people and goals you care about matter most.",
		"muted")
end

local function buildTRP3()
	local p = pageFrame("trp3")
	local status = panel(p, "Your Total RP 3 profile", 0, 0, BODY_WIDTH, 112)
	wizard.trp3Chip = Widgets.Chip(status.inner, "Total RP 3", "muted")
	wizard.trp3Chip:SetPoint("TOPLEFT", 0, 0)
	wizard.trp3 = Widgets.Label(status.inner, "GameFontHighlightSmall", true, "body")
	wizard.trp3:SetPoint("TOPLEFT", 0, -28)
	wizard.trp3:SetWidth(INNER_WIDTH)
	wizard.trp3Warn = Widgets.Label(status.inner, "GameFontHighlightSmall", true, "danger")
	wizard.trp3Warn:SetPoint("TOPLEFT", 0, -50)
	wizard.trp3Warn:SetWidth(INNER_WIDTH)

	local choicesH = 36 + #Onboarding.TRP3_CHOICES * L.cycleRow + 4
	local choices = panel(p, "Connection", 0, -126, BODY_WIDTH, choicesH)
	wizard.trp3Cycles = {}
	for i, choice in ipairs(Onboarding.TRP3_CHOICES) do
		wizard.trp3Cycles[choice.key] = cycleRow(choices.inner, -(i - 1) * L.cycleRow, choice, INNER_WIDTH)
	end
	wizard.trp3Note = paragraph(p, 0, -126 - choicesH - 10, BODY_WIDTH, SetupWizard.TRP3_NOTE, "muted")
end

local function buildAppearance()
	local p = pageFrame("appearance")
	local rows = math.ceil(#Themes.LIST / 3)
	local themes = panel(p, "Theme", 0, 0, BODY_WIDTH, 36 + rows * 42 + 60)
	wizard.themeTiles = {}
	local tileWidth = math.floor((INNER_WIDTH - 16) / 3)
	for i, theme in ipairs(Themes.LIST) do
		local tile = Widgets.Button(themes.inner, theme.name, tileWidth, 36, "choice")
		tile:SetPoint("TOPLEFT", ((i - 1) % 3) * (tileWidth + 8), -math.floor((i - 1) / 3) * 42)
		-- Round swatches (square where the client has no masks).
		for k, role in ipairs({ "background", "surface", "accent" }) do
			local ring = Style.Disc(tile, "ARTWORK", 0, 14)
			ring:SetPoint("RIGHT", -8 - (3 - k) * 17, 0)
			Style.Register(ring, function(t, current) Style.Color(t, current.edge) end)
			local sw = Style.Disc(tile, "ARTWORK", 1, ring.round and 12 or 14)
			sw:SetPoint("CENTER", ring, "CENTER", 0, 0)
			Widgets.SetColor(sw, theme[role])
		end
		-- The chosen theme also carries a gold bar on its left edge.
		tile.mark = Style.Solid(tile, "ARTWORK", 2)
		tile.mark:SetPoint("TOPLEFT", 0, 0)
		tile.mark:SetPoint("BOTTOMLEFT", 0, 0)
		tile.mark:SetWidth(3)
		Style.Register(tile.mark, function(t, current) Style.Color(t, current.accent) end)
		tile.mark:Hide()
		tile.themeId = theme.id
		tile:SetScript("OnClick", function()
			wizard.values.theme = theme.id
			wizard.edited.theme = true
			SetupWizard.Refresh()
		end)
		Widgets.Tooltip(tile, theme.name, theme.description)
		wizard.themeTiles[i] = tile
	end
	wizard.themeNote = paragraph(themes.inner, 0, -rows * 42 - 4, INNER_WIDTH, "", "muted")
	paragraph(p, 0, -(36 + rows * 42 + 60) - 2, BODY_WIDTH, "It changes only how the journal looks, and never "
		.. "depends on class, race or faction.", "muted")

	local mini = panel(p, "Minimap", 0, -(36 + rows * 42 + 60) - 34, BODY_WIDTH, 36 + L.cycle + 14)
	cycleRow(mini.inner, 0, { key = "minimap", label = "Minimap button",
		values = { { true, "Show the button on the minimap" }, { false, "Hide it (/dawnward still works)" } } },
		INNER_WIDTH)
end

local function buildFinish()
	local p = pageFrame("finish")
	local left = panel(p, "Character", 0, 0, COLUMN_WIDTH, 250)
	wizard.summary = Widgets.Label(left.inner, "GameFontHighlightSmall", true, "small")
	wizard.summary:SetPoint("TOPLEFT", 0, 0)
	wizard.summary:SetWidth(COLUMN_WIDTH - 2 * Widgets.PANEL_PAD)
	local right = panel(p, "Story and appearance", COLUMN_WIDTH + COLUMN_GAP, 0, COLUMN_WIDTH, 250)
	wizard.choices = Widgets.Label(right.inner, "GameFontHighlightSmall", true, "small")
	wizard.choices:SetPoint("TOPLEFT", 0, 0)
	wizard.choices:SetWidth(COLUMN_WIDTH - 2 * Widgets.PANEL_PAD)
	local note = panel(p, "Before you finish", 0, -266, BODY_WIDTH, 100, true)
	wizard.finishNote = paragraph(note.inner, 0, 0, INNER_WIDTH, "", "small")
end

local function buildPages()
	buildWelcome()
	buildCharacter()
	buildStory()
	buildAppearance()
	buildTRP3()
	buildFinish()
end

--- Step rail ---------------------------------------------------------------------------

-- States (SetupWizard.dc.html .step): done (gold-tinted badge with the
-- check mark, light text), current (gold badge, raised row with the
-- ornament edge, title-white text), future (an edged badge, muted text).
local function paintStep(step, theme)
	local s = step.state
	local current, done = s == "current", s == "done"
	local tones = Style.Tones(theme)
	Style.Color(step.bg, theme.surfaceHover, current and 1 or (step.hover and 0.6 or 0))
	step.edges:Paint(theme.border, current and 1 or 0)
	local fill = current and theme.accent or done and Style.Mix(theme.surface, theme.accent, 0.12) or theme.panel
	local edge = current and theme.accent or done and theme.border or tones.edgeStrong
	Style.Color(step.badgeRing, edge)
	Style.Color(step.badgeBg, fill)
	if not step.badgeRing.round then
		-- Square fallback: the ring would hide under the fill, so draw an edge.
		step.badgeEdges:Paint(edge, 1)
	end
	Style.TextColor(step.num, current and theme.accentText or theme.muted)
	step.num:SetShown(not done)
	step.check:SetShown(done)
	local gold = tones.accentBright
	step.check:SetVertexColor(gold[1], gold[2], gold[3])
	Style.TextColor(step.label, current and tones.heading or done and tones.ghostText or theme.muted)
end

local function buildRail()
	wizard.railBg = Style.Fill(wizard, "panel", "BACKGROUND", -6)
	wizard.railBg:SetPoint("TOPLEFT", 1, -1)
	wizard.railBg:SetPoint("BOTTOMLEFT", 1, 1)
	wizard.railBg:SetWidth(L.rail - 1)
	wizard.railLine = Widgets.Divider(wizard)
	wizard.railLine:SetWidth(1)
	wizard.railLine:SetPoint("TOPLEFT", L.rail, -1)
	wizard.railLine:SetPoint("BOTTOMLEFT", L.rail, 1)

	-- Wordmark: the shell's gold jewel and DAWNWARD (Cinzel 13, gold).
	wizard.jewel = Widgets.Solid(wizard, "ARTWORK")
	wizard.jewel:SetSize(8, 8)
	wizard.jewel:SetPoint("CENTER", wizard, "TOPLEFT", 30, -L.top - 8)
	if wizard.jewel.SetRotation then wizard.jewel:SetRotation(math.pi / 4) end
	Style.Register(wizard.jewel, function(t, theme) Style.Color(t, theme.accent) end)
	wizard.brand = Widgets.Label(wizard, nil, false, "eyebrow")
	Widgets.SetTextRole(wizard.brand, "accent")
	wizard.brand:SetPoint("TOPLEFT", 42, -L.top)
	wizard.brand:SetText("DAWNWARD")
	wizard.eyebrow = Widgets.Label(wizard, "GameFontNormalSmall", true, "eyebrow")
	wizard.eyebrow:SetPoint("TOPLEFT", 24, -L.top - 26)
	wizard.eyebrow:SetWidth(L.rail - 48)

	wizard.steps = {}
	for i, page in ipairs(Onboarding.PAGES) do
		local step = CreateFrame("Button", nil, wizard)
		step:SetSize(L.rail - 32, L.step)
		step:SetPoint("TOPLEFT", 16, -L.stepsTop - (i - 1) * (L.step + L.stepGap))
		step.index = i
		step.bg = Style.Solid(step, "BACKGROUND")
		step.bg:SetAllPoints(step)
		step.edges = Style.Edge(step, "BORDER")
		step.badge = CreateFrame("Frame", nil, step)
		step.badge:SetSize(L.badge, L.badge)
		step.badge:SetPoint("LEFT", 10, 0)
		-- A round badge: an edge-coloured disc under a fill disc 2 px smaller.
		step.badgeRing = Style.Disc(step.badge, "BACKGROUND", 0, L.badge)
		step.badgeRing:SetPoint("CENTER", 0, 0)
		step.badgeBg = Style.Disc(step.badge, "BACKGROUND", 1, step.badgeRing.round and L.badge - 2 or L.badge)
		step.badgeBg:SetPoint("CENTER", 0, 0)
		step.badgeEdges = Style.Edge(step.badge, "BORDER")
		step.badgeEdges:SetShown(not step.badgeRing.round)
		step.num = step.badge:CreateFontString(nil, "OVERLAY", Style.FontFor("badge"))
		step.num:SetPoint("CENTER", 0, 0)
		step.num:SetText(tostring(i))
		step.check = step.badge:CreateTexture(nil, "OVERLAY")
		step.check:SetTexture(SetupWizard.CHECK_TEXTURE)
		step.check:SetSize(20, 20)
		step.check:SetPoint("CENTER", 0, 0)
		step.label = Widgets.Label(step, "reading")
		step.label:SetPoint("LEFT", step.badge, "RIGHT", 12, 0)
		step.label:SetText(page.title)
		step.state = "future"
		step:SetScript("OnClick", function(self) SetupWizard.Step(self.index) end)
		step:SetScript("OnEnter", function(self) self.hover = true; Style.Repaint(self) end)
		step:SetScript("OnLeave", function(self) self.hover = nil; Style.Repaint(self) end)
		wizard.steps[i] = Style.Register(step, paintStep)
	end

	wizard.railNote = Widgets.Label(wizard, "GameFontHighlightSmall", true, "muted")
	wizard.railNote:SetPoint("BOTTOMLEFT", 24, 24)
	wizard.railNote:SetWidth(L.rail - 48)
end

-- Places the visible stages in order and numbers them 1..m; a stage that
-- does not apply this time (Total RP 3 not installed) is hidden.
local function layoutRail()
	local position = {}
	for n, index in ipairs(wizard.visible) do
		position[index] = n
	end
	for i, step in ipairs(wizard.steps) do
		local n = position[i]
		step:SetShown(n ~= nil)
		if n then
			step:ClearAllPoints()
			step:SetPoint("TOPLEFT", 16, -L.stepsTop - (n - 1) * (L.step + L.stepGap))
			step.num:SetText(tostring(n))
		end
	end
	wizard.position = position
end

--- Frame -------------------------------------------------------------------------------

local function build()
	wizard = CreateFrame("Frame", SetupWizard.FRAME_NAME, UIParent)
	wizard:SetSize(L.width, L.height)
	wizard:SetPoint("CENTER")
	wizard:SetFrameStrata(SetupWizard.STRATA)
	wizard:SetToplevel(true)
	wizard:SetClampedToScreen(true)
	wizard:EnableMouse(true)
	wizard:SetMovable(true)
	wizard:RegisterForDrag("LeftButton")
	wizard:SetScript("OnDragStart", wizard.StartMoving)
	wizard:SetScript("OnDragStop", wizard.StopMovingOrSizing)
	Style.Chrome(wizard, "background")
	wizard.pages, wizard.cycles = {}, {}

	buildRail()

	local x = L.rail + L.pad
	-- Header (SetupWizard.dc.html): STEP n OF 6, the stage title in Cinzel
	-- (the shell's screen title style), a one-line subtitle; the 36 px close.
	wizard.stepLabel = Widgets.Label(wizard, "GameFontNormalSmall", false, "eyebrow")
	wizard.stepLabel:SetPoint("TOPLEFT", x, -L.top)
	wizard.title = Widgets.Label(wizard, "GameFontNormalHuge", false, "title")
	wizard.title:SetPoint("TOPLEFT", x, -L.top - 20)
	wizard.subtitle = Widgets.Label(wizard, "GameFontHighlight", false, "muted")
	Widgets.SetTextRole(wizard.subtitle, "navText")
	wizard.subtitle:SetPoint("TOPLEFT", x, -L.top - 60)
	wizard.subtitle:SetWidth(BODY_WIDTH - 44)
	wizard.close = Widgets.IconButton(wizard, "X", "Close", "Close setup. It resumes where you left it the next "
		.. "time you open Dawnward, or from Settings > Run setup.")
	wizard.close:SetSize(Style.CONTROL.icon, Style.CONTROL.icon)
	wizard.close:SetPoint("TOPRIGHT", -L.pad, -L.top)
	wizard.close:SetScript("OnClick", function() SetupWizard.Close() end)

	buildPages()

	-- Footer: Set up later (quiet, left); Back (secondary) and Next / Finish
	-- (primary) on the right; Close preview beside them in test mode.
	wizard.later = Widgets.Button(wizard, "Set up later", 120, L.button, "ghost")
	wizard.later:SetPoint("BOTTOMLEFT", x, 22)
	wizard.later:SetScript("OnClick", function() SetupWizard.Later() end)
	Widgets.Tooltip(wizard.later, "Set up later", "Keep your answers and open the journal. Setup resumes the "
		.. "next time you log in, or from Settings > Run setup.")
	wizard.next = Widgets.Button(wizard, "Next", 170, L.button, "primary")
	wizard.next:SetPoint("BOTTOMRIGHT", -L.pad, 22)
	wizard.next:SetScript("OnClick", function() SetupWizard.Next() end)
	wizard.back = Widgets.Button(wizard, "Back", 96, L.button)
	wizard.back:SetPoint("RIGHT", wizard.next, "LEFT", -10, 0)
	wizard.back:SetScript("OnClick", function() SetupWizard.Back() end)
	wizard.discard = Widgets.Button(wizard, "Close preview", 130, L.button)
	wizard.discard:SetPoint("RIGHT", wizard.back, "LEFT", -10, 0)
	wizard.discard:SetScript("OnClick", function() SetupWizard.Close() end)

	wizard:SetScript("OnHide", function() SetupWizard.OnHide() end)
	if UISpecialFrames then
		tinsert(UISpecialFrames, SetupWizard.FRAME_NAME) -- Escape closes (and keeps the draft)
	end
	wizard:Hide()
end

--- State --------------------------------------------------------------------------------

-- Reads the text inputs into the values table, noting what the player
-- changed (compared with what the box was filled with).
local function collect()
	for _, input in ipairs(wizard.inputs) do
		local text = input:GetText() or ""
		if text ~= (wizard.initial[input.fieldKey] or "") then
			wizard.edited[input.fieldKey] = true
		end
		wizard.values[input.fieldKey] = text
		input:ClearFocus()
	end
end

local function fill()
	for _, input in ipairs(wizard.inputs) do
		input:SetText(wizard.values[input.fieldKey] or "")
		Widgets.SetFieldError(input, nil)
	end
end

-- Only what the player changed goes into the draft.
local function saveDraft()
	if wizard.test or wizard.readOnly or wizard.finished then
		return
	end
	local changed = {}
	for key in pairs(wizard.edited) do changed[key] = wizard.values[key] end
	Actions.SaveSetupDraft(ns.ctx, { page = wizard.page, values = changed })
end

local function characterTheme()
	return Actions.ThemeOf(Actions.Character(ns.ctx))
end

local function pageIndex(id)
	for i, page in ipairs(Onboarding.PAGES) do
		if page.id == id then return i end
	end
end

-- The visible stage after (step 1) or before (step -1) page index i, or nil.
local function neighbour(i, step)
	local n = wizard.position[i]
	local target = n and wizard.visible[n + step]
	return target
end

-- A page index that is visible: i itself, else the next visible one, else the last.
local function visibleFrom(i)
	for _, index in ipairs(wizard.visible) do
		if index >= i then return index end
	end
	return wizard.visible[#wizard.visible]
end

--- Inline validation of the Character stage: a field longer than its limit
-- is marked and named beneath it (rather than silently cut short). Returns
-- the first invalid input, or nil when everything fits.
function SetupWizard.Validate()
	local first
	for _, input in ipairs(wizard.inputs) do
		local text = input:GetText() or ""
		local field = input.field
		local message = #text > field.max and string.format("%s can be at most %d characters", field.label, field.max)
			or nil
		Widgets.SetFieldError(input, message)
		if message and not first then first = input end
	end
	return first
end

-- Whether Total RP 3 is installed (the stage is shown only then). Read only.
local function trp3Installed()
	local status = ns.ctx.trp3Status and ns.ctx.trp3Status()
	return type(status) == "table" and not status.error and (status.installed or status.loaded) and true or false
end

--- What the Total RP 3 stage shows: { chip, tone, line, warn, connectable }.
-- The installed state comes from the same status read as everywhere else
-- (ctx.trp3Status); the active profile from the adapter's probe, read only.
function SetupWizard.TRP3View()
	local view = { chip = "Not installed", tone = "muted", line = "Total RP 3 is not installed. Dawnward works "
		.. "fully without it.", connectable = false }
	local status = ns.ctx.trp3Status and ns.ctx.trp3Status()
	if type(status) ~= "table" then
		return view
	end
	if status.error then
		view.chip, view.tone, view.line = "Could not be read", "danger", "Total RP 3 could not be read safely."
		return view
	end
	if not status.loaded then
		if status.installed then
			view.chip = "Installed, not loaded"
			view.line = "Total RP 3 is installed but not loaded. Enable it at the character screen to connect it."
		end
		return view
	end
	view.chip, view.tone = "Total RP 3 " .. tostring(status.version or ""), "accent"
	local probe = ns.TRP3Adapter and ns.TRP3Adapter.Probe(_G)
	local profile = probe and probe.profile
	view.line = profile and profile.name and ("Active profile: " .. tostring(profile.name)) or "Active profile: unknown"
	if profile and profile.sharedWith and profile.sharedWith > 0 then
		view.line = view.line .. string.format(" (also used by %d other character%s; they would show the same)",
			profile.sharedWith, profile.sharedWith == 1 and "" or "s")
	end
	view.connectable = probe ~= nil and probe.experimental.allowed == true
	if not view.connectable then
		view.warn = "Cannot connect right now: " .. (probe and table.concat(probe.experimental.reasons, "; ")
			or "Total RP 3 could not be read") .. ". You can connect later in Settings > Total RP 3."
	end
	return view
end

local function refreshIdentity()
	local game = ns.Showcase.GameIdentity()
	local ok, name = pcall(UnitName, "player")
	local parts = {}
	if ok and type(name) == "string" and name ~= "" then parts[#parts + 1] = name end
	if game.level then parts[#parts + 1] = "Level " .. game.level end
	local line = ns.Showcase.IdentityLine(game, nil)
	if line ~= "" then parts[#parts + 1] = line end
	wizard.identity:SetText(#parts > 0 and table.concat(parts, "  ·  ") or "Your character")
	wizard.portrait.Update()
end

--- Redraws the current page from the values.
function SetupWizard.Refresh()
	if not wizard then return end
	local count = #wizard.visible
	local page = Onboarding.PAGES[wizard.page]
	local at = wizard.position[wizard.page] or 1
	wizard.stepLabel:SetText(string.format("STEP %d OF %d", at, count))
	wizard.title:SetText(page.title)
	wizard.subtitle:SetText(SetupWizard.SUBTITLES[page.id] or "")
	for i, step in ipairs(wizard.steps) do
		local n = wizard.position[i]
		step.state = n and (n < at and "done" or n == at and "current") or "future"
		Style.Repaint(step)
	end
	for id, frame in pairs(wizard.pages) do
		frame:SetShown(id == page.id)
	end
	for _, b in ipairs(wizard.cycles) do
		b:Update()
	end
	-- Appearance: the chosen theme is previewed on the wizard itself.
	for _, tile in ipairs(wizard.themeTiles) do
		tile:SetSelected(tile.themeId == wizard.values.theme)
		tile.mark:SetShown(tile.themeId == wizard.values.theme)
	end
	local theme = Themes.Get(wizard.values.theme)
	wizard.themeNote:SetText(theme.name .. ": " .. theme.description)
	if Style.Current() ~= theme then
		Style.Apply(theme)
	end
	if page.id == "character" then
		refreshIdentity()
	elseif page.id == "story" then
		local current = Actions.Character(ns.ctx) and ns.Sources.Current(Actions.Character(ns.ctx))
		wizard.storyState:SetText(current and string.format("Your backstory is saved word for word (%d paragraphs). "
			.. "Import again to replace it; earlier versions are kept.", #ns.Sources.Paragraphs(current.text))
			or "No backstory yet. Import the story you already wrote, or add it later from the Character tab.")
	elseif page.id == "trp3" then
		local view = SetupWizard.TRP3View()
		wizard.trp3View = view
		wizard.trp3Chip:SetChip(view.chip, view.tone)
		wizard.trp3:SetText(view.line)
		wizard.trp3Warn:SetText(view.warn or "")
		for _, b in pairs(wizard.trp3Cycles) do
			b:SetEnabled(view.connectable)
		end
		if not view.connectable then
			wizard.trp3Cycles.trp3:SetText("Not available now")
		end
		wizard.trp3Cycles.trp3Existing:SetEnabled(view.connectable and wizard.values.trp3 == "connect")
	end
	local last = wizard.page == wizard.visible[count]
	if last then
		local lines = Onboarding.Summary(wizard.values)
		local nFields = #Onboarding.FIELDS
		local trp3Line = Onboarding.TRP3Summary(wizard.values, wizard.trp3Shown)
		if trp3Line and not SetupWizard.CanConnect() then
			trp3Line = "Total RP 3: not connected now (connect later in Settings > Total RP 3)"
		end
		if trp3Line then lines[#lines + 1] = trp3Line end
		wizard.summary:SetText(table.concat(lines, "\n", 1, nFields))
		wizard.choices:SetText(table.concat(lines, "\n", nFields + 1, #lines))
		local blocked = wizard.simulation and "Simulation mode is on, so setup cannot be saved. Turn simulation "
			.. "off (Settings > Data) and run setup again."
			or wizard.readOnly and "Saved data is read-only this session, so setup cannot be saved. Nothing has "
			.. "been changed."
		wizard.finishNote:SetText(blocked or wizard.test and "Preview: Save choices applies these choices "
			.. "to this character without changing its setup status. Close preview discards them."
			or (SetupWizard.WillConnect() and "Finish saves your choices and connects Total RP 3: your Public "
				.. "details, backstory and personality are written there after a backup. Nothing you already had "
				.. "in Dawnward is cleared."
				or "Finish saves only what you changed here and never clears a detail you already had. Nothing is "
				.. "sent to Total RP 3."))
	end
	wizard.railNote:SetText(wizard.test and "Preview: nothing is kept when you close it. Choices are saved only "
		.. "with Save choices."
		or wizard.readOnly and "Preview only: nothing can be saved this session."
		or "Your answers are kept if you close this. Nothing is saved to your profile until you choose Finish.")
	wizard.back:SetEnabled(neighbour(wizard.page, -1) ~= nil)
	wizard.later:SetShown(not wizard.test)
	wizard.discard:SetShown(wizard.test and last or false)
	local following = neighbour(wizard.page, 1)
	wizard.next:SetText(following and ("Next: " .. Onboarding.PAGES[following].title)
		or wizard.test and "Save choices" or "Finish")
	wizard.next:SetEnabled(not (last and wizard.readOnly))
end

-- Focuses the first editable field on the current page, if it has one.
local function focusPage()
	if Onboarding.PAGES[wizard.page].id == "character" then
		wizard.chain.FocusFirst()
	end
end

--- Whether Finish will connect Total RP 3 (the stage was shown, the
-- player chose Connect, and connecting is possible now).
function SetupWizard.CanConnect()
	return wizard.trp3Shown and (wizard.trp3View == nil or wizard.trp3View.connectable) or false
end

function SetupWizard.WillConnect()
	return SetupWizard.CanConnect() and wizard.values.trp3 == "connect" and not wizard.test
end

--- Goes to page n (values kept; the draft is saved).
function SetupWizard.Go(n)
	collect()
	wizard.page = visibleFrom(math.max(1, math.min(n, #Onboarding.PAGES)))
	saveDraft()
	SetupWizard.Refresh()
	focusPage()
end

--- Moves to page n as the player asked (Next, Enter, a step in the rail):
-- leaving the Character stage forwards first checks its fields inline.
function SetupWizard.Step(n)
	local character = pageIndex("character")
	if wizard.page == character and n > character then
		local bad = SetupWizard.Validate()
		if bad then
			bad:SetFocus()
			return false
		end
	end
	SetupWizard.Go(n)
	return true
end

--- Next (or, on the last page, Finish / Save choices).
function SetupWizard.Next()
	local following = neighbour(wizard.page, 1)
	if following then
		SetupWizard.Step(following)
	else
		SetupWizard.Finish()
	end
end

--- Back to the previous visible stage.
function SetupWizard.Back()
	local previous = neighbour(wizard.page, -1)
	if previous then
		SetupWizard.Go(previous)
	end
end

--- Opens the wizard. opts.test: developer preview (/dawnward dev setup).
function SetupWizard.Open(opts)
	opts = opts or {}
	local ctx = ns.ctx
	if not ctx then return false end
	if not wizard then build() end
	-- A running wizard keeps what was typed since the last step.
	if wizard:IsShown() and wizard.values and not wizard.test then
		collect()
		saveDraft()
	end
	local char = Actions.Character(ctx)
	local name = UnitName and UnitName("player") or nil
	local values = Onboarding.DefaultValues(char, name, not Actions.MinimapSettings(ctx).hidden)
	local page, edited = 1, {}
	-- The draft holds only what the player changed; everything else comes
	-- fresh from the character, so newer settings are kept.
	local initial = {}
	for k, v in pairs(values) do initial[k] = v end
	if not opts.test then
		local draft = Actions.SetupDraft(ctx)
		if draft then
			for k, v in pairs(draft.values) do
				values[k] = v
				edited[k] = true
			end
			page = draft.page
		end
	end
	wizard.test = opts.test and true or false
	wizard.simulation = ctx.store:IsSimulation()
	-- Simulation mode: a preview that cannot save, so real and test data never mix.
	wizard.readOnly = ctx.store:ReadOnlyReason() ~= nil or wizard.simulation
	wizard.initial, wizard.edited = initial, edited
	wizard.finished = false
	wizard.trp3Shown = trp3Installed()
	wizard.trp3View = nil
	wizard.visible = Onboarding.VisiblePages(wizard.trp3Shown)
	layoutRail()
	wizard.values = values
	wizard.page = visibleFrom(page)
	-- At most two lines in the rail; the rail note says what the mode means.
	wizard.eyebrow:SetText(wizard.test and "PREVIEW · TEST MODE"
		or wizard.simulation and "SIMULATION · PREVIEW ONLY"
		or wizard.readOnly and "READ-ONLY · NOTHING SAVED" or "FIRST-TIME SETUP")
	wizard.eyebrow.textRole = (wizard.test or wizard.readOnly) and "danger" or "ornament"
	Style.Repaint(wizard.eyebrow)
	fill()
	wizard.chain.SetFields(wizard.inputs) -- the starting text, for comparison
	-- Fits small screens the same way as the main window.
	wizard.fitScale = Style.FitScale(L.height, UIParent.GetHeight and UIParent:GetHeight(), nil,
		L.width, UIParent.GetWidth and UIParent:GetWidth())
	wizard:SetScale(wizard.fitScale)
	wizard:Show()
	if wizard.Raise then wizard:Raise() end
	SetupWizard.Refresh()
	focusPage()
	return true
end

--- Finish (or, in test mode, Save choices).
function SetupWizard.Finish()
	local bad = SetupWizard.Validate()
	if bad then
		SetupWizard.Go(pageIndex("character")) -- the marks stay; Go only redraws
		bad:SetFocus()
		return
	end
	collect()
	if wizard.readOnly then return end
	local connect = SetupWizard.WillConnect()
	local ok, message = Actions.CompleteSetup(ns.ctx, wizard.values, { test = wizard.test, only = wizard.edited,
		trp3Shown = connect })
	if not ok then
		wizard.finishNote:SetText(message)
		return
	end
	wizard.finished = true
	local test = wizard.test
	wizard:Hide()
	if not test then
		MainWindow.Show(true)
		MainWindow.Select("journal")
	end
	MainWindow.SetStatus(message)
	MainWindow.Refresh()
end

--- Closes without finishing: the draft is kept (not in test mode).
function SetupWizard.Close()
	wizard:Hide()
end

--- "Set up later": keep the draft and open the journal.
function SetupWizard.Later()
	wizard:Hide()
	MainWindow.Show(true)
end

function SetupWizard.OnHide()
	if not wizard.values then
		return -- the frame is created shown and hidden once while being built
	end
	if not wizard.finished then
		collect()
		saveDraft()
	end
	-- Back to the character's own theme after any preview.
	Style.Apply(characterTheme())
	MainWindow.Refresh()
end

function SetupWizard.IsShown()
	return wizard ~= nil and wizard:IsShown()
end

--- For tests and diagnostics only.
function SetupWizard.Frame()
	return wizard
end

--- Stops the wizard from opening by itself for key this session (as if it
-- had already been shown). Saved data is not touched.
function SetupWizard.SkipAutoLaunchThisSession(key)
	autoShown[key] = true
end

function SetupWizard.WasAutoShown(key)
	return autoShown[key] == true
end

--- MainWindow.BeforeShow: opens the wizard instead of the journal the first
-- time a genuinely new character opens Dawnward (once per session; never
-- in simulation mode or on read-only data). Returns true when it opened.
function SetupWizard.MaybeAutoLaunch()
	local ctx = ns.ctx
	if not ctx or ctx.store:IsSimulation() or ctx.store:ReadOnlyReason() then
		return false
	end
	if SetupWizard.IsShown() then
		return true
	end
	if autoShown[ctx.characterKey] then
		return false
	end
	local char = ctx.store.real.characters[ctx.characterKey]
	if not Onboarding.ShouldAutoLaunch(char, ctx.now()) then
		return false
	end
	autoShown[ctx.characterKey] = true
	return SetupWizard.Open({})
end

MainWindow.BeforeShow = SetupWizard.MaybeAutoLaunch
