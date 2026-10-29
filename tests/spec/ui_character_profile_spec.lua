-- L2: the v0.7 Character profile (docs/design/mockups/character-profile.png):
-- grouped panels with tiles and cards, visibility chips, personality with
-- waiting changes, the public profile preview and the Total RP 3 button.
-- The mock proves wiring and layout maths, not the look in game.
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

return function(t, expect)
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
			expect.equal(summary:GetWidth(), cols.left - 2 * ns.Widgets.PANEL_PAD)
			-- Each group panel wraps its fields.
			local panel = section.groups.identity
			local _, top = pos(panel)
			expect.truthy(ny > top and ry + rowFor(section, "race"):GetHeight() <= top + panel:GetHeight())
		end)

		t:it("shows visibility as a chip inside each tile, and Add on an empty one", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set faith The Light, quietly doubted")
			mock.Slash("vis faith secret")
			local faith = rowFor(section, "faith")
			expect.equal(faith.key:GetText(), "FAITH")
			expect.equal(faith.value:GetText(), "The Light, quietly doubted")
			expect.equal(faith.vis:GetText(), "Secret")
			expect.equal(faith.vis:GetParent(), faith)
			local secret = ns.Themes.VISIBILITY_COLORS.secret
			expect.truthy(math.abs(faith.vis.bg.__color[1] - secret[1]) < 1e-9, "tinted like a chip")
			expect.truthy(faith.vis.bg.__color[4] > 0 and faith.vis.bg.__color[4] < 1)
			expect.equal(faith.edit:GetText(), "Edit")
			local age = rowFor(section, "age")
			expect.equal(age.value:GetText(), "Not set")
			expect.equal(age.edit:GetText(), "Add")
			expect.falsy(age.vis:IsShown())
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

		t:it("previews exactly the public projection, and nothing private or secret", function()
			local mock, env, ns, section = openCharacter()
			mock.Slash("set name Aelin Brightwater")
			mock.Slash("vis name public")
			mock.Slash("set faith Doubts the Light")
			mock.Slash("vis faith secret")
			mock.Slash("set homeland Goldshire")
			mock.Slash("family add mother Ilsa")
			mock.Slash("personality set courage 12")
			mock.Slash("personality vis courage public")
			click(section.previewButton)
			expect.equal(section.mode, "preview")
			expect.truthy(section.previewScroll:IsShown())
			expect.falsy(section.scroll:IsShown())
			expect.equal(section.previewButton:GetText(), "Back to profile")
			local text = section.previewText:GetText()
			expect.truthy(text:find("Name: Aelin Brightwater", 1, true))
			expect.truthy(text:find("Cautious - Bold: 12/20", 1, true))
			expect.falsy(text:find("Doubts", 1, true), "secret stays out")
			expect.falsy(text:find("Goldshire", 1, true), "private stays out")
			expect.falsy(text:find("Ilsa", 1, true), "private family stays out")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			local expected = ns.CharacterView.PublicPreview(ns.Projection.GetPublic(char))
			expect.deepEqual(section.previewSections, expected, "built from Projection.GetPublic")
			click(section.previewButton)
			expect.equal(section.mode, "profile")
			expect.truthy(section.scroll:IsShown())
		end)

		t:it("says so when nothing is public", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set name Aelin")
			click(section.previewButton)
			expect.falsy(section.previewAny)
			expect.truthy(section.previewText:GetText():find(ns.CharacterView.NOTHING_PUBLIC, 1, true))
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
			expect.equal(panelX, cols.rightX)
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
