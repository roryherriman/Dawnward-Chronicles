-- Story section: the living chronicle in the journal window.
--
--   summary      what is waiting, and the next suggested step
--   reaction     one waiting reaction at a time: its question, its answers,
--                "in your own words", and Later / Not now / Dismiss
--   development  personality changes waiting for approval
--
-- Every button calls the same Actions as /dawnward story and develop.
-- Nothing here changes the character without a click.
local _, ns = ...
local Widgets, MainWindow, Actions, Reactions, Evolution, Journal =
	ns.Widgets, ns.MainWindow, ns.Actions, ns.Reactions, ns.Evolution, ns.Journal

local StoryView = {}
ns.StoryView = StoryView

StoryView.HEADING = "Your story is still being written"
StoryView.BODY = "When something worth remembering happens on your adventures, a quiet question "
	.. "will wait for you here: how did it affect your character?\n\n"
	.. "Your answers shape their personality only when you approve it, and become private journal drafts "
	.. "you can edit, approve and choose to share. Nothing changes your character without you."
StoryView.MAX_OPTIONS = 7
StoryView.MAX_CHANGES = 2

local INSET = 8
local WIDTH = 540
local OPTION_HEIGHT = 22
local OPTION_STEP = 24
local OPTIONS_TOP = -108

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
		next = "review the personality changes below"
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
	return table.concat(parts, "  -  ")
