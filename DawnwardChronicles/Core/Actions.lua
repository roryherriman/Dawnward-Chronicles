-- Player actions shared by the journal window and slash commands.
--
-- Every write goes through here: it refuses read-only data, creates the
-- character on first write, and reuses the Character/Journal validation.
-- Each function returns ok (or the changed item) plus a short player-facing
-- message, and never raises for bad input.
--
-- ctx needs: store, characterKey, now()
local _, ns = ...
local Character, Journal, Milestones, Themes, Facts, Personality =
	ns.Character, ns.Journal, ns.Milestones, ns.Themes, ns.Facts, ns.Personality

local Actions = {}
ns.Actions = Actions

local function fail(err)
	return nil, "Not changed: " .. tostring(err)
end

-- Runs change(char) on the active character, creating it first if needed.
-- If the character was created for this change and the change fails, it is
-- removed again, so a rejected first edit leaves no empty record behind.
-- change returns result, message (result nil on failure).
local function withCharacter(ctx, change)
	local reason = ctx.store:ReadOnlyReason()
	if reason then
		return nil, "Saved data is read-only (" .. reason .. "). Nothing was changed."
	end
	local existed = ctx.store:GetCharacter(ctx.characterKey) ~= nil
	local char, err = ctx.store:EnsureCharacter(ctx.characterKey, ctx.now())
	if not char then
		return nil, "Cannot save: " .. err
	end
	local result, message = change(char)
	if not result and not existed then
		ctx.store:Root().characters[ctx.characterKey] = nil
	end
	return result, message
end

--- Read access (never creates anything).
function Actions.Character(ctx)
	return ctx.store:GetCharacter(ctx.characterKey)
end

function Actions.ThemeOf(char)
	return Themes.Get(char and char.theme)
end

--- Journal -------------------------------------------------------------------

local function prunedNote(pruned)
	if pruned and pruned > 0 then
		return " The journal was full, so the oldest automatic entry was removed."
			.. " Entries you write are never removed automatically."
	end
	return ""
end

function Actions.AddNote(ctx, title, text, visibility)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.AddNote(char, { title = title, text = text, visibility = visibility }, ctx.now())
		if not entry then return fail(result) end
		return entry, "Added journal entry #" .. entry.id .. "." .. prunedNote(result)
	end)
end

function Actions.UpdateNote(ctx, id, title, text, visibility)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.UpdateNote(char, id,
			{ title = title, text = text, visibility = visibility }, ctx.now())
		if not entry then return fail(result) end
		return entry, "Updated journal entry #" .. id .. "."
	end)
end

function Actions.SetEntryVisibility(ctx, id, level)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.SetVisibility(char, id, level, ctx.now())
		if not entry then return fail(result) end
		return entry, "Journal entry #" .. id .. " is now " .. level .. "."
	end)
end

function Actions.RemoveNote(ctx, id)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.RemoveNote(char, id, ctx.now())
		if not entry then return fail(result) end
		return entry, "Deleted journal entry #" .. id .. "."
	end)
end

--- Records a milestone observed in the real game into the real character.
-- Returns entry, message; or nil, reason ("duplicate" is silent for callers).
function Actions.RecordRealMilestone(ctx, typeName, data)
	local existed = ctx.store.real.characters[ctx.characterKey] ~= nil
	local char, err = ctx.store:EnsureRealCharacter(ctx.characterKey, ctx.now())
	if not char then
		return nil, err
	end
	local entry, result = Milestones.Record(char, typeName, data, ctx.now())
	if not entry then
		if not existed then
			ctx.store.real.characters[ctx.characterKey] = nil
		end
		return nil, result
	end
	return entry, "Journal: " .. entry.text .. prunedNote(result)
end

--- Records a simulated milestone into simulation data only.
function Actions.RecordSimulatedMilestone(ctx, typeName, data)
	if not ctx.store:IsSimulation() then
		return nil, "Simulated milestones need simulation mode: /dawnward sim on"
	end
	return withCharacter(ctx, function(char)
		data.source = "SIMULATION"
		local entry, result = Milestones.Record(char, typeName, data, ctx.now())
		if not entry then
			if result == "duplicate" then
				return nil, "Not recorded: that milestone is already in the simulated journal (duplicate prevented)."
			end
			return fail(result)
		end
		return entry, "Simulated journal: " .. entry.text .. prunedNote(result)
	end)
