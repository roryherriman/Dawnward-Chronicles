-- Story section: an empty state until the decision engine arrives (v0.3+).
local _, ns = ...
local Widgets, MainWindow = ns.Widgets, ns.MainWindow

local StoryView = {}
ns.StoryView = StoryView

StoryView.HEADING = "Your story is still being written"
StoryView.BODY = "Story decisions and character development are coming in a future version of "
	.. "Dawnward Chronicles.\n\n"
	.. "They will grow from what you write here: your journal, your character's history and the "
	.. "facts you choose to make part of their story. Nothing will change your character "
	.. "without your approval.\n\n"
	.. "For now, keep adventuring and keep writing."

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent) }
	local f = section.frame

	section.icon = f:CreateTexture(nil, "ARTWORK")
	section.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	section.icon:SetSize(48, 48)
	section.icon:SetPoint("TOP", 0, -56)

	section.heading = Widgets.Label(f, "GameFontNormalLarge", true)
	section.heading:SetJustifyH("CENTER")
	section.heading:SetPoint("TOP", section.icon, "BOTTOM", 0, -16)
	section.heading:SetWidth(440)
	section.heading:SetText(StoryView.HEADING)

	section.body = Widgets.Label(f, "GameFontHighlight", true)
	section.body:SetJustifyH("CENTER")
	section.body:SetPoint("TOP", section.heading, "BOTTOM", 0, -14)
	section.body:SetWidth(440)
	section.body:SetText(StoryView.BODY)

	function section:ApplyTheme(theme)
		Widgets.TextColor(self.heading, theme.accent)
		Widgets.TextColor(self.body, theme.text)
	end

	function section.Refresh() end -- static content; nothing to redraw

	return section
end

MainWindow.RegisterSection({ id = "story", label = "Story", order = 3, create = create })
