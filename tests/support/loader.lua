-- Loads addon files the way the WoW client does: each file receives
-- (addonName, namespace) as varargs and shares one global environment.
--
-- The environment holds only the Lua globals WoW provides. os, io, require,
-- dofile and loadfile are deliberately absent, so addon code that relies on
-- them fails here instead of in the client.

local Loader = {}

Loader.ADDON_NAME = "DawnwardChronicles"
Loader.ROOT = "DawnwardChronicles/"

-- Core modules in TOC order (kept in sync by tests/spec/addon_load_spec.lua).
Loader.CORE = {
	"Core/Util.lua",
	"Core/Privacy.lua",
	"Core/Themes.lua",
	"Core/Schema.lua",
	"Core/Migrations.lua",
	"Core/Character.lua",
	"Core/Journal.lua",
	"Core/Milestones.lua",
	"Core/Projection.lua",
	"Core/Serializer.lua",
	"Core/Transfer.lua",
	"Core/Store.lua",
	"Core/Actions.lua",
	"Core/Commands.lua",
}

local SAFE_GLOBALS = {
	"assert", "error", "ipairs", "next", "pairs", "pcall", "xpcall", "select",
	"tonumber", "tostring", "type", "unpack", "setmetatable", "getmetatable",
	"rawequal", "rawget", "rawset", "loadstring", "string", "table", "math",
}

function Loader.NewEnv(extra)
	local env = {}
	for _, name in ipairs(SAFE_GLOBALS) do
		env[name] = _G[name]
	end
	if extra then
		for k, v in pairs(extra) do
			env[k] = v
		end
	end
	env._G = env
	return env
end

--- Loads files (relative to the addon folder) into env with namespace ns.
function Loader.Load(files, env, ns)
	env = env or Loader.NewEnv()
	ns = ns or {}
	for _, rel in ipairs(files) do
		local chunk, err = loadfile(Loader.ROOT .. rel)
		if not chunk then
			error("could not load " .. rel .. ": " .. tostring(err), 2)
		end
		setfenv(chunk, env)
		chunk(Loader.ADDON_NAME, ns)
	end
	return ns, env
end

--- Fresh namespace with every core module loaded and a deterministic clock.
function Loader.Core(count)
	local files = {}
	for i = 1, (count or #Loader.CORE) do
		files[i] = Loader.CORE[i]
	end
	local ns = Loader.Load(files)
	return ns
end

--- Loads the first core modules up to and including the named file.
function Loader.CoreUpTo(fileName)
	for i, rel in ipairs(Loader.CORE) do
		if rel == "Core/" .. fileName .. ".lua" then
			return Loader.Core(i)
		end
	end
	error("unknown core module " .. fileName, 2)
end

return Loader
