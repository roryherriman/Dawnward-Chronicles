-- The story import window (#23, #16): bring a story the player already wrote
-- into Dawnward, then decide piece by piece what becomes canon. Opened from
-- the setup wizard's Character stage, the Character section header
-- ("Import story"), Settings > Data, and /dawnward biography.
--
-- Two pages, in the setup wizard's design language:
--   Your story   a large paste area (lossless up to the biography limit; a
--                longer text is refused with its size, never cut), a byte
--                and paragraph count, "Read from Total RP 3" (the player's
--                own About text, read-only through the TRP3 adapter; nothing
--                is ever written to Total RP 3), "Load saved story", the
--                split choice (by sentence or by paragraph) and Save and
--                review, which stores the text verbatim (Core/StoryImport.lua).
--   Review       one waiting piece at a time: the exact quote and where it
--                is in the story, an editable fact and its category (a
--                keyword guess, marked as suggested). Approve adds it to
--                canon (part of the profile, v0.10). Skip removes it for
--                good; Later moves on and keeps it waiting.
-- Nothing becomes canon without Approve, and every write goes through
-- Actions.WithCharacter (read-only data refused).
--
-- Look (v0.8): the setup wizard's header (eyebrow, Cinzel title, subtitle,
-- 36 px close), 36 px inputs and buttons, the split choice as a segmented
-- control showing both options, notes in plain panels.
-- v0.10: the two steps are shown as in the setup's rail, beside the
-- eyebrow: round numbered badges (gold for the step you are on, a check
-- for one behind you), each a click away; the stage title in the setup's
-- Cinzel 26.
local _, ns = ...
local Widgets, Style, Schema, MainWindow = ns.Widgets, ns.Style, ns.Schema, ns.MainWindow

local ImportWizard = {}
ns.ImportWizard = ImportWizard

ImportWizard.FRAME_NAME = "DawnwardChroniclesStoryImport"
ImportWizard.STRATA = "HIGH" -- like the setup wizard; raised over it when opened from there
ImportWizard.LAYOUT = { width = 760, height = 580, pad = 28, top = 22, bodyTop = 126, footer = 64, area = 240,
	control = 36, label = 120, quote = 130, note = 62 }
-- The paste box accepts a little more than can be saved, so an over-long
-- paste is shown and named rather than cut off silently by the box.
ImportWizard.OVERFLOW = 4096
ImportWizard.LIMIT = Schema.FOUNDATION.bioBytes

ImportWizard.SUBTITLES = {
	text = "Paste a story you already wrote. It is saved exactly as written; nothing becomes part of your "
		.. "character until you approve it.",
	review = "Approve what is true for your character, edit it first if you like, or skip it.",
}
ImportWizard.TEXT_NOTE = "Saved word for word, line breaks and all. Dawnward splits it into sentences (or "
	.. "paragraphs) by simple rules; it never rewrites or invents. With Total RP 3 connected, the whole story "
	.. "becomes your profile's About text."
ImportWizard.REVIEW_NOTE = "Approve adds this to your character's canon, as part of your profile. Skip "
	.. "means it is not suggested again. Later keeps it waiting. Your saved story is never changed."
ImportWizard.MODE_LABELS = { sentence = "Split: by sentence", paragraph = "Split: by paragraph" }
ImportWizard.MODES = { { id = "sentence", label = "By sentence" }, { id = "paragraph", label = "By paragraph" } }
-- The two steps, as the setup rail shows its stages.
ImportWizard.STEPS = { { id = "text", label = "Paste your story" }, { id = "review", label = "Review the pieces" } }
ImportWizard.STEP = { badge = 22, gap = 8, x = 214, width = 168 }

local L = ImportWizard.LAYOUT
local BODY = L.width - 2 * L.pad

local wizard

--- Pure helpers (tested) ------------------------------------------------------------

