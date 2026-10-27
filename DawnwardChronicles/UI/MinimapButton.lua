-- A button on the minimap that opens the journal (#45). Click to open or
-- close the journal, right-click for story moments, drag to move it around
-- the minimap. It can be hidden from Settings or with /dawnward minimap.
-- Its angle and hidden state are account-wide (DawnwardChroniclesDB.ui).
local _, ns = ...
local MainWindow, Actions = ns.MainWindow, ns.Actions

local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.DEFAULT_ANGLE = 200 -- lower left, clear of the default clock and tracking buttons
MinimapButton.RADIUS = 80
MinimapButton.ICON = "Interface\\Icons\\INV_Misc_Book_09"

--- Offset from the minimap's centre for an angle in degrees. Pure.
function MinimapButton.Offset(angle, radius)
	local rad = math.rad(angle or MinimapButton.DEFAULT_ANGLE)
	radius = radius or MinimapButton.RADIUS
	return math.cos(rad) * radius, math.sin(rad) * radius
end

--- Angle in degrees [0, 360) of a point relative to the minimap's centre. Pure.
function MinimapButton.Angle(dx, dy)
	return math.deg(math.atan2(dy, dx)) % 360
end

--- Tooltip lines for the current state. Pure apart from reading the ctx.
function MinimapButton.TooltipLines(ctx)
	local lines = { "Click: open or close your journal.", "Right-click: story moments.",
		"Drag: move this button." }
	local char = ctx and Actions.Character(ctx)
	local waiting = char and ns.Reactions and #ns.Reactions.List(char, ctx.now()) or 0
	if waiting > 0 then
		table.insert(lines, 1, string.format("%d story moment%s waiting.", waiting, waiting == 1 and " is" or "s are"))
	end
	return lines
end

local function place(button, angle)
	local x, y = MinimapButton.Offset(angle)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function cursorAngle()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	return MinimapButton.Angle(cx / scale - mx, cy / scale - my)
end

function MinimapButton.Create(ctx)
	if MinimapButton.button or not Minimap then
		return MinimapButton.button
	end
	local b = CreateFrame("Button", "DawnwardChroniclesMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(MinimapButton.ICON)
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	b.icon = icon
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			if ctx.ui and ctx.ui.ShowStory then ctx.ui.ShowStory() end
		else
			MainWindow.Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", function(frame) place(frame, cursorAngle()) end)
	end)
	b:SetScript("OnDragStop", function(self)
		self.dragging = nil
		self:SetScript("OnUpdate", nil)
		Actions.SaveMinimap(ctx, { angle = cursorAngle() })
		MinimapButton.Update(ctx)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Dawnward Chronicles")
		for _, line in ipairs(MinimapButton.TooltipLines(ctx)) do
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	MinimapButton.button = b
	MinimapButton.Update(ctx)
	return b
end

--- Places and shows or hides the button from the saved settings.
function MinimapButton.Update(ctx)
	local b = MinimapButton.button
	if not b then return end
	local settings = Actions.MinimapSettings(ctx)
	place(b, settings.angle or MinimapButton.DEFAULT_ANGLE)
	b:SetShown(not settings.hidden)
end

--- Called once at login.
function MinimapButton.Init(ctx)
	ctx.ui = ctx.ui or {}
	ctx.ui.UpdateMinimap = function() MinimapButton.Update(ctx) end
	return MinimapButton.Create(ctx)
end

