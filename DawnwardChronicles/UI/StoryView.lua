-- Story section ("Story Director", docs/design/mockups/story-director.png):
-- the living chronicle in the journal window.
--
--   header       eyebrow "Story · moment 1 of 2" and < > between moments
--   moment card  where, what and when (chips from the event record), the
--                question, "Why now" (the Director's own reasons) and the
--                memories this moment touches, the answers as a two-column
--                choice grid with each answer's personality hint, "in your
--                own words", and Save answer / Later / Not now / Dismiss
--   also waiting the other waiting moments, selectable; Reflect
--   growth       personality changes waiting for approval (with why), and
--                recently applied ones, which can be reversed
--
-- Every button calls the same Actions as /dawnward story and develop.
-- Nothing here changes the character without a click: answers only propose
-- changes, which wait for Approve unless the player chose automatic
-- approval in Settings (unchanged).
local _, ns = ...
local Widgets, MainWindow, Actions, Reactions, Evolution, Journal, Style =
	ns.Widgets, ns.MainWindow, ns.Actions, ns.Reactions, ns.Evolution, ns.Journal, ns.Style

local StoryView = {}
ns.StoryView = StoryView

StoryView.HEADING = "Your story is still being written"
StoryView.BODY = "When something worth remembering happens on your adventures, a quiet question "
	.. "will wait for you here: how did it affect your character?\n\n"
	.. "Your answers shape their personality only when you approve it, and become private journal drafts "
	.. "you can edit, approve and choose to share. Nothing changes your character without you."
-- Template answers (4), a class flavour answer, two from the character's
-- own goals and arcs, and the neutral one: at most 8, four rows of two.
StoryView.MAX_OPTIONS = 8
StoryView.MAX_CHANGES = 2
StoryView.MAX_WAITING = 2
StoryView.MAX_APPLIED = 2
StoryView.MAX_MEMORIES = 2

-- Layout (UI units), from docs/design/mockups/source/Story.dc.html.
local L = {
	contentW = MainWindow.ContentWidth(), contentH = MainWindow.ContentHeight(),
	sideW = 236, gap = 20, pad = 22,
	chipsTop = -20, questionTop = -50, questionH = 50,
	whyTop = -104, whyH = 58,
	optionsTop = -172, optionH = 58, optionGap = 8,
	customLabelTop = -438, customTop = -456, customH = 58,
	buttonsTop = -528, buttonH = 30,
	headerIcon = 36, headerUp = 74, -- prev/next sit in the window header, beside Close
	rowH = 52, rowGap = 6, changeH = 96, appliedH = 28,
}
L.cardW = L.contentW - L.sideW - L.gap
L.inner = L.cardW - 2 * L.pad
L.colW = (L.inner - L.optionGap) / 2
L.sideInner = L.sideW - 2 * Widgets.PANEL_PAD
StoryView.LAYOUT = L

--- Pure helpers --------------------------------------------------------------------

--- One-line summary of what is waiting. Pure: used by tests.
function StoryView.Summary(char, now)
	if not char then
		return "Nothing recorded yet."
	end
	local waiting = #Reactions.List(char, now)
	local pending = #Evolution.Pending(char)
	local drafts = #Journal.Search(char, { kind = "story", status = "draft" })
	local parts = {
		string.format("%d waiting %s", waiting, waiting == 1 and "moment" or "moments"),
		string.format("%d %s to approve", pending, pending == 1 and "change" or "changes"),
		string.format("%d journal %s", drafts, drafts == 1 and "draft" or "drafts"),
	}
	local next
	if waiting > 0 then
		next = "answer a waiting moment below"
	elseif pending > 0 then
		next = "review the personality changes beside this"
	elseif drafts > 0 then
		next = "review your drafts in the Journal"
	else
		next = "keep adventuring"
	end
	return table.concat(parts, "  -  ") .. "\nNext: " .. next .. "."
end

--- The small line under the question: folded events, a recalled memory and
-- why the moment appeared (verified data only). Pure: used by tests.
function StoryView.ContextText(presentation)
	local parts = {}
	if presentation.context then parts[#parts + 1] = presentation.context end
	if presentation.recall then parts[#parts + 1] = presentation.recall end
	if presentation.why and #presentation.why > 0 then
		parts[#parts + 1] = "Why now: " .. table.concat(presentation.why, "; ")
	end
	if presentation.echo then parts[#parts + 1] = "Last time: " .. presentation.echo end
	return table.concat(parts, "  -  ")
end

--- "just now", "12 min ago", "3 h ago", "2 days ago" from two real dates.
-- An unknown date gives nil. Pure.
function StoryView.Ago(at, now)
	if type(at) ~= "number" or at <= 0 or type(now) ~= "number" then
		return nil
	end
	local s = math.max(0, now - at)
	if s < 60 then return "just now" end
	local m = math.floor(s / 60)
	if m < 60 then return m .. " min ago" end
	local h = math.floor(m / 60)
	if h < 24 then return h .. " h ago" end
	local d = math.floor(h / 24)
	return d .. (d == 1 and " day ago" or " days ago")
end

--- A short hint under an answer: the personality direction it would propose
-- (only a proposal) and what it is about, from the library. Pure.
function StoryView.OptionHint(option)
	if option.goalId then return "Ties it to your goal" end
	if option.arcId then return "Adds to your story arc" end
	local axes = {}
	for axis in pairs(option.effects or {}) do axes[#axes + 1] = axis end
	table.sort(axes)
	local parts = {}
	for _, axis in ipairs(axes) do
		parts[#parts + 1] = "More " .. Evolution.AxisLabel(axis, option.effects[axis])
	end
	local hint = table.concat(parts, ", ")
	if option.theme then
		local theme = option.theme:sub(1, 1):upper() .. option.theme:sub(2)
		hint = hint ~= "" and (hint .. " · " .. theme) or theme
	end
	return hint ~= "" and hint or "No personality change"
end

--- Established memories this moment touches: the Director's own ranking
-- (same place or shared theme, the threshold Director.Recall uses), at
-- most MAX_MEMORIES titles. Pure.
function StoryView.RelevantMemories(char, presentation)
	local context = ns.Director.Context(char, presentation.record, presentation.template)
	local out = {}
	for _, ranked in ipairs(context.memories) do
		if ranked.score < 3 or #out >= StoryView.MAX_MEMORIES then break end
		local title = ranked.item.title or ranked.item.text
		if title then out[#out + 1] = (title:gsub("[{}]", "")) end
	end
	return out
end

local TIE_LABELS = { homeland = "Homeland", meaningful = "Marked place", memory = "In your memories" }

--- Chips for the moment: { text, tone }: the place (and how it is tied to
-- the character), what happened, and level and when. From the event record
-- only; nothing is shown that the record does not hold. Pure.
function StoryView.Chips(char, presentation, now)
	local record = presentation.record
	local chips = {}
	if not record then
		return chips
	end
	local m = record.meta or {}
	local place
	if record.category == "place" and m.placeName and record.zone then
		place = m.placeName .. ", " .. record.zone
	elseif record.zone then
		place = ns.Places.Label({ zone = record.zone, subzone = record.subzone })
	end
	if place then chips[#chips + 1] = { text = place, tone = "accent" } end
	local entry = record.zone and (ns.Places.Entry(char, record.zone, record.subzone)
		or ns.Places.Entry(char, record.zone))
	local tie = entry and ns.Places.Tie(char, entry)
	if tie then chips[#chips + 1] = { text = TIE_LABELS[tie], tone = "accent" } end
	chips[#chips + 1] = { text = ns.GameEvents.RecordLabel(record), tone = "muted" }
	local when = {}
	if record.level then when[#when + 1] = "Level " .. record.level end
	when[#when + 1] = StoryView.Ago(record.at, now)
	if #when > 0 then chips[#chips + 1] = { text = table.concat(when, " · "), tone = "muted" } end
	return chips
end

--- The "Why now" box: { { label, text } } lines. Pure.
function StoryView.WhyLines(presentation, memories)
	local lines = {}
	local why = {}
	for _, r in ipairs(presentation.why or {}) do why[#why + 1] = r end
	local text = #why > 0 and table.concat(why, "; ") or nil
	if presentation.context then
		text = text and (text .. " " .. presentation.context) or presentation.context
	end
	if text then
		text = text .. "."
		-- The player's own earlier answer about the same situation (Director.Echo).
		if presentation.echo then text = text .. " Last time: " .. presentation.echo .. "." end
		lines[#lines + 1] = { label = "Why now:", text = text }
	end
	if memories and #memories > 0 then
		local quoted = {}
		for i, title in ipairs(memories) do quoted[i] = "\226\128\156" .. title .. "\226\128\157" end
		lines[#lines + 1] = { label = (presentation.name or "They") .. " remembers:", text = table.concat(quoted, "; ") }
	end
	return lines
end

--- Why a waiting change was proposed, from its decision record. Pure.
function StoryView.ChangeReason(change)
	local reason = change.reason
	if not reason or reason == "" then
		return "Proposed by Dawnward."
	end
	reason = reason:gsub("%.$", "")
	return (change.decisionId and "From your answer: " or "") .. reason .. "."
end

--- Applied Dawnward changes that can still be reversed, newest first.
function StoryView.Reversible(char, limit)
	local out = {}
	for _, change in ipairs(Evolution.History(char, 50)) do
		if change.status == "applied" and not change.manual then
			out[#out + 1] = change
			if #out >= (limit or StoryView.MAX_APPLIED) then break end
		end
	end
	return out
end

--- Building blocks --------------------------------------------------------------------

local function hex(color)
	return string.format("%02x%02x%02x", math.floor((color[1] or 1) * 255), math.floor((color[2] or 1) * 255),
		math.floor((color[3] or 1) * 255))
end

-- Observed text (quest titles) never carries colour codes into the line.
local function safe(text)
	return (tostring(text or ""):gsub("|", "||"))
end

local function hook(frame, script, fn)
	if frame.HookScript and frame:GetScript(script) then
		frame:HookScript(script, fn)
	else
		frame:SetScript(script, fn)
	end
end

local function at(region, parent, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

-- A flat inset box on the window ground (the "Why now" well).
local function well(parent)
	local box = CreateFrame("Frame", nil, parent)
	box.bg = Style.Solid(box, "BACKGROUND")
	box.bg:SetAllPoints(box)
	box.edges = Style.Edge(box, "BORDER")
	Style.Register(box, function(b, theme)
		Style.Color(b.bg, theme.background)
		b.edges:Paint(theme.edge, 1)
	end)
	return box
end

-- The question reads larger than body text (22px Alegreya in the mockup;
-- 19 here). FontInstance:SetFont is the call Style.InitFonts already makes
-- on its font objects (also FloatingChatFrame.lua in the 1.15.9 UI source).
-- Only when the bundled fonts loaded; otherwise the game font stays.
local function largeReading(fs)
	if Style.Font("GameFontHighlight") == "GameFontHighlight" or not fs.SetFont then
		return
	end
	local ok = pcall(fs.SetFont, fs, Style.FONT_DIR .. Style.FONT_FILES.body, 19, "")
	if ok and fs.SetShadowOffset then
		fs:SetShadowOffset(1, -1)
	end
end

-- One answer card: a number key, the answer (two lines) and its hint.
local function choiceCard(parent, index, onClick)
	local b = Widgets.Button(parent, "", L.colW, L.optionH, "choice")
	b.key = CreateFrame("Frame", nil, b)
	b.key:SetSize(24, 24)
	b.key:SetPoint("LEFT", 12, 0)
	b.key.edges = Style.Edge(b.key, "BORDER")
	b.key.label = Widgets.Label(b.key, "GameFontHighlightSmall", false, "muted")
	b.key.label:SetPoint("CENTER", 0, 0)
	b.key.label:SetJustifyH("CENTER")
	b.key.label:SetText(tostring(index))
	Style.Register(b.key, function(k, theme) k.edges:Paint(theme.edge, 1) end)
	local textW = L.colW - 12 - 24 - 10 - 10
	b.text = Widgets.Label(b, "GameFontHighlight", true, "body")
	b.text:SetPoint("TOPLEFT", 46, -7)
	b.text:SetWidth(textW)
	b.text:SetHeight(32)
	b.hint = Widgets.Label(b, "GameFontHighlightSmall", false, "muted")
	b.hint:SetPoint("BOTTOMLEFT", 46, 6)
	b.hint:SetWidth(textW)
	b:SetScript("OnClick", onClick)
	-- Like any button, its text is the answer it gives.
	function b.SetText(self, t) self.text:SetText(t) end
	function b.GetText(self) return self.text:GetText() end
	return b
end

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), index = 1, optionButtons = {}, changeRows = {},
		waitingRows = {}, appliedRows = {} }
	local f = section.frame

	local function act(fn, ...)
		local result, message = fn(ns.ctx, ...)
		MainWindow.SetStatus(message)
		MainWindow.Refresh()
		return result, message
	end

	-- Header: previous / next moment, in the window header beside Close.
	section.next = Widgets.IconButton(f, ">", "Next moment", "Show the next waiting moment.")
	section.next:SetSize(L.headerIcon, L.headerIcon)
	section.next:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(L.headerIcon + 6), L.headerUp)
	section.prev = Widgets.IconButton(f, "<", "Previous moment", "Show the previous waiting moment.")
	section.prev:SetSize(L.headerIcon, L.headerIcon)
	section.prev:SetPoint("RIGHT", section.next, "LEFT", -6, 0)
	section.prev:SetScript("OnClick", function() section.index = section.index - 1; MainWindow.Refresh() end)
	section.next:SetScript("OnClick", function() section.index = section.index + 1; MainWindow.Refresh() end)
	-- The pager's position ("1 of 2 · kept for later"), left of the arrows.
	section.position = Widgets.Label(f, "GameFontHighlightSmall", false, "muted")
	section.position:SetPoint("RIGHT", section.prev, "LEFT", -10, 0)
	section.position:SetJustifyH("RIGHT")

	--- The moment card ------------------------------------------------------------
	local card = Widgets.Callout(f)
	section.card = card
	card:SetSize(L.cardW, L.contentH)
	at(card, f, 0, 0)

	section.chips = {}
	for i = 1, 4 do
		section.chips[i] = Widgets.Chip(card, "", "accent")
		section.chips[i]:Hide()
	end

	section.question = Widgets.Label(card, "GameFontHighlight", true, "body")
	largeReading(section.question)
	at(section.question, card, L.pad, L.questionTop)
	section.question:SetWidth(L.inner)
	section.question:SetHeight(L.questionH)

	section.why = well(card)
	section.why:SetSize(L.inner, L.whyH)
	at(section.why, card, L.pad, L.whyTop)
	section.context = Widgets.Label(section.why, "GameFontHighlightSmall", true, nil)
	at(section.context, section.why, 12, -9)
	section.context:SetWidth(L.inner - 24)
	section.context:SetHeight(L.whyH - 14)
	section.context.lines = {}
	-- Labels in the accent colour, reasons in muted; repainted with the theme.
	Style.Register(section.context, function(fs, theme)
		local out = {}
		for _, line in ipairs(fs.lines) do
			out[#out + 1] = "|cff" .. hex(theme.accent) .. safe(line.label) .. "|r " .. safe(line.text)
		end
		fs:SetText(table.concat(out, "\n"))
		Style.TextColor(fs, theme.muted)
	end)

	for i = 1, StoryView.MAX_OPTIONS do
		local button = choiceCard(card, i, function(self)
			act(Actions.Decide, section.reactionId, { optionId = self.optionId })
		end)
		at(button, card, L.pad + ((i - 1) % 2) * (L.colW + L.optionGap),
			L.optionsTop - math.floor((i - 1) / 2) * (L.optionH + L.optionGap))
		section.optionButtons[i] = button
	end

	section.customLabel = Widgets.Label(card, "GameFontNormal", false, "heading")
	at(section.customLabel, card, L.pad, L.customLabelTop)
	section.customLabel:SetText("Or in your own words")
	section.customArea = Widgets.TextArea(card, 600, L.inner)
	section.customArea.frame:SetSize(L.inner, L.customH)
	at(section.customArea.frame, card, L.pad, L.customTop)
	section.custom = section.customArea.edit
	section.customError = Widgets.FieldError(section.custom, L.inner - 180)
	section.customError:ClearAllPoints()
	section.customError:SetPoint("LEFT", section.customLabel, "RIGHT", 12, 0)
	section.placeholder = Widgets.Label(section.customArea.frame, "GameFontHighlight", false, "muted")
	section.placeholder:SetPoint("TOPLEFT", 10, -9)
	local function placeholder()
		local empty = (section.custom:GetText() or "") == ""
		section.placeholder:SetShown(empty and not section.custom.focused)
	end
	hook(section.custom, "OnTextChanged", placeholder)
	hook(section.custom, "OnEditFocusGained", function() section.placeholder:Hide() end)
	hook(section.custom, "OnEditFocusLost", placeholder)
	-- Keyboard: Escape leaves the field; Enter keeps new lines (multi-line).
	section.chain = Widgets.FocusChain({ onEscape = function() end })
	section.chain.SetFields({ section.custom })

	local function saveCustom()
		local text = section.custom:GetText() or ""
		local result, message = Actions.Decide(ns.ctx, section.reactionId, { custom = text })
		if not result then
			Widgets.SetFieldError(section.custom, message)
			MainWindow.SetStatus(message)
			return
		end
		Widgets.SetFieldError(section.custom, nil)
		section.custom:SetText("")
		section.custom:ClearFocus()
		MainWindow.SetStatus(message)
		MainWindow.Refresh()
	end

	section.save = Widgets.Button(card, "Save answer", 130, L.buttonH, "primary")
	at(section.save, card, L.pad, L.buttonsTop)
	section.save:SetScript("OnClick", saveCustom)
	Widgets.Tooltip(section.save, "Save answer", "Save the answer you wrote in your own words. It proposes no "
		.. "personality change; adjust personality by hand if you wish.")
	-- Later and Not now are different actions (Core/Reactions.lua):
	-- Later marks the moment "kept for later" (Reflect brings it back);
	-- Not now only stops the reminder, the moment stays waiting as it is.
	section.later = Widgets.Button(card, "Later", 80, L.buttonH, "ghost")
	at(section.later, card, L.pad + 130 + 8, L.buttonsTop)
	section.later:SetScript("OnClick", function() act(Actions.PostponeReaction, section.reactionId) end)
	Widgets.Tooltip(section.later, "Later", "Keep it here for later. You will not be reminded again.")
	section.notNow = Widgets.Button(card, "Not now", 90, L.buttonH, "ghost")
	at(section.notNow, card, L.pad + 130 + 8 + 80 + 8, L.buttonsTop)
	section.notNow:SetScript("OnClick", function() act(Actions.IgnoreReaction, section.reactionId) end)
	Widgets.Tooltip(section.notNow, "Not now", "Leave it waiting quietly, without reminders.")
	section.dismiss = Widgets.Button(card, "Dismiss", 90, L.buttonH, "danger")
	at(section.dismiss, card, L.pad + L.inner - 90, L.buttonsTop)
	section.dismiss:SetScript("OnClick", function() act(Actions.DismissReaction, section.reactionId) end)
	Widgets.Tooltip(section.dismiss, "Dismiss", "Never ask about this. The event stays in your record.")

	-- Empty state, inside the same card.
	section.heading = Widgets.Label(card, "GameFontNormalLarge", true, "title")
	section.heading:SetJustifyH("CENTER")
	section.heading:SetPoint("TOP", card, "TOP", 0, -110)
	section.heading:SetWidth(420)
	section.heading:SetText(StoryView.HEADING)
	section.body = Widgets.Label(card, "GameFontHighlight", true, "body")
	section.body:SetJustifyH("CENTER")
	section.body:SetPoint("TOP", section.heading, "BOTTOM", 0, -14)
	section.body:SetWidth(420)
	section.body:SetText(StoryView.BODY)
	section.summary = Widgets.Label(card, "GameFontHighlightSmall", true, "muted")
	section.summary:SetJustifyH("CENTER")
	section.summary:SetPoint("TOP", section.body, "BOTTOM", 0, -18)
	section.summary:SetWidth(420)

	--- Also waiting --------------------------------------------------------------
	local sideX = L.cardW + L.gap
	local waiting = Widgets.Panel(f, "Also waiting")
	section.waitingPanel = waiting
	waiting:SetWidth(L.sideW)
	at(waiting, f, sideX, 0)
	-- Reflection (#29): bring back everything kept for later.
	section.reflect = Widgets.Button(waiting, "Reflect", 64, 20, "ghost")
	section.reflect:SetPoint("TOPRIGHT", waiting, "TOPRIGHT", -10, -10)
	section.reflect:SetScript("OnClick", function()
		ns.Commands.Execute(ns.ctx, "reflect")
		MainWindow.Refresh()
	end)
	Widgets.Tooltip(section.reflect, "Reflect", "Bring back the moments you kept for later. Nothing has to change.")
	for i = 1, StoryView.MAX_WAITING do
		local row = Widgets.Button(waiting, "", L.sideInner, L.rowH)
		row.text = Widgets.Label(row, "GameFontHighlightSmall", true, "small")
		row.text:SetPoint("TOPLEFT", 8, -6)
		row.text:SetWidth(L.sideInner - 16)
		row.text:SetHeight(28)
		row.meta = Widgets.Label(row, "GameFontHighlightSmall", false, "muted")
		row.meta:SetPoint("BOTTOMLEFT", 8, 5)
		row.meta:SetWidth(L.sideInner - 16)
		row:SetScript("OnClick", function(self)
			section.index = self.listIndex
			MainWindow.Refresh()
		end)
		section.waitingRows[i] = row
	end
	section.waitingNote = Widgets.Label(waiting, "GameFontHighlightSmall", true, "muted")
	section.waitingNote:SetWidth(L.sideInner)

	--- Growth to approve ------------------------------------------------------------
	local growth = Widgets.Panel(f, "Growth to approve")
	section.growthPanel = growth
	growth:SetWidth(L.sideW)
	for i = 1, StoryView.MAX_CHANGES do
		-- Each change is its own card, its Approve and Reject inside it.
		local row = Widgets.EntryRow(growth)
		row:SetSize(L.sideInner, L.changeH)
		row.label = Widgets.Label(row, "GameFontNormal", false, "accent")
		row.label:SetPoint("TOPLEFT", 8, -8)
		row.label:SetWidth(L.sideInner - 16)
		row.reason = Widgets.Label(row, "GameFontHighlightSmall", true, "muted")
		row.reason:SetPoint("TOPLEFT", 8, -28)
		row.reason:SetWidth(L.sideInner - 16)
		row.reason:SetHeight(30)
		local half = (L.sideInner - 16 - 6) / 2
		row.approve = Widgets.Button(row, "Approve", half, 22, "primary")
		row.approve:SetPoint("TOPLEFT", 8, -64)
		row.approve:SetScript("OnClick", function() act(Actions.ApplyChange, row.changeId) end)
		row.reject = Widgets.Button(row, "Reject", half, 22, "ghost")
		row.reject:SetPoint("LEFT", row.approve, "RIGHT", 6, 0)
		row.reject:SetScript("OnClick", function() act(Actions.RejectChange, row.changeId) end)
		section.changeRows[i] = row
	end
	section.moreChanges = Widgets.Label(growth, "GameFontHighlightSmall", false, "muted")
	for i = 1, StoryView.MAX_APPLIED do
		local row = Widgets.EntryRow(growth)
		row:SetSize(L.sideInner, L.appliedH)
		row.label = Widgets.Label(row, "GameFontHighlightSmall", false, "small")
		row.label:SetPoint("LEFT", 8, 0)
		row.label:SetWidth(L.sideInner - 16 - 70)
		row.reverse = Widgets.Button(row, "Reverse", 64, 20, "ghost")
		row.reverse:SetPoint("RIGHT", -4, 0)
		row.reverse:SetScript("OnClick", function()
			local id, text = row.changeId, row.describe
			Widgets.Confirm("Reverse this change (" .. text .. ")? The axis steps back by one. "
				.. "You can always set personality by hand.", "Reverse", function()
				act(Actions.ReverseChange, id)
			end)
		end)
		Widgets.Tooltip(row.reverse, "Reverse", "Undo this applied change: the axis steps back by one.")
		section.appliedRows[i] = row
	end
	section.growthNote = Widgets.Label(growth, "GameFontHighlightSmall", true, "muted")
	section.growthNote:SetWidth(L.sideInner)

	local reactionWidgets = { section.prev, section.position, section.next, section.question, section.why,
		section.customLabel, section.customArea.frame, section.save, section.later, section.notNow, section.dismiss }

	-- Every label and control paints itself (UI/Style.lua).
	function section:ApplyTheme(theme)
		self.theme = theme
	end

	--- Selects a reaction by ID (from the reaction card).
	function section:Focus(reactionId)
		self.focusId = reactionId
	end

	local function name(char)
		local field = char and char.fields and char.fields.name
		return field and field.value or nil
	end

	local function refreshChips(chips)
		local x, limit = L.pad, L.inner
		for i, chip in ipairs(section.chips) do
			local c = chips[i]
			if c then
				chip:SetChip(c.text, c.tone)
				local w = chip:GetWidth() or 0
				if x + w > L.pad + limit then c = nil end
			end
			chip:SetShown(c ~= nil)
			if c then
				at(chip, card, x, L.chipsTop)
				x = x + (chip:GetWidth() or 0) + 8
			end
		end
	end

	local function refreshWaiting(char, list, now)
		local pad = Widgets.PANEL_PAD
		local y = -36
		local shown = 0
		for i, r in ipairs(list) do
			if i ~= section.index and shown < StoryView.MAX_WAITING then
				shown = shown + 1
				local row = section.waitingRows[shown]
				local view = Reactions.Present(char, r, now)
				local record = view and view.record
				row.listIndex = i
				row.text:SetText(view and view.question or ("Moment #" .. r.id))
				local meta = { record and ns.GameEvents.RecordLabel(record) or ns.GameEvents.Label(r.category) }
				meta[#meta + 1] = StoryView.Ago(record and record.at or r.createdAt, now)
				if r.status == "postponed" then meta[#meta + 1] = "kept for later" end
				row.meta:SetText(table.concat(meta, " · "))
				at(row, waiting, pad, y)
				y = y - L.rowH - L.rowGap
			end
		end
		for i = shown + 1, StoryView.MAX_WAITING do
			section.waitingRows[i]:Hide()
		end
		for i = 1, shown do
			section.waitingRows[i]:Show()
		end
		local others = math.max(0, #list - 1)
		local note
		if #list == 0 then
			note = "Nothing is waiting."
		elseif others == 0 then
			note = "Nothing else is waiting."
		elseif others > shown then
			note = string.format("%d more: use < > above.", others - shown)
		end
		section.waitingNote:SetShown(note ~= nil)
		if note then
			section.waitingNote:SetText(note)
			at(section.waitingNote, waiting, pad, y)
			y = y - 18
		end
		local height = -y + pad - L.rowGap
		waiting:SetHeight(height)
		return height
	end

	local function refreshGrowth(char, top)
		local pad = Widgets.PANEL_PAD
		at(growth, f, L.cardW + L.gap, top)
		local y = -36
		local pending = char and Evolution.Pending(char) or {}
		for i, row in ipairs(section.changeRows) do
			local change = pending[i]
			row:SetShown(change ~= nil)
			if change then
				row.changeId = change.id
				row.label:SetText("More " .. Evolution.AxisLabel(change.axis, change.delta))
				row.reason:SetText(StoryView.ChangeReason(change))
				Widgets.Tooltip(row.approve, "Approve", Evolution.Describe(change))
				at(row, growth, pad, y)
				y = y - L.changeH - L.rowGap
			end
		end
		local more = #pending - StoryView.MAX_CHANGES
		section.moreChanges:SetShown(more > 0)
		if more > 0 then
			section.moreChanges:SetText(string.format("%d more waiting: /dawnward develop", more))
			at(section.moreChanges, growth, pad, y)
			y = y - 18
		end
		local applied = char and StoryView.Reversible(char, StoryView.MAX_APPLIED) or {}
		for i, row in ipairs(section.appliedRows) do
			local change = applied[i]
			row:SetShown(change ~= nil)
			if change then
				row.changeId = change.id
				row.describe = Evolution.Describe(change)
				row.label:SetText("Applied: more " .. Evolution.AxisLabel(change.axis, change.delta))
				at(row, growth, pad, y)
				y = y - L.appliedH - 4
			end
		end
		local who = name(char)
		local note
		if char and char.story.prefs.approval == "auto" then
			note = "Automatic approval is on (Settings): answers apply their changes at once. "
				.. "Each one can be reversed here."
		else
			note = "Nothing about " .. (who and (who .. "'s") or "your character's")
				.. " personality changes without your approval, and approved changes can be reversed."
		end
		if #pending == 0 and #applied == 0 then
			note = "No personality changes are waiting. " .. note
		end
		section.growthNote:SetText(note)
		at(section.growthNote, growth, pad, y - 2)
		local noteH = section.growthNote.GetStringHeight and section.growthNote:GetStringHeight() or 42
		if type(noteH) ~= "number" or noteH <= 0 then noteH = 42 end
		y = y - 2 - noteH
		growth:SetHeight(-y + pad)
	end

	function section:Refresh(view)
		local char = view.char
		local now = view.ctx.now()
		self.summary:SetText(StoryView.Summary(char, now))
		local list = char and Reactions.List(char, now) or {}
		if self.focusId then
			for i, r in ipairs(list) do
				if r.id == self.focusId then self.index = i end
			end
			self.focusId = nil
		end
		self.index = math.max(1, math.min(self.index, #list))
		local reaction = list[self.index]
		local presentation = reaction and Reactions.Present(char, reaction, now)
		if self.reactionId ~= (reaction and reaction.id) then
			Widgets.SetFieldError(self.custom, nil)
		end
		self.reactionId = reaction and reaction.id
		local hasReaction = presentation ~= nil
		for _, w in ipairs(reactionWidgets) do
			w:SetShown(hasReaction)
		end
		self.heading:SetShown(not hasReaction)
		self.body:SetShown(not hasReaction)
		self.summary:SetShown(not hasReaction)
		local window = MainWindow.GetFrame()
		if hasReaction then
			self.position:SetText(string.format("%d of %d%s", self.index, #list,
				reaction.status == "postponed" and " · kept for later" or ""))
			if window and window.eyebrow then
				window.eyebrow:SetText(string.format("STORY · MOMENT %d OF %d", self.index, #list))
			end
			self.prev:SetEnabled(self.index > 1)
			self.next:SetEnabled(self.index < #list)
			self.question:SetText(presentation.question)
			refreshChips(StoryView.Chips(char, presentation, now))
			local lines = StoryView.WhyLines(presentation, StoryView.RelevantMemories(char, presentation))
			self.context.lines = lines
			Style.Repaint(self.context)
			self.why:SetShown(#lines > 0)
			self.placeholder:SetText("What does " .. (presentation.name or "your character") .. " think or feel?")
			self.placeholder:SetShown((self.custom:GetText() or "") == "" and not self.custom.focused)
		else
			refreshChips({})
		end
		for i, button in ipairs(self.optionButtons) do
			local option = hasReaction and presentation.options[i]
			button:SetShown(option and true or false)
			if option then
				button.optionId = option.id
				button:SetText(option.text)
				button.hint:SetText(StoryView.OptionHint(option))
				Widgets.Tooltip(button, "Answer " .. i, option.meaning or option.text)
			end
		end
		local waitH = refreshWaiting(char, list, now)
		refreshGrowth(char, -(waitH + 12))
	end

	StoryView.section = section
	return section
end

MainWindow.RegisterSection({ id = "story", label = "Story", order = 3, heading = "A moment for your story",
	titleInset = 230,
	icon = "Interface\\Icons\\INV_Misc_Note_01", create = create })
