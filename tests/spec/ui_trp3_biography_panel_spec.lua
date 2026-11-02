-- L2 (v0.10.1): Settings -> Total RP 3 -> Biography panel
-- (UI/TRP3BiographyPanel.lua), on its own, under the WoW mock and the TRP3
-- 3.4.1 fake (mocked client; not in-game evidence). The choices are saved
-- per character, the preview follows them at once and draws the page as
-- Total RP 3 does, the panel fits the card it is given at any window scale,
-- and nothing it does writes to Total RP 3.
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

local CHAR = "Testchar-TestRealm"
local W, H = 820, 470

local function click(button)
	button:GetScript("OnClick")(button)
end

local function start()
	local fake = Fake.new({})
	local extra = {}
	for k, v in pairs(fake.env) do
		if k ~= "C_AddOns" then extra[k] = v end
	end
	local mock, env, ns = Boot.Load({ extra = extra })
	mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
	local meta = mock.env.C_AddOns.GetAddOnMetadata
	mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
		return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
	end
	Boot.Login(mock)
	ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
	mock.Slash("set summary A quiet paladin who keeps a book of names.")
	mock.Slash("set appearance Grey eyes, a burn scar on one hand.")
	mock.Slash("set motivation No village forgotten.")
	ns.Actions.WithCharacter(ns.ctx, function(c)
		return ns.Sources.Capture(c, "paste", "# The fall\nThe walls fell.\n\nShe hid in the mill.", nil, 5)
	end)
	local parent = mock.env.CreateFrame("Frame", nil, mock.env.UIParent)
	parent:SetSize(W, H)
	local panel = ns.TRP3BiographyPanel.Build(parent, W, H)
	local function view() return ns.TRP3Commands.Overview(ns.ctx.trp3Deps()) end
	panel:Refresh(view())
	return { mock = mock, env = env, ns = ns, fake = fake, panel = panel, parent = parent, view = view,
		prefs = function() return ns.ctx.store.real.characters[CHAR].story.prefs end }
end

local function rowOf(panel, id)
	for _, row in ipairs(panel.rows) do
		if row.id == id then return row end
	end
end

local function segment(seg, id)
	for _, b in ipairs(seg.buttons) do
		if b.segmentId == id then return b end
	end
end

