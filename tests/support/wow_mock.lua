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
	-- A Forever mock knows only the documented events; the modern client
	-- raises an error for an unknown one, so this does too.
	local events = self.__mock.knownEvents
	if events and not events[event] then
		error("Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
	end
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
function Methods:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a or 1 } end
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

-- Region objects (textures, mask textures, lines, font strings) are strict:
-- only methods the Classic Era client documents exist on them (generated by
-- tools/gen_client_api.py), so a call the client would reject as "attempt to
-- call a nil value" fails here too (v0.10.1: SetColor on a Texture).
local CLIENT_API = require("support.client_api")
-- WoW Forever 1.60.1 (70755, game type camelot), from the forever branch
-- (tools/gen_client_api.py --forever). Used by frames of a Forever mock.
local FOREVER_API = require("support.client_api_forever")

local FrameMT = {
	__index = function(self, key)
		local api = rawget(self, "__mock").clientApi or CLIENT_API
		local strict = api[rawget(self, "__kind")]
		if strict and type(key) == "string" and key:match("^%u") and not strict[key] then
			return nil
		end
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

-- WoW Forever mode (opts.client = "forever"): the mock exposes only what the
-- Forever 1.60.1 (70755) UI source shows. Evidence: Gethe/wow-ui-source
-- branch forever (docs/COMPATIBILITY.md, "WoW Forever API compatibility").
--
-- Global functions must be documented (client_api_forever._globals), or be
-- one of these engine globals that are not in the generated documentation
-- but that Blizzard code loaded for the camelot game type calls, or Lua and
-- FrameXML values. Anything else in the environment is an error, so the
-- Forever mock cannot drift into exposing a Classic-only API.
Mock.FOREVER_ENGINE_GLOBALS = {
	CreateFrame = "called by camelot-loaded FrameXML throughout",
	CreateFont = "Blizzard_SharedXML/FontableFrameMixin.lua:120",
	InCombatLockdown = "Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua:375",
	GetQuestID = "Blizzard_UIPanels_Game/Mainline/QuestInfo.lua:40",
	GetTitleText = "Blizzard_UIPanels_Game/Mainline/QuestFrame.lua:212",
	GetGuildInfo = "Blizzard_FrameXML/Mainline/AlertFrameSystems.lua:355",
	StaticPopup_Show = "Blizzard_StaticPopup (FrameXML Lua)",
	date = "Lua global (Blizzard_SharedXML/TimeUtil.lua:47)",
	time = "Lua global (Blizzard_FriendsFrame/Mainline/FriendsListUtil.lua:277)",
	tinsert = "Lua global alias",
}
-- Classic Era globals that the forever branch neither documents nor calls
-- from camelot-loaded code: removed from a Forever mock. GetQuestLogIndexByID
-- is only a fallback in Mainline/TutorialFrame.lua:25 behind
-- C_QuestLog.GetLogIndexForQuestID, so it is treated as absent (unknown).
Mock.FOREVER_REMOVED = { "GetQuestLogIndexByID", "GetQuestLogTitle", "GetNumFactions", "GetFactionInfo",
	"GetAddOnMetadata", "IsAddOnLoaded" }

-- Secret values (12.x engine, FrameScriptDocumentation.lua issecretvalue):
-- mock.Secret(v) wraps v so that comparing it as text, concatenating or
-- printing it fails, as addon code touching a secret would in game.
local SecretMT = {
	__concat = function() error("attempt to concatenate a secret value", 2) end,
	__tostring = function() error("attempt to convert a secret value to a string", 2) end,
	__index = function() error("attempt to index a secret value", 2) end,
	__lt = function() error("attempt to compare a secret value", 2) end,
	__le = function() error("attempt to compare a secret value", 2) end,
}

function Mock.MakeForever(mock, env, opts)
	mock.client = "forever"
	mock.clientApi = FOREVER_API
	mock.knownEvents = FOREVER_API._events
	mock.secrets = setmetatable({}, { __mode = "k" })
	function mock.Secret(v)
		local s = setmetatable({}, SecretMT)
		mock.secrets[s] = v == nil and true or v
		return s
	end
	env.WOW_PROJECT_MAINLINE = 1
	env.WOW_PROJECT_CLASSIC = 2
	env.WOW_PROJECT_CAMELOT = 18
	env.WOW_PROJECT_ID = opts.project or 18
	env.GetBuildInfo = function()
		return "1.60.1", "70755", "Nov 3 2026", opts.interface or 16001, "1.60.1", "Release"
	end
	env.issecretvalue = function(v) return mock.secrets[v] ~= nil end
	for _, name in ipairs(Mock.FOREVER_REMOVED) do
		env[name] = nil
	end
	-- Retail-style replacements (QuestLogDocumentation.lua, ReputationInfoDocumentation.lua).
	env.C_QuestLog = {
		GetLogIndexForQuestID = function(id) return mock.quest and mock.quest.id == id and 3 or nil end,
		GetInfo = function(index)
			if index == 3 and mock.quest then
				return { title = mock.quest.title, questLogIndex = 3, questID = mock.quest.id,
					level = mock.quest.level, difficultyLevel = mock.quest.level, isHeader = false }
			end
		end,
		GetTitleForQuestID = function(id) return mock.questTitles and mock.questTitles[id] end,
	}
	env.C_Reputation = {
		GetNumFactions = function() return #(mock.factions or {}) end,
		GetFactionDataByIndex = function(i)
			local f = (mock.factions or {})[i]
			if f then
				return { factionID = f.id, name = f.name, description = "", reaction = f.standing,
					isHeader = f.header and true or false, isHeaderWithRep = f.hasRep and true or false,
					isCollapsed = false, isChild = false, isWatched = false, isAccountWide = false }
			end
		end,
	}
	Mock.CheckForever(env)
end

--- Errors when a Forever environment exposes a function or namespace
-- function the Forever source does not show.
function Mock.CheckForever(env)
	local docs = FOREVER_API._globals
	for name, value in pairs(env) do
		if type(value) == "function" and not docs[name] and not Mock.FOREVER_ENGINE_GLOBALS[name] then
			error("Forever mock exposes " .. name .. ", which the Forever 1.60.1 source does not show", 2)
		end
		local space = FOREVER_API._namespaces[name]
		if type(value) == "table" and name:match("^C_") then
			assert(space, "Forever mock exposes namespace " .. name .. " without generated evidence")
			for fn, impl in pairs(value) do
				if type(impl) == "function" and not space[fn] then
					error("Forever mock exposes " .. name .. "." .. fn .. ", which the Forever source does not document", 2)
				end
			end
		end
	end
end

--- opts: { interface = number, project = number, savedVariables = table, extra = table,
--          client = "forever" (WoW Forever 1.60.1 mode), target = "classic"|"forever" (TOC X-Dawnward-Target) }
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
				if name == "DawnwardChronicles" and opts.metadata and opts.metadata[field] ~= nil then
					return opts.metadata[field]
				end
				if name == "DawnwardChronicles" and field == "Version" then
					return opts.version or "0.10.3-dev"
				end
				-- The package target a packaged TOC may declare (tools/package.py).
				if name == "DawnwardChronicles" and field == "X-Dawnward-Target" then
					return opts.target
				end
				return nil
			end,
			IsAddOnLoaded = function() return false end,
		},
		-- C_Map (MapDocumentation.lua, both clients): nothing known unless a
		-- test sets mock.mapId, mock.maps[id] or mock.areas[id].
		C_Map = {
			GetBestMapForUnit = function() return mock.mapId end,
			GetMapInfo = function(id) return mock.maps and mock.maps[id] end,
			GetAreaInfo = function(id) return mock.areas and mock.areas[id] end,
		},
	}
	if opts.client == "forever" then
		Mock.MakeForever(mock, env, opts)
	end
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
