-- Minimal WoW client mock for load tests (L2).
--
-- Only what Dawnward's Platform and UI layers touch is modelled. Frames
-- accept any other method as a no-op, so these tests prove wiring and
-- behaviour of our code, not that the FrameXML calls are valid: only an
-- in-game (L3) run proves that.

local Mock = {}

local function noop() end

local Methods = {}

function Methods:SetScript(script, fn) self.__scripts[script] = fn end
-- Keyboard focus, like the client: one EditBox at a time, with its focus scripts.
function Methods:SetFocus()
	local mock = self.__mock
	if mock.focus == self then return end
	if mock.focus then mock.focus:ClearFocus() end
	mock.focus = self
	if self.__scripts.OnEditFocusGained then self.__scripts.OnEditFocusGained(self) end
end
function Methods:ClearFocus()
	local mock = self.__mock
	if mock.focus ~= self then return end
	mock.focus = nil
	if self.__scripts.OnEditFocusLost then self.__scripts.OnEditFocusLost(self) end
end
function Methods:HasFocus() return self.__mock.focus == self end
function Methods:GetParent() return self.__parent end
-- Like the client: a frame can move to another parent (pooled rows change columns).
function Methods:SetParent(parent) self.__parent = parent end
-- Shown, and every parent shown too.
function Methods:IsVisible()
	if not self.__shown then return false end
	local parent = self.__parent
	return parent == nil or parent:IsVisible()
end
function Methods:GetScript(script) return self.__scripts[script] end
-- Like the client: a hook runs after the existing handler.
function Methods:HookScript(script, fn)
	local old = self.__scripts[script]
	if not old then
		self.__scripts[script] = fn
		return
	end
	self.__scripts[script] = function(...)
		old(...)
		fn(...)
	end
end
function Methods:RegisterEvent(event)
	self.__events[event] = true
	self.__mock.eventFrames[self] = true
end
function Methods:UnregisterEvent(event) self.__events[event] = nil end
-- Like the client, hiding a shown frame fires its OnHide (showing: OnShow).
function Methods:Show()
	local was = self.__shown
	self.__shown = true
	if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function Methods:Hide()
	local was = self.__shown
	self.__shown = false
	if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function Methods:IsShown() return self.__shown end
-- Like the client, an EditBox keeps at most maxBytes - 1 bytes of text.
function Methods:SetText(text)
	if self.__maxBytes and self.__maxBytes > 0 and type(text) == "string" and #text > self.__maxBytes - 1 then
		text = text:sub(1, self.__maxBytes - 1)
	end
	self.__text = text
end
function Methods:SetMaxBytes(n) self.__maxBytes = n end
function Methods:GetText() return self.__text end
function Methods:Enable() self.__enabled = true end
function Methods:Disable() self.__enabled = false end
function Methods:IsEnabled() return self.__enabled end
function Methods:GetName() return self.__name end
function Methods:CreateFontString(name, layer, template)
	local fs = self.__mock.newFrame("FontString", name, self)
	fs.__layer, fs.__template = layer, template
	return fs
end
-- Fonts: SetFont succeeds unless mock.fontFails names the file (a missing font).
-- As in 1.15.9 (SimpleFontAPIDocumentation), a Font object's SetFont returns
-- nothing; a FontString's or EditBox's returns success.
function Methods:SetFont(file, height, flags)
	local failed = self.__mock.fontFails and tostring(file):find(self.__mock.fontFails, 1, true)
	if not failed then
		self.__font = { file = file, height = height, flags = flags }
	end
	if self.__kind == "Font" then return end
	return not failed
end
function Methods:GetObjectType() return self.__kind end
function Methods:EnableMouse(on) self.__mouse = on and true or false end
function Methods:IsMouseEnabled() return self.__mouse == true end
function Methods:GetFont() return self.__font and self.__font.file, self.__font and self.__font.height end
function Methods:SetFontObject(font) self.__fontObject = font end
-- Models: SetUnit fails on a model frame that is not visible (a hidden
-- model cannot load), and while mock.modelFails is set: true fails every
-- call, a number fails that many calls and then counts down.
function Methods:SetUnit(unit, blend)
	self.__mock.setUnitCalls = (self.__mock.setUnitCalls or 0) + 1
	self.__blend = blend
	local fails = self.__mock.modelFails
	if type(fails) == "number" then
		if fails > 0 then
			self.__mock.modelFails = fails - 1
			return false
		end
	elseif fails then
		return false
	end
	if not self:IsVisible() then return false end
	self.__unit = unit
	return true
