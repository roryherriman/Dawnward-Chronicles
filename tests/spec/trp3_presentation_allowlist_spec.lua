-- L1 (v0.10, Phase 7): how Dawnward's content looks in Total RP 3. Every
-- icon, background and markup tag Dawnward writes is on an allowlist
-- verified in Total RP 3 3.4.1's source (Core/Utils.lua convertTextTags and
-- toHTML, Resources/InterfaceIcons.lua, Core/UITools.lua) and the Classic
-- Era 1.15.9 UI source; the biography stays word for word in every style
-- and template; the preview model mirrors what Total RP 3 draws.
local Loader = require("support.loader")

-- The verified lists, written out here so a change to the code's lists is
-- a deliberate, reviewed change to this test as well.
local VERIFIED_ICONS = {
	inv_misc_book_09 = true,         -- TRP3 DirectorySection
	inv_misc_book_12 = true,         -- TRP3 HistorySection
	inv_misc_note_06 = true,         -- TRP3 MiscInfoSection
	spell_nature_strength = true,    -- TRP3 PhysicalSection (older clients)
	spell_arcane_mindmastery = true, -- TRP3 TraitSection
	inv_scroll_02 = true,            -- TRP3 TargetNotes (older clients)
	inv_misc_grouplooking = true,    -- TRP3 ProfileDefault
	inv_misc_questionmark = true,    -- TRP3 Default; 1.15.9 QuestInfo
}
local VERIFIED_BACKGROUNDS = {
	[1] = "Interface\\DialogFrame\\UI-DialogBox-Background",
	[3] = "Interface\\FrameGeneral\\UI-Background-Marble",
	[4] = "Interface\\FrameGeneral\\UI-Background-Rock",
}
-- Tags TRP3 3.4.1 converts (structureTags and convertTextTag).
local TAG_PATTERNS = { "^h[123]$", "^/h[123]$", "^h[123]:[cr]$", "^p:[cr]$", "^/p$", "^col:%x%x%x%x%x%x$", "^/col$",
	"^icon:[^:]+:%d+$" }

local BIOGRAPHY = "# The fall of Lordaeron\nWhen the grain carts stopped, she left {quietly}.\n\n"
	.. "She hid | waited.\n## Stormwind\nA new oath."

local function public(style)
	return {
		trp3Style = style,
		fields = {
			summary = { value = "A quiet paladin.", visibility = "public" },
			appearance = { value = "Tall, a silver scar.", visibility = "public" },
			motivation = { value = "To keep a promise.", visibility = "public" },
		},
		biography = { text = BIOGRAPHY },
		facts = {
			{ category = "belief", statement = "Protect the weak" },
			{ category = "trait", statement = "Stubborn" },
			{ category = "origin", statement = "Born in Stormwind" },
		},
		family = { { relation = "mother", name = "Elda", status = "alive" } },
		stances = { { subject = "Stormwind", persona = "Loyal" } },
		history = { { when = "Year 20", text = "Took the oath" } },
		moments = {},
	}
end

