-- The first-time setup wizard (v0.6): Welcome, Character, Story, Privacy,
-- Appearance, Finish. Rules (docs/design/UI_DESIGN_V06.md, section 5):
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
local _, ns = ...
local Widgets, Style, Actions, Onboarding, Themes, MainWindow =
	ns.Widgets, ns.Style, ns.Actions, ns.Onboarding, ns.Themes, ns.MainWindow

local SetupWizard = {}
ns.SetupWizard = SetupWizard

SetupWizard.FRAME_NAME = "DawnwardChroniclesSetup"
SetupWizard.STRATA = "HIGH" -- above the journal (MEDIUM), below game dialogs
SetupWizard.LAYOUT = { width = 560, height = 470, pad = 24, bodyTop = 106, footer = 52 }

local L = SetupWizard.LAYOUT
local BODY_WIDTH = L.width - 2 * L.pad
local LABEL_WIDTH = 150

local wizard           -- the frame and its parts, built once
local autoShown = {}   -- characters the wizard opened for by itself this session

--- Pages ---------------------------------------------------------------------------

local function pageFrame(id)
	local p = CreateFrame("Frame", nil, wizard)
	p:SetPoint("TOPLEFT", L.pad, -L.bodyTop)
	p:SetPoint("BOTTOMRIGHT", -L.pad, L.footer + 8)
	p:Hide()
	wizard.pages[id] = p
	return p
end

local function paragraph(parent, y, text, role)
	local fs = Widgets.Label(parent, nil, true, role or "body")
	fs:SetPoint("TOPLEFT", 0, y)
	fs:SetWidth(BODY_WIDTH)
	fs:SetText(text)
	return fs
end

