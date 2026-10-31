-- Opens first-time setup by itself after a genuinely new character enters
-- the world (v0.9), instead of waiting for the player to open Dawnward.
--
-- Rules (Core/Onboarding.lua, LoginAction):
--   * a new character that has never seen the wizard: it opens once, a few
--     seconds after the world is ready, and that is remembered
--     (db.ui.setupSeen), so it never opens by itself again
--   * setup left unfinished: later logins offer to resume it (once per
--     session), with the draft intact; nothing opens by itself
--   * setup complete, or an established character: nothing happens
-- It never opens during combat, a cinematic or a movie (a brand-new
-- character's intro cinematic plays first), or while the loading screen is
-- up; it waits and tries again when that ends (PLAYER_REGEN_ENABLED,
-- CINEMATIC_STOP, LOADING_SCREEN_DISABLED) or after RETRY seconds, at most
-- MAX_TRIES times. Never in simulation mode or on read-only data.
local _, ns = ...
local Onboarding, Actions = ns.Onboarding, ns.Actions

local SetupLaunch = {}
ns.SetupLaunch = SetupLaunch

SetupLaunch.DELAY = 3      -- seconds after the world is ready
SetupLaunch.RETRY = 5      -- seconds between tries while something blocks it
SetupLaunch.MAX_TRIES = 60 -- about five minutes of waiting at most

local done, tries, generation = false, 0, 0

local function shown(name)
	local frame = _G[name]
	local ok, result = pcall(function() return frame and frame.IsShown and frame:IsShown() end)
	return ok and result == true
end

--- Why setup cannot open right now, or nil. Each check is optional, so a
-- client without one of these functions simply skips it. Verified for
-- 1.15.9 in the client's UI source (classic_era): InCinematic
-- (CinematicDocumentation.lua), CinematicFrame (Shared/CinematicFrame.xml),
-- LOADING_SCREEN_ENABLED/DISABLED (LoadingScreenDocumentation.lua),
-- CINEMATIC_STOP (Shared/CinematicFrame.lua).
function SetupLaunch.Blocked()
	if InCombatLockdown and InCombatLockdown() then
		return "combat"
	end
	if InCinematic and InCinematic() then
		return "cinematic"
	end
	if shown("CinematicFrame") or shown("MovieFrame") then
		return "cinematic"
	end
	if SetupLaunch.loading then
		return "loading"
	end
	return nil
end

local function schedule(delay)
	generation = generation + 1
	local mine = generation
	C_Timer.After(delay, function()
		if mine == generation then
			SetupLaunch.Try()
		end
	end)
end

-- "Continue setting up …?" with the draft intact. Accept opens the wizard
-- where it was left; anything else leaves it for Settings > Run setup.
local function offer(ctx)
	local name = UnitName and UnitName("player") or "this character"
	ctx.print("Setup for " .. tostring(name) .. " is unfinished. Resume it with /dawnward setup, or from "
		.. "Settings > Run setup.")
	ns.Widgets.Confirm("Continue setting up " .. tostring(name) .. "?\n\nYour answers so far are kept. "
		.. "You can also finish it later from Settings > Run setup.", "Resume", function()
		ns.SetupWizard.Open({})
	end)
end

-- What this session still has to do: "open", "offer", or nil (nothing;
-- the session's decision is then final). Cheap and read-only.
local function pending()
	local ctx = ns.ctx
	if done or not ctx then
		return nil
	end
	if ctx.store:IsSimulation() or ctx.store:ReadOnlyReason() or ns.SetupWizard.WasAutoShown(ctx.characterKey) then
		done = true
		return nil
	end
	local char = ctx.store.real.characters[ctx.characterKey]
	local action = Onboarding.LoginAction(char, Actions.SetupSeen(ctx), ctx.now())
	if action == "none" then
		done = true
		return nil
	end
	return action
end

--- Decides and acts once per session. Returns what it did: "open",
-- "offer", "waiting" or "skipped" (nothing to do).
function SetupLaunch.Try()
	local action = pending()
	if not action then
		return "skipped"
	end
	local ctx = ns.ctx
	if SetupLaunch.Blocked() then
		tries = tries + 1
		if tries < SetupLaunch.MAX_TRIES then
			schedule(SetupLaunch.RETRY)
			return "waiting"
		end
		done = true
		return "skipped"
	end
	done = true
	ns.SetupWizard.SkipAutoLaunchThisSession(ctx.characterKey)
	if ns.SetupWizard.IsShown() then
		return "skipped"
	end
	if action == "open" then
		Actions.MarkSetupSeen(ctx)
		ns.SetupWizard.Open({})
		return "open"
	end
	offer(ctx)
	return "offer"
end

--- For tests: forget this session's decision.
function SetupLaunch.Reset()
	done, tries, generation = false, 0, generation + 1
	SetupLaunch.loading = nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LOADING_SCREEN_ENABLED")
frame:RegisterEvent("LOADING_SCREEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("CINEMATIC_STOP")
frame:SetScript("OnEvent", function(_, event)
	if done then
		return
	end
	if event == "LOADING_SCREEN_ENABLED" then
		SetupLaunch.loading = true
		return
	elseif event == "LOADING_SCREEN_DISABLED" then
		SetupLaunch.loading = nil
	end
	-- Only queue a try when this session still has something to do.
	if pending() then
		schedule(SetupLaunch.DELAY)
	end
end)