end

--- Profile -------------------------------------------------------------------

function Actions.SetField(ctx, key, value)
	return withCharacter(ctx, function(char)
		local ok, result = Character.SetField(char, key, value, ctx.now())
		if not ok then return fail(result) end
		return true, "Saved " .. key .. "."
	end)
end

function Actions.ClearField(ctx, key)
	return withCharacter(ctx, function(char)
		local ok, result = Character.ClearField(char, key, ctx.now())
		if not ok then return fail(result) end
		return true, "Cleared " .. key .. "."
	end)
end

function Actions.SetFieldVisibility(ctx, key, level)
	return withCharacter(ctx, function(char)
		local ok, result = Character.SetFieldVisibility(char, key, level, ctx.now())
		if not ok then return fail(result) end
		return true, key .. " is now " .. level .. "."
	end)
end

--- Facts (canon) --------------------------------------------------------------

function Actions.AddFact(ctx, category, statement, visibility)
	return withCharacter(ctx, function(char)
		local fact, err = Facts.Add(char, { category = category, statement = statement, visibility = visibility },
			nil, ctx.now())
		if not fact then return fail(err) end
		return fact, string.format("Added fact #%d (%s) [%s].", fact.id, Facts.DisplayCategory(fact.category).label,
			fact.visibility)
	end)
end

function Actions.SetFactVisibility(ctx, id, level)
	return withCharacter(ctx, function(char)
		local fact, err = Facts.SetVisibility(char, id, level, ctx.now())
		if not fact then return fail(err) end
		return fact, "Fact #" .. id .. " is now " .. level .. "."
	end)
end

function Actions.RemoveFact(ctx, id)
	return withCharacter(ctx, function(char)
		local fact, err = Facts.Remove(char, id, ctx.now())
		if not fact then return fail(err) end
		return fact, "Removed fact #" .. id .. "."
	end)
end

--- Personality ----------------------------------------------------------------

function Actions.SetPersonality(ctx, axisId, value)
	return withCharacter(ctx, function(char)
		local entry, err = Personality.Set(char, axisId, value, ctx.now())
		if not entry then return fail(err) end
		local axis = Personality.AXIS_BY_ID[axisId]
		return entry, string.format("%s: %d/20 (%s %d - %d %s) [%s].", axisId, value, axis.left, 20 - value, value,
			axis.right, entry.visibility)
	end)
end

function Actions.SetPersonalityVisibility(ctx, axisId, level)
	return withCharacter(ctx, function(char)
		local entry, err = Personality.SetVisibility(char, axisId, level, ctx.now())
		if not entry then return fail(err) end
		return entry, axisId .. " is now " .. level .. "."
	end)
end

function Actions.ClearPersonality(ctx, axisId)
	return withCharacter(ctx, function(char)
		local entry, err = Personality.Clear(char, axisId, ctx.now())
		if not entry then return fail(err) end
		return entry, "Cleared " .. axisId .. "."
	end)
end

--- Window preferences (account-wide, stored in real data only) ------------------

function Actions.WindowPosition(ctx)
	local ui = ctx.store.real.ui
	return ui and ui.position
end

function Actions.SaveWindowPosition(ctx, left, top)
	if ctx.store.realReadOnly then
		return nil, "saved data is read-only"
	end
	if type(left) ~= "number" or type(top) ~= "number" then
		return nil, "invalid position"
	end
	ctx.store.real.ui = ctx.store.real.ui or {}
	ctx.store.real.ui.position = { left = left, top = top }
	return true
end

--- Theme (cosmetic only) -----------------------------------------------------

function Actions.SetTheme(ctx, themeId)
	if not Themes.IsValid(themeId) then
		return nil, "Unknown theme '" .. tostring(themeId) .. "'."
	end
	return withCharacter(ctx, function(char)
		char.theme = themeId
		return true, "Theme set to " .. Themes.Get(themeId).name .. "."
	end)
end
