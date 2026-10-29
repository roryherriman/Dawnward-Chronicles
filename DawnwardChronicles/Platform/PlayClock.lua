-- Feeds the narrative clock (Core/NarrativeClock.lua) from the client.
--
--   GetTime()               seconds since the computer started; only the
--                           differences within this session are used
--   C_Timer.NewTicker(60)   reads the clock once a minute while playing, so a
--                           long stall (sleep, freeze) is capped, not counted
--   PLAYER_FLAGS_CHANGED    UnitIsAFK("player"): the clock pauses while AFK
--   PLAYER_LOGOUT           a last reading before SavedVariables are written
--                           (also fires on /reload)
--
-- Reading the clock only adds play time to characters that already have a
-- Dawnward record; it never creates one.
local _, ns = ...
local NarrativeClock = ns.NarrativeClock

local PlayClock = {}
ns.PlayClock = PlayClock

PlayClock.TICK = 60

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
	return nil
end

function PlayClock.Monotonic()
	return call(GetTime)
end

-- The characters this session plays: the real one, and its simulation copy.
local function characters(ctx)
	local out = {}
	local store = ctx.store
	for _, data in ipairs({ store.real, store.sim }) do
		local char = data and data.characters and data.characters[ctx.characterKey]
		if char then out[#out + 1] = char end
	end
	return out
end

--- Adds the play since the last reading to each character.
function PlayClock.Read(ctx)
	local mono = PlayClock.Monotonic()
	for _, char in ipairs(characters(ctx)) do
		NarrativeClock.Advance(char, ctx.narrative, mono)
	end
end

--- Pauses (AFK) or resumes the clock.
function PlayClock.SetAway(ctx, away)
	local mono = PlayClock.Monotonic()
	if away == ctx.narrative.paused then
		return
	end
	for _, char in ipairs(characters(ctx)) do
		if away then
			NarrativeClock.Advance(char, ctx.narrative, mono)
		else
			ctx.narrative.anchors[char] = mono
		end
	end
	ctx.narrative.paused = away and true or false
end

function PlayClock.Init(ctx)
	PlayClock.Read(ctx)
	PlayClock.SetAway(ctx, call(UnitIsAFK, "player") and true or false)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGOUT")
	frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
	frame:SetScript("OnEvent", function(_, event, unit)
		-- The clock must never break the game.
		pcall(function()
			if event == "PLAYER_LOGOUT" then
				PlayClock.Read(ctx)
			elseif unit == nil or unit == "player" then
				PlayClock.SetAway(ctx, call(UnitIsAFK, "player") and true or false)
			end
		end)
	end)
	if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
		PlayClock.ticker = C_Timer.NewTicker(PlayClock.TICK, function() pcall(PlayClock.Read, ctx) end)
	end
	PlayClock.frame = frame
	return frame
end
