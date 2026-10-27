-- Boots the whole addon from its TOC against the WoW mock (L2 tests).
local Loader = require("support.loader")
local Mock = require("support.wow_mock")

local Boot = {}

Boot.TOC_PATH = "DawnwardChronicles/DawnwardChronicles.toc"

--- Returns files (in load order) and metadata from the TOC.
function Boot.ReadToc()
	local f = assert(io.open(Boot.TOC_PATH, "rb"))
	local text = f:read("*a")
	f:close()
	local files, meta = {}, {}
	for line in text:gmatch("[^\r\n]+") do
		local key, value = line:match("^## ([%w%-]+): (.+)$")
		if key then
			meta[key] = value
		elseif not line:match("^#") and line:match("%S") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files, meta
end

--- Loads every TOC file. Returns mock, env, ns.
function Boot.Load(opts)
	local files = Boot.ReadToc()
	local mock = Mock.new(opts)
	local env = Loader.NewEnv(mock.env)
	local ns = Loader.Load(files, env, {})
	return mock, env, ns
end

--- Fires the client's startup events.
function Boot.Login(mock)
	mock.Fire("ADDON_LOADED", "SomeOtherAddon")
	mock.Fire("ADDON_LOADED", "DawnwardChronicles")
	mock.Fire("PLAYER_LOGIN")
end

--- Load + login in one step.
function Boot.Start(opts)
	local mock, env, ns = Boot.Load(opts)
	Boot.Login(mock)
	-- Confirmations use Dawnward's own dialog (UI/Widgets.lua): accept it
	-- like a click on its accept button, and record what it asked.
	function mock.AcceptPopup()
		local d = ns.Widgets.dialog
		assert(d and d:IsShown(), "no confirmation dialog is open")
		local asked = { text = d.text:GetText() }
		d.accept:GetScript("OnClick")(d.accept)
		return asked
	end
	return mock, env, ns
end

return Boot