--- "1,234 / 16,384 bytes · 3 paragraphs", and whether it is too long.
function ImportWizard.CountText(text)
	text = text or ""
	local paragraphs = #ns.Sources.Paragraphs(text)
	local over = #text > ImportWizard.LIMIT
	local line = string.format("%d / %d bytes · %d paragraph%s", #text, ImportWizard.LIMIT, paragraphs,
		paragraphs == 1 and "" or "s")
	if over then
		line = line .. string.format(" · too long by %d bytes: shorten it or import it in parts", #text - ImportWizard.LIMIT)
	end
	return line, over
end


--- Reads the player's own About text from Total RP 3 (read-only). Returns
-- text, profileName; or nil plus a reason.
function ImportWizard.ReadTRP3()
	local ctx = ns.ctx
	local deps = ctx and ctx.trp3Deps and ctx.trp3Deps()
	local Adapter = ns.TRP3Adapter
	if not deps or not Adapter then
		return nil, "Total RP 3 is not available"
	end
	-- Only on an audited Total RP 3 version (Integrations/TRP3/Adapter.lua).
	local about, err = (Adapter.ReadAudited or Adapter.ReadSection)(deps.env, "about")
	if not about then
		return nil, err or "the About page could not be read"
	end
	-- Only to recognise (and leave out) the block Dawnward itself may have
	-- written there; the ledger is read, never changed.
	local probe = Adapter.Probe(deps.env)
	local profile = probe and probe.profile
	local profiles = deps.ledger and deps.ledger.profiles
	local record = profile and profile.id and type(profiles) == "table" and profiles[profile.id] or nil
	local text, terr = ns.StoryImport.AboutText(about, record and record.about)
	if not text then
		return nil, terr
	end
	return text, profile and profile.name
end

--- Building ---------------------------------------------------------------------------

local function label(parent, font, wrap, role, x, y, width)
	local fs = Widgets.Label(parent, font, wrap, role)
	fs:SetPoint("TOPLEFT", x, y)
	if width then fs:SetWidth(width) end
	return fs
end

local function page(id)
	local p = CreateFrame("Frame", nil, wizard)
	p:SetPoint("TOPLEFT", L.pad, -L.bodyTop)
	p:SetPoint("BOTTOMRIGHT", -L.pad, L.footer)
	p:Hide()
	wizard.pages[id] = p
	return p
end

local function setStatus(text)
	wizard.status:SetText(text or "")
	-- Two lines on the window; the whole message on hover.
	Widgets.Tooltip(wizard.statusHover, (text and text ~= "") and "Status" or nil, text)
	if MainWindow.SetStatus and text then MainWindow.SetStatus(text) end
end

-- A plain panel holding one note paragraph (meta 14, at most two lines).
local function notePanel(p, y, text)
	local note = Widgets.Panel(p, nil)
	note:SetPoint("TOPLEFT", 0, y)
	note:SetSize(BODY, L.note)
	local fs = label(note.inner, "meta", true, "muted", 0, 0, BODY - 2 * Widgets.PANEL_PAD)
	fs:SetMaxLines(2)
	fs:SetText(text)
	note.text = fs
	return note
end

local function buildText()
	local p = page("text")
	-- An edit box keeps at most maxBytes - 1 bytes.
	wizard.area = Widgets.TextArea(p, ImportWizard.LIMIT + ImportWizard.OVERFLOW + 1, BODY)
	wizard.area.frame:SetPoint("TOPLEFT", 0, 0)
	wizard.area.frame:SetSize(BODY, L.area)
	wizard.edit = wizard.area.edit
	wizard.edit:SetScript("OnTextChanged", function() ImportWizard.UpdateCount() end)
	wizard.count = label(p, "meta", false, "muted", 0, -L.area - 6, BODY)

	local y = -L.area - 34
	wizard.readTRP3 = Widgets.Button(p, "Read from Total RP 3", 180, L.control)
	wizard.readTRP3:SetPoint("TOPLEFT", 0, y)
	wizard.readTRP3:SetScript("OnClick", function() ImportWizard.FillFromTRP3() end)
	Widgets.Tooltip(wizard.readTRP3, "Read from Total RP 3", "Copies your own About text from your active Total RP 3 "
		.. "profile into the box (without anything Dawnward added there). Read-only: Total RP 3 is not changed.")
	wizard.loadSaved = Widgets.Button(p, "Load saved story", 160, L.control)
	wizard.loadSaved:SetPoint("LEFT", wizard.readTRP3, "RIGHT", 8, 0)
	wizard.loadSaved:SetScript("OnClick", function() ImportWizard.FillFromSaved() end)
	Widgets.Tooltip(wizard.loadSaved, "Load saved story", "Puts the story you saved last into the box, to add to it "
		.. "or revise it. Importing again suggests only the new parts.")
	-- How to split: both options visible, the one in use selected.
	local modeWidth = 2 * 116
	wizard.mode = Widgets.Segmented(p, ImportWizard.MODES, modeWidth, L.control, function(id)
		wizard.modeValue = id
		ImportWizard.Refresh()
	end)
	wizard.mode.buttons[1]:SetPoint("TOPLEFT", BODY - modeWidth, y)
	wizard.modeLabel = Widgets.Label(p, "GameFontNormal", false, "heading")
	wizard.modeLabel:SetPoint("RIGHT", wizard.mode.buttons[1], "LEFT", -10, 0)
	wizard.modeLabel:SetText("Split")
	for _, b in ipairs(wizard.mode.buttons) do
		Widgets.Tooltip(b, ImportWizard.MODE_LABELS[b.segmentId], "By sentence: one piece per sentence (best for "
			.. "long prose). By paragraph: one piece per paragraph (long ones are cut into parts at word boundaries).")
	end

	wizard.textNote = notePanel(p, y - L.control - 12, ImportWizard.TEXT_NOTE)
end

local function buildReview()
	local p = page("review")
	wizard.progress = label(p, "GameFontNormal", false, "heading", 0, 0, BODY)

	local quote = Widgets.Panel(p, "From your story")
	quote:SetPoint("TOPLEFT", 0, -26)
	quote:SetSize(BODY, L.quote)
	wizard.quote = quote
	local qW = BODY - 2 * Widgets.PANEL_PAD
	wizard.ref = label(quote.inner, "meta", false, "muted", 0, 0, qW)
	wizard.excerpt = label(quote.inner, "reading", true, "reading", 0, -20, qW)
	wizard.excerpt:SetMaxLines(3)
	-- A long piece is cut to three lines here; the whole of it is on hover.
	wizard.excerptHover = CreateFrame("Frame", nil, quote)
	wizard.excerptHover:SetAllPoints(quote)

	local y = -26 - L.quote - 14
	label(p, "GameFontNormal", false, "heading", 0, y - 10, L.label - 10):SetText("As a fact")
	wizard.statement = Widgets.EditLine(p, Schema.FOUNDATION.statement + 64, L.control)
	wizard.statement:SetPoint("TOPLEFT", L.label, y)
	wizard.statement:SetWidth(BODY - L.label)
	wizard.statement:SetScript("OnTextChanged", function(_, userInput)
		if userInput then ImportWizard.RememberEdits() end
	end)
	-- After the script above: the error line hooks it.
	wizard.statementError = Widgets.FieldError(wizard.statement, BODY - L.label)
	wizard.statement:SetScript("OnEnterPressed", function() ImportWizard.Approve() end)

	y = y - L.control - 24
	label(p, "GameFontNormal", false, "heading", 0, y - 10, L.label - 10):SetText("Category")
	wizard.category = Widgets.Button(p, "", 300, L.control, "choice")
	wizard.category:SetPoint("TOPLEFT", L.label, y)
	wizard.category:SetScript("OnClick", function() ImportWizard.CycleCategory() end)
	Widgets.Tooltip(wizard.category, "Category", "Click for the next category. A suggested category is only a "
		.. "guess from a few words; change it freely.")

	y = y - L.control - 14
	wizard.approve = Widgets.Button(p, "Approve", 130, L.control, "primary")
	wizard.approve:SetPoint("TOPLEFT", L.label, y)
	wizard.approve:SetScript("OnClick", function() ImportWizard.Approve() end)
	Widgets.Tooltip(wizard.approve, "Approve", "Add this to your character's canon, as written in the box.")
	wizard.skip = Widgets.Button(p, "Skip", 96, L.control, "danger")
	wizard.skip:SetPoint("LEFT", wizard.approve, "RIGHT", 8, 0)
	wizard.skip:SetScript("OnClick", function() ImportWizard.Skip() end)
	Widgets.Tooltip(wizard.skip, "Skip", "Not part of your canon. It will not be suggested again (your saved story "
		.. "keeps it).")
	wizard.later = Widgets.Button(p, "Later", 96, L.control, "ghost")
	wizard.later:SetPoint("LEFT", wizard.skip, "RIGHT", 8, 0)
	wizard.later:SetScript("OnClick", function() ImportWizard.Move(1) end)
	Widgets.Tooltip(wizard.later, "Later", "Keep it waiting and show the next piece.")
	wizard.previous = Widgets.Button(p, "Previous", 96, L.control, "ghost")
	wizard.previous:SetPoint("LEFT", wizard.later, "RIGHT", 8, 0)
	wizard.previous:SetScript("OnClick", function() ImportWizard.Move(-1) end)

	wizard.reviewNote = notePanel(p, y - L.control - 12, ImportWizard.REVIEW_NOTE)
	wizard.empty = label(p, "reading", true, "reading", 0, -30, BODY)
end

-- A step's look (the setup rail's badges): current gold, done with the
-- game's check mark, upcoming edged with a muted number.
local function paintStep(step, theme)
	local tones = Style.Tones(theme)
	local current, done = step.state == "current", step.state == "done"
	Style.Color(step.ring, current and theme.accent or done and theme.border or tones.edgeStrong)
	Style.Color(step.fill, current and theme.accent or done and Style.Mix(theme.surface, theme.accent, 0.12)
		or theme.panel)
	if not step.ring.round then step.edges:Paint(current and theme.accent or tones.edgeStrong, 1) end
	Style.TextColor(step.num, current and theme.accentText or theme.muted)
	step.num:SetShown(not done)
	step.check:SetShown(done)
	local gold = tones.accentBright
	step.check:SetVertexColor(gold[1], gold[2], gold[3])
	Style.TextColor(step.label, current and tones.heading or done and tones.ghostText or theme.muted)
