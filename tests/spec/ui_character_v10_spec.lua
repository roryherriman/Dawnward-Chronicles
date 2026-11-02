-- L2 (v0.10): the Character profile and Showcase against the approved
-- mockups (character-profile.png, proposed-character-showcase.png):
-- values from the game with the player's override, dashed "+ Add" tiles,
-- the imported story card and its reader, a right column that fits without
-- its own scroll bar, "+N more" family, and the Showcase's turn arrows and
-- own-words panel. The mock proves wiring and layout maths, not the look in
-- game (docs/design/audit/v10-character.md lists the in-game checks).
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local STORY = "Raised above the Lion's Pride Inn by a widowed innkeeper.\n\n"
	.. "She joined the Light late, and not for glory.\n\n"
	.. "She keeps a list of every name she could not save.\n\n"
	.. string.rep("The road east of Goldshire was never quiet. ", 60) .. "\n\n"
	.. "{h1}The Lantern Road{/h1}Last words."

local function click(button)
	button:GetScript("OnClick")(button)
end

-- A character on the v0.10 model (no publish callout over the columns).
local function openCharacter()
	local mock, env, ns = Boot.Start()
	ns.Actions.WithCharacter(ns.ctx, function(c) return ns.Publication.Adopt(c, 1) end)
	mock.Slash("")
	ns.MainWindow.Select("character")
	return mock, env, ns, ns.CharacterView.section
end

local function rowFor(section, key)
	for i, spec in ipairs(section.specs) do
		if spec.kind == "field" and spec.field.key == key then return section.rows[i] end
	end
end

local function rowOfKind(section, kind, list)
	for i, spec in ipairs(section.specs) do
		if spec.kind == kind and (list == nil or spec.list == list) then return section.rows[i], spec end
	end
end

-- Offsets of a region's first anchor: x, top (positive, downwards).
local function pos(region)
	local p = region.__points[1]
	if type(p[2]) == "number" then return p[2], -p[3] end
	return p[4] or 0, -(p[5] or 0)
end

local function saveStory(ns, text)
	ns.Actions.WithCharacter(ns.ctx, function(c) return ns.Sources.Capture(c, "paste", text, nil, 1) end)
	ns.MainWindow.Refresh()
end

