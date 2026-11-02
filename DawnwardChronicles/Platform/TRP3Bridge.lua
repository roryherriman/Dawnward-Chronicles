-- Connects the TRP3 sync integration to the client: its saved variable, the
-- /dawnward trp3 commands, and debounced automatic runs.
--
-- Automatic runs only happen for characters that authorised at least one
-- mapping. They are requested:
--   * at login;
--   * after any /dawnward command (Bootstrap) and after any successful
--     change made in the window (Actions.withCharacter): profile fields,
--     facts, personality values, approvals of story entries and changes,
--     visibility, the Total RP 3 presentation style, policies;
--   * when Total RP 3 reports a profile switch or an edit of the player's
--     own active profile (hints only; each run re-reads everything; hints
--     about other players' profiles and those caused by Dawnward's own
--     write are ignored, so a write never triggers another run);
--   * when combat ends, if a run was waiting for it.
-- Requests are merged into one run a few seconds later, so a burst of
-- changes writes at most once. A run that has to wait (open editor, combat)
-- is retried every RETRY_DELAY seconds, at most MAX_RETRIES times per
-- request; a new request starts a fresh, equally bounded, series.
local _, ns = ...
local Ledger, Sync, Adapter, TRP3Commands = ns.TRP3Ledger, ns.TRP3Sync, ns.TRP3Adapter, ns.TRP3Commands

local Bridge = {}
ns.TRP3Bridge = Bridge

Bridge.DELAY = 5        -- seconds between a request and the run
Bridge.RETRY_DELAY = 30 -- seconds before retrying a run that had to wait
Bridge.MAX_RETRIES = 20

local pending, retries = false, 0
local generation = 0 -- a timer from an older schedule does nothing
local lastMessage = {}

local function schedule(delay)
	generation = generation + 1
	local mine = generation
	pending = true
	C_Timer.After(delay, function()
		if mine == generation then
			Bridge.Flush()
		end
	end)
end

--- At ADDON_LOADED. A ledger from a newer build stays untouched and blocks sync.
function Bridge.Load()
	local ledger, err = Ledger.Normalize(DawnwardChroniclesTRP3DB)
	if ledger then
		DawnwardChroniclesTRP3DB = ledger
		Bridge.ledger, Bridge.readOnly = ledger, nil
	else
		Bridge.ledger, Bridge.readOnly = Ledger.New(), err
	end
end

local function deps(ctx)
	return {
		env = _G,
		ledger = Bridge.ledger,
		ledgerReadOnly = Bridge.readOnly,
		store = ctx.store,
		characterKey = ctx.characterKey,
		now = ctx.now,
		inCombat = function() return InCombatLockdown() and true or false end,
	}
end

local function anyOptIn(ctx)
	local entry = Bridge.ledger and Bridge.ledger.optIn[ctx.characterKey]
	return TRP3Commands.AnyManaged(entry)
end

--- Runs every managed feature now and reports what changed. Messages for
-- states that persist (blocked, conflict, still waiting) are shown once,
-- not on every run.
function Bridge.Flush()
	pending = false
	local ctx = Bridge.ctx
	if not ctx or not anyOptIn(ctx) then
		Bridge.waiting = false
		return
	end
	Bridge.flushing = true
	local ok, results = pcall(Sync.Run, deps(ctx))
	Bridge.flushing = false
	if not ok then
		ctx.print("Total RP 3 sync stopped after an unexpected error: " .. tostring(results))
		return
	end
	local waiting = false
	for _, r in ipairs(results) do
		if r.state == "deferred" then
			waiting = true
		elseif r.state == "written" or r.state == "failed" then
			ctx.print(r.message)
			lastMessage[r.feature] = nil
		elseif r.state ~= "noop" and r.message ~= lastMessage[r.feature] then
			ctx.print("Total RP 3 sync: " .. r.message)
			lastMessage[r.feature] = r.message
		elseif r.state == "noop" then
			lastMessage[r.feature] = nil
		end
	end
	Bridge.waiting = waiting
	if waiting and retries < Bridge.MAX_RETRIES then
		retries = retries + 1
		schedule(Bridge.RETRY_DELAY)
	elseif waiting then
		local note = "Total RP 3 sync is still waiting (editor open or in combat). It will try again after your "
			.. "next change, when combat ends, or with /dawnward trp3 sync."
		if lastMessage.waiting ~= note then
			ctx.print(note)
			lastMessage.waiting = note
		end
	else
		retries = 0
		lastMessage.waiting = nil
	end
end

--- Asks for a run soon. Cheap when nothing is managed. A new request gets
-- a fresh retry budget.
function Bridge.Request()
	local ctx = Bridge.ctx
	if pending or not ctx or not anyOptIn(ctx) then
		return
	end
	retries = 0
	schedule(Bridge.DELAY)
end

-- Total RP 3's own events are hints. While Dawnward itself writes, TRP3
-- fires REGISTER_DATA_UPDATED for that write; it is not a new change. TRP3
-- also fires it for every other player's (and companion's) profile it
-- receives; only hints about the player's own active profile count
-- (Adapter.IsOwnHint), checked last so the common case stays cheap.
local function onHint(name, ...)
	local ctx = Bridge.ctx
	if name == "REGISTER_PROFILES_LOADED" then
		-- The player switched (or created) a Total RP 3 profile: the setup's
		-- Total RP 3 stage and the Total RP 3 page show the new one at once.
		pcall(Bridge.ProfileChanged)
	end
	if Bridge.flushing or pending or not ctx or not anyOptIn(ctx) then
		return
	end
	if Adapter.IsOwnHint(_G, name, ...) then
		Bridge.Request()
	end
end
Bridge.OnHint = onHint

--- Redraws what shows the active Total RP 3 profile (read only).
function Bridge.ProfileChanged()
	if ns.SetupWizard and ns.SetupWizard.IsShown() then
		ns.SetupWizard.Refresh()
	end
	if ns.MainWindow and ns.MainWindow.IsShown and ns.MainWindow.IsShown() then
		ns.MainWindow.Refresh()
	end
end

--- At PLAYER_LOGIN, once the core context exists.
function Bridge.Attach(ctx)
	Bridge.ctx = ctx
	ctx.trp3Deps = function() return deps(ctx) end
	ctx.trp3 = { Command = TRP3Commands.Command, StatusLines = TRP3Commands.StatusLines,
		ConnectAll = TRP3Commands.ConnectAll }
	ctx.trp3RequestSync = Bridge.Request
	ctx.formatTime = function(t) return date("%Y-%m-%d %H:%M", t) end
	Adapter.Listen(_G, onHint)
	-- Combat ending releases a run that was waiting for it (PLAYER_REGEN_ENABLED,
	-- Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua).
	-- Only acts when a run is waiting, so it costs nothing otherwise.
	if not Bridge.combatFrame then
		Bridge.combatFrame = CreateFrame("Frame")
		Bridge.combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		Bridge.combatFrame:SetScript("OnEvent", function()
			if Bridge.waiting then
				pending = false
				Bridge.Request()
			end
		end)
	end
	Bridge.Request()
end
