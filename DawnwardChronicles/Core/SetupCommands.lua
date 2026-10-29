-- /dawnward setup (the first-time setup wizard, on demand) and the
-- developer-only /dawnward dev commands for testing it repeatably.
--
-- Developer commands exist only in development builds (an addon version
-- containing "-dev"): release builds answer that they are unavailable.
-- They never touch a character's profile, journal or story. The one reset
-- forgets only the setup state, and only after "confirm". The story
-- diagnostics (Core/StoryDiagnostics.lua) are read-only.
local _, ns = ...
local Util, Commands, Actions, Onboarding = ns.Util, ns.Commands, ns.Actions, ns.Onboarding

local SetupCommands = {}
ns.SetupCommands = SetupCommands

local out = Commands.Out

--- Whether developer commands are available in this build.
function SetupCommands.DevEnabled(ctx)
	return type(ctx.version) == "string" and ctx.version:find("-dev", 1, true) ~= nil
end

--- Status lines for /dawnward dev setup status. Pure apart from reading ctx.
function SetupCommands.StatusLines(ctx)
	local char = ctx.store.real.characters[ctx.characterKey]
	local wizard = char and char.wizard or {}
	local lines = {}
	if wizard.done then
		local when = wizard.doneAt and wizard.doneAt > 0 and ctx.formatDate and (", " .. ctx.formatDate(wizard.doneAt))
			or ""
		lines[#lines + 1] = string.format("Setup: complete (wizard version %s%s).", tostring(wizard.version or "?"), when)
	else
		lines[#lines + 1] = "Setup: not complete."
	end
	lines[#lines + 1] = "Current wizard version: " .. Onboarding.VERSION .. "."
	local draft = Actions.SetupDraft(ctx)
	if draft then
		local page = Onboarding.PAGES[draft.page]
		lines[#lines + 1] = string.format("Draft: saved, page %d of %d (%s).", draft.page, #Onboarding.PAGES,
			page and page.title or "?")
	else
		lines[#lines + 1] = "Draft: none."
	end
	if Onboarding.IsEstablished(char, ctx.now()) then
		lines[#lines + 1] = "This character has Dawnward data, so the wizard never opens by itself (Settings > Run setup)."
	elseif wizard.done then
		lines[#lines + 1] = "The wizard will not open by itself again."
	else
		lines[#lines + 1] = "New character: the wizard opens the next time Dawnward is opened."
	end
	return lines
end

Commands.Register("setup", function(ctx)
	if ctx.ui and ctx.ui.ShowSetup then
		ctx.ui.ShowSetup({})
	else
		out(ctx, "The setup wizard opens in the game window.")
	end
end)

local DEV_USAGE = "Developer commands: /dawnward dev setup | dev setup status | dev setup reset | "
	.. "dev story status | dev story simulate [place]"

-- Other developer areas register here: DEV_AREAS[name] = { usage, run(ctx, rest) }
-- (Core/StoryDiagnostics.lua adds "story"). They share the build gate below.
SetupCommands.DEV_AREAS = {}

Commands.Register("dev", function(ctx, rest)
	if not SetupCommands.DevEnabled(ctx) then
		out(ctx, "Developer commands are only available in development builds.")
		return
	end
	local area, tail = Util.NextWord(rest or "")
	area = area:lower()
	if SetupCommands.DEV_AREAS[area] then
		SetupCommands.DEV_AREAS[area].run(ctx, tail)
		return
	end
	if area ~= "setup" then
		out(ctx, DEV_USAGE)
		return
	end
	local word, more = Util.NextWord(tail)
	word = word:lower()
	if word == "" then
		if ctx.ui and ctx.ui.ShowSetup then
			ctx.ui.ShowSetup({ test = true })
			out(ctx, "Setup wizard opened as a preview. Nothing is saved unless you choose Save choices, "
				.. "and setup status never changes.")
		else
			out(ctx, "The setup wizard opens in the game window.")
		end
	elseif word == "status" then
		for _, line in ipairs(SetupCommands.StatusLines(ctx)) do
			out(ctx, line)
		end
	elseif word == "reset" then
		if Util.NextWord(more):lower() ~= "confirm" then
			out(ctx, "This forgets only whether this character finished setup, and any unfinished setup draft. "
				.. "The profile, journal, story, memories and goals are not touched. To continue: "
				.. "/dawnward dev setup reset confirm")
			return
		end
		local _, message = Actions.ResetSetup(ctx)
		out(ctx, message)
	else
		out(ctx, DEV_USAGE)
	end
end)
