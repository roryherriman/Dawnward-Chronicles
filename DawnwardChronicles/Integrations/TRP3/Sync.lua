-- Keeps Dawnward-owned content in the player's TRP3 profile up to date.
--
-- Every run re-reads everything and re-checks every guard; nothing is
-- cached between runs. A write happens only when all of these hold:
--   * the player opted this character in for the feature, for this exact
--     TRP3 profile ID (switching profile pauses sync)
--   * the TRP3 version is allowlisted and the adapter's capability checks pass
--   * the profile is not TRP3's default profile
--   * not in simulation mode, saved data is writable, not in combat
--   * no TRP3 editor holds a draft that would overwrite the change
--   * there is no unresolved conflict, and the plan is not a no-op
-- Then: back up the section, write only the owned change, read it back, and
-- restore the backup at once if anything differs (and switch the feature
-- off). Unchanged content writes nothing, so versions never churn.
--
-- deps: { env, ledger, ledgerReadOnly?, store, characterKey, now(), inCombat() }
local _, ns = ...
local Util, Projection, Ledger, Adapter, AboutBlock, TraitPlan =
	ns.Util, ns.Projection, ns.TRP3Ledger, ns.TRP3Adapter, ns.TRP3AboutBlock, ns.TRP3TraitPlan

local Sync = {}
ns.TRP3Sync = Sync

Sync.FEATURES = {
	about = {
		section = "about",
		label = "biography",
		plan = function(section, record, public)
			return AboutBlock.Plan(section, record, AboutBlock.Compose(public))
		end,
		planned = "about",
	},
	traits = {
		section = "characteristics",
		label = "personality traits",
		plan = function(section, record, public)
			return TraitPlan.Plan(section, record, TraitPlan.Desired(public))
		end,
		planned = "characteristics",
	},
}
Sync.ORDER = { "about", "traits" }

local function deepEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end
Sync.DeepEqual = deepEqual

local function realCharacter(deps)
	return deps.store.real.characters[deps.characterKey]
end

local function optIn(deps)
	return deps.ledger.optIn[deps.characterKey]
end

