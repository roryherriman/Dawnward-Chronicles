-- Access to the real and simulation databases.
--
-- Simulation mode switches every read and write to a separate database
-- (a separate SavedVariable), so test data can never mix with real data.
-- It is off at every login and must be switched on explicitly.
local _, ns = ...
local Util, Schema = ns.Util, ns.Schema

local Store = {}
Store.__index = Store
ns.Store = Store

--- opts: { realReadOnly = reason|nil, simReadOnly = reason|nil }
function Store.new(realDB, simDB, opts)
	opts = opts or {}
	return setmetatable({
		real = realDB,
		sim = simDB,
		realReadOnly = opts.realReadOnly,
		simReadOnly = opts.simReadOnly,
		simulation = false,
	}, Store)
end

function Store:IsSimulation()
	return self.simulation
end

function Store:SetSimulation(on)
	self.simulation = on and true or false
end

function Store:Root()
	return self.simulation and self.sim or self.real
end

--- Returns the reason the active database is read-only, or nil.
function Store:ReadOnlyReason()
	if self.simulation then
		return self.simReadOnly
	end
	return self.realReadOnly
end

function Store:GetCharacter(key)
	return self:Root().characters[key]
end

-- New characters start on the whole-profile model. Tests that model data
-- saved by an earlier version turn this off to create characters as 0.9 did.
Store.ADOPT_NEW_CHARACTERS = true

local function ensureIn(root, readOnlyReason, key, now)
	local char = root.characters[key]
	if char then
		return char
	end
	if readOnlyReason then
		return nil, "saved data is read-only"
	end
	if Util.CountKeys(root.characters) >= Schema.LIMITS.characters then
		return nil, "the character limit (" .. Schema.LIMITS.characters .. ") has been reached"
	end
	char = Schema.NewCharacter(now)
	-- A character first seen by this version has nothing an earlier version
	-- kept back: its whole profile publishes (Core/Publication.lua), however
	-- it is created (setup, a command, an automatic event).
	if Store.ADOPT_NEW_CHARACTERS then
		ns.Publication.Adopt(char, now)
	end
	root.characters[key] = char
	return char
end

--- Returns the active character, creating it if needed. Fails when read-only or full.
function Store:EnsureCharacter(key, now)
	return ensureIn(self:Root(), self:ReadOnlyReason(), key, now)
end

--- Real gameplay events always belong to the real character, even while
-- simulation mode is on; simulation is for testing, not for hiding events.
function Store:EnsureRealCharacter(key, now)
	return ensureIn(self.real, self.realReadOnly, key, now)
end

--- Replaces a character, keeping the previous one as the single undo slot.
function Store:ReplaceCharacter(key, newChar)
	local root = self:Root()
	root.importBackups[key] = root.characters[key]
	root.characters[key] = newChar
end

--- Swaps the character with its undo slot. Returns false if there is none.
function Store:UndoReplace(key)
	local root = self:Root()
	local previous = root.importBackups[key]
	if not previous then
		return false
	end
	root.importBackups[key] = root.characters[key]
	root.characters[key] = previous
	return true
end

-- The saved variable keeps pointing at the same table, so contents are
-- replaced in place rather than assigning a new table.
local function replaceContents(target, source)
	for k in pairs(target) do
		target[k] = nil
	end
	for k, v in pairs(source) do
		target[k] = v
	end
end

--- Wipes all simulation data. Only allowed while simulation data is writable.
function Store:ResetSimulation()
	if self.simReadOnly then
		return nil, "simulation data is read-only"
	end
	replaceContents(self.sim, Schema.NewDatabase())
	return true
end

--- Copies the real character into simulation data (overwriting it there).
function Store:CopyRealToSimulation(key)
	if self.simReadOnly then
		return nil, "simulation data is read-only"
	end
	local source = self.real.characters[key]
	if not source then
		return nil, "there is no real profile for this character yet"
	end
	self.sim.characters[key] = Util.DeepCopy(source)
	return true
end
