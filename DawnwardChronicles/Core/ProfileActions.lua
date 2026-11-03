-- The player's actions on profile suggestions (v0.10.2,
-- Core/ProfileSuggestions.lua), shared by the Story Director, the Total RP 3
-- page and the Automatic Currently mode.
--
-- Every change goes through Actions.WithCharacter (read-only data refused,
-- a Total RP 3 sync requested afterwards), so an accepted suggestion
-- reaches Total RP 3 only through the existing guarded sync: backup, write
-- through Total RP 3's own setters or section, read-back, restore. Like
-- every Total RP 3 profile edit (TRP3Commands.SIMULATION_REFUSAL), these
-- are refused in simulation mode: the profile is the real character's.
--
-- The Automatic Currently mode (AfterChange) replaces Dawnward's Currently
-- text by itself only when all of these hold:
--   * the player confirmed Automatic for this character
--   * the suggestion was made in that mode within the last hour, and names
--     no private goal
--   * Dawnward's own Currently is empty, still the text it held when
--     Automatic was turned on, or Automatic's own last text (never a text
--     the player wrote since)
--   * not in simulation mode, Total RP 3 is connected and bound to this
--     character, Dawnward keeps Currently in sync, there is no conflict,
--     and Total RP 3 shows nothing or exactly what Dawnward last wrote
-- Otherwise the suggestion waits for the player, with the reason (held).
-- UndoAutomatic brings the previous text back.
--
-- ctx needs: store, characterKey, now(); trp3Deps() for the Automatic mode.
local _, ns = ...
local PS, Actions = ns.ProfileSuggestions, ns.Actions

local ProfileActions = {}
ns.ProfileActions = ProfileActions

ProfileActions.SIMULATION_REFUSAL = "Turn simulation mode off first: profile suggestions belong to your real "
	.. "character, as Total RP 3 shows it."

local function simulated(ctx)
	return ctx and ctx.store and ctx.store:IsSimulation() or false
end

--- Why Total RP 3 does not let the Automatic mode change Currently now, or
-- nil when it does (Dawnward keeps Currently in sync, bound to this
-- character's profile, with no conflict, and Total RP 3 shows nothing or
-- exactly what Dawnward last wrote). Reads only.
function ProfileActions.CurrentlyGate(ctx)
	if simulated(ctx) then
		return "simulation mode is on"
	end
	local deps = ctx and ctx.trp3Deps and ctx.trp3Deps() or nil
	if not deps or not ns.TRP3Sync then
		return "Total RP 3 is not connected"
	end
	if deps.ledgerReadOnly then
		return "Dawnward's Total RP 3 record is read-only"
	end
	local ok, view = pcall(ns.TRP3Sync.StatusView, deps)
	if not ok or type(view) ~= "table" then
		return "Total RP 3 could not be read"
	end
	if view.reason then
		return view.reason
	end
	local row = view.rows.currently
	if not row or row.policy ~= "dawnward" then
		return "Dawnward does not keep your Currently in sync with Total RP 3"
	end
	if row.conflict then
		return "Currently is paused by a conflict with Total RP 3"
	end
	if not (row.trp3 == nil or row.trp3 == "" or row.owned) then
		return "Total RP 3 shows a Currently text you wrote there"
	end
	return nil
end

--- After any change through Actions.WithCharacter (and a new zone): in the
-- Automatic mode, applies the waiting Currently suggestion when every
-- guard holds. Returns the applied suggestion, or nil.
function ProfileActions.AfterChange(ctx, char)
	if type(char) ~= "table" or not char.profileSuggestions or ns.RPStatus.CurrentlyMode(char) ~= "automatic" then
		return nil
	end
	local now = ctx.now()
	local s = PS.Waiting(char, now, "currently")[1]
	if not s or not s.automatic then
		return nil
	end
	local reason = PS.AutoBlocked(char, s, now) or ProfileActions.CurrentlyGate(ctx)
	if reason then
		s.held = reason
		return nil
	end
	s.held = nil
	return PS.ApplyAutomatic(char, s.id, now)
