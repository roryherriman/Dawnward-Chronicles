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
function Methods:GetScript(script) return self.__scripts[script] end
function Methods:RegisterEvent(event)
	self.__events[event] = true
	self.__mock.eventFrames[self] = true
end
function Methods:UnregisterEvent(event) self.__events[event] = nil end
function Methods:Show() self.__shown = true end
function Methods:Hide() self.__shown = false end
function Methods:IsShown() return self.__shown end
function Methods:SetText(text) self.__text = text end
function Methods:GetText() return self.__text end
function Methods:Enable() self.__enabled = true end
function Methods:Disable() self.__enabled = false end
function Methods:IsEnabled() return self.__enabled end
function Methods:GetName() return self.__name end
function Methods:CreateFontString(name, layer)
	local fs = self.__mock.newFrame("FontString", name, self)
	fs.__layer = layer
	return fs
end
function Methods:CreateTexture(name, layer, _, sublevel)
	local tex = self.__mock.newFrame("Texture", name, self)
	tex.__layer, tex.__sublevel = layer, sublevel
	self.__textures = self.__textures or {}
	self.__textures[#self.__textures + 1] = tex
	return tex
end

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
function Methods:SetWordWrap(on) self.__wordWrap = on end
function Methods:SetShown(on) self.__shown = on and true or false end
function Methods:SetEnabled(on) self.__enabled = on and true or false end
function Methods:GetLeft() return self.__left or 100 end
function Methods:GetTop() return self.__top or 600 end
function Methods:SetTextColor(r, g, b) self.__textColor = { r, g, b } end
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
	local mock = { eventFrames = {}, framesByName = {}, chat = {}, clock = 1700000000, popups = {}, timers = {},
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
		return f
	end

	local env = {
		WOW_PROJECT_ID = opts.project or 2,
		WOW_PROJECT_CLASSIC = 2,
		GetBuildInfo = function()
			return "1.15.x", "00000", "mock", opts.interface or 11509
		end,
		CreateFrame = function(kind, name, parent) return mock.newFrame(kind, name, parent) end,
		UIParent = mock.newFrame("Frame", "UIParent"),
		UISpecialFrames = {},
		tinsert = table.insert,
		BackdropTemplateMixin = {},
		ChatFontNormal = {},
		GameFontNormal = {},
		GameFontHighlightSmall = {},
		InCombatLockdown = function() return mock.inCombat == true end,
		C_Timer = {
			After = function(seconds, fn) mock.timers[#mock.timers + 1] = { seconds = seconds, fn = fn } end,
		},
		GameFontNormalLarge = {},
		GameFontHighlight = {},
		GameTooltip = mock.newFrame("GameTooltip", "GameTooltip"),
		StaticPopupDialogs = {},
		StaticPopup_Show = function(name, textArg, _, data)
			mock.popups[#mock.popups + 1] = { name = name, text = textArg, data = data }
		end,
		date = function(fmt, t) return "date(" .. tostring(fmt) .. "," .. tostring(t) .. ")" end,
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
					return "0.1.0"
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
