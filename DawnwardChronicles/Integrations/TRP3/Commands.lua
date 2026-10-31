-- /dawnward trp3 ... subcommands. Plugged into the core through ctx.trp3,
-- so Core/ never touches Total RP 3.
--
-- ctx.trp3Deps() must return the Sync deps (see Sync.lua). Anything that
-- writes to TRP3 or removes content requires the word "confirm".
local _, ns = ...
local Util, Sync, AboutBlock, TraitPlan, Projection, FieldPlan, Ledger =
	ns.Util, ns.TRP3Sync, ns.TRP3AboutBlock, ns.TRP3TraitPlan, ns.Projection, ns.TRP3FieldPlan, ns.TRP3Ledger

local TRP3Commands = {}
ns.TRP3Commands = TRP3Commands

local HELP = {
	"Total RP 3 sync (EXPERIMENTAL, off by default; Total RP 3 3.4.1 only):",
	"  trp3 preview | trp3 sync | trp3 paste | trp3 backups | trp3 log",
	"  trp3 enable about|traits confirm | trp3 disable about|traits",
	"  trp3 fields (each mapping, who manages it, and what Total RP 3 holds vs your Public value)",
	"  trp3 field <title|race|class|age|homeland> dawnward confirm | trp3 field <name> trp3|off",
	"  trp3 import <field> [private|public|secret] confirm (copy Total RP 3's value into Dawnward)",
	"  trp3 release about|traits|fields confirm | trp3 rollback [#] [exact] confirm",
	"  trp3 resolve about|traits|<field> keep|reclaim",
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
	elseif word == "fields" then
		return "fields"
	end
	return nil
end

-- A field mapping id ("race", "title", ...), or nil.
local function fieldArg(word)
	word = (word or ""):lower()
	return FieldPlan.BY_ID[word] and word or nil
end

-- Dawnward fields and where they go in TRP3's editor (manual path only).
TRP3Commands.MANUAL_FIELDS = {
	{ source = "name", trp3 = "First and last name" },
	{ source = "title", trp3 = "Full title" },
	{ source = "race", trp3 = "Race" },
	{ source = "class", trp3 = "Class" },
	{ source = "age", trp3 = "Age" },
	{ source = "homeland", trp3 = "Birthplace" },
	{ source = "pronouns", trp3 = "Additional information: Pronouns" },
	{ source = "faith", trp3 = "Additional information (custom): Faith" },
	{ source = "occupation", trp3 = "Additional information (custom): Occupation" },
	{ source = "appearance", trp3 = "About (template 3): Physical description" },
}

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
	-- Profile fields: every Public Dawnward field with a TRP3 place to type
	-- it, including those Dawnward never writes itself.
	lines[#lines + 1] = ""
	lines[#lines + 1] = "-- Public profile fields (type them into Total RP 3's characteristics yourself) --"
	local shown = false
	for _, f in ipairs(TRP3Commands.MANUAL_FIELDS) do
		local entry = public.fields and public.fields[f.source]
		if entry and entry.visibility == "public" then
			shown = true
			lines[#lines + 1] = f.trp3 .. ": " .. entry.value
		end
	end
	if not shown then
		lines[#lines + 1] = "(no public profile fields yet)"
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
	if check.plan and check.plan.rows then
		for _, row in ipairs(check.plan.rows) do
			out(ctx, "    " .. TRP3Commands.FieldRowText(row))
		end
	elseif check.plan and check.plan.changes and #check.plan.changes > 0 then
		out(ctx, "    would change: " .. table.concat(check.plan.changes, ", "))
	elseif check.plan and check.state == "ready" then
		out(ctx, "    would " .. check.plan.action .. " the Dawnward section")
	end
end

local ROW_STATE = {
	write = "will write", clear = "will clear (no longer Public)", noop = "up to date",
	matches = "Total RP 3 already shows the same text (yours, not managed)", empty = "nothing Public to write",
	conflict = "PAUSED", unwritable = "not writable",
}

--- One planned field as a line: "Race -> Race: will write 'Half-elf'".
function TRP3Commands.FieldRowText(row)
	local m = FieldPlan.BY_ID[row.id]
	local text = m.label .. " -> " .. m.trp3 .. ": " .. (ROW_STATE[row.state] or row.state)
	if row.state == "write" then
		text = text .. " '" .. tostring(row.desired) .. "'"
	elseif row.state == "conflict" or row.state == "unwritable" then
		text = text .. " - " .. tostring(row.reason)
	end
	return text
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
			flag(Sync.FeatureOn(entry, feature)), tostring(entry and entry.profileId),
			STATE_LABEL[check.state] or check.state,
			#check.reasons > 0 and (" - " .. table.concat(check.reasons, "; ")) or ""))
	end
end

local function statusLines(ctx)
	local deps = ctx.trp3Deps()
	local entry = deps.ledger.optIn[deps.characterKey]
	if not TRP3Commands.AnyManaged(entry) then
		return { "  Automatic profile sync: off (experimental; see /dawnward trp3 help)" }
	end
	local lines = { "  Automatic profile sync (EXPERIMENTAL):" }
	for _, feature in ipairs(Sync.ORDER) do
		if Sync.FeatureOn(entry, feature) then
			local check = Sync.Check(deps, feature)
			lines[#lines + 1] = string.format("    %s: %s%s", Sync.FEATURES[feature].label,
				STATE_LABEL[check.state] or check.state,
				#check.reasons > 0 and (" - " .. table.concat(check.reasons, "; ")) or "")
		end
	end
	return lines
end

--- True when Dawnward manages anything for this opt-in entry.
function TRP3Commands.AnyManaged(entry)
	for _, feature in ipairs(Sync.ORDER) do
		if Sync.FeatureOn(entry, feature) then
			return true
		end
	end
	return false
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
	if not Sync.FeatureOn(entry, feature) then
		return nil, "Automatic " .. Sync.FEATURES[feature].label .. " sync is off for this character. "
			.. "Nothing was written."
	end
	return Sync.RunFeature(deps, feature)
end

--- The single authorisation of the v0.9 first-time setup ("Connect"):
-- every mapping becomes managed by Dawnward for the active profile, through
-- Sync.Authorize (all-or-nothing, every guard and the shared-profile rule
-- apply). opts.existing == "replace": where Total RP 3 already holds the
-- player's own text, Dawnward may take it over on its first write, after a
-- pinned backup (Sync.Authorize's adopt); "keep" leaves it untouched and
-- pauses those items until the player chooses. Nothing is written here:
-- the normal debounced run writes. Returns ok, message.
function TRP3Commands.ConnectAll(ctx, opts)
	opts = opts or {}
	local deps = ctx.trp3Deps and ctx.trp3Deps()
	if not deps then
		return nil, "Total RP 3 sync is not available"
	end
	local choices = {}
	for _, id in ipairs(Ledger.MAPPINGS) do
		choices[id] = "dawnward"
	end
	local ok, message = Sync.Authorize(deps, choices, { adopt = opts.existing == "replace" })
	if ok and ctx.trp3RequestSync then
		ctx.trp3RequestSync()
	end
	return ok, message
end

--- Warning shown before a feature is switched on (chat adds how to confirm).
function TRP3Commands.EnableWarning(feature)
	local m = FieldPlan.BY_ID[feature]
	if m then
		return "EXPERIMENTAL: this lets Dawnward keep your Total RP 3 " .. m.trp3 .. " equal to your Public "
			.. m.label .. ", automatically, using Total RP 3 internals with no official support. It writes only "
			.. "while Total RP 3 still holds the value Dawnward last wrote; if it already holds your own value, "
			.. "nothing is overwritten until you choose. A backup is taken before every write."
	end
	return "EXPERIMENTAL: this lets Dawnward change your Total RP 3 " .. Sync.FEATURES[feature].label
		.. " automatically, using Total RP 3 internals with no official support. Only Dawnward's own "
		.. "section is changed and a backup is taken first. Try it on a spare (non-default) TRP3 profile "
		.. "first."
end

-- A backup holds the section exactly as it was, including what Dawnward
-- wrote from facts that were public then. The safe default restores only
-- the player's own content and rebuilds Dawnward's part from what is
-- Public now; an exact restore is offered separately, naming what it would
-- bring back.
TRP3Commands.ROLLBACK_PRIVACY = "Privacy: by default only your own text comes back from the backup and "
	.. "Dawnward's part is rebuilt from what is Public now. An exact restore brings the section back exactly as it "
	.. "was then: anything Dawnward had written from items you have since made Private or Secret would be "
	.. "visible again."
TRP3Commands.ROLLBACK_WARNING = "This restores a Total RP 3 section from Dawnward's newest backup "
	.. "(see /dawnward trp3 backups). " .. TRP3Commands.ROLLBACK_PRIVACY

--- Lines describing a Sync.RollbackPreview (what an exact restore would
-- bring back that is no longer Public). Pure.
function TRP3Commands.RollbackRiskLines(preview, max)
	local lines = {}
	if #preview.items == 0 then
		lines[1] = "Nothing in this backup's Dawnward part is hidden now: an exact restore brings back no Private "
			.. "or Secret item."
		return lines
	end
	lines[1] = "An exact restore would make visible again " .. #preview.items .. " item(s) that are no longer "
		.. "Public in Dawnward:"
	max = max or #preview.items
	for i = 1, math.min(max, #preview.items) do
		lines[#lines + 1] = "  - " .. preview.items[i]
	end
	if #preview.items > max then
		lines[#lines + 1] = "  (+" .. (#preview.items - max) .. " more)"
	end
	return lines
end

--- Copies Total RP 3's current value of a mapped field into Dawnward, through
-- the normal Actions write path (read-only check, validation, sync request).
-- level: the Dawnward visibility to give it (default "private"). Never
-- automatic: only the player's explicit command or button calls this.
-- Returns ok, message.
function TRP3Commands.Import(ctx, id, level)
	local m = FieldPlan.BY_ID[id]
	if not m then
		return nil, "unknown field '" .. tostring(id) .. "'"
	end
	level = level or "private"
	if not ns.Privacy.IsValid(level) then
		return nil, "choose private, public or secret"
	end
	local deps = ctx.trp3Deps()
	local section, err = ns.TRP3Adapter.ReadAudited(deps.env, "characteristics")
	if not section then
		return nil, "Nothing was imported: " .. tostring(err) .. "."
	end
	local value = FieldPlan.Display(m, section[m.key])
	if type(value) ~= "string" or value == "" then
		return nil, "Total RP 3 has no " .. m.trp3 .. " to import"
	end
	-- Import exactly or not at all: Dawnward's field rules (length, one line)
	-- must not silently shorten or reshape the player's text.
	local spec = ns.Schema.FIELD_BY_KEY[m.source]
	if ns.Schema.CleanValue(spec, value) ~= value then
		return nil, "Nothing was imported: Total RP 3's " .. m.trp3 .. " is longer than Dawnward's "
			.. m.label .. " field allows (" .. ns.Schema.LIMITS[spec.kind] .. " bytes) or has formatting it does "
			.. "not keep. Copy the part you want by hand."
	end
	return ns.Actions.WithCharacter(ctx, function(char)
		local ok, ferr = ns.Character.SetField(char, m.source, value, ctx.now())
		if not ok then return ns.Actions.Fail(ferr) end
		local vok, verr = ns.Character.SetFieldVisibility(char, m.source, level, ctx.now())
		if not vok then return ns.Actions.Fail(verr) end
		return true, "Imported Total RP 3's " .. m.trp3 .. " into your Dawnward " .. m.label .. " (" .. level .. ")."
	end)
end

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
	local fields = {}
	local fieldValues = FieldPlan.Desired(public)
	for _, m in ipairs(FieldPlan.MAPPINGS) do
		if fieldValues[m.id] then
			fields[#fields + 1] = { id = m.id, label = m.label, trp3 = m.trp3,
				value = FieldPlan.Display(m, fieldValues[m.id]) }
		end
	end
	local miscValues = ns.TRP3MiscPlan.Desired(public)
	for _, m in ipairs(ns.TRP3MiscPlan.MAPPINGS) do
		if miscValues[m.id] then
			fields[#fields + 1] = { id = m.id, label = m.label, trp3 = m.trp3, value = miscValues[m.id] }
		end
	end
	return { about = AboutBlock.Compose(public), traits = traits, fields = fields }
end

--- Read-only snapshot for the settings page: the adapter probe, the opt-in
-- entry, a Sync.Check per feature (the same check "trp3 preview" prints),
-- the public preview and the backups of the active profile. Writes nothing
-- to Total RP 3.
function TRP3Commands.Overview(deps)
	-- One probe and one read per section for the whole view (Sync.ProbeOf):
	-- the page refreshes often and writes nothing.
	local cached = {}
	for k, v in pairs(deps) do cached[k] = v end
	cached.cache = {}
	deps = cached
	local probe = Sync.ProbeOf(deps)
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
	view.differences = Sync.Differences(deps)
	view.policies = {}
	local bound = view.entry and probe.profile and view.entry.profileId == probe.profile.id
	view.bound = bound and true or false
	for _, id in ipairs(Ledger.MAPPINGS) do
		view.policies[id] = Ledger.Policy(bound and view.entry or nil, id)
	end
	-- Conflicts only for fields Dawnward manages now.
	local record = profileId and deps.ledger.profiles[profileId]
	view.fieldConflicts = {}
	for id, reason in pairs(record and record.fieldConflicts or {}) do
		if view.policies[id] == "dawnward" then
			view.fieldConflicts[id] = reason
		end
	end
	-- Fields that would still show a value Dawnward wrote but that is no
	-- longer Public, if they stopped being managed (Sync.FieldRisk).
	view.risks = {}
	for _, id in ipairs(Ledger.MAPPINGS) do
		if Sync.MappingOf(id) and view.policies[id] == "dawnward" then
			view.risks[id] = Sync.FieldRisk(deps, id)
		end
	end
	return view
end

--- The rollback warning, with what an exact restore would bring back that
-- is no longer Public (the same preview the Total RP 3 page shows). Read-only.
function TRP3Commands.RollbackPreviewLines(deps, id, formatTime)
	local lines = { TRP3Commands.ROLLBACK_WARNING }
	local preview = Sync.RollbackPreview(deps, id)
	if preview then
		lines[#lines + 1] = "Backup: " .. TRP3Commands.BackupLine(preview.backup, formatTime)
		for _, line in ipairs(TRP3Commands.RollbackRiskLines(preview)) do lines[#lines + 1] = line end
		if not preview.ownPossible then
			lines[#lines + 1] = "Your own text cannot be separated from this backup (" .. tostring(preview.ownReason)
				.. "); only an exact restore is possible."
		end
	end
	lines[#lines + 1] = "Type: /dawnward trp3 rollback [#] confirm (your own text only; Dawnward's part rebuilt "
		.. "from what is Public now) or /dawnward trp3 rollback [#] exact confirm (everything exactly as it was)"
	return lines
end

--- /dawnward trp3 fields: every mapping, its policy, and the differences
-- between Total RP 3 and Dawnward's Public values. Read-only.
function TRP3Commands.FieldsReport(ctx, deps)
	local probe = ns.TRP3Adapter.Probe(deps.env)
	local entry = deps.ledger.optIn[deps.characterKey]
	local bound = entry and probe.profile and entry.profileId == probe.profile.id
	out(ctx, "Total RP 3 mappings (who manages each; nothing is written by this command):")
	for _, id in ipairs(Ledger.MAPPINGS) do
		local policy = Ledger.Policy(bound and entry or nil, id)
		out(ctx, string.format("  %s: %s", Sync.MappingLabel(id), Sync.POLICY_LABEL[policy]))
	end
	local diff = Sync.Differences(deps)
	if diff.reason then
		out(ctx, "Differences unavailable: " .. tostring(diff.reason))
	else
		out(ctx, "Total RP 3 vs your Public Dawnward value:")
		for _, row in ipairs(diff.rows) do
			out(ctx, string.format("  %s (%s): Total RP 3 '%s' / Dawnward %s%s%s", row.label, row.trp3Label,
				row.trp3 or "-", row.dawnward and ("'" .. row.dawnward .. "'") or (row.hidden and "(not Public)" or "-"),
				row.differ and " - differs" or " - same", row.conflict and (" - PAUSED: " .. row.conflict) or ""))
			if row.unwritable then
				out(ctx, "    not writable: " .. row.unwritable)
			end
		end
	end
	out(ctx, "Not synchronised automatically (see /dawnward trp3 paste):")
	for _, u in ipairs(ns.TRP3FieldPlan.UNSUPPORTED) do
		out(ctx, "  " .. u.label .. " - " .. u.reason)
	end
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
	elseif sub == "fields" then
		TRP3Commands.FieldsReport(ctx, deps)
	elseif sub == "field" then
		local id = fieldArg(word1)
		local policy = word2
		if not id or not Ledger.POLICIES[policy] then
			out(ctx, "Usage: /dawnward trp3 field <title|race|class|age|homeland> dawnward|trp3|off "
				.. "(dawnward needs the word confirm)")
			return
		end
		if policy == "dawnward" and not confirmed then
			out(ctx, TRP3Commands.EnableWarning(id) .. " Type: /dawnward trp3 field " .. id .. " dawnward confirm")
			return
		end
		local release, keep = false, false
		for word in args:lower():gmatch("%S+") do
			if word == "release" then release = true elseif word == "keep" then keep = true end
		end
		local ok, message, risk = Sync.SetPolicy(deps, id, policy,
			{ release = release and confirmed, keep = keep and confirmed })
		if not ok and risk then
			out(ctx, "Warning: " .. risk.reason .. ".")
			out(ctx, "Type: /dawnward trp3 field " .. id .. " " .. policy .. " release confirm (remove it from Total "
				.. "RP 3 first; recommended) or /dawnward trp3 field " .. id .. " " .. policy .. " keep confirm "
				.. "(leave it showing)")
			return
		end
		out(ctx, message or "Not changed.")
	elseif sub == "import" then
		local id = fieldArg(word1)
		local level = (word2 ~= "" and word2 ~= "confirm") and word2 or "private"
		if not id or not confirmed then
			out(ctx, "This copies Total RP 3's value of a field into your Dawnward profile (Private unless you say "
				.. "otherwise). Type: /dawnward trp3 import <title|race|class|age|homeland> [private|public|secret] "
				.. "confirm")
			return
		end
		local _, message = TRP3Commands.Import(ctx, id, level)
		out(ctx, message)
	elseif sub == "release" then
		local feature = featureArg(word1)
		if not feature or not confirmed then
			out(ctx, "This removes Dawnward's own content from Total RP 3 (your text stays) and turns sync off. "
				.. "Type: /dawnward trp3 release about|traits|fields confirm")
			return
		end
		local _, message = Sync.Release(deps, feature)
		out(ctx, message)
	elseif sub == "rollback" then
		local id = tonumber(word1)
		id = Util.IsPositiveInteger(id) and id or nil
		local exact = false
		for word in args:lower():gmatch("%S+") do
			if word == "exact" then exact = true end
		end
		if not confirmed then
			for _, line in ipairs(TRP3Commands.RollbackPreviewLines(deps, id, ctx.formatTime)) do out(ctx, line) end
			return
		end
		local _, message = Sync.Rollback(deps, id, exact and "exact" or "own")
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
		local feature = featureArg(word1) or fieldArg(word1)
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