end

--- A logged location (Actions.ObserveLocation): a first visit to a zone may
-- offer a Currently text (Suggested and Automatic modes only). char is the
-- real character; created is the list ObserveLocation returns.
function ProfileActions.OnLocation(ctx, char, created)
	if type(char) ~= "table" or ns.RPStatus.CurrentlyMode(char) == "manual" then
		return nil
	end
	local made
	for _, c in ipairs(created or {}) do
		if c.record and c.record.category == "zone" then
			made = PS.Generate(char, ctx.now(), { kind = "zone", record = c.record })[1] or made
		end
	end
	if made and not simulated(ctx) then
		local applied = ProfileActions.AfterChange(ctx, char)
		if applied and ctx.trp3RequestSync then ctx.trp3RequestSync() end
	end
	return made
end

local function act(ctx, fn)
	if simulated(ctx) then
		return nil, ProfileActions.SIMULATION_REFUSAL
	end
	return Actions.WithCharacter(ctx, fn)
end

local function accepted(s)
	if s.kind == "currently" then
		return "Currently saved in Dawnward. Total RP 3 shows it after the next sync while Currently is kept in sync."
			.. " To undo, write or clear Currently in Settings > Total RP 3 > Status and OOC."
	end
	local n = s.result and s.result.n
	return "At First Glance entry " .. tostring(n) .. " saved in Dawnward. Total RP 3 shows it after the next sync "
		.. "while At First Glance sync is on. To undo, edit or remove entry " .. tostring(n) .. " (Settings > Total RP 3 "
		.. "> At First Glance)."
end

--- Accepts suggestion id as offered, or in the player's own words (values
-- = { title, text } for At First Glance, { text } for Currently).
function ProfileActions.Accept(ctx, id, values)
	return act(ctx, function(char)
		local s, err = PS.Accept(char, id, ctx.now(), values)
		if not s then return Actions.Fail(err) end
		return s, accepted(s)
	end)
end

function ProfileActions.Postpone(ctx, id)
	return act(ctx, function(char)
		local s, err = PS.Postpone(char, id, ctx.now())
		if not s then return Actions.Fail(err) end
		return s, "Kept for later: Dawnward shows this suggestion again tomorrow. Nothing was changed."
	end)
end

function ProfileActions.Dismiss(ctx, id)
	return act(ctx, function(char)
		local s, err = PS.Dismiss(char, id, ctx.now())
		if not s then return Actions.Fail(err) end
		return s, "Dismissed. Dawnward will not suggest this again unless your character develops much further. "
			.. "Nothing was changed."
	end)
end

ProfileActions.MODE_TEXT = {
	manual = "Currently: Manual. You write it yourself; Dawnward suggests nothing.",
	suggested = "Currently: Suggested. After a meaningful moment Dawnward offers a text; nothing changes until you "
		.. "accept it.",
	automatic = "Currently: Automatic. Dawnward updates your Currently after a meaningful moment while it keeps "
		.. "Currently in sync without a conflict. Undo the last update any time.",
}

--- Sets the Currently mode; "automatic" only with confirmed == true (the
-- player confirmed the dialog).
function ProfileActions.SetCurrentlyMode(ctx, mode, confirmed)
	return act(ctx, function(char)
		local ok, err = PS.SetCurrentlyMode(char, mode, ctx.now(), confirmed)
		if not ok then return Actions.Fail(err) end
		return true, ProfileActions.MODE_TEXT[mode]
	end)
end

--- Undoes the last automatic Currently change.
function ProfileActions.UndoAutomatic(ctx)
	return act(ctx, function(char)
		local previous, err = PS.UndoAutomatic(char, ctx.now())
		if not previous then return Actions.Fail(err) end
		return true, previous == "" and "Undone: Currently is empty again in Dawnward; Total RP 3 follows on the next sync."
			or "Undone: your previous Currently is back in Dawnward; Total RP 3 follows on the next sync."
	end)
end
