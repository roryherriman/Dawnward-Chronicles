-- Chronicle section: the character's narrative records in the window.
--
--   Memories, Arcs, Goals, Stances, People   lists with each record's
--       provenance, canon status and visibility, and buttons to accept a
--       suggestion, change visibility, dispute or remove it
--   Review                                   continuity findings, answered
--       as growth / unreliable / secret / correction / ignore
--
-- A line at the bottom adds a record in the player's own words. Every
-- button calls the same core functions as the chat commands, through
-- Actions.WithCharacter (read-only data refused).
local _, ns = ...
local Widgets, MainWindow, Actions, Records = ns.Widgets, ns.MainWindow, ns.Actions, ns.Records

local ChronicleView = {}
ns.ChronicleView = ChronicleView

ChronicleView.ROWS = 8
ChronicleView.TABS = {
	{ id = "memories", label = "Memories", module = "Memories", add = "Add memory" },
	{ id = "arcs", label = "Arcs", module = "Arcs", add = "Add arc" },
	{ id = "goals", label = "Goals", module = "Goals", add = "Add goal" },
	{ id = "identity", label = "Stances", module = "Identity" },
	{ id = "people", label = "People", module = "People" },
	{ id = "review", label = "Review" },
}
ChronicleView.REVIEW_CHOICES = { "growth", "unreliable", "secret", "correction", "ignore" }

local INSET = 8
local WIDTH = 560
local ROW_HEIGHT = 34

--- One-line text for a record. Pure: used by tests.
function ChronicleView.RecordText(listId, r, char)
	local body
	if listId == "memories" then
		body = (r.title and (r.title .. ": ") or "") .. (r.text or "")
	elseif listId == "arcs" then
		body = string.format("%s (%s, %s)", r.title, r.kind, r.state)
	elseif listId == "goals" then
		local p = ns.Goals.Progress(char, r)
		body = string.format("%s (%s, %d/%d milestones%s)", r.title, r.state, p.milestonesDone, p.milestonesTotal,
			p.objective and string.format(", level %s/%d", tostring(p.objective.current or "?"), p.objective.target) or "")
	elseif listId == "identity" then
		body = string.format("%s - in public: %s / privately (%s): %s", r.subject, r.persona or "-",
			r.convictionVisibility, r.conviction or "-")
	elseif listId == "people" then
		body = string.format("%s%s (%s)%s", r.name, r.realm and ("-" .. r.realm) or "", r.kind,
			r.relation and (": " .. r.relation) or "")
	end
	return body or "", Records.Label(r)
end

