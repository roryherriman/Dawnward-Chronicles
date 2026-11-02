-- L2: the v0.7 Character profile (docs/design/mockups/character-profile.png):
-- grouped panels with tiles and cards (value and Edit only, v0.10),
-- personality with waiting changes, the one-time publish callout for an
-- older character and the Total RP 3 button.
-- The mock proves wiring and layout maths, not the look in game.
local Loader = require("support.loader")
local Boot = require("support.boot")

local CHAR = "Testchar-TestRealm"

local function click(button)
	button:GetScript("OnClick")(button)
end

local function openCharacter(opts)
	local mock, env, ns = Boot.Start(opts)
	mock.Slash("")
	ns.MainWindow.Select("character")
	return mock, env, ns, ns.CharacterView.section
end

local function rowFor(section, key)
	for i, spec in ipairs(section.specs) do
		if spec.kind == "field" and spec.field.key == key then
			return section.rows[i]
		end
	end
end

local function pos(frame)
	local p = frame.__points[1]
	return p[4] or 0, -(p[5] or 0)
end

local function legacySpec(t, expect)
	t:describe("character profile (v0.7, L2)", function()
		t:it("puts every profile field in exactly one group", function()
			local ns = select(3, Boot.Load())
			local seen = {}
			for _, group in ipairs(ns.CharacterView.GROUPS) do
				for _, key in ipairs(group.keys) do
					expect.falsy(seen[key], key .. " in one group only")
					seen[key] = group.id
				end
			end
			for _, field in ipairs(ns.Schema.FIELDS) do
				expect.truthy(seen[field.key], field.key .. " has a group")
			end
			expect.deepEqual(ns.CharacterView.GROUPS[1].keys, { "name", "title", "pronouns", "race", "class", "age" })
		end)

		t:it("lays short fields out as tiles, three to a row, and long fields as full-width cards", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set name Aelin Brightwater")
			local W = ns.MainWindow.ContentWidth()
			local tile = ns.CharacterView.TileWidth(W)
			local nx, ny = pos(rowFor(section, "name"))
			local tx, ty = pos(rowFor(section, "title"))
			local px, py = pos(rowFor(section, "pronouns"))
			local rx, ry = pos(rowFor(section, "race"))
			expect.equal(ny, ty)
			expect.equal(ty, py)
			expect.truthy(tx > nx and px > tx, "side by side")
			expect.equal(rx, nx, "the fourth starts a new row")
			expect.truthy(ry > ny)
			expect.equal(rowFor(section, "name"):GetWidth(), tile)
			local cols = ns.CharacterView.Columns(W)
			expect.equal(px + tile <= cols.left, true, "tiles stay in the left column")
			local summary = rowFor(section, "summary")
			expect.equal(summary:GetWidth(), cols.left, "cards span the left column, as the mockup's Summary")
			-- Each group wraps its fields.
			local panel = section.groups.identity
			local _, top = pos(panel)
			expect.truthy(ny > top and ry + rowFor(section, "race"):GetHeight() <= top + panel:GetHeight())
		end)

		t:it("shows each tile's value and Edit, whatever its old visibility, and Add on an empty one", function()
			local mock, _, _, section = openCharacter()
			mock.Slash("set faith The Light, quietly doubted")
			mock.Vis("vis faith secret")
			local faith = rowFor(section, "faith")
			expect.equal(faith.key:GetText(), "FAITH")
			expect.equal(faith.value:GetText(), "The Light, quietly doubted")
			expect.equal(faith.vis, nil, "no visibility chip")
			expect.equal(faith.edit:GetText(), "Edit")
			local age = rowFor(section, "age")
			expect.equal(age.value:GetText(), "Not set")
			expect.equal(age.edit:GetText(), "Add")
			click(age.edit)
			expect.truthy(section.editor:IsShown(), "Add opens the same editor")
		end)

		t:it("shows the six personality axes with their real values", function()
			local mock, _, _, section = openCharacter()
			mock.Slash("personality set courage 14")
			mock.Slash("personality set sociability 4")
			local pers = section.personality
			expect.equal(#pers.rows, 6)
			expect.equal(pers.rows[1].value, 14)
			expect.equal(pers.rows[2].value, nil, "never invented")
			local courage = pers.axes[1]
			expect.equal(courage.left:GetText(), "Cautious")
			expect.equal(courage.right:GetText(), "Bold")
			expect.truthy(courage.knob:IsShown())
			expect.falsy(pers.axes[2].knob:IsShown(), "an unset axis has no knob")
			expect.equal(pers.axes[2].note:GetText(), "Not set")
			local x6 = pers.axes[6].knob.__points[1][2]
			local x1 = courage.knob.__points[1][2]
			expect.truthy(x1 > x6, "the knob sits at the value")
			expect.truthy(pers.status:GetText():find("need your approval", 1, true))
			expect.falsy(pers.review:IsShown())
		end)

		t:it("marks personality changes waiting for approval and links to Story", function()
			local mock, env, ns, section = openCharacter()
			mock.Slash("set name Aelin")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			assert(ns.Evolution.Propose(char, "compassion", 1, "helped a stranger", nil, 1))
			ns.MainWindow.Refresh()
			local pers = section.personality
			expect.equal(pers.waiting, 1)
			expect.equal(pers.status:GetText(), "1 change waits for your approval in Story.")
			expect.equal(pers.axes[2].note:GetText(), "1 change waiting: toward Compassionate")
			expect.truthy(pers.review:IsShown())
			click(pers.review)
			expect.equal(ns.MainWindow.CurrentSection(), "story")
			expect.equal(char.personality.compassion, nil, "nothing applied without approval")
		end)

		t:it("shows the publish callout only for a character an earlier version kept partly back", function()
			local mock, env, ns, section = openCharacter()
			expect.falsy(section.callout:IsShown(), "nothing written: nothing to confirm")
			mock.Slash("set name Aelin Brightwater")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			expect.equal(ns.Publication.Status(char), "pending")
			expect.truthy(section.callout:IsShown())
			expect.equal(section.callout.text:GetText(),
				"An earlier version of Dawnward kept part of this profile back from Total RP 3.")
			expect.equal(section.callout.button:GetText(), "Publish whole profile…")
			expect.truthy(ns.Widgets.LabelFits(section.callout.button:GetText(), section.callout.button:GetWidth(),
				section.callout.button:GetHeight(), section.callout.button.variant))
			-- Not in the showcase, and not while the field editor is open.
			click(section.showcaseButton)
			expect.falsy(section.callout:IsShown())
			click(section.showcaseButton)
			expect.truthy(section.callout:IsShown())
			click(rowFor(section, "title").edit)
			expect.falsy(section.callout:IsShown())
			click(section.editor.cancel)
			expect.truthy(section.callout:IsShown())
		end)

		t:it("never shows the callout for a v0.10 character", function()
			local mock, env, ns, section = openCharacter()
			mock.Slash("set name Aelin")
			ns.Publication.Adopt(env.DawnwardChroniclesDB.characters[CHAR], 1)
			ns.MainWindow.Refresh()
			expect.falsy(section.callout:IsShown())
		end)

		t:it("Publish whole profile asks first, lists what changes, then publishes; Cancel changes nothing",
			function()
			local mock, env, ns, section = openCharacter()
			mock.Slash("set name Aelin")
			mock.Slash("set faith Doubts the Light")
			mock.Vis("vis faith secret")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			click(section.callout.button)
			local d = ns.Widgets.dialog
			expect.truthy(d:IsShown())
			expect.truthy(d.text:GetText():find("Profile details: 2 more to publish", 1, true), d.text:GetText())
			click(d.cancel)
			expect.equal(ns.Publication.Status(char), "pending", "Cancel: nothing changes")
			click(section.callout.button)
			mock.AcceptPopup()
			expect.truthy(ns.Publication.IsComplete(char))
			expect.equal(char.fields.faith.visibility, "secret", "the stored records are not changed")
			expect.equal(ns.Projection.GetPublic(char).fields.faith.value, "Doubts the Light")
			expect.truthy(ns.MainWindow.GetFrame().status:GetText():find("whole character profile", 1, true))
			expect.falsy(section.callout:IsShown(), "gone once confirmed")
			mock.Slash("publish undo")
			ns.MainWindow.Refresh()
			expect.truthy(section.callout:IsShown(), "back after an undo")
		end)

		t:it("the Character page and the Total RP 3 page share one confirmation", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set name Aelin")
			click(section.callout.button)
			local first = ns.Widgets.dialog.text:GetText()
			ns.Widgets.dialog:Hide()
			ns.MainWindow.AskPublishWholeProfile()
			expect.equal(ns.Widgets.dialog.text:GetText(), first)
			ns.Widgets.dialog:Hide()
			mock.Slash("publish confirm")
			expect.equal(ns.MainWindow.AskPublishWholeProfile(), nil, "nothing to confirm once published")
		end)

		t:it("opens the Total RP 3 page of Settings", function()
			local _, _, ns, section = openCharacter()
			local opened
			ns.SettingsPanel.OpenPage = function(page) opened = page end
			click(section.trp3Button)
			expect.equal(opened, "trp3")
			ns.SettingsPanel.OpenPage = nil
			click(section.trp3Button)
			expect.equal(ns.MainWindow.CurrentSection(), "settings")
			expect.equal(ns.MainWindow.settings.page, "trp3")
		end)

		t:it("hides the header actions while a family form is open", function()
			local _, _, _, section = openCharacter()
			expect.truthy(section.header:IsShown())
			section:OpenItemForm("family", nil)
			expect.falsy(section.header:IsShown())
			click(section.form.cancel)
			expect.truthy(section.header:IsShown())
		end)

		t:it("keeps family and history in the Family & relationships panel", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("family add sister Mira")
			mock.Slash("history add Took the oath")
			local cols = ns.CharacterView.Columns(ns.MainWindow.ContentWidth())
			local panelX, panelY = pos(section.familyPanel)
			-- In the right column's own scroll child, which stands at rightX.
			expect.equal(panelX, 0)
			expect.equal(section.familyPanel:GetParent(), section.side)
			expect.equal(section.sideScroll.__points[1][2], cols.rightX)
			for i, spec in ipairs(section.specs) do
				if spec.kind ~= "field" then
					local x, y = pos(section.rows[i])
					expect.truthy(x >= panelX and x + section.rows[i]:GetWidth() <= panelX + cols.right, spec.kind)
					expect.truthy(y >= panelY and y + section.rows[i]:GetHeight() <= panelY + section.familyPanel:GetHeight())
				end
			end
			local _, persY = pos(section.personality)
			expect.truthy(persY < panelY, "personality first")
		end)
	end)
end

-- These specs model characters an earlier version created (Loader.Legacy).
return function(t, expect)
	Loader.Legacy(function() legacySpec(t, expect) end)
end
