-- Character presentation (v0.7): the player's own portrait for the window's
-- side rail, and the Character Showcase (approved mockup
-- docs/design/mockups/proposed-character-showcase.png): a live 3D model of
-- the player beside what the game says about them ("In game") and what the
-- player wrote ("Your character"), kept visibly apart.
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
Showcase.BAR_HEIGHT = 56 -- the control bar under the model
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

--- A live 3D model of the player with rotate and zoom buttons, drag to
-- turn and the mouse wheel to zoom, falling back to the portrait. Returns a
-- frame with :Update(), :Rotate(d), :Zoom(d), :SetPreferPortrait(on).
function Showcase.Model(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	f.bg = Style.Fill(f, "panel", "BACKGROUND")
	f.bg:SetAllPoints(f)
	f.edges = Style.Edge(f, "BORDER")
	Style.Register(f.edges, function(e, theme) e:Paint(theme.border or theme.edge, 1) end)

	local bar = Showcase.BAR_HEIGHT
	f.model = CreateFrame("PlayerModel", nil, f)
	f.model:SetPoint("TOPLEFT", 1, -1)
	f.model:SetPoint("BOTTOMRIGHT", -1, bar)
	f.model:EnableMouse(true)
	if f.model.EnableMouseWheel then f.model:EnableMouseWheel(true) end
	f.rotation = 0
	f.zoom = Showcase.ZOOM_MIN

	f.fallback = Showcase.Portrait(f, math.max(60, math.min(width, height - bar) - 60))
	f.fallback:SetPoint("CENTER", 0, bar / 2)
	f.fallback:Hide()

	-- What is showing: "Live model" or "Portrait".
	f.chip = Widgets.Chip(f, "Live model", "accent")
	f.chip:SetPoint("TOPLEFT", 12, -12)
	-- Above the model, which draws over its siblings at the same level.
	local level = f.model.GetFrameLevel and f.model:GetFrameLevel()
	if type(level) == "number" and f.chip.SetFrameLevel then f.chip:SetFrameLevel(level + 2) end

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

	local function controlButton(glyph, title, tip)
		local b = Widgets.Button(f, glyph, 30, 28)
		Widgets.Tooltip(b, title, tip)
		return b
	end
	f.left = controlButton("<", "Turn left")
	f.left:SetPoint("BOTTOMLEFT", 10, 14)
	f.left:SetScript("OnClick", function() f:Rotate(-Showcase.ROTATE_STEP) end)
	f.right = controlButton(">", "Turn right")
	f.right:SetPoint("LEFT", f.left, "RIGHT", 4, 0)
	f.right:SetScript("OnClick", function() f:Rotate(Showcase.ROTATE_STEP) end)
	f.zoomOut = controlButton("-", "Zoom out", "The mouse wheel over the model also zooms.")
	f.zoomOut:SetPoint("LEFT", f.right, "RIGHT", 10, 0)
	f.zoomOut:SetScript("OnClick", function() f:Zoom(-Showcase.ZOOM_STEP) end)
	f.zoomIn = controlButton("+", "Zoom in", "The mouse wheel over the model also zooms.")
	f.zoomIn:SetPoint("LEFT", f.zoomOut, "RIGHT", 4, 0)
	f.zoomIn:SetScript("OnClick", function() f:Zoom(Showcase.ZOOM_STEP) end)

	f.note = Widgets.Label(f, "GameFontHighlightSmall", true, "muted")
	f.note:SetPoint("BOTTOMLEFT", 10 + 4 * 34 + 10, 10)
	f.note:SetPoint("BOTTOMRIGHT", -10, 10)
	f.note:SetHeight(bar - 18)
	f.note:SetJustifyV("MIDDLE")
	f.note:SetText("Drag to turn, scroll to zoom. Shows the gear you are wearing now.")

	function f.UpdateControls()
		local on = f.modelShown and true or false
		for _, b in ipairs({ f.left, f.right }) do b:SetEnabled(on) end
		f.zoomOut:SetEnabled(on and f.zoom > Showcase.ZOOM_MIN)
		f.zoomIn:SetEnabled(on and f.zoom < Showcase.ZOOM_MAX)
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

--- The "Your character" content, from the player's own profile fields:
-- { name, title, pronouns, summary, chips = { { text, tone } } }. Pure.
function Showcase.OwnWords(char)
	local fields = char and char.fields or {}
	local function value(key)
		return fields[key] and text(fields[key].value)
	end
	local out = { name = value("name"), title = value("title"), pronouns = value("pronouns"), chips = {} }
	local summary = value("summary")
	out.summary = summary and shorten(summary, Showcase.SUMMARY_MAX)
	for _, key in ipairs({ "name", "title", "pronouns", "summary" }) do
		local entry = fields[key]
		if entry and text(entry.value) then
			local level = entry.visibility or "private"
			local label = ns.Schema and ns.Schema.FIELD_BY_KEY[key] and ns.Schema.FIELD_BY_KEY[key].label or key
			out.chips[#out.chips + 1] = { text = label .. " is " .. (ns.Themes.VISIBILITY_LABELS[level] or level),
				tone = level }
		end
	end
	out.empty = not (out.name or out.title or out.pronouns or out.summary)
	return out
end

--- The whole showcase: model card on the left; "In game", "Your character"
-- and the portrait note on the right. onPreferPortrait(on) saves the
-- player's choice; onEditProfile() returns to the profile fields.
-- Returns a frame with :Refresh(char, preferPortrait), .model (the model card).
function Showcase.View(parent, width, height, opts)
	opts = opts or {}
	local v = CreateFrame("Frame", nil, parent)
	v:SetSize(width, height)
	v.model = Showcase.Model(v, Showcase.MODEL_WIDTH, height)
	v.model:SetPoint("TOPLEFT", 0, 0)

	local x = Showcase.MODEL_WIDTH + Showcase.GAP
	local colWidth = width - x
	local innerWidth = colWidth - 2 * Widgets.PANEL_PAD

	-- In game: read live from the client, never stored.
	v.game = Widgets.Panel(v, "In game")
	v.game:SetPoint("TOPLEFT", x, 0)
	v.game:SetWidth(colWidth)
	v.game.rows = {}
	for i = 1, 4 do
		local row = {}
		row.key = Widgets.Label(v.game, "GameFontNormalSmall", false, "eyebrow")
		row.key:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -(36 + (i - 1) * 30 + 8))
		row.key:SetWidth(110)
		row.value = Widgets.Label(v.game, "GameFontHighlight", false, "body")
		row.value:SetPoint("TOPLEFT", Widgets.PANEL_PAD + 120, -(36 + (i - 1) * 30 + 6))
		row.value:SetWidth(innerWidth - 120)
		if i < 4 then
			row.rule = Widgets.Divider(v.game)
			row.rule:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -(36 + i * 30))
			row.rule:SetPoint("TOPRIGHT", -Widgets.PANEL_PAD, -(36 + i * 30))
		end
		v.game.rows[i] = row
	end
	v.game:SetHeight(36 + 4 * 30 + 8)

	-- Your character: written by the player, with each field's visibility.
	v.own = Widgets.Panel(v, "Your character")
	v.own:SetPoint("TOPLEFT", v.game, "BOTTOMLEFT", 0, -12)
	v.own:SetWidth(colWidth)
	v.own.name = Widgets.Label(v.own, "GameFontNormalLarge", true, "title")
	v.own.name:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -36)
	v.own.name:SetWidth(innerWidth)
	v.own.title = Widgets.Label(v.own, "GameFontHighlight", true, "accent")
	v.own.title:SetWidth(innerWidth)
	v.own.pronouns = Widgets.Label(v.own, "GameFontHighlightSmall", true, "muted")
	v.own.pronouns:SetWidth(innerWidth)
	v.own.summary = Widgets.Label(v.own, "GameFontHighlight", true, "body")
	v.own.summary:SetWidth(innerWidth)
	v.own.chips = {}
	v.own.edit = Widgets.Button(v.own, "Profile fields", 120, 22, "ghost")
	v.own.edit:SetPoint("TOPRIGHT", -Widgets.PANEL_PAD, -10)
	v.own.edit:SetScript("OnClick", function() if opts.onEditProfile then opts.onEditProfile() end end)
	Widgets.Tooltip(v.own.edit, "Profile fields", "Edit what you wrote, and who may see each part.")

	-- The portrait note and the player's own choice.
	v.note = Widgets.Panel(v)
	v.note:SetPoint("TOPLEFT", v.own, "BOTTOMLEFT", 0, -12)
	v.note:SetWidth(colWidth)
	v.note.text = Widgets.Label(v.note, "GameFontHighlightSmall", true, "muted")
	v.note.text:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -12)
	v.note.text:SetWidth(innerWidth)
	v.note.toggle = Widgets.Button(v.note, "Show portrait instead", 190, 22)
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
		v.note.toggle:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -(12 + h + 8))
		v.note:SetHeight(12 + h + 8 + 22 + 12)
	end

	local function chip(i)
		local c = v.own.chips[i]
		if not c then
			c = Widgets.Chip(v.own, "", "private")
			v.own.chips[i] = c
		end
		return c
	end

	--- Re-reads the game identity and the player's words.
	function v.Refresh(_, char, preferPortrait)
		v.model:SetPreferPortrait(preferPortrait)
		for i, row in ipairs(Showcase.GameRows(Showcase.GameIdentity())) do
			local r = v.game.rows[i]
			r.key:SetText(row.label:upper())
			r.value:SetText(row.value)
			r.value.textRole = row.empty and "muted" or "text"
			Style.Repaint(r.value)
		end

		local own = Showcase.OwnWords(char)
		local y = 36
		local function place(fs, value, gap)
			fs:ClearAllPoints()
			if value then
				fs:SetText(value)
				fs:SetPoint("TOPLEFT", Widgets.PANEL_PAD, -y)
				fs:Show()
				y = y + fs:GetStringHeight() + (gap or 6)
			else
				fs:SetText("")
				fs:Hide()
			end
		end
		if own.empty then
			place(v.own.summary, "You have not written your character's name, title or summary yet. "
				.. "Add them under Profile fields; only you decide what is public.", 8)
			v.own.name:Hide(); v.own.title:Hide(); v.own.pronouns:Hide()
		else
			place(v.own.name, own.name, 4)
			place(v.own.title, own.title, 4)
			place(v.own.pronouns, own.pronouns, 8)
			place(v.own.summary, own.summary, 8)
		end
		local cx = Widgets.PANEL_PAD
		for i, c in ipairs(own.chips) do
			local w = chip(i)
			w:SetChip(c.text, c.tone)
			local cw = w:GetWidth()
			if cx > Widgets.PANEL_PAD and cx + cw > colWidth - Widgets.PANEL_PAD then
				cx = Widgets.PANEL_PAD
				y = y + Widgets.CHIP_HEIGHT + 6
			end
			w:ClearAllPoints()
			w:SetPoint("TOPLEFT", cx, -y)
			w:Show()
			cx = cx + cw + 6
		end
		for i = #own.chips + 1, #v.own.chips do v.own.chips[i]:Hide() end
		if #own.chips > 0 then y = y + Widgets.CHIP_HEIGHT end
		v.own:SetHeight(y + Widgets.PANEL_PAD)
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