local CYCLE = { private = "public", public = "secret", secret = "private" }

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), tab = "memories", rows = {}, tabButtons = {} }
	local f = section.frame

	local function act(fn)
		local _, message = Actions.WithCharacter(ns.ctx, function(char)
			local r, err = fn(char, ns.ctx.now())
			if not r then return Actions.Fail(err) end
			return r, "Saved."
		end)
		MainWindow.SetStatus(message)
		MainWindow.Refresh()
	end

	for i, tab in ipairs(ChronicleView.TABS) do
		local b = Widgets.Button(f, tab.label, 88, 22)
		b:SetPoint("TOPLEFT", INSET + (i - 1) * 92, -6)
		b:SetScript("OnClick", function() section.tab = tab.id; MainWindow.Refresh() end)
		b.tabId = tab.id
		section.tabButtons[i] = b
	end

	section.empty = Widgets.Label(f, "GameFontHighlight", true)
	section.empty:SetPoint("TOPLEFT", INSET, -44)
	section.empty:SetWidth(WIDTH)

	for i = 1, ChronicleView.ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(WIDTH, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", INSET, -36 - (i - 1) * ROW_HEIGHT)
		row.text = Widgets.Label(row, "GameFontHighlightSmall")
		row.text:SetPoint("TOPLEFT", 0, -2)
		row.text:SetWidth(WIDTH - 250)
		row.meta = Widgets.Label(row, "GameFontHighlightSmall")
		row.meta:SetPoint("TOPLEFT", 0, -17)
		row.meta:SetWidth(WIDTH - 250)
		row.buttons = {}
		for b = 1, 5 do
			local button = Widgets.Button(row, "", 60, 20)
			button:SetPoint("TOPRIGHT", -(b - 1) * 62, -4)
			row.buttons[b] = button
		end
		section.rows[i] = row
	end

	section.input = Widgets.EditLine(f, 300)
	section.input:SetPoint("BOTTOMLEFT", INSET + 6, 10)
	section.input:SetWidth(WIDTH - 120)
	section.add = Widgets.Button(f, "Add", 100, 22)
	section.add:SetPoint("BOTTOMRIGHT", -INSET, 8)
	section.add:SetScript("OnClick", function()
		local text = section.input:GetText()
		section.input:SetText("")
		section.input:ClearFocus()
		act(function(char, now)
			if section.tab == "memories" then return ns.Memories.Add(char, { text = text }, "player", now) end
			if section.tab == "arcs" then return ns.Arcs.Add(char, { title = text }, "player", now) end
			if section.tab == "goals" then return ns.Goals.Add(char, { title = text }, now) end
			return nil, "add these from chat: /dawnward stance add or /dawnward person add"
		end)
	end)

	local function setButton(button, label, fn)
		button:SetShown(label ~= nil)
		if label then
			button:SetText(label)
			button:SetScript("OnClick", fn)
		end
	end

	local function recordButtons(row, listId, mod, r)
		local m = ns[mod]
		setButton(row.buttons[1], (r.status == "proposed" or r.status == "disputed") and m.Accept and "Accept" or nil,
			function() act(function(char, now) return m.Accept(char, r.id, now) end) end)
		setButton(row.buttons[2], ns.Themes.VISIBILITY_LABELS[r.visibility] or r.visibility,
			function() act(function(char, now) return m.SetVisibility(char, r.id, CYCLE[r.visibility], now) end) end)
		setButton(row.buttons[3], r.status == "established" and m.Dispute and "Dispute" or nil,
			function() act(function(char, now) return m.Dispute(char, r.id, now) end) end)
		local removable = r.provenance == "player" or r.status == "proposed"
		setButton(row.buttons[4], removable and "Remove" or nil, function()
			Widgets.Confirm("Remove this record?", "Remove", function()
				act(function(char) return m.Remove(char, r.id) end)
			end)
		end)
		setButton(row.buttons[5], nil)
		if listId == "identity" then
			setButton(row.buttons[5], "Private: " .. r.convictionVisibility:sub(1, 3), function()
				act(function(char, now) return ns.Identity.SetConvictionVisibility(char, r.id,
					CYCLE[r.convictionVisibility], now) end)
			end)
		end
	end

	function section:ApplyTheme(theme)
		self.theme = theme
		Widgets.TextColor(self.empty, theme.muted)
		for _, row in ipairs(self.rows) do
			Widgets.TextColor(row.text, theme.text)
			Widgets.TextColor(row.meta, theme.muted)
		end
	end

	function section:Refresh(view)
		local char = view.char
		for _, b in ipairs(self.tabButtons) do
			b:SetEnabled(b.tabId ~= self.tab)
		end
		local spec
		for _, tab in ipairs(ChronicleView.TABS) do
			if tab.id == self.tab then spec = tab end
		end
		self.input:SetShown(spec.add ~= nil)
		self.add:SetShown(spec.add ~= nil)
		if spec.add then self.add:SetText(spec.add) end
		local items = {}
		if char and self.tab == "review" then
			items = ns.Continuity.Findings(char)
		elseif char then
			local list = char.story[self.tab] or {}
			for i = #list, 1, -1 do items[#items + 1] = list[i] end
		end
		self.empty:SetShown(#items == 0)
		self.empty:SetText(self.tab == "review" and "Nothing to review: your story is consistent as far as "
			.. "Dawnward can tell." or "Nothing here yet.")
		for i, row in ipairs(self.rows) do
			local item = items[i]
			row:SetShown(item ~= nil)
			if item and self.tab == "review" then
				row.text:SetText(item.message)
				row.meta:SetText("What is it?")
				for b, choice in ipairs(ChronicleView.REVIEW_CHOICES) do
					setButton(row.buttons[b], choice, function()
						act(function(c, now) return ns.Continuity.Review(c, item.key, choice, nil, now) end)
					end)
				end
			elseif item then
				local text, meta = ChronicleView.RecordText(self.tab, item, char)
				row.text:SetText(text)
				row.meta:SetText(meta)
				recordButtons(row, self.tab, spec.module, item)
			end
		end
	end

	ChronicleView.section = section
	return section
end

MainWindow.RegisterSection({ id = "chronicle", label = "Chronicle", order = 4, create = create })
