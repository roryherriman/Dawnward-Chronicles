-- /dawnward story and /dawnward develop: the living chronicle from chat.
-- Everything here is also reachable from the journal window's Story section.
local _, ns = ...
local Util, Commands, Actions, Reactions, Evolution, Decisions, GameEvents =
	ns.Util, ns.Commands, ns.Actions, ns.Reactions, ns.Evolution, ns.Decisions, ns.GameEvents

local StoryCommands = {}
ns.StoryCommands = StoryCommands

local out, preview = Commands.Out, Commands.Preview

local SIGNIFICANCE = { "routine", "notable", "major" }

local function reactionLine(char, r)
	local view = Reactions.Present(char, r)
	return string.format("  #%d [%s%s] %s", r.id, SIGNIFICANCE[r.significance] or "?",
		r.status == "postponed" and ", later" or "", view and preview(view.question or "") or "(unavailable)")
end

local function showReaction(ctx, char, r)
	local view, err = Reactions.Present(char, r)
	if not view then
		out(ctx, "Reaction #" .. r.id .. ": " .. err)
		return
	end
	out(ctx, string.format("Reaction #%d: %s", r.id, view.question))
	if view.context then
		out(ctx, "  " .. view.context)
	end
	-- The Director's reasons and recollections (verified data and the player's own).
	if view.why and #view.why > 0 then
		out(ctx, "  Why now: " .. table.concat(view.why, "; ") .. ".")
	end
	if view.recall then out(ctx, "  " .. view.recall) end
	if view.echo then out(ctx, "  Last time: " .. view.echo .. ".") end
	for i, option in ipairs(view.options) do
		out(ctx, string.format("  %d. %s", i, option.text))
	end
	out(ctx, string.format("Answer: /dawnward story %d <answer #> | story %d write <your own words> | "
		.. "story %d later | story %d notnow | story %d dismiss", r.id, r.id, r.id, r.id, r.id))
end

