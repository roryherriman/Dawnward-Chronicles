-- /dawnward memory | arc | goal | stance | continuity: the narrative records
-- from chat. Every change goes through Actions.WithCharacter (read-only
-- data refused, nothing created by a failed first write).
local _, ns = ...
local Util, Commands, Actions, Records, Memories, Arcs, Goals, Identity, Continuity =
	ns.Util, ns.Commands, ns.Actions, ns.Records, ns.Memories, ns.Arcs, ns.Goals, ns.Identity, ns.Continuity

local NarrativeCommands = {}
ns.NarrativeCommands = NarrativeCommands

local out, preview = Commands.Out, Commands.Preview

local function run(ctx, fn, done)
	local _, message = Actions.WithCharacter(ctx, function(char)
		local r, err = fn(char, ctx.now())
		if not r then return Actions.Fail(err) end
		return r, type(done) == "function" and done(r) or done
	end)
	out(ctx, message)
end

local function id(word)
	local n = tonumber(word)
	return Util.IsPositiveInteger(n) and n or nil
end

-- Shared subcommands for record lists: accept, dispute, remove, vis.
local function common(ctx, mod, label, sub, n, tail)
	if sub == "accept" then
		run(ctx, function(char, now) return mod.Accept(char, n, now) end, label .. " #" .. n .. " is now established.")
	elseif sub == "dispute" then
		run(ctx, function(char, now) return mod.Dispute(char, n, now) end, label .. " #" .. n .. " is marked disputed.")
	elseif sub == "remove" then
		if Util.NextWord(tail):lower() ~= "confirm" then
			out(ctx, string.format("This removes %s #%d. Add: confirm", label:lower(), n))
			return true
		end
		run(ctx, function(char) return mod.Remove(char, n) end, "Removed " .. label:lower() .. " #" .. n .. ".")
	elseif sub == "vis" then
		local level = Util.NextWord(tail):lower()
		run(ctx, function(char, now) return mod.SetVisibility(char, n, level, now) end,
			label .. " #" .. n .. " is now " .. level .. ".")
	else
		return false
	end
	return true
end

local function line(r, body)
	return string.format("  #%d %s [%s]", r.id, preview(body or ""), Records.Label(r))
end