end
function Methods:SetAlpha(a) self.__alpha = a end
-- Textures: the file last set (state textures record theirs the same way).
function Methods:SetTexture(file) self.__texture = file end
function Methods:GetAlpha() return self.__alpha or 1 end
function Methods:ClearModel() self.__unit = nil end
function Methods:SetRotation(r) self.__rotation = r end
function Methods:GetRotation() return self.__rotation or 0 end
function Methods:CreateTexture(name, layer, _, sublevel)
	local tex = self.__mock.newFrame("Texture", name, self)
	tex.__layer, tex.__sublevel = layer, sublevel
	self.__textures = self.__textures or {}
	self.__textures[#self.__textures + 1] = tex
	return tex
end

-- Line regions (SimpleLineAPI): start and end points and thickness recorded.
function Methods:CreateLine(name, layer, _, sublevel)
	local line = self.__mock.newFrame("Line", name, self)
	line.__layer, line.__sublevel = layer, sublevel
	return line
end
function Methods:SetStartPoint(...) self.__start = { ... } end
function Methods:SetEndPoint(...) self.__end = { ... } end
function Methods:SetThickness(t) self.__thickness = t end

-- Layout and layering state, recorded so UI tests can check it.
function Methods:SetFrameStrata(strata) self.__strata = strata end
function Methods:GetFrameStrata() return self.__strata or "MEDIUM" end
function Methods:SetToplevel(on) self.__toplevel = on end
function Methods:Raise() self.__raised = (self.__raised or 0) + 1 end
function Methods:SetBackdrop(backdrop) self.__backdrop = backdrop end
function Methods:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a or 1 } end
function Methods:SetTextInsets(l, r, t, b) self.__insets = { l, r, t, b } end
function Methods:SetWidth(w) self.__width = w end
function Methods:GetWidth() return self.__width or 0 end
function Methods:SetHeight(h) self.__height = h end
function Methods:GetHeight() return self.__height or 0 end
function Methods:SetSize(w, h) self.__width, self.__height = w, h end
function Methods:ClearAllPoints() self.__points = {} end
function Methods:SetPoint(...)
	self.__points = self.__points or {}
	self.__points[#self.__points + 1] = { ... }
end
function Methods:SetVerticalScroll(v) self.__vscroll = v end
function Methods:GetVerticalScroll() return self.__vscroll or 0 end
-- Scroll frames: the range is how much taller the scroll child is than the
-- frame (both as last sized), as the client computes it.
function Methods:SetScrollChild(child)
	self.__scrollChild = child
	child.__scrollParent = self
end
function Methods:GetScrollChild() return self.__scrollChild end
function Methods:GetVerticalScrollRange()
	local child = self.__scrollChild
	if not child then return 0 end
	return math.max(0, (child.__height or 0) - (self.__height or 0))
end
function Methods:EnableMouseWheel(on) self.__wheel = on and true or false end
function Methods:IsMouseWheelEnabled() return self.__wheel == true end
function Methods:SetWordWrap(on) self.__wordWrap = on end
function Methods:SetShown(on)
	if on then self:Show() else self:Hide() end
end
function Methods:SetEnabled(on) self.__enabled = on and true or false end
function Methods:GetLeft() return self.__left or 100 end
function Methods:GetTop() return self.__top or 600 end
function Methods:GetCenter() return self.__cx or 500, self.__cy or 400 end
function Methods:GetEffectiveScale() return 1 end
function Methods:SetScale(scale) self.__scale = scale end
function Methods:GetScale() return self.__scale or 1 end
-- Button state textures (resize handle).
for _, state in ipairs({ "Normal", "Highlight", "Pushed" }) do
	Methods["Set" .. state .. "Texture"] = function(self, file)
		local tex = self.__mock.newFrame("Texture", nil, self)
		tex.__texture = file
		self["__" .. state] = tex
	end
	Methods["Get" .. state .. "Texture"] = function(self) return self["__" .. state] end
end
-- A texture's file (only recorded; nothing is drawn).
function Methods:SetTexture(file) self.__texture = file end
function Methods:SetTextColor(r, g, b) self.__textColor = { r, g, b } end
function Methods:SetFontString(fs) self.__fontString = fs end
function Methods:GetFontString()
	self.__fontString = self.__fontString or self.__mock.newFrame("FontString", nil, self)
	return self.__fontString
end
-- Rough text height: one 14px line per 60 characters of width-independent text.
function Methods:GetStringHeight()
	local text = self.__text or ""
	if text == "" then return 0 end
	return 14 * math.max(1, math.ceil(#text / 60))
end

local FrameMT = {
	__index = function(_, key)
		if Methods[key] then
			return Methods[key]
		end
		-- Like the real client, unknown fields read as nil. Widget methods are
		-- PascalCase, so any unmodelled method is accepted as a no-op; our own
		-- fields (lowercase) and recorded state ("__x") stay nil until set.
		if type(key) == "string" and key:match("^%u") then
			return noop
		end
		return nil
	end,
}

--- opts: { interface = number, project = number, savedVariables = table, extra = table }
function Mock.new(opts)
	opts = opts or {}
	-- clock: what time() returns (real dates); mono: what GetTime() returns.
	-- allFrames: every frame, texture and font string, in creation order (for
	-- sweeps over everything a screen shows, e.g. tests/spec/ui_no_privacy_spec.lua).
	local mock = { eventFrames = {}, framesByName = {}, allFrames = {}, chat = {}, clock = 1700000000, popups = {},
		timers = {}, tickers = {}, mono = 1000,
		zone = "Elwynn Forest", subzone = "Goldshire" }

	--- Accepts the most recent confirmation dialog, like clicking its first button.
	function mock.AcceptPopup()
		local popup = table.remove(mock.popups)
		assert(popup, "no confirmation dialog is open")
		local def = mock.env.StaticPopupDialogs[popup.name]
		def.OnAccept(nil, popup.data)
		return popup
	end

	function mock.newFrame(kind, name, parent)
		local f = setmetatable({
			__mock = mock, __kind = kind, __name = name, __parent = parent,
			__scripts = {}, __events = {}, __shown = true, __text = "", __enabled = true,
		}, FrameMT)
		if name then
			mock.framesByName[name] = f
		end
		mock.allFrames[#mock.allFrames + 1] = f
		return f
	end

	local env = {
		WOW_PROJECT_ID = opts.project or 2,
		WOW_PROJECT_CLASSIC = 2,
		GetBuildInfo = function()
			return "1.15.x", "00000", "mock", opts.interface or 11509
		end,
		CreateFrame = function(kind, name, parent) return mock.newFrame(kind, name, parent) end,
		CreateFont = function(name) return mock.newFrame("Font", name) end,
		GetLocale = function() return mock.locale or "enUS" end,
		SetPortraitTexture = function(texture, unit) texture.__portrait = unit end,
		STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
		UIParent = mock.newFrame("Frame", "UIParent"),
		UISpecialFrames = {},
		tinsert = table.insert,
		BackdropTemplateMixin = {},
		ChatFontNormal = {},
		GameFontNormal = {},
		GameFontHighlightSmall = {},
		InCombatLockdown = function() return mock.inCombat == true end,
		IsShiftKeyDown = function() return mock.shift == true end,
		C_Timer = {
			After = function(seconds, fn) mock.timers[#mock.timers + 1] = { seconds = seconds, fn = fn } end,
			NewTicker = function(seconds, fn)
				local ticker = { seconds = seconds, fn = fn }
				mock.tickers[#mock.tickers + 1] = ticker
				return ticker
			end,
		},
		-- GetTime: seconds since the computer started (mock.mono, moved by mock.Play).
		GetTime = function() return mock.mono end,
		UnitIsAFK = function() return mock.afk == true end,
		GameFontNormalLarge = {},
		GameFontHighlight = {},
		GameTooltip = mock.newFrame("GameTooltip", "GameTooltip"),
		Minimap = mock.newFrame("Frame", "Minimap"),
		GetCursorPosition = function() return mock.cursorX or 500, mock.cursorY or 400 end,
		StaticPopupDialogs = {},
		StaticPopup_Show = function(name, textArg, _, data)
			mock.popups[#mock.popups + 1] = { name = name, text = textArg, data = data }
		end,
		-- UTC, so the output is the same on every machine.
		date = function(fmt, t) return os.date("!" .. tostring(fmt):gsub("^!", ""), t) end,
		GetRealZoneText = function() return mock.zone end,
		GetSubZoneText = function() return mock.subzone end,
		UnitName = function() return "Testchar" end,
		UnitLevel = function() return mock.level or 20 end,
		UnitClass = function() return "Mage", mock.classToken or "MAGE", 8 end,
		UnitRace = function() return "Orc", mock.raceToken or "Orc", 2 end,
		UnitFactionGroup = function() return mock.faction or "Horde", "Horde" end,
		UnitIsDeadOrGhost = function() return mock.dead == true end,
		GetQuestID = function() return mock.quest and mock.quest.id or 0 end,
		GetTitleText = function() return mock.quest and mock.quest.title or "" end,
		GetQuestLogIndexByID = function(id) return mock.quest and mock.quest.id == id and 3 or 0 end,
		GetQuestLogTitle = function(index)
			if index == 3 and mock.quest then return mock.quest.title, mock.quest.level end
		end,
		GetNumFactions = function() return #(mock.factions or {}) end,
		GetFactionInfo = function(i)
			local f = (mock.factions or {})[i]
			if f then return f.name, "", f.standing, 0, 0, 0, false, false, f.header, false, f.hasRep, false, false, f.id end
		end,
		IsInInstance = function() return mock.instanceType ~= nil, mock.instanceType or "none" end,
		GetInstanceInfo = function() return mock.instanceName, mock.instanceType end,
		IsInGuild = function() if mock.guildKnown == false then return nil end return mock.guild ~= nil end,
		GetGuildInfo = function() if mock.guild then return mock.guild.name, mock.guild.rank, 1 end end,
		C_QuestLog = { GetQuestInfo = function(id) return mock.questTitles and mock.questTitles[id] end },
		GetRealmName = function() return "Test Realm" end,
		GetNormalizedRealmName = function() return "TestRealm" end,
		time = function() mock.clock = mock.clock + 1; return mock.clock end,
		SlashCmdList = {},
		DEFAULT_CHAT_FRAME = {
			AddMessage = function(_, text) mock.chat[#mock.chat + 1] = text end,
		},
		C_AddOns = {
			GetAddOnMetadata = function(name, field)
				if name == "DawnwardChronicles" and field == "Version" then
					return opts.version or "0.9.0-dev"
				end
				return nil
			end,
			IsAddOnLoaded = function() return false end,
		},
	}
	for k, v in pairs(opts.savedVariables or {}) do
		env[k] = v
	end
	for k, v in pairs(opts.extra or {}) do
		env[k] = v
	end
	mock.env = env

	--- Plays for this many seconds: GetTime moves on and the minute tickers
	-- run as they would (at least once). Real time (time()) is not touched.
	function mock.Play(seconds)
		local step = 60
		local left = seconds
		while left > 0 do
			local d = math.min(step, left)
			mock.mono = mock.mono + d
			left = left - d
			for _, ticker in ipairs(mock.tickers) do ticker.fn() end
		end
	end

	--- Runs the timers queued so far (not ones they queue in turn).
	function mock.RunTimers()
		local due = mock.timers
		mock.timers = {}
		for _, timer in ipairs(due) do
			timer.fn()
		end
		return #due
	end

	function mock.Fire(event, ...)
		for frame in pairs(mock.eventFrames) do
			local handler = frame.__scripts.OnEvent
			if frame.__events[event] and handler then
				handler(frame, event, ...)
			end
		end
	end

	function mock.Slash(message)
		mock.chat = {}
		env.SlashCmdList.DAWNWARD(message)
		return table.concat(mock.chat, "\n")
	end

	return mock
end

return Mock