--- Guards that do not depend on the feature. Returns probe, reasons, deferred.
-- deferred is true when the only problem is temporary (combat, open editor).
local function guards(deps, feature)
	local reasons, deferred = {}, false
	if deps.ledgerReadOnly then
		reasons[#reasons + 1] = deps.ledgerReadOnly
	end
	if deps.store:IsSimulation() then
		reasons[#reasons + 1] = "simulation mode is on (simulated data is never published)"
	end
	if deps.store.realReadOnly then
		reasons[#reasons + 1] = "saved data is read-only"
	end
	local probe = Adapter.Probe(deps.env)
	for _, r in ipairs(probe.experimental.reasons) do
		reasons[#reasons + 1] = r
	end
	local entry = optIn(deps)
	if not entry or not entry[feature] then
		reasons[#reasons + 1] = "automatic " .. Sync.FEATURES[feature].label .. " sync is off for this character"
	elseif probe.profile and probe.profile.id ~= entry.profileId then
		reasons[#reasons + 1] = "the active Total RP 3 profile is not the one sync was enabled for"
	end
	if #reasons == 0 then
		local section = Sync.FEATURES[feature].section
		if probe.editorOpen[section] then
			reasons[#reasons + 1] = "the Total RP 3 editor is open; Dawnward will try again after it is closed"
			deferred = true
		elseif deps.inCombat and deps.inCombat() then
			reasons[#reasons + 1] = "in combat; Dawnward will try again later"
			deferred = true
		end
	end
	return probe, reasons, deferred
end

--- Works out what a run would do, without writing anything.
-- Returns { feature, state, reasons, plan, section, probe, profileId } where
-- state is "off", "blocked", "deferred", "conflict", "noop" or "ready".
function Sync.Check(deps, feature)
	local spec = Sync.FEATURES[feature]
	local result = { feature = feature, reasons = {} }
	local probe, reasons, deferred = guards(deps, feature)
	result.probe = probe
	result.reasons = reasons
	local entry = optIn(deps)
	if #reasons > 0 then
		result.state = deferred and "deferred" or ((not entry or not entry[feature]) and "off" or "blocked")
		return result
	end
	local profileId = probe.profile.id
	result.profileId = profileId
	local record = Ledger.Profile(deps.ledger, profileId)
	if record.conflicts[feature] then
		result.state = "conflict"
		result.reasons = { record.conflicts[feature] }
		return result
	end
	local char = realCharacter(deps)
	local public = char and Projection.GetPublic(char) or { facts = {}, personality = {} }
	local section, err = Adapter.ReadSection(deps.env, spec.section)
	if not section then
		result.state = "blocked"
		result.reasons = { err }
		return result
	end
	result.section = Util.DeepCopy(section)
	local plan = spec.plan(section, record[feature], public)
	result.plan = plan
	if plan.action == "conflict" or plan.action == "unsupported" then
		result.state = plan.action == "conflict" and "conflict" or "blocked"
		result.reasons = { plan.reason }
	elseif plan.action == "noop" then
		result.state = "noop"
	else
		result.state = "ready"
	end
	return result
end

local function disable(deps, feature)
	local entry = optIn(deps)
	if entry then
		entry[feature] = false
	end
end

--- Restores a section from backup data through the experimental driver.
local function restore(deps, profileId, sectionName, data)
	return Adapter.WriteSection(deps.env, sectionName, data, profileId)
end

--- Runs one feature. Returns { feature, state, message } where state is one
-- of the Check states, or "written", "failed" (rolled back).
function Sync.RunFeature(deps, feature)
	local spec = Sync.FEATURES[feature]
	local check = Sync.Check(deps, feature)
	local now = deps.now()
	if check.state == "conflict" then
		local record = Ledger.Profile(deps.ledger, check.profileId)
		if not record.conflicts[feature] then
			record.conflicts[feature] = check.reasons[1]
			Ledger.Log(deps.ledger, now, feature .. ": conflict: " .. tostring(check.reasons[1]))
		end
		return { feature = feature, state = "conflict", message = "Total RP 3 " .. spec.label .. " sync paused: "
			.. tostring(check.reasons[1]) .. ". Your version is kept. See /dawnward trp3 resolve." }
	end
	if check.state ~= "ready" then
		return { feature = feature, state = check.state, message = table.concat(check.reasons, "; ") }
	end

	local profileId = check.profileId
	local backup, berr = Ledger.AddBackup(deps.ledger, profileId, spec.section, check.section,
		{ reason = "before " .. check.plan.action .. " " .. feature, characterKey = deps.characterKey }, now)
	if not backup then
		Ledger.Log(deps.ledger, now, feature .. ": not written: " .. tostring(berr))
		return { feature = feature, state = "blocked", message = berr }
	end

	local planned = check.plan[spec.planned]
	local version, werr = Adapter.WriteSection(deps.env, spec.section, planned, profileId)
	local readBack = version and Adapter.ReadSection(deps.env, spec.section)
	local expected = Util.DeepCopy(planned)
	expected.v = version
	if not version or not readBack or not deepEqual(readBack, expected) then
		local why = werr or "the profile did not read back as written"
		local restored = restore(deps, profileId, spec.section, check.section)
		disable(deps, feature)
		Ledger.Log(deps.ledger, now, feature .. ": write failed (" .. why .. "); "
			.. (restored and "restored backup #" .. backup.id or "RESTORE FAILED, use /dawnward trp3 rollback"))
		return { feature = feature, state = "failed", message = "Total RP 3 " .. spec.label .. " update failed ("
			.. why .. "). " .. (restored and "Your profile was restored from the backup"
				or "Restoring failed: run /dawnward trp3 rollback confirm")
			.. " and automatic sync was switched off." }
	end

	local record = Ledger.Profile(deps.ledger, profileId)
	if check.plan.record then
		record[feature] = Util.DeepCopy(check.plan.record)
		record[feature].at = now
	else
		record[feature] = nil
	end
	Ledger.Log(deps.ledger, now, feature .. ": " .. check.plan.action .. " (version " .. version .. ", backup #"
		.. backup.id .. ")")
	return { feature = feature, state = "written", message = "Updated your Total RP 3 " .. spec.label
		.. " (" .. check.plan.action .. "). Other players see it the next time their Total RP 3 checks your profile." }
end

--- Runs every opted-in feature. Returns a list of RunFeature results.
function Sync.Run(deps)
	local results = {}
	for _, feature in ipairs(Sync.ORDER) do
		local entry = optIn(deps)
		if entry and entry[feature] then
			results[#results + 1] = Sync.RunFeature(deps, feature)
		end
	end
	return results
end

--- Turns a feature on (bound to the active profile) or off.
function Sync.SetOptIn(deps, feature, on)
	if not Sync.FEATURES[feature] then
		return nil, "unknown feature '" .. tostring(feature) .. "' (use about or traits)"
	end
	if deps.ledgerReadOnly then
		return nil, deps.ledgerReadOnly
	end
	local entry = optIn(deps)
	if not on then
		if entry then
			entry[feature] = false
		end
		return true, "Automatic " .. Sync.FEATURES[feature].label .. " sync is off. Content Dawnward already wrote "
			.. "stays until you run /dawnward trp3 release " .. feature .. " confirm."
	end
	local probe = Adapter.Probe(deps.env)
	if not probe.experimental.allowed then
		return nil, table.concat(probe.experimental.reasons, "; ")
	end
	local id = probe.profile.id
	if not entry or entry.profileId ~= id then
		entry = { about = false, traits = false, profileId = id }
		deps.ledger.optIn[deps.characterKey] = entry
	end
	entry[feature] = true
	entry.at = deps.now()
	local shared = probe.profile.sharedWith
	return true, string.format("EXPERIMENTAL automatic %s sync is ON for Total RP 3 profile '%s'.%s "
		.. "Dawnward backs up the section before every write; undo with /dawnward trp3 rollback confirm.",
		Sync.FEATURES[feature].label, tostring(probe.profile.name),
		(shared and shared > 0) and (" This profile is shared with " .. shared
			.. " other character(s); they will show the same content.") or "")
end

--- Removes Dawnward's owned content for a feature, then turns it off.
function Sync.Release(deps, feature)
	local spec = Sync.FEATURES[feature]
	if not spec then
		return nil, "unknown feature"
	end
	local entry = optIn(deps)
	if not entry or not entry[feature] then
		return nil, "turn sync on first (it is needed to write); then release"
	end
	local real = deps.store.real
	local saved = real.characters[deps.characterKey]
	-- Plan against an empty character: nothing public means "remove owned content".
	real.characters[deps.characterKey] = nil
	local ok, result = pcall(Sync.RunFeature, deps, feature)
	real.characters[deps.characterKey] = saved
	if not ok then
		return nil, tostring(result)
	end
	if result.state == "written" or result.state == "noop" then
		entry[feature] = false
		return true, "Removed Dawnward's " .. spec.label .. " from Total RP 3 and switched sync off."
	end
	return nil, result.message
end

--- Restores the newest backup for the active profile (optionally one
-- section). The current state is backed up first, so a rollback can itself
-- be undone. Ownership records for the section are cleared and its feature
-- switched off.
function Sync.Rollback(deps, backupId)
	if deps.ledgerReadOnly then
		return nil, deps.ledgerReadOnly
	end
	local probe = Adapter.Probe(deps.env)
	local id = probe.profile and probe.profile.id
	if not id or probe.profile.isDefault then
		return nil, "no suitable Total RP 3 profile is active"
	end
	local backup = backupId and Ledger.FindBackup(deps.ledger, backupId) or Ledger.LatestBackup(deps.ledger, id)
	if not backup then
		return nil, "there is no Dawnward backup for this Total RP 3 profile"
	end
	if backup.profileId ~= id then
		return nil, "that backup belongs to another Total RP 3 profile; switch to it first"
	end
	if probe.editorOpen and probe.editorOpen[backup.section] ~= false then
		return nil, "close the Total RP 3 editor first"
	end
	local data, derr = Ledger.BackupData(backup)
	if not data then
		return nil, derr
	end
	local current, cerr = Adapter.ReadSection(deps.env, backup.section)
	if not current then
		return nil, cerr
	end
	local safety, serr = Ledger.AddBackup(deps.ledger, id, backup.section, current,
		{ reason = "before rollback to #" .. backup.id, characterKey = deps.characterKey }, deps.now())
	if not safety then
		return nil, serr
	end
	local version, werr = restore(deps, id, backup.section, data)
	if not version then
		return nil, werr
	end
	local record = Ledger.Profile(deps.ledger, id)
	for feature, spec in pairs(Sync.FEATURES) do
		if spec.section == backup.section then
			record[feature] = nil
			record.conflicts[feature] = nil
			disable(deps, feature)
		end
	end
	Ledger.Log(deps.ledger, deps.now(), "rollback: restored " .. backup.section .. " from backup #" .. backup.id)
	return true, string.format("Restored your Total RP 3 %s from backup #%d. The state before this rollback is "
		.. "backup #%d. Automatic sync for it is off.", backup.section, backup.id, safety.id)
end

--- Settles a conflict. "keep": the player's version stays and Dawnward
-- stops managing it (the feature is switched off). "reclaim": for the
-- biography, the edited text now belongs to the player and Dawnward adds a
-- fresh section of its own on the next sync (nothing the player wrote is
-- changed); for traits, Dawnward takes back the traits carrying its own
-- labels, at their current values, and updates them on the next sync.
function Sync.Resolve(deps, feature, choice)
	if not Sync.FEATURES[feature] then
		return nil, "unknown feature '" .. tostring(feature) .. "' (use about or traits)"
	end
	if choice ~= "keep" and choice ~= "reclaim" then
		return nil, "choose keep or reclaim"
	end
	local probe = Adapter.Probe(deps.env)
	local id = probe.profile and probe.profile.id
	local record = id and deps.ledger.profiles[id]
	if not record or not record.conflicts[feature] then
		return nil, "there is no conflict to resolve for this profile"
	end
	if choice == "keep" then
		record.conflicts[feature] = nil
		record[feature] = nil
		disable(deps, feature)
		return true, "Kept your version. Dawnward no longer manages it; sync is off."
	end
	if feature == "traits" then
		local section, err = Adapter.ReadSection(deps.env, "characteristics")
		if not section then
			return nil, err
		end
		local char = realCharacter(deps)
		local desired = TraitPlan.Desired(char and Projection.GetPublic(char) or {})
		local owned = {}
		for axisId, d in pairs(desired) do
			local matches = {}
			for _, trait in ipairs(section.PS or {}) do
				if trait.ID == nil and trait.LT == d.LT and trait.RT == d.RT then
					matches[#matches + 1] = trait
				end
			end
			if #matches > 1 then
				return nil, "the trait " .. d.LT .. "/" .. d.RT
					.. " appears more than once; remove the extra one in Total RP 3 first"
			elseif #matches == 1 and type(matches[1].V2) == "number" then
				owned[axisId] = { LT = d.LT, RT = d.RT, V2 = matches[1].V2 }
			end
		end
		record[feature] = next(owned) and { owned = owned, at = deps.now() } or nil
		record.conflicts[feature] = nil
		return true, "Dawnward manages its own traits again and will update them on the next sync."
	end
	record.conflicts[feature] = nil
	record[feature] = nil
	return true, "Your edited version is now yours. Dawnward will add a new section of its own on the next sync."
end
