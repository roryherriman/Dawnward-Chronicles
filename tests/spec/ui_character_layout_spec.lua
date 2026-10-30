-- L2: v0.8 layout guarantees of the Character profile against the approved
-- mockup (docs/design/mockups/character-profile.png, Character.dc.html):
-- sizes, positions and fits that the mock can prove. Whether it looks right
-- is the owner's in-game comparison (docs/design/audit/character.md).
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

-- First anchor of a region: point, x, y (offsets as given to SetPoint).
local function anchor(region)
	local p = region.__points[1]
	if type(p[2]) == "number" then return p[1], p[2], p[3] end
	return p[1], p[4] or 0, p[5] or 0
end

local function pos(frame)
	local _, x, y = anchor(frame)
	return x, -y
end

return function(t, expect)
	t:describe("character profile layout (v0.8, L2)", function()
		t:it("follows the mockup's grid: three tiles 10 apart, a 268 column 20 to the right", function()
			local _, _, ns = openCharacter()
			local CV = ns.CharacterView
			local W = ns.MainWindow.ContentWidth()
			local cols = CV.Columns(W)
			expect.equal(cols.right, 268)
			expect.equal(cols.rightX - cols.left, 20)
			expect.equal(CV.LAYOUT.tileGap, 10)
			local tile = CV.TileWidth(W)
			expect.truthy(3 * tile + 2 * CV.LAYOUT.tileGap <= cols.left, "three tiles fit the left column")
			expect.truthy(tile >= 140, "tiles stay close to the mockup's 150")
			expect.truthy(cols.rightX + cols.right <= cols.child, "the right column stays inside the scroll child")
			expect.truthy(cols.child <= W, "and the content area")
		end)

		t:it("fits the chip and Edit inside every tile, whatever the visibility", function()
			local mock, _, ns, section = openCharacter()
			local CV, L = ns.CharacterView, ns.CharacterView.LAYOUT
			mock.Slash("set name Aelin Brightwater")
			local tile = CV.TileWidth(ns.MainWindow.ContentWidth())
			for _, level in ipairs({ "private", "public", "secret" }) do
				mock.Slash("vis name " .. level)
				local row = rowFor(section, "name")
				expect.equal(row.vis:GetText(), ns.Themes.VISIBILITY_LABELS[level])
				local chipRight = L.tilePadX + row.vis:GetWidth()
				local editLeft = tile - L.tilePadY - row.edit:GetWidth()
				expect.truthy(chipRight + 6 <= editLeft, level .. ": chip and Edit do not touch")
				expect.equal(row.vis:GetWidth(), CV.ChipWidth(level), "the chip is as wide as its word")
				expect.truthy(ns.Widgets.LabelFits(row.vis:GetText(), row.vis:GetWidth() + 2 * 4, row.vis:GetHeight(), "ghost"),
					level .. " is readable in its chip")
			end
			local row = rowFor(section, "name")
			expect.equal(row.edit:GetHeight(), ns.Style.CONTROL.compact, "buttons in cards are 30 high")
			expect.equal(row.vis:GetHeight(), ns.Widgets.CHIP_HEIGHT)
		end)

		t:it("keeps a tile's value clear of its controls, even when it wraps", function()
			local mock, _, ns, section = openCharacter()
			local L = ns.CharacterView.LAYOUT
			mock.Slash("set title " .. string.rep("Keeper of the Lantern Road ", 3))
			local row = rowFor(section, "title")
			local valueBottom = L.tileValueTop + row.value:GetStringHeight()
			local controlsTop = row:GetHeight() - L.tilePadY - L.controlHeight
			expect.truthy(valueBottom + 8 <= controlsTop, "value above the chip and Edit")
			expect.truthy(row:GetHeight() >= L.tileMin)
			-- Tiles of one row share its height (as the mockup's grid).
			expect.equal(rowFor(section, "name"):GetHeight(), row:GetHeight())
			expect.equal(row.value.__template, ns.Style.FontFor("nav"), "values in the 17 px style")
			expect.equal(row.value.textRole, "heading", "values in title white")
		end)

		t:it("draws an empty field without fill, and its label as a Cinzel eyebrow", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set name Aelin")
			local age, name = rowFor(section, "age"), rowFor(section, "name")
			expect.equal(age.bg.__color[4], 0, "an empty tile is only its edge")
			expect.equal(name.bg.__color[4], 1)
			expect.equal(age.edges.top.__color[4], 1)
			expect.equal(age.key:GetText(), "AGE")
			expect.equal(age.key.__template, ns.Style.Font("GameFontNormalSmall"))
		end)

		t:it("puts a card's chip and Edit on its label row, and its text in the reading style", function()
			local mock, _, ns, section = openCharacter()
			local L = ns.CharacterView.LAYOUT
			mock.Slash("set summary Raised above the Lion's Pride Inn by a widowed innkeeper.")
			local card = rowFor(section, "summary")
			local point, x, y = anchor(card.edit)
			expect.equal(point, "TOPRIGHT")
			expect.equal(x, -L.cardPadX)
			expect.equal(y, -L.cardPadY)
			expect.equal(card.edit:GetText(), "Edit")
			expect.equal(card.edit.variant, "default", "a secondary button, as the mockup")
			expect.equal(card.vis.__points[1][2], card.edit, "the chip sits left of Edit")
			expect.truthy(card.reading:IsShown())
			expect.equal(card.reading:GetText(), "Raised above the Lion's Pride Inn by a widowed innkeeper.")
			expect.equal(card.reading.__template, ns.Style.FontFor("reading"))
			expect.truthy(card:GetHeight() >= L.cardTextTop + card.reading:GetStringHeight() + L.cardPadY)
		end)

		t:it("places the intro under the title and the header buttons level with the close button", function()
			local _, _, ns, section = openCharacter()
			local ML = ns.MainWindow.LAYOUT
			local L = ns.CharacterView.LAYOUT
			local _, _, introY = anchor(section.intro)
			local introTop = ML.contentTop - introY
			local titleBottom = ML.headerTop + ML.eyebrowHeight + ML.titleGap + ML.titleHeight
			expect.truthy(introTop >= titleBottom, "under the title")
			expect.truthy(introTop + 18 <= ML.contentTop + L.scrollTop, "above the tiles")
			expect.equal(ML.contentTop - L.headerOffset, ML.headerTop, "header buttons start where the close button does")
			local width = 0
			for _, b in ipairs({ section.previewButton, section.showcaseButton, section.trp3Button, section.importButton }) do
				expect.equal(b:GetHeight(), ns.Style.CONTROL.standard, b:GetText())
				expect.truthy(ns.Widgets.LabelFits(b:GetText(), b:GetWidth(), b:GetHeight(), b.variant), b:GetText())
				width = width + b:GetWidth() + 8
			end
			expect.truthy(width - 8 <= section.header:GetWidth(), "four buttons fit the header's room")
			for _, text in ipairs({ "Back to profile", "Profile fields" }) do
				expect.truthy(ns.Widgets.LabelFits(text, 128, ns.Style.CONTROL.standard), text)
			end
		end)

		t:it("names the view in the eyebrow and keeps only the way back in the showcase header", function()
			local _, _, ns, section = openCharacter()
			local frame = ns.MainWindow.GetFrame()
			expect.equal(frame.eyebrow:GetText(), "CHARACTER")
			click(section.showcaseButton)
			expect.equal(frame.eyebrow:GetText(), "CHARACTER · SHOWCASE")
			expect.falsy(section.previewButton:IsShown())
			expect.falsy(section.importButton:IsShown())
			expect.falsy(section.trp3Button:IsShown())
			expect.equal(anchor(section.showcaseButton), "TOPRIGHT", "Profile fields takes the right end")
			click(section.showcaseButton)
			expect.truthy(section.previewButton:IsShown() and section.importButton:IsShown() and section.trp3Button:IsShown())
			click(section.previewButton)
			expect.equal(frame.eyebrow:GetText(), "CHARACTER · PUBLIC PREVIEW")
			ns.MainWindow.Select("journal")
			expect.equal(frame.eyebrow:GetText(), "JOURNAL", "other sections keep their own")
		end)

		t:it("draws personality as the mockup: a 6 px track, a ringed 14 px knob centred on the value", function()
			local mock, env, ns, section = openCharacter()
			local L = ns.CharacterView.LAYOUT
			mock.Slash("personality set courage 20")
			mock.Slash("personality set compassion 10")
			mock.Slash("personality set discipline 0")
			local axes = section.personality.axes
			local width = section.personality:GetWidth() - 2 * L.pad
			expect.equal(axes[1].track:GetHeight(), 6)
			expect.equal(axes[1].knob:GetWidth(), 14)
			expect.equal(axes[1].knobDot:GetWidth(), 10, "a 2 px ring around the gold")
			local function centre(a) return a.knob.__points[1][2] + 7 end
			expect.equal(centre(axes[1]), width - 7, "the knob stays on the track at 20")
			expect.equal(centre(axes[2]), math.floor(width / 2 + 0.5), "10 is the middle")
			expect.equal(centre(axes[3]), 7, "and at 0")
			local theme = ns.Style.Current()
			local bright = ns.Style.Tones(theme).accentBright
			expect.equal(axes[1].right.__textColor[1], bright[1], "the pole she leans to is bright gold")
			expect.equal(axes[1].left.__textColor[1], theme.muted[1])
			-- A waiting change: an amber note and a marker where the value would go.
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			assert(ns.Evolution.Propose(char, "compassion", 1, "helped a stranger", nil, 1))
			ns.MainWindow.Refresh()
			local amber = ns.Themes.STATUS_COLORS.waiting
			expect.equal(axes[2].note.__textColor[1], amber[1])
			expect.equal(section.personality.status.__textColor[1], amber[1])
			expect.truthy(axes[2].pendingMark:IsShown())
			expect.falsy(axes[1].pendingMark:IsShown())
			expect.equal(section.personality.review:GetHeight(), ns.Style.CONTROL.compact)
			-- Axes never overlap and stay inside the panel.
			local _, panelY = pos(section.personality)
			local last = panelY
			for _, a in ipairs(axes) do
				local _, y = pos(a)
				expect.truthy(y >= last, "below the one before")
				last = y + a:GetHeight()
			end
			expect.truthy(last <= panelY + section.personality:GetHeight())
		end)

		t:it("shows a family member as name, relation and notes, with Edit and the chip inside", function()
			local mock, env, ns, section = openCharacter()
			local L = ns.CharacterView.LAYOUT
			mock.Slash("family add mother Maybell Dawnwhisper")
			local char = env.DawnwardChroniclesDB.characters[CHAR]
			char.family[1].notes = "innkeeper, Goldshire"
			char.family[1].status = "living"
			ns.MainWindow.Refresh()
			local row
			for i, spec in ipairs(section.specs) do
				if spec.kind == "item" and spec.list == "family" then row = section.rows[i] end
			end
			expect.equal(row.title:GetText(), "Maybell Dawnwhisper")
			expect.equal(row.detail:GetText(), "Mother · living")
			expect.equal(row.notes:GetText(), "innkeeper, Goldshire")
			local w = row:GetWidth()
			expect.truthy(10 + row.title:GetWidth() + 8 + row.edit:GetWidth() + 10 <= w, "text clear of Edit")
			local _, _, chipY = anchor(row.vis)
			expect.truthy(-chipY + row.vis:GetHeight() <= row:GetHeight(), "the chip inside the card")
			expect.truthy(10 + row.vis:GetWidth() <= w)
			expect.equal(row.edit:GetHeight(), L.controlHeight)
			-- The Add line uses a quiet button, as the mockup's family "Add".
			for i, spec in ipairs(section.specs) do
				if spec.kind == "add" then expect.equal(section.rows[i].edit.variant, "ghost") end
			end
		end)

		t:it("keeps every profile text at the readable minimum or larger", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set name Aelin")
			mock.Slash("family add sister Mira")
			local S = ns.Style
			local sizes = {}
			for _, f in ipairs(S.FONTS) do sizes[f.name] = f.size end
			local function check(fs, what)
				local template = fs.__template
				local size = sizes[template]
				if size then expect.truthy(size >= S.MIN_TEXT, what .. " " .. template) end
			end
			for i, spec in ipairs(section.specs) do
				local row = section.rows[i]
				for _, key in ipairs({ "key", "label", "value", "reading", "title", "detail", "notes" }) do
					check(row[key], spec.kind .. "." .. key)
				end
			end
			for _, a in ipairs(section.personality.axes) do
				check(a.left, "pole"); check(a.right, "pole"); check(a.note, "note")
			end
			check(section.intro, "intro")
			expect.equal(sizes[section.intro.__template], 15, "the intro at 15, as the mockup")
		end)

		t:it("lays the public preview out as reading text at a readable measure", function()
			local mock, _, ns, section = openCharacter()
			mock.Slash("set name Aelin Brightwater")
			mock.Slash("vis name public")
			click(section.previewButton)
			expect.equal(section.previewText.__template, ns.Style.FontFor("reading"))
			expect.truthy(section.previewText:GetWidth() <= 620, "lines no longer than about 62 characters at 16")
			expect.truthy(section.previewText:GetText():find("NAME", 1, true) == nil, "field names are not shouted")
			expect.truthy(section.previewText:GetText():find("PROFILE", 1, true), "section titles are eyebrows")
		end)
	end)
end
