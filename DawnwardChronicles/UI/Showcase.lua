-- Character presentation (v0.7): the player's own portrait for the window's
-- side rail, and a live 3D model for the Character Showcase.
--
-- Client APIs (checked against the Classic Era 1.15.9.70576 UI source):
--   SetPortraitTexture(texture, "player")   the game's round portrait, as on
--                                           unit frames
--   CreateFrame("PlayerModel")              the character model frame Blizzard's
--                                           own Classic panels use (QuestFrame,
--                                           TabardFrame): SetUnit("player"),
--                                           SetRotation, SetPortraitZoom,
--                                           ClearModel; UNIT_MODEL_CHANGED when
--                                           gear or form changes
-- Nothing is invented: the model is the client's own rendering of the
-- player's character in the gear they are wearing, and the portrait is the
-- client's. When the model cannot be shown (SetUnit fails, or the unit is
-- not ready yet), the portrait is shown in its place.
--
-- Performance: the model is set only while the showcase is visible and is
-- cleared when it hides, so a closed journal renders nothing. Events are
-- registered only while shown.
local _, ns = ...
local Style, Widgets = ns.Style, ns.Widgets

local Showcase = {}
ns.Showcase = Showcase

Showcase.ROTATE_STEP = math.pi / 8
Showcase.DRAG_SPEED = 0.01 -- radians per pixel of mouse movement
Showcase.RING = "Interface\\Minimap\\MiniMap-TrackingBorder"

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return nil
end

--- What the game says about the player: { level, raceName, className,
-- classToken, classColor }. Read live; never stored.
function Showcase.GameIdentity()
	local race = call(UnitRace, "player")
	local className, classToken = call(UnitClass, "player")
	local colors = type(RAID_CLASS_COLORS) == "table" and classToken and RAID_CLASS_COLORS[classToken] or nil
	return {
		level = call(UnitLevel, "player"),
		raceName = type(race) == "string" and race or nil,
		className = type(className) == "string" and className or nil,
		classToken = classToken,
		classColor = colors and { colors.r, colors.g, colors.b } or nil,
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

--- A live 3D model of the player with rotate buttons and drag to turn,
-- falling back to the portrait. Returns a frame with :Update(), :Rotate(d).
function Showcase.Model(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	f.bg = Style.Fill(f, "panel", "BACKGROUND")
	f.bg:SetAllPoints(f)
	f.edges = Style.Edge(f, "BORDER")
	Style.Register(f.edges, function(e, theme) e:Paint(theme.border or theme.edge, 1) end)

	f.model = CreateFrame("PlayerModel", nil, f)
	f.model:SetPoint("TOPLEFT", 1, -1)
	f.model:SetPoint("BOTTOMRIGHT", -1, 40)
	f.model:EnableMouse(true)
	f.rotation = 0

	f.fallback = Showcase.Portrait(f, math.min(width, height - 40) - 40)
	f.fallback:SetPoint("CENTER", 0, 20)
	f.fallback:Hide()

	f.note = Widgets.Label(f, "GameFontHighlightSmall", true, "muted")
	f.note:SetPoint("BOTTOMLEFT", 92, 10)
	f.note:SetPoint("BOTTOMRIGHT", -10, 10)
	f.note:SetText("Drag to turn. Shows the gear you are wearing now.")

	function f.Rotate(_, delta)
		f.rotation = (f.rotation + delta) % (2 * math.pi)
		if f.model.SetRotation then f.model:SetRotation(f.rotation) end
	end
	f.left = Widgets.Button(f, "<", 34, 28)
	f.left:SetPoint("BOTTOMLEFT", 10, 8)
	f.left:SetScript("OnClick", function() f:Rotate(-Showcase.ROTATE_STEP) end)
	Widgets.Tooltip(f.left, "Turn left")
	f.right = Widgets.Button(f, ">", 34, 28)
	f.right:SetPoint("LEFT", f.left, "RIGHT", 6, 0)
	f.right:SetScript("OnClick", function() f:Rotate(Showcase.ROTATE_STEP) end)
	Widgets.Tooltip(f.right, "Turn right")

	-- Drag to turn: the model follows the cursor while the button is held.
	f.model:SetScript("OnMouseDown", function()
		f.dragX = call(GetCursorPosition)
	end)
	f.model:SetScript("OnMouseUp", function() f.dragX = nil end)
	f.model:SetScript("OnUpdate", function()
		if not f.dragX then return end
		local x = call(GetCursorPosition)
		if x then
			f:Rotate((x - f.dragX) * Showcase.DRAG_SPEED)
			f.dragX = x
		end
	end)

	--- Shows the model, or the portrait when the model is not available.
	function f.Update()
		local ok = f.model.SetUnit and call(f.model.SetUnit, f.model, "player")
		f.modelShown = ok and true or false
		f.model:SetShown(f.modelShown)
		f.fallback:SetShown(not f.modelShown)
		if f.modelShown then
			if f.model.SetRotation then f.model:SetRotation(f.rotation) end
		else
			f.fallback.Update()
		end
	end

	f:SetScript("OnShow", function()
		f:RegisterEvent("UNIT_MODEL_CHANGED")
		f.Update()
	end)
	f:SetScript("OnHide", function()
		f:UnregisterEvent("UNIT_MODEL_CHANGED")
		f.dragX = nil
		-- Nothing is rendered while the journal is closed.
		if f.model.ClearModel then f.model:ClearModel() end
	end)
	f:SetScript("OnEvent", function(_, _, unit)
		if unit == "player" and f:IsVisible() then f.Update() end
	end)
	return f
end
