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

-- Test setup for older saved data (v0.10 retired the visibility commands):
-- sets an item's stored visibility through the core, in the grammar the
-- old commands had ("vis race public", "fact vis 1 public", "biography
-- secret", "stance private 2 secret", ...). Goes through
-- Actions.WithCharacter like a window edit. Returns the outcome message.
local function attachVis(mock, ns)
	function mock.Vis(line)
		local w = {}
		for word in line:gmatch("%S+") do w[#w + 1] = word end
		local modules = { memory = ns.Memories, arc = ns.Arcs, goal = ns.Goals, stance = ns.Identity,
			person = ns.People }
		local _, message = ns.Actions.WithCharacter(ns.ctx, function(char)
			local now, r, err = ns.ctx.now()
			local cmd = w[1]
			if cmd == "vis" then
				r, err = ns.Character.SetFieldVisibility(char, ns.Schema.FieldKey(w[2]:lower()), w[3], now)
			elseif cmd == "fact" then
				r, err = ns.Facts.SetVisibility(char, tonumber(w[3]), w[4], now)
			elseif cmd == "personality" then
				r, err = ns.Personality.SetVisibility(char, w[3], w[4], now)
			elseif cmd == "journal" then
				r, err = ns.Journal.SetVisibility(char, tonumber(w[3]), w[4], now)
			elseif cmd == "family" or cmd == "history" then
				r, err = ns.Character.SetItemVisibility(char, cmd, tonumber(w[3]), w[4], now)
			elseif cmd == "biography" then
				r, err = ns.Sources.SetVisibility(char, w[2], now)
			elseif cmd == "stance" and w[2] == "private" then
				r, err = ns.Identity.SetConvictionVisibility(char, tonumber(w[3]), w[4], now)
			elseif modules[cmd] then
				r, err = modules[cmd].SetVisibility(char, tonumber(w[3]), w[4], now)
			else
				error("mock.Vis: unknown line " .. line)
			end
			if not r then return ns.Actions.Fail(err) end
			return r, "Visibility set (test setup)."
		end)
		return message
	end
end

--- Loads every TOC file. Returns mock, env, ns.
function Boot.Load(opts)
	local files = Boot.ReadToc()
	local mock = Mock.new(opts)
	local env = Loader.NewEnv(mock.env)
	local ns = Loader.Load(files, env, {})
	attachVis(mock, ns)
	return mock, env, ns
end

--- Fires the client's startup events.
function Boot.Login(mock)
	mock.Fire("ADDON_LOADED", "SomeOtherAddon")
	mock.Fire("ADDON_LOADED", "DawnwardChronicles")
	mock.Fire("PLAYER_LOGIN")
end

--- Load + login in one step.
-- opts.wizard: let the first-time setup wizard open by itself (as in game).
-- Off by default, so tests that open the journal for a new character see
-- the journal; tests/spec/ui_setup_wizard_spec.lua turns it on.
function Boot.Start(opts)
	local mock, env, ns = Boot.Load(opts)
	Boot.Login(mock)
	if not (opts and opts.wizard) and ns.ctx then
		ns.SetupWizard.SkipAutoLaunchThisSession(ns.ctx.characterKey)
	end
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
