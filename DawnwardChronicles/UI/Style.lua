-- The Dawnward design system: tokens, theme painting and frame chrome.
-- Values follow the approved design system (docs/design/mockups/design-system.png
-- and its source DesignSystem.dc.html); see docs/design/UI_DESIGN_V07.md and
-- docs/design/audit/shell-and-components.md.
--
-- Components register a painter once (Style.Register); Style.Apply(theme)
-- repaints every registered object, and a new object is painted with the
-- current theme straight away. Modules therefore never hand-colour buttons,
-- inputs, cards or frames. Everything is drawn from solid-colour textures
-- (round shapes use the game's own circular portrait mask): no art files
-- ship, so every theme recolours the whole interface.
local _, ns = ...
local Themes = ns.Themes

local Style = {}
ns.Style = Style

--- Tokens -------------------------------------------------------------------------

-- Spacing steps of the design system: 4 · 8 · 12 · 16 · 20 · 28.
Style.SPACE = { xs = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 28 }

-- Control heights of the design system. New and reworked layouts use these.
--   compact 30 (buttons inside cards, rail buttons, segmented items)
--   standard 36 (toolbar and dialog buttons, inputs, the close button)
--   nav 44 (rail navigation)   chip 24 (status pills)   chipSmall 20
Style.CONTROL = { compact = 30, standard = 36, nav = 44, input = 36, icon = 36, segment = 30, chip = 24,
	chipSmall = 20, badge = 22, progress = 6 }

-- Defaults used when a caller gives no size. Kept at their v0.6 values because
-- screens that rely on them lay themselves out around them; pass a
-- Style.CONTROL height to get the design-system size.
Style.SIZE = { button = 22, compact = 20, nav = 44, segment = 22, input = 22, icon = 22 }

-- The smallest text size any Dawnward style uses (UI units).
Style.MIN_TEXT = 13

-- Text roles: font template and colour (a theme role or a Style.Tones key).
Style.TEXT = {
	title = { font = "GameFontNormalLarge", color = "heading" },
	eyebrow = { font = "GameFontNormalSmall", color = "ornament" },
	heading = { font = "GameFontNormal", color = "label" },
	body = { font = "GameFontHighlight", color = "text" },
	reading = { font = "GameFontHighlight", color = "reading" },
	muted = { font = "GameFontHighlightSmall", color = "muted" },
	small = { font = "GameFontHighlightSmall", color = "text" },
	accent = { font = "GameFontNormal", color = "accent" },
	danger = { font = "GameFontHighlightSmall", color = "dangerText" },
}

--- Colours -----------------------------------------------------------------------

--- a mixed toward b by t (0..1). Pure.
function Style.Mix(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

--- color mixed toward white by amount (0..1). Pure.
function Style.Lighten(color, amount)
	return Style.Mix(color, { 1, 1, 1 }, amount)
end

-- Secondary tones, derived from a theme's roles so every theme gets them. The
-- formulas are tuned so Classic Dawnward lands on the design system's values
-- (hex in the comments); tests/spec/ui_components_spec.lua checks contrast.
local WHITE = { 1, 1, 1 }
local function deriveTones(t)
	local text, muted, accent, edge = t.text, t.muted, t.accent, t.edge
	return {
		heading = Style.Mix(text, WHITE, 0.3),          -- F5EEDD screen and card titles
		reading = Style.Mix(text, muted, 0.15),         -- E4DCCB story text
		label = Style.Mix(accent, text, 0.4),           -- D8C49A field labels, the rail's title
		ghostText = Style.Mix(text, muted, 0.25),       -- D9D2C2 ghost button text
		navText = Style.Mix(text, muted, 0.5),          -- C9C2B2 rail navigation
		accentBright = Style.Lighten(accent, 0.3),      -- F0D08E primary edge, gold chips, dates
		edgeStrong = Style.Lighten(edge, 0.1),          -- 3E4C66 secondary button edge
		selectedFill = Style.Lighten(t.surfaceHover, 0.05), -- 2A3346 selected segment
		selectedEdge = Style.Lighten(edge, 0.18),       -- 4A5874 selected segment, hovered card
		cardHover = Style.Mix(t.surface, t.surfaceHover, 0.5), -- 1A2230 hovered card
		field = Style.Mix(t.background, t.panel, 0.3),  -- 0F141D input well
		fieldFocus = Style.Mix(t.background, t.surfaceHover, 0.3), -- 141B27 focused input
		fieldEdge = Style.Lighten(edge, 0.06),          -- 33405A input edge
		dangerText = Style.Lighten(t.danger, 0.25),     -- F0A39B danger button text
		dangerEdge = Style.Mix(t.background, t.danger, 0.33), -- 5E3236 danger button edge
		track = Style.Mix(edge, t.background, 0.3),     -- 232C3D progress track
		calloutFill = Style.Mix(t.background, accent, 0.05), -- 1A1A17 "needs you" callout
		dot = Style.Mix(muted, edge, 0.45),             -- 6E7891 neutral status dot
	}
end

local toneCache = setmetatable({}, { __mode = "k" })

--- The derived tones of theme (cached). Pure.
function Style.Tones(theme)
	local tones = toneCache[theme]
	if not tones then
		tones = deriveTones(theme)
		toneCache[theme] = tones
	end
	return tones
end

--- A colour by name: a theme role first, then a derived tone.
function Style.Tone(theme, name)
	return theme[name] or Style.Tones(theme)[name] or theme.text
end

--- Fonts (docs/design/UI_DESIGN_V07.md, design system "Type") --------------------
-- Dawnward ships two OFL fonts (Media/Fonts/FONTS.txt): Cinzel SemiBold for
-- display text and Alegreya Sans (Regular, Bold) for reading text, labels
-- and buttons. Each Dawnward font object either stands in for a game font
-- template (Style.Font(template)) or is a named style (Style.FontFor(style))
-- with a game font as its fallback. When the bundled fonts are not used (a
-- non-Latin client, or a font file that failed to load) the game font is used.
--
-- Letter spacing: WoW has no tracking, and Cinzel has no thin or hair space
-- to fake it with (a no-break space is 0.25 em, more than the design's
-- 0.16 em), so eyebrows are plain capitals one size up (13 instead of 12).
Style.FONT_DIR = "Interface\\AddOns\\DawnwardChronicles\\Media\\Fonts\\"
Style.FONT_FILES = { display = "Cinzel-SemiBold.ttf", body = "AlegreyaSans-Regular.ttf",
	bold = "AlegreyaSans-Bold.ttf" }
-- Clients whose script the bundled fonts cover.
Style.LATIN_LOCALES = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true,
	ptBR = true, ptPT = true }
Style.FONTS = {
	-- Stand-ins for game templates (every existing label uses these).
	{ name = "DawnwardFontScreen", file = "display", size = 28, template = "GameFontNormalHuge", style = "screen" },
	{ name = "DawnwardFontTitle", file = "display", size = 18, template = "GameFontNormalLarge", style = "title" },
	{ name = "DawnwardFontName", file = "display", size = 18, template = "GameFontHighlightLarge", style = "name" },
	{ name = "DawnwardFontEyebrow", file = "display", size = 13, template = "GameFontNormalSmall", style = "eyebrow" },
	{ name = "DawnwardFontLabel", file = "bold", size = 14, template = "GameFontNormal", style = "label" },
	{ name = "DawnwardFontBody", file = "body", size = 15, template = "GameFontHighlight", style = "body" },
	{ name = "DawnwardFontSmall", file = "body", size = 13, template = "GameFontHighlightSmall", style = "small" },
	{ name = "DawnwardFontDisabled", file = "body", size = 13, template = "GameFontDisableSmall", style = "disabled" },
	{ name = "DawnwardFontInput", file = "body", size = 15, template = "ChatFontNormal", style = "input" },
	-- Named styles (Style.FontFor); fallback is the game font used without them.
	{ name = "DawnwardFontRailName", file = "display", size = 21, fallback = "GameFontHighlightLarge",
		style = "railName" },
	{ name = "DawnwardFontDay", file = "display", size = 24, fallback = "GameFontNormalLarge", style = "day" },
	{ name = "DawnwardFontButton", file = "bold", size = 15, fallback = "GameFontHighlight", style = "button" },
	{ name = "DawnwardFontButtonSmall", file = "bold", size = 14, fallback = "GameFontHighlightSmall",
		style = "buttonSmall" },
	{ name = "DawnwardFontNav", file = "body", size = 17, fallback = "GameFontHighlight", style = "nav" },
	{ name = "DawnwardFontReading", file = "body", size = 16, spacing = 4, fallback = "GameFontHighlight",
		style = "reading" },
	{ name = "DawnwardFontMeta", file = "body", size = 14, fallback = "GameFontHighlightSmall", style = "meta" },
	{ name = "DawnwardFontBadge", file = "bold", size = 13, fallback = "GameFontHighlightSmall", style = "badge" },
	{ name = "DawnwardFontGlyph", file = "bold", size = 20, fallback = "GameFontHighlightLarge", style = "glyph" },
}
Style.FONT_BY_STYLE = {}
for _, f in ipairs(Style.FONTS) do
	Style.FONT_BY_STYLE[f.style] = f
end
local fontFor, styleFont = {}, {}
Style.fontObjects = {}

--- Creates the font objects. Safe to call again; returns the number loaded.
function Style.InitFonts()
	fontFor, styleFont = {}, {}
	if type(CreateFont) ~= "function" then
		return 0
	end
	local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
	if not Style.LATIN_LOCALES[locale] then
		return 0
	end
	-- A Font object's SetFont returns nothing in 1.15.9 (SimpleFontAPIDocumentation),
	-- but a FontString's returns whether the file loaded
	-- (SimpleFontStringAPIDocumentation). So each file is tried once on a
	-- hidden font string, and only files that load are used.
	local fileLoads = {}
	local probe = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
	local probeText = probe and probe:CreateFontString(nil, "OVERLAY")
	if probe then probe:Hide() end
	local function loads(file)
		if fileLoads[file] == nil then
			local ok, success = pcall(function()
				return probeText:SetFont(Style.FONT_DIR .. Style.FONT_FILES[file], 12, "")
			end)
			fileLoads[file] = (probeText and ok and success) and true or false
		end
		return fileLoads[file]
	end
	local loaded = 0
	for _, f in ipairs(Style.FONTS) do
		local ok, set = pcall(function()
			if not loads(f.file) then return false end
			local object = Style.fontObjects[f.name] or CreateFont(f.name)
			Style.fontObjects[f.name] = object
			object:SetFont(Style.FONT_DIR .. Style.FONT_FILES[f.file], f.size, "")
			object:SetShadowOffset(1, -1)
			object:SetShadowColor(0, 0, 0, 0.75)
			if f.spacing and object.SetSpacing then object:SetSpacing(f.spacing) end
			return true
		end)
		if ok and set then
			if f.template then fontFor[f.template] = f.name end
			styleFont[f.style] = f.name
			loaded = loaded + 1
		end
	end
	return loaded
end

--- The font object name to use in place of a game font template.
function Style.Font(template)
	return fontFor[template] or template
end

--- The font object name for a named style ("button", "nav", "reading", ...),
-- or its game-font fallback when the bundled fonts are not in use.
function Style.FontFor(style)
	local spec = Style.FONT_BY_STYLE[style]
	if not spec then return Style.Font(style) end
	return styleFont[style] or spec.template or spec.fallback
end

--- The Dawnward font object standing in for template, or nil.
function Style.FontObject(template)
	return fontFor[template] and Style.fontObjects[fontFor[template]] or nil
end

--- Whether the bundled font for style is in use.
function Style.UsesBundledFont(style)
	return styleFont[style] ~= nil
end

--- Text measurement ------------------------------------------------------------------
-- Advance widths (1/1000 em) of the bundled fonts for ASCII 32..126, read
-- from the font files (hmtx). Used to check in tests that labels fit their
-- controls; kerning is ignored, so treat the result as an estimate within a
-- few per cent.
Style.ADVANCE = {
	display = {
		250,256,347,562,528,722,753,190,395,395,388,481,215,380,208,419,634,376,596,543,607,536,607,530,
		586,607,208,215,489,481,481,445,986,715,645,773,821,613,577,824,845,370,364,724,598,946,857,865,
		630,867,724,544,650,809,732,975,707,689,658,389,419,389,543,500,504,650,593,690,752,558,531,734,
		749,347,330,657,545,868,779,776,575,770,648,497,592,703,646,880,642,637,607,365,253,365,493,
	},
	body = {
		165,256,280,516,428,824,694,166,288,306,374,480,229,307,229,287,528,344,455,412,481,418,470,417,
		474,470,229,229,480,480,480,331,825,578,537,520,646,482,434,600,684,268,310,547,416,789,683,635,
		520,639,555,472,490,626,564,893,594,528,528,288,287,288,424,450,389,462,514,385,518,461,303,487,
		520,242,265,456,247,800,516,491,509,510,323,370,319,510,423,674,435,427,412,288,314,288,480,
	},
	bold = {
		151,264,354,549,450,854,711,205,295,300,383,480,229,304,229,284,521,360,471,431,503,432,483,432,
		493,483,229,229,480,480,480,340,844,600,579,517,655,509,456,598,696,295,335,584,433,797,695,643,
		553,649,590,498,503,638,587,903,623,558,547,295,284,295,441,444,389,481,523,385,526,472,329,500,
		533,261,285,495,263,807,529,494,518,519,348,384,338,522,445,698,461,447,424,295,307,295,480,
	},
}
local WIDE_CHAR = 600 -- any other character (·, ×, accented letters): a generous estimate

--- Estimated width in UI units of text set in a Dawnward style (a
-- Style.FONTS style name such as "button", "body", "eyebrow"). Colour codes
-- are ignored. Pure.
function Style.TextWidth(text, style)
	local spec = Style.FONT_BY_STYLE[style or "body"] or Style.FONT_BY_STYLE.body
	local advance = Style.ADVANCE[spec.file]
	text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local units = 0
	for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local byte = char:byte()
		if #char == 1 and byte >= 32 and byte <= 126 then
			units = units + advance[byte - 31]
		elseif #char > 1 then
			units = units + WIDE_CHAR
		end
	end
	return units * spec.size / 1000
end

--- Painting ------------------------------------------------------------------------

-- Weak keys: objects that disappear are forgotten.
local registry = setmetatable({}, { __mode = "k" })

--- The theme currently painted (the active character's, or a preview).
function Style.Current()
	return Style.theme or Themes.Get(Themes.DEFAULT)
end

--- Registers painter(object, theme) and paints object now. Returns object.
function Style.Register(object, painter)
	registry[object] = painter
	painter(object, Style.Current())
	return object
end

--- Repaints one object (after a state change such as hover).
function Style.Repaint(object)
	local painter = registry[object]
	if painter then
		painter(object, Style.Current())
	end
end

--- Paints every registered object with theme. Cheap: a few hundred objects at most.
function Style.Apply(theme)
	Style.theme = theme
	for object, painter in pairs(registry) do
		painter(object, theme)
	end
end

function Style.Color(texture, color, alpha)
	local a = alpha or 1
	if texture.SetColorTexture then
		texture:SetColorTexture(color[1], color[2], color[3], a)
	else
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
		texture:SetVertexColor(color[1], color[2], color[3], a)
	end
end

function Style.TextColor(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
end

function Style.Solid(parent, layer, sublevel)
	return parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
end

--- A 1 px border inside frame: { top, bottom, left, right } textures, with
-- edges:Paint(color, alpha) and edges:SetShown(on). inset moves it inwards.
function Style.Edge(frame, layer, inset, thickness)
	inset, thickness = inset or 0, thickness or 1
	local e = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		e[side] = Style.Solid(frame, layer or "BORDER")
	end
	e.top:SetPoint("TOPLEFT", inset, -inset)
	e.top:SetPoint("TOPRIGHT", -inset, -inset)
	e.top:SetHeight(thickness)
	e.bottom:SetPoint("BOTTOMLEFT", inset, inset)
	e.bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
	e.bottom:SetHeight(thickness)
	e.left:SetPoint("TOPLEFT", inset, -inset)
	e.left:SetPoint("BOTTOMLEFT", inset, inset)
	e.left:SetWidth(thickness)
	e.right:SetPoint("TOPRIGHT", -inset, -inset)
	e.right:SetPoint("BOTTOMRIGHT", -inset, inset)
	e.right:SetWidth(thickness)
	function e.Paint(_, color, alpha)
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do
			Style.Color(e[side], color, alpha)
		end
	end
	function e.SetShown(_, on)
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do
			e[side]:SetShown(on and true or false)
		end
	end
	return e
end

--- Round shapes -------------------------------------------------------------------
-- The client has no rounded rectangles, but it does have mask textures
-- (SimpleFrameAPI CreateMaskTexture, used by the 1.15.9 ContainerFrame.xml
-- and FriendshipStatusBar.xml) and the game's own circular portrait mask.
-- A solid colour masked by it is a smooth disc; discs give round portrait
-- rings, dots, round badges and pill-shaped chips. Where masks are not
-- available every caller falls back to the square v0.7 look.
Style.CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

--- A circle mask for a texture on frame, or nil when the client offers none.
-- (Overridable in tests.)
function Style.NewMask(frame)
	if type(frame.CreateMaskTexture) ~= "function" then return nil end
	local ok, mask = pcall(frame.CreateMaskTexture, frame)
	if not ok or type(mask) ~= "table" then return nil end
	mask:SetTexture(Style.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	return mask
end

--- A solid disc of size on frame (a square where masks are unavailable).
-- tex.round tells which one it is.
function Style.Disc(frame, layer, sublevel, size)
	local tex = Style.Solid(frame, layer or "ARTWORK", sublevel)
	if size then tex:SetSize(size, size) end
	local mask = tex.AddMaskTexture and Style.NewMask(frame)
	if mask then
		mask:SetAllPoints(tex)
		tex:AddMaskTexture(mask)
		tex.mask, tex.round = mask, true
	end
	return tex
end

--- A pill (a rectangle with round ends) filling frame, with a 1 px edge:
-- pill:Paint(fill, edge) with opaque colours, pill:SetShown(on). Returns nil
-- when round shapes are not available (callers keep a square fill and edge).
-- The frame's height sets the end radius; keep the frame at least that wide.
function Style.Pill(frame, height)
	local h = height or frame:GetHeight()
	local first = Style.Disc(frame, "BACKGROUND", 1, h)
	if not first.round then
		first:Hide()
		return nil
	end
	local pill = { parts = {} }
	local function part(tex) pill.parts[#pill.parts + 1] = tex; return tex end
	pill.capL = part(first)
	pill.capR = part(Style.Disc(frame, "BACKGROUND", 1, h))
	pill.innerL = part(Style.Disc(frame, "BACKGROUND", 2, h - 2))
	pill.innerR = part(Style.Disc(frame, "BACKGROUND", 2, h - 2))
	pill.mid = part(Style.Solid(frame, "BACKGROUND", 2))
	pill.top = part(Style.Solid(frame, "BACKGROUND", 1))
	pill.bottom = part(Style.Solid(frame, "BACKGROUND", 1))
	--- Lays the parts out for a frame height (round ends of that diameter).
	function pill.Resize(_, size)
		local r = size / 2
		pill.height = size
		for _, cap in ipairs({ pill.capL, pill.capR }) do cap:SetSize(size, size) end
		for _, cap in ipairs({ pill.innerL, pill.innerR }) do cap:SetSize(size - 2, size - 2) end
		pill.capL:ClearAllPoints()
		pill.capL:SetPoint("LEFT", 0, 0)
		pill.capR:ClearAllPoints()
		pill.capR:SetPoint("RIGHT", 0, 0)
		pill.innerL:ClearAllPoints()
		pill.innerL:SetPoint("LEFT", 1, 0)
		pill.innerR:ClearAllPoints()
		pill.innerR:SetPoint("RIGHT", -1, 0)
		pill.mid:ClearAllPoints()
		pill.mid:SetPoint("TOPLEFT", r, -1)
		pill.mid:SetPoint("BOTTOMRIGHT", -r, 1)
		pill.top:ClearAllPoints()
		pill.top:SetPoint("TOPLEFT", r, 0)
		pill.top:SetPoint("TOPRIGHT", -r, 0)
		pill.top:SetHeight(1)
		pill.bottom:ClearAllPoints()
		pill.bottom:SetPoint("BOTTOMLEFT", r, 0)
		pill.bottom:SetPoint("BOTTOMRIGHT", -r, 0)
		pill.bottom:SetHeight(1)
	end
	pill:Resize(h)
	function pill.Paint(_, fill, edge)
		for _, t in ipairs({ pill.capL, pill.capR, pill.top, pill.bottom }) do Style.Color(t, edge, 1) end
		for _, t in ipairs({ pill.innerL, pill.innerR, pill.mid }) do Style.Color(t, fill, 1) end
		pill.fill, pill.edge = fill, edge
	end
	function pill.SetShown(_, on)
		for _, t in ipairs(pill.parts) do t:SetShown(on and true or false) end
	end
	return pill
end

--- Frame chrome ----------------------------------------------------------------

-- The window frame of the design system: a 1 px gold line ("ornament line",
-- theme.border) and a double-L ornament in two corners (the mockup draws
-- them top-left and bottom-right, 6 px in, 18 px across).
Style.CHROME = { ornamentInset = 6, outer = 12, inner = 5, innerOffset = 4, thickness = 2, ornamentAlpha = 0.85,
	corners = { "TOPLEFT", "BOTTOMRIGHT" } }
local CORNER_SIGN = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

--- Gives frame the Dawnward frame treatment: an opaque fill (theme role
-- fill, default "background"), the gold frame line and corner ornaments.
-- opts.corners lists the corners that carry an ornament (default top-left
-- and bottom-right). Returns the chrome table (chrome.fill is the fill).
function Style.Chrome(frame, fill, opts)
	local C = Style.CHROME
	local chrome = { fillRole = fill or "background", corners = {} }
	chrome.fill = Style.Solid(frame, "BACKGROUND", -8)
	chrome.fill:SetAllPoints(frame)
	chrome.outline = Style.Edge(frame, "BORDER", 0, 1)
	for _, point in ipairs(opts and opts.corners or C.corners) do
		local sx, sy = CORNER_SIGN[point][1], CORNER_SIGN[point][2]
		-- Outer L: legs of C.outer; inner L: legs of C.inner, C.innerOffset further in.
		for _, l in ipairs({ { 0, C.outer }, { C.innerOffset, C.inner } }) do
			local offset, length = C.ornamentInset + l[1], l[2]
			local h = Style.Solid(frame, "ARTWORK")
			h:SetSize(length, C.thickness)
			h:SetPoint(point, sx * offset, sy * offset)
			local v = Style.Solid(frame, "ARTWORK")
			v:SetSize(C.thickness, length)
			v:SetPoint(point, sx * offset, sy * offset)
			chrome.corners[#chrome.corners + 1] = h
			chrome.corners[#chrome.corners + 1] = v
		end
	end
	Style.Register(chrome, function(c, theme)
		Style.Color(c.fill, theme[c.fillRole])
		c.outline:Paint(theme.border, 1)
		for _, t in ipairs(c.corners) do
			Style.Color(t, theme.ornament, C.ornamentAlpha)
		end
	end)
	frame.chrome = chrome
	return chrome
end

--- A solid fill painted with a theme role or tone (for wells and panels).
function Style.Fill(parent, role, layer, sublevel, alpha)
	local tex = Style.Solid(parent, layer or "BACKGROUND", sublevel)
	tex.role, tex.alpha = role, alpha
	Style.Register(tex, function(t, theme) Style.Color(t, Style.Tone(theme, t.role), t.alpha) end)
	return tex
end

--- Window scale that fits a frame of height h (and width w, when given)
-- inside a parent of parentHeight (and parentWidth) with margin to spare;
-- never above 1. Pure.
function Style.FitScale(h, parentHeight, margin, w, parentWidth)
	margin = margin or 40
	local scale = 1
	if type(parentHeight) == "number" and parentHeight > 0 then
		scale = math.min(scale, (parentHeight - margin) / h)
	end
	if w and type(parentWidth) == "number" and parentWidth > 0 then
		scale = math.min(scale, (parentWidth - margin) / w)
	end
	return scale
end

Style.InitFonts()