local function tagsOf(text, out)
	for tag in text:gmatch("{(.-)}") do out[#out + 1] = tag end
	return out
end

return function(t, expect)
	local ns = Loader.WithTRP3()
	local P, Doc = ns.TRP3Presentation, ns.TRP3AboutDoc

	t:describe("TRP3 presentation: verified icons, backgrounds and markup (v0.10, L1)", function()
		t:it("the code's lists are exactly the verified ones", function()
			for name in pairs(P.ICONS) do
				expect.truthy(VERIFIED_ICONS[name], "unverified icon on the allowlist: " .. name)
			end
			for index, bk in pairs(P.BACKGROUNDS) do
				expect.equal(bk.file, VERIFIED_BACKGROUNDS[index], "background " .. index)
			end
			for _, icon in pairs(P.SECTION_ICONS) do
				expect.truthy(P.ICONS[icon:lower()], icon)
			end
			for _, part in ipairs(P.T3_PARTS) do
				expect.truthy(P.ICONS[part.icon:lower()], part.icon)
			end
			expect.truthy(P.ICONS[ns.TRP3AboutBlock.FRAME_ICON:lower()], "the summary frame's icon")
			expect.truthy(P.BACKGROUNDS[ns.TRP3AboutBlock.FRAME_BACKGROUND], "the summary frame's background")
			expect.truthy(P.ICONS[ns.TRP3TraitPlan.ICON:lower()], "Dawnward's trait icon")
			expect.truthy(P.ICONS[ns.Glance.DEFAULT_ICON:lower()], "the At First Glance default icon")
		end)

		t:it("every style's background is verified for Classic Era (Silver Hand: Marble)", function()
			for id, style in pairs(P.STYLES) do
				expect.truthy(P.BACKGROUNDS[style.background], id .. ": background " .. tostring(style.background))
			end
			expect.equal(P.STYLES.silverhand.background, 3)
			expect.equal(P.STYLES.neutral.background, 1)
		end)

		t:it("every template and style writes only verified icons, backgrounds and tags", function()
			for styleId in pairs(P.STYLES) do
				local doc = Doc.Build(public(styleId))
				for template = 1, 3 do
					local r = Doc.Render(doc, template, styleId)
					local texts = {}
					if template == 2 then
						for _, f in ipairs(r.frames) do
							texts[#texts + 1] = f.TX
							expect.truthy(P.ICONS[f.IC:lower()], styleId .. " frame icon " .. f.IC)
							expect.truthy(P.BACKGROUNDS[f.BK], styleId .. " frame background " .. tostring(f.BK))
						end
					else
						for _, k in ipairs({ "T1", "PH", "PS", "HI" }) do
							if r[k] then texts[#texts + 1] = r[k] end
						end
					end
					for _, text in ipairs(texts) do
						for _, tag in ipairs(tagsOf(text, {})) do
							local ok = false
							for _, pattern in ipairs(TAG_PATTERNS) do
								if tag:match(pattern) then ok = true end
							end
							-- The player's own biography is kept as written, tags and all.
							ok = ok or BIOGRAPHY:find("{" .. tag .. "}", 1, true) ~= nil
							expect.truthy(ok, styleId .. " T" .. template .. ": unsupported tag {" .. tag .. "}")
							local icon = tag:match("^icon:([^:]+):")
							if icon then expect.truthy(P.ICONS[icon:lower()], "icon " .. icon) end
						end
					end
				end
			end
		end)

		t:it("the biography stays word for word in every style and template (the player's own tags included)", function()
			for styleId in pairs(P.STYLES) do
				for template = 1, 3 do
					local r = Doc.Render(Doc.Build(public(styleId)), template, styleId)
					local all = template == 2 and "" or table.concat({ r.T1 or "", r.PH or "", r.PS or "", r.HI or "" },
						"\n")
					for _, f in ipairs(r.frames or {}) do all = all .. "\n" .. f.TX end
					for _, line in ipairs({ "When the grain carts stopped, she left {quietly}.", "She hid | waited.",
						"A new oath." }) do
						expect.truthy(all:find(line, 1, true), styleId .. " T" .. template .. ": " .. line)
					end
					expect.truthy(all:find("When the grain carts stopped, she left {quietly}.\n\nShe hid | waited.", 1,
						true), "the paragraph break is kept")
				end
			end
		end)

		t:it("Neutral is unchanged, so a profile synced earlier is not rewritten", function()
			expect.equal(P.SectionHeading(P.Get("neutral"), "Family", 2, "family"), "{h2}Family{/h2}")
			expect.equal(P.STYLES.neutral.heading, "{h3}Chronicle{/h3}")
		end)
	end)

	t:describe("TRP3 presentation: the preview model mirrors Total RP 3 (v0.10, L1)", function()
		t:it("reads headings and paragraphs as toHTML does", function()
			local items = P.DisplayItems("{h2}Family{/h2}\nMother: Elda\nFather: Tor\n\nSecond paragraph\n# Old\nx")
			expect.equal(#items, 5)
			expect.deepEqual({ items[1].kind, items[1].text }, { "h2", "Family" })
			expect.deepEqual({ items[2].kind, items[2].text }, { "p", "Mother: Elda\nFather: Tor" })
			expect.equal(items[3].text, "Second paragraph")
			expect.deepEqual({ items[4].kind, items[4].text }, { "h1", "Old" })
		end)

		t:it("turns colour and icon tags into the client's own codes, and keeps a literal bar literal", function()
			expect.equal(P.DisplayText("{col:e6c35c}Family{/col}"), "|cffe6c35cFamily|r")
			expect.equal(P.DisplayText("{icon:inv_misc_book_12:18} Bio"), "|TInterface\\ICONS\\inv_misc_book_12:18|t Bio")
			expect.equal(P.DisplayText("{icon:Not_A_Verified_Icon:18} x"), "Not_A_Verified_Icon x")
			expect.equal(P.DisplayText("a | b"), "a || b")
		end)

		t:it("keeps Total RP 3's order: one page, one frame per section, or the three titled parts", function()
			local doc = Doc.Build(public("arcane"))
			local page = P.Display(Doc.Render(doc, 1, "arcane"), 1)
			expect.equal(#page, 1)
			expect.equal(page[1].items[1].kind, "h2")
			local frames = P.Display(Doc.Render(doc, 2, "arcane"), 2)
			expect.equal(#frames, #doc)
			for i, f in ipairs(frames) do
				expect.equal(f.kind, "frame")
				expect.truthy(f.items[1].text:find(doc[i].title, 1, true), doc[i].title)
			end
			local parts = P.Display(Doc.Render(doc, 3, "arcane"), 3)
			local titles = {}
			for _, part in ipairs(parts) do titles[#titles + 1] = part.title end
			expect.deepEqual(titles, { "Physical Description", "Personality Traits", "History" })
		end)

		t:it("the profile preview window lays the About page out as Total RP 3 does", function()
			local lines = ns.TRP3Commands.PlainLines(P.DisplayItems("{h2}{col:e6c35c}Family{/col}{/h2}\nMother\n\nNext"))
			expect.deepEqual(lines, { "-- Family --", "Mother", "", "Next" })
		end)
	end)
end
