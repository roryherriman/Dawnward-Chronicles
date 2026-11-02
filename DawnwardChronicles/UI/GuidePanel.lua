-- The guide panel (#51): contextual help over the journal's content area,
-- a short tour plus a searchable reference. It opens from the "?" button,
-- Settings or /dawnward guide, never by itself: since v0.6 the first-time
-- setup wizard (UI/SetupWizard.lua) welcomes new characters.
-- v0.10.1: the design system's control sizes, a scrolling reading column
-- (long topics and search results are never cut off) and plain Back / Next.
local _, ns = ...
local Style, Widgets, MainWindow, Guide = ns.Style, ns.Widgets, ns.MainWindow, ns.Guide

local GuidePanel = {}
ns.GuidePanel = GuidePanel

-- Layout (v0.10.1): the design system's sizes. A topic list on the left
-- (30 px items, the selected one raised as in a segmented control), search
-- under it, and the topic in a scrolling reading column with a slim bar, so
-- a long topic or a long list of search results is never cut off. The
-- pager (Back, "2 of 9", Next) and Close guide sit on one row at the foot.
local L = {
	inset = 12, listW = 150, gap = 24, topicH = Style.CONTROL.compact, topicGap = 4, eyebrowTop = 12,
	listTop = 40, buttonH = Style.CONTROL.compact, foot = 12, searchH = Style.CONTROL.compact,
	titleH = 26, titleGap = 10, bar = 14,
}
L.bodyLeft = L.inset + L.listW + L.gap
GuidePanel.LAYOUT = L

--- Body text for a topic, or for search results. Pure.
function GuidePanel.TopicText(topic)
	return table.concat(topic.lines, "\n\n")
end

function GuidePanel.ResultsText(query, results)
	if #results == 0 then
		return string.format("Nothing matches '%s'. Try a single word, such as goal, profile or minimap.", query)
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
	-- The wheel over the guide never reaches the camera.
	Widgets.SwallowWheel(f)
	f:Hide()
	panel.frame = f
	panel.background = Style.Fill(f, "panel", "BACKGROUND")
	panel.background:SetAllPoints(f)
	local width, height = MainWindow.ContentWidth(), MainWindow.ContentHeight()
	L.bodyW = width - L.bodyLeft - L.inset - L.bar
	L.viewH = height - L.foot - L.buttonH - 12 - L.inset
	panel.rule = Widgets.Divider(f)
	panel.rule:SetPoint("TOPLEFT", L.bodyLeft - L.gap / 2, -L.inset)
	panel.rule:SetPoint("BOTTOMLEFT", L.bodyLeft - L.gap / 2, L.inset)
	panel.rule:SetWidth(1)

	local heading = Widgets.TrackedLabel(f, "eyebrow", "eyebrow")
	heading:SetPoint("TOPLEFT", L.inset, -L.eyebrowTop)
	heading:SetText("GUIDE")
	panel.heading = heading
	for i, topic in ipairs(Guide.TOPICS) do
		local b = Widgets.Button(f, topic.title, L.listW, L.topicH, "segment")
		b:SetPoint("TOPLEFT", L.inset, -L.listTop - (i - 1) * (L.topicH + L.topicGap))
		b.label:SetJustifyH("LEFT")
		b:SetScript("OnClick", function() panel:Show(i) end)
		panel.topicButtons[i] = b
	end

	-- Search: the design's search field over a ghost Search button.
	panel.search = Widgets.SearchBox(f, L.listW, "Search help", nil, L.searchH)
	panel.search:SetPoint("BOTTOMLEFT", L.inset, L.foot + L.buttonH + 8)
	panel.searchButton = Widgets.Button(f, "Search", L.listW, L.buttonH, "ghost")
	panel.searchButton:SetPoint("BOTTOMLEFT", L.inset, L.foot)
	panel.searchButton:SetScript("OnClick", function() panel:Search(panel.search:GetText()) end)
	panel.search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		panel:Search(self:GetText())
	end)
	Widgets.Tooltip(panel.searchButton, "Search help", "Finds every guide line and chat command containing "
		.. "your words, for example: goal level.")

	-- The reading column: title and text in a scroll frame.
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("DawnwardGuideScroll"), f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", L.bodyLeft, -L.inset)
	scroll:SetSize(L.bodyW, L.viewH)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(L.bodyW, 1)
	scroll:SetScrollChild(child)
	panel.scroll, panel.child = scroll, child
	panel.bar = Widgets.SlimScrollBar(scroll, math.floor((L.bar - Widgets.SLIM_BAR.width) / 2))
	Widgets.WheelScroll(scroll)
	panel.title = Widgets.Label(child, "title", false, "title")
	panel.title:SetPoint("TOPLEFT", 0, 0)
	panel.title:SetWidth(L.bodyW)
	panel.body = Widgets.Label(child, "reading", true, "reading")
	panel.body:SetPoint("TOPLEFT", 0, -(L.titleH + L.titleGap))
	panel.body:SetWidth(L.bodyW)

	panel.back = Widgets.Button(f, "Back", Widgets.ButtonWidth("Back", L.buttonH), L.buttonH, "ghost")
	panel.back:SetPoint("BOTTOMLEFT", L.bodyLeft, L.foot)
	panel.back:SetScript("OnClick", function() panel:Show(panel.page - 1) end)
	panel.pageLabel = Widgets.Label(f, "small", false, "muted")
	panel.pageLabel:SetPoint("LEFT", panel.back, "RIGHT", 12, 0)
	local nextW = math.max(Widgets.ButtonWidth("Next", L.buttonH), Widgets.ButtonWidth("Done", L.buttonH))
	panel.next = Widgets.Button(f, "Next", nextW, L.buttonH, "primary")
	panel.next:SetPoint("BOTTOMLEFT", L.bodyLeft + panel.back:GetWidth() + 12
		+ math.ceil(Style.TextWidth("10 of 10", "small")) + 12, L.foot)
	panel.next:SetScript("OnClick", function() panel:Show(panel.page + 1) end)
	panel.close = Widgets.Button(f, "Close guide", Widgets.ButtonWidth("Close guide", L.buttonH), L.buttonH)
	panel.close:SetPoint("BOTTOMRIGHT", -L.inset, L.foot)
	panel.close:SetScript("OnClick", function() panel:Close() end)
	Widgets.Tooltip(panel.close, "Close guide", "Reopen it any time with the ? button, from Settings, "
		.. "or with /dawnward guide.")

	-- Sets the reading column and starts it at the top; the child is as tall
	-- as the text (estimated from the font's advance widths, never less than
	-- the client's own measurement), so the slim bar shows only when needed.
	local function setText(title, text)
		panel.title:SetText(title)
		panel.body:SetText(text)
		local reading = Style.FONT_BY_STYLE.reading
		local lines = ns.StoryView.WrapLines(text, "reading", reading.size, L.bodyW)
		local h = ns.StoryView.TextHeight(lines, reading.size, reading.spacing or 0)
		local measured = panel.body.GetStringHeight and panel.body:GetStringHeight()
		if type(measured) == "number" then h = math.max(h, measured) end
		panel.body:SetHeight(h)
		child:SetHeight(math.max(1, L.titleH + L.titleGap + h + 8))
		if panel.bar then panel.bar.UpdateThumb() end
		Widgets.ScrollTo(scroll, 0)
	end
	panel.SetText = setText

	function panel:Show(page)
		page = math.min(math.max(page or 1, 1), #Guide.TOPICS)
		self.page = page
		local topic = Guide.TOPICS[page]
		setText(topic.title, GuidePanel.TopicText(topic))
		for i, b in ipairs(self.topicButtons) do
			b:SetSelected(i == page)
		end
		self.back:SetEnabled(page > 1)
		self.next:SetText(page < #Guide.TOPICS and "Next" or "Done")
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
		setText("Search", GuidePanel.ResultsText(query, Guide.Search(query, ns.Commands.HELP)))
		for _, b in ipairs(self.topicButtons) do
			b:SetSelected(false)
		end
		f:Show()
	end

	function panel.IsOpen()
		return f:IsShown()
	end

	--- Closes the guide. It is contextual help only (v0.6): closing it saves
	-- nothing; first-time setup is the wizard's job (UI/SetupWizard.lua).
	function panel:Close()
		self.search:ClearFocus()
		f:Hide()
		MainWindow.Refresh()
	end

	-- Every part paints itself (UI/Style.lua).
	function panel.ApplyTheme() end

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
