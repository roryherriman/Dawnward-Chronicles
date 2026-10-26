-- A small, non-blocking card announcing a waiting story moment. It is shown
-- only by Platform/SafeTime (never in combat, while dead, in a cinematic or
-- loading), hides itself when combat starts, and never answers for the
-- player: "Answer" opens the Story section on that moment.
local _, ns = ...
local Widgets, MainWindow, Actions, Reactions = ns.Widgets, ns.MainWindow, ns.Actions, ns.Reactions

local ReactionCard = {}
ns.ReactionCard = ReactionCard

ReactionCard.WIDTH, ReactionCard.HEIGHT = 380, 104

local card

local function build()
	card = CreateFrame("Frame", "DawnwardChroniclesReactionCard", UIParent,
		BackdropTemplateMixin and "BackdropTemplate" or nil)
	card:SetSize(ReactionCard.WIDTH, ReactionCard.HEIGHT)
	card:SetPoint("TOP", 0, -140)
	card:SetFrameStrata("MEDIUM")
	card:SetToplevel(true)
	card:Hide()
	card.background = Widgets.Solid(card, "BACKGROUND")
	card.background:SetAllPoints(card)
	card.title = Widgets.Label(card, "GameFontNormal")
	card.title:SetPoint("TOPLEFT", 12, -10)
	card.title:SetText("A moment for your story")
	card.question = Widgets.Label(card, "GameFontHighlight", true)
	card.question:SetPoint("TOPLEFT", 12, -30)
	card.question:SetWidth(ReactionCard.WIDTH - 24)
	card.answer = Widgets.Button(card, "Answer", 90, 22)
	card.answer:SetPoint("BOTTOMLEFT", 12, 10)
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
	card.later = Widgets.Button(card, "Later", 80, 22)
	card.later:SetPoint("LEFT", card.answer, "RIGHT", 6, 0)
	card.later:SetScript("OnClick", function()
		Actions.PostponeReaction(ns.ctx, card.reactionId)
		card:Hide()
		MainWindow.Refresh()
	end)
	card.dismiss = Widgets.Button(card, "Dismiss", 80, 22)
	card.dismiss:SetPoint("LEFT", card.later, "RIGHT", 6, 0)
	card.dismiss:SetScript("OnClick", function()
		Actions.DismissReaction(ns.ctx, card.reactionId)
		card:Hide()
		MainWindow.Refresh()
	end)
	card.close = Widgets.Button(card, "x", 22, 20)
	card.close:SetPoint("TOPRIGHT", -6, -6)
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
	Widgets.SetColor(card.background, theme.background, 0.95)
	Widgets.TextColor(card.title, theme.accent)
	Widgets.TextColor(card.question, theme.text)
	if card.SetBackdropBorderColor then
		card:SetBackdropBorderColor(theme.border[1], theme.border[2], theme.border[3], 1)
	end
	card.reactionId = reactionId
	card.question:SetText(view.question)
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

