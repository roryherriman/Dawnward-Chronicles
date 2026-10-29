-- /dawnward trp3 ... subcommands. Plugged into the core through ctx.trp3,
-- so Core/ never touches Total RP 3.
--
-- ctx.trp3Deps() must return the Sync deps (see Sync.lua). Anything that
-- writes to TRP3 or removes content requires the word "confirm".
local _, ns = ...
local Util, Sync, AboutBlock, TraitPlan, Projection =
	ns.Util, ns.TRP3Sync, ns.TRP3AboutBlock, ns.TRP3TraitPlan, ns.Projection

local TRP3Commands = {}
ns.TRP3Commands = TRP3Commands

local HELP = {
	"Total RP 3 sync (EXPERIMENTAL, off by default; Total RP 3 3.4.1 only):",
	"  trp3 preview | trp3 sync | trp3 paste | trp3 backups | trp3 log",
	"  trp3 enable about|traits confirm | trp3 disable about|traits",
	"  trp3 release about|traits confirm | trp3 rollback [#] confirm",
	"  trp3 resolve about|traits keep|reclaim",
	"  trp3 diagnose (read-only: which guard is holding each feature back)",
}

local STATE_LABEL = {
	off = "off", blocked = "blocked", deferred = "waiting", conflict = "CONFLICT", noop = "up to date",
	ready = "has changes to write",
}
TRP3Commands.STATE_LABEL = STATE_LABEL

local function out(ctx, line)
	ctx.print(line)
end

local function featureArg(word)
	word = (word or ""):lower()
	if word == "about" or word == "biography" or word == "bio" then
		return "about"
	elseif word == "traits" or word == "personality" then
		return "traits"
	end
	return nil
end

