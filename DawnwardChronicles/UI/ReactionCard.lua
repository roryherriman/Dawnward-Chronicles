-- A small, non-blocking card announcing a waiting story moment. It is shown
-- only by Platform/SafeTime (never in combat, while dead, in a cinematic or
-- loading), hides itself when combat starts, and never answers for the
-- player: "Answer" opens the Story section on that moment.
local _, ns = ...
local Widgets, MainWindow, Actions, Reactions, Style = ns.Widgets, ns.MainWindow, ns.Actions, ns.Reactions, ns.Style

local ReactionCard = {}
ns.ReactionCard = ReactionCard

ReactionCard.WIDTH, ReactionCard.HEIGHT = 400, 116

local card

local function build()
	card = CreateFrame("Frame", "DawnwardChroniclesReactionCard", UIParent)
	card:SetSize(ReactionCard.WIDTH, ReactionCard.HEIGHT)
	card:SetPoint("TOP", 0, -140)
	card:SetFrameStrata("MEDIUM")
	card:SetToplevel(true)
	card:Hide()
	Style.Chrome(card, "background")
	card.background = card.chrome.fill
	card.title = Widgets.Label(card, "GameFontNormalSmall", false, "eyebrow")
	card.title:SetPoint("TOPLEFT", 16, -14)
	card.title:SetText("A MOMENT FOR YOUR STORY")
	card.question = Widgets.Label(card, "GameFontHighlight", true, "body")
	card.question:SetPoint("TOPLEFT", 16, -34)
	card.question:SetWidth(ReactionCard.WIDTH - 32)
	card.answer = Widgets.Button(card, "Answer", 96, 22, "primary")
	card.answer:SetPoint("BOTTOMLEFT", 16, 14)
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
	card.later = Widgets.Button(card, "Later", 80, 22, "ghost")
	card.later:SetPoint("LEFT", card.answer, "RIGHT", 6, 0)
	card.later:SetScript("OnClick", function()
		Actions.PostponeReaction(ns.ctx, card.reactionId)
		card:Hide()
		MainWindow.Refresh()
	end)
	card.dismiss = Widgets.Button(card, "Dismiss", 80, 22, "ghost")
	card.dismiss:SetPoint("LEFT", card.later, "RIGHT", 6, 0)
	card.dismiss:SetScript("OnClick", function()
		Actions.DismissReaction(ns.ctx, card.reactionId)
		card:Hide()
		MainWindow.Refresh()
	end)
	card.close = Widgets.IconButton(card, "X", "Close", "Hide this card. The moment keeps waiting in the Story section.")
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

