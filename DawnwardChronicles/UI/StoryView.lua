-- Story section ("Story Director", docs/design/mockups/story-director.png):
-- the living chronicle in the journal window.
--
--   header       eyebrow "Story · moment 1 of 2" and < > between moments
--   moment card  where, what and when (chips from the event record), the
--                question in large reading type, a "Why now" well (the
--                Director's own reasons, the memories this moment touches
--                and the player's own earlier answer, "Last time"), the
--                answers as a two-column grid of numbered choice cards with
--                each answer's personality hint, "in your own words", and
--                Save answer / Later / Not now / Dismiss at the bottom
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
StoryView.MAX_WHY_ROWS = 3 -- Why now, remembers, Last time
-- Both side panels stay inside the content height: { waiting rows, changes
-- waiting for approval, applied changes } tried in order. The second
-- waiting row goes first (the pager still reaches it), then the second
-- applied change, then the second waiting change (both still listed by
-- /dawnward develop).
StoryView.SIDE_STEPS = { { 2, 2, 2 }, { 1, 2, 2 }, { 1, 2, 1 }, { 1, 1, 1 }, { 1, 1, 0 } }

-- Layout (UI units), from docs/design/mockups/source/Story.dc.html. The
-- moment card flows top to bottom (chips, question, "Why now", answers, own
-- words) and keeps its action row at the bottom, as the mockup does. The
-- vertical positions come from StoryView.MomentLayout, from the measured
-- text, so nothing overlaps whatever a moment holds.
local L = {
	contentW = MainWindow.ContentWidth(), contentH = MainWindow.ContentHeight(),
	sideW = 236, gap = 20, pad = 22,
	chipH = Style.CONTROL.chip, chipGap = 8,
	-- The question: Alegreya Sans 22 with the mockup's 1.4 line height.
	question = { size = 22, spacing = 6, maxLines = 3 },
	-- The "Why now" well: padding 10 / 12, 14 px lines (bold label, muted text).
	why = { padX = 12, padY = 10, size = 14, spacing = 4, rowGap = 4, labelGap = 5, maxLines = 2 },
	-- Answer cards: at least 52 high, a 24 px number disc 14 in, the answer
	-- (16 on a 20 line) 12 right of it, and its hint (13) under it.
	option = { min = 52, key = 24, keyLeft = 14, textGap = 12, padRight = 12, size = 16, spacing = 4,
		hint = 13, hintGap = 3, maxLines = 3 },
	optionGap = 8,
	customLabelH = 18, customLabelGap = 6, customMax = 64, customMin = Style.CONTROL.input,
	buttonH = Style.CONTROL.standard, buttonGap = 8, buttonPad = 16,
	headerIcon = Style.CONTROL.icon, headerUp = 74, -- prev/next sit in the window header, beside Close
	-- Side panels: rows and change cards pad 10, 6 apart; panels 12 apart.
	sidePad = 10, rowGap = 6, panelGap = 12, panelTitle = 36,
	rowText = { size = 15, spacing = 3, maxLines = 2 }, rowMeta = 13, rowMetaGap = 2,
	reason = { size = 13, spacing = 4, maxLines = 2 }, changeLabel = 15, changeGap = 6, changeButtonsGap = 10,
	appliedH = 34, smallButton = Style.CONTROL.compact, reverseH = Style.CONTROL.chip, reflectH = Style.CONTROL.chip,
	note = { size = 13, spacing = 4 },
}
-- Two spacings: the mockup's ("comfortable"), and a tighter one used only
-- when a moment holds more than the comfortable card has room for.
L.DENSITY = {
	{ name = "comfortable", top = 20, bottom = 20, gap = 12, optionPadY = 8, optionGap = 8 },
	{ name = "compact", top = 16, bottom = 16, gap = 8, optionPadY = 6, optionGap = 6 },
}
L.cardW = L.contentW - L.sideW - L.gap
L.inner = L.cardW - 2 * L.pad
L.colW = (L.inner - L.optionGap) / 2
L.optionTextW = L.colW - L.option.keyLeft - L.option.key - L.option.textGap - L.option.padRight
L.whyInner = L.inner - 2 * L.why.padX
L.sideInner = L.sideW - 2 * Widgets.PANEL_PAD
L.rowInner = L.sideInner - 2 * L.sidePad
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
-- (only a proposal) and what it is about, from the library. With width,
-- the theme is left out when the whole hint would not fit on one line of
-- that width (the answer's tooltip always has it). Pure.
function StoryView.OptionHint(option, width)
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
	if option.theme and width and hint ~= "" then
		local theme = option.theme:sub(1, 1):upper() .. option.theme:sub(2)
		local full = hint .. " · " .. theme
		return Style.TextWidth(full, "small") <= width and full or hint
	elseif option.theme then
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

local function sentence(text)
	return text:find("[%.!?]$") and text or (text .. ".")
end

--- The "Why now" well: { { label, text } } lines. Pure.
-- separateEcho puts the player's own earlier answer (Director.Echo) on its
-- own "Last time:" line, as the Story screen shows it; without it the echo
-- ends the "Why now" line (as chat and older callers expect).
function StoryView.WhyLines(presentation, memories, separateEcho)
	local lines = {}
	local why = {}
	for _, r in ipairs(presentation.why or {}) do why[#why + 1] = r end
	local text = #why > 0 and table.concat(why, "; ") or nil
	if presentation.context then
		text = text and (text .. " " .. presentation.context) or presentation.context
	end
	if text then
		text = text .. "."
		if presentation.echo and not separateEcho then text = text .. " Last time: " .. presentation.echo .. "." end
		lines[#lines + 1] = { label = "Why now:", text = text }
	end
	if memories and #memories > 0 then
		local quoted = {}
		for i, title in ipairs(memories) do quoted[i] = "\226\128\156" .. title .. "\226\128\157" end
		lines[#lines + 1] = { label = (presentation.name or "They") .. " remembers:", text = table.concat(quoted, "; ") }
	end
	if presentation.echo and separateEcho then
		lines[#lines + 1] = { label = "Last time:", text = sentence(presentation.echo), echo = true }
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

--- Height of lines of text at size with spacing between lines. Pure.
function StoryView.TextHeight(lines, size, spacing)
	if not lines or lines <= 0 then return 0 end
	return lines * size + (lines - 1) * spacing
end

--- Estimated number of lines text wraps to at width, set in a Dawnward
-- style's font at size (word wrap, real advance widths, Style.TextWidth).
-- indent narrows the first line. Pure.
function StoryView.WrapLines(text, style, size, width, indent)
	local spec = Style.FONT_BY_STYLE[style] or Style.FONT_BY_STYLE.body
	local scale = (size or spec.size) / spec.size
	local space = Style.TextWidth(" ", style) * scale
	local total = 0
	for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
		local lines, x = 1, indent or 0
		indent = nil
		local first = true
		for word in paragraph:gmatch("%S+") do
			local w = Style.TextWidth(word, style) * scale
			if first then
				x = x + w
				first = false
			elseif x + space + w <= width then
				x = x + space + w
			else
				lines = lines + 1
				x = w
			end
			while x > width do -- a word longer than the line breaks anywhere
				lines = lines + 1
				x = x - width
			end
		end
		total = total + lines
	end
	return math.max(1, total)
end

--- Width of an action button for its label: the label plus the design's
-- 16 px padding on each side. Pure.
function StoryView.ButtonWidth(text)
	return math.ceil(Style.TextWidth(text, "button")) + 2 * L.buttonPad
end

--- Vertical layout of the moment card (distances down from its top edge).
-- m = { chips = bool, questionLines = n, whyRows = { { lines, stacked } },
-- rows = { lines of the taller answer in each row } }. Tries the mockup's
-- spacing first, then the compact one, then caps the "Why now" lines at one
-- and the question at two (their full text then shows on hover). Returns
-- { density, chipsTop, questionTop, questionH, questionLines, whyTop, whyH,
-- whyRows = { { top, lines } }, gridTop, rows = { { top, height, lines } },
-- customLabelTop, customTop, customH, buttonsTop, fits, capped }. Pure.
function StoryView.MomentLayout(m)
	local o, w = L.option, L.why
	local function build(d, caps)
		local out = { density = d.name, rows = {}, whyRows = {}, capped = false, padY = d.optionPadY }
		local y = d.top
		if m.chips then
			out.chipsTop = y
			y = y + L.chipH + d.gap
		end
		out.questionLines = math.min(m.questionLines or 1, caps.question)
		out.capped = out.capped or out.questionLines < (m.questionLines or 1)
		out.questionTop = y
		out.questionH = StoryView.TextHeight(out.questionLines, L.question.size, L.question.spacing)
		y = y + out.questionH + d.gap
		if m.whyRows and #m.whyRows > 0 then
			out.whyTop = y
			local inner = w.padY
			for i, row in ipairs(m.whyRows) do
				local lines = math.min(row.lines, caps.why)
				out.capped = out.capped or lines < row.lines
				if i > 1 then inner = inner + w.rowGap end
				out.whyRows[i] = { top = inner, lines = lines, stacked = row.stacked }
				inner = inner + StoryView.TextHeight(lines + (row.stacked and 1 or 0), w.size, w.spacing)
			end
			out.whyH = inner + w.padY
			y = y + out.whyH + d.gap
		end
		out.gridTop = y
		for i, lines in ipairs(m.rows or {}) do
			lines = math.min(lines, caps.option)
			out.capped = out.capped or lines < (m.rows[i] or 1)
			local h = 2 * d.optionPadY + StoryView.TextHeight(lines, o.size, o.spacing)
				+ (caps.hints and (o.hintGap + o.hint) or 0)
			h = math.max(o.min, h)
			out.rows[i] = { top = y, height = h, lines = lines }
			y = y + h + (i < #m.rows and d.optionGap or 0)
		end
		if m.rows and #m.rows > 0 then y = y + d.gap end
		out.customLabelTop = y
		y = y + L.customLabelH + L.customLabelGap
		out.customTop = y
		out.buttonsTop = L.contentH - d.bottom - L.buttonH
		local room = out.buttonsTop - d.gap - y
		out.customH = math.max(L.customMin, math.min(L.customMax, room))
		out.fits = room >= L.customMin
		out.optionGap = d.optionGap
		out.optionLines = caps.option
		out.hints = caps.hints
		return out
	end
	local open = { question = L.question.maxLines, why = w.maxLines, option = o.maxLines, hints = true }
	local steps = {
		{ L.DENSITY[1], open },
		{ L.DENSITY[2], open },
		{ L.DENSITY[2], { question = L.question.maxLines, why = 1, option = o.maxLines, hints = true } },
		{ L.DENSITY[2], { question = 2, why = 1, option = o.maxLines, hints = true } },
		{ L.DENSITY[2], { question = 2, why = 1, option = 2, hints = true } },
		-- The fullest moments (eight answers, three "Why now" lines): the
		-- hints move into each answer's tooltip.
		{ L.DENSITY[2], { question = 2, why = 1, option = 2, hints = false } },
	}
	local layout
	for _, step in ipairs(steps) do
		layout = build(step[1], step[2])
		if layout.fits then break end
	end
	return layout
end

--- Building blocks --------------------------------------------------------------------

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

local function spacing(fs, px)
	if fs.SetSpacing then fs:SetSpacing(px) end
	return fs
end

local function maxLines(fs, n)
	if fs.SetMaxLines then fs:SetMaxLines(n) end
end

-- Sets text and returns how many lines it takes at width: the client's own
-- measurement where it gives one, never less than the estimate from the
-- font's advance widths (so a line is never cut because the client had not
-- laid the text out yet).
local function measure(fs, text, style, size, gap, width, indent)
	fs:SetText(text)
	maxLines(fs, 0)
	local n = StoryView.WrapLines(text, style, size, width, indent)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	if not indent and type(h) == "number" and h > 0 then
		n = math.max(n, math.floor((h + gap) / (size + gap) + 0.5))
	end
	return math.max(1, n)
end

local function stringWidth(fs, text, style)
	local w = fs.GetStringWidth and fs:GetStringWidth()
	if type(w) ~= "number" or w <= 0 then w = Style.TextWidth(text, style) end
	return math.ceil(w)
end

-- The moment card: the design's card colour with a dim gold edge
-- (#151B26 / #4A3E26 on Classic Dawnward).
local function paintMomentCard(p, theme)
	Style.Color(p.bg, theme.surface)
	p.edges:Paint(Style.Mix(theme.background, theme.border, 0.62), 1)
end

-- The "Why now" well: darker than the card, with a quiet edge (#11161E / #232C3D).
local function well(parent)
	local box = CreateFrame("Frame", nil, parent)
	box.bg = Style.Solid(box, "BACKGROUND")
	box.bg:SetAllPoints(box)
	box.edges = Style.Edge(box, "BORDER")
	Style.Register(box, function(b, theme)
		Style.Color(b.bg, Style.Mix(theme.background, theme.surface, 0.4))
		b.edges:Paint(Style.Tones(theme).track, 1)
	end)
	return box
end

-- The question in large reading type (22 px Alegreya Sans, 1.4 line height,
-- title white). FontInstance:SetFont is the call Style.InitFonts already makes
-- on its font objects (also FloatingChatFrame.lua in the 1.15.9 UI source).
-- Only when the bundled fonts loaded; otherwise the game font stays.
local function largeReading(fs)
	if not Style.UsesBundledFont("reading") or not fs.SetFont then
		return
	end
	local ok = pcall(fs.SetFont, fs, Style.FONT_DIR .. Style.FONT_FILES.body, L.question.size, "")
	if ok then
		spacing(fs, L.question.spacing)
		if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
	end
end

-- Answer cards (the mockup's .choice): #1A2230 fill, #33405A edge, the number
-- in a round disc. Hovered, a card takes the mockup's chosen look (warm dark
-- gold fill, gold edge, gold disc), since a click answers at once.
local BLACK = { 0, 0, 0 }
local function paintChoice(b, theme)
	local tones = Style.Tones(theme)
	local on = b.hover and b:IsEnabled()
	if on then
		Style.Color(b.bg, Style.Mix(BLACK, theme.accent, 0.195))
		b.edges:Paint(theme.accent, 1)
		Style.Color(b.key.ring, theme.accent)
		Style.Color(b.key.fill, theme.accent)
		Style.TextColor(b.key.label, theme.accentText)
		Style.TextColor(b.text, tones.heading)
		Style.TextColor(b.hint, tones.label)
	else
		Style.Color(b.bg, tones.cardHover)
		b.edges:Paint(tones.fieldEdge, 1)
		Style.Color(b.key.ring, tones.selectedEdge)
		Style.Color(b.key.fill, tones.cardHover)
		Style.TextColor(b.key.label, Style.Mix(theme.muted, theme.text, 0.25))
		Style.TextColor(b.text, theme.text)
		Style.TextColor(b.hint, theme.muted)
	end
end

-- One answer card: a number disc, the answer (up to two lines) and its hint.
local function choiceCard(parent, index, onClick)
	local o = L.option
	local b = Widgets.Button(parent, "", L.colW, o.min, "choice")
	b.key = CreateFrame("Frame", nil, b)
	b.key:SetSize(o.key, o.key)
	b.key:SetPoint("LEFT", o.keyLeft, 0)
	-- A 1 px ring: a disc in the edge colour under a disc 2 px smaller (square
	-- with a 1 px border where the client has no masks).
	b.key.ring = Style.Disc(b.key, "ARTWORK", 1, o.key)
	b.key.ring:SetPoint("CENTER", 0, 0)
	b.key.fill = Style.Disc(b.key, "ARTWORK", 2, o.key - 2)
	b.key.fill:SetPoint("CENTER", 0, 0)
	b.key.label = Widgets.Label(b.key, "badge", false)
	b.key.label:SetPoint("CENTER", 0, 0)
	b.key.label:SetJustifyH("CENTER")
	b.key.label:SetText(tostring(index))
	b.textLeft = o.keyLeft + o.key + o.textGap
	b.text = Widgets.Label(b, "reading", true)
	b.text:SetWidth(L.optionTextW)
	maxLines(b.text, o.maxLines)
	b.hint = Widgets.Label(b, "small", false)
	b.hint:SetWidth(L.optionTextW)
	b:SetScript("OnClick", onClick)
	-- Like any button, its text is the answer it gives.
	function b.SetText(self, t) self.text:SetText(t) end
	function b.GetText(self) return self.text:GetText() end
	return Style.Register(b, paintChoice)
end

-- Rows and cards inside the side panels (the mockup's inner cards):
-- #1A2230 fill and the plain edge; hovered, a lighter fill and gold edge.
local function paintSideRow(b, theme)
	local tones = Style.Tones(theme)
	Style.Color(b.bg, b.hover and tones.selectedFill or tones.cardHover)
	b.edges:Paint(b.hover and theme.border or theme.edge, 1)
end

local function paintSideCard(c, theme)
	local tones = Style.Tones(theme)
	Style.Color(c.bg, tones.cardHover)
	c.edges:Paint(c.hover and tones.selectedEdge or theme.edge, 1)
	c.bar:Hide()
end

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), index = 1, optionButtons = {}, changeRows = {},
		waitingRows = {}, appliedRows = {}, whyRows = {} }
	local f = section.frame

	local function act(fn, ...)
		local result, message = fn(ns.ctx, ...)
		MainWindow.SetStatus(message)
		MainWindow.Refresh()
		return result, message
	end

	-- Header: previous / next moment, in the window header beside Close
	-- (36 px icon buttons, 6 apart, as the mockup).
	section.next = Widgets.IconButton(f, ">", "Next moment", "Show the next waiting moment.")
	section.next:SetSize(L.headerIcon, L.headerIcon)
	section.next:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(L.headerIcon + 6), L.headerUp)
	section.prev = Widgets.IconButton(f, "<", "Previous moment", "Show the previous waiting moment.")
	section.prev:SetSize(L.headerIcon, L.headerIcon)
	section.prev:SetPoint("RIGHT", section.next, "LEFT", -6, 0)
	if Style.UsesBundledFont("glyph") then
		for _, b in ipairs({ section.prev, section.next }) do
			b.label:SetFontObject(Style.fontObjects[Style.FontFor("glyph")])
		end
	end
	section.prev:SetScript("OnClick", function() section.index = section.index - 1; MainWindow.Refresh() end)
	section.next:SetScript("OnClick", function() section.index = section.index + 1; MainWindow.Refresh() end)
	-- The pager's position ("1 of 2 · kept for later"), left of the arrows.
	section.position = Widgets.Label(f, "meta", false, "muted")
	section.position:SetPoint("RIGHT", section.prev, "LEFT", -10, 0)
	section.position:SetJustifyH("RIGHT")

	--- The moment card ------------------------------------------------------------
	local card = Widgets.Panel(f)
	Style.Register(card, paintMomentCard)
	section.card = card
	card:SetSize(L.cardW, L.contentH)
	at(card, f, 0, 0)

	section.chips = {}
	for i = 1, 4 do
		section.chips[i] = Widgets.Chip(card, "", "accent")
		section.chips[i]:SetMaxWidth(L.inner)
		section.chips[i]:Hide()
	end

	section.question = Widgets.Label(card, "reading", true, "title")
	largeReading(section.question)
	section.question:SetWidth(L.inner)
	-- Hover area for the full question when a long one is cut.
	section.questionHit = CreateFrame("Frame", nil, card)
	Widgets.Tooltip(section.questionHit, nil)

	section.why = well(card)
	section.why:SetWidth(L.inner)
	Widgets.Tooltip(section.why, nil)
	for i = 1, StoryView.MAX_WHY_ROWS do
		local row = {}
		row.label = Widgets.Label(section.why, "label", false, "heading")
		row.text = spacing(Widgets.Label(section.why, "meta", true, "muted"), L.why.spacing)
		section.whyRows[i] = row
	end
	-- What the well shows, as text (labels and reasons, one line each).
	section.context = {}
	function section.context.GetText()
		local out = {}
		for _, row in ipairs(section.whyRows) do
			if row.shown then out[#out + 1] = row.label:GetText() .. " " .. row.text:GetText() end
		end
		return table.concat(out, "\n")
	end

	for i = 1, StoryView.MAX_OPTIONS do
		local button = choiceCard(card, i, function(self)
			act(Actions.Decide, section.reactionId, { optionId = self.optionId })
		end)
		section.optionButtons[i] = button
	end

	section.customLabel = Widgets.Label(card, "GameFontNormal", false, "heading")
	section.customLabel:SetText("Or in your own words")
	section.customArea = Widgets.TextArea(card, 600, L.inner)
	section.customArea.frame:SetSize(L.inner, L.customMax)
	section.custom = section.customArea.edit
	local labelW = stringWidth(section.customLabel, "Or in your own words", "label")
	section.customError = Widgets.FieldError(section.custom, L.inner - labelW - 12)
	section.customError:ClearAllPoints()
	section.customError:SetPoint("LEFT", section.customLabel, "RIGHT", 12, 0)
	section.placeholder = Widgets.Label(section.customArea.frame, "GameFontHighlight", false, "muted")
	section.placeholder:SetPoint("TOPLEFT", Widgets.FIELD.textInset, -9)
	section.placeholder:SetPoint("RIGHT", section.customArea.frame, "RIGHT", -30, 0)
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

	-- The action row (standard 36 px buttons, 8 apart; Dismiss on the right).
	section.save = Widgets.Button(card, "Save answer", StoryView.ButtonWidth("Save answer"), L.buttonH, "primary")
	section.save:SetScript("OnClick", saveCustom)
	Widgets.Tooltip(section.save, "Save answer", "Save the answer you wrote in your own words. It proposes no "
		.. "personality change; adjust personality by hand if you wish.")
	-- Later and Not now are different actions (Core/Reactions.lua):
	-- Later marks the moment "kept for later" (Reflect brings it back);
	-- Not now only stops the reminder, the moment stays waiting as it is.
	section.later = Widgets.Button(card, "Later", StoryView.ButtonWidth("Later"), L.buttonH, "ghost")
	section.later:SetScript("OnClick", function() act(Actions.PostponeReaction, section.reactionId) end)
	Widgets.Tooltip(section.later, "Later", "Keep it here for later. You will not be reminded again.")
	section.notNow = Widgets.Button(card, "Not now", StoryView.ButtonWidth("Not now"), L.buttonH, "ghost")
	section.notNow:SetScript("OnClick", function() act(Actions.IgnoreReaction, section.reactionId) end)
	Widgets.Tooltip(section.notNow, "Not now", "Leave it waiting quietly, without reminders.")
	section.dismiss = Widgets.Button(card, "Dismiss", StoryView.ButtonWidth("Dismiss"), L.buttonH, "danger")
	section.dismiss:SetScript("OnClick", function() act(Actions.DismissReaction, section.reactionId) end)
	Widgets.Tooltip(section.dismiss, "Dismiss", "Never ask about this. The event stays in your record.")

	-- Empty state, inside the same card: a title, a short gold rule, the
	-- explanation in reading type and the summary of what is waiting.
	section.heading = Widgets.Label(card, "GameFontNormalLarge", true, "title")
	section.heading:SetJustifyH("CENTER")
	section.heading:SetPoint("TOP", card, "TOP", 0, -150)
	section.heading:SetWidth(440)
	section.heading:SetText(StoryView.HEADING)
	section.rule = Style.Solid(card, "ARTWORK")
	section.rule:SetSize(48, 1)
	section.rule:SetPoint("TOP", section.heading, "BOTTOM", 0, -14)
	Style.Register(section.rule, function(t, theme) Style.Color(t, theme.border) end)
	section.body = Widgets.Label(card, "reading", true, "reading")
	section.body:SetJustifyH("CENTER")
	section.body:SetPoint("TOP", section.rule, "BOTTOM", 0, -14)
	section.body:SetWidth(440)
	section.body:SetText(StoryView.BODY)
	section.summary = Widgets.Label(card, "meta", true, "muted")
	section.summary:SetJustifyH("CENTER")
	section.summary:SetPoint("TOP", section.body, "BOTTOM", 0, -18)
	section.summary:SetWidth(440)

	--- Also waiting --------------------------------------------------------------
	local sideX = L.cardW + L.gap
	local waiting = Widgets.Panel(f, "Also waiting")
	section.waitingPanel = waiting
	waiting:SetWidth(L.sideW)
	at(waiting, f, sideX, 0)
	-- Reflection (#29): bring back everything kept for later.
	section.reflect = Widgets.Button(waiting, "Reflect", 70, L.reflectH, "ghost")
	section.reflect:SetPoint("TOPRIGHT", waiting, "TOPRIGHT", -Widgets.PANEL_PAD, -9)
	section.reflect:SetScript("OnClick", function()
		ns.Commands.Execute(ns.ctx, "reflect")
		MainWindow.Refresh()
	end)
	Widgets.Tooltip(section.reflect, "Reflect", "Bring back the moments you kept for later. Nothing has to change.")
	for i = 1, StoryView.MAX_WAITING do
		local row = Widgets.Button(waiting, "", L.sideInner, 50)
		Style.Register(row, paintSideRow)
		row.text = spacing(Widgets.Label(row, "body", true, "body"), L.rowText.spacing)
		row.text:SetWidth(L.rowInner)
		at(row.text, row, L.sidePad, -L.sidePad)
		row.meta = Widgets.Label(row, "small", false, "muted")
		row.meta:SetWidth(L.rowInner)
		row:SetScript("OnClick", function(self)
			section.index = self.listIndex
			MainWindow.Refresh()
		end)
		section.waitingRows[i] = row
	end
	section.waitingNote = spacing(Widgets.Label(waiting, "small", true, "muted"), L.note.spacing)
	section.waitingNote:SetWidth(L.sideInner)

	--- Growth to approve ------------------------------------------------------------
	local growth = Widgets.Panel(f, "Growth to approve")
	section.growthPanel = growth
	growth:SetWidth(L.sideW)
	local half = (L.rowInner - 6) / 2
	for i = 1, StoryView.MAX_CHANGES do
		-- Each change is its own card, its Approve and Reject inside it.
		local row = Widgets.EntryRow(growth)
		Style.Register(row, paintSideCard)
		row:SetWidth(L.sideInner)
		row.label = Widgets.Label(row, "button", false)
		Widgets.SetTextRole(row.label, "accentBright")
		at(row.label, row, L.sidePad, -L.sidePad)
		row.label:SetWidth(L.rowInner)
		row.reason = spacing(Widgets.Label(row, "small", true, "muted"), L.reason.spacing)
		row.reason:SetWidth(L.rowInner)
		at(row.reason, row, L.sidePad, -(L.sidePad + L.changeLabel + L.changeGap))
		row.approve = Widgets.Button(row, "Approve", half, L.smallButton, "primary")
		row.approve:SetScript("OnClick", function() act(Actions.ApplyChange, row.changeId) end)
		row.reject = Widgets.Button(row, "Reject", half, L.smallButton, "ghost")
		row.reject:SetPoint("LEFT", row.approve, "RIGHT", 6, 0)
		row.reject:SetScript("OnClick", function() act(Actions.RejectChange, row.changeId) end)
		section.changeRows[i] = row
	end
	section.moreChanges = Widgets.Label(growth, "small", false, "muted")
	section.moreChanges:SetWidth(L.sideInner)
	for i = 1, StoryView.MAX_APPLIED do
		local row = Widgets.EntryRow(growth)
		Style.Register(row, paintSideCard)
		row:SetSize(L.sideInner, L.appliedH)
		row.label = Widgets.Label(row, "small", false, "small")
		row.label:SetPoint("LEFT", L.sidePad, 0)
		row.label:SetWidth(L.rowInner - 70 - 6)
		row.reverse = Widgets.Button(row, "Reverse", 70, L.reverseH, "ghost")
		row.reverse:SetPoint("RIGHT", -5, 0)
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
	section.growthNote = spacing(Widgets.Label(growth, "small", true, "muted"), L.note.spacing)
	section.growthNote:SetWidth(L.sideInner)

	local reactionWidgets = { section.prev, section.position, section.next, section.question, section.questionHit,
		section.why, section.customLabel, section.customArea.frame, section.save, section.later, section.notNow,
		section.dismiss }

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

	local function refreshChips(chips, top)
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
				at(chip, card, x, -top)
				x = x + (chip:GetWidth() or 0) + L.chipGap
			end
		end
	end

	-- Sets the "Why now" rows' text and measures them: { lines, stacked }.
	local function measureWhy(lines)
		local w = L.why
		local rows = {}
		for i, row in ipairs(section.whyRows) do
			local line = lines[i]
			row.shown = line ~= nil
			row.label:SetShown(row.shown)
			row.text:SetShown(row.shown)
			if line then
				row.label:SetText(line.label)
				row.labelW = stringWidth(row.label, line.label, "label")
				-- A long label ("Kyssarra Dawnwhisper remembers:") puts its text on
				-- the next line rather than squeezing it into a narrow column.
				row.stacked = row.labelW > L.whyInner * 0.45
				row.textX = row.stacked and 0 or (row.labelW + w.labelGap)
				row.text:SetWidth(L.whyInner - row.textX)
				row.full = line.text
				rows[i] = { lines = measure(row.text, safe(line.text), "meta", w.size, w.spacing,
					L.whyInner - row.textX), stacked = row.stacked }
			end
		end
		return rows
	end

	local function placeWhy(layout)
		local w = L.why
		local cut = {}
		for i, row in ipairs(section.whyRows) do
			local spec = layout.whyRows[i]
			if row.shown and spec then
				at(row.label, section.why, w.padX, -spec.top)
				local textTop = spec.top + (row.stacked and (w.size + w.spacing) or 0)
				at(row.text, section.why, w.padX + row.textX, -textTop)
				maxLines(row.text, spec.lines)
				if spec.lines < (section.whyMeasured[i].lines or 1) then
					cut[#cut + 1] = row.label:GetText() .. " " .. row.full
				end
			end
		end
		-- The full text on hover when a line had to be cut.
		Widgets.Tooltip(section.why, #cut > 0 and "Why now" or nil, #cut > 0 and table.concat(cut, "\n") or nil)
	end

	local function placeOption(button, x, row, layout)
		local o = L.option
		local padY = layout.padY
		at(button, card, x, -row.top)
		button:SetHeight(row.height)
		local lines = math.min(button.lines or 1, layout.optionLines)
		maxLines(button.text, layout.optionLines)
		local textH = StoryView.TextHeight(lines, o.size, o.spacing)
		local hintH = layout.hints and (o.hintGap + o.hint) or 0
		local top = math.floor((row.height - (textH + hintH)) / 2)
		top = math.max(padY, top)
		at(button.text, button, button.textLeft, -top)
		at(button.hint, button, button.textLeft, -(top + textH + o.hintGap))
		button.hint:SetShown(layout.hints and true or false)
	end

	local function refreshMoment(char, presentation, now)
		local o = L.option
		-- Measure first: the layout follows what this moment holds.
		local chips = StoryView.Chips(char, presentation, now)
		local qLines = measure(section.question, presentation.question, "reading", L.question.size,
			L.question.spacing, L.inner)
		local lines = StoryView.WhyLines(presentation, StoryView.RelevantMemories(char, presentation), true)
		section.whyMeasured = measureWhy(lines)
		local rows = {}
		for i, button in ipairs(section.optionButtons) do
			local option = presentation.options[i]
			button:SetShown(option and true or false)
			if option then
				button.optionId = option.id
				button:SetText(option.text)
				button.lines = measure(button.text, option.text, "reading", o.size, o.spacing, L.optionTextW)
				local hint = StoryView.OptionHint(option)
				button.hint:SetText(StoryView.OptionHint(option, L.optionTextW))
				local about = { option.text }
				if option.meaning and option.meaning ~= option.text then about[#about + 1] = option.meaning end
				about[#about + 1] = hint
				Widgets.Tooltip(button, "Answer " .. i, table.concat(about, "\n"))
				local r = math.floor((i - 1) / 2) + 1
				rows[r] = math.max(rows[r] or 1, math.min(button.lines, o.maxLines))
			end
		end
		local layout = StoryView.MomentLayout({ chips = #chips > 0, questionLines = qLines,
			whyRows = section.whyMeasured, rows = rows })
		section.layout = layout

		refreshChips(chips, layout.chipsTop or 0)
		at(section.question, card, L.pad, -layout.questionTop)
		maxLines(section.question, layout.questionLines)
		at(section.questionHit, card, L.pad, -layout.questionTop)
		section.questionHit:SetSize(L.inner, layout.questionH)
		local cutQuestion = layout.questionLines < qLines
		Widgets.Tooltip(section.questionHit, cutQuestion and "The question" or nil,
			cutQuestion and presentation.question or nil)

		section.why:SetShown(#lines > 0)
		if #lines > 0 then
			at(section.why, card, L.pad, -layout.whyTop)
			section.why:SetHeight(layout.whyH)
			placeWhy(layout)
		end

		for i, button in ipairs(section.optionButtons) do
			if button:IsShown() then
				local row = layout.rows[math.floor((i - 1) / 2) + 1]
				placeOption(button, L.pad + ((i - 1) % 2) * (L.colW + L.optionGap), row, layout)
			end
		end

		at(section.customLabel, card, L.pad, -layout.customLabelTop)
		at(section.customArea.frame, card, L.pad, -layout.customTop)
		section.customArea.frame:SetSize(L.inner, layout.customH)
		local y = -layout.buttonsTop
		at(section.save, card, L.pad, y)
		at(section.later, card, L.pad + section.save:GetWidth() + L.buttonGap, y)
		at(section.notNow, card, L.pad + section.save:GetWidth() + section.later:GetWidth() + 2 * L.buttonGap, y)
		at(section.dismiss, card, L.pad + L.inner - section.dismiss:GetWidth(), y)
	end

	-- Also waiting: up to limit rows. Returns the panel's height.
	local function refreshWaiting(char, list, now, limit)
		local pad = Widgets.PANEL_PAD
		local y = -L.panelTitle
		local shown = 0
		for i, r in ipairs(list) do
			if i ~= section.index and shown < limit then
				shown = shown + 1
				local row = section.waitingRows[shown]
				local view = Reactions.Present(char, r, now)
				local record = view and view.record
				row.listIndex = i
				local question = view and view.question or ("Moment #" .. r.id)
				local lines = measure(row.text, question, "body", L.rowText.size, L.rowText.spacing, L.rowInner)
				local shownLines = math.min(lines, L.rowText.maxLines)
				maxLines(row.text, shownLines)
				local meta = { record and ns.GameEvents.RecordLabel(record) or ns.GameEvents.Label(r.category) }
				meta[#meta + 1] = StoryView.Ago(record and record.at or r.createdAt, now)
				if r.status == "postponed" then meta[#meta + 1] = "kept for later" end
				row.meta:SetText(table.concat(meta, " · "))
				local textH = StoryView.TextHeight(shownLines, L.rowText.size, L.rowText.spacing)
				at(row.meta, row, L.sidePad, -(L.sidePad + textH + L.rowMetaGap))
				row:SetHeight(2 * L.sidePad + textH + L.rowMetaGap + L.rowMeta)
				Widgets.Tooltip(row, "Show this moment", question)
				at(row, waiting, pad, y)
				y = y - row:GetHeight() - L.rowGap
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
			local lines = measure(section.waitingNote, note, "small", L.note.size, L.note.spacing, L.sideInner)
			at(section.waitingNote, waiting, pad, y)
			y = y - StoryView.TextHeight(lines, L.note.size, L.note.spacing) - L.rowGap
		end
		local height = -y + pad - L.rowGap
		waiting:SetHeight(height)
		return height
	end

	-- Growth to approve: up to limits changes and applied rows. Returns its height.
	local function refreshGrowth(char, top, changeLimit, appliedLimit)
		local pad = Widgets.PANEL_PAD
		at(growth, f, L.cardW + L.gap, top)
		local y = -L.panelTitle
		local pending = char and Evolution.Pending(char) or {}
		for i, row in ipairs(section.changeRows) do
			local change = i <= changeLimit and pending[i] or nil
			row:SetShown(change ~= nil)
			if change then
				row.changeId = change.id
				row.label:SetText("More " .. Evolution.AxisLabel(change.axis, change.delta))
				local reason = StoryView.ChangeReason(change)
				local lines = measure(row.reason, reason, "small", L.reason.size, L.reason.spacing, L.rowInner)
				local shownLines = math.min(lines, L.reason.maxLines)
				maxLines(row.reason, shownLines)
				local reasonH = StoryView.TextHeight(shownLines, L.reason.size, L.reason.spacing)
				local buttonsTop = L.sidePad + L.changeLabel + L.changeGap + reasonH + L.changeButtonsGap
				at(row.approve, row, L.sidePad, -buttonsTop)
				row:SetHeight(buttonsTop + L.smallButton + L.sidePad)
				Widgets.Tooltip(row.approve, "Approve", Evolution.Describe(change))
				Widgets.Tooltip(row, lines > shownLines and row.label:GetText() or nil, reason)
				at(row, growth, pad, y)
				y = y - row:GetHeight() - L.rowGap
			end
		end
		local more = #pending - math.min(changeLimit, #pending)
		section.moreChanges:SetShown(more > 0)
		if more > 0 then
			section.moreChanges:SetText(string.format("%d more waiting: /dawnward develop", more))
			at(section.moreChanges, growth, pad, y)
			y = y - 18
		end
		local applied = char and StoryView.Reversible(char, StoryView.MAX_APPLIED) or {}
		for i, row in ipairs(section.appliedRows) do
			local change = i <= appliedLimit and applied[i] or nil
			row:SetShown(change ~= nil)
			if change then
				row.changeId = change.id
				row.describe = Evolution.Describe(change)
				row.label:SetText("Applied: more " .. Evolution.AxisLabel(change.axis, change.delta))
				at(row, growth, pad, y)
				y = y - L.appliedH - L.rowGap
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
		local lines = measure(section.growthNote, note, "small", L.note.size, L.note.spacing, L.sideInner)
		at(section.growthNote, growth, pad, y)
		y = y - StoryView.TextHeight(lines, L.note.size, L.note.spacing)
		local height = -y + pad
		growth:SetHeight(height)
		return height
	end

	local function refreshSide(char, list, now)
		for _, step in ipairs(StoryView.SIDE_STEPS) do
			local waitH = refreshWaiting(char, list, now, math.min(step[1], StoryView.MAX_WAITING))
			local growthH = refreshGrowth(char, -(waitH + L.panelGap), step[2], step[3])
			section.sideStep = step
			if waitH + L.panelGap + growthH <= L.contentH then return end
		end
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
		self.rule:SetShown(not hasReaction)
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
			self.placeholder:SetText("What does " .. (presentation.name or "your character") .. " think or feel?")
			self.placeholder:SetShown((self.custom:GetText() or "") == "" and not self.custom.focused)
			refreshMoment(char, presentation, now)
		else
			refreshChips({}, 0)
			for _, button in ipairs(self.optionButtons) do button:Hide() end
			for _, row in ipairs(self.whyRows) do row.shown = false end
		end
		refreshSide(char, list, now)
	end

	StoryView.section = section
	return section
end

MainWindow.RegisterSection({ id = "story", label = "Story", order = 3, heading = "A moment for your story",
	titleInset = 230,
	icon = "Interface\\Icons\\INV_Misc_Note_01", create = create })