end

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), index = 1, optionButtons = {}, changeRows = {} }
	local f = section.frame

	local function act(fn, ...)
		local _, message = fn(ns.ctx, ...)
		MainWindow.SetStatus(message)
		MainWindow.Refresh()
	end

	section.summary = Widgets.Label(f, "GameFontHighlightSmall", true, "muted")
	section.summary:SetPoint("TOPLEFT", INSET, -6)
	section.summary:SetWidth(WIDTH - 90)

	-- Reflection (#29): bring back everything kept for later.
	section.reflect = Widgets.Button(f, "Reflect", 80, 20, "ghost")
	section.reflect:SetPoint("TOPRIGHT", -INSET, -4)
	section.reflect:SetScript("OnClick", function()
		ns.Commands.Execute(ns.ctx, "reflect")
		MainWindow.Refresh()
	end)
	Widgets.Tooltip(section.reflect, "Reflect", "Bring back the moments you kept for later. Nothing has to change.")

	-- Navigation between waiting reactions.
	section.prev = Widgets.Button(f, "<", 28, 20, "ghost")
	section.prev:SetPoint("TOPLEFT", INSET, -40)
	section.position = Widgets.Label(f, "GameFontNormal", false, "muted")
	section.position:SetPoint("LEFT", section.prev, "RIGHT", 8, 0)
	section.next = Widgets.Button(f, ">", 28, 20, "ghost")
	section.next:SetPoint("LEFT", section.position, "RIGHT", 8, 0)
	section.prev:SetScript("OnClick", function() section.index = section.index - 1; MainWindow.Refresh() end)
	section.next:SetScript("OnClick", function() section.index = section.index + 1; MainWindow.Refresh() end)

	section.question = Widgets.Label(f, "GameFontNormal", true, "heading")
	section.question:SetPoint("TOPLEFT", INSET, -66)
	section.question:SetWidth(WIDTH)
	section.context = Widgets.Label(f, "GameFontHighlightSmall", true, "muted")
	section.context:SetPoint("TOPLEFT", section.question, "BOTTOMLEFT", 0, -2)
	section.context:SetWidth(WIDTH)

	for i = 1, StoryView.MAX_OPTIONS do
		local button = Widgets.Button(f, "", WIDTH, OPTION_HEIGHT, "choice")
		button:SetPoint("TOPLEFT", INSET, OPTIONS_TOP - (i - 1) * OPTION_STEP)
		button:SetScript("OnClick", function(self)
			act(Actions.Decide, section.reactionId, { optionId = self.optionId })
		end)
		section.optionButtons[i] = button
	end

	local customTop = OPTIONS_TOP - StoryView.MAX_OPTIONS * OPTION_STEP - 6
	section.customLabel = Widgets.Label(f, "GameFontHighlightSmall", false, "muted")
	section.customLabel:SetPoint("TOPLEFT", INSET, customTop)
	section.customLabel:SetText("Or in your own words:")
	section.custom = Widgets.EditLine(f, 300)
	section.custom:SetPoint("TOPLEFT", INSET + 130, customTop + 4)
	section.custom:SetWidth(320)
	section.save = Widgets.Button(f, "Save answer", 96, 22, "primary")
	section.save:SetPoint("LEFT", section.custom, "RIGHT", 6, 0)
	section.save:SetScript("OnClick", function()
		local text = section.custom:GetText()
		section.custom:SetText("")
		section.custom:ClearFocus()
		act(Actions.Decide, section.reactionId, { custom = text })
	end)

	local controlsTop = customTop - 28
	section.later = Widgets.Button(f, "Later", 80, 22, "ghost")
	section.later:SetPoint("TOPLEFT", INSET, controlsTop)
	section.later:SetScript("OnClick", function() act(Actions.PostponeReaction, section.reactionId) end)
	Widgets.Tooltip(section.later, "Later", "Keep it here for later. You will not be reminded again.")
	section.notNow = Widgets.Button(f, "Not now", 80, 22, "ghost")
	section.notNow:SetPoint("LEFT", section.later, "RIGHT", 6, 0)
	section.notNow:SetScript("OnClick", function() act(Actions.IgnoreReaction, section.reactionId) end)
	Widgets.Tooltip(section.notNow, "Not now", "Leave it waiting quietly, without reminders.")
	section.dismiss = Widgets.Button(f, "Dismiss", 80, 22, "danger")
	section.dismiss:SetPoint("LEFT", section.notNow, "RIGHT", 6, 0)
	section.dismiss:SetScript("OnClick", function() act(Actions.DismissReaction, section.reactionId) end)
	Widgets.Tooltip(section.dismiss, "Dismiss", "Never ask about this. The event stays in your record.")

	-- Empty state.
	section.heading = Widgets.Label(f, "GameFontNormalLarge", true, "title")
	section.heading:SetJustifyH("CENTER")
	section.heading:SetPoint("TOP", 0, -60)
	section.heading:SetWidth(440)
	section.heading:SetText(StoryView.HEADING)
	section.body = Widgets.Label(f, "GameFontHighlight", true, "body")
	section.body:SetJustifyH("CENTER")
	section.body:SetPoint("TOP", section.heading, "BOTTOM", 0, -14)
	section.body:SetWidth(440)
	section.body:SetText(StoryView.BODY)

	-- Development: changes waiting for approval.
	local devTop = controlsTop - 34
	section.devHeading = Widgets.Label(f, "GameFontNormal", false, "heading")
	section.devHeading:SetPoint("TOPLEFT", INSET, devTop)
	for i = 1, StoryView.MAX_CHANGES do
		-- Each change is its own entry row, its Approve and Reject inside it.
		local row = Widgets.EntryRow(f)
		-- (a 4px gap here: the section has no room for more below its controls)
		row:SetSize(WIDTH, 22)
		row:SetPoint("TOPLEFT", INSET, devTop - 18 - (i - 1) * 26)
		row.label = Widgets.Label(row, "GameFontHighlightSmall", false, "small")
		row.label:SetPoint("LEFT", Widgets.ENTRY.pad, 0)
		row.label:SetWidth(WIDTH - 170 - Widgets.ENTRY.pad)
		row.reject = Widgets.Button(row, "Reject", 70, 20, "ghost")
		row.reject:SetPoint("RIGHT", -(Widgets.ENTRY.pad - 6), 0)
		row.reject:SetScript("OnClick", function() act(Actions.RejectChange, row.changeId) end)
		row.approve = Widgets.Button(row, "Approve", 80, 20, "primary")
		row.approve:SetPoint("RIGHT", row.reject, "LEFT", -4, 0)
		row.approve:SetScript("OnClick", function() act(Actions.ApplyChange, row.changeId) end)
		section.changeRows[i] = row
	end

	local reactionWidgets = { section.prev, section.position, section.next, section.question, section.context,
		section.customLabel, section.custom, section.save, section.later, section.notNow, section.dismiss }

	-- Every label and control paints itself (UI/Style.lua).
	function section:ApplyTheme(theme)
		self.theme = theme
	end

	--- Selects a reaction by ID (from the reaction card).
	function section:Focus(reactionId)
		self.focusId = reactionId
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
		self.reactionId = reaction and reaction.id
		local hasReaction = presentation ~= nil
		for _, w in ipairs(reactionWidgets) do
			w:SetShown(hasReaction)
		end
		self.heading:SetShown(not hasReaction)
		self.body:SetShown(not hasReaction)
		if hasReaction then
			self.position:SetText(string.format("Moment %d of %d%s", self.index, #list,
				reaction.status == "postponed" and " (kept for later)" or ""))
			self.prev:SetEnabled(self.index > 1)
			self.next:SetEnabled(self.index < #list)
			self.question:SetText(presentation.question)
			self.context:SetText(StoryView.ContextText(presentation))
		end
		for i, button in ipairs(self.optionButtons) do
			local option = hasReaction and presentation.options[i]
			button:SetShown(option and true or false)
			if option then
				button.optionId = option.id
				button:SetText(option.text)
			end
		end
		local pending = char and Evolution.Pending(char) or {}
		self.devHeading:SetShown(#pending > 0)
		self.devHeading:SetText(string.format("Personality changes waiting for you (%d)%s", #pending,
			#pending > StoryView.MAX_CHANGES and " - more: /dawnward develop" or ""))
		for i, row in ipairs(self.changeRows) do
			local change = pending[i]
			row:SetShown(change ~= nil)
			if change then
				row.changeId = change.id
				row.label:SetText(Evolution.Describe(change) .. (change.reason and (" - " .. change.reason) or ""))
			end
		end
	end

	StoryView.section = section
	return section
end

MainWindow.RegisterSection({ id = "story", label = "Story", order = 3, create = create })
