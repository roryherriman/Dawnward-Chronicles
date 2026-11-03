-- Decides when a waiting story reaction may be announced, and announces it
-- quietly: one chat line, and the small reaction card if the player wants it.
--
-- Never during combat, while dead or a ghost, during a cinematic or a
-- loading screen, while the player is AFK (UnitIsAFK), or inside a dungeon
-- or raid (IsInInstance "party"/"raid": boss fights and group pulls come and
-- go between combat checks, so a moment waits until the group content is
-- left). Checks run only on events that mark a calmer moment (leaving
-- combat, reviving, resting, arriving in a zone, coming back from AFK) and
-- shortly after a reaction is queued; nothing polls. Waiting moments are
-- never lost: they are announced at the next calm moment, or kept in the
-- Story section until they expire on the gameplay clock. Pacing (how often)
-- is the core's job (Reactions.NextNotice); this module decides whether
-- *now* is safe, shows one card at a time, and records whether it was
-- actually displayed (Core/Reactions.lua "Notices"). When the notice
-- cooldown holds a moment back, one timer fires as it ends.
local _, ns = ...
local Reactions = ns.Reactions

local SafeTime = {}
ns.SafeTime = SafeTime

SafeTime.DELAY = 4            -- seconds after a trigger before checking
SafeTime.LOGIN_DELAY = 20     -- after login, let the world settle first
-- After the player closed a card (Close, Escape, Later, Dismiss, Not now),
-- the next one waits at least this long, even for a major moment: a closed
-- card is never followed by another one seconds later.
SafeTime.CLOSE_GAP = 120

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	return nil
end

local busy = { cinematic = false, loading = false }
local scheduled = false

