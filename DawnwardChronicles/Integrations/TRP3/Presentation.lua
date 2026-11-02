-- How Dawnward's narrative data is formatted for TRP3, kept apart from the
-- data itself. AboutDoc decides *what* is published; a style decides only
-- how it looks.
--
-- Only markup confirmed in TRP3 3.4.1's source (Core/Utils.lua,
-- convertTextTags and toHTML; docs/TRP3_INTEGRATION.md) is used:
--   {h1}..{h3} headings (optionally :c / :r), {p:c} / {p:r} paragraphs,
--   {col:RRGGBB}...{/col} colour, {icon:<icon name>:<size>} icons.
-- TRP3 has no font tags and no divider (toHTML's structureTags are only
-- h1-h3 and p; SimpleHTML has no <hr>), so sections are separated by their
-- heading and one blank line. toHTML drops the line break right after a
-- heading (its "()>?()\n" rule), and a blank line between paragraphs shows
-- as one empty line.
--
-- Colours (v0.10.1). RegisterAbout.lua setupHTMLFonts (lines 67-75) gives
-- the About text TRP3's own fonts: paragraphs TRP3_AboutParagraphFont, a
-- copy of SystemFont_Shadow_Med1 (line 55), headings h1-h3 Huge3/Huge1/
-- Large. It sets h1, h2 and h3 to white (SetTextColor, lines 73-75) but
-- never sets the paragraph colour, so body text keeps the system font's own
-- colour: the game's normal gold (NORMAL_FONT_COLOR, 1, 0.82, 0). That is
-- the bright yellow the owner saw on every line Dawnward wrote. The only
-- colour mechanism the About text has is the {col:RRGGBB} tag, which
-- convertTextTag (Utils.lua 441-455) turns into |cffRRGGBB ... |r AFTER the
-- HTML is built, so it colours text inside a paragraph but cannot span
-- block elements. Dawnward therefore wraps every non-empty body line it
-- writes in its style's body colour (a neutral ivory or parchment), and
-- re-opens it after a {/col} of the player's own. With TRP3's high
-- contrast option, convertTextToHTML strips every {col} tag (lines
-- 115-127), and the text shows in TRP3's own colours, as the player chose.
--
-- v0.10 (Phase 7): every icon and frame background Dawnward writes is on an
-- allowlist checked against the sources (Presentation.ICONS,
-- Presentation.BACKGROUNDS; tests/spec/trp3_presentation_allowlist_spec.lua).
-- Silver Hand frames use background 3 (Marble), which the Classic Era
-- 1.15.9 UI itself uses; background 2 (Bank-Background) appears only in a
-- later client's bank frame and could not be verified for Classic Era.
-- Frames the player restyled in TRP3 keep their own icon and background
-- (AboutDoc's frame planning copies them), so their formatting survives
-- every update. Player text is never changed, only escaped.
--
-- How the About page will look is also modelled here (Presentation.Display)
-- for Dawnward's preview: the same headings, order, frames and colours TRP3
-- draws, as plain data for UI/TRP3BiographyPanel.lua and UI/TRP3Page.lua.
local _, ns = ...

local Presentation = {}
ns.TRP3Presentation = Presentation

Presentation.DEFAULT = "neutral"

-- Each style: body (the paragraph colour, always set: see above), color
-- (section titles; nil keeps TRP3's white), chapter (the player's own
-- chapter titles; nil keeps TRP3's white), background (template 2 frames),
-- icons (an inline icon before each section title). The heading/moments/
-- stances strings are the v0.3 summary block's (AboutBlock.Compose).
Presentation.STYLES = {
	neutral = {
		label = "Neutral",
		heading = "{h3}Chronicle{/h3}",
		momentsHeading = "Defining moments:",
		momentPrefix = "- ",
		stancesHeading = "Where they stand:",
		body = "e8e0d0",       -- soft ivory
		background = 1,
	},
	silverhand = {
		label = "Silver Hand (gold headings, marble frames)",
		heading = "{h3}{col:e6c35c}Chronicle{/col}{/h3}",
		momentsHeading = "{col:e6c35c}Defining moments{/col}",
		momentPrefix = "- ",
		stancesHeading = "{col:e6c35c}Where they stand{/col}",
		color = "e6c35c",      -- gold section titles
		chapter = "d9c38a",    -- muted gold chapter titles
		body = "efe4c9",       -- warm parchment
		background = 3,
	},
	arcane = {
		label = "Arcane (violet headings, section icons)",
		heading = "{h3}{icon:INV_Misc_Book_09:18} {col:b89cff}Chronicle{/col}{/h3}",
		momentsHeading = "{col:b89cff}Defining moments{/col}",
		momentPrefix = "- ",
		stancesHeading = "{col:b89cff}Where they stand{/col}",
		color = "c4adff",      -- a lighter violet, readable on TRP3's dark backgrounds
		chapter = "b6a6dc",
		body = "e6e1f0",       -- cool ivory
		icons = true,
		background = 1,
	},
}

-- Heading colours the player may choose instead of the style's
-- (StorySchema.TRP3_ACCENTS; "style" keeps the style's own).
Presentation.ACCENTS = {
	{ id = "style", label = "Style" },
	{ id = "gold", label = "Gold", hex = "e6c35c" },
	{ id = "silver", label = "Silver", hex = "d6dce6" },
	{ id = "crimson", label = "Crimson", hex = "e08a7c" },
	{ id = "azure", label = "Azure", hex = "8fbfee" },
	{ id = "violet", label = "Violet", hex = "c4adff" },
	{ id = "verdant", label = "Verdant", hex = "a3d69d" },
}
Presentation.ACCENT_BY_ID = {}
for _, a in ipairs(Presentation.ACCENTS) do Presentation.ACCENT_BY_ID[a.id] = a end

--- The style to render with: the named style, its heading colours replaced
-- by the accent when one is chosen. Returns a new table. Pure.
function Presentation.Resolve(styleId, accentId)
	local base = Presentation.Get(styleId)
	local out = {}
	for k, v in pairs(base) do out[k] = v end
	local accent = Presentation.ACCENT_BY_ID[accentId or "style"]
	if accent and accent.hex then
		out.color, out.chapter = accent.hex, accent.hex
	end
	return out
end

-- Section icons: the default template 2 frame icon of each About section,
-- and the inline icon in the Arcane style. Each is one of Total RP 3
-- 3.4.1's own interface icons, the entry TRP3 itself resolves to on Classic
-- Era (Resources/InterfaceIcons.lua takes the first candidate the client
-- has; these are the only or the oldest candidates, shipped for every
-- client). "bio" is the v0.9/v0.10 name of the biography.
Presentation.SECTION_ICONS = {
	overview = "inv_misc_book_09",
	biography = "inv_misc_book_12",
	bio = "inv_misc_book_12",
	appearance = "spell_nature_strength",
	personality = "spell_arcane_mindmastery",
	motivation = "inv_misc_note_06",
	developments = "inv_scroll_02",
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

-- Readable names for the allowlisted icons and backgrounds (the panel's picker).
Presentation.ICON_CHOICES = {
	{ id = "inv_misc_book_09", label = "Closed book" },
	{ id = "inv_misc_book_12", label = "Old tome" },
	{ id = "inv_scroll_02", label = "Scroll" },
	{ id = "inv_misc_note_06", label = "Note" },
	{ id = "spell_nature_strength", label = "Strength" },
	{ id = "spell_arcane_mindmastery", label = "Mind" },
	{ id = "inv_misc_grouplooking", label = "Company" },
}
Presentation.BACKGROUND_CHOICES = {
	{ id = 1, label = "Dialog" },
	{ id = 3, label = "Marble" },
	{ id = 4, label = "Rock" },
}

function Presentation.SectionIcon(id)
	return Presentation.SECTION_ICONS[id] or Presentation.SECTION_ICONS.biography
end

--- An allowlisted icon: the chosen one when it is on the list, else the
-- section's default. Pure.
function Presentation.SafeIcon(chosen, id)
	if type(chosen) == "string" and Presentation.ICONS[chosen:lower()] then
		return chosen:lower()
	end
	return Presentation.SectionIcon(id)
end

--- An allowlisted background index: the chosen one, else the style's. Pure.
function Presentation.SafeBackground(chosen, style)
	if Presentation.BACKGROUNDS[chosen] then
		return chosen
	end
	return style and Presentation.BACKGROUNDS[style.background] and style.background or 1
end

--- A section heading line: {h2} (or {h3}) with the style's colour and, in
-- the Arcane style, the section's icon. title is escaped (a player's own
-- heading can never become markup). icon: the section's chosen icon.
function Presentation.SectionHeading(style, title, level, id, icon)
	level = level == 3 and 3 or 2
	local text = Presentation.Escape(title)
	if style.color then
		text = "{col:" .. style.color .. "}" .. text .. "{/col}"
	end
	if style.icons then
		text = "{icon:" .. Presentation.SafeIcon(icon, id) .. ":18} " .. text
	end
	return "{h" .. level .. "}" .. text .. "{/h" .. level .. "}"
end

--- A chapter heading from the player's own biography ({h3}, the style's
-- chapter colour). Escaped like every title.
function Presentation.ChapterHeading(style, title)
	local text = Presentation.Escape(title)
	if style.chapter then
		text = "{col:" .. style.chapter .. "}" .. text .. "{/col}"
	end
	return "{h3}" .. text .. "{/h3}"
end

-- The player's own block markup in a body line, as toHTML (Core/Utils.lua,
-- TRP3 3.4.1) turns it into HTML elements BEFORE the colour tags become
-- |c...|r (convertTextTags runs last, line 709): structureTags (lines
-- 475-485: {h1}..{h3} with :c/:r, {/hN}, {p}, {p:c}, {p:r}, {/p}),
-- IMAGE_PATTERN (line 503, written as "</P><img .../><P>", line 507) and a
-- markdown image with a texture path (lines 662-675, the same tag). A
-- colour opened before one of these ends at it, so the text after it would
-- fall back to TRP3's gold. Returns the tag at position i of line, or nil.
local IMAGE_TAG_PATTERN = "^{img%:[^:]+%:[^:]+%:[^:}]+%:?[^:}]*%}"
local BLOCK_TAGS = { "^{h%d}", "^{h%d:[cr]}", "^{/h%d}", "^{p}", "^{p:[cr]}", "^{/p}", IMAGE_TAG_PATTERN }
local function blockTagAt(line, i)
	local c = line:sub(i, i)
	if c == "{" then
		for _, pattern in ipairs(BLOCK_TAGS) do
			local s, e = line:find(pattern, i)
			if s then return line:sub(s, e) end
		end
	elseif c == "!" then
		local s, e, icon = line:find("^!%[(.-)%]%(.-%)", i)
		if s and icon:find("\\", 1, true) then return line:sub(s, e) end
	end
	return nil
end

--- Body text in the style's paragraph colour: every run of text with
-- something visible is wrapped in {col:body}...{/col} (a colour cannot
-- span TRP3's block elements, see above), and re-opened after any {/col}
-- the text already has, so the rest never falls back to TRP3's gold. A run
-- is the text between the player's own block tags (paragraphs, headings,
-- images: blockTagAt), so the colour opens inside a {p:c} paragraph and
-- closes before its {/p}; text inside a heading of the player's keeps
-- TRP3's heading colour. Blank and whitespace-only lines stay exactly as
-- they are; nothing else changes.
function Presentation.Body(style, text)
	local body = style and style.body
	if not body then
		return text
	end
	local open = "{col:" .. body .. "}"
	local inHeading = false
	local function colour(run)
		if inHeading or not run:match("%S") then
			return run
		end
		return open .. run:gsub("{/col}", "{/col}" .. open) .. "{/col}"
	end
	local out = {}
	for line in (tostring(text or ""):gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
		if line:match("%S") then
			local parts, runStart, i = {}, 1, 1
			while i <= #line do
				local tag = blockTagAt(line, i)
				if tag then
					parts[#parts + 1] = colour(line:sub(runStart, i - 1))
					parts[#parts + 1] = tag
					if tag:find("^{h%d") then
						inHeading = true
					elseif tag:find("^{/h%d") then
						inHeading = false
					end
					i = i + #tag
					runStart = i
				else
					i = i + 1
				end
			end
			parts[#parts + 1] = colour(line:sub(runStart))
			out[#out + 1] = table.concat(parts)
		else
			out[#out + 1] = line
		end
	end
	return table.concat(out, "\n")
end

--- The text a reader sees: Dawnward's colour tags removed (the player's
-- own braces are escaped or kept as written, so only markup goes). Pure.
function Presentation.Visible(text)
	return (tostring(text or ""):gsub("{col:%x%x%x%x%x%x}", ""):gsub("{/col}", ""))
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