end

local function buildSteps()
	local S = ImportWizard.STEP
	wizard.steps = {}
	for i, def in ipairs(ImportWizard.STEPS) do
		local step = CreateFrame("Button", nil, wizard)
		step:SetSize(S.width, S.badge)
		step:SetPoint("TOPLEFT", L.pad + S.x + (i - 1) * (S.width + S.gap), -L.top + 3)
		step.id = def.id
		step.ring = Style.Disc(step, "BACKGROUND", 0, S.badge)
		step.ring:SetPoint("LEFT", 0, 0)
		step.fill = Style.Disc(step, "BACKGROUND", 1, step.ring.round and S.badge - 2 or S.badge)
		step.fill:SetPoint("CENTER", step.ring, "CENTER", 0, 0)
		step.edges = Style.Edge(step, "BORDER")
		step.edges:SetShown(not step.ring.round)
		step.num = step:CreateFontString(nil, "OVERLAY", Style.FontFor("badge"))
		step.num:SetPoint("CENTER", step.ring, "CENTER", 0, 0)
		step.num:SetText(tostring(i))
		step.check = step:CreateTexture(nil, "OVERLAY")
		step.check:SetTexture(ns.SetupWizard and ns.SetupWizard.CHECK_TEXTURE or "Interface\\Buttons\\UI-CheckBox-Check")
		step.check:SetSize(18, 18)
		step.check:SetPoint("CENTER", step.ring, "CENTER", 0, 0)
		step.label = Widgets.Label(step, "meta", false, nil)
		step.label:SetPoint("LEFT", S.badge + 8, 0)
		step.label:SetWidth(S.width - S.badge - 8)
		step.label:SetText(def.label)
		step.state = "future"
		step:SetScript("OnClick", function(self)
			if self.id ~= wizard.page then
				ImportWizard.Show(self.id)
			end
		end)
		Widgets.Tooltip(step, def.label, i == 1 and "Paste or read your story, then Save and review."
			or "Approve, edit or skip each piece Dawnward found in your story.")
		wizard.steps[i] = Style.Register(step, paintStep)
	end
