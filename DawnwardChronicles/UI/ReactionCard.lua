-- A small, non-blocking card announcing a waiting story moment. It is shown
-- only by Platform/SafeTime (never in combat, while dead, in a cinematic or
-- loading), hides itself when combat starts, and never answers for the
-- player: "Answer" opens the Story section on that moment.
-- Keyboard: Escape hides it like the close button (UISpecialFrames, as the
-- copy window and the setup wizard do); the moment keeps waiting.
--
-- Look: the Story screen's moment in miniature (docs/design/mockups/
-- story-director.png): the gold frame line, the eyebrow, what happened and
-- where in the meta style, the question in reading type, and the design's
-- compact (30 px) buttons. Its height follows the question (up to 3 lines).
local _, ns = ...
local Widgets, MainWindow, Actions, Reactions, Style = ns.Widgets, ns.MainWindow, ns.Actions, ns.Reactions, ns.Style

local ReactionCard = {}
ns.ReactionCard = ReactionCard

ReactionCard.WIDTH = 400
ReactionCard.LAYOUT = { pad = 16, top = 14, eyebrowH = 18, metaH = 18, gap = 8, buttonH = Style.CONTROL.compact,
	close = 28, question = { size = 16, spacing = 4, maxLines = 3 } }
local L = ReactionCard.LAYOUT
L.questionW = ReactionCard.WIDTH - 2 * L.pad

--- Card height for a question of lines lines. Pure.
function ReactionCard.Height(lines)
	lines = math.max(1, math.min(lines or 1, L.question.maxLines))
	local q = lines * L.question.size + (lines - 1) * L.question.spacing
	return L.top + L.eyebrowH + L.metaH + L.gap + q + 14 + L.buttonH + L.pad
end
ReactionCard.HEIGHT = ReactionCard.Height(2)

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
	-- What happened and where, from the event record (as in the Story section).
	card.meta = Widgets.Label(card, "meta", false, "muted")
	-- On its own line under the eyebrow, so a long place name is not cut.
	card.meta:SetPoint("TOPLEFT", L.pad, -(L.top + L.eyebrowH))
	card.meta:SetWidth(L.questionW - L.close)
	card.question = Widgets.Label(card, "reading", true, "title")
	card.question:SetPoint("TOPLEFT", L.pad, -(L.top + L.eyebrowH + L.metaH + L.gap))
	card.question:SetWidth(L.questionW)
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
	local lines = ns.StoryView and ns.StoryView.WrapLines(view.question, "reading", L.question.size,
		L.questionW * 0.96) or 2
	lines = math.min(lines, L.question.maxLines)
	if card.question.SetMaxLines then card.question:SetMaxLines(L.question.maxLines) end
	card:SetHeight(ReactionCard.Height(lines))
	local record = view.record
	local meta = {}
	if record then
		meta[1] = ns.GameEvents.RecordLabel(record)
		if record.zone then meta[2] = record.zone end
	end
	card.meta:SetText(table.concat(meta, " · "))
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
