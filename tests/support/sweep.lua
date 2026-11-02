-- Shared helpers for whole-window sweeps (v0.10.1): a character with every
-- kind of record, a walk through every section, tab, full view and side
-- window, and readers for what the mock records (text sizes, colours,
-- visibility). Used by tests/spec/ui_v101_sweep_spec.lua.
local Boot = require("support.boot")

local Sweep = {}

local function click(button)
	button:GetScript("OnClick")(button)
end
Sweep.click = click

local function turnIn(mock, id, title)
	mock.quest = { id = id, title = title, level = 20 }
	mock.Fire("QUEST_COMPLETE")
	mock.Fire("QUEST_TURNED_IN", id, 100, 10)
end

--- A started addon with a character holding every kind of record, a waiting
-- story moment, a draft, findings to review, a visited place and an imported
-- story. opts.theme: the character's theme before the window first opens.
function Sweep.Sample(opts)
	opts = opts or {}
	local mock, env, ns = Boot.Start()
	if opts.theme then ns.Actions.SetTheme(ns.ctx, opts.theme) end
	for _, line in ipairs({
		"set name Aelin Brightwater", "set title Keeper of the Road", "set faith The Light",
		"set homeland Goldshire", "set summary Kind to strangers.", "set motivation To keep the lamps lit.",
		"family add mother Ilsa", "history add Took the oath at the chapel", "fact add belief Mercy first",
		"fact add origin Born in Lordaeron", "personality set courage 14", "journal add A quiet night",
		"memory add The night the river flooded", "memory add The night the river flooded",
		"arc add Finding a home", "goal add Reach the capital", "stance add Stormwind; Loyal; Doubts the king",
		"person add npc Old Tom; Innkeeper in Goldshire", "person feel 1 Owes him a debt",
	}) do
		mock.Slash(line)
	end
	local char = ns.Actions.Character(ns.ctx)
	char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = ns.Places.CleanEntry({
		zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", first = 1, last = 1 })
	ns.StoryImport.Import(ns.ctx, "paste", "Aelin was born in Lordaeron.\n\nShe keeps a lantern lit.", nil, "sentence")
	turnIn(mock, 30, "Draft Quest")
	local answered = char.story.reactions[1]
	mock.Slash("story " .. (answered and answered.id or 1) .. " 1")
	turnIn(mock, 31, "The Defias Brotherhood")
	mock.Slash("")
	return mock, env, ns, char
end

--- An addon with a brand-new character (every empty state).
function Sweep.Empty()
	local mock, env, ns = Boot.Start()
	mock.Slash("")
	return mock, env, ns, ns.Actions.Character(ns.ctx)
end

--- The screens of the main window, in order: { name, open(ns) }. Each open
-- leaves that screen showing; the walk visits them one by one.
function Sweep.Screens()
	local list = {
		{ "Journal", function(ns) ns.MainWindow.Select("journal") end },
		{ "Journal editor", function(ns)
			ns.MainWindow.Select("journal")
			click(ns.JournalView.section.newButton)
		end },
		{ "Character", function(ns)
			local s = ns.JournalView.section
			if s and s.CloseEditor then s:CloseEditor() end
			ns.MainWindow.Select("character")
			local c = ns.CharacterView.section
			if c.showcase and c.showcaseView and c.showcaseView:IsShown() then click(c.showcaseButton) end
		end },
		{ "Character story reader", function(ns)
			ns.MainWindow.Select("character")
			ns.CharacterView.section:OpenReader("story")
		end },
		{ "Character family list", function(ns)
			ns.MainWindow.Select("character")
			ns.CharacterView.section:OpenReader("family")
		end },
		{ "Showcase", function(ns)
			ns.MainWindow.Select("character")
			local c = ns.CharacterView.section
			if c.CloseReader then c:CloseReader() end
			click(c.showcaseButton)
		end },
		{ "Story", function(ns)
			local c = ns.CharacterView.section
			if c.showcaseView and c.showcaseView:IsShown() then click(c.showcaseButton) end
			ns.MainWindow.Select("story")
		end },
	}
	return list
end

--- Chronicle tab ids, in their order.
function Sweep.ChronicleTabs(ns)
	local out = {}
	for _, tab in ipairs(ns.ChronicleView.TABS) do out[#out + 1] = tab.id end
	return out
end

--- Opens Chronicle on tab id.
function Sweep.ChronicleTab(ns, id)
	ns.MainWindow.Select("chronicle")
	for _, b in ipairs(ns.ChronicleView.section.tabButtons) do
		if b.tabId == id then click(b) end
	end
end

--- Visits every screen, calling visit(name) on each.
function Sweep.Walk(ns, visit, opts)
	for _, s in ipairs(Sweep.Screens()) do
		s[2](ns)
		visit(s[1])
	end
	for _, tab in ipairs(ns.ChronicleView.TABS) do
		Sweep.ChronicleTab(ns, tab.id)
		visit("Chronicle > " .. tab.id)
		local section = ns.ChronicleView.section
		if tab.new then
			click(section.new)
			visit("Chronicle > " .. tab.id .. " > " .. tab.new)
			if section.form:IsOpen() then click(section.form.cancel) end
		end
	end
	-- The reaction card on the waiting moment.
	local char = ns.Actions.Character(ns.ctx)
	local waiting
	for _, r in ipairs(char and char.story.reactions or {}) do
		if r.status == "pending" then waiting = waiting or r end
	end
	if waiting then
		ns.ReactionCard.Show(waiting.id)
		visit("Reaction card")
		ns.ReactionCard.Hide()
	end
	-- A confirmation dialog.
	ns.MainWindow.Select("journal")
	if char and char.journal[1] then
		ns.JournalView.section:ConfirmDelete(char.journal[1])
		visit("Confirm dialog")
		ns.Widgets.dialog:Hide()
	end
	for _, page in ipairs(ns.SettingsPanel.PAGES) do
		ns.SettingsPanel.OpenPage(page.id)
		visit("Settings > " .. page.id)
	end
	ns.MainWindow.Select("journal")
	ns.GuidePanel.Open(1)
	for i = 1, #ns.Guide.TOPICS do
		ns.GuidePanel.panel:Show(i)
		visit("Guide " .. i)
	end
	ns.GuidePanel.panel:Close()
	ns.ImportWizard.Open({})
	visit("Import story")
	ns.ImportWizard.Close()
	if not opts or not opts.noWizard then
		ns.SetupWizard.Open({})
		for i = 1, #ns.Onboarding.PAGES do
			ns.SetupWizard.Go(i)
			visit("Setup " .. i)
		end
		ns.SetupWizard.Close()
	end
end

--- The font size a font string shows (UI units), or nil with the reason.
function Sweep.TextSize(ns, fs)
	if fs.__font and fs.__font.height then return fs.__font.height end
	local obj = fs.__fontObject
	if obj then
		if obj.__font and obj.__font.height then return obj.__font.height end
		local spec = Sweep.FontByName(ns)[obj.__name]
		if spec then return spec.size end
	end
	local spec = Sweep.FontByName(ns)[fs.__template]
	if spec then return spec.size end
	return nil, "game template " .. tostring(fs.__template)
end

function Sweep.FontByName(ns)
	local out = {}
	for _, f in ipairs(ns.Style.FONTS) do out[f.name] = f end
	return out
end

--- Every visible font string with text.
function Sweep.VisibleText(mock)
	local out = {}
	for _, f in ipairs(mock.allFrames) do
		if f.__kind == "FontString" and f:IsVisible() and type(f.__text) == "string" and f.__text ~= "" then
			out[#out + 1] = f
		end
	end
	return out
end

--- Every colour the mock recorded, by creation index, for visible regions.
function Sweep.Colours(mock)
	local out = {}
	for i, f in ipairs(mock.allFrames) do
		if (f.__kind == "Texture" or f.__kind == "FontString" or f.__kind == "Line") and f:IsVisible() then
			out[i] = { kind = f.__kind, color = f.__color, vertex = f.__vertex, text = f.__textColor,
				label = f.__text }
		end
	end
	return out
end

return Sweep
