-- A small, non-blocking card announcing a waiting story moment. It is shown
-- only by Platform/SafeTime (never in combat, while dead, in a cinematic or
-- loading), hides itself when combat starts, and never answers for the
-- player: "Answer" opens the Story section on that moment.
-- Keyboard: Escape hides it like the close button (UISpecialFrames, as the
-- copy window and the setup wizard do); the moment keeps waiting.
--
-- Look: the Story screen's moment in miniature (docs/design/mockups/
-- story-director.png), in the same language: the gold frame line, the
-- eyebrow, the gold place chip and the event chip, the question in the
-- large reading type, the Director's "Why now" (a bold label with the reason
-- running on after it), and the design's compact (30 px) buttons. Its
-- height follows the question (up to 3 lines) and the reason (up to 2).
local _, ns = ...
local Widgets, MainWindow, Actions, Reactions, Style = ns.Widgets, ns.MainWindow, ns.Actions, ns.Reactions, ns.Style

local ReactionCard = {}
ns.ReactionCard = ReactionCard

ReactionCard.WIDTH = 420
ReactionCard.LAYOUT = { pad = 16, top = 14, eyebrowH = 18, chipGap = 6, chipH = Style.CONTROL.chip, gap = 10,
	buttonH = Style.CONTROL.compact, buttonGap = 16, close = 28,
	question = { size = 18, spacing = 5, maxLines = 3 }, why = { size = 14, spacing = 4, maxLines = 2, labelGap = 5 } }
local L = ReactionCard.LAYOUT
L.questionW = ReactionCard.WIDTH - 2 * L.pad
-- Chips stop short of the close button's column.
L.chipsW = L.questionW - L.close + 6

--- Card height for a question of lines lines and a "Why now" of whyLines
-- (0 when there is none). Pure.
function ReactionCard.Height(lines, whyLines)
	lines = math.max(1, math.min(lines or 1, L.question.maxLines))
	whyLines = math.max(0, math.min(whyLines or 0, L.why.maxLines))
	local q = lines * L.question.size + (lines - 1) * L.question.spacing
	local why = whyLines > 0 and (L.gap + whyLines * L.why.size + (whyLines - 1) * L.why.spacing) or 0
	return L.top + L.eyebrowH + L.chipGap + L.chipH + L.gap + q + why + L.buttonGap + L.buttonH + L.pad
end
ReactionCard.HEIGHT = ReactionCard.Height(2, 1)

