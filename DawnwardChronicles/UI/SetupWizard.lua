-- The first-time setup wizard (v0.6 rules, v0.7 look): Welcome, Character,
-- Story, Privacy, Appearance, Finish. Rules (docs/design/UI_DESIGN_V06.md,
-- section 5):
--
--   * it opens by itself only for a genuinely new character, once per
--     session, when the player opens Dawnward (MainWindow.BeforeShow)
--   * values are kept while moving between pages; what the player changed
--     is saved as a draft on every step and on close, so it resumes where
--     it was left (only changed keys are kept and applied, so settings
--     changed elsewhere meanwhile are never undone)
--   * nothing is written to the character, and setup is not marked
--     complete, until Finish; Finish never clears an existing value and
--     never writes to Total RP 3
--   * test mode (/dawnward dev setup) is a clearly marked preview: no
--     draft, no completion, and choices are saved only on "Save choices"
--   * in simulation mode or on read-only data it is a preview that cannot
--     save, so real and test data never mix
--
-- Layout (docs/design/mockups/first-time-setup.png, v0.7): an 820 x 600
-- dialog in the main window's design language. A left step rail lists the
-- six stages (done / current / upcoming; click one to go there), the right
-- side shows "STEP n OF 6", the stage title and subtitle, the stage's
-- grouped panels, and a footer with Set up later, Back and Next. Classic
-- Era has no rounded corners, so the step numbers sit in square badges and
-- the done mark is the game's own check texture. The dialog scales down to
-- fit small screens (Style.FitScale), like the main window.
local _, ns = ...
local Widgets, Style, Actions, Onboarding, Themes, MainWindow =
	ns.Widgets, ns.Style, ns.Actions, ns.Onboarding, ns.Themes, ns.MainWindow

local SetupWizard = {}
ns.SetupWizard = SetupWizard

SetupWizard.FRAME_NAME = "DawnwardChroniclesSetup"
SetupWizard.STRATA = "HIGH" -- above the journal (MEDIUM), below game dialogs
-- rail: step rail width; pad: content padding; bodyTop: where a stage's
-- panels start; footer: the button strip; button: footer button height.
SetupWizard.LAYOUT = { width = 820, height = 600, rail = 236, pad = 30, top = 26, bodyTop = 108, footer = 70,
	button = 30, step = 40, stepGap = 4, stepsTop = 104, field = 28 }

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
	welcome = "A private chronicle of your character. This takes about two minutes.",
	character = "Fill in what you know. Anything left empty can be added later.",
	story = "Choose how often Dawnward asks about what happens on your travels.",
	privacy = "Everything you add starts Private. Here is what each level means.",
	appearance = "Choose how this character's journal looks.",
	finish = "Review your choices. Finish saves them for this character.",
}