return function(t, expect)
	t:describe("Biography panel (v0.10.1, L2)", function()
		t:it("previews the About page as Total RP 3 draws it: white headings, coloured body, the story in order", function()
			local w = start()
			local text = w.panel:PreviewText()
			local a = text:find("Character overview", 1, true)
			local b = text:find("Biography", 1, true)
			local c = text:find("The fall", 1, true)
			local d = text:find("Appearance", 1, true)
			expect.truthy(a and b and c and d and a < b and b < c and c < d, text)
			expect.truthy(text:find("|cffe8e0d0She hid in the mill.|r", 1, true), "Neutral's ivory body text")
			expect.falsy(text:find("No village forgotten", 1, true), "motivation is off by default")
			local r = w.panel.render
			for _, fs in ipairs(r.pools.p) do
				if fs:IsShown() then expect.deepEqual(fs.__textColor, { 1, 0.82, 0 }, "TRP3's paragraph gold underneath") end
			end
			expect.deepEqual(r.pools.h2[1].__textColor, { 1, 1, 1 }, "TRP3's white headings")
			expect.truthy(w.panel.previewHead:GetText():find("TEMPLATE 1", 1, true))
			expect.equal(r.usedFrames, 0)
		end)

		t:it("saves the template, style and heading colour per character, and the preview follows", function()
			local w = start()
			click(segment(w.panel.template, "frames"))
			expect.equal(w.prefs().trp3Layout, "frames")
			expect.truthy(w.panel.previewHead:GetText():find("TEMPLATE 2", 1, true))
			expect.equal(w.panel.render.usedFrames, 3, "one frame per section: overview, biography, appearance")
			expect.truthy(rowOf(w.panel, "overview").icon:IsShown(), "frame icons can be chosen in Frames")
			click(segment(w.panel.style, "silverhand"))
			expect.equal(w.prefs().trp3Style, "silverhand")
			expect.truthy(w.panel:PreviewText():find("|cffe6c35cBiography|r", 1, true), "gold headings")
			expect.truthy(w.panel:PreviewText():find("|cffefe4c9The walls fell.|r", 1, true), "parchment body")
			expect.equal(w.panel.render.frames[1].bg.__texture, w.ns.TRP3Presentation.BACKGROUNDS[3].file)
			click(w.panel.swatches[6]) -- violet
			expect.equal(w.prefs().trp3Accent, "violet")
			expect.truthy(w.panel:PreviewText():find("|cffc4adffBiography|r", 1, true))
			expect.truthy(w.panel.swatches[6].selected)
			click(segment(w.panel.template, "sections"))
			local parts = {}
			for _, fs in ipairs(w.panel.render.order) do
				local title = (fs:GetText() or ""):match("|t  (.-)  |T")
				if title then parts[#parts + 1] = title end
			end
			expect.deepEqual(parts, { "Physical Description", "History" })
			expect.falsy(rowOf(w.panel, "overview").icon:IsShown(), "no frame icons outside Frames")
			-- Saved data keeps the choices across a reload.
			local char = w.ns.ctx.store.real.characters[CHAR]
			local again = w.ns.Schema.NormalizeCharacter(w.ns.Util.DeepCopy(char))
			expect.equal(again.story.prefs.trp3Accent, "violet")
			expect.equal(again.story.prefs.trp3Layout, "sections")
		end)

		t:it("shows, hides, renames and reorders sections", function()
			local w = start()
			local motivation = rowOf(w.panel, "motivation")
			expect.falsy(motivation.on)
			click(motivation.toggle)
			expect.equal(w.prefs().trp3Sections.on.motivation, true)
			expect.truthy(w.panel:PreviewText():find("No village forgotten.", 1, true))
			click(rowOf(w.panel, "motivation").toggle)
			expect.falsy(w.panel:PreviewText():find("No village forgotten.", 1, true))
			-- Rename: typed, saved when the field loses focus; empty restores the default.
			local bio = rowOf(w.panel, "biography")
			bio.title:SetFocus()
			bio.title:SetText("Her long road")
			bio.title:ClearFocus()
			expect.equal(w.prefs().trp3Sections.titles.biography, "Her long road")
			expect.truthy(w.panel:PreviewText():find("Her long road", 1, true))
			bio = rowOf(w.panel, "biography")
			bio.title:SetFocus()
			bio.title:SetText("")
			bio.title:ClearFocus()
			expect.equal(w.prefs().trp3Sections.titles.biography, nil)
			expect.equal(rowOf(w.panel, "biography").title:GetText(), "Biography")
			-- Order: Up moves the biography first; the first row cannot go up.
			click(rowOf(w.panel, "biography").up)
			expect.equal(w.panel.rows[1].id, "biography")
			expect.falsy(w.panel.rows[1].up:IsEnabled())
			expect.falsy(w.panel.rows[#w.panel.rows].down:IsEnabled())
			local text = w.panel:PreviewText()
			expect.truthy(text:find("Biography", 1, true) < text:find("Character overview", 1, true))
			-- A section with nothing written says how to add it.
			local personality = rowOf(w.panel, "personality")
			expect.truthy(personality.toggle.tooltipText:find("Describe the personality on the Character page", 1, true))
			expect.falsy(personality.toggle.tooltipText:find("no personality description", 1, true),
				"the help no longer says there is no personality field")
			click(w.panel.reset)
			expect.equal(w.prefs().trp3Sections, nil)
			expect.equal(w.panel.rows[1].id, "overview")
		end)

		t:it("picks a frame icon and background from the verified lists only", function()
			local w = start()
			click(segment(w.panel.template, "frames"))
			local overview = rowOf(w.panel, "overview")
			click(overview.icon)
			local picker = w.panel.picker
			expect.truthy(picker:IsShown())
			local P = w.ns.TRP3Presentation
			local shown = 0
			for i, b in ipairs(picker.buttons) do
				if b:IsShown() then
					shown = shown + 1
					expect.equal(b.image.__texture, "Interface\\ICONS\\" .. P.ICON_CHOICES[i].id)
				end
			end
			expect.equal(shown, #P.ICON_CHOICES)
			click(picker.buttons[3]) -- inv_scroll_02
			expect.falsy(picker:IsShown())
			expect.equal(w.prefs().trp3Sections.icons.overview, "inv_scroll_02")
			expect.equal(w.panel.render.frames[1].icon.__texture, "Interface\\ICONS\\inv_scroll_02")
			click(rowOf(w.panel, "overview").background)
			click(picker.buttons[3]) -- Rock
			expect.equal(w.prefs().trp3Sections.backgrounds.overview, 4)
			expect.equal(w.panel.render.frames[1].bg.__texture, P.BACKGROUNDS[4].file)
			-- Anything not on the lists is refused.
			expect.falsy(w.ns.TRP3Commands.SetAboutSection(w.ns.ctx, "icon", "overview", "ability_rogue_unknown"))
			expect.falsy(w.ns.TRP3Commands.SetAboutSection(w.ns.ctx, "background", "overview", 2))
			expect.equal(w.prefs().trp3Sections.icons.overview, "inv_scroll_02")
		end)

		t:it("writes nothing to Total RP 3, and read-only saved data refuses changes", function()
			local w = start()
			local before = w.fake.snapshot()
			click(segment(w.panel.template, "frames"))
			click(segment(w.panel.style, "arcane"))
			click(rowOf(w.panel, "motivation").toggle)
			click(rowOf(w.panel, "biography").down)
			w.panel:Refresh(w.view())
			expect.deepEqual(w.fake.snapshot(), before)
			expect.equal(#w.fake.events, 0)
			w.ns.ctx.store.realReadOnly = "test"
			local ok = w.ns.TRP3Commands.SetAboutSection(w.ns.ctx, "on", "developments", true)
			expect.falsy(ok)
			expect.falsy(w.ns.TRP3Commands.SetAboutAccent(w.ns.ctx, "gold"))
			expect.falsy(w.prefs().trp3Sections.on.developments)
		end)

		t:it("fits its card, with the same geometry at window scale 0.7 and 1.4", function()
			local w = start()
			local p = w.panel
			local function snapshot()
				local s = { p:GetWidth(), p:GetHeight(), p.leftWidth, p.rightWidth, p.choices:GetWidth(),
					p.choices:GetHeight(), p.render.scroll:GetWidth(), p.render.scroll:GetHeight(), p.contentHeight }
				for _, row in ipairs(p.rows) do
					s[#s + 1] = row:GetWidth()
					s[#s + 1] = row.titleWidth
				end
				return s
			end
			expect.equal(p.leftWidth + w.ns.TRP3BiographyPanel.GAP + p.rightWidth, W, "the two columns fill the card exactly")
			expect.equal(p.choices:GetHeight(), H)
			expect.truthy(p.render.scroll:GetHeight() + 18 + 8 <= H, "the preview stays inside the card")
			for _, row in ipairs(p.rows) do
				expect.equal(row:GetWidth(), p.contentWidth)
				expect.truthy(row.titleWidth >= 100, "a usable title field: " .. row.titleWidth)
			end
			click(segment(p.template, "frames"))
			for _, row in ipairs(p.rows) do
				expect.truthy(row.titleWidth >= 80, "still usable with the frame pickers: " .. row.titleWidth)
				local right = row.icon:GetWidth() + row.background:GetWidth() + row.up:GetWidth() + row.down:GetWidth() + 16
				expect.truthy(30 + 6 + row.titleWidth + right <= p.contentWidth, "the row's controls fit")
			end
			-- The template choices fit their column.
			local seg = 0
			for _, b in ipairs(p.template.buttons) do seg = seg + b:GetWidth() + 2 end
			expect.truthy(seg <= p.contentWidth + 2)
			local base = snapshot()
			for _, scale in ipairs({ 0.7, 1.4 }) do
				w.parent:SetScale(scale)
				p:Refresh(w.view())
				expect.deepEqual(snapshot(), base, "scale " .. scale)
			end
			-- A narrower card still lays out.
			local narrow = w.ns.TRP3BiographyPanel.Build(w.parent, 640, 400)
			narrow:Refresh(w.view())
			expect.equal(narrow.leftWidth + w.ns.TRP3BiographyPanel.GAP + narrow.rightWidth, 640)
			expect.truthy(narrow.rightWidth >= 260)
		end)
	end)
end
