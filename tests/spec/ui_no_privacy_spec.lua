-- L2 (v0.10): no screen of the normal Dawnward experience shows a Public /
-- Private / Secret classification any more. The whole profile publishes once
-- Total RP 3 is connected (Core/Publication.lua), so the words survive only
-- where they are not about privacy (whitelisted below with the reason).
--
-- The sweep opens every section, tab, form, full view and dialog of the main
-- window, the story import window and the guide, with a character that has
-- every kind of record and legacy visibility values of every level, and
-- reads every visible font string, button label and tooltip.
--
-- Settings > Total RP 3 and the setup wizard: ui_no_privacy_trp3_spec.lua.
local Loader = require("support.loader")
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"
local WORDS = { "Public", "Private", "Secret", "Secrets" }

-- Allowed non-privacy uses: { pattern (plain text), why }. Empty on purpose:
-- add an entry only with its reason.
local ALLOWED = {}

local function click(button)
	button:GetScript("OnClick")(button)
end

local function turnIn(mock, id, title)
	mock.quest = { id = id, title = title, level = 20 }
	mock.Fire("QUEST_COMPLETE")
	mock.Fire("QUEST_TURNED_IN", id, 100, 10)
end

-- Every visible text: font strings and frames with text (buttons, labels),
-- and the tooltips of visible frames. Edit boxes hold the player's own text.
local function visibleTexts(mock)
	local out = {}
	for _, f in ipairs(mock.allFrames) do
		if f.__kind ~= "EditBox" and f.__kind ~= "Texture" and f:IsVisible() then
			for _, text in ipairs({ f.__text, f.tooltipTitle, f.tooltipText }) do
				if type(text) == "string" and text ~= "" then out[#out + 1] = text end
			end
		end
	end
	return out
end

local function allowed(text)
	for _, a in ipairs(ALLOWED) do
		if text:find(a[1], 1, true) then return true end
	end
	return false
end

-- The privacy words found on screen (whole words, case as shown).
local function hits(mock)
	local found = {}
	for _, text in ipairs(visibleTexts(mock)) do
		for _, word in ipairs(WORDS) do
			if text:find("%f[%a]" .. word .. "%f[%A]") and not allowed(text) then
				found[#found + 1] = word .. " in: " .. text
			end
		end
	end
	return found
end

-- A character with every kind of record, legacy visibility values of every
-- level, a waiting story moment, a draft, findings to review, a visited
-- place and an imported story waiting for review.
local function sample()
	local mock, env, ns = Boot.Start()
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
	for _, line in ipairs({ "vis name public", "vis faith secret", "vis summary public", "family vis 1 public",
		"history vis 1 secret", "fact vis 1 public", "fact vis 2 secret", "personality vis courage public",
		"journal vis 1 secret", "memory vis 1 secret", "stance private 1 secret", "biography secret" }) do
		mock.Vis(line)
	end
	local char = env.DawnwardChroniclesDB.characters[CHAR]
	char.story.places[ns.Places.Key("Elwynn Forest", "Goldshire")] = ns.Places.CleanEntry({
		zone = "Elwynn Forest", subzone = "Goldshire", kind = "town", first = 1, last = 1 })
	ns.StoryImport.Import(ns.ctx, "paste", "Aelin was born in Lordaeron. She keeps a lantern lit.", nil, "sentence")
	-- One moment answered (a draft and a waiting personality change), one waiting.
	turnIn(mock, 30, "Draft Quest")
	local answered = char.story.reactions[1]
	mock.Slash("story " .. (answered and answered.id or 1) .. " 1")
	turnIn(mock, 31, "The Defias Brotherhood")
	mock.Slash("")
	return mock, env, ns, char
end

local function legacySpec(t, expect)
	t:describe("no Public / Private / Secret on any screen (v0.10, L2)", function()
		local mock, ns, char
		local function check(where)
			local found = hits(mock)
			expect.equal(#found, 0, where .. ": " .. table.concat(found, " | "))
		end

		t:it("builds a character with every kind of record and old visibility values", function()
			local _
			mock, _, ns, char = sample()
			expect.equal(ns.Publication.Status(char), "pending")
			expect.truthy(#char.story.memories >= 2, "two alike, for a duplicate finding")
			expect.equal(#char.story.identity, 1)
			expect.truthy(#char.journal >= 2, "notes and a draft")
			expect.truthy(#ns.Continuity.Findings(char) > 0, "something to review")
			expect.equal(char.fields.faith.visibility, "secret", "legacy values kept")
		end)

		t:it("Journal: dashboard, a draft card and the editor", function()
			ns.MainWindow.Select("journal")
			check("Journal")
			local section = ns.JournalView.section
			click(section.newButton)
			check("Journal editor (new)")
			section:CloseEditor()
			section:OpenEditor(char.journal[1])
			check("Journal editor (edit)")
			section:CloseEditor()
			-- The delete confirmation.
			section:ConfirmDelete(char.journal[#char.journal])
			check("Journal delete dialog")
			ns.Widgets.dialog:Hide()
		end)

		t:it("Story: the waiting moment and the settings", function()
			ns.MainWindow.Select("story")
			expect.truthy(ns.StoryView.section.card:IsVisible(), "the waiting moment's card is on screen")
			check("Story")
		end)

		t:it("Character: profile with the publish callout, its dialog, editors and forms, showcase", function()
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			expect.truthy(section.callout:IsShown(), "the one-time callout is the only publish wording")
			check("Character profile")
			click(section.callout.button)
			check("Publish whole profile dialog")
			ns.Widgets.dialog:Hide()
			for i, spec in ipairs(section.specs) do
				if spec.kind == "field" and spec.field.key == "faith" then click(section.rows[i].edit) end
			end
			check("Field editor")
			section.CloseEditor()
			for i, spec in ipairs(section.specs) do
				if spec.kind == "item" and spec.list == "family" then click(section.rows[i].edit) end
			end
			check("Family form")
			click(section.form.cancel)
			for i, spec in ipairs(section.specs) do
				if spec.kind == "add" and spec.list == "history" then click(section.rows[i].edit) end
			end
			check("History form")
			click(section.form.cancel)
			section:OpenAxisForm(ns.Schema.PERSONALITY_AXES[1])
			check("Personality axis form")
			click(section.form.cancel)
			click(section.showcaseButton)
			check("Showcase")
			click(section.showcaseButton)
			-- Once confirmed, the callout is gone and the page is the same.
			mock.Slash("publish confirm")
			ns.MainWindow.Refresh()
			expect.falsy(section.callout:IsShown())
			check("Character profile (whole profile published)")
			mock.Slash("publish undo")
		end)

		t:it("Chronicle: every tab, its New form, a full view, Review, examine and answered", function()
			ns.MainWindow.Select("chronicle")
			local section = ns.ChronicleView.section
			for _, tab in ipairs(ns.ChronicleView.TABS) do
				for _, b in ipairs(section.tabButtons) do
					if b.tabId == tab.id then click(b) end
				end
				check("Chronicle > " .. tab.label)
				if tab.new then
					click(section.new)
					check("Chronicle > " .. tab.label .. " > " .. tab.new)
					click(section.form.cancel)
				end
				if tab.id ~= "review" and tab.id ~= "places" and section.rows[1]:IsShown() then
					local key = ns.ChronicleView.ItemKey(section.rows[1].item or char.story[tab.id][1])
					section.detailKey = key
					ns.MainWindow.Refresh()
					expect.truthy(section.detail:IsShown(), tab.label .. ": the full view is open")
					check("Chronicle > " .. tab.label .. " > full view")
					section.detailKey = nil
					ns.MainWindow.Refresh()
					-- Edit form of an existing record.
					for _, b in ipairs(section.rows[1].buttons) do
						if b:IsShown() and b:GetText() == "Edit" then click(b) break end
					end
					check("Chronicle > " .. tab.label .. " > Edit")
					if section.form:IsOpen() then click(section.form.cancel) end
				end
			end
			-- Review: examine the first finding, explain, then the answered list.
			local row = section.rows[1]
			expect.truthy(row:IsShown() and row.examine:IsShown(), "a finding to examine")
			click(row.examine)
			expect.equal(section.reviewMode, "examine")
			check("Review > examine")
			for _, b in ipairs(section.rows[#section.rows].buttons or {}) do
				if b:IsShown() and b:GetText() == "Explain..." then click(b) end
			end
			check("Review > explain form")
			if section.form:IsOpen() then click(section.form.cancel) end
			section.reviewMode, section.examineKey = "open", nil
			ns.MainWindow.Refresh()
			for _, b in ipairs(section.rows[1].buttons) do
				if b:IsShown() and b.actionId == "secret" then click(b) break end
			end
			expect.truthy(#ns.Continuity.Answered(char) > 0, "one finding answered Intended")
			section.reviewMode = "answered"
			ns.MainWindow.Refresh()
			expect.truthy(section.rows[1]:IsShown())
			check("Review > answered")
			section.reviewMode = "open"
			ns.MainWindow.Refresh()
		end)

		t:it("Story import: the text page and the review page", function()
			ns.ImportWizard.Open({}) -- opens on the review page while pieces wait
			local w = ns.ImportWizard.Frame()
			expect.truthy(w.approve:IsVisible(), "a piece waits for review")
			check("Import story > Review")
			click(w.approve)
			check("Import story > Review, after an approval")
			click(w.secondary) -- Back to text
			expect.truthy(w.edit:IsVisible())
			check("Import story > Your story")
			ns.ImportWizard.Close()
		end)

		t:it("Settings: General, Story and Data", function()
			for _, page in ipairs({ "general", "story", "data" }) do
				ns.SettingsPanel.OpenPage(page)
				check("Settings > " .. page)
			end
			ns.MainWindow.Select("journal")
		end)

		t:it("Guide: every topic", function()
			ns.GuidePanel.Open(1)
			local panel = ns.GuidePanel.panel
			for i = 1, #ns.Guide.TOPICS do
				panel:Show(i)
				check("Guide topic " .. ns.Guide.TOPICS[i].title)
			end
		end)

		t:it("the sweep would notice a chip: a planted Private label is reported", function()
			local fs = ns.MainWindow.GetFrame():CreateFontString(nil, "OVERLAY")
			fs:SetText("Private")
			expect.equal(#hits(mock), 1)
			fs:Hide()
			expect.equal(#hits(mock), 0, "hidden text is not on screen")
		end)
	end)
end

-- These specs model characters an earlier version created (Loader.Legacy).
return function(t, expect)
	Loader.Legacy(function() legacySpec(t, expect) end)
end
