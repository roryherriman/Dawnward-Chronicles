-- Loads saved data, upgrading it one schema version at a time.
--
-- Safety rules:
--  * The raw saved table is never modified. Work happens on a deep copy.
--  * Data from a newer schema, data with no migration path, and data a
--    migration fails on all put the database in read-only mode: the caller
--    must leave the saved variable untouched and refuse writes.
local _, ns = ...
local Util, Schema = ns.Util, ns.Schema

local Migrations = {}
ns.Migrations = Migrations

-- steps[n] upgrades a database from schema n to n + 1. Each step receives a
-- private deep copy and returns the upgraded table. Steps only add or reshape
-- data; Schema.NormalizeDatabase then validates the result.
Migrations.steps = {}

-- 1 -> 2 (v0.2): add an empty journal, journal keys and the neutral theme to
-- every character (including import backups), and window preferences.
-- Existing fields, family, history and visibility are not touched.
Migrations.steps[1] = function(db)
	for _, mapName in ipairs({ "characters", "importBackups" }) do
		local map = db[mapName]
		if type(map) == "table" then
			for _, char in pairs(map) do
				if type(char) == "table" then
					if type(char.journal) ~= "table" then
						char.journal = {}
					end
					if type(char.journalKeys) ~= "table" then
						char.journalKeys = {}
					end
					if char.theme == nil then
						char.theme = ns.Themes.DEFAULT
					end
				end
			end
		end
	end
	if type(db.ui) ~= "table" then
		db.ui = {}
	end
	return db
end

local function readOnly(reason, version)
	return Schema.NewDatabase(), { status = "readOnly", reason = reason, from = version, notes = {} }
end

--- Returns database, info. info.status is "new", "ok", "migrated" or "readOnly".
function Migrations.Load(raw, steps, targetVersion)
	steps = steps or Migrations.steps
	targetVersion = targetVersion or Schema.VERSION

	if raw == nil then
		return Schema.NewDatabase(), { status = "new", notes = {} }
	end
	if type(raw) ~= "table" then
		return readOnly("saved data is not a table")
	end

	local version = raw.schemaVersion
	if version == nil then
		if next(raw) == nil then
			return Schema.NewDatabase(), { status = "new", notes = {} }
		end
		return readOnly("saved data has no schema version")
	end
	if not Util.IsPositiveInteger(version) then
		return readOnly("saved schema version is invalid")
	end
	if version > targetVersion then
		return readOnly("saved data comes from a newer version of Dawnward Chronicles", version)
	end

	local work = Util.DeepCopy(raw)
	while work.schemaVersion < targetVersion do
		local from = work.schemaVersion
		local step = steps[from]
		if type(step) ~= "function" then
			return readOnly("no migration from schema " .. from, version)
		end
		local ok, result = pcall(step, work)
		if not ok or type(result) ~= "table" then
			return readOnly("migration from schema " .. from .. " failed: " .. tostring(result), version)
		end
		result.schemaVersion = from + 1
		work = result
	end

	local notes = {}
	local db = Schema.NormalizeDatabase(work, notes)
	db.schemaVersion = targetVersion
	return db, { status = (version < targetVersion) and "migrated" or "ok", from = version, notes = notes }
end
