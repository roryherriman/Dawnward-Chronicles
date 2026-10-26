-- How Dawnward's narrative data is formatted for TRP3, kept apart from the
-- data itself. AboutBlock decides *what* is public; a style decides only
-- how it looks.
--
-- Only markup confirmed in TRP3 3.4.1's source (Core/Utils.lua,
-- convertTextTags and toHTML; docs/TRP3_INTEGRATION.md) is used:
--   {h1}..{h3} headings (optionally :c / :r), {p:c} / {p:r} paragraphs,
--   {col:RRGGBB}...{/col} colour, {icon:<icon name>:<size>} icons.
-- TRP3 has no font tags; headings use TRP3's own heading fonts. How each
-- style renders in game is not yet verified (L3).
--
-- "neutral" is the default and produces exactly the v0.3 block, so a
-- profile synced by v0.3 is not rewritten by an upgrade.
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
	},
	silverhand = {
		label = "Silver Hand (gold headings)",
		heading = "{h3}{col:e6c35c}Chronicle{/col}{/h3}",
		momentsHeading = "{col:e6c35c}Defining moments{/col}",
		momentPrefix = "- ",
	},
	arcane = {
		label = "Arcane (violet headings, book icon)",
		heading = "{h3}{icon:INV_Misc_Book_09:18} {col:b89cff}Chronicle{/col}{/h3}",
		momentsHeading = "{col:b89cff}Defining moments{/col}",
		momentPrefix = "- ",
	},
}

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