--- Text for the manual (copy-and-paste) path: always available.
function TRP3Commands.ManualText(char)
	local public = char and Projection.GetPublic(char) or { facts = {}, personality = {} }
	local lines = { "-- Paste this at the end of your Total RP 3 About text --", "" }
	local block = AboutBlock.Compose(public)
	lines[#lines + 1] = block ~= "" and block or "(no public facts yet)"
	lines[#lines + 1] = ""
	lines[#lines + 1] = "-- Suggested Total RP 3 personality traits (custom traits; left / right) --"
	local any = false
	for _, axisId in ipairs({ "courage", "compassion", "discipline", "faith", "honour", "sociability" }) do
		local d = TraitPlan.Desired(public)[axisId]
		if d then
			any = true
			lines[#lines + 1] = string.format("%s %d / %d %s", d.LT, d.V2, 20 - d.V2, d.RT)
		end
	end
	if not any then
		lines[#lines + 1] = "(no public personality values yet)"
	end
	return table.concat(lines, "\n")
end

local function describeCheck(ctx, check)
	local spec = Sync.FEATURES[check.feature]
	local line = string.format("  %s: %s", spec.label, STATE_LABEL[check.state] or check.state)
	if #check.reasons > 0 then
		line = line .. " - " .. table.concat(check.reasons, "; ")
	end
	out(ctx, line)
	if check.plan and check.plan.changes and #check.plan.changes > 0 then
		out(ctx, "    would change: " .. table.concat(check.plan.changes, ", "))
	elseif check.plan and check.state == "ready" then
		out(ctx, "    would " .. check.plan.action .. " the Dawnward section")
	end
end

local function flag(v)
	if v == nil then return "unknown" end
	return v and "yes" or "no"
end

--- Read-only report of every guard input, so an in-game "waiting" or
-- "blocked" can be traced to the exact check. Writes nothing.
local function diagnose(ctx, deps)
	local probe = ns.TRP3Adapter.Probe(deps.env)
	local status = probe.status
	out(ctx, "Total RP 3 sync diagnostics (read-only, nothing is written):")
	out(ctx, string.format("  Total RP 3: %s, version %s, writes allowed: %s", status.loaded and "loaded"
		or "not loaded", tostring(status.version), flag(probe.experimental.allowed)))
	if probe.profile then
		out(ctx, string.format("  profile: '%s' (%s), default: %s", tostring(probe.profile.name),
			tostring(probe.profile.id), flag(probe.profile.isDefault)))
	end
	for _, r in ipairs(probe.experimental.reasons) do
		out(ctx, "  capability check failed: " .. r)
	end
	for _, section in ipairs({ "about", "characteristics" }) do
		local e = probe.editorState and probe.editorState[section]
		if e then
			out(ctx, string.format("  %s editor: draft %s (%s) - page %s, context %s, edit mode %s, tab shown %s, "
				.. "edit frame shown %s", section, flag(e.open), tostring(e.why), tostring(e.pageId),
				flag(e.hasContext), flag(e.editMode), flag(e.tabShown), flag(e.editShown)))
		end
	end
	out(ctx, string.format("  simulation: %s, saved data read-only: %s, ledger read-only: %s, in combat: %s",
		flag(deps.store:IsSimulation()), flag(deps.store.realReadOnly == true), flag(deps.ledgerReadOnly ~= nil),
		flag(deps.inCombat and deps.inCombat() or false)))
	local entry = deps.ledger.optIn[deps.characterKey]
	for _, feature in ipairs(Sync.ORDER) do
		local check = Sync.Check(deps, feature)
		out(ctx, string.format("  %s: opted in %s (profile %s), state %s%s", Sync.FEATURES[feature].label,
			flag(entry and entry[feature] == true), tostring(entry and entry.profileId),
			STATE_LABEL[check.state] or check.state,
			#check.reasons > 0 and (" - " .. table.concat(check.reasons, "; ")) or ""))
	end
end

local function statusLines(ctx)
	local deps = ctx.trp3Deps()
	local entry = deps.ledger.optIn[deps.characterKey]
	if not entry or not (entry.about or entry.traits) then
		return { "  Automatic profile sync: off (experimental; see /dawnward trp3 help)" }
	end
	local lines = { "  Automatic profile sync (EXPERIMENTAL):" }
	for _, feature in ipairs(Sync.ORDER) do
		if entry[feature] then
			local check = Sync.Check(deps, feature)
			lines[#lines + 1] = string.format("    %s: %s%s", Sync.FEATURES[feature].label,
				STATE_LABEL[check.state] or check.state,
				#check.reasons > 0 and (" - " .. table.concat(check.reasons, "; ")) or "")
		end
	end
	return lines
end

--- Extra lines for /dawnward trp3 and status.
function TRP3Commands.StatusLines(ctx)
	local ok, lines = pcall(statusLines, ctx)
	if not ok then
		return { "  Automatic profile sync: status unavailable (" .. tostring(lines) .. ")" }
	end
	return lines
end

--- One line for a Sync.RunFeature result (chat and the settings page).
function TRP3Commands.ResultText(r)
	local label = Sync.FEATURES[r.feature].label
	if r.state == "noop" then
		return "Total RP 3 " .. label .. ": already up to date (nothing written)."
	elseif r.state == "written" or r.state == "failed" or r.state == "conflict" then
		return r.message
	end
	return "Total RP 3 " .. label .. ": not written - " .. tostring(r.message)
end

local function runSync(ctx, deps)
	local results = Sync.Run(deps)
	if #results == 0 then
		out(ctx, "Automatic sync is off for this character. Nothing was written. See /dawnward trp3 help")
		return
	end
	for _, r in ipairs(results) do
		out(ctx, TRP3Commands.ResultText(r))
	end
end

--- The explicit write for ONE opted-in feature: the same guarded
-- Sync.RunFeature that "trp3 sync" runs (through Sync.Run) for every
-- opted-in feature. Writes nothing for a feature that is not opted in.
-- Returns the RunFeature result, or nil plus a reason.
function TRP3Commands.Approve(deps, feature)
	if not Sync.FEATURES[feature] then
		return nil, "unknown feature"
	end
	local entry = deps.ledger.optIn[deps.characterKey]
	if not entry or not entry[feature] then
		return nil, "Automatic " .. Sync.FEATURES[feature].label .. " sync is off for this character. "
			.. "Nothing was written."
	end
	return Sync.RunFeature(deps, feature)
end

--- Warning shown before a feature is switched on (chat adds how to confirm).
function TRP3Commands.EnableWarning(feature)
	return "EXPERIMENTAL: this lets Dawnward change your Total RP 3 " .. Sync.FEATURES[feature].label
		.. " automatically, using Total RP 3 internals with no official support. Only Dawnward's own "
		.. "section is changed and a backup is taken first. Try it on a spare (non-default) TRP3 profile "
		.. "first."
end

-- A backup holds the section exactly as it was, including what Dawnward
-- wrote from facts that were public then. Rollback is a recovery tool and
-- restores it unchanged, so the player is told before confirming.
TRP3Commands.ROLLBACK_PRIVACY = "Privacy: the section comes back exactly as it was then. Anything Dawnward "
	.. "had written from items you have since made Private or Secret would be visible again; check the section "
	.. "afterwards, or run a sync (or release) to bring Dawnward's part up to date."
TRP3Commands.ROLLBACK_WARNING = "This restores a Total RP 3 section from Dawnward's newest backup "
	.. "(see /dawnward trp3 backups). " .. TRP3Commands.ROLLBACK_PRIVACY

--- Switches a feature on or off: Sync.SetOptIn, then (when turning on) the
-- same debounced automatic run request the command makes. Returns ok, message.
function TRP3Commands.SetFeature(ctx, deps, feature, on)
	local ok, message = Sync.SetOptIn(deps, feature, on)
	if on and ctx.trp3RequestSync then
		ctx.trp3RequestSync()
	end
	return ok, message
end

--- One backup as a display line.
function TRP3Commands.BackupLine(b, formatTime)
	return string.format("#%d %s, profile %s, %s%s", b.id, b.section, b.profileId,
		b.reason or "", formatTime and (" (" .. formatTime(b.at) .. ")") or "")
end

--- Exactly what Dawnward would write, from the PUBLIC projection only (the
-- same Compose/Desired inputs Sync.Check plans with, including the chosen
-- presentation style). Returns { about = string, traits = { {axis,LT,RT,V2} } }.
function TRP3Commands.PublicPreview(char)
	local public = char and Projection.GetPublic(char) or { facts = {}, personality = {} }
	public.trp3Style = char and char.story and char.story.prefs.trp3Style or nil
	local traits = {}
	local desired = TraitPlan.Desired(public)
	for _, axisId in ipairs({ "courage", "compassion", "discipline", "faith", "honour", "sociability" }) do
		local d = desired[axisId]
		if d then
			traits[#traits + 1] = { axis = axisId, LT = d.LT, RT = d.RT, V2 = d.V2 }
		end
	end
	return { about = AboutBlock.Compose(public), traits = traits }
end

--- Read-only snapshot for the settings page: the adapter probe, the opt-in
-- entry, a Sync.Check per feature (the same check "trp3 preview" prints),
-- the public preview and the backups of the active profile. Writes nothing
-- to Total RP 3.
function TRP3Commands.Overview(deps)
	local probe = ns.TRP3Adapter.Probe(deps.env)
	local view = { probe = probe, entry = deps.ledger.optIn[deps.characterKey], checks = {}, backups = {},
		ledgerReadOnly = deps.ledgerReadOnly }
	for _, feature in ipairs(Sync.ORDER) do
		view.checks[feature] = Sync.Check(deps, feature)
	end
	local profileId = probe.profile and probe.profile.id
	for i = #deps.ledger.backups, 1, -1 do
		local b = deps.ledger.backups[i]
		if b.profileId == profileId then
			view.backups[#view.backups + 1] = b
		end
	end
	local char = deps.store.real.characters[deps.characterKey]
	view.preview = TRP3Commands.PublicPreview(char)
	return view
end

local function command(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	local deps = ctx.trp3Deps()
	local word1, tail = Util.NextWord(args)
	local word2 = Util.NextWord(tail):lower()
	local confirmed = false
	for word in args:lower():gmatch("%S+") do
		if word == "confirm" then confirmed = true end
	end

	if sub == "help" then
		for _, line in ipairs(HELP) do out(ctx, line) end
	elseif sub == "preview" then
		out(ctx, "Total RP 3 sync preview (nothing is written):")
		for _, feature in ipairs(Sync.ORDER) do
			describeCheck(ctx, Sync.Check(deps, feature))
		end
	elseif sub == "diagnose" then
		diagnose(ctx, deps)
	elseif sub == "sync" then
		runSync(ctx, deps)
	elseif sub == "paste" then
		local text = TRP3Commands.ManualText(deps.store.real.characters[deps.characterKey])
		if ctx.ui and ctx.ui.ShowExport then
			ctx.ui.ShowExport("Total RP 3 text to paste - public facts only", text)
			out(ctx, "Copy the text from the window (Ctrl+C) and paste it into Total RP 3 yourself.")
		else
			out(ctx, "No window is available to show the text.")
		end
	elseif sub == "enable" or sub == "disable" then
		local feature = featureArg(word1)
		if not feature then
			out(ctx, "Usage: /dawnward trp3 enable about|traits confirm | trp3 disable about|traits")
			return
		end
		if sub == "enable" and not confirmed then
			out(ctx, TRP3Commands.EnableWarning(feature) .. " Type: /dawnward trp3 enable " .. feature .. " confirm")
			return
		end
		local _, message = TRP3Commands.SetFeature(ctx, deps, feature, sub == "enable")
		out(ctx, message or "Not changed.")
	elseif sub == "release" then
		local feature = featureArg(word1)
		if not feature or not confirmed then
			out(ctx, "This removes Dawnward's own section from Total RP 3 (your text stays) and turns sync off. "
				.. "Type: /dawnward trp3 release about|traits confirm")
			return
		end
		local _, message = Sync.Release(deps, feature)
		out(ctx, message)
	elseif sub == "rollback" then
		local id = tonumber(word1)
		if not confirmed then
			out(ctx, TRP3Commands.ROLLBACK_WARNING .. " Type: /dawnward trp3 rollback [#] confirm")
			return
		end
		local _, message = Sync.Rollback(deps, Util.IsPositiveInteger(id) and id or nil)
		out(ctx, message)
	elseif sub == "backups" then
		if #deps.ledger.backups == 0 then
			out(ctx, "No Dawnward backups of Total RP 3 sections yet.")
			return
		end
		out(ctx, "Dawnward backups of Total RP 3 sections (newest last):")
		for _, b in ipairs(deps.ledger.backups) do
			out(ctx, "  " .. TRP3Commands.BackupLine(b, ctx.formatTime))
		end
	elseif sub == "resolve" then
		local feature = featureArg(word1)
		local _, message = Sync.Resolve(deps, feature, word2)
		out(ctx, message)
	elseif sub == "log" then
		if #deps.ledger.log == 0 then
			out(ctx, "The Total RP 3 sync log is empty.")
		end
		for _, line in ipairs(deps.ledger.log) do
			out(ctx, "  " .. line.text)
		end
	else
		out(ctx, "Unknown trp3 command '" .. sub .. "'. Try /dawnward trp3 help")
	end
end

--- Entry point: a TRP3 surprise must never break /dawnward.
function TRP3Commands.Command(ctx, rest)
	local ok, err = pcall(command, ctx, rest)
	if not ok then
		ctx.print("Total RP 3 command failed safely: " .. tostring(err))
	end
end