Commands.Register("memory", function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	local char = Actions.Character(ctx)
	if sub == "" or sub == "list" then
		local list = char and char.story.memories or {}
		out(ctx, string.format("Memories (%d):", #list))
		for i = #list, math.max(1, #list - 9), -1 do
			local m = list[i]
			out(ctx, line(m, (m.title and (m.title .. ": ") or "") .. (m.text or "")))
		end
		out(ctx, "memory add <text> | accept|dispute|vis|remove <#> | supersede <#> <by #>")
		return
	elseif sub == "add" then
		run(ctx, function(c, now) return Memories.Add(c, { text = args }, "player", now) end,
			function(m) return "Added memory #" .. m.id .. " (established, " .. m.visibility .. ")." end)
		return
	end
	local idWord, tail = Util.NextWord(args)
	local n = id(idWord)
	if not n then
		out(ctx, "Usage: /dawnward memory list | add <text> | accept|dispute|vis|remove|supersede <#>")
		return
	end
	if sub == "supersede" then
		local by = id((Util.NextWord(tail)))
		run(ctx, function(c, now) return Memories.Supersede(c, n, by, now) end, "Memory #" .. n .. " is superseded.")
	elseif not common(ctx, Memories, "Memory", sub, n, tail) then
		out(ctx, "Unknown memory command '" .. sub .. "'.")
	end
end)

Commands.Register("arc", function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	local char = Actions.Character(ctx)
	if sub == "" or sub == "list" then
		local list = char and char.story.arcs or {}
		out(ctx, string.format("Arcs (%d):", #list))
		for _, a in ipairs(list) do
			out(ctx, line(a, string.format("%s (%s, %s, %d turning points)", a.title, a.kind, a.state, #a.turningPoints)))
		end
		out(ctx, "arc add <title> | accept|dispute|vis|remove <#> | state <#> active|paused|concluded|abandoned | "
			.. "rename <#> <title> | turn <#> <note>")
		return
	elseif sub == "add" then
		run(ctx, function(c, now) return Arcs.Add(c, { title = args }, "player", now) end,
			function(a) return "Added arc #" .. a.id .. "." end)
		return
	end
	local idWord, tail = Util.NextWord(args)
	local n = id(idWord)
	if not n then
		out(ctx, "Usage: /dawnward arc list | add <title> | <command> <#> ...")
		return
	end
	if sub == "state" then
		local state = Util.NextWord(tail):lower()
		run(ctx, function(c, now) return Arcs.SetState(c, n, state, now) end, "Arc #" .. n .. " is now " .. state .. ".")
	elseif sub == "rename" then
		run(ctx, function(c, now) return Arcs.Rename(c, n, tail, now) end, "Renamed arc #" .. n .. ".")
	elseif sub == "turn" then
		run(ctx, function(c, now) return Arcs.AddTurningPoint(c, n, tail, nil, now) end,
			"Added a turning point to arc #" .. n .. ".")
	elseif not common(ctx, Arcs, "Arc", sub, n, tail) then
		out(ctx, "Unknown arc command '" .. sub .. "'.")
	end
end)

Commands.Register("goal", function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	local char = Actions.Character(ctx)
	if sub == "" or sub == "list" then
		local list = char and char.story.goals or {}
		out(ctx, string.format("Goals (%d):", #list))
		for _, g in ipairs(list) do
			local p = Goals.Progress(char, g)
			local objective = p.objective and string.format(", level %s/%d%s", tostring(p.objective.current or "?"),
				p.objective.target, p.objective.met and " (reached)" or "") or ""
			out(ctx, line(g, string.format("%s (%s, %d/%d milestones%s)", g.title, g.state, p.milestonesDone,
				p.milestonesTotal, objective)))
		end
		out(ctx, "goal add <title> | goal level <#> <target level> | goal milestone <#> <text> | goal done <#> <n> | "
			.. "goal state <#> <state> | goal vis|remove <#>")
		return
	elseif sub == "add" then
		run(ctx, function(c, now) return Goals.Add(c, { title = args }, now) end,
			function(g) return "Added goal #" .. g.id .. " (private)." end)
		return
	end
	local idWord, tail = Util.NextWord(args)
	local n = id(idWord)
	if not n then
		out(ctx, "Usage: /dawnward goal list | add <title> | <command> <#> ...")
		return
	end
	if sub == "state" then
		local state = Util.NextWord(tail):lower()
		run(ctx, function(c, now) return Goals.SetState(c, n, state, now) end, "Goal #" .. n .. " is now " .. state .. ".")
	elseif sub == "milestone" then
		run(ctx, function(c, now) return Goals.AddMilestone(c, n, tail, now) end, "Added a milestone to goal #" .. n .. ".")
	elseif sub == "done" or sub == "undone" then
		local index = id((Util.NextWord(tail)))
		run(ctx, function(c, now) return Goals.SetMilestone(c, n, index, sub == "done", now) end,
			"Updated goal #" .. n .. ".")
	elseif sub == "level" then
		local target = id((Util.NextWord(tail)))
		run(ctx, function(c, now)
			local g = Goals.Find(c, n)
			if not g then return nil, "no goal #" .. n end
			if not target or target < 2 or target > 100 then return nil, "the target level must be 2-100" end
			g.objective, g.updatedAt = { kind = "level", target = target }, now
			return g
		end, "Goal #" .. n .. " now tracks reaching level " .. tostring(target) .. " (verified from your level-ups).")
	elseif not common(ctx, Goals, "Goal", sub, n, tail) then
		out(ctx, "Unknown goal command '" .. sub .. "'.")
	end
end)

Commands.Register("stance", function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	local char = Actions.Character(ctx)
	if sub == "" or sub == "list" then
		local list = char and char.story.identity or {}
		out(ctx, string.format("Public persona and private convictions (%d):", #list))
		for _, i in ipairs(list) do
			out(ctx, line(i, string.format("%s - public: %s / private: %s [%s]%s", i.subject, i.persona or "-",
				i.conviction or "-", i.convictionVisibility, i.deliberate and " (deliberate)" or "")))
		end
		out(ctx, "stance add <subject>; <public stance>; <private conviction>   (either side may be empty)")
		out(ctx, "stance vis <#> <level> (public side) | stance private <#> <level> | stance remove <#> confirm")
		return
	elseif sub == "add" then
		-- ";" separates the parts: WoW's chat box doubles a typed "|".
		local subject, persona, conviction = args:match("^([^;]+);([^;]*);?(.*)$")
		if not subject then
			out(ctx, "Usage: /dawnward stance add <subject>; <public stance>; <private conviction>")
			return
		end
		run(ctx, function(c, now) return Identity.Add(c, { subject = subject, persona = persona, conviction = conviction },
			now) end, function(i) return "Added stance #" .. i.id .. " (both sides private until you change them)." end)
		return
	end
	local idWord, tail = Util.NextWord(args)
	local n = id(idWord)
	if not n then
		out(ctx, "Usage: /dawnward stance list | add ... | vis|private|remove <#> ...")
		return
	end
	if sub == "private" then
		local level = Util.NextWord(tail):lower()
		run(ctx, function(c, now) return Identity.SetConvictionVisibility(c, n, level, now) end,
			"The private conviction of stance #" .. n .. " is now " .. level .. ".")
	elseif not common(ctx, Identity, "Stance", sub, n, tail) then
		out(ctx, "Unknown stance command '" .. sub .. "'.")
	end
end)

Commands.Register("continuity", function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	local char = Actions.Character(ctx)
	if sub == "" or sub == "list" then
		local findings = char and Continuity.Findings(char) or {}
		out(ctx, string.format("Continuity review (%d to look at):", #findings))
		for i, f in ipairs(findings) do
			out(ctx, string.format("  %d. %s", i, f.message))
		end
		if #findings > 0 then
			out(ctx, "Answer: /dawnward continuity <n> growth|unreliable|secret|correction|ignore   "
				.. "(nothing in your story is changed for you)")
		end
		return
	end
	local n = id(sub)
	local findings = char and Continuity.Findings(char) or {}
	local finding = n and findings[n]
	if not finding then
		out(ctx, "Usage: /dawnward continuity | continuity <n> <answer>")
		return
	end
	local choice, note = Util.NextWord(args)
	choice = choice:lower()
	run(ctx, function(c, now) return Continuity.Review(c, finding.key, choice, note, now) end,
		"Noted as " .. choice .. ".")
end)

Commands.Register("person", function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	local char = Actions.Character(ctx)
	if sub == "" or sub == "list" then
		local list = char and ns.People.OfKind(char, nil) or {}
		out(ctx, string.format("People they know (%d):", #list))
		for _, p in ipairs(list) do
			out(ctx, line(p, string.format("%s%s (%s)%s", p.name, p.realm and ("-" .. p.realm) or "", p.kind,
				p.relation and (": " .. p.relation) or "")))
		end
		out(ctx, "person add npc|player|family|other <name>; <relation>   (players: Name-Realm)")
		out(ctx, "person feel <#> <how they feel> | person vis <#> <level> | person remove <#> confirm")
		return
	elseif sub == "add" then
		local kind, restArgs = Util.NextWord(args)
		local who, relation = restArgs:match("^([^;]+);?(.*)$")
		if not who then
			out(ctx, "Usage: /dawnward person add npc|player|family|other <name>; <relation>")
			return
		end
		who = Util.Trim(who)
		local name, realm = who, nil
		if kind:lower() == "player" then
			name, realm = who:match("^([^%-]+)%-(.+)$")
			name = name or who
		end
		run(ctx, function(c, now) return ns.People.Add(c, { kind = kind:lower(), name = name, realm = realm,
			relation = relation }, now) end, function(p) return "Added #" .. p.id .. " " .. p.name .. " (private)." end)
		return
	end
	local idWord, tail = Util.NextWord(args)
	local n = id(idWord)
	if not n then
		out(ctx, "Usage: /dawnward person list | add ... | feel|vis|remove <#> ...")
		return
	end
	if sub == "feel" then
		run(ctx, function(c, now) return ns.People.Edit(c, n, { feelings = tail }, now) end,
			"Noted how they feel about #" .. n .. " (private).")
	elseif not common(ctx, ns.People, "Person", sub, n, tail) then
		out(ctx, "Unknown person command '" .. sub .. "'.")
	end
end)

-- A roleplay moment the player records (#40): it becomes a story event at
-- once, marked as player-authored, and may be reflected on immediately.
Commands.Register("moment", function(ctx, rest)
	if Util.Trim(rest) == "" then
		out(ctx, "Usage: /dawnward moment <what happened>   (a ceremony, a vow, a meeting: anything you roleplayed)")
		return
	end
	local _, message = Actions.WithCharacter(ctx, function(char)
		local data = { title = rest, zone = ctx.zone and ctx.zone() or nil }
		local record, err = ns.GameEvents.Record(char, "moment", data, ctx.now())
		if not record then return Actions.Fail(err) end
		local reaction = ns.Reactions.Consider(char, record, ctx.now())
		return record, "Recorded your moment" .. (reaction and ("; reflect on it: /dawnward story " .. reaction.id)
			or ".")
	end)
	out(ctx, message)
end)

Commands.Register("timeline", function(ctx, rest)
	local char = Actions.Character(ctx)
	if not char then
		out(ctx, "Nothing recorded yet.")
		return
	end
	local n = tonumber((Util.NextWord(rest))) or 12
	local dated, undated = ns.Timeline.Build(char, { limit = n })
	out(ctx, string.format("Timeline, newest first (%d shown):", #dated))
	for _, item in ipairs(dated) do
		out(ctx, string.format("  %s  %s: %s [%s]", ctx.formatTime and ctx.formatTime(item.at) or tostring(item.at),
			item.kind, preview(item.text), item.visibility))
	end
	if #undated > 0 then
		out(ctx, "Before the chronicle (undated):")
		for _, item in ipairs(undated) do
			out(ctx, string.format("  %s%s [%s]", item.when and (item.when .. ": ") or "", preview(item.text),
				item.visibility))
		end
	end
end)

Commands.Register("reflect", function(ctx)
	local _, message = Actions.WithCharacter(ctx, function(char)
		local back = ns.Reactions.Reflect(char)
		local waiting = #ns.Reactions.List(char, ctx.now())
		local pending = #ns.Evolution.Pending(char)
		local drafts = #ns.Journal.Search(char, { kind = "story", status = "draft" })
		local review = #ns.Continuity.Findings(char)
		return true, string.format("A quiet moment to reflect: %d waiting moment%s (%d brought back from later), %d "
			.. "personality change%s, %d draft%s, %d thing%s to review. Nothing has to change: skipping is fine.",
			waiting, waiting == 1 and "" or "s", back, pending, pending == 1 and "" or "s", drafts,
			drafts == 1 and "" or "s", review, review == 1 and "" or "s")
	end)
	out(ctx, message)
	if ctx.ui and ctx.ui.ShowStory then
		ctx.ui.ShowStory()
	end
end)
