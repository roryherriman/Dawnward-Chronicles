-- Decides when a waiting story reaction may be announced, and announces it
-- quietly: one chat line, and the small reaction card if the player wants it.
--
-- Never during combat, while dead or a ghost, during a cinematic or a
-- loading screen. Checks run only on events that mark a calmer moment
-- (leaving combat, reviving, resting, arriving in a zone) and shortly after
-- a reaction is queued; nothing polls. Pacing (how often) is the core's job
-- (Reactions.NextNotice); this module only decides whether *now* is safe.
local _, ns = ...
local Reactions = ns.Reactions

local SafeTime = {}
ns.SafeTime = SafeTime

SafeTime.DELAY = 4            -- seconds after a trigger before checking
SafeTime.LOGIN_DELAY = 20     -- after login, let the world settle first

local busy = { cinematic = false, loading = false }
local scheduled = false

function SafeTime.Reasons()
	local reasons = {}
	if InCombatLockdown() then reasons[#reasons + 1] = "combat" end
	if UnitIsDeadOrGhost("player") then reasons[#reasons + 1] = "dead" end
	if busy.cinematic then reasons[#reasons + 1] = "cinematic" end
	if busy.loading then reasons[#reasons + 1] = "loading" end
	return reasons
end

function SafeTime.IsSafe()
	return #SafeTime.Reasons() == 0
end

-- Reactions come from real gameplay, so they live on the real character.
local function realCharacter(ctx)
	return ctx.store.real.characters[ctx.characterKey]
end

--- Announces the next due reaction if it is safe. Returns the reaction or nil.
function SafeTime.Check(ctx)
	scheduled = false
	if not SafeTime.IsSafe() or ctx.store.realReadOnly then
		return nil
	end
	local char = realCharacter(ctx)
	if not char then
		return nil
	end
	local now = ctx.now()
	local reaction = Reactions.NextNotice(char, now)
	if not reaction then
		return nil
	end
	local view = Reactions.Present(char, reaction)
	if not view then
		return nil
	end
	Reactions.MarkNotified(char, reaction.id, now)
	ctx.print("A moment for your story: " .. view.question .. "  (/dawnward story " .. reaction.id
		.. ", or the Story section of the journal)")
	-- The card never appears in simulation mode, where the Story section
	-- shows simulated data instead of this real reaction.
	if char.story.prefs.card and SafeTime.ShowCard and not ctx.store:IsSimulation() then
		SafeTime.ShowCard(reaction.id)
	end
	return reaction
end

function SafeTime.Schedule(ctx, delay)
	local char = realCharacter(ctx)
	if scheduled or not char or #char.story.reactions == 0 then
		return
	end
	scheduled = true
	C_Timer.After(delay or SafeTime.DELAY, function() SafeTime.Check(ctx) end)
end

SafeTime.TRIGGERS = {
	PLAYER_REGEN_ENABLED = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true, PLAYER_UPDATE_RESTING = true,
	ZONE_CHANGED_NEW_AREA = true,
}

function SafeTime.Init(ctx)
	local frame = CreateFrame("Frame")
	for event in pairs(SafeTime.TRIGGERS) do
		frame:RegisterEvent(event)
	end
	for _, event in ipairs({ "CINEMATIC_START", "CINEMATIC_STOP", "LOADING_SCREEN_ENABLED",
		"LOADING_SCREEN_DISABLED" }) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event)
		if event == "CINEMATIC_START" then
			busy.cinematic = true
		elseif event == "CINEMATIC_STOP" then
			busy.cinematic = false
			SafeTime.Schedule(ctx)
		elseif event == "LOADING_SCREEN_ENABLED" then
			busy.loading = true
		elseif event == "LOADING_SCREEN_DISABLED" then
			busy.loading = false
			SafeTime.Schedule(ctx)
		else
			SafeTime.Schedule(ctx)
		end
	end)
	SafeTime.frame = frame
	-- A reaction left from an earlier session may be announced after login.
	local char = realCharacter(ctx)
	if char and Reactions.NextNotice(char, ctx.now()) then
		SafeTime.Schedule(ctx, SafeTime.LOGIN_DELAY)
	end
	return frame
end
