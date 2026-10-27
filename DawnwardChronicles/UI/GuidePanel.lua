-- The guide panel (#51): a short tour and a searchable help reference over
-- the journal's content area. It opens by itself the first time a
-- character opens the journal (never during combat, since the journal only
-- opens when the player asks), and from the "?" button, Settings or
-- /dawnward guide. Closing it remembers that this character has seen it.
local _, ns = ...
local Widgets, MainWindow, Actions, Guide = ns.Widgets, ns.MainWindow, ns.Actions, ns.Guide

local GuidePanel = {}
ns.GuidePanel = GuidePanel

local INSET = 10
local LIST_WIDTH = 132
local BODY_LEFT = INSET + LIST_WIDTH + 14
local BODY_WIDTH = 580 - BODY_LEFT - INSET

--- Body text for a topic, or for search results. Pure.
function GuidePanel.TopicText(topic)
	return table.concat(topic.lines, "\n\n")
end

function GuidePanel.ResultsText(query, results)
	if #results == 0 then
		return string.format("Nothing matches '%s'. Try a single word, such as goal, privacy or minimap.", query)
	end
	local lines = { string.format("%d match%s for '%s':", #results, #results == 1 and "" or "es", query) }
	for i = 1, math.min(#results, 10) do
		lines[#lines + 1] = results[i].topic .. ": " .. results[i].line
	end
	if #results > 10 then
		lines[#lines + 1] = string.format("...and %d more. Add another word to narrow it down.", #results - 10)
	end
	return table.concat(lines, "\n\n")
end

local function create(parent)
	local panel = { topicButtons = {}, page = 1 }
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	if f.SetFrameLevel and parent.GetFrameLevel then
		f:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
	end
	if f.EnableMouse then f:EnableMouse(true) end
	f:Hide()
	panel.frame = f
	panel.background = Widgets.Solid(f, "BACKGROUND")
	panel.background:SetAllPoints(f)

	panel.title = Widgets.Label(f, "GameFontNormalLarge")
	panel.title:SetPoint("TOPLEFT", BODY_LEFT, -8)
	panel.title:SetWidth(BODY_WIDTH)
	panel.body = Widgets.Label(f, "GameFontHighlight", true)
	panel.body:SetPoint("TOPLEFT", BODY_LEFT, -36)
	panel.body:SetWidth(BODY_WIDTH)
	panel.body:SetHeight(300)

	local heading = Widgets.Label(f, "GameFontNormal")
	heading:SetPoint("TOPLEFT", INSET, -12)
	heading:SetText("Guide")
	panel.heading = heading
	for i, topic in ipairs(Guide.TOPICS) do
		local b = Widgets.Button(f, topic.title, LIST_WIDTH, 22)
		b:SetPoint("TOPLEFT", INSET, -36 - (i - 1) * 26)
		b:SetScript("OnClick", function() panel:Show(i) end)
		panel.topicButtons[i] = b
	end

	panel.search = Widgets.EditLine(f, 60)
	panel.search:SetPoint("BOTTOMLEFT", INSET + 6, 44)
	panel.search:SetWidth(LIST_WIDTH - 6)
	panel.searchButton = Widgets.Button(f, "Search", 70, 22)
	panel.searchButton:SetPoint("BOTTOMLEFT", INSET, 12)
	panel.searchButton:SetScript("OnClick", function() panel:Search(panel.search:GetText()) end)
	panel.search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		panel:Search(self:GetText())
	end)
	Widgets.Tooltip(panel.searchButton, "Search help", "Finds every guide line and chat command containing "
		.. "your words, for example: goal level.")

	panel.back = Widgets.Button(f, "< Back", 80, 22)
	panel.back:SetPoint("BOTTOMLEFT", BODY_LEFT, 12)
	panel.back:SetScript("OnClick", function() panel:Show(panel.page - 1) end)
	panel.pageLabel = Widgets.Label(f, "GameFontHighlightSmall")
	panel.pageLabel:SetPoint("BOTTOMLEFT", BODY_LEFT + 90, 17)
	panel.next = Widgets.Button(f, "Next >", 80, 22)
	panel.next:SetPoint("BOTTOMLEFT", BODY_LEFT + 160, 12)
	panel.next:SetScript("OnClick", function() panel:Show(panel.page + 1) end)
	panel.close = Widgets.Button(f, "Close guide", 110, 22)
	panel.close:SetPoint("BOTTOMRIGHT", -INSET, 12)
	panel.close:SetScript("OnClick", function() panel:Close() end)
	Widgets.Tooltip(panel.close, "Close guide", "Reopen it any time with the ? button, from Settings, "
		.. "or with /dawnward guide.")

	function panel:Show(page)
		page = math.min(math.max(page or 1, 1), #Guide.TOPICS)
		self.page = page
		local topic = Guide.TOPICS[page]
		self.title:SetText(topic.title)
		self.body:SetText(GuidePanel.TopicText(topic))
		for i, b in ipairs(self.topicButtons) do
			b:SetEnabled(i ~= page)
		end
		self.back:SetEnabled(page > 1)
		self.next:SetText(page < #Guide.TOPICS and "Next >" or "Done")
		self.pageLabel:SetText(string.format("%d of %d", page, #Guide.TOPICS))
		if page == #Guide.TOPICS then
			self.next:SetScript("OnClick", function() panel:Close() end)
		else
			self.next:SetScript("OnClick", function() panel:Show(panel.page + 1) end)
		end
		f:Show()
	end

	function panel:Search(query)
		query = query or ""
		if not query:match("%S") then
			self:Show(self.page)
			return
		end
		self.title:SetText("Search")
		self.body:SetText(GuidePanel.ResultsText(query, Guide.Search(query, ns.Commands.HELP)))
		for _, b in ipairs(self.topicButtons) do
			b:SetEnabled(true)
		end
		f:Show()
	end

	function panel.IsOpen()
		return f:IsShown()
	end

	--- Closes the guide and remembers that this character has seen it.
	function panel:Close()
		self.search:ClearFocus()
		f:Hide()
		Actions.FinishGuide(ns.ctx)
		MainWindow.Refresh()
	end

	function panel:ApplyTheme(theme)
		Widgets.SetColor(self.background, theme.panel)
		Widgets.TextColor(self.title, theme.accent)
		Widgets.TextColor(self.heading, theme.accent)
		Widgets.TextColor(self.body, theme.text)
		Widgets.TextColor(self.pageLabel, theme.muted)
		self.search:SetTextColor(theme.text[1], theme.text[2], theme.text[3])
	end

	GuidePanel.panel = panel
	return panel
end

MainWindow.createGuide = create

--- Opens the guide, opening the journal first if needed.
function GuidePanel.Open(page)
	if not MainWindow.IsShown() then
		MainWindow.Show()
	end
	if GuidePanel.panel then
		GuidePanel.panel:Show(page or 1)
	end
end