-- A labelled cycle button for one of Onboarding.PREFS (or any { key, label, values }).
local function cycleRow(parent, y, spec)
	local label = Widgets.Label(parent, "GameFontNormal", false, "muted")
	label:SetPoint("TOPLEFT", 0, y - 4)
	label:SetWidth(LABEL_WIDTH - 8)
	label:SetText(spec.label)
	local b = Widgets.Button(parent, "", BODY_WIDTH - LABEL_WIDTH, 22, "choice")
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
	function b.Update(self)
		for _, v in ipairs(self.spec.values) do
			if v[1] == wizard.values[self.spec.key] then self:SetText(v[2]) end
		end
	end
	wizard.cycles[#wizard.cycles + 1] = b
	return b
end

local function buildPages()
	-- 1 Welcome
	local p = pageFrame("welcome")
	paragraph(p, 0, "Dawnward Chronicles keeps a living chronicle of your character: what happens on their "
		.. "travels, the choices you make about it, and who they slowly become.")
	paragraph(p, -64, "It complements Total RP 3 rather than replacing it. Total RP 3 is your public profile; "
		.. "Dawnward is your character's private story.")
	paragraph(p, -116, "This setup takes about two minutes. Everything is optional, everything starts private, and "
		.. "you can change any of it later in Settings.", "muted")
	paragraph(p, -170, "Next: who your character is.", "accent")

	-- 2 Character
	p = pageFrame("character")
	paragraph(p, 0, "Confirm who your character is. All of it is optional and private until you choose "
		.. "otherwise. Existing details are kept; an empty box never erases anything.", "muted")
	wizard.inputs = {}
	for i, field in ipairs(Onboarding.FIELDS) do
		local y = -48 - (i - 1) * 34
		local label = Widgets.Label(p, "GameFontNormal", false, "muted")
		label:SetPoint("TOPLEFT", 0, y - 4)
		label:SetWidth(LABEL_WIDTH - 8)
		label:SetText(field.label)
		local input
		if field.multiline then
			-- Long text keeps its full size and line breaks.
			local area = Widgets.TextArea(p, field.max + 1, BODY_WIDTH - LABEL_WIDTH)
			area.frame:SetPoint("TOPLEFT", LABEL_WIDTH, y)
			area.frame:SetSize(BODY_WIDTH - LABEL_WIDTH, 64)
			input = area.edit
		else
			input = Widgets.EditLine(p, field.max + 1)
			input:SetPoint("TOPLEFT", LABEL_WIDTH, y)
			input:SetWidth(BODY_WIDTH - LABEL_WIDTH)
		end
		input.fieldKey = field.key
		wizard.inputs[#wizard.inputs + 1] = input
	end
	paragraph(p, -264, "The name is suggested from the game. More fields, family and history are in the "
		.. "Character tab.", "muted")

	-- 3 Story preferences
	p = pageFrame("story")
	paragraph(p, 0, "When something worth remembering happens, Dawnward may ask a quiet question about it, "
		.. "never in combat. Choose how much.", "muted")
	for i, pref in ipairs(Onboarding.PREFS) do
		cycleRow(p, -48 - (i - 1) * 36, pref)
	end
	paragraph(p, -200, "Questions are weighted: your homeland and the places, people and goals you care about "
		.. "matter most. Ordinary travel is logged quietly.", "muted")

	-- 4 Privacy
	p = pageFrame("privacy")
	paragraph(p, 0, "Everything you add starts private.")
	paragraph(p, -26, "Private: only you; included in your personal backups.\nSecret: only you; left out of backups "
		.. "unless you ask.\nPublic: may be shared through share exports and, only if you turn it on, Total RP 3.",
		"muted")
	paragraph(p, -100, "Total RP 3 sync is off, and setup will not turn it on. If you want it later, "
		.. "/dawnward trp3 help explains how; it shares only what you made public, backs up first and can be "
		.. "rolled back.")
	wizard.trp3 = paragraph(p, -176, "", "muted")
	paragraph(p, -220, "Dawnward never sends chat, emotes or whispers, and uses no internet or AI.", "muted")

	-- 5 Appearance
	p = pageFrame("appearance")
	paragraph(p, 0, "Choose this character's theme. It changes only how the journal looks, and never "
		.. "depends on class, race or faction.", "muted")
	wizard.themeTiles = {}
	local tileWidth = math.floor((BODY_WIDTH - 16) / 3)
	for i, theme in ipairs(Themes.LIST) do
		local tile = Widgets.Button(p, theme.name, tileWidth, 36, "choice")
		tile:SetPoint("TOPLEFT", ((i - 1) % 3) * (tileWidth + 8), -44 - math.floor((i - 1) / 3) * 42)
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
	wizard.themeNote = paragraph(p, -140, "", "muted")
	cycleRow(p, -180, { key = "minimap", label = "Minimap button",
		values = { { true, "Show the button on the minimap" }, { false, "Hide it (/dawnward still works)" } } })

	-- 6 Finish
	p = pageFrame("finish")
	paragraph(p, 0, "Review your choices. Finish saves them for this character and opens your journal.", "muted")
	wizard.summary = Widgets.Label(p, "GameFontHighlightSmall", true, "small")
	wizard.summary:SetPoint("TOPLEFT", 0, -30)
	wizard.summary:SetWidth(BODY_WIDTH)
	wizard.finishNote = paragraph(p, -250, "", "muted")
end

--- Frame -------------------------------------------------------------------------------

local function paintStep(step, theme)
	local color = step.state == "current" and theme.accent or step.state == "done" and theme.text or theme.muted
	Style.TextColor(step.label, color)
	Style.Color(step.bar, step.state == "future" and theme.edge or theme.accent)
end

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

	wizard.eyebrow = Widgets.Label(wizard, "GameFontNormalSmall", false, "eyebrow")
	wizard.eyebrow:SetPoint("TOPLEFT", L.pad, -18)
	wizard.title = Widgets.Label(wizard, "GameFontNormalLarge", false, "title")
	wizard.title:SetPoint("TOPLEFT", L.pad, -36)
	wizard.close = Widgets.IconButton(wizard, "X", "Close", "Close setup. It resumes where you left it the next "
		.. "time you open Dawnward, or from Settings > Run setup.")
	wizard.close:SetPoint("TOPRIGHT", -12, -12)
	wizard.close:SetScript("OnClick", function() SetupWizard.Close() end)

	-- Step indicator: a numbered label and a bar per stage.
	wizard.steps = {}
	local stepWidth = math.floor(BODY_WIDTH / #Onboarding.PAGES)
	for i, page in ipairs(Onboarding.PAGES) do
		local step = {}
		step.label = Widgets.Label(wizard, "GameFontHighlightSmall")
		step.label:SetPoint("TOPLEFT", L.pad + (i - 1) * stepWidth, -68)
		step.label:SetWidth(stepWidth - 4)
		step.label:SetText(i .. "  " .. page.title)
		step.bar = Widgets.Solid(wizard, "ARTWORK")
		step.bar:SetSize(stepWidth - 6, 2)
		step.bar:SetPoint("TOPLEFT", L.pad + (i - 1) * stepWidth, -86)
		step.state = "future"
		wizard.steps[i] = Style.Register(step, paintStep)
	end

	buildPages()

	wizard.footLine = Widgets.Divider(wizard)
	wizard.footLine:SetPoint("BOTTOMLEFT", L.pad, L.footer)
	wizard.footLine:SetPoint("BOTTOMRIGHT", -L.pad, L.footer)
	wizard.back = Widgets.Button(wizard, "< Back", 90, 22, "ghost")
	wizard.back:SetPoint("BOTTOMLEFT", L.pad, 16)
	wizard.back:SetScript("OnClick", function() SetupWizard.Go(wizard.page - 1) end)
	wizard.later = Widgets.Button(wizard, "Set up later", 120, 22, "ghost")
	wizard.later:SetPoint("LEFT", wizard.back, "RIGHT", 8, 0)
	wizard.later:SetScript("OnClick", function() SetupWizard.Later() end)
	Widgets.Tooltip(wizard.later, "Set up later", "Keep your answers and open the journal. Setup resumes the "
		.. "next time you log in, or from Settings > Run setup.")
	wizard.next = Widgets.Button(wizard, "Next >", 120, 22, "primary")
	wizard.next:SetPoint("BOTTOMRIGHT", -L.pad, 16)
	wizard.next:SetScript("OnClick", function()
		if wizard.page < #Onboarding.PAGES then
			SetupWizard.Go(wizard.page + 1)
		else
			SetupWizard.Finish()
		end
	end)
	wizard.discard = Widgets.Button(wizard, "Close preview", 120, 22)
	wizard.discard:SetPoint("RIGHT", wizard.next, "LEFT", -8, 0)
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

--- Redraws the current page from the values.
function SetupWizard.Refresh()
	if not wizard then return end
	local page = Onboarding.PAGES[wizard.page]
	wizard.title:SetText(page.title)
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
	if page.id == "privacy" then
		local status = ns.ctx.trp3Status and ns.ctx.trp3Status()
		wizard.trp3:SetText("Total RP 3 here: " .. (ns.Commands.Trp3Lines(status)[1] or "not detected"))
	end
	local last = wizard.page == #Onboarding.PAGES
	if last then
		wizard.summary:SetText(table.concat(Onboarding.Summary(wizard.values), "\n"))
		local blocked = wizard.simulation and "Simulation mode is on, so setup cannot be saved. Turn simulation "
			.. "off (Settings > Data) and run setup again."
			or wizard.readOnly and "Saved data is read-only this session, so setup cannot be saved. Nothing has "
			.. "been changed."
		wizard.finishNote:SetText(blocked or wizard.test and "Preview: Save choices applies these choices "
			.. "to this character without changing its setup status. Close preview discards them."
			or "Nothing is shared and nothing is sent to Total RP 3.")
	end
	wizard.back:SetEnabled(wizard.page > 1)
	wizard.later:SetShown(not wizard.test)
	wizard.discard:SetShown(wizard.test and last or false)
	wizard.next:SetText(not last and "Next >" or wizard.test and "Save choices" or "Finish")
	wizard.next:SetEnabled(not (last and wizard.readOnly))
end

--- Goes to page n (values kept; the draft is saved).
function SetupWizard.Go(n)
	collect()
	wizard.page = math.max(1, math.min(n, #Onboarding.PAGES))
	saveDraft()
	SetupWizard.Refresh()
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
	wizard:Show()
	if wizard.Raise then wizard:Raise() end
	SetupWizard.Refresh()
	return true
end

--- Finish (or, in test mode, Save choices).
function SetupWizard.Finish()
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
