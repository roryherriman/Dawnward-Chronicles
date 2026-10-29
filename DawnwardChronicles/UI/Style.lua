-- The v0.6 design system: tokens, theme painting and frame chrome.
-- See docs/design/UI_DESIGN_V06.md.
--
-- Components register a painter once (Style.Register); Style.Apply(theme)
-- repaints every registered object, and a new object is painted with the
-- current theme straight away. Modules therefore never hand-colour buttons,
-- inputs, cards or frames. Everything is drawn from solid-colour textures:
-- no art files ship, so every theme recolours the whole interface.
local _, ns = ...
local Themes = ns.Themes

local Style = {}
ns.Style = Style

Style.SPACE = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
Style.SIZE = { button = 22, compact = 20, nav = 28, segment = 22, input = 22, icon = 22 }

-- Text roles: font object and theme colour.
Style.TEXT = {
	title = { font = "GameFontNormalLarge", color = "accent" },
	eyebrow = { font = "GameFontNormalSmall", color = "ornament" },
	heading = { font = "GameFontNormal", color = "accent" },
	body = { font = "GameFontHighlight", color = "text" },
	muted = { font = "GameFontHighlightSmall", color = "muted" },
	small = { font = "GameFontHighlightSmall", color = "text" },
	accent = { font = "GameFontNormal", color = "accent" },
	danger = { font = "GameFontHighlightSmall", color = "danger" },
}

--- Fonts (v0.7, docs/design/UI_DESIGN_V07.md) ------------------------------------
-- Dawnward ships two OFL fonts (Media/Fonts/FONTS.txt): Cinzel for display
-- text and Alegreya Sans for reading text and labels. Each Dawnward font
-- object stands in for one game font template; Style.Font(template) returns
-- the Dawnward one, or the template itself when the bundled fonts are not
-- used (a non-Latin client, or a font file that failed to load).
Style.FONT_DIR = "Interface\\AddOns\\DawnwardChronicles\\Media\\Fonts\\"
Style.FONT_FILES = { display = "Cinzel-SemiBold.ttf", body = "AlegreyaSans-Regular.ttf",
	bold = "AlegreyaSans-Bold.ttf" }
-- Clients whose script the bundled fonts cover.
Style.LATIN_LOCALES = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true,
	ptBR = true, ptPT = true }
Style.FONTS = {
	{ name = "DawnwardFontScreen", file = "display", size = 26, template = "GameFontNormalHuge" },
	{ name = "DawnwardFontTitle", file = "display", size = 19, template = "GameFontNormalLarge" },
	{ name = "DawnwardFontName", file = "display", size = 18, template = "GameFontHighlightLarge" },
	{ name = "DawnwardFontEyebrow", file = "display", size = 11, template = "GameFontNormalSmall" },
	{ name = "DawnwardFontLabel", file = "bold", size = 14, template = "GameFontNormal" },
	{ name = "DawnwardFontBody", file = "body", size = 15, template = "GameFontHighlight" },
	{ name = "DawnwardFontSmall", file = "body", size = 13, template = "GameFontHighlightSmall" },
	{ name = "DawnwardFontDisabled", file = "body", size = 13, template = "GameFontDisableSmall" },
	{ name = "DawnwardFontInput", file = "body", size = 15, template = "ChatFontNormal" },
}
local fontFor = {}
Style.fontObjects = {}

--- Creates the font objects. Safe to call again; returns the number loaded.
function Style.InitFonts()
	fontFor = {}
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
			return true
		end)
		if ok and set then
			fontFor[f.template] = f.name
			loaded = loaded + 1
		end
	end
	return loaded
end

--- The font object name to use in place of a game font template.
function Style.Font(template)
	return fontFor[template] or template
end

--- The Dawnward font object standing in for template, or nil.
function Style.FontObject(template)
	return fontFor[template] and Style.fontObjects[fontFor[template]] or nil
end

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

--- Colour helpers -------------------------------------------------------------

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

--- color mixed toward white by amount (0..1). Pure.
function Style.Lighten(color, amount)
	return { color[1] + (1 - color[1]) * amount, color[2] + (1 - color[2]) * amount,
		color[3] + (1 - color[3]) * amount }
end

function Style.Solid(parent, layer, sublevel)
	return parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
end

--- A 1 px border inside frame: { top, bottom, left, right } textures, with
-- edges:Paint(color, alpha). inset moves it inwards.
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
	return e
end

--- Frame chrome ----------------------------------------------------------------

Style.CHROME = { ornamentInset = 3, ornamentAlpha = 0.45, corner = 10, cornerThickness = 2 }
local OUTLINE = { 0.02, 0.02, 0.03 }

--- Gives frame the Dawnward frame treatment: an opaque fill (theme role
-- fill, default "background"), a dark outline, an inner ornament line and
-- corner brackets. Returns the chrome table (chrome.fill is the fill texture).
function Style.Chrome(frame, fill)
	local C = Style.CHROME
	local chrome = { fillRole = fill or "background", corners = {} }
	chrome.fill = Style.Solid(frame, "BACKGROUND", -8)
	chrome.fill:SetAllPoints(frame)
	chrome.outline = Style.Edge(frame, "BORDER", 0, 1)
	chrome.inner = Style.Edge(frame, "BORDER", C.ornamentInset, 1)
	-- Corner brackets: a horizontal and a vertical stroke at each corner.
	for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 },
		{ "BOTTOMRIGHT", -1, 1 } }) do
		local point, dx, dy = corner[1], corner[2], corner[3]
		local h = Style.Solid(frame, "ARTWORK")
		h:SetSize(C.corner, C.cornerThickness)
		h:SetPoint(point, dx * C.ornamentInset, dy * C.ornamentInset)
		local v = Style.Solid(frame, "ARTWORK")
		v:SetSize(C.cornerThickness, C.corner)
		v:SetPoint(point, dx * C.ornamentInset, dy * C.ornamentInset)
		chrome.corners[#chrome.corners + 1] = h
		chrome.corners[#chrome.corners + 1] = v
	end
	Style.Register(chrome, function(c, theme)
		Style.Color(c.fill, theme[c.fillRole])
		c.outline:Paint(OUTLINE, 1)
		c.inner:Paint(theme.ornament, C.ornamentAlpha)
		for _, t in ipairs(c.corners) do
			Style.Color(t, theme.ornament, 1)
		end
	end)
	frame.chrome = chrome
	return chrome
end

--- A solid fill painted with a theme role (for wells and panels).
function Style.Fill(parent, role, layer, sublevel, alpha)
	local tex = Style.Solid(parent, layer or "BACKGROUND", sublevel)
	tex.role, tex.alpha = role, alpha
	Style.Register(tex, function(t, theme) Style.Color(t, theme[t.role], t.alpha) end)
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
