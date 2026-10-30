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
	"Core/Records.lua",
	"Core/RecordTypes.lua",
	"Core/NarrativeClock.lua",
	"Core/Places.lua",
	"Core/Guide.lua",
	"Core/Atlas.lua",
	"Core/Onboarding.lua",
	"Core/StorySchema.lua",
	"Core/Schema.lua",
	"Core/Migrations.lua",
	"Core/Character.lua",
	"Core/Journal.lua",
	"Core/Milestones.lua",
	"Core/Facts.lua",
	"Core/Sources.lua",
	"Core/Interpretations.lua",
	"Core/Personality.lua",
	"Core/GameEvents.lua",
	"Core/ReactionLibrary.lua",
	"Core/Reactions.lua",
	"Core/Evolution.lua",
	"Core/Narrative.lua",
	"Core/Decisions.lua",
	"Core/Memories.lua",
	"Core/Arcs.lua",
	"Core/Goals.lua",
	"Core/Identity.lua",
	"Core/Director.lua",
	"Core/Continuity.lua",
	"Core/Observed.lua",
	"Core/People.lua",
	"Core/Timeline.lua",
	"Core/Projection.lua",
	"Core/Serializer.lua",
	"Core/Transfer.lua",
	"Core/Store.lua",
	"Core/Actions.lua",
	"Core/Commands.lua",
	"Core/StoryCommands.lua",
	"Core/NarrativeCommands.lua",
	"Core/SetupCommands.lua",
	"Core/StoryDiagnostics.lua",
}

-- TRP3 integration modules in TOC order (pure; they receive TRP3 explicitly).
Loader.TRP3 = {
	"Integrations/TRP3/VersionProfiles.lua",
	"Integrations/TRP3/Status.lua",
	"Integrations/TRP3/FieldPlan.lua",
	"Integrations/TRP3/Ledger.lua",
	"Integrations/TRP3/Presentation.lua",
	"Integrations/TRP3/AboutBlock.lua",
	"Integrations/TRP3/TraitPlan.lua",
	"Integrations/TRP3/Shape.lua",
	"Integrations/TRP3/Adapter.lua",
	"Integrations/TRP3/Sync.lua",
	"Integrations/TRP3/Commands.lua",
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

--- Core plus the TRP3 integration modules.
function Loader.WithTRP3()
	local files = {}
	for _, rel in ipairs(Loader.CORE) do files[#files + 1] = rel end
	for _, rel in ipairs(Loader.TRP3) do files[#files + 1] = rel end
	return (Loader.Load(files))
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
