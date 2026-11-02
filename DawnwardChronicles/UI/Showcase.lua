-- Character presentation (v0.7): the player's own portrait for the window's
-- side rail, and the Character Showcase (approved mockup
-- docs/design/mockups/proposed-character-showcase.png): a live 3D model of
-- the player beside what the game says about them ("From the game") and what
-- the player wrote ("In your own words"), kept visibly apart. v0.8 brings the
-- card, the panels and the portrait fallback closer to the mockup
-- (docs/design/audit/character.md); the model's loading is unchanged.
-- v0.10 (docs/design/audit/v10-character.md): the turn buttons show the
-- client's own rotate arrows, and "In your own words" leads with the title
-- the player wrote, as the mockup.
--
-- Client APIs (checked against the Classic Era 1.15.9.70576 UI source,
-- /home/user/gethe/wow-ui-source):
--   SetPortraitTexture(texture, "player")   the game's round portrait, as on
--                                           unit frames
--   CreateFrame("PlayerModel")              the character model frame Blizzard's
--                                           own Classic panels use: QuestFrame.lua
--                                           (QuestNPCModel:SetUnit("player")),
--                                           TabardFrame.lua (TabardModel:SetUnit)
--   PlayerModel:SetUnit(unit) -> success    FrameAPICharacterModelBaseDocumentation
--                                           (Returns success, bool)
--   SetRotation, SetPortraitZoom(zoom)      the same documentation; Classic's
--                                           ModelFrames.lua zooms model frames with
--                                           SetPortraitZoom between
--                                           MODELFRAME_MIN_ZOOM 0.0 and
--                                           MODELFRAME_MAX_ZOOM 0.7, steps of 0.15
--                                           (Model_OnMouseWheel)
--   ClearModel                              releases the model when hidden
--   Interface\Buttons\UI-RotationLeft-Button-Up / UI-RotationRight-Button-Up
--                                           the turn arrows of Classic's own model
--                                           panels (TabardFrame.xml, PetStable.xml;
--                                           "RotationLeft" turns the model with a
--                                           falling rotation, as Model_RotateRight)
--   UNIT_MODEL_CHANGED                      gear or form changed
--   GetGuildInfo("player")                  TabardFrame.lua, FriendsFrame.lua
--   GetRealmName()                          FriendsFrame.lua
--   PLAYER_GUILD_UPDATE                     FriendsFrame.lua, HonorFrame_Shared.lua
-- Nothing is invented: the model is the client's own rendering of the
-- player's character in the gear they are wearing, the portrait is the
-- client's, and the game identity (level, race, class, guild, realm) is read
-- live and never stored. When the model cannot be shown (SetUnit fails, or
-- the player chose the portrait), the portrait is shown in its place.
--
-- Performance: the model is set only while the showcase is visible and is
-- cleared when it hides, so a closed journal renders nothing. Events are
-- registered only while shown, and the drag handler (OnUpdate) runs only
-- while the mouse button is held on the model.
local _, ns = ...
local Style, Widgets = ns.Style, ns.Widgets

local Showcase = {}
ns.Showcase = Showcase

Showcase.ROTATE_STEP = math.pi / 8
Showcase.DRAG_SPEED = 0.01 -- radians per pixel of mouse movement
-- Zoom: Blizzard's own Classic model frame range and step (ModelFrames.lua).
Showcase.ZOOM_MIN, Showcase.ZOOM_MAX, Showcase.ZOOM_STEP = 0, 0.7, 0.15
Showcase.RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
Showcase.BAR_HEIGHT = 56 -- the control bar under the model (mockup: 36 px buttons, 10 px padding)
-- The turn buttons' arrows: the client's own art (see the API list above).
Showcase.ROTATE_ICONS = { left = "Interface\\Buttons\\UI-RotationLeft-Button-Up",
	right = "Interface\\Buttons\\UI-RotationRight-Button-Up" }
Showcase.ROTATE_ICON_SIZE = 30
Showcase.BAR_NOTE = "Drag to turn, scroll to zoom. Shows the gear you are wearing now."
Showcase.MODEL_WIDTH = 330 -- the model card in the showcase view
Showcase.GAP = 18

-- Seconds between attempts after SetUnit fails (about 8 s in all).
Showcase.RETRY_DELAYS = { 0.1, 0.3, 0.6, 1, 2, 4 }
-- What the chip on the model card says for each state.
Showcase.MODE_LABELS = {
	live = "Live model",
	loading = "Loading the live model...",
	choice = "Portrait (your choice)",
	unavailable = "Portrait: live model not available",
}

