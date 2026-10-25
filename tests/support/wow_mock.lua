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
function Methods:CreateFontString(name) return self.__mock.newFrame("FontString", name, self) end
function Methods:CreateTexture(name) return self.__mock.newFrame("Texture", name, self) end

local FrameMT = {
	__index = function(_, key)
		return Methods[key] or noop
	end,
}

--- opts: { interface = number, project = number, savedVariables = table, extra = table }
function Mock.new(opts)
	opts = opts or {}
	local mock = { eventFrames = {}, framesByName = {}, chat = {}, clock = 1700000000 }

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
		InCombatLockdown = function() return false end,
		UnitName = function() return "Testchar" end,
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
