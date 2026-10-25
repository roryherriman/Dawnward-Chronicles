-- Player actions shared by the journal window and slash commands.
--
-- Every write goes through here: it refuses read-only data, creates the
-- character on first write, and reuses the Character/Journal validation.
-- Each function returns ok (or the changed item) plus a short player-facing
-- message, and never raises for bad input.
--
-- ctx needs: store, characterKey, now()
local _, ns = ...
local Character, Journal, Milestones, Themes =
	ns.Character, ns.Journal, ns.Milestones, ns.Themes

local Actions = {}
ns.Actions = Actions

local function writableCharacter(ctx)
	local reason = ctx.store:ReadOnlyReason()
	if reason then
		return nil, "Saved data is read-only (" .. reason .. "). Nothing was changed."
	end
	local char, err = ctx.store:EnsureCharacter(ctx.characterKey, ctx.now())
	if not char then
		return nil, "Cannot save: " .. err
	end
	return char
end

local function fail(err)
	return nil, "Not changed: " .. tostring(err)
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
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	local entry, result = Journal.AddNote(char, { title = title, text = text, visibility = visibility }, ctx.now())
	if not entry then return fail(result) end
	return entry, "Added journal entry #" .. entry.id .. "." .. prunedNote(result)
end

function Actions.UpdateNote(ctx, id, title, text, visibility)
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	local entry, result = Journal.UpdateNote(char, id,
		{ title = title, text = text, visibility = visibility }, ctx.now())
	if not entry then return fail(result) end
	return entry, "Updated journal entry #" .. id .. "."
end

function Actions.SetEntryVisibility(ctx, id, level)
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	local entry, result = Journal.SetVisibility(char, id, level, ctx.now())
	if not entry then return fail(result) end
	return entry, "Journal entry #" .. id .. " is now " .. level .. "."
end

function Actions.RemoveNote(ctx, id)
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	local entry, result = Journal.RemoveNote(char, id, ctx.now())
	if not entry then return fail(result) end
	return entry, "Deleted journal entry #" .. id .. "."
end

--- Records a milestone observed in the real game into the real character.
-- Returns entry, message; or nil, reason ("duplicate" is silent for callers).
function Actions.RecordRealMilestone(ctx, typeName, data)
	local char, err = ctx.store:EnsureRealCharacter(ctx.characterKey, ctx.now())
	if not char then
		return nil, err
	end
	local entry, result = Milestones.Record(char, typeName, data, ctx.now())
	if not entry then
		return nil, result
	end
	return entry, "Journal: " .. entry.text .. prunedNote(result)
end

--- Records a simulated milestone into simulation data only.
function Actions.RecordSimulatedMilestone(ctx, typeName, data)
	if not ctx.store:IsSimulation() then
		return nil, "Simulated milestones need simulation mode: /dawnward sim on"
	end
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	data.source = "SIMULATION"
	local entry, result = Milestones.Record(char, typeName, data, ctx.now())
	if not entry then
		if result == "duplicate" then
			return nil, "Not recorded: that milestone is already in the simulated journal (duplicate prevented)."
		end
		return fail(result)
	end
	return entry, "Simulated journal: " .. entry.text .. prunedNote(result)
end

--- Profile -------------------------------------------------------------------

function Actions.SetField(ctx, key, value)
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	local ok, result = Character.SetField(char, key, value, ctx.now())
	if not ok then return fail(result) end
	return true, "Saved " .. key .. "."
end

function Actions.ClearField(ctx, key)
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	local ok, result = Character.ClearField(char, key, ctx.now())
	if not ok then return fail(result) end
	return true, "Cleared " .. key .. "."
end

function Actions.SetFieldVisibility(ctx, key, level)
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	local ok, result = Character.SetFieldVisibility(char, key, level, ctx.now())
	if not ok then return fail(result) end
	return true, key .. " is now " .. level .. "."
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
	local char, err = writableCharacter(ctx)
	if not char then return nil, err end
	char.theme = themeId
	return true, "Theme set to " .. Themes.Get(themeId).name .. "."
end