Showcase.FALLBACK_NOTE = "If the model can't be shown (for example while the character is still loading), "
	.. "your portrait takes its place."

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return nil
end

local function text(v)
	return type(v) == "string" and v ~= "" and v or nil
end

--- What the game says about the player: { level, raceName, className,
-- classToken, classColor, guildName, realmName }. Read live; never stored.
function Showcase.GameIdentity()
	local race = call(UnitRace, "player")
	local className, classToken = call(UnitClass, "player")
	local colors = type(RAID_CLASS_COLORS) == "table" and classToken and RAID_CLASS_COLORS[classToken] or nil
	return {
		level = call(UnitLevel, "player"),
		raceName = text(race),
		className = text(className),
		classToken = classToken,
		classColor = colors and { colors.r, colors.g, colors.b } or nil,
		guildName = text((call(GetGuildInfo, "player"))),
		realmName = text((call(GetRealmName))),
	}
end

--- The identity line under the name: "Human · Paladin · she/her". The
-- pronouns come from the player's own profile field, when set. Pure apart
-- from the game identity passed in.
function Showcase.IdentityLine(game, char)
	local parts = {}
	if game.raceName then parts[#parts + 1] = game.raceName end
	if game.className then parts[#parts + 1] = game.className end
	local pronouns = char and char.fields and char.fields.pronouns and char.fields.pronouns.value
	if type(pronouns) == "string" and pronouns ~= "" then parts[#parts + 1] = pronouns end
	return table.concat(parts, " · ")
end

local function hex(color)
	return string.format("%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5))
end

--- The "In game" rows: { { label, value, empty } }. The class is shown in
-- its class colour. Pure.
function Showcase.GameRows(game)
	local class = game.className
	if class and game.classColor then
		class = "|cff" .. hex(game.classColor) .. class .. "|r"
	end
	local parts = {}
	if game.raceName then parts[#parts + 1] = game.raceName end
	if class then parts[#parts + 1] = class end
	local raceClass = #parts > 0 and table.concat(parts, " · ") or nil
	return {
		{ label = "Level", value = game.level and tostring(game.level) or "Unknown", empty = game.level == nil },
		{ label = "Race · class", value = raceClass or "Unknown", empty = raceClass == nil },
		{ label = "Guild", value = game.guildName or "No guild", empty = game.guildName == nil },
		{ label = "Realm", value = game.realmName or "Unknown", empty = game.realmName == nil },
	}
end

--- A round portrait of the player inside a gold ring. size: outer size.
-- Returns a frame with :Update().
function Showcase.Portrait(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetPoint("CENTER")
	f.portrait:SetSize(size - 14, size - 14)
	f.ring = f:CreateTexture(nil, "OVERLAY")
	f.ring:SetTexture(Showcase.RING)
	-- The tracking border's ring sits in the top-left of its texture.
	f.ring:SetTexCoord(0, 0.6, 0, 0.6)
	f.ring:SetPoint("CENTER", 1, -1)
	f.ring:SetSize(size + 6, size + 6)
	function f.Update()
		call(SetPortraitTexture, f.portrait, "player")
	end
	Style.Register(f, function(self, theme)
		self.ring:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3])
	end)
	f:SetScript("OnShow", f.Update)
	f:RegisterEvent("UNIT_PORTRAIT_UPDATE")
	f:SetScript("OnEvent", function(_, _, unit)
		if unit == "player" and f:IsVisible() then f.Update() end
	end)
	f.Update()
	return f
end

-- The model card (CharacterShowcase.dc.html): a darker card with a dark
-- gold edge, the stage (the model's area) above a control bar with the turn
-- buttons and a short note; the mode chip at the stage's top left. Zoom
-- buttons stack at the stage's top right, so the bar keeps the mockup's two
-- buttons and its note stays on two lines.
Showcase.CARD = { pad = 12, button = 36, zoomButton = 30, gap = 8, portrait = 132, ringWidth = 2, ringGap = 4,
	frameInset = 24 }

-- What the portrait fallback says, by state (the chip names the state).
Showcase.FALLBACK_TEXT = {
	loading = "Loading your live model. Your portrait is shown until it is ready.",
	choice = "You chose to show your portrait here instead of the live model.",
	unavailable = "The live model could not be loaded just now.",
}

--- The portrait fallback inside the model card: a framed area centred on the
-- stage with the round portrait at a fixed, sharp size (never stretched to
-- the stage), a caption and a line saying why it shows. Returns a frame with
-- .portrait (the texture), .Update() and :SetReason(state).
function Showcase.Fallback(stage, width)
	local C = Showcase.CARD
	local fb = CreateFrame("Frame", nil, stage)
	fb:SetAllPoints(stage)
	local boxWidth = width - 2 * C.frameInset
	fb.box = CreateFrame("Frame", nil, fb)
	fb.box:SetWidth(boxWidth)
	fb.box:SetPoint("CENTER", fb, "CENTER", 0, 0)
	fb.box.bg = Style.Solid(fb.box, "BACKGROUND", 1)
	fb.box.bg:SetAllPoints(fb.box)
	fb.box.edges = Style.Edge(fb.box, "BORDER")
	-- The game's round portrait inside a gold ring with a dark gap, drawn
	-- as discs where masks exist (as the rail), else with the tinted ring.
	fb.badge = Showcase.Portrait(fb.box, C.portrait)
	fb.badge:SetPoint("TOP", fb.box, "TOP", 0, -C.frameInset)
	local ring = {}
	ring.outer = Style.Disc(fb.badge, "BACKGROUND", 0, C.portrait)
	ring.gap = Style.Disc(fb.badge, "BACKGROUND", 1, C.portrait - 2 * C.ringWidth)
	ring.well = Style.Disc(fb.badge, "BACKGROUND", 2, C.portrait - 2 * (C.ringWidth + C.ringGap))
	for _, disc in pairs(ring) do disc:SetPoint("CENTER", fb.badge, "CENTER", 0, 0) end
	ring.round = ring.outer.round and ring.gap.round and ring.well.round
	for _, key in ipairs({ "outer", "gap", "well" }) do ring[key]:SetShown(ring.round and true or false) end
	if ring.round and fb.badge.ring then fb.badge.ring:Hide() end
	fb.ringDiscs = ring
	fb.portrait = fb.badge.portrait
	fb.ring = fb.badge.ring
	fb.Update = fb.badge.Update

	fb.caption = Widgets.Label(fb.box, "GameFontNormalLarge", false, "title")
	fb.caption:SetPoint("TOP", fb.badge, "BOTTOM", 0, -14)
	fb.caption:SetWidth(boxWidth - 32)
	fb.caption:SetJustifyH("CENTER")
	fb.caption:SetText("Your portrait")
	fb.text = Widgets.Label(fb.box, "meta", true, "muted")
	fb.text:SetPoint("TOP", fb.caption, "BOTTOM", 0, -8)
	fb.text:SetWidth(boxWidth - 32)
	fb.text:SetJustifyH("CENTER")

	Style.Register(fb.box, function(box, theme)
		local well = Style.Mix(theme.background, theme.surface, 0.8)
		Style.Color(box.bg, well)
		box.edges:Paint(theme.edge, 1)
		Style.Color(ring.outer, theme.accent)
		Style.Color(ring.gap, well)
		Style.Color(ring.well, theme.surfaceHover)
	end)

	--- Says why the portrait shows; sizes the frame to its content.
	function fb.SetReason(_, state)
		fb.reason = state
		fb.text:SetText(Showcase.FALLBACK_TEXT[state] or "")
		local textHeight = fb.text:GetStringHeight() or 0
		fb.box:SetHeight(C.frameInset + C.portrait + 14 + 24 + 8 + textHeight + C.frameInset)
	end
	fb:SetReason("loading")
	return fb
end

--- A live 3D model of the player with rotate and zoom buttons, drag to
-- turn and the mouse wheel to zoom, falling back to the portrait. Returns a
-- frame with :Update(), :Rotate(d), :Zoom(d), :SetPreferPortrait(on).
function Showcase.Model(parent, width, height)
	local C = Showcase.CARD
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	f.bg = Style.Solid(f, "BACKGROUND", -2)
	f.bg:SetAllPoints(f)
	f.edges = Style.Edge(f, "BORDER")

	local bar = Showcase.BAR_HEIGHT
	-- The stage: the model's area, everything above the control bar.
	f.stage = CreateFrame("Frame", nil, f)
	f.stage:SetPoint("TOPLEFT", 1, -1)
	f.stage:SetPoint("BOTTOMRIGHT", -1, bar)
	f.stage.bg = Style.Solid(f.stage, "BACKGROUND", -1)
	f.stage.bg:SetAllPoints(f.stage)
	Style.Register(f, function(card, theme)
		-- Mockup: card #10151F with a #4A3E26 edge, stage #121A27.
		Style.Color(card.bg, Style.Mix(theme.background, theme.surface, 0.3))
		card.edges:Paint(Style.Mix(theme.background, theme.border or theme.edge, 0.6), 1)
		Style.Color(card.stage.bg, Style.Mix(theme.background, theme.surface, 0.55))
	end)

	-- The model fills the whole stage.
	f.model = CreateFrame("PlayerModel", nil, f)
	f.model:SetPoint("TOPLEFT", f.stage, "TOPLEFT", 0, 0)
	f.model:SetPoint("BOTTOMRIGHT", f.stage, "BOTTOMRIGHT", 0, 0)
	f.model:EnableMouse(true)
	if f.model.EnableMouseWheel then f.model:EnableMouseWheel(true) end
	f.rotation = 0
	f.zoom = Showcase.ZOOM_MIN

	f.fallback = Showcase.Fallback(f.stage, width)
	f.fallback:Hide()

	-- What is showing: "Live model" or "Portrait".
	f.chip = Widgets.Chip(f, "Live model", "accent")
	f.chip:SetPoint("TOPLEFT", C.pad, -C.pad)
	f.chip:SetMaxWidth(width - 2 * C.pad - C.zoomButton - C.gap)
	-- Above the model, which draws over its siblings at the same level.
	local level = f.model.GetFrameLevel and f.model:GetFrameLevel()
	local function raise(frame)
		if type(level) == "number" and frame.SetFrameLevel then frame:SetFrameLevel(level + 2) end
	end
	raise(f.chip)

	f.rule = Widgets.Divider(f)
	f.rule:SetPoint("BOTTOMLEFT", 1, bar)
	f.rule:SetPoint("BOTTOMRIGHT", -1, bar)

	function f.Rotate(_, delta)
		f.rotation = (f.rotation + delta) % (2 * math.pi)
		if f.model.SetRotation then f.model:SetRotation(f.rotation) end
	end

	--- Zooms by delta, kept inside Blizzard's own model zoom range.
	function f.Zoom(_, delta)
		f.zoom = math.max(Showcase.ZOOM_MIN, math.min(Showcase.ZOOM_MAX, f.zoom + delta))
		-- Avoid float drift at the ends.
		if math.abs(f.zoom - Showcase.ZOOM_MIN) < 1e-6 then f.zoom = Showcase.ZOOM_MIN end
		if math.abs(f.zoom - Showcase.ZOOM_MAX) < 1e-6 then f.zoom = Showcase.ZOOM_MAX end
		if f.modelShown and f.model.SetPortraitZoom then f.model:SetPortraitZoom(f.zoom) end
		f.UpdateControls()
	end

	-- Icon-style buttons with a large glyph (the design's icon buttons).
	local function controlButton(glyph, size, variant, title, tip)
		local b = Widgets.Button(f, glyph, size, size, variant)
		if Style.UsesBundledFont("glyph") and Style.fontObjects then
			local font = Style.fontObjects[Style.FontFor("glyph")]
			if font then b.label:SetFontObject(font) end
		end
		Widgets.Tooltip(b, title, tip)
		return b
	end
	-- The turn buttons show the client's rotate arrows (mockup: rotate icons
	-- in 36 px icon buttons), not text glyphs.
	local function rotateButton(side, title)
		local b = controlButton("", C.button, "ghost", title, "Dragging the model also turns it.")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetTexture(Showcase.ROTATE_ICONS[side])
		b.icon:SetSize(Showcase.ROTATE_ICON_SIZE, Showcase.ROTATE_ICON_SIZE)
		b.icon:SetPoint("CENTER", 0, 0)
		return b
	end
	f.left = rotateButton("left", "Turn left")
	f.left:SetPoint("BOTTOMLEFT", C.pad, (bar - C.button) / 2)
	f.left:SetScript("OnClick", function() f:Rotate(-Showcase.ROTATE_STEP) end)
	f.right = rotateButton("right", "Turn right")
	f.right:SetPoint("LEFT", f.left, "RIGHT", C.gap, 0)
	f.right:SetScript("OnClick", function() f:Rotate(Showcase.ROTATE_STEP) end)
	-- Zoom: filled buttons over the stage (readable over the model).
	f.zoomIn = controlButton("+", C.zoomButton, "default", "Zoom in", "The mouse wheel over the model also zooms.")
	f.zoomIn:SetPoint("TOPRIGHT", f.stage, "TOPRIGHT", -(C.pad - 1), -(C.pad - 1))
	f.zoomIn:SetScript("OnClick", function() f:Zoom(Showcase.ZOOM_STEP) end)
	f.zoomOut = controlButton("-", C.zoomButton, "default", "Zoom out", "The mouse wheel over the model also zooms.")
	f.zoomOut:SetPoint("TOP", f.zoomIn, "BOTTOM", 0, -4)
	f.zoomOut:SetScript("OnClick", function() f:Zoom(-Showcase.ZOOM_STEP) end)
	raise(f.zoomIn)
	raise(f.zoomOut)

	-- Mockup: muted 13 beside the buttons, two lines at most.
	f.note = Widgets.Label(f, "GameFontHighlightSmall", true, "muted")
	f.note:SetPoint("BOTTOMLEFT", C.pad + 2 * C.button + C.gap + 12, 8)
	f.note:SetPoint("BOTTOMRIGHT", -C.pad, 8)
	f.note:SetHeight(bar - 16)
	f.note:SetJustifyV("MIDDLE")
	f.note:SetText(Showcase.BAR_NOTE)

	function f.UpdateControls()
		local on = f.modelShown and true or false
		for _, b in ipairs({ f.left, f.right }) do
			b:SetEnabled(on)
			if b.icon.SetDesaturated then b.icon:SetDesaturated(not on) end
			b.icon:SetAlpha(on and 1 or Widgets.BUTTON.disabledAlpha)
		end
		f.zoomOut:SetEnabled(on and f.zoom > Showcase.ZOOM_MIN)
		f.zoomIn:SetEnabled(on and f.zoom < Showcase.ZOOM_MAX)
		-- The zoom buttons sit over the stage: only while the model shows, so
		-- they never cover the portrait's frame.
		f.zoomIn:SetShown(on)
		f.zoomOut:SetShown(on)
	end

	-- Drag to turn: the model follows the cursor while the button is held.
	-- The OnUpdate handler exists only during a drag.
	local function dragStep()
		if not f.dragX then return end
		local x = call(GetCursorPosition)
		if x then
			f:Rotate((x - f.dragX) * Showcase.DRAG_SPEED)
			f.dragX = x
		end
	end
	local function stopDrag()
		f.dragX = nil
		f.model:SetScript("OnUpdate", nil)
	end
	f.model:SetScript("OnMouseDown", function()
		if not f.modelShown then return end
		f.dragX = call(GetCursorPosition)
		f.model:SetScript("OnUpdate", dragStep)
	end)
	f.model:SetScript("OnMouseUp", stopDrag)
	f.model:SetScript("OnMouseWheel", function(_, delta)
		if f.modelShown then f:Zoom((delta or 0) * Showcase.ZOOM_STEP) end
	end)

	-- Loading the model. Blizzard's own panels set the unit on a model frame
	-- that is already shown (PaperDollFrame.lua: CharacterModelFrame:SetUnit(
	-- "player", false) on PLAYER_ENTERING_WORLD and UNIT_MODEL_CHANGED;
	-- DressUpFrames.lua: ShowUIPanel, then SetUnit). A model frame that is
	-- hidden cannot load, so this frame is never hidden while a load may be
	-- wanted: when the portrait is showing, the model is only made
	-- transparent. SetUnit can also fail while the frame or the character is
	-- not ready yet (the first frame after the window opens, a loading
	-- screen), so a failure is retried a few times (RETRY_DELAYS, about 8 s
	-- in all) before the portrait is shown; it is tried again whenever the
	-- showcase reopens, gear changes, after a loading screen, or when the
	-- player asks. A token cancels retries that are no longer wanted.
	f.attempts, f.token, f.state = 0, 0, nil

	local function setModelVisible(on)
		f.model:Show()
		if f.model.SetAlpha then f.model:SetAlpha(on and 1 or 0) end
		f.model:EnableMouse(on and true or false)
		if f.model.EnableMouseWheel then f.model:EnableMouseWheel(on and true or false) end
	end

	local function show(state)
		f.state = state
		local live = state == "live"
		f.modelShown = live
		f.fallbackReason = (not live) and state or nil
		setModelVisible(live)
		f.fallback:SetShown(not live)
		if live then
			if f.model.SetRotation then f.model:SetRotation(f.rotation) end
			if f.model.SetPortraitZoom then f.model:SetPortraitZoom(f.zoom) end
		else
			stopDrag()
			f.fallback:SetReason(state)
			f.fallback.Update()
		end
		f.chip:SetChip(Showcase.MODE_LABELS[state], live and "accent" or "muted")
		f.UpdateControls()
		if f.onUpdate then f.onUpdate() end
	end

	--- One SetUnit call. Returns ok. Records the result for diagnostics.
	function f.TryModel()
		f.attempts = f.attempts + 1
		if not f.model.SetUnit then
			f.lastResult = "SetUnit is not available"
			return false
		end
		f.model:Show()
		-- blend false, as the character frame does: show the model at once.
		local called, result = pcall(f.model.SetUnit, f.model, "player", false)
		f.lastResult = called and tostring(result) or ("error: " .. tostring(result))
		-- SetUnit returns success in 1.15.9; only an error or an explicit
		-- false counts as a failure.
		return called and result ~= false
	end

	local function attempt(token)
		if token ~= f.token or f.preferPortrait or not f:IsVisible() then return end
		if f.TryModel() then
			show("live")
			return
		end
		local delay = Showcase.RETRY_DELAYS[f.attempts]
		if delay and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			if f.state ~= "loading" then show("loading") end
			C_Timer.After(delay, function() attempt(token) end)
		else
			show("unavailable")
		end
	end

	--- Shows the model, or the portrait when the player chose it or the model
	-- cannot be loaded. Every call starts a fresh set of attempts, so an
	-- earlier failure never stops a later try.
	function f.Update()
		f.token = f.token + 1
		f.attempts = 0
		if f.preferPortrait then
			if f.model.ClearModel then f.model:ClearModel() end
			show("choice")
			return
		end
		attempt(f.token)
	end
	f.Retry = f.Update

	--- The player's choice: the portrait instead of the model.
	function f.SetPreferPortrait(_, on)
		on = on and true or false
		if f.preferPortrait == on then return end
		f.preferPortrait = on
		if f:IsVisible() then f.Update() end
	end

	--- What the showcase knows about the model, for /dawnward dev showcase.
	function f.Diagnostics()
		local w, h = f.model:GetWidth(), f.model:GetHeight()
		local can = f.model.CanSetUnit and call(f.model.CanSetUnit, f.model, "player")
		local file = f.model.GetModelFileID and call(f.model.GetModelFileID, f.model)
		return {
			"Showcase: " .. Showcase.MODE_LABELS[f.state or "loading"] .. (f.preferPortrait and " (portrait chosen)" or ""),
			"  visible: " .. tostring(f:IsVisible() and true or false) .. ", model frame shown: "
				.. tostring(f.model:IsShown() and true or false) .. ", size: " .. string.format("%dx%d", w or 0, h or 0),
			"  attempts this time: " .. f.attempts .. ", last SetUnit result: " .. tostring(f.lastResult or "none"),
			"  CanSetUnit(\"player\"): " .. tostring(can) .. ", model file: " .. tostring(file),
		}
	end

	f:SetScript("OnShow", function()
		f:RegisterEvent("UNIT_MODEL_CHANGED")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f.Update()
	end)
	f:SetScript("OnHide", function()
		f:UnregisterEvent("UNIT_MODEL_CHANGED")
		f:UnregisterEvent("PLAYER_ENTERING_WORLD")
		f.token = f.token + 1 -- cancels pending retries
		stopDrag()
		-- Nothing is rendered while the journal is closed.
		if f.model.ClearModel then f.model:ClearModel() end
	end)
	f:SetScript("OnEvent", function(_, event, unit)
		if (event == "PLAYER_ENTERING_WORLD" or unit == "player") and f:IsVisible() and not f.preferPortrait then
			f.Update()
		end
	end)
	return f
end

--- The Character Showcase view ---------------------------------------------------

-- Summary text longer than this is shortened in the showcase (the full text
-- is in the profile).
Showcase.SUMMARY_MAX = 320

local function shorten(s, max)
	if #s <= max then return s end
	local cut = s:sub(1, max):gsub("%s+%S*$", "")
	return cut .. "..."
end

--- The "In your own words" content, from the player's own profile fields:
-- { heading, summary, empty }. The heading is the title the player wrote
-- (mockup: "Keeper of the Lantern Road" in Cinzel), else their name; the
-- name and pronouns are on the rail beside it. Pure.
function Showcase.OwnWords(char)
	local fields = char and char.fields or {}
	local function value(key)
		return fields[key] and text(fields[key].value)
	end
	local out = { heading = value("title") or value("name") }
	local summary = value("summary")
	out.summary = summary and shorten(summary, Showcase.SUMMARY_MAX)
	out.empty = not (out.heading or out.summary)
	return out
end

-- The right-hand panels (CharacterShowcase.dc.html): 18 px side padding,
-- 14 top; game rows 38 high with the key 110 wide (120 here: Cinzel 13 has
-- no letter spacing to lean on, see Style); panels 12 apart.
Showcase.PANEL = { padX = 18, padY = 14, rowsTop = 34, rowHeight = 38, keyWidth = 120, gap = 12, ownTop = 44 }

--- The whole showcase: model card on the left; "From the game", "In your own
-- words" and the portrait note on the right. onPreferPortrait(on) saves the
-- player's choice; onEditProfile() returns to the profile fields.
-- Returns a frame with :Refresh(char, preferPortrait), .model (the model card).
function Showcase.View(parent, width, height, opts)
	opts = opts or {}
	local P = Showcase.PANEL
	local v = CreateFrame("Frame", nil, parent)
	v:SetSize(width, height)
	v.model = Showcase.Model(v, Showcase.MODEL_WIDTH, height)
	v.model:SetPoint("TOPLEFT", 0, 0)

	local x = Showcase.MODEL_WIDTH + Showcase.GAP
	local colWidth = width - x
	local innerWidth = colWidth - 2 * P.padX

	-- A panel with the mockup's 18 px side padding.
	local function panel(title)
		local p = Widgets.Panel(v, title)
		if p.title then
			p.title:ClearAllPoints()
			p.title:SetPoint("TOPLEFT", P.padX, -P.padY)
		end
		p:SetWidth(colWidth)
		return p
	end

	-- From the game: read live from the client, never stored (mockup: key
	-- 110 wide in Cinzel capitals, value 16 in title white, rows 38 apart
	-- with a line between).
	v.game = panel("From the game")
	v.game:SetPoint("TOPLEFT", x, 0)
	v.game.rows = {}
	for i = 1, 4 do
		local top = P.rowsTop + (i - 1) * P.rowHeight
		local row = { top = top }
		row.key = Widgets.Label(v.game, "GameFontNormalSmall", false, "eyebrow")
		row.key:SetPoint("TOPLEFT", P.padX, -(top + 12))
		row.key:SetWidth(P.keyWidth)
		row.value = Widgets.Label(v.game, "reading", false, "title")
		row.value:SetPoint("TOPLEFT", P.padX + P.keyWidth + 10, -(top + 9))
		row.value:SetWidth(innerWidth - P.keyWidth - 10)
		if i < 4 then
			row.rule = Widgets.Divider(v.game)
			row.rule:SetPoint("TOPLEFT", P.padX, -(top + P.rowHeight))
			row.rule:SetPoint("TOPRIGHT", -P.padX, -(top + P.rowHeight))
			Style.Register(row.rule, function(l, theme) Style.Color(l, Style.Tones(theme).track) end)
		end
		v.game.rows[i] = row
	end
	v.game:SetHeight(P.rowsTop + 4 * P.rowHeight + P.padY - 6)

	-- In your own words: written by the player.
	v.own = panel("In your own words")
	v.own:SetPoint("TOPLEFT", v.game, "BOTTOMLEFT", 0, -P.gap)
	-- Mockup: the title in Cinzel (title white), then the summary at 16.
	v.own.title = Widgets.Label(v.own, "GameFontNormalLarge", true, "title")
	v.own.title:SetWidth(innerWidth)
	v.own.summary = Widgets.Label(v.own, "reading", true, "reading")
	v.own.summary:SetWidth(innerWidth)
	v.own.edit = Widgets.Button(v.own, "Edit", 56, Style.CONTROL.compact, "ghost")
	v.own.edit:SetPoint("TOPRIGHT", -P.padX, -(P.padY - 6))
	v.own.edit:SetScript("OnClick", function() if opts.onEditProfile then opts.onEditProfile() end end)
	Widgets.Tooltip(v.own.edit, "Profile fields", "Edit what you wrote about your character.")

	-- The portrait note and the player's own choice.
	v.note = panel()
	v.note:SetPoint("TOPLEFT", v.own, "BOTTOMLEFT", 0, -P.gap)
	v.note.text = Widgets.Label(v.note, "meta", true, "muted")
	v.note.text:SetPoint("TOPLEFT", P.padX, -12)
	v.note.text:SetWidth(innerWidth)
	v.note.toggle = Widgets.Button(v.note, "Show portrait instead", 210, Style.CONTROL.compact)
	v.note.toggle:SetScript("OnClick", function()
		local m = v.model
		if not m.preferPortrait and m.state == "unavailable" then
			-- The player chose the live model; it just failed: try again.
			m.Retry()
			return
		end
		local on = not m.preferPortrait
		-- A refused save (read-only data) leaves the view as it was.
		if opts.onPreferPortrait and not opts.onPreferPortrait(on) then return end
		m:SetPreferPortrait(on)
		v.UpdateNote()
	end)

	--- The note and the toggle always say what is showing and how to change it.
	function v.UpdateNote()
		local m = v.model
		local note, button = Showcase.FALLBACK_NOTE, "Show portrait instead"
		if m.state == "unavailable" then
			note = "The live model could not be loaded just now, so your portrait is shown. It is tried again "
				.. "when the showcase reopens, your gear changes, or you ask."
			button = "Try the live model again"
		elseif m.state == "loading" then
			note = "Loading your live model. Your portrait is shown until it is ready."
		elseif m.preferPortrait then
			note = "You chose to show your portrait instead of the live model."
			button = "Show the live model"
		end
		v.note.text:SetText(note)
		v.note.toggle:SetText(button)
		local h = v.note.text:GetStringHeight()
		v.note.toggle:ClearAllPoints()
		v.note.toggle:SetPoint("TOPLEFT", P.padX, -(12 + h + 10))
		v.note:SetHeight(12 + h + 10 + Style.CONTROL.compact + 12)
	end

	--- Re-reads the game identity and the player's words.
	function v.Refresh(_, char, preferPortrait)
		v.model:SetPreferPortrait(preferPortrait)
		for i, row in ipairs(Showcase.GameRows(Showcase.GameIdentity())) do
			local r = v.game.rows[i]
			r.key:SetText(row.label:upper())
			r.value:SetText(row.value)
			r.value.textRole = row.empty and "muted" or "heading"
			Style.Repaint(r.value)
		end

		local own = Showcase.OwnWords(char)
		local y = P.ownTop
		local function place(fs, value, gap)
			fs:ClearAllPoints()
			if value then
				fs:SetText(value)
				fs:SetPoint("TOPLEFT", P.padX, -y)
				fs:Show()
				y = y + fs:GetStringHeight() + (gap or 6)
			else
				fs:SetText("")
				fs:Hide()
			end
		end
		if own.empty then
			place(v.own.summary, "You have not written your character's name, title or summary yet. "
				.. "Add them under Profile fields.", 10)
			v.own.title:Hide()
		else
			place(v.own.title, own.heading, 8)
			place(v.own.summary, own.summary, 10)
		end
		v.own:SetHeight(y + P.padY)
		v.UpdateNote()
	end

	-- The note follows the model card's state (model, chosen or forced portrait).
	v.model.onUpdate = function() v.UpdateNote() end

	-- Live game data: the guild can change while the showcase is open.
	-- Listens only while shown.
	v:SetScript("OnShow", function() v:RegisterEvent("PLAYER_GUILD_UPDATE") end)
	v:SetScript("OnHide", function() v:UnregisterEvent("PLAYER_GUILD_UPDATE") end)
	v:SetScript("OnEvent", function()
		if v:IsVisible() then ns.MainWindow.Refresh() end
	end)
	return v
end

-- /dawnward dev showcase (development builds only): what the model card knows
-- about the live model, for checking it in game. Read-only.
if ns.SetupCommands and ns.SetupCommands.DEV_AREAS then
	ns.SetupCommands.DEV_AREAS.showcase = {
		usage = "dev showcase",
		run = function(ctx)
			local section = ns.CharacterView and ns.CharacterView.section
			local model = section and section.showcase
			if not model then
				ctx.print("Showcase: not opened yet this session. Open Character, then Showcase.")
				return
			end
			for _, line in ipairs(model.Diagnostics()) do ctx.print(line) end
		end,
	}
end
