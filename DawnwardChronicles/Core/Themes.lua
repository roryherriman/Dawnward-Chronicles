-- Cosmetic journal themes. Data only: a theme changes colours and border art,
-- never layout, behaviour or character data. See docs/UI_DIRECTION.md.
--
-- Themes are chosen by the player per character. Nothing here is selected
-- from class, race or faction; every new character starts with Classic
-- Dawnward. Saved IDs of the v0.2 themes stay valid.
local _, ns = ...

local Themes = {}
ns.Themes = Themes

Themes.DEFAULT = "dawnward"

-- "#rrggbb" -> { r, g, b } in 0..1.
local function hex(s)
	return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255 }
end

-- Colours are { r, g, b } in 0..1. Roles (docs/design/UI_DESIGN_V06.md):
--   background    window body: header, navigation, footer
--   panel         content area (all reading text sits on this)
--   surface       raised elements: cards, rows, buttons, inputs
--   surfaceHover  a hovered surface
--   edge          1 px borders and dividers
--   ornament      frame line and corner accents
--   text          body text          muted   dates, labels, hints
--   accent        headings, selected navigation, focus
--   accentText    text on an accent-filled (primary) button
--   danger        destructive actions
--   border        legacy tint (v0.5 code)
-- tests/spec/core_themes_spec.lua checks every text colour for a WCAG
-- contrast of at least 4.5:1 on background, panel and surfaces.
Themes.LIST = {
	{
		id = "dawnward",
		name = "Classic Dawnward",
		description = "Charcoal and deep navy with antique gold. The default.",
		background = hex("#141821"), panel = hex("#0D1018"), surface = hex("#1B2130"),
		surfaceHover = hex("#242C3E"), edge = hex("#2E3749"), ornament = hex("#A88B52"),
		text = hex("#ECE6D8"), muted = hex("#A8A391"), accent = hex("#D6B66E"), accentText = hex("#15130E"),
		danger = hex("#E8837A"), border = hex("#A88B52"),
	},
	{
		id = "lightbound",
		name = "Lightbound",
		description = "Warm charcoal with muted ivory and pale gold.",
		background = hex("#1C1B18"), panel = hex("#141310"), surface = hex("#25231F"),
		surfaceHover = hex("#2F2C27"), edge = hex("#3D3930"), ornament = hex("#C9B98C"),
		text = hex("#F2ECDE"), muted = hex("#B7AE99"), accent = hex("#E7DCBC"), accentText = hex("#1A1812"),
		danger = hex("#E8837A"), border = hex("#C9B98C"),
	},
	{
		id = "shadowbound",
		name = "Shadowbound",
		description = "Charcoal with restrained crimson.",
		background = hex("#151315"), panel = hex("#0D0C0E"), surface = hex("#1D1A1E"),
		surfaceHover = hex("#272328"), edge = hex("#352E33"), ornament = hex("#8E3A40"),
		text = hex("#ECE4E2"), muted = hex("#ABA1A1"), accent = hex("#D9737A"), accentText = hex("#140B0C"),
		danger = hex("#F09A8C"), border = hex("#8E3A40"),
	},
	-- The v0.2 themes, kept so saved characters look as they chose.
	{
		id = "neutral",
		name = "Neutral",
		description = "Quiet parchment and ink (v0.2).",
		background = { 0.10, 0.09, 0.08 },
		panel = { 0.04, 0.035, 0.03 },
		text = { 0.93, 0.90, 0.84 },
		muted = { 0.72, 0.68, 0.60 },
		accent = { 0.86, 0.74, 0.46 },
		border = { 0.62, 0.57, 0.48 },
		surface = hex("#221E1A"), surfaceHover = hex("#2C2721"), edge = hex("#3A332B"), ornament = hex("#9E917A"),
		accentText = hex("#17130B"), danger = hex("#E8837A"),
	},
	{
		id = "silverhand",
		name = "Silver Hand",
		description = "Gold on deep blue: steadfast and bright (v0.2).",
		background = { 0.05, 0.07, 0.13 },
		panel = { 0.02, 0.03, 0.07 },
		text = { 0.95, 0.93, 0.86 },
		muted = { 0.70, 0.75, 0.86 },
		accent = { 0.98, 0.80, 0.34 },
		border = { 0.86, 0.70, 0.32 },
		surface = hex("#141B30"), surfaceHover = hex("#1C253F"), edge = hex("#2A3556"), ornament = hex("#DBB352"),
		accentText = hex("#12100A"), danger = hex("#F09A8C"),
	},
	{
		id = "arcane",
		name = "Arcane",
		description = "Violet and blue: curious and otherworldly (v0.2).",
		background = { 0.08, 0.05, 0.13 },
		panel = { 0.03, 0.02, 0.07 },
		text = { 0.94, 0.92, 0.99 },
		muted = { 0.74, 0.71, 0.89 },
		accent = { 0.80, 0.64, 1.00 },
		border = { 0.56, 0.62, 1.00 },
		surface = hex("#1C1430"), surfaceHover = hex("#261C40"), edge = hex("#352957"), ornament = hex("#8F9EFF"),
		accentText = hex("#120A1C"), danger = hex("#F09A8C"),
	},
}

-- Every role a theme defines (tests check all of them).
Themes.ROLES = { "background", "panel", "surface", "surfaceHover", "edge", "ornament", "text", "muted", "accent",
	"accentText", "danger", "border" }

-- Visibility labels use fixed meanings across themes, so "Secret" always
-- looks like a warning. Checked for contrast on every theme's panel.
Themes.VISIBILITY_COLORS = {
	public = { 0.55, 0.86, 0.55 },
	private = { 0.78, 0.78, 0.78 },
	secret = { 0.98, 0.58, 0.48 },
}

Themes.VISIBILITY_LABELS = { public = "Public", private = "Private", secret = "Secret" }

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
