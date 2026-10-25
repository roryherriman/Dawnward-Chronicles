-- Cosmetic journal themes. Data only: a theme changes colours and border art,
-- never layout, behaviour or character data. See docs/UI_DIRECTION.md.
--
-- Themes are chosen by the player per character. Nothing here is selected
-- from class or race; every new character starts with the neutral theme.
local _, ns = ...

local Themes = {}
ns.Themes = Themes

Themes.DEFAULT = "neutral"

-- Colours are { r, g, b } in 0..1.
--   background  window body (titles, tabs, status line sit on this)
--   panel       reading/writing areas (all body text sits on this)
--   text        body text          muted   dates, labels, hints
--   accent      headings, selected section, focus
--   border      tint for the built-in border art
-- tests/spec/core_themes_spec.lua checks every text colour against both
-- surfaces for a WCAG contrast ratio of at least 4.5:1.
Themes.LIST = {
	{
		id = "neutral",
		name = "Neutral",
		description = "Quiet parchment and ink, for any character.",
		background = { 0.10, 0.09, 0.08 },
		panel = { 0.04, 0.035, 0.03 },
		text = { 0.93, 0.90, 0.84 },
		muted = { 0.72, 0.68, 0.60 },
		accent = { 0.86, 0.74, 0.46 },
		border = { 0.62, 0.57, 0.48 },
	},
	{
		id = "silverhand",
		name = "Silver Hand",
		description = "Gold on deep blue: steadfast and bright.",
		background = { 0.05, 0.07, 0.13 },
		panel = { 0.02, 0.03, 0.07 },
		text = { 0.95, 0.93, 0.86 },
		muted = { 0.70, 0.75, 0.86 },
		accent = { 0.98, 0.80, 0.34 },
		border = { 0.86, 0.70, 0.32 },
	},
	{
		id = "arcane",
		name = "Arcane",
		description = "Violet and blue: curious and otherworldly.",
		background = { 0.08, 0.05, 0.13 },
		panel = { 0.03, 0.02, 0.07 },
		text = { 0.94, 0.92, 0.99 },
		muted = { 0.74, 0.71, 0.89 },
		accent = { 0.80, 0.64, 1.00 },
		border = { 0.56, 0.62, 1.00 },
	},
}

Themes.BY_ID = {}
for _, theme in ipairs(Themes.LIST) do
	Themes.BY_ID[theme.id] = theme
end

function Themes.IsValid(id)
	return type(id) == "string" and Themes.BY_ID[id] ~= nil
end

--- Returns the theme for id, falling back to the default.
function Themes.Get(id)
	return Themes.BY_ID[id] or Themes.BY_ID[Themes.DEFAULT]
end

local function channel(c)
	if c <= 0.03928 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

--- Relative luminance (WCAG 2.x).
function Themes.Luminance(color)
	return 0.2126 * channel(color[1]) + 0.7152 * channel(color[2]) + 0.0722 * channel(color[3])
end

--- Contrast ratio between two colours, 1..21.
function Themes.Contrast(a, b)
	local la, lb = Themes.Luminance(a), Themes.Luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end
