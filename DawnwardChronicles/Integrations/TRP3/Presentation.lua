-- How Dawnward's narrative data is formatted for TRP3, kept apart from the
-- data itself. AboutBlock decides *what* is public; a style decides only
-- how it looks.
--
-- Only markup confirmed in TRP3 3.4.1's source (Core/Utils.lua,
-- convertTextTags and toHTML; docs/TRP3_INTEGRATION.md) is used:
--   {h1}..{h3} headings (optionally :c / :r), {p:c} / {p:r} paragraphs,
--   {col:RRGGBB}...{/col} colour, {icon:<icon name>:<size>} icons.
-- TRP3 has no font tags; headings use TRP3's own heading fonts
-- (RegisterAbout.lua: h1 SystemFont_Shadow_Huge3, h2 Huge1, h3 Large, all
-- white unless a {col} says otherwise). toHTML drops the line break right
-- after a heading, and a blank line between paragraphs shows as one empty
-- line, so sections are separated by one blank line and nothing more.
--
-- v0.10 (Phase 7): every icon and frame background Dawnward writes is on an
-- allowlist checked against the sources (Presentation.ICONS,
-- Presentation.BACKGROUNDS; tests/spec/trp3_presentation_allowlist_spec.lua).
-- Neutral is unchanged, so a profile synced by v0.3 is not rewritten.
-- Silver Hand frames now use background 3 (Marble), which the Classic Era
-- 1.15.9 UI itself uses; background 2 (Bank-Background) appears only in a
-- later client's bank frame and could not be verified for Classic Era.
-- Frames the player restyled in TRP3 keep their own icon and background
-- (AboutDoc's frame planning copies them), so their formatting survives
-- every update. Player text is never changed, only escaped.
--
-- How the About page will look is also modelled here (Presentation.Display)
-- for Dawnward's preview: the same headings, order, frames and colours TRP3
-- draws, as plain data for UI/TRP3Page.lua.
local _, ns = ...

local Presentation = {}
ns.TRP3Presentation = Presentation

Presentation.DEFAULT = "neutral"

Presentation.STYLES = {
	neutral = {
		label = "Neutral",
		heading = "{h3}Chronicle{/h3}",
		momentsHeading = "Defining moments:",
		momentPrefix = "- ",
		stancesHeading = "Where they stand:",
		-- v0.9 full profile: plain headings, TRP3's first background.
		background = 1,
	},
	silverhand = {
		label = "Silver Hand (gold headings, marble frames)",
		heading = "{h3}{col:e6c35c}Chronicle{/col}{/h3}",
		momentsHeading = "{col:e6c35c}Defining moments{/col}",
		momentPrefix = "- ",
		stancesHeading = "{col:e6c35c}Where they stand{/col}",
		color = "e6c35c",
		background = 3,
	},
	arcane = {
		label = "Arcane (violet headings, section icons)",
		heading = "{h3}{icon:INV_Misc_Book_09:18} {col:b89cff}Chronicle{/col}{/h3}",
		momentsHeading = "{col:b89cff}Defining moments{/col}",
		momentPrefix = "- ",
		stancesHeading = "{col:b89cff}Where they stand{/col}",
		color = "b89cff",
		icons = true,
		background = 1,
	},
}

-- Section icons (v0.9 full profile): template 2 frame icons, and inline
-- icons in the Arcane style. Each is one of Total RP 3 3.4.1's own
-- interface icons, the entry TRP3 itself resolves to on Classic Era
-- (Resources/InterfaceIcons.lua takes the first candidate the client has;
-- these are the only or the oldest candidates, shipped for every client).
Presentation.SECTION_ICONS = {
	overview = "inv_misc_book_09",
	appearance = "spell_nature_strength",
	bio = "inv_misc_book_12",
	family = "inv_misc_grouplooking",
	beliefs = "inv_misc_note_06",
	personality = "spell_arcane_mindmastery",
	experiences = "inv_scroll_02",
	notes = "inv_misc_note_06",
}

-- The allowlist: every icon Dawnward names in Total RP 3, with where it was
-- verified (Total RP 3 3.4.1, Resources/InterfaceIcons.lua, unless noted).
-- Keys are lower case (the client does not mind the case of icon paths).
Presentation.ICONS = {
	inv_misc_book_09 = "DirectorySection (only candidate); AboutBlock.FRAME_ICON",
	inv_misc_book_12 = "HistorySection (only candidate)",
	inv_misc_note_06 = "MiscInfoSection (only candidate)",
	spell_nature_strength = "PhysicalSection (older-client candidate)",
	spell_arcane_mindmastery = "TraitSection (only candidate)",
	inv_scroll_02 = "TargetNotes (older-client candidate)",
	inv_misc_grouplooking = "ProfileDefault (only candidate)",
	inv_misc_questionmark = "Default; the 1.15.9 UI's own QuestInfo icon; TraitPlan's trait icon",
}

-- Frame backgrounds Dawnward may give a frame it adds (an index into
-- TRP3's tiled background list, Core/UITools.lua), each texture checked in
-- the Classic Era 1.15.9 UI source.
Presentation.BACKGROUNDS = {
	[1] = { file = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = 64,
		verified = "Classic/LootFrame.lua; SharedXML/Backdrop.lua" },
	[3] = { file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = 256,
		verified = "SharedXML/Classic/SharedUIPanelTemplates.xml" },
	[4] = { file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = 256,
		verified = "SharedXML/Classic/SharedUIPanelTemplates.xml; Classic/FriendsFrame.xml" },
}

-- Template 3's fixed titles and icons, as TRP3 draws them
-- (RegisterAbout.lua showTemplate3, enUS locale; the icons are its
-- PhysicalSection, TraitSection and HistorySection).
Presentation.T3_PARTS = {
	{ slot = "PH", title = "Physical Description", icon = "spell_nature_strength" },
	{ slot = "PS", title = "Personality Traits", icon = "spell_arcane_mindmastery" },
	{ slot = "HI", title = "History", icon = "inv_misc_book_12" },
}

function Presentation.SectionIcon(id)
	return Presentation.SECTION_ICONS[id] or Presentation.SECTION_ICONS.bio
end

--- A section heading line: {h2} (or {h3}) with the style's colour and, in
-- the Arcane style, the section's icon. title is escaped (a player's own
-- heading can never become markup).
function Presentation.SectionHeading(style, title, level, id)
	level = level == 3 and 3 or 2
	local text = Presentation.Escape(title)
	if style.color then
		text = "{col:" .. style.color .. "}" .. text .. "{/col}"
	end
	if style.icons then
		text = "{icon:" .. Presentation.SectionIcon(id) .. ":18} " .. text
	end
	return "{h" .. level .. "}" .. text .. "{/h" .. level .. "}"
end

function Presentation.Get(id)
	return Presentation.STYLES[id] or Presentation.STYLES[Presentation.DEFAULT]
end

-- Braces would be read as TRP3 tags; player text must never become markup.
function Presentation.Escape(s)
	return (s:gsub("{", "("):gsub("}", ")"))
end

--- Lines for one public fact.
function Presentation.FactLine(_, label, statement)
	return label .. ": " .. Presentation.Escape(statement:gsub("\n", " "))
end

function Presentation.MomentLine(style, title)
	return style.momentPrefix .. Presentation.Escape(title:gsub("\n", " "))
end

--- A public stance: "Subject: persona" (plus the conviction only when the
-- player made it public too).
function Presentation.StanceLine(style, stance)
	local text = stance.persona or stance.conviction
	if stance.persona and stance.conviction then
		text = stance.persona .. " (privately: " .. stance.conviction .. ")"
	end
	return style.momentPrefix .. Presentation.Escape((stance.subject .. ": " .. text):gsub("\n", " "))
end

--- Preview model ------------------------------------------------------------------

--- WoW text for one line of TRP3 markup: {col:hex} ... {/col} become colour
-- codes, {icon:name:size} an inline icon (allowlisted icons only; any other
-- shows as its name), and a literal "|" stays literal. Pure.
function Presentation.DisplayText(line)
	line = tostring(line or ""):gsub("|", "||")
	line = line:gsub("{col:(%x%x%x%x%x%x)}", "|cff%1"):gsub("{/col}", "|r")
	line = line:gsub("{icon:([^:}]+):(%d+)}", function(icon, size)
		if Presentation.ICONS[icon:lower()] then
			return "|TInterface\\ICONS\\" .. icon .. ":" .. size .. "|t"
		end
		return icon
	end)
	return line
end

--- One text slot as the blocks TRP3 shows: headings ({h1}..{h3} or "#"
-- lines, as toHTML reads them) and paragraphs (runs of lines between blank
-- lines, their own line breaks kept). Returns { { kind = "h2" | "p", text },
-- ... } with display text. Pure.
function Presentation.DisplayItems(text)
	local items, para = {}, nil
	local function flush()
		if para then
			items[#items + 1] = { kind = "p", text = table.concat(para, "\n") }
			para = nil
		end
	end
	for line in (tostring(text or ""):gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
		local level, title = line:match("^%s*{h(%d)[:%a]*}(.-){/h%d}%s*$")
		if not level then
			local hashes, rest = line:match("^(#+)(.-)$")
			if hashes then
				level, title = tostring(#hashes), rest:match("^%s*(.-)%s*$")
			end
		end
		if level then
			flush()
			items[#items + 1] = { kind = "h" .. math.min(3, math.max(1, tonumber(level))),
				text = Presentation.DisplayText(title) }
		elseif line:match("%S") then
			para = para or {}
			para[#para + 1] = Presentation.DisplayText(line)
		else
			flush()
		end
	end
	flush()
	return items
end

--- What TRP3 will show for a rendered About (AboutDoc.Render) in template
-- 1, 2 or 3, as blocks in TRP3's order: template 1 one page; template 2
-- one frame per entry { icon, background, items }; template 3 the titled
-- parts that have text. Pure.
function Presentation.Display(rendered, template)
	local blocks = {}
	rendered = rendered or {}
	if template == 2 then
		for _, frame in ipairs(rendered.frames or {}) do
			blocks[#blocks + 1] = { kind = "frame", icon = frame.IC, background = frame.BK,
				items = Presentation.DisplayItems(frame.TX) }
		end
	elseif template == 3 then
		for _, part in ipairs(Presentation.T3_PARTS) do
			local text = rendered[part.slot]
			if type(text) == "string" and text:match("%S") then
				blocks[#blocks + 1] = { kind = "part", title = part.title, icon = part.icon,
					items = Presentation.DisplayItems(text) }
			end
		end
	else
		blocks[1] = { kind = "page", items = Presentation.DisplayItems(rendered.T1 or rendered.text) }
	end
	return blocks
end