function SafeTime.Reasons()
	local reasons = {}
	if InCombatLockdown() then reasons[#reasons + 1] = "combat" end
	if UnitIsDeadOrGhost("player") then reasons[#reasons + 1] = "dead" end
	if busy.cinematic then reasons[#reasons + 1] = "cinematic" end
	if busy.loading then reasons[#reasons + 1] = "loading" end
	-- UnitIsAFK: UnitDocumentation.lua; IsInInstance: Classic UI code
	-- (classic_era 1.15.9.70576). Both are also used elsewhere in Dawnward.
	if call(UnitIsAFK, "player") then reasons[#reasons + 1] = "away" end
	local inInstance, instanceType = call(IsInInstance)
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		reasons[#reasons + 1] = "instance"
	end
	return reasons
end

function SafeTime.IsSafe()
	return #SafeTime.Reasons() == 0
end

-- Reactions come from real gameplay, so they live on the real character.
local function realCharacter(ctx)
	return ctx.store.real.characters[ctx.characterKey]
end

-- Card hooks (UI/ReactionCard.lua, wired by Platform/Bootstrap): ShowCard(id,
-- more) returns true when the card is on screen; ShownId() names the moment
-- on screen; SetMore(n) updates the card's "n more waiting" line.
SafeTime.MAX_TRIES = 3        -- card attempts before the chat line stands in

local retryAt -- when the one pending cooldown retry fires (a real date), or nil
local quietUntil -- no card before this real date (CLOSE_GAP after a close), or nil
SafeTime.lastError = nil      -- why the last card attempt failed (session only)

-- The moment on screen, if the card is showing one.
function SafeTime.CardShownId()
	if SafeTime.ShownId then
		local ok, id = pcall(SafeTime.ShownId)
		if ok then return id end
	end
	return nil
end

-- Moments waiting besides the one announced (the card's "n more" line).
local function others(char, now)
	return math.max(0, #Reactions.List(char, now) - 1)
end

-- One timer for the end of the notice cooldown: the moment it held back is
-- offered then (if it is safe), instead of at the next zone change or
-- fight by chance. Never more than one pending; nothing polls.
local function retryAfterCooldown(ctx, due, now)
	if retryAt and retryAt <= due + 1 then
		return
	end
	retryAt = due
	C_Timer.After(math.max(1, due - now + 1), function()
		retryAt = nil
		SafeTime.Run(ctx)
	end)
end

--- Why no card can appear now (simulation, read-only, or SafeTime.Reasons),
-- as reason codes; empty when it may.
function SafeTime.Blockers(ctx)
	local reasons = SafeTime.Reasons()
	if ctx.store.realReadOnly then reasons[#reasons + 1] = "readonly" end
	if ctx.store:IsSimulation() then reasons[#reasons + 1] = "simulation" end
	return reasons
end

--- Announces the next due reaction if it is safe. Returns the reaction or nil.
-- The moment counts as announced only once the card (or, with the card
-- switched off, the chat line) was displayed; a card that does not appear
-- leaves it eligible for the next calm moment (after MAX_TRIES attempts the
-- chat line stands in, so it is never lost silently).
function SafeTime.Run(ctx)
	-- In simulation mode the Story commands act on test data, so a notice
	-- about a real moment would point at the wrong character: it waits.
	if #SafeTime.Blockers(ctx) > 0 then
		return nil
	end
	local char = realCharacter(ctx)
	if not char then
		return nil
	end
	local now = ctx.now()
	-- One card at a time: one on screen is never replaced (its moment would
	-- count as announced, unseen); the line under it says how many wait.
	if SafeTime.CardShownId() then
		if SafeTime.SetMore then pcall(SafeTime.SetMore, others(char, now)) end
		return nil
	end
	-- The pause after the player closed a card (one timer for its end).
	if quietUntil and now < quietUntil then
		if #Reactions.NoticeOrder(char, now) > 0 then
			retryAfterCooldown(ctx, quietUntil, now)
		end
		return nil
	end
	local reaction, info = Reactions.NextNotice(char, now)
	if not reaction then
		if info and info.cooldownUntil then
			retryAfterCooldown(ctx, info.cooldownUntil, now)
		end
		return nil
	end
	local view = Reactions.Present(char, reaction)
	local question = view and view.question
	local via = "chat"
	if char.story.prefs.card and SafeTime.ShowCard and question then
		local ok, shown = pcall(SafeTime.ShowCard, reaction.id, others(char, now))
		if ok and shown and SafeTime.CardShownId() == reaction.id then
			via = "card"
		else
			SafeTime.lastError = not ok and tostring(shown) or "the card did not appear"
			Reactions.NoticeFailed(char, reaction.id, now)
			if (reaction.noticeTries or 0) < SafeTime.MAX_TRIES then
				return nil
			end
		end
	elseif not question then
		Reactions.NoticeFailed(char, reaction.id, now)
		if (reaction.noticeTries or 0) < SafeTime.MAX_TRIES then
			return nil
		end
	end
	Reactions.MarkNotified(char, reaction.id, now, via)
	ctx.print("A moment for your story: " .. (question or "a moment is waiting.") .. "  (/dawnward story "
		.. reaction.id .. ", or the Story section of the journal)")
	return reaction
end

--- The scheduled check (and the one tests call directly).
function SafeTime.Check(ctx)
	scheduled = false
	return SafeTime.Run(ctx)
end

-- How a card went away that schedules nothing: Answer opened the journal
-- on it (another card would pop up over the player's reading), Dawnward
-- replaced or withdrew it ("gone"), or combat hid it (leaving combat is a
-- trigger of its own).
SafeTime.NO_FOLLOW = { answer = true, gone = true, combat = true }

--- The card went away (UI/ReactionCard: how is "close", "escape", "journal",
-- "later", "dismiss", "answer", "combat" or "gone"). Records it on the
-- moment. After the player closed it, the next waiting moment follows no
-- sooner than CLOSE_GAP (pacing permitting); after Answer, or when Dawnward
-- withdrew it, nothing is scheduled: the next calm-moment trigger offers it.
function SafeTime.Closed(ctx, id, how)
	local char = realCharacter(ctx)
	if not char or ctx.store.realReadOnly or ctx.store:IsSimulation() then
		return
	end
	local now = ctx.now()
	Reactions.NoticeClosed(char, id, how, now)
	if SafeTime.NO_FOLLOW[how] then
		return
	end
	quietUntil = now + SafeTime.CLOSE_GAP
	if #Reactions.NoticeOrder(char, now) > 0 then
		retryAfterCooldown(ctx, quietUntil, now)
	end
end

--- The end of the pause after a closed card (a real date), or nil.
function SafeTime.QuietUntil(now)
	if quietUntil and (now == nil or quietUntil > now) then
		return quietUntil
	end
	return nil
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
	-- (unit): AFK and other flags; only the player's own matter here.
	PLAYER_FLAGS_CHANGED = true,
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
	frame:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_FLAGS_CHANGED" and unit ~= nil and unit ~= "player" then
			return
		end
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
	-- A moment left from an earlier session and never shown is offered after
	-- login once it is safe (the notice cooldown still applies).
	local char = realCharacter(ctx)
	if char and #Reactions.NoticeOrder(char, ctx.now()) > 0 then
		SafeTime.Schedule(ctx, SafeTime.LOGIN_DELAY)
	end
	return frame
end