return function(t, expect)
	t:describe("character profile v0.10: values from the game (L2)", function()
		t:it("shows race, class and first name from the game until the player writes their own", function()
			local _, env, ns, section = openCharacter()
			local race = rowFor(section, "race")
			expect.equal(race.value:GetText(), "Orc", "UnitRace's first value, as Total RP 3 uses")
			expect.equal(rowFor(section, "class").value:GetText(), "Mage")
			expect.equal(rowFor(section, "firstName").value:GetText(), "Testchar")
			expect.equal(race.value.textRole, "text", "quieter than the player's own words")
			expect.truthy(race.notes:IsShown())
			expect.equal(race.notes:GetText(), ns.CharacterView.GAME_HINT)
			expect.equal(race.gameValue, "Orc")
			expect.falsy(race.emptyField, "a value from the game is not an empty tile")
			expect.equal(race.edit:GetText(), "Edit")
			expect.truthy(race.tooltipTitle:find("from the game", 1, true))
			expect.truthy(race.edit.tooltipTitle:find("Write your own", 1, true))
			-- Never written into saved data by itself.
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.fields.race, nil)
			expect.equal(char.fields.class, nil)
			expect.equal(char.fields.firstName, nil)
			-- Fields the game does not know stay empty.
			expect.truthy(rowFor(section, "age").emptyField)
			expect.equal(rowFor(section, "age").gameValue, nil)
		end)

		t:it("keeps an RP override possible through Edit, and clearing it brings the game's back", function()
			local mock, env, _, section = openCharacter()
			click(rowFor(section, "race").edit)
			local editor = section.editor
			expect.truthy(editor:IsShown())
			expect.equal(editor.line:GetText(), "", "the game's value is not put in the box to be saved")
			expect.truthy(editor.hint:GetText():find("\"Orc\"", 1, true), editor.hint:GetText())
			expect.falsy(editor.clear:IsShown(), "nothing of the player's to clear yet")
			editor.line:SetText("Mag'har")
			click(editor.save)
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(char.fields.race.value, "Mag'har")
			local race = rowFor(section, "race")
			expect.equal(race.value:GetText(), "Mag'har")
			expect.equal(race.value.textRole, "heading")
			expect.falsy(race.notes:IsShown(), "the player's own words carry no game hint")
			click(race.edit)
			expect.truthy(editor.clear:IsShown())
			expect.truthy(editor.hint:GetText():find("show the game's again", 1, true))
			click(editor.clear)
			mock.AcceptPopup()
			expect.equal(char.fields.race, nil)
			expect.equal(rowFor(section, "race").value:GetText(), "Orc", "back to the game's")
		end)

		t:it("shows an empty tile when the game cannot say", function()
			local _, env, ns, section = openCharacter()
			env.UnitRace = nil
			ns.MainWindow.Refresh()
			local race = rowFor(section, "race")
			expect.truthy(race.emptyField)
			expect.equal(race.value:GetText(), "Not set")
			expect.equal(race.edit:GetText(), "+ Add")
		end)

		t:it("keeps the game hint clear of the tile's Edit", function()
			local _, _, ns, section = openCharacter()
			local L = ns.CharacterView.LAYOUT
			for _, key in ipairs({ "race", "class", "firstName" }) do
				local row = rowFor(section, key)
				local _, top = pos(row.notes)
				local controlsTop = row:GetHeight() - L.tilePadY - L.controlHeight
				expect.truthy(top + row.notes:GetStringHeight() + 8 <= controlsTop, key)
				expect.truthy(ns.Style.TextWidth(ns.CharacterView.GAME_HINT, "meta")
					<= ns.CharacterView.TileWidth(ns.MainWindow.ContentWidth()) - 2 * L.tilePadX, "one line")
			end
		end)
	end)

	t:describe("character profile v0.10: dashed Add tiles (L2)", function()
		t:it("draws an empty field as a dashed tile whose dashes stay on its edge", function()
			local _, _, _, section = openCharacter()
			local age = rowFor(section, "age")
			local d = age.dashes
			expect.truthy(d and d.shown)
			expect.truthy(d.used >= 20, "dashes along all four sides")
			local w, h = age:GetWidth(), age:GetHeight()
			for k = 1, d.used do
				local tex = d.textures[k]
				local p = tex.__points[1]
				local x, y = p[2], -p[3]
				if p[1] == "TOPLEFT" or p[1] == "BOTTOMLEFT" then
					expect.truthy(x >= 0 and x + tex:GetWidth() <= w, "inside the tile across")
				end
				if p[1] == "TOPLEFT" or p[1] == "TOPRIGHT" then
					expect.truthy(y >= 0 and y + tex:GetHeight() <= h, "inside the tile down")
				end
				expect.truthy(tex:IsShown())
			end
			expect.equal(age.edges.top.__color[4], 0, "no solid edge under the dashes")
			expect.equal(age.bg.__color[4], 0, "no fill")
		end)

		t:it("opens the editor from + Add and from the tile itself, and drops the dashes once set", function()
			local mock, _, _, section = openCharacter()
			local age = rowFor(section, "age")
			expect.equal(age.edit:GetText(), "+ Add")
			age:GetScript("OnMouseUp")(age)
			expect.truthy(section.editor:IsShown(), "the whole empty tile opens its editor")
			expect.equal(section.editor.field.key, "age")
			click(section.editor.cancel)
			click(age.edit)
			expect.truthy(section.editor:IsShown())
			click(section.editor.cancel)
			mock.Slash("set age 24")
			age = rowFor(section, "age")
			expect.falsy(age.dashes.shown, "a set field is a filled tile again")
			expect.equal(age.edges.top.__color[4], 1)
			age:GetScript("OnMouseUp")(age)
			expect.falsy(section.editor:IsShown(), "a set tile opens only through Edit")
		end)

		t:it("draws an empty long field as a dashed card with + Add on its label row", function()
			local _, _, ns, section = openCharacter()
			local motivation = rowFor(section, "motivation")
			expect.truthy(motivation.dashes and motivation.dashes.shown)
			expect.equal(motivation.edit:GetText(), "+ Add")
			expect.equal(motivation.edit.variant, "ghost")
			expect.truthy(ns.Widgets.LabelFits("+ Add", motivation.edit:GetWidth(), motivation.edit:GetHeight(),
				"ghost"))
		end)
	end)

	t:describe("character profile v0.10: the imported story (L2)", function()
		t:it("trims a story to its first paragraphs for the card, without changing it", function()
			local _, _, ns = Boot.Load()
			local CV = ns.CharacterView
			local excerpt, more = CV.StoryExcerpt(STORY)
			expect.equal(excerpt, "Raised above the Lion's Pride Inn by a widowed innkeeper.\n\n"
				.. "She joined the Light late, and not for glory.")
			expect.truthy(more, "there is more to read")
			local short, cut = CV.StoryExcerpt("One paragraph only.")
			expect.equal(short, "One paragraph only.")
			expect.falsy(cut)
			local long, longCut = CV.StoryExcerpt(string.rep("word ", 200), 2, 100)
			expect.truthy(#long <= 100 + 3 and long:find("…$"), "shortened at a word, with an ellipsis")
			expect.truthy(longCut)
			expect.equal(CV.StoryExcerpt("{h1}Title{/h1}Body {icon:x:12} text"), "Title\n\nBody  text",
				"Total RP 3 tags are not shown")
			expect.equal(CV.StoryMeta({ kind = "trp3", text = "Three short words" }),
				"Read from Total RP 3 · 3 words")
		end)

		t:it("offers + Import on an empty Biography card, which opens Import story", function()
			local _, _, ns, section = openCharacter()
			local card, spec = rowOfKind(section, "story")
			expect.equal(spec.group, "background")
			expect.truthy(card.emptyField and card.dashes.shown)
			expect.equal(card.key:GetText(), "BIOGRAPHY")
			expect.equal(card.reading:GetText(), ns.CharacterView.STORY_EMPTY)
			expect.equal(card.edit:GetText(), "+ Import")
			click(card.edit)
			expect.truthy(ns.ImportWizard.IsShown())
		end)

		t:it("shows the first paragraphs and opens the whole story in a scrolling reader", function()
			local _, _, ns, section = openCharacter()
			saveStory(ns, STORY)
			local card = rowOfKind(section, "story")
			local L = ns.CharacterView.LAYOUT
			expect.falsy(card.emptyField)
			expect.truthy(card.reading:GetText():find("^Raised above"))
			expect.equal(card.reading.textRole, "reading")
			expect.truthy(card.detail:GetText():find("^Pasted · %d+ words$"), card.detail:GetText())
			expect.equal(card.edit:GetText(), "Read full story")
			expect.truthy(ns.Widgets.LabelFits("Read full story", card.edit:GetWidth(), card.edit:GetHeight()))
			local _, detailTop = pos(card.detail)
			expect.truthy(detailTop + card.detail:GetStringHeight() + L.cardPadY <= card:GetHeight(),
				"the card ends under its meta line")
			click(card.edit)
			local reader = section.reader
			expect.truthy(reader:IsShown())
			expect.equal(section.readerKind, "story")
			expect.falsy(section.scroll:IsShown() or section.sideScroll:IsShown(), "the profile steps aside")
			expect.falsy(section.header:IsShown())
			expect.equal(reader.heading:GetText(), "Your story")
			local shown = {}
			for _, fs in ipairs(reader.paras) do
				if fs:IsShown() then shown[#shown + 1] = fs:GetText() end
			end
			expect.equal(#shown, 6, "every paragraph, tags removed")
			expect.equal(shown[5], "The Lantern Road")
			expect.truthy(reader.scroll:GetVerticalScrollRange() > 0, "a long story scrolls")
			expect.truthy(reader.scroll:IsMouseWheelEnabled())
			-- Paragraphs never overlap.
			local last = 0
			for _, fs in ipairs(reader.paras) do
				if fs:IsShown() then
					local _, top = pos(fs)
					expect.truthy(top >= last)
					last = top + fs:GetStringHeight()
				end
			end
			-- The import window opens on the saved story.
			click(reader.action)
			expect.truthy(ns.ImportWizard.IsShown())
			expect.equal(ns.ImportWizard.Frame().edit:GetText(), STORY, "the saved story, exactly")
			ns.ImportWizard.Close()
			click(reader.back)
			expect.falsy(reader:IsShown())
			expect.truthy(section.scroll:IsShown() and section.sideScroll:IsShown() and section.header:IsShown())
			expect.equal(section.mode, "profile")
		end)
	end)

	t:describe("character profile v0.10: a right column without its own scroll bar (L2)", function()
		local function sideFits(section)
			return section.sideScroll:GetVerticalScrollRange() == 0
				and section.side:GetHeight() <= section.sideScroll:GetHeight()
		end

		t:it("fits personality and a typical family without scrolling", function()
			local mock, env, ns, section = openCharacter()
			expect.truthy(sideFits(section), "a new character (every axis unset)")
			for _, axis in ipairs(ns.Schema.PERSONALITY_AXES) do mock.Slash("personality set " .. axis.id .. " 12") end
			mock.Slash("family add mother Maybell Dawnwhisper")
			mock.Slash("family add brother Tobin")
			mock.Slash("family add father Aldric")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			char.family[1].notes = "innkeeper, Goldshire\nShe kept the lamps lit every night."
			ns.MainWindow.Refresh()
			expect.truthy(sideFits(section), "six axes and three family members")
			expect.equal(section.familyHidden, 0)
			expect.falsy(section.familyMore:IsShown())
			-- A waiting change adds its note and Review in Story; still no bar.
			assert(ns.Evolution.Propose(char, "compassion", 1, "helped a stranger", nil, 1))
			ns.MainWindow.Refresh()
			expect.truthy(sideFits(section), "with a waiting change")
		end)

		t:it("lays the personality note beside its eyebrow and the axes in compact rows", function()
			local _, _, ns, section = openCharacter()
			local L = ns.CharacterView.LAYOUT
			local pers = section.personality
			local eyebrow = ns.Style.TextWidth("PERSONALITY", "eyebrow")
			expect.equal(pers.status:GetText(), "changes need your approval")
			expect.equal(pers.status.__points[1][1], "TOPRIGHT", "on the eyebrow's row, at the right")
			expect.truthy(L.pad + eyebrow + L.statusGap + pers.status:GetWidth() <= pers:GetWidth() - L.pad,
				"clear of the eyebrow")
			for _, a in ipairs(pers.axes) do
				expect.equal(a:GetHeight(), L.axisTrackTop + L.track, "no note line on a plain axis")
			end
		end)

		t:it("uses the player's own axis words on the poles", function()
			local mock, env, ns, section = openCharacter()
			mock.Slash("personality set courage 15")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			assert(ns.AxisMeanings.Set(char, "courage", { left = "Wary", right = "Reckless", meaning = "", locked = false },
				1))
			ns.MainWindow.Refresh()
			local a = section.personality.axes[1]
			expect.equal(a.left:GetText(), "Wary")
			expect.equal(a.right:GetText(), "Reckless")
			expect.equal(a.right.__textColor[1], ns.Style.Tones(ns.Style.Current()).accentBright[1])
		end)

		t:it("shows as many family members as fit, then +N more opening the whole list", function()
			local mock, _, ns, section = openCharacter()
			for i = 1, 9 do mock.Slash("family add cousin Cousin" .. i) end
			expect.truthy(sideFits(section))
			expect.truthy(section.familyShown >= 2, "several still shown")
			expect.equal(section.familyShown + section.familyHidden, 9)
			local more = section.familyMore
			expect.equal(more:GetText(), "+" .. section.familyHidden .. " more")
			expect.truthy(ns.Widgets.LabelFits(more:GetText(), more:GetWidth(), more:GetHeight(), "ghost"))
			-- The Add is on the eyebrow row, inside the panel.
			local add = section.familyAdd
			expect.equal(add.edit:GetText(), "+ Add")
			local _, addTop = pos(add)
			local _, panelTop = pos(section.familyPanel)
			expect.truthy(addTop > panelTop and addTop + add:GetHeight() < panelTop + ns.CharacterView.LAYOUT.famHead)
			click(more)
			local reader = section.reader
			expect.truthy(reader:IsShown())
			expect.equal(section.readerKind, "family")
			local cards = 0
			for _, c in ipairs(reader.cards) do if c:IsShown() then cards = cards + 1 end end
			expect.equal(cards, 9, "everyone, each with Edit")
			click(reader.cards[9].edit)
			expect.truthy(section.form:IsOpen())
			expect.truthy(reader:IsShown(), "the list stays under the form")
			click(section.form.cancel)
			expect.truthy(reader:IsShown())
			expect.falsy(section.header:IsShown())
			click(reader.action)
			expect.truthy(section.form:IsOpen(), "+ Add family member")
			click(section.form.cancel)
			click(reader.back)
			expect.truthy(section.sideScroll:IsShown())
		end)

		t:it("puts an empty family's hint inside its panel", function()
			local _, _, ns, section = openCharacter()
			local panel = section.familyPanel
			expect.truthy(panel.empty:IsShown())
			local _, top = pos(panel.empty)
			expect.truthy(top + panel.empty:GetStringHeight() + ns.CharacterView.LAYOUT.pad <= panel:GetHeight())
		end)
	end)

	t:describe("character profile v0.10: layout guarantees (L2)", function()
		local function boxes(ns, section)
			local cols = ns.CharacterView.Columns(ns.MainWindow.ContentWidth())
			local out = {}
			for i, spec in ipairs(section.specs) do
				local row = section.rows[i]
				if row:IsShown() and spec.kind ~= "add" then
					local x, y = pos(row)
					out[#out + 1] = { x = x + (row:GetParent() == section.side and cols.rightX or 0), y = y,
						w = row:GetWidth(), h = row:GetHeight(), what = spec.kind .. ":" .. tostring(spec.group) }
				end
			end
			return out
		end

		local function fill(mock, ns)
			mock.Slash("set name Kyssarra Dawnwhisper")
			mock.Slash("set title Keeper of the Lantern Road")
			mock.Slash("set summary " .. string.rep("She is kind to strangers and sharp with friends. ", 5))
			mock.Slash("set appearance Tall, with a lantern at her belt.")
			mock.Slash("family add mother Maybell")
			mock.Slash("history add as a child; Saw the Plague")
			saveStory(ns, STORY)
		end

		t:it("never overlaps two entries, in either column", function()
			local mock, _, ns, section = openCharacter()
			fill(mock, ns)
			local list = boxes(ns, section)
			expect.equal(#list, #ns.Schema.FIELDS + 3, "every field, the story, a history entry and a family member")
			for a = 1, #list do
				for b = a + 1, #list do
					local A, B = list[a], list[b]
					local across = math.max(B.x - (A.x + A.w), A.x - (B.x + B.w))
					local down = math.max(B.y - (A.y + A.h), A.y - (B.y + B.h))
					expect.truthy(across >= ns.Widgets.ENTRY.gap or down >= ns.Widgets.ENTRY.gap,
						A.what .. " / " .. B.what)
				end
			end
			-- Left column order: tiles, Summary and Motivation, Background with the story, Details, History.
			local function top(kind, key)
				for i, spec in ipairs(section.specs) do
					if spec.kind == kind and (key == nil or (spec.field and spec.field.key == key) or spec.list == key) then
						return select(2, pos(section.rows[i]))
					end
				end
			end
			expect.truthy(top("field", "age") < top("field", "summary"), "summary right under the tiles (mockup)")
			expect.truthy(top("field", "motivation") < top("field", "homeland"))
			expect.truthy(top("field", "appearance") < top("story"))
			expect.truthy(top("story") < top("field", "firstName"))
			expect.truthy(top("field", "allegiance") < top("item", "history"))
		end)

		t:it("keeps the same geometry in layout units at window scale 0.7 and 1.4", function()
			local mock, _, ns, section = openCharacter()
			fill(mock, ns)
			local function snapshot()
				local s = { section.side:GetHeight(), section.child:GetHeight(), section.familyShown }
				for _, b in ipairs(boxes(ns, section)) do
					s[#s + 1] = b.x; s[#s + 1] = b.y; s[#s + 1] = b.w; s[#s + 1] = b.h
				end
				return s
			end
			local base = snapshot()
			local frame = ns.MainWindow.GetFrame()
			for _, scale in ipairs({ 0.7, 1.4 }) do
				frame:SetScale(scale)
				ns.MainWindow.Refresh()
				expect.deepEqual(snapshot(), base, "scale " .. scale)
			end
		end)

		t:it("keeps every new text at the readable minimum", function()
			local mock, _, ns, section = openCharacter()
			fill(mock, ns)
			local sizes = {}
			for _, f in ipairs(ns.Style.FONTS) do sizes[f.name] = f.size end
			local function check(fs, what)
				local size = sizes[fs.__template]
				if size then expect.truthy(size >= ns.Style.MIN_TEXT, what) end
			end
			check(section.personality.status, "personality note")
			check(section.familyPanel.empty, "family hint")
			section:OpenReader("story")
			for _, fs in ipairs(section.reader.paras) do check(fs, "story paragraph") end
			check(section.reader.hint, "reader hint")
			expect.equal(section.reader.paras[1].__template, ns.Style.FontFor("reading"))
		end)
	end)

	t:describe("Character Showcase v0.10 (L2)", function()
		local function showcase(ns)
			ns.MainWindow.Select("character")
			local section = ns.CharacterView.section
			click(section.showcaseButton)
			return section.showcase, section.showcaseView, section
		end

		t:it("turns with the client's own rotate arrows, dimmed while the portrait shows", function()
			local _, _, ns = openCharacter()
			local model = showcase(ns)
			local S = ns.Showcase
			expect.equal(model.left.icon.__texture, S.ROTATE_ICONS.left)
			expect.equal(model.right.icon.__texture, S.ROTATE_ICONS.right)
			expect.equal(S.ROTATE_ICONS.left, "Interface\\Buttons\\UI-RotationLeft-Button-Up")
			expect.equal(S.ROTATE_ICONS.right, "Interface\\Buttons\\UI-RotationRight-Button-Up")
			expect.equal(model.left.label:GetText(), "", "no text glyph")
			expect.truthy(S.ROTATE_ICON_SIZE <= S.CARD.button - 4, "inside the 36 px button")
			model:SetPreferPortrait(true)
			expect.falsy(model.left:IsEnabled())
			expect.equal(model.left.icon.__alpha, ns.Widgets.BUTTON.disabledAlpha)
			model:SetPreferPortrait(false)
			expect.truthy(model.left:IsEnabled())
		end)

		t:it("zooms with the wheel over the live model only, and keeps zoom and turn across the portrait", function()
			local _, _, ns = openCharacter()
			local model = showcase(ns)
			expect.truthy(model.model:IsMouseWheelEnabled())
			model.model:GetScript("OnMouseWheel")(model.model, 1)
			model:Rotate(1)
			local zoom, rotation = model.zoom, model.rotation
			model:SetPreferPortrait(true)
			expect.falsy(model.model:IsMouseWheelEnabled(), "over the portrait the wheel goes to the window")
			model.model:GetScript("OnMouseWheel")(model.model, 1)
			expect.equal(model.zoom, zoom, "no zoom while the portrait shows")
			model:SetPreferPortrait(false)
			expect.equal(model.zoom, zoom)
			expect.equal(model.model:GetRotation(), rotation, "turned as before")
		end)

		t:it("never changes the character's equipment", function()
			local f = assert(io.open("DawnwardChronicles/UI/Showcase.lua", "rb"))
			local source = f:read("*a")
			f:close()
			for _, call in ipairs({ "TryOn", "Undress", "Dress%(", "UndressSlot", "SetItem", "EquipItem",
				"PickupInventoryItem", "UseInventoryItem" }) do
				expect.falsy(source:find(":" .. call) or source:find("[^%w]" .. call .. "%("), call)
			end
		end)

		t:it("leads the own-words panel with the title the player wrote, else the name", function()
			local mock, _, ns = openCharacter()
			mock.Slash("set name Kyssarra")
			local _, view = showcase(ns)
			expect.equal(view.own.title:GetText(), "Kyssarra", "no title: the name")
			expect.equal(view.own.title.__template, ns.Style.Font("GameFontNormalLarge"), "Cinzel")
			mock.Slash("set title Keeper of the Lantern Road")
			ns.MainWindow.Refresh()
			expect.equal(view.own.title:GetText(), "Keeper of the Lantern Road")
			local _, titleTop = pos(view.own.title)
			expect.truthy(titleTop >= view.own.edit:GetHeight(), "under the Edit button's row")
		end)
	end)
end
