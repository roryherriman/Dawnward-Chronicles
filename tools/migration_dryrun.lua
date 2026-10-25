-- Read-only migration dry run on a COPY of a real SavedVariables file.
-- Usage (from the repository root):
--   lua5.1 tools/migration_dryrun.lua path/to/copy/of/DawnwardChronicles.lua
--
-- Prints only structure and counts, never content. The file is loaded in an
-- empty environment (a SavedVariables file is plain assignments), and
-- nothing is written anywhere.
package.path = "./?.lua;./tests/?.lua;" .. package.path
local Loader = require("support.loader")
local deepEqual = require("harness").deepEqual

local path = arg and arg[1]
if not path then
	print("usage: lua5.1 tools/migration_dryrun.lua <copy of DawnwardChronicles.lua>")
	os.exit(2)
end
local chunk, err = loadfile(path)
if not chunk then
	print("could not read: " .. tostring(err))
	os.exit(1)
end
local saved = {}
setfenv(chunk, saved)
local ok, runErr = pcall(chunk)
if not ok then
	print("could not load: " .. tostring(runErr))
	os.exit(1)
end

local ns = Loader.Core()
local function count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
	return n
end

for _, name in ipairs({ "DawnwardChroniclesDB", "DawnwardChroniclesSimDB" }) do
	local raw = saved[name]
	print("\n" .. name .. ": schema " .. tostring(type(raw) == "table" and raw.schemaVersion or raw))
	local before = ns.Util.DeepCopy(raw)
	local db, info = ns.Migrations.Load(raw)
	print("  status: " .. info.status .. (info.reason and (" (" .. info.reason .. ")") or ""))
	print("  repairs reported: " .. #(info.notes or {}))
	for _, note in ipairs(info.notes or {}) do print("    - " .. note) end
	if info.status ~= "readOnly" then
		local i = 0
		for _, mapName in ipairs({ "characters", "importBackups" }) do
			for key, char in pairs(db[mapName]) do
				i = i + 1
				local old = type(raw) == "table" and type(raw[mapName]) == "table" and raw[mapName][key] or {}
				local same = true
				for _, part in ipairs({ "fields", "family", "history", "journal", "journalKeys", "theme", "nextId",
					"createdAt", "updatedAt" }) do
					if old[part] ~= nil and not deepEqual(old[part], char[part]) then
						same = false
						print(string.format("  %s #%d: %s CHANGED", mapName, i, part))
					end
				end
				print(string.format("  %s #%d: %d fields, %d family, %d history, %d journal, %d keys; "
					.. "facts %d, sources %d, suggestions %d; v2 data preserved: %s",
					mapName, i, count(char.fields), #char.family, #char.history, #char.journal, count(char.journalKeys),
					#char.facts, #char.sources.versions, #char.interpretations, same and "yes" or "NO"))
			end
		end
		local again, info2 = ns.Migrations.Load(ns.Util.DeepCopy(db))
		print("  idempotent: " .. ((info2.status == "ok" and deepEqual(again, db)) and "yes" or "NO"))
	end
	print("  input left unmodified: " .. (deepEqual(before, raw) and "yes" or "NO"))
end