end

local function build()
	wizard = CreateFrame("Frame", ImportWizard.FRAME_NAME, UIParent)
	wizard:SetSize(L.width, L.height)
	wizard:SetPoint("CENTER")
	wizard:SetFrameStrata(ImportWizard.STRATA)
	wizard:SetToplevel(true)
	wizard:SetClampedToScreen(true)
	wizard:EnableMouse(true)
	wizard:SetMovable(true)
	wizard:RegisterForDrag("LeftButton")
	wizard:SetScript("OnDragStart", wizard.StartMoving)
	wizard:SetScript("OnDragStop", wizard.StopMovingOrSizing)
	Style.Chrome(wizard, "background")
	wizard.pages, wizard.edits, wizard.modeValue, wizard.index = {}, {}, ns.StoryImport.DEFAULT_MODE, 1

	wizard.eyebrow = label(wizard, "GameFontNormalSmall", false, "eyebrow", L.pad, -L.top)
	wizard.eyebrow:SetText("STORY IMPORT")
	wizard.title = label(wizard, "stage", false, "title", L.pad, -L.top - 22)
	wizard.subtitle = label(wizard, "GameFontHighlight", true, "muted", L.pad, -L.top - 60, BODY - 48)
	Widgets.SetTextRole(wizard.subtitle, "navText")
	wizard.subtitle:SetMaxLines(2)
	wizard.close = Widgets.IconButton(wizard, "X", "Close", "Close. What you saved is kept; pieces you have not "
		.. "reviewed keep waiting.")
	wizard.close:SetSize(Style.CONTROL.icon, Style.CONTROL.icon)
	wizard.close:SetPoint("TOPRIGHT", -L.pad, -L.top)
	wizard.close:SetScript("OnClick", function() ImportWizard.Close() end)

	buildSteps()
	buildText()
	buildReview()

	wizard.status = Widgets.Label(wizard, "meta", true, "muted")
	wizard.status:SetPoint("BOTTOMLEFT", L.pad, 18)
	wizard.status:SetWidth(BODY - 380)
	wizard.status:SetMaxLines(2)
	wizard.statusHover = CreateFrame("Frame", nil, wizard)
	wizard.statusHover:SetAllPoints(wizard.status)
	wizard.primary = Widgets.Button(wizard, "", 180, L.control, "primary")
	wizard.primary:SetPoint("BOTTOMRIGHT", -L.pad, 16)
	wizard.primary:SetScript("OnClick", function() ImportWizard.Primary() end)
	wizard.secondary = Widgets.Button(wizard, "", 180, L.control)
	wizard.secondary:SetPoint("RIGHT", wizard.primary, "LEFT", -10, 0)
	wizard.secondary:SetScript("OnClick", function() ImportWizard.Secondary() end)

	wizard:SetScript("OnHide", function()
		if MainWindow.Refresh then MainWindow.Refresh() end
	end)
	if UISpecialFrames then
		tinsert(UISpecialFrames, ImportWizard.FRAME_NAME) -- Escape closes; nothing is lost
	end
	wizard:Hide()
