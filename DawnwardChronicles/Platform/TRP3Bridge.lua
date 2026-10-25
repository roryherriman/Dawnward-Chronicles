-- Connects the TRP3 sync integration to the client: its saved variable, the
-- /dawnward trp3 commands, and debounced automatic runs.
--
-- Automatic runs only happen for characters that opted in. They are
-- requested after login, after any /dawnward command, and when Total RP 3
-- reports a profile switch or edit (hints only; each run re-reads
-- everything). Requests are merged into one run a few seconds later, so a
-- burst of changes writes at most once. A run that has to wait (open
-- editor, combat) is retried a limited number of times.
local _, ns = ...
local Ledger, Sync, Adapter, TRP3Commands = ns.TRP3Ledger, ns.TRP3Sync, ns.TRP3Adapter, ns.TRP3Commands

local Bridge = {}
ns.TRP3Bridge = Bridge

Bridge.DELAY = 5        -- seconds between a request and the run
Bridge.RETRY_DELAY = 30 -- seconds before retrying a run that had to wait
Bridge.MAX_RETRIES = 20

local pending, retries = false, 0
local lastMessage = {}

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
	return entry ~= nil and (entry.about or entry.traits) == true
end

--- Runs every opted-in feature now and reports what changed. Messages for
-- states that persist (blocked, conflict) are shown once, not on every run.
function Bridge.Flush()
	pending = false
	local ctx = Bridge.ctx
	if not ctx or not anyOptIn(ctx) then
		return
	end
	local ok, results = pcall(Sync.Run, deps(ctx))
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
		end
	end
	if waiting and retries < Bridge.MAX_RETRIES then
		retries = retries + 1
		pending = true
		C_Timer.After(Bridge.RETRY_DELAY, Bridge.Flush)
	elseif not waiting then
		retries = 0
	end
end

--- Asks for a run soon. Cheap when nothing is opted in.
function Bridge.Request()
	local ctx = Bridge.ctx
	if pending or not ctx or not anyOptIn(ctx) then
		return
	end
	pending = true
	C_Timer.After(Bridge.DELAY, Bridge.Flush)
end

--- At PLAYER_LOGIN, once the core context exists.
function Bridge.Attach(ctx)
	Bridge.ctx = ctx
	ctx.trp3Deps = function() return deps(ctx) end
	ctx.trp3 = { Command = TRP3Commands.Command, StatusLines = TRP3Commands.StatusLines }
	ctx.trp3RequestSync = Bridge.Request
	ctx.formatTime = function(t) return date("%Y-%m-%d %H:%M", t) end
	Adapter.Listen(_G, function() Bridge.Request() end)
	Bridge.Request()
end