-- What each visibility level means (the Privacy stage's chips).
SetupWizard.PRIVACY_LEVELS = {
	{ "public", "May be shared: share exports and, only if you turn sync on later, Total RP 3." },
	{ "private", "Only you. Included in your personal backups. Everything starts here." },
	{ "secret", "Only you. Left out of backups unless you ask for it." },
}

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
local function cycleRow(parent, y, spec, width)
	local label = Widgets.Label(parent, "GameFontNormal", false, "heading")
	label:SetPoint("TOPLEFT", 0, y - 6)
	label:SetWidth(LABEL_WIDTH - 8)
	label:SetText(spec.label)
	local b = Widgets.Button(parent, "", width - LABEL_WIDTH, 26, "choice")
	b:SetPoint("TOPLEFT", LABEL_WIDTH, y)
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
		for _, v in ipairs(self.spec.values) do
			if v[1] == wizard.values[self.spec.key] then self:SetText(v[2]) end
		end
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
		area.frame:SetPoint("TOPLEFT", x, y - 20)
		area.frame:SetSize(width, height)
		input = area.edit
	else
		input = Widgets.EditLine(parent, maxBytes)
		input:SetPoint("TOPLEFT", x, y - 20)
		input:SetSize(width, height)
	end
	input.fieldKey, input.field = field.key, field
	Widgets.FieldError(input, width)
	if hint then
		local region = input.anchorRegion or input
		input.hint = Widgets.Label(parent, "GameFontHighlightSmall", true, "muted")
		input.hint:SetPoint("TOPLEFT", region, "BOTTOMLEFT", 0, -3)
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
	paragraph(b.inner, 0, 0, INNER_WIDTH, "It complements Total RP 3 rather than replacing it. Total RP 3 is your "
		.. "public profile; Dawnward is your character's private story.")
	local c = panel(p, "This setup", 0, -228, BODY_WIDTH, 100)
	paragraph(c.inner, 0, 0, INNER_WIDTH, "Everything is optional, everything starts private, and you can change "
		.. "any of it later in Settings. Close it at any time: your answers are kept.", "muted")
	paragraph(p, 0, -346, BODY_WIDTH, "Next: who your character is.", "accent")
end

local function buildCharacter()
	local p = pageFrame("character")
	-- The player's own portrait and the game's identity line: read live,
	-- never stored, nothing invented.
	wizard.portrait = ns.Showcase.Portrait(p, 56)
	wizard.portrait:SetPoint("TOPLEFT", 0, 0)
	wizard.identity = Widgets.Label(p, "GameFontNormal", false, "heading")
	wizard.identity:SetPoint("TOPLEFT", 70, -10)
	wizard.identity:SetWidth(BODY_WIDTH - 70)
	wizard.identityNote = Widgets.Label(p, "GameFontHighlightSmall", true, "muted")
	wizard.identityNote:SetPoint("TOPLEFT", 70, -30)
	wizard.identityNote:SetWidth(BODY_WIDTH - 70)
	wizard.identityNote:SetText("From the game. Existing details are kept; an empty box never erases anything.")

	wizard.inputs = {}
	local F = Onboarding.FIELDS
	local hints = { name = "Suggested from the game; change it freely.",
		pronouns = "Used in story questions." }
	local top = -72
	for i = 1, 4 do
		local field = F[i]
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		fieldBox(p, field, col * (COLUMN_WIDTH + COLUMN_GAP), top - row * 72, COLUMN_WIDTH, L.field,
			hints[field.key])
	end
	for i = 5, #F do
		fieldBox(p, F[i], 0, top - 144 - (i - 5) * 112, BODY_WIDTH, 80, hints[F[i].key])
	end
	-- Keyboard: Tab / Shift+Tab between the fields, Enter on a one-line field
	-- moves on (and after the last, to the next page), Escape closes setup
	-- (what was typed is kept in the draft, so nothing is lost).
	wizard.chain = Widgets.FocusChain({
		onSubmit = function() SetupWizard.Next() end,
		onEscape = function() SetupWizard.Close() end,
	})
	wizard.chain.SetFields(wizard.inputs)
	local note = panel(p, nil, 0, -346, BODY_WIDTH, 44, true)
	paragraph(note.inner, 0, 2, INNER_WIDTH, "Everything starts Private. Nothing is sent to Total RP 3 unless you "
		.. "choose to share it later.", "small")
end

local function buildStory()
	local p = pageFrame("story")
	local q = panel(p, "Story questions", 0, 0, BODY_WIDTH, 36 + #Onboarding.PREFS * 38 + 14)
	for i, pref in ipairs(Onboarding.PREFS) do
		cycleRow(q.inner, -(i - 1) * 38, pref, INNER_WIDTH)
	end
	paragraph(p, 0, -230, BODY_WIDTH, "When something worth remembering happens, Dawnward may ask a quiet question "
		.. "about it, never in combat.", "muted")
	paragraph(p, 0, -270, BODY_WIDTH, "Questions are weighted: your homeland and the places, people and goals you "
		.. "care about matter most. Ordinary travel is logged quietly.", "muted")
end

local function buildPrivacy()
	local p = pageFrame("privacy")
	local levels = panel(p, "Who sees what", 0, 0, BODY_WIDTH, 36 + #SetupWizard.PRIVACY_LEVELS * 34 + 6)
	wizard.privacyChips = {}
	for i, level in ipairs(SetupWizard.PRIVACY_LEVELS) do
		local y = -(i - 1) * 34
		local chip = Widgets.Chip(levels.inner, Themes.VISIBILITY_LABELS[level[1]], level[1])
		chip:SetPoint("TOPLEFT", 0, y)
		chip.level = level[1]
		wizard.privacyChips[i] = chip
		paragraph(levels.inner, 84, y - 3, INNER_WIDTH - 84, level[2], "small")
	end

	-- Total RP 3: status only. Setup never publishes anything to it.
	local trp3 = panel(p, "Total RP 3 (optional)", 0, -150, BODY_WIDTH, 150)
	wizard.trp3Chip = Widgets.Chip(trp3.inner, "Not installed", "muted")
	wizard.trp3Chip:SetPoint("TOPLEFT", 0, 0)
	wizard.trp3 = Widgets.Label(trp3.inner, "GameFontHighlightSmall", true, "muted")
	wizard.trp3:SetPoint("TOPLEFT", 0, -28)
	wizard.trp3:SetWidth(INNER_WIDTH)
	wizard.trp3Note = paragraph(trp3.inner, 0, -48, INNER_WIDTH, "Setup never publishes anything to Total RP 3 "
		.. "and does not turn sync on. If you want it later, /dawnward trp3 help explains how: it shares only "
		.. "what you made Public, backs up first and can be rolled back.")

	paragraph(p, 0, -316, BODY_WIDTH, "Dawnward never sends chat, emotes or whispers, and uses no internet or AI.",
		"muted")
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
		for k, role in ipairs({ "background", "surface", "accent" }) do
			local sw = Widgets.Solid(tile, "ARTWORK")
			sw:SetSize(12, 12)
			sw:SetPoint("RIGHT", -8 - (3 - k) * 14, 0)
			Widgets.SetColor(sw, theme[role])
		end
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

	local mini = panel(p, "Minimap", 0, -(36 + rows * 42 + 60) - 34, BODY_WIDTH, 36 + 26 + 14)
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
	buildPrivacy()
	buildAppearance()
	buildFinish()
end

--- Step rail ---------------------------------------------------------------------------

-- States: done (check mark), current (gold badge, highlighted row), future.
local function paintStep(step, theme)
	local s = step.state
	local current, done = s == "current", s == "done"
	Style.Color(step.bg, theme.surfaceHover, current and 1 or (step.hover and 0.6 or 0))
	step.edges:Paint(theme.border, current and 1 or 0)
	Style.Color(step.badgeBg, theme.accent, current and 1 or done and 0.16 or 0)
	step.badgeEdges:Paint(current and theme.accent or done and theme.border or theme.edge, 1)
	Style.TextColor(step.num, current and theme.accentText or theme.muted)
	step.num:SetShown(not done)
	step.check:SetShown(done)
	step.check:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3])
	Style.TextColor(step.label, (current or done) and theme.text or theme.muted)
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

	wizard.brand = Widgets.Label(wizard, "GameFontNormal", false, "title")
	wizard.brand:SetPoint("TOPLEFT", 24, -L.top)
	wizard.brand:SetText("DAWNWARD")
	wizard.eyebrow = Widgets.Label(wizard, "GameFontNormalSmall", true, "eyebrow")
	wizard.eyebrow:SetPoint("TOPLEFT", 24, -L.top - 22)
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
		step.badge:SetSize(24, 24)
		step.badge:SetPoint("LEFT", 10, 0)
		step.badgeBg = Style.Solid(step.badge, "BACKGROUND")
		step.badgeBg:SetAllPoints(step.badge)
		step.badgeEdges = Style.Edge(step.badge, "BORDER")
		step.num = step.badge:CreateFontString(nil, "OVERLAY", Style.Font("GameFontNormalSmall"))
		step.num:SetPoint("CENTER", 0, 0)
		step.num:SetText(tostring(i))
		step.check = step.badge:CreateTexture(nil, "OVERLAY")
		step.check:SetTexture(SetupWizard.CHECK_TEXTURE)
		step.check:SetSize(20, 20)
		step.check:SetPoint("CENTER", 0, 0)
		step.label = Widgets.Label(step, "GameFontHighlight")
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
	wizard.stepLabel = Widgets.Label(wizard, "GameFontNormalSmall", false, "eyebrow")
	wizard.stepLabel:SetPoint("TOPLEFT", x, -L.top)
	wizard.title = Widgets.Label(wizard, "GameFontNormalLarge", false, "title")
	wizard.title:SetPoint("TOPLEFT", x, -L.top - 18)
	wizard.subtitle = Widgets.Label(wizard, "GameFontHighlight", true, "muted")
	wizard.subtitle:SetPoint("TOPLEFT", x, -L.top - 46)
	wizard.subtitle:SetWidth(BODY_WIDTH - 40)
	wizard.close = Widgets.IconButton(wizard, "X", "Close", "Close setup. It resumes where you left it the next "
		.. "time you open Dawnward, or from Settings > Run setup.")
	wizard.close:SetSize(30, 30)
	wizard.close:SetPoint("TOPRIGHT", -L.pad + 6, -L.top + 6)
	wizard.close:SetScript("OnClick", function() SetupWizard.Close() end)

	buildPages()

	-- Footer: Set up later (quiet, left); Back (secondary) and Next / Finish
	-- (primary) on the right; Close preview beside them in test mode.
	wizard.later = Widgets.Button(wizard, "Set up later", 120, L.button, "ghost")
	wizard.later:SetPoint("BOTTOMLEFT", x, 22)
	wizard.later:SetScript("OnClick", function() SetupWizard.Later() end)
	Widgets.Tooltip(wizard.later, "Set up later", "Keep your answers and open the journal. Setup resumes the "
		.. "next time you log in, or from Settings > Run setup.")
	wizard.next = Widgets.Button(wizard, "Next", 150, L.button, "primary")
	wizard.next:SetPoint("BOTTOMRIGHT", -L.pad, 22)
	wizard.next:SetScript("OnClick", function() SetupWizard.Next() end)
	wizard.back = Widgets.Button(wizard, "Back", 90, L.button)
	wizard.back:SetPoint("RIGHT", wizard.next, "LEFT", -10, 0)
	wizard.back:SetScript("OnClick", function() SetupWizard.Go(wizard.page - 1) end)
	wizard.discard = Widgets.Button(wizard, "Close preview", 120, L.button)
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

-- The Total RP 3 status chip: installed or not, nothing more. Read only.
local function trp3Status()
	local status = ns.ctx.trp3Status and ns.ctx.trp3Status()
	if type(status) ~= "table" then
		return "Status unavailable", "muted"
	end
	if status.error then
		return "Could not be read", "danger"
	end
	if status.loaded then
		return "Installed", "accent"
	end
	return status.installed and "Installed, not loaded" or "Not installed", "muted"
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
	local count = #Onboarding.PAGES
	local page = Onboarding.PAGES[wizard.page]
	wizard.stepLabel:SetText(string.format("STEP %d OF %d", wizard.page, count))
	wizard.title:SetText(page.title)
	wizard.subtitle:SetText(SetupWizard.SUBTITLES[page.id] or "")
	for i, step in ipairs(wizard.steps) do
		step.state = i < wizard.page and "done" or i == wizard.page and "current" or "future"
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
	end
	local theme = Themes.Get(wizard.values.theme)
	wizard.themeNote:SetText(theme.name .. ": " .. theme.description)
	if Style.Current() ~= theme then
		Style.Apply(theme)
	end
	if page.id == "character" then
		refreshIdentity()
	elseif page.id == "privacy" then
		local text, tone = trp3Status()
		wizard.trp3Chip:SetChip("Total RP 3: " .. text, tone)
		local status = ns.ctx.trp3Status and ns.ctx.trp3Status()
		wizard.trp3:SetText(ns.Commands.Trp3Lines(status)[1] or "Total RP 3: not detected")
	end
	local last = wizard.page == count
	if last then
		local lines = Onboarding.Summary(wizard.values)
		local nFields = #Onboarding.FIELDS
		wizard.summary:SetText(table.concat(lines, "\n", 1, nFields))
		wizard.choices:SetText(table.concat(lines, "\n", nFields + 1, #lines))
		local blocked = wizard.simulation and "Simulation mode is on, so setup cannot be saved. Turn simulation "
			.. "off (Settings > Data) and run setup again."
			or wizard.readOnly and "Saved data is read-only this session, so setup cannot be saved. Nothing has "
			.. "been changed."
		wizard.finishNote:SetText(blocked or wizard.test and "Preview: Save choices applies these choices "
			.. "to this character without changing its setup status. Close preview discards them."
			or "Finish saves only what you changed here and never clears a detail you already had. Nothing is "
			.. "shared and nothing is sent to Total RP 3.")
	end
	wizard.railNote:SetText(wizard.test and "Preview: nothing is kept when you close it. Choices are saved only "
		.. "with Save choices."
		or wizard.readOnly and "Preview only: nothing can be saved this session."
		or "Your answers are kept if you close this. Nothing is saved to your profile until you choose Finish.")
	wizard.back:SetEnabled(wizard.page > 1)
	wizard.later:SetShown(not wizard.test)
	wizard.discard:SetShown(wizard.test and last or false)
	wizard.next:SetText(not last and ("Next: " .. Onboarding.PAGES[wizard.page + 1].title)
		or wizard.test and "Save choices" or "Finish")
	wizard.next:SetEnabled(not (last and wizard.readOnly))
end

-- Focuses the first editable field on the current page, if it has one.
local function focusPage()
	if Onboarding.PAGES[wizard.page].id == "character" then
		wizard.chain.FocusFirst()
	end
end

--- Goes to page n (values kept; the draft is saved).
function SetupWizard.Go(n)
	collect()
	wizard.page = math.max(1, math.min(n, #Onboarding.PAGES))
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
	if wizard.page < #Onboarding.PAGES then
		SetupWizard.Step(wizard.page + 1)
	else
		SetupWizard.Finish()
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
	wizard.values, wizard.page = values, page
	wizard.eyebrow:SetText(wizard.test and "PREVIEW  -  TEST MODE: NOTHING IS SAVED UNLESS YOU CHOOSE"
		or wizard.simulation and "FIRST-TIME SETUP  -  SIMULATION MODE: PREVIEW ONLY"
		or wizard.readOnly and "FIRST-TIME SETUP  -  READ-ONLY: NOTHING CAN BE SAVED" or "FIRST-TIME SETUP")
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
	local ok, message = Actions.CompleteSetup(ns.ctx, wizard.values, { test = wizard.test, only = wizard.edited })
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