end

--- State --------------------------------------------------------------------------------

local function character()
	return ns.Actions.Character(ns.ctx)
end

local function waiting()
	local char = character()
	return char and ns.StoryImport.Waiting(char) or {}
end

local function current()
	local items = waiting()
	if #items == 0 then return nil, items end
	wizard.index = math.max(1, math.min(wizard.index, #items))
	return items[wizard.index], items
end

function ImportWizard.UpdateCount()
	if not wizard then return end
	local text = wizard.edit:GetText() or ""
	local line, over = ImportWizard.CountText(text)
	if #text >= ImportWizard.LIMIT + ImportWizard.OVERFLOW then
		line = line .. " · the box is full: the end of what you pasted may be missing"
		over = true
	end
	wizard.count:SetText(line)
	wizard.count.textRole = over and "danger" or "muted"
	Style.Repaint(wizard.count)
end

-- What the player has changed on the current piece (kept while they move
-- between pieces this session; nothing is saved until Approve).
function ImportWizard.RememberEdits()
	local item = current()
	if not item then return end
	local e = wizard.edits[item.key] or {}
	e.statement = wizard.statement:GetText()
	wizard.edits[item.key] = e
end

local function categoryOf(item)
	local e = wizard.edits[item.key]
	return e and e.category or item.category
end

function ImportWizard.CycleCategory()
	local item = current()
	if not item then return end
	local list, now = Schema.FACT_CATEGORIES, categoryOf(item)
	local nextId = list[1].id
	for i, c in ipairs(list) do
		if c.id == now then nextId = list[i % #list + 1].id end
	end
	ImportWizard.RememberEdits()
	wizard.edits[item.key].category = nextId
	ImportWizard.Refresh()
end

--- Redraws the current page.
function ImportWizard.Refresh()
	if not wizard then return end
	local onText = wizard.page == "text"
	for id, p in pairs(wizard.pages) do p:SetShown(id == wizard.page) end
	wizard.title:SetText(onText and "Your story" or "Review")
	wizard.subtitle:SetText(ImportWizard.SUBTITLES[wizard.page])
	wizard.eyebrow:SetText("STORY IMPORT · STEP " .. (onText and 1 or 2) .. " OF 2")
	for i, step in ipairs(wizard.steps) do
		step.state = (onText and i == 1 or not onText and i == 2) and "current" or (not onText and i == 1) and "done"
			or "future"
		Style.Repaint(step)
	end
	local char = character()
	local counts = ns.StoryImport.Counts(char)
	if onText then
		wizard.mode:Select(wizard.modeValue)
		local saved = char ~= nil and ns.Sources.Current(char) ~= nil
		wizard.loadSaved:SetEnabled(saved)
		ImportWizard.UpdateCount()
		wizard.primary:SetText("Save and review")
		wizard.secondary:SetText(counts.waiting > 0 and ("Review waiting (" .. counts.waiting .. ")") or "Close")
		return
	end
	local item, items = current()
	wizard.primary:SetText("Done")
	wizard.secondary:SetText("Back to text")
	local controls = { wizard.quote, wizard.statement, wizard.category, wizard.approve, wizard.skip,
		wizard.later, wizard.previous }
	for _, c in ipairs(controls) do c:SetShown(item ~= nil) end
	wizard.empty:SetShown(item == nil)
	wizard.progress:SetText(item and string.format("Piece %d of %d waiting  ·  %d approved  ·  %d skipped",
		wizard.index, #items, counts.approved, counts.skipped)
		or string.format("Nothing is waiting  ·  %d approved  ·  %d skipped", counts.approved, counts.skipped))
	if not item then
		wizard.ref:SetText("")
		wizard.excerpt:SetText("")
		wizard.empty:SetText("Every piece has been reviewed. Approved pieces are part of your character's profile "
			.. "now. Import again at any time: only new parts are suggested.")
		return
	end
	local e = wizard.edits[item.key] or {}
	wizard.ref:SetText(ns.StoryImport.RefText(item.ref) .. (item.origin == "trp3-biography" and "  ·  from Total RP 3"
		or ""))
	wizard.excerpt:SetText(item.excerpt or item.statement)
	Widgets.Tooltip(wizard.excerptHover, "From your story", item.excerpt or item.statement)
	if wizard.shownKey ~= item.key then
		wizard.statement:SetText(e.statement or item.statement)
		Widgets.SetFieldError(wizard.statement, nil)
		wizard.shownKey = item.key
	end
	local category = categoryOf(item)
	wizard.category:SetText("Category: " .. ns.Facts.DisplayCategory(category).label
		.. (category == item.category and not e.category and " (suggested)" or "") .. "  ›")
	wizard.previous:SetEnabled(wizard.index > 1)
	wizard.later:SetEnabled(#items > 1)
end

local function show(pageId)
	wizard.page = pageId
	wizard.shownKey = nil
	ImportWizard.Refresh()
end

--- Shows a step ("text" or "review"); what was typed is kept.
function ImportWizard.Show(pageId)
	if wizard and (pageId == "text" or pageId == "review") then
		show(pageId)
	end
end

--- Opens the window. opts.from: "setup", "character", "settings" or "chat".
-- Opens on Review when pieces are waiting, otherwise on Your story.
function ImportWizard.Open(opts)
	opts = opts or {}
	if not ns.ctx then return false end
	if not wizard then build() end
	wizard.from = opts.from
	wizard.fitScale = Style.FitScale(L.height, UIParent.GetHeight and UIParent:GetHeight(), nil,
		L.width, UIParent.GetWidth and UIParent:GetWidth())
	wizard:SetScale(wizard.fitScale)
	wizard:Show()
	if wizard.Raise then wizard:Raise() end
	local readOnly = ns.ctx.store:ReadOnlyReason()
	setStatus(readOnly and ("Saved data is read-only (" .. readOnly .. "): nothing can be saved this session.")
		or ns.ctx.store:IsSimulation() and "Simulation mode is on: this goes to your test data, not your real journal."
		or "")
	show(#waiting() > 0 and opts.page ~= "text" and "review" or "text")
	return true
end

function ImportWizard.Close()
	if wizard then wizard:Hide() end
end

function ImportWizard.IsShown()
	return wizard ~= nil and wizard:IsShown()
end

--- For tests and diagnostics only.
function ImportWizard.Frame()
	return wizard
end

--- Text page actions ------------------------------------------------------------------

function ImportWizard.FillFromTRP3()
	local text, nameOrErr = ImportWizard.ReadTRP3()
	if not text then
		setStatus("Could not read Total RP 3: " .. tostring(nameOrErr) .. ". You can paste the text instead.")
		return false
	end
	wizard.edit:SetText(text)
	wizard.loaded = { text = text, kind = "trp3", profile = nameOrErr }
	ImportWizard.UpdateCount()
	setStatus("Read your Total RP 3 About text" .. (nameOrErr and (" (profile " .. nameOrErr .. ")") or "")
		.. ". Total RP 3 was not changed. Save and review to keep it.")
	return true
end

function ImportWizard.FillFromSaved()
	local char = character()
	local source = char and ns.Sources.Current(char)
	if not source then
		setStatus("No story is saved yet.")
		return false
	end
	wizard.edit:SetText(source.text)
	wizard.loaded = { text = source.text, kind = source.kind, profile = source.meta and source.meta.profile }
	ImportWizard.UpdateCount()
	setStatus("Loaded your saved story (version " .. source.id .. "). Edit it and save to add the new parts.")
	return true
end

--- Saves the text verbatim and proposes its pieces, then shows Review.
function ImportWizard.Save()
	local text = wizard.edit:GetText() or ""
	ImportWizard.UpdateCount()
	local _, over = ImportWizard.CountText(text)
	if over then
		setStatus(string.format("Not saved: the story is %d bytes and the limit is %d. Nothing was cut or stored; "
			.. "shorten it, or import it in two parts.", #text, ImportWizard.LIMIT))
		return false
	end
	-- Unchanged text read from Total RP 3 is recorded as such.
	local loaded = wizard.loaded
	local fromTRP3 = loaded and loaded.kind == "trp3" and loaded.text == text
	local result, message = ns.StoryImport.Import(ns.ctx, fromTRP3 and "trp3" or "paste", text,
		fromTRP3 and { profile = loaded.profile, note = "Total RP 3 About" } or nil, wizard.modeValue)
	setStatus(message)
	if not result then
		return false
	end
	wizard.index = 1
	show("review")
	return true
end

function ImportWizard.Primary()
	if wizard.page == "text" then
		return ImportWizard.Save()
	end
	ImportWizard.Close()
	return true
end

function ImportWizard.Secondary()
	if wizard.page == "text" then
		if #waiting() > 0 then
			show("review")
		else
			ImportWizard.Close()
		end
	else
		show("text")
	end
end

--- Review actions ---------------------------------------------------------------------

function ImportWizard.Move(step)
	local _, items = current()
	if #items == 0 then return end
	ImportWizard.RememberEdits()
	wizard.index = ((wizard.index - 1 + step) % #items) + 1
	wizard.shownKey = nil
	ImportWizard.Refresh()
end

local function approveNow(item, edits)
	local fact, message = ns.StoryImport.ApproveAction(ns.ctx, item.key, edits)
	if not fact then
		Widgets.SetFieldError(wizard.statement, message)
		setStatus(message)
		return false
	end
	wizard.edits[item.key] = nil
	wizard.shownKey = nil
	setStatus(message)
	ImportWizard.Refresh()
	return true
end

--- Approve: into canon with the player's edits.
function ImportWizard.Approve()
	local item = current()
	if not item then return false end
	ImportWizard.RememberEdits()
	local e = wizard.edits[item.key]
	return approveNow(item, { statement = e.statement, category = categoryOf(item) })
end

function ImportWizard.Skip()
	local item = current()
	if not item then return false end
	local ok, message = ns.StoryImport.SkipAction(ns.ctx, item.key)
	setStatus(message)
	if ok then
		wizard.edits[item.key] = nil
		wizard.shownKey = nil
		ImportWizard.Refresh()
	end
	return ok ~= nil
end