--- The card's chips: where (gold) and what happened (neutral), from the
-- event record as the Story section shows them. Pure.
function ReactionCard.Chips(char, view)
	local out = {}
	for _, c in ipairs(ns.StoryView.Chips(char, view, nil)) do
		-- Where, then what happened; the tie and the level stay in the Story section.
		if #out == 0 and c.tone == "accent" then out[1] = c
		elseif c.tone == "muted" then out[#out + 1] = c; break end
	end
	return out
end

local card

local function width(text)
	return math.ceil(Style.TextWidth(text, "buttonSmall")) + 24
end

local function build()
	card = CreateFrame("Frame", "DawnwardChroniclesReactionCard", UIParent)
	card:SetSize(ReactionCard.WIDTH, ReactionCard.HEIGHT)
	card:SetPoint("TOP", 0, -140)
	card:SetFrameStrata("MEDIUM")
	card:SetToplevel(true)
	card:Hide()
	if type(UISpecialFrames) == "table" then
		tinsert(UISpecialFrames, card:GetName())
	end
	Style.Chrome(card, "background")
	card.background = card.chrome.fill
	card.title = Widgets.Label(card, nil, false, "eyebrow")
	card.title:SetPoint("TOPLEFT", L.pad, -L.top)
	card.title:SetText("A MOMENT FOR YOUR STORY")
	-- Where and what happened, as chips under the eyebrow (the Story
	-- section's first two); card.meta keeps the same facts as one line of
	-- text for the tooltip and for screen readers.
	local chipsTop = L.top + L.eyebrowH + L.chipGap
	card.chips = {}
	for i = 1, 2 do
		card.chips[i] = Widgets.Chip(card, "", i == 1 and "accent" or "muted")
		card.chips[i]:Hide()
	end
	card.meta = { text = "" }
	function card.meta.GetText(self) return self.text end
	card.question = Widgets.Label(card, "reading", true, "title")
	card.question:SetPoint("TOPLEFT", L.pad, -(chipsTop + L.chipH + L.gap))
	card.question:SetWidth(L.questionW)
	-- The large reading type of the Story section's question (bundled font only).
	if Style.UsesBundledFont("reading") and card.question.SetFont then
		local ok = pcall(card.question.SetFont, card.question, Style.FONT_DIR .. Style.FONT_FILES.body,
			L.question.size, "")
		if ok and card.question.SetSpacing then card.question:SetSpacing(L.question.spacing) end
	end
	card.whyLabel = Widgets.Label(card, "label", false, "heading")
	card.why = Widgets.Label(card, "meta", true, "muted")
	card.why:SetWidth(L.questionW)
	if card.why.SetSpacing then card.why:SetSpacing(L.why.spacing) end
	card.answer = Widgets.Button(card, "Answer", width("Answer") + 12, L.buttonH, "primary")
	card.answer:SetPoint("BOTTOMLEFT", L.pad, L.pad)
	card.answer:SetScript("OnClick", function()
		local id = card.reactionId
		card:Hide()
		if not MainWindow.IsShown() then
			MainWindow.Show()
		end
		if ns.StoryView and ns.StoryView.section then
			ns.StoryView.section:Focus(id)
		end
		MainWindow.Select("story")
	end)
	card.later = Widgets.Button(card, "Later", width("Later"), L.buttonH, "ghost")
	card.later:SetPoint("LEFT", card.answer, "RIGHT", 8, 0)
	card.later:SetScript("OnClick", function()
		Actions.PostponeReaction(ns.ctx, card.reactionId)
		card:Hide()
		MainWindow.Refresh()
	end)
	card.dismiss = Widgets.Button(card, "Dismiss", width("Dismiss"), L.buttonH, "danger")
	card.dismiss:SetPoint("BOTTOMRIGHT", -L.pad, L.pad)
	card.dismiss:SetScript("OnClick", function()
		Actions.DismissReaction(ns.ctx, card.reactionId)
		card:Hide()
		MainWindow.Refresh()
	end)
	card.close = Widgets.IconButton(card, "X", "Close", "Hide this card. The moment keeps waiting in the Story section.")
	card.close:SetSize(L.close, L.close)
	card.close:SetPoint("TOPRIGHT", -10, -10)
	card.close:SetScript("OnClick", function() card:Hide() end)
	card:RegisterEvent("PLAYER_REGEN_DISABLED")
	card:SetScript("OnEvent", function(self) self:Hide() end)
end

--- Shows the card for a reaction on the active character. Returns true if shown.
function ReactionCard.Show(reactionId)
	local ctx = ns.ctx
	local char = ctx and Actions.Character(ctx)
	local reaction = char and Reactions.Find(char, reactionId)
	local view = reaction and Reactions.Present(char, reaction)
	if not view or InCombatLockdown() then
		return false
	end
	if not card then
		build()
	end
	local theme = Actions.ThemeOf(char)
	if Style.Current() ~= theme then
		Style.Apply(theme)
	end
	card.reactionId = reactionId
	card.question:SetText(view.question)
	-- The card grows with the question; a longer one is cut at three lines
	-- (the Story section shows it whole).
	-- Measured a little narrow (as the Chronicle does, 0.96) so a line the
	-- client wraps sooner than the estimate still gets its room.
	local lines = ns.StoryView.WrapLines(view.question, "reading", L.question.size, L.questionW * 0.96)
	lines = math.min(lines, L.question.maxLines)
	if card.question.SetMaxLines then card.question:SetMaxLines(L.question.maxLines) end
	local qH = lines * L.question.size + (lines - 1) * L.question.spacing

	local record = view.record
	local meta = {}
	if record then
		meta[1] = ns.GameEvents.RecordLabel(record)
		if record.zone then meta[2] = record.zone end
	end
	card.meta.text = table.concat(meta, " · ")
	local x = L.pad
	local chips = ReactionCard.Chips(char, view)
	for i, chip in ipairs(card.chips) do
		local c = chips[i]
		if c then
			chip:SetMaxWidth(L.pad + L.chipsW - x)
			chip:SetChip(c.text, c.tone)
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(L.top + L.eyebrowH + L.chipGap))
			x = x + (chip:GetWidth() or 0) + 8
			if x > L.pad + L.chipsW then c = nil end
		end
		chip:SetShown(c ~= nil)
	end

	-- Why now: the Director's own reasons (the Story section's first line).
	local whyLines = 0
	local line = ns.StoryView.WhyLines(view, nil, true)[1]
	card.whyLabel:SetShown(line ~= nil)
	card.why:SetShown(line ~= nil)
	if line then
		local top = L.top + L.eyebrowH + L.chipGap + L.chipH + L.gap + qH + L.gap
		card.whyLabel:SetText(line.label)
		card.whyLabel:ClearAllPoints()
		card.whyLabel:SetPoint("TOPLEFT", L.pad, -top)
		card.why:ClearAllPoints()
		card.why:SetPoint("TOPLEFT", L.pad, -top)
		local labelW = card.whyLabel.GetStringWidth and card.whyLabel:GetStringWidth() or 0
		if type(labelW) ~= "number" or labelW <= 0 then labelW = Style.TextWidth(line.label, "label") end
		local text = tostring(line.text):gsub("|", "||")
		local prefix, indent = ns.StoryView.InlineIndent(labelW + L.why.labelGap, L.questionW)
		if prefix then
			card.why:SetText(prefix .. text)
			whyLines = ns.StoryView.WrapLines(text, "meta", L.why.size, L.questionW * 0.96, indent)
		else
			-- Without the bundled font: the reason under its label.
			card.why:ClearAllPoints()
			card.why:SetPoint("TOPLEFT", L.pad, -(top + L.why.size + L.why.spacing))
			card.why:SetText(text)
			whyLines = 1 + ns.StoryView.WrapLines(text, "meta", L.why.size, L.questionW * 0.96)
		end
		whyLines = math.min(whyLines, L.why.maxLines)
		if card.why.SetMaxLines then card.why:SetMaxLines(prefix and whyLines or math.max(1, whyLines - 1)) end
	end
	card:SetHeight(ReactionCard.Height(lines, whyLines))
	card:Show()
	return true
end

function ReactionCard.Hide()
	if card then
		card:Hide()
	end
end

function ReactionCard.Frame()
	return card
end