local function settings(ctx, char)
	local p = char and char.story.prefs or ns.StorySchema.NewPrefs()
	local tracked = {}
	for _, category in ipairs({ "quest", "levelup", "death", "zone", "place" }) do
		tracked[#tracked + 1] = category .. " " .. (p.tracking[category] and "on" or "off")
	end
	out(ctx, "Story settings:")
	out(ctx, string.format("  frequency %s (off|rare|normal|frequent), threshold %d (1-3), approval %s (ask|auto)",
		p.frequency, p.threshold, p.approval))
	out(ctx, string.format("  drafts %s, flavor %s, card %s, trp3Style %s, places %s (on|fewer|off)",
		p.drafts and "on" or "off", p.flavor and "on" or "off", p.card and "on" or "off", p.trp3Style, p.places))
	out(ctx, string.format("  pace %s (brisk|standard|slow): a narrative day is %d hour%s of play", p.pace,
		ns.NarrativeClock.PACES[p.pace] / 3600, ns.NarrativeClock.PACES[p.pace] == 3600 and "" or "s"))
	out(ctx, string.format("  repeat %d (0-14): narrative days before the same question about the same place, "
		.. "faction or zone's quests is asked again (0 off)", p.repeatDays or ns.Reactions.DEFAULT_REPEAT_DAYS))
	out(ctx, "  tracking: " .. table.concat(tracked, ", "))
	out(ctx, "Change: /dawnward story set <setting> <value> | story track <category> on|off")
end

local function listAll(ctx, char)
	local list = char and Reactions.List(char, ctx.now()) or {}
	if #list == 0 then
		out(ctx, "No story reactions are waiting (" .. Commands.ModeLabel(ctx) .. "). Keep adventuring.")
	else
		out(ctx, string.format("Story reactions waiting (%d):", #list))
		for _, r in ipairs(list) do
			out(ctx, reactionLine(char, r))
		end
		out(ctx, "Open one: /dawnward story <#>")
	end
	local pending = char and #Evolution.Pending(char) or 0
	if pending > 0 then
		out(ctx, string.format("%d personality change%s waiting for approval: /dawnward develop", pending,
			pending == 1 and "" or "s"))
	end
end

Commands.Register("story", function(ctx, rest)
	local word, tail = Util.NextWord(rest)
	word = word:lower()
	local char = Actions.Character(ctx)
	if word == "" or word == "list" then
		listAll(ctx, char)
		return
	elseif word == "settings" then
		settings(ctx, char)
		return
	elseif word == "set" then
		local name, value = Util.NextWord(tail)
		-- "repeat" (any case) is the chat name of the repeat window.
		if name:lower() == "repeat" or name:lower() == "repeatdays" then name = "repeatDays" end
		local _, message = Actions.SetStoryPref(ctx, name, value:lower())
		out(ctx, message)
		return
	elseif word == "track" then
		local category, value = Util.NextWord(tail)
		value = Util.NextWord(value):lower()
		if value ~= "on" and value ~= "off" then
			out(ctx, "Usage: /dawnward story track quest|levelup|death|zone|place on|off")
			return
		end
		local _, message = Actions.SetTracking(ctx, category:lower(), value == "on")
		out(ctx, message)
		return
	elseif word == "events" then
		local recent = char and GameEvents.Recent(char, 10) or {}
		out(ctx, string.format("Recent events (%d recorded):", char and #char.story.events or 0))
		for _, e in ipairs(recent) do
			out(ctx, string.format("  %s%s%s [%s, %s, %s]", GameEvents.RecordLabel(e),
				e.meta.title and (": " .. e.meta.title) or (e.level and e.category ~= "quest" and (" " .. e.level) or ""),
				e.zone and (" in " .. e.zone) or "", SIGNIFICANCE[e.significance], e.confidence, e.status))
		end
		return
	elseif word == "decisions" then
		local list = char and Decisions.Recent(char, 10) or {}
		out(ctx, "Recent decisions:")
		for _, d in ipairs(list) do
			out(ctx, string.format("  #%d %s: %s", d.id, d.category, preview(d.custom or d.phrase or d.optionId or "")))
		end
		return
	end
	local id = tonumber(word)
	if not Util.IsPositiveInteger(id) then
		out(ctx, "Usage: /dawnward story | story <#> | story settings | story events | story decisions")
		return
	end
	local reaction = char and Reactions.Find(char, id)
	if not reaction then
		out(ctx, "No waiting reaction #" .. id .. ". See /dawnward story")
		return
	end
	local action, text = Util.NextWord(tail)
	action = action:lower()
	local message
	if action == "" then
		showReaction(ctx, char, reaction)
		return
	elseif action == "write" then
		_, message = Actions.Decide(ctx, id, { custom = text })
	elseif action == "later" then
		_, message = Actions.PostponeReaction(ctx, id)
	elseif action == "notnow" or action == "ignore" then
		_, message = Actions.IgnoreReaction(ctx, id)
	elseif action == "dismiss" then
		_, message = Actions.DismissReaction(ctx, id)
	else
		local n = tonumber(action)
		local view = Reactions.Present(char, reaction)
		local option = view and n and view.options[n]
		if not option then
			out(ctx, "Choose an answer number from /dawnward story " .. id)
			return
		end
		_, message = Actions.Decide(ctx, id, { optionId = option.id })
	end
	out(ctx, message)
end)

Commands.Register("develop", function(ctx, rest)
	local word, tail = Util.NextWord(rest)
	word = word:lower()
	local char = Actions.Character(ctx)
	if word == "" or word == "list" then
		local pending = char and Evolution.Pending(char) or {}
		out(ctx, string.format("Personality changes waiting for approval (%d):", #pending))
		for _, c in ipairs(pending) do
			out(ctx, string.format("  #%d %s - because %s", c.id, Evolution.Describe(c), preview(c.reason or "?")))
		end
		local history = char and Evolution.History(char, 5) or {}
		if #history > 0 then
			out(ctx, "Recent development:")
			for _, c in ipairs(history) do
				if c.status ~= "pending" then
					out(ctx, string.format("  #%d %s %s%s", c.id, c.status, Evolution.Describe(c),
						c.to and string.format(" (%s -> %d)", tostring(c.from), c.to) or ""))
				end
			end
		end
		out(ctx, "Approve: /dawnward develop approve <#> | reject <#> | reverse <#>. Adjust by hand any time: "
			.. "/dawnward personality set <axis> <0-20>")
		return
	end
	local id = tonumber((Util.NextWord(tail)))
	if not Util.IsPositiveInteger(id) then
		out(ctx, "Usage: /dawnward develop | develop approve|reject|reverse <#>")
		return
	end
	local message
	if word == "approve" then
		_, message = Actions.ApplyChange(ctx, id)
	elseif word == "reject" then
		_, message = Actions.RejectChange(ctx, id)
	elseif word == "reverse" then
		_, message = Actions.ReverseChange(ctx, id)
	else
		message = "Unknown develop command '" .. word .. "'."
	end
	out(ctx, message)
end)
