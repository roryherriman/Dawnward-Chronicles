-- Keeps Dawnward-owned content in the player's TRP3 profile up to date.
--
-- Every run re-reads everything and re-checks every guard; nothing is
-- cached between runs. A write happens only when all of these hold:
--   * the player authorised the mapping ("dawnward" policy) for this
--     character, for this exact TRP3 profile ID (switching profile pauses)
--   * the TRP3 version is allowlisted and the adapter's capability checks pass
--   * the profile is not TRP3's default profile
--   * not in simulation mode, saved data is writable, not in combat
--   * no TRP3 editor holds a draft that would overwrite the change
--   * there is no unresolved conflict, and the plan is not a no-op
-- Then: back up the section, write only the owned change, read it back, and
-- restore the backup at once if anything differs (and stop managing it).
-- Unchanged content writes nothing, so versions never churn.
--
-- Features (one transaction each): "about" (Dawnward's biography block),
-- "traits" (Dawnward's personality traits), "fields" (every profile
-- field mapping the player handed to Dawnward, FieldPlan.lua) and, since
-- v0.9, "misc" (Dawnward's entries in TRP3's additional-information list,
-- MiscPlan.lua). A field or entry in conflict is paused on its own; the
-- others still update.
--
-- deps: { env, ledger, ledgerReadOnly?, store, characterKey, now(), inCombat() }
local _, ns = ...
local Util, Projection, Ledger, Adapter, AboutBlock, TraitPlan, FieldPlan, Presentation, VersionProfiles =
	ns.Util, ns.Projection, ns.TRP3Ledger, ns.TRP3Adapter, ns.TRP3AboutBlock, ns.TRP3TraitPlan, ns.TRP3FieldPlan,
	ns.TRP3Presentation, ns.TRP3VersionProfiles
local MiscPlan, AboutDoc = ns.TRP3MiscPlan, ns.TRP3AboutDoc


local Sync = {}
ns.TRP3Sync = Sync

-- Template numbers for the Total RP 3 layout preference (nil keeps TRP3's).
local LAYOUT_TEMPLATE = { text = 1, frames = 2, sections = 3 }

--- Whether the About page gets the full profile (AboutDoc) or the summary
-- block (AboutBlock), from the public projection's settings.
function Sync.UsesProfile(public)
	return public.trp3About == "profile" or (public.trp3About ~= "summary" and public.profileModel == true)
end

-- Plans the About page for one projection (the about feature's planner).
local function planAbout(section, record, public, extra)
	extra = extra or {}
	local upgraded = record and (record.slots ~= nil or record.frames ~= nil)
	if Sync.UsesProfile(public) or upgraded or extra.adopt then
		local doc = Sync.UsesProfile(public) and AboutDoc.Build(public) or {}
		if not Sync.UsesProfile(public) then
			-- The summary block as one section, without a heading of its own.
			local block = AboutBlock.Compose(public)
			if block ~= "" then doc = { { id = "notes", title = nil, body = block, raw = true } } end
		end
		return AboutDoc.Plan(section, record, doc, { template = LAYOUT_TEMPLATE[public.trp3Layout],
			style = public.trp3Style, adopt = extra.adopt })
	end
	return AboutBlock.Plan(section, record, AboutBlock.Compose(public))
end
Sync.PlanAbout = planAbout

Sync.FEATURES = {
	about = {
		section = "about",
		label = "biography",
		plan = function(section, record, public, extra)
			return planAbout(section, record, public, extra)
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
	fields = {
		section = "characteristics",
		label = "profile fields",
		plan = function(section, record, public, extra)
			local desired, unwritable = FieldPlan.Desired(public)
			return FieldPlan.Plan(section, record, desired, extra.policies, extra.paused, unwritable,
				{ defaults = extra.defaults, adopt = extra.adopt })
		end,
		planned = "characteristics",
	},
	misc = {
		section = "characteristics",
		label = "additional information",
		plan = function(section, record, public, extra)
			local desired, unwritable = MiscPlan.Desired(public)
			return MiscPlan.Plan(section, record, desired, extra.policies, extra.paused, unwritable,
				{ names = extra.names, adopt = extra.adopt })
		end,
		planned = "characteristics",
	},
}
Sync.ORDER = { "about", "traits", "fields", "misc" }

-- The features stored in one TRP3 section (a backup covers all of them).
local SECTION_FEATURES = { about = { "about" }, characteristics = { "traits", "fields", "misc" } }
Sync.SECTION_FEATURES = SECTION_FEATURES

-- Features made of per-item mappings (one policy and one conflict per
-- field or entry), and the planner that knows their mappings.
local ROW_FEATURES = { fields = FieldPlan, misc = MiscPlan }
Sync.ROW_FEATURES = ROW_FEATURES

--- The mapping for an item id, and the row feature it belongs to.
local function mappingOf(id)
	if FieldPlan.BY_ID[id] then
		return FieldPlan.BY_ID[id], "fields"
	elseif MiscPlan.BY_ID[id] then
		return MiscPlan.BY_ID[id], "misc"
	end
	return nil
end
Sync.MappingOf = mappingOf

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

--- Whether Dawnward manages a feature for this opt-in entry.
function Sync.FeatureOn(entry, feature)
	if feature == "fields" then
		return entry ~= nil and Ledger.AnyFieldManaged(entry)
	elseif feature == "misc" then
		return entry ~= nil and Ledger.AnyMiscManaged(entry)
	end
	return Ledger.Policy(entry, feature) == "dawnward"
end
local featureOn = Sync.FeatureOn

-- Stops Dawnward managing a feature for every character opted in on this
-- profile, so "stop managing it" holds even when characters share a
-- profile. Biography and traits switch off; managed fields go back to Total
-- RP 3 (only the given ids, or all of them).
local function disableForProfile(deps, profileId, feature, fieldIds)
	local record = deps.ledger.profiles[profileId]
	local rowPlan = ROW_FEATURES[feature]
	if rowPlan and record and record.fieldConflicts then
		for id in pairs(record.fieldConflicts) do
			if not fieldIds or fieldIds[id] then
				record.fieldConflicts[id] = nil
			end
		end
	end
	for _, entry in pairs(deps.ledger.optIn) do
		if entry.profileId == profileId then
			if rowPlan then
				for _, m in ipairs(rowPlan.MAPPINGS) do
					if (not fieldIds or fieldIds[m.id]) and Ledger.Policy(entry, m.id) == "dawnward" then
						Ledger.SetPolicy(entry, m.id, "trp3")
					end
				end
			else
				Ledger.SetPolicy(entry, feature, "off")
			end
		end
	end
end

--- Copies the presentation settings a plan reads onto a projection: the
-- style, the About layout and template, and whether the character uses the
-- profile publication model (all cosmetic; no character data).
function Sync.ApplySettings(public, char)
	local prefs = char and char.story and char.story.prefs or {}
	public.trp3Style = prefs.trp3Style
	public.trp3About = prefs.trp3About or "auto"
	public.trp3Layout = prefs.trp3Layout or "current"
	public.profileModel = ns.Privacy.ProfileModel(char)
	return public
end

-- The public projection and the cosmetic settings a plan reads.
local function publicOf(deps)
	local char = realCharacter(deps)
	local public = (char and Projection.GetPublic(char)) or { facts = {}, personality = {}, fields = {} }
	Sync.ApplySettings(public, char)
	return public
end
Sync.PublicOf = publicOf

-- Reads made while building one read-only view (the Total RP 3 page) share
-- one probe and one read per section: deps.cache is set only by such
-- callers (TRP3Commands.Overview); a run that writes never has it, so every
-- write decision re-reads everything.
local function probeOf(deps)
	local cache = deps.cache
	if not cache then
		return Adapter.Probe(deps.env)
	end
	cache.probe = cache.probe or Adapter.Probe(deps.env)
	return cache.probe
end
Sync.ProbeOf = probeOf

local function readSection(deps, section)
	local cache = deps.cache
	if not cache then
		return Adapter.ReadSection(deps.env, section)
	end
	cache.sections = cache.sections or {}
	local hit = cache.sections[section]
	if not hit then
		local data, err = Adapter.ReadSection(deps.env, section)
		hit = { data = data, err = err }
		cache.sections[section] = hit
	end
	if not hit.data then
		return nil, hit.err
	end
	return Util.DeepCopy(hit.data)
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
	local probe = probeOf(deps)
	for _, r in ipairs(probe.experimental.reasons) do
		reasons[#reasons + 1] = r
	end
	local entry = optIn(deps)
	if not featureOn(entry, feature) then
		reasons[#reasons + 1] = "automatic " .. Sync.FEATURES[feature].label .. " sync is off for this character"
	elseif probe.profile and probe.profile.id ~= entry.profileId then
		reasons[#reasons + 1] = "the active Total RP 3 profile is not the one sync was enabled for"
	end
	if #reasons == 0 then
		local section = Sync.FEATURES[feature].section
		if probe.editorOpen[section] then
			reasons[#reasons + 1] = "the Total RP 3 editor holds unsaved changes to this section; save or cancel "
				.. "it in Total RP 3 and Dawnward will try again"
			deferred = true
		elseif deps.inCombat and deps.inCombat() then
			reasons[#reasons + 1] = "in combat; Dawnward will try again later"
			deferred = true
		end
	end
	return probe, reasons, deferred
end

-- The ownership policies a fields plan uses: the entry's, or every field
-- "dawnward" when planning a release (remove everything Dawnward owns).
local function fieldPolicies(entry)
	local out = {}
	for _, plan in pairs(ROW_FEATURES) do
		for _, m in ipairs(plan.MAPPINGS) do
			out[m.id] = Ledger.Policy(entry, m.id)
		end
	end
	return out
end

--- Works out what a run would do, without writing anything.
-- Returns { feature, state, reasons, plan, section, probe, profileId } where
-- state is "off", "blocked", "deferred", "conflict", "noop" or "ready".
-- publicOverride replaces the character's public projection (Release uses
-- an empty one to plan "remove Dawnward's content"). fieldScope ({ [id] =
-- true }) limits a fields plan to those fields (releasing one field).
-- result.notes lists fields Dawnward cannot write unchanged.
function Sync.Check(deps, feature, publicOverride, fieldScope)
	local spec = Sync.FEATURES[feature]
	local result = { feature = feature, reasons = {} }
	local probe, reasons, deferred = guards(deps, feature)
	result.probe = probe
	result.reasons = reasons
	local entry = optIn(deps)
	if #reasons > 0 then
		result.state = deferred and "deferred" or (not featureOn(entry, feature) and "off" or "blocked")
		return result
	end
	local profileId = probe.profile.id
	result.profileId = profileId
	local record = Ledger.Profile(deps.ledger, profileId)
	if not record then
		result.state = "blocked"
		result.reasons = { "the active Total RP 3 profile ID is not one Dawnward can track" }
		return result
	end
	if record.conflicts[feature] then
		result.state = "conflict"
		result.reasons = { record.conflicts[feature] }
		return result
	end
	local public = publicOverride or publicOf(deps)
	if publicOverride then
		Sync.ApplySettings(public, realCharacter(deps))
	end
	local section, err = readSection(deps, spec.section)
	if not section then
		result.state = "blocked"
		result.reasons = { err }
		return result
	end
	result.section = Util.DeepCopy(section)
	local policies = fieldPolicies(entry)
	if fieldScope then
		for id in pairs(policies) do
			if not fieldScope[id] then policies[id] = "off" end
		end
	end
	-- The one-time takeover ("Replace it with Dawnward's", v0.9 setup) for
	-- this feature, and what Total RP 3 filled in by itself.
	local adopt = entry and entry.adopt and entry.adopt[feature] == true or nil
	local plan = spec.plan(section, record[feature], public,
		{ policies = policies, paused = record.fieldConflicts, adopt = adopt,
			defaults = FieldPlan.GameDefaults(deps.env), names = MiscPlan.PresetNames(deps.env) })
	result.plan = plan
	result.adopt = adopt
	result.notes = {}
	if ROW_FEATURES[feature] then
		for _, row in ipairs(plan.rows) do
			if row.state == "conflict" then
				result.reasons[#result.reasons + 1] = row.reason
			elseif row.state == "unwritable" then
				result.notes[#result.notes + 1] = row.reason
			end
		end
		result.state = plan.action == "write" and "ready" or (#result.reasons > 0 and "conflict" or "noop")
	elseif plan.action == "conflict" or plan.action == "unsupported" then
		result.state = plan.action == "conflict" and "conflict" or "blocked"
		result.reasons = { plan.reason }
	elseif plan.action == "noop" then
		result.state = "noop"
	else
		result.state = "ready"
	end
	return result
end

--- Restores a section from backup data through the experimental driver.
-- Returns ok, note: ok when the data is back in place (note says if TRP3
-- could not be told about it).
local function restore(deps, profileId, sectionName, data)
	local version, err, notifyErr = Adapter.WriteSection(deps.env, sectionName, data, profileId)
	if not version then
		return nil, err
	end
	return true, notifyErr
end

-- Ownership records of every feature stored in a section, for a backup.
local function ownersOf(record, sectionName)
	local owners = {}
	for _, feature in ipairs(SECTION_FEATURES[sectionName]) do
		owners[feature] = record[feature]
	end
	return owners
end

-- Records new per-field conflicts (each logged once).
local function pauseFields(deps, record, conflicts, now)
	local added = {}
	for id, reason in pairs(conflicts or {}) do
		if not record.fieldConflicts[id] then
			record.fieldConflicts[id] = reason
			added[#added + 1] = reason
			Ledger.Log(deps.ledger, now, "fields: " .. id .. ": conflict: " .. reason)
		end
	end
	table.sort(added)
	return added
end

--- Runs one feature. Returns { feature, state, message } where state is one
-- of the Check states, or "written", "failed" (rolled back).
function Sync.RunFeature(deps, feature, publicOverride, fieldScope)
	local spec = Sync.FEATURES[feature]
	local check = Sync.Check(deps, feature, publicOverride, fieldScope)
	local now = deps.now()
	local fieldNote = ""
	if ROW_FEATURES[feature] and check.plan then
		local added = pauseFields(deps, Ledger.Profile(deps.ledger, check.profileId), check.plan.conflicts, now)
		if #added > 0 then
			fieldNote = " Paused (your version is kept): " .. table.concat(added, "; ") .. "."
		end
	end
	if check.state == "conflict" then
		if ROW_FEATURES[feature] then
			return { feature = feature, state = "conflict", message = "Total RP 3 " .. spec.label .. " sync paused: "
				.. table.concat(check.reasons, "; ") .. ". Your version is kept. Choose on the Total RP 3 page, or "
				.. "/dawnward trp3 resolve <field> keep|reclaim." }
		end
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
	local profileRecord = Ledger.Profile(deps.ledger, profileId)
	local backup, berr = Ledger.AddBackup(deps.ledger, profileId, spec.section, check.section,
		{ reason = "before " .. check.plan.action .. " " .. feature, characterKey = deps.characterKey,
			ownerFeature = feature, owner = profileRecord[feature],
			owners = ownersOf(profileRecord, spec.section) }, now)
	if not backup then
		Ledger.Log(deps.ledger, now, feature .. ": not written: " .. tostring(berr))
		return { feature = feature, state = "blocked", message = berr }
	end

	local planned = check.plan[spec.planned]
	local version, werr, notifyErr = Adapter.WriteSection(deps.env, spec.section, planned, profileId)
	local readBack = version and Adapter.ReadSection(deps.env, spec.section)
	local expected = Util.DeepCopy(planned)
	expected.v = version
	if not version or notifyErr or not readBack or not deepEqual(readBack, expected) then
		local why = werr or notifyErr or "the profile did not read back as written"
		local restored, rnote = restore(deps, profileId, spec.section, check.section)
		disableForProfile(deps, profileId, feature)
		Ledger.Log(deps.ledger, now, feature .. ": write failed (" .. why .. "); "
			.. (restored and ("restored backup #" .. backup.id .. (rnote and " (TRP3 not notified)" or ""))
				or "RESTORE FAILED, use /dawnward trp3 rollback"))
		return { feature = feature, state = "failed", message = "Total RP 3 " .. spec.label .. " update failed ("
			.. why .. "). " .. (restored and "Your profile was restored from the backup"
				or "Restoring failed: run /dawnward trp3 rollback confirm")
			.. " and automatic sync was switched off." }
	end

	if check.plan.record then
		profileRecord[feature] = Util.DeepCopy(check.plan.record)
		if not ROW_FEATURES[feature] then
			profileRecord[feature].at = now
		end
	else
		profileRecord[feature] = nil
	end
	-- The one-time takeover is used up by the first successful write.
	local entry = optIn(deps)
	if check.adopt and entry and entry.adopt then
		entry.adopt[feature] = nil
		if not next(entry.adopt) then entry.adopt = nil end
	end
	Ledger.Log(deps.ledger, now, feature .. ": " .. check.plan.action
		.. (check.plan.changes and #check.plan.changes > 0 and (" " .. table.concat(check.plan.changes, ", ")) or "")
		.. " (version " .. version .. ", backup #" .. backup.id .. ")")
	return { feature = feature, state = "written", message = "Updated your Total RP 3 " .. spec.label
		.. " (" .. ((ROW_FEATURES[feature] and table.concat(check.plan.changes, ", ")) or check.plan.action)
		.. "). Other players see it the next time their Total RP 3 checks your profile." .. fieldNote }
end

--- Runs every feature Dawnward manages. Returns a list of RunFeature results.
function Sync.Run(deps)
	local results = {}
	for _, feature in ipairs(Sync.ORDER) do
		if featureOn(optIn(deps), feature) then
			results[#results + 1] = Sync.RunFeature(deps, feature)
		end
	end
	return results
end

local POLICY_LABEL = { dawnward = "Managed by Dawnward", trp3 = "Managed by Total RP 3", off = "Not synchronised" }
Sync.POLICY_LABEL = POLICY_LABEL

--- Label of a mapping id ("biography", "Race", ...).
function Sync.MappingLabel(id)
	if Sync.FEATURES[id] then
		return Sync.FEATURES[id].label
	end
	local m = mappingOf(id)
	return m and m.label or tostring(id)
end

--- Sets one mapping's ownership policy for this character, bound to the
-- active profile. "dawnward" is the authorisation to write automatically:
-- it needs every write capability, an exact storable profile and no other
-- character managing the same mapping on that profile. Leaving "dawnward"
-- for a field forgets Dawnward's ownership of it (Total RP 3 keeps the
-- value); for the biography and traits, content Dawnward wrote stays until
-- released. Returns ok, message.
--- When a field leaves Dawnward's management: Total RP 3 still shows the
-- exact value Dawnward wrote, but that value is no longer Dawnward's Public
-- value (made Private or Secret, cleared, or changed). Forgetting ownership
-- then would leave it published for good. Returns { value, reason } or nil.
function Sync.FieldRisk(deps, id)
	local m, feature = mappingOf(id)
	local entry = optIn(deps)
	if not m or not entry then
		return nil
	end
	local record = deps.ledger.profiles[entry.profileId]
	local owned = record and record[feature] and record[feature][id]
	if not owned then
		return nil
	end
	local probe = probeOf(deps)
	if not probe.profile or probe.profile.id ~= entry.profileId then
		return nil
	end
	local section = readSection(deps, "characteristics")
	if not section then
		return nil
	end
	if feature == "fields" then
		if section[m.key] ~= owned.value then
			return nil
		end
	elseif not MiscPlan.WithoutOwned(section, { [id] = owned }) then
		return nil
	end
	local char = realCharacter(deps)
	local stored = char and char.fields[m.source]
	if stored and stored.visibility == "public" and stored.value == owned.value then
		return nil
	end
	return { value = owned.value, reason = "Total RP 3 still shows \"" .. tostring(FieldPlan.Display(m, owned.value))
		.. "\" as your " .. m.trp3
		.. ", which Dawnward wrote but which is no longer your Public " .. m.label }
end

--- Removes Dawnward's value of one field from Total RP 3 (a guarded,
-- backed-up write), without changing its policy. Returns ok, message.
function Sync.ReleaseField(deps, id)
	local m, feature = mappingOf(id)
	if not m then
		return nil, "unknown field"
	end
	local public = publicOf(deps)
	public.fields = Util.DeepCopy(public.fields or {})
	public.fields[m.source] = nil
	local result = Sync.RunFeature(deps, feature, public, { [id] = true })
	if result.state == "written" or result.state == "noop" then
		return true, "Removed Dawnward's " .. m.trp3 .. " from Total RP 3."
	end
	return nil, "Dawnward's " .. m.trp3 .. " could not be removed now (" .. tostring(result.message) .. ")"
end

--- Sets one mapping's policy. opts.release (a field leaving "dawnward"):
-- remove Dawnward's value from Total RP 3 first. When FieldRisk applies,
-- the change is refused unless opts.release or opts.keep says what to do
-- with the value still shown. Returns ok, message (or nil, message, risk).
function Sync.SetPolicy(deps, id, policy, opts)
	opts = opts or {}
	if mappingOf(id) and policy ~= "dawnward" and Ledger.POLICIES[policy] and not deps.ledgerReadOnly then
		local risk = Sync.FieldRisk(deps, id)
		if risk then
			if opts.release then
				local ok, err = Sync.ReleaseField(deps, id)
				if not ok then
					return nil, err
				end
			elseif not opts.keep then
				return nil, risk.reason .. ". Remove it first (release), or keep it showing.", risk
			end
		end
	end
	return Sync.ApplyPolicy(deps, id, policy)
end

--- Saves a policy without the FieldRisk check (see SetPolicy).
function Sync.ApplyPolicy(deps, id, policy)
	if not Ledger.MAPPING_SET[id] then
		return nil, "unknown mapping '" .. tostring(id) .. "'"
	end
	if not Ledger.POLICIES[policy] then
		return nil, "choose dawnward, trp3 or off"
	end
	if deps.ledgerReadOnly then
		return nil, deps.ledgerReadOnly
	end
	local entry = optIn(deps)
	local label = Sync.MappingLabel(id)
	if policy ~= "dawnward" then
		local probe = probeOf(deps)
		local activeId = probe.profile and probe.profile.id
		local offMessage = "Automatic " .. label .. " sync is off. Content Dawnward already wrote "
			.. "stays until you run /dawnward trp3 release " .. id .. " confirm."
		if not entry then
			if Ledger.Policy(nil, id) == policy then
				return true, Ledger.BLOCK_FEATURES[id] and offMessage
					or (label .. ": " .. POLICY_LABEL[policy] .. " (unchanged).")
			end
			if not Ledger.IsStorableProfileId(activeId) or (probe.profile and probe.profile.isDefault) then
				return nil, "link a non-default Total RP 3 profile first"
			end
			entry = { about = false, traits = false, profileId = activeId, policy = {} }
			deps.ledger.optIn[deps.characterKey] = entry
		end
		Ledger.SetPolicy(entry, id, policy)
		local _, rowFeature = mappingOf(id)
		if rowFeature then
			local record = deps.ledger.profiles[entry.profileId]
			if record then
				if record[rowFeature] then
					record[rowFeature][id] = nil
					if not next(record[rowFeature]) then record[rowFeature] = nil end
				end
				if record.fieldConflicts then record.fieldConflicts[id] = nil end
			end
			return true, label .. ": " .. POLICY_LABEL[policy] .. ". Dawnward will not write it; Total RP 3 keeps "
				.. "its current value."
		end
		return true, offMessage
	end
	local probe = probeOf(deps)
	if not probe.experimental.allowed then
		return nil, table.concat(probe.experimental.reasons, "; ")
	end
	local profileId = probe.profile.id
	if not Ledger.IsStorableProfileId(profileId) then
		return nil, "the active Total RP 3 profile ID is not one Dawnward can track"
	end
	-- One character per profile and mapping: two characters writing to one
	-- shared profile would keep replacing each other's content.
	for key, other in pairs(deps.ledger.optIn) do
		if key ~= deps.characterKey and other.profileId == profileId and Ledger.Policy(other, id) == "dawnward" then
			return nil, "this Total RP 3 profile is already synced by " .. key .. " (" .. label
				.. "); turn it off there first"
		end
	end
	if not entry or entry.profileId ~= profileId then
		entry = { about = false, traits = false, profileId = profileId, policy = {} }
		deps.ledger.optIn[deps.characterKey] = entry
	end
	Ledger.SetPolicy(entry, id, "dawnward")
	entry.at = deps.now()
	-- A re-authorised field starts unpaused; if it still conflicts, the next
	-- plan pauses it again.
	local record = deps.ledger.profiles[profileId]
	if record and record.fieldConflicts then
		record.fieldConflicts[id] = nil
	end
	local shared = probe.profile.sharedWith
	return true, string.format("EXPERIMENTAL automatic %s sync is ON for Total RP 3 profile '%s'.%s "
		.. "Dawnward backs up the section before every write; undo with /dawnward trp3 rollback confirm.",
		label, tostring(probe.profile.name),
		(shared and shared > 0) and (" This profile is shared with " .. shared
			.. " other character(s); they will show the same content.") or "")
end

--- Turns the biography or traits feature on (bound to the active profile)
-- or off. Same as SetPolicy "dawnward" / "off".
function Sync.SetOptIn(deps, feature, on)
	if feature ~= "about" and feature ~= "traits" then
		return nil, "unknown feature '" .. tostring(feature) .. "' (use about or traits)"
	end
	return Sync.SetPolicy(deps, feature, on and "dawnward" or "off")
end

--- Applies several policies at once (the first-time connection's
-- "Authorize"). Every "dawnward" choice is checked before anything is
-- saved, so a refusal changes nothing. opts.adopt (v0.9 setup, "Replace it
-- with Dawnward's"): where Total RP 3 already holds the player's own
-- content, the first write of each managed feature may take it over (after
-- a pinned backup) instead of pausing; recorded as entry.adopt and used
-- once per feature. Returns ok, message.
function Sync.Authorize(deps, choices, opts)
	local ids = {}
	for _, id in ipairs(Ledger.MAPPINGS) do
		if choices[id] ~= nil then
			if not Ledger.POLICIES[choices[id]] then
				return nil, "unknown policy for " .. id
			end
			ids[#ids + 1] = id
		end
	end
	if #ids == 0 then
		return nil, "nothing was chosen"
	end
	if deps.ledgerReadOnly then
		return nil, deps.ledgerReadOnly
	end
	-- 1. Validate everything before anything is saved.
	local probe = probeOf(deps)
	local profileId = probe.profile and probe.profile.id
	local linkable = Ledger.IsStorableProfileId(profileId) and not probe.profile.isDefault
	local entry = optIn(deps)
	local releases = {}
	for _, id in ipairs(ids) do
		local policy = choices[id]
		if policy == "dawnward" then
			if not probe.experimental.allowed then
				return nil, table.concat(probe.experimental.reasons, "; ") .. "; nothing was changed"
			end
			if not linkable then
				return nil, "the active Total RP 3 profile ID is not one Dawnward can track; nothing was changed"
			end
			for key, other in pairs(deps.ledger.optIn) do
				if key ~= deps.characterKey and other.profileId == profileId
					and Ledger.Policy(other, id) == "dawnward" then
					return nil, "this Total RP 3 profile is already synced by " .. key .. " ("
						.. Sync.MappingLabel(id) .. "); nothing was changed"
				end
			end
		elseif not entry and Ledger.Policy(nil, id) ~= policy and not linkable then
			return nil, "link a non-default Total RP 3 profile first; nothing was changed"
		elseif Sync.FieldRisk(deps, id) then
			releases[#releases + 1] = id
		end
	end
	-- 2. Values no longer Public are removed from Total RP 3 first (guarded,
	-- backed-up writes, which must happen while the field is still
	-- Dawnward's); if one cannot be removed now, no policy is saved.
	for _, id in ipairs(releases) do
		local released, rerr = Sync.ReleaseField(deps, id)
		if not released then
			return nil, rerr .. "; no choice was saved"
		end
	end
	-- 3. Apply on a snapshot; any failure puts the ledger back as it was.
	local key = deps.characterKey
	local savedEntry = Util.DeepCopy(deps.ledger.optIn[key])
	local savedRecord = profileId and Util.DeepCopy(deps.ledger.profiles[profileId])
	local function undo()
		deps.ledger.optIn[key] = savedEntry
		if profileId then deps.ledger.profiles[profileId] = savedRecord end
	end
	local managed = {}
	local ok, err = pcall(function()
		for _, id in ipairs(ids) do
			local done, why = Sync.ApplyPolicy(deps, id, choices[id])
			if not done then
				error(why, 0)
			end
			if choices[id] == "dawnward" then
				managed[#managed + 1] = Sync.MappingLabel(id)
			end
		end
	end)
	if not ok then
		undo()
		return nil, tostring(err) .. "; nothing was changed"
	end
	local saved = deps.ledger.optIn[key]
	if saved and opts and opts.adopt then
		saved.adopt = { about = true, traits = true, fields = true }
	end
	if #managed == 0 then
		return true, "Saved. Dawnward manages nothing in Total RP 3 for this character."
	end
	return true, "Authorised: Dawnward now keeps " .. table.concat(managed, ", ") .. " up to date in Total RP 3 '"
		.. tostring(probe.profile and probe.profile.name) .. "' from your Dawnward character. Undo any write with "
		.. "a rollback."
end

--- Removes Dawnward's owned content for a feature, then turns it off.
function Sync.Release(deps, feature)
	local spec = Sync.FEATURES[feature]
	if not spec then
		return nil, "unknown feature"
	end
	local entry = optIn(deps)
	if not featureOn(entry, feature) then
		return nil, "turn sync on first (it is needed to write); then release"
	end
	-- Plan against an empty projection: nothing public means "remove owned content".
	local result = Sync.RunFeature(deps, feature, { facts = {}, personality = {}, fields = {} })
	if result.state == "written" or result.state == "noop" then
		disableForProfile(deps, entry.profileId, feature)
		return true, "Removed Dawnward's " .. spec.label .. " from Total RP 3 and switched sync off."
	end
	return nil, result.message
end

--- Read-only comparison of every field mapping that is not "off": what
-- Total RP 3 holds against Dawnward's PUBLIC value. A Dawnward value that is
-- not Public is never shown (only flagged). Returns { rows, reason } where
-- rows[i] = { id, label, trp3Label, policy, trp3, dawnward, hidden, differ,
-- importable, conflict }.
function Sync.Differences(deps)
	local view = { rows = {} }
	local status = probeOf(deps)
	if not status.status.loaded then
		view.reason = "Total RP 3 is not loaded"
		return view
	end
	if not VersionProfiles.Get(status.status.version).audited then
		view.reason = "this Total RP 3 version has not been audited, so Dawnward does not read its profile"
		return view
	end
	local section, err = readSection(deps, "characteristics")
	if not section then
		view.reason = err
		return view
	end
	local entry = optIn(deps)
	local profileId = status.profile and status.profile.id
	local bound = entry and entry.profileId == profileId
	local record = profileId and deps.ledger.profiles[profileId]
	local char = realCharacter(deps)
	local public, unwritable = FieldPlan.Desired(publicOf(deps))
	for _, m in ipairs(FieldPlan.MAPPINGS) do
		local policy = Ledger.Policy(bound and entry or nil, m.id)
		if policy ~= "off" then
			-- Shown as the player reads them (a relationship number as its word).
			local trp3 = FieldPlan.Display(m, section[m.key])
			trp3 = type(trp3) == "string" and trp3 ~= "" and trp3 or nil
			local stored = char and char.fields[m.source]
			local row = { id = m.id, label = m.label, trp3Label = m.trp3, policy = policy, trp3 = trp3,
				dawnward = FieldPlan.Display(m, public[m.id]), hidden = stored ~= nil and stored.visibility ~= "public",
				conflict = policy == "dawnward" and record and record.fieldConflicts
					and record.fieldConflicts[m.id] or nil,
				unwritable = unwritable[m.id] }
			row.differ = row.trp3 ~= row.dawnward
			-- Importing TRP3's value is useful only when it differs from what
			-- Dawnward holds (Public or not); the value itself is not shown
			-- when the Dawnward side is hidden.
			row.importable = trp3 ~= nil and (stored == nil or stored.value ~= trp3)
			view.rows[#view.rows + 1] = row
		end
	end
	-- Additional-information entries (v0.9): the same comparison, never
	-- importable (Total RP 3 holds them as a list, not one field).
	local misc, miscUnwritable = MiscPlan.Desired(publicOf(deps))
	for _, m in ipairs(MiscPlan.MAPPINGS) do
		local policy = Ledger.Policy(bound and entry or nil, m.id)
		if policy ~= "off" then
			local found = MiscPlan.Find(section, m)
			local trp3 = found[1] and type(found[1].value) == "string" and found[1].value ~= "" and found[1].value or nil
			local stored = char and char.fields[m.source]
			local row = { id = m.id, label = m.label, trp3Label = m.trp3, policy = policy, trp3 = trp3,
				dawnward = misc[m.id], hidden = stored ~= nil and stored.visibility ~= "public",
				conflict = policy == "dawnward" and record and record.fieldConflicts
					and record.fieldConflicts[m.id] or nil,
				unwritable = miscUnwritable[m.id], importable = false }
			row.differ = row.trp3 ~= row.dawnward
			view.rows[#view.rows + 1] = row
		end
	end
	return view
end

--- Rollback -------------------------------------------------------------------

-- Lines of every style of the current public block (a style change alone
-- must not make old lines look private).
local function currentBlockLines(public)
	local lines = {}
	local function addLines(text)
		for line in (text .. "\n"):gmatch("([^\n]*)\n") do
			lines[line] = true
		end
	end
	local doc = AboutDoc.Build(public)
	for id in pairs(Presentation.STYLES) do
		local copy = Util.DeepCopy(public)
		copy.trp3Style = id
		addLines(AboutBlock.Compose(copy))
		for template = 1, 3 do
			local rendered = AboutDoc.Render(doc, template, id)
			for _, text in pairs({ rendered.T1 or "", rendered.PH or "", rendered.PS or "", rendered.HI or "" }) do
				addLines(text)
			end
			for _, frame in ipairs(rendered.frames or {}) do addLines(frame.TX) end
		end
	end
	return lines
end

-- Headings Dawnward adds (never content of their own).
local function isHeading(line)
	return line == "" or line:find("^{h%d") ~= nil or line:find("^%(%d+ more in the") ~= nil
end

local function backupOwners(backup)
	local owners = Util.DeepCopy(backup.owners) or {}
	if backup.ownerFeature and owners[backup.ownerFeature] == nil then
		owners[backup.ownerFeature] = Util.DeepCopy(backup.owner)
	end
	return owners
end

--- What restoring a backup exactly would bring back that is NOT Public in
-- Dawnward now: lines of Dawnward's old biography block, personality axes
-- and field values. Pure read; writes nothing. Returns { backup, items,
-- ownPossible, ownReason } or nil plus a reason.
function Sync.RollbackPreview(deps, backupId)
	local probe = probeOf(deps)
	local id = probe.profile and probe.profile.id
	local backup = backupId and Ledger.FindBackup(deps.ledger, backupId) or Ledger.LatestBackup(deps.ledger, id)
	if not backup then
		return nil, "there is no Dawnward backup for this Total RP 3 profile"
	end
	local data, derr = Ledger.BackupData(backup)
	if not data then
		return nil, derr
	end
	local owners = backupOwners(backup)
	local public = publicOf(deps)
	local items = {}
	if backup.section == "about" and owners.about then
		local now = currentBlockLines(public)
		for line in (AboutDoc.OwnedText(owners.about) .. "\n"):gmatch("([^\n]*)\n") do
			if not isHeading(line) and not now[line] then
				items[#items + 1] = "Biography line: " .. line
			end
		end
	end
	if owners.traits then
		local desired = TraitPlan.Desired(public)
		local axes = {}
		for axisId in pairs(owners.traits.owned or {}) do axes[#axes + 1] = axisId end
		table.sort(axes)
		for _, axisId in ipairs(axes) do
			local o = owners.traits.owned[axisId]
			local d = desired[axisId]
			if not d or d.V2 ~= o.V2 then
				items[#items + 1] = string.format("Personality: %s %d / %d %s", o.LT, o.V2, 20 - o.V2, o.RT)
			end
		end
	end
	if owners.fields then
		local desired = FieldPlan.Desired(public)
		for _, m in ipairs(FieldPlan.MAPPINGS) do
			local o = owners.fields[m.id]
			if o and desired[m.id] ~= o.value then
				items[#items + 1] = m.label .. ": " .. o.value
			end
		end
	end
	if owners.misc then
		local desired = MiscPlan.Desired(public)
		for _, m in ipairs(MiscPlan.MAPPINGS) do
			local o = owners.misc[m.id]
			if o and desired[m.id] ~= o.value then
				items[#items + 1] = m.label .. ": " .. o.value
			end
		end
	end
	local preview = { backup = backup, items = items, ownPossible = true }
	-- "Your own text only" needs Dawnward's old part to be separable.
	if backup.section == "about" then
		if owners.about then
			local ok, why = AboutDoc.Strip(data, owners.about)
			if not ok then
				preview.ownPossible, preview.ownReason = false, why
			end
		end
	else
		if owners.traits then
			local plan = TraitPlan.Plan(Util.DeepCopy(data), owners.traits, {})
			if plan.action == "conflict" then
				preview.ownPossible, preview.ownReason = false, plan.reason
			end
		end
		if preview.ownPossible and owners.fields then
			local ok, why = FieldPlan.WithoutOwned(data, owners.fields)
			if not ok then
				preview.ownPossible, preview.ownReason = false, why
			end
		end
		if preview.ownPossible and owners.misc then
			local ok, why = MiscPlan.WithoutOwned(data, owners.misc)
			if not ok then
				preview.ownPossible, preview.ownReason = false, why
			end
		end
	end
	return preview
end

-- Shared guards for a rollback. Returns probe, backup, data, current or nil plus a reason.
local function rollbackInputs(deps, backupId)
	if deps.ledgerReadOnly then
		return nil, deps.ledgerReadOnly
	end
	if deps.store:IsSimulation() then
		return nil, "turn simulation mode off first"
	end
	local probe = Adapter.Probe(deps.env)
	if not probe.experimental.allowed then
		return nil, table.concat(probe.experimental.reasons, "; ")
	end
	if deps.inCombat and deps.inCombat() then
		return nil, "wait until you are out of combat"
	end
	local id = probe.profile.id
	local backup = backupId and Ledger.FindBackup(deps.ledger, backupId) or Ledger.LatestBackup(deps.ledger, id)
	if not backup then
		return nil, "there is no Dawnward backup for this Total RP 3 profile"
	end
	if backup.profileId ~= id then
		return nil, "that backup belongs to another Total RP 3 profile; switch to it first"
	end
	if probe.editorOpen[backup.section] ~= false then
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
	return { probe = probe, backup = backup, data = data, current = current, profileId = id }
end

-- "Your own text only": the backup without Dawnward's old part, plus
-- Dawnward's part planned afresh from current public data for the features
-- Dawnward manages now. Returns data, owners, conflicts or nil plus a reason.
local function ownOnly(deps, inputs)
	local backup, owners = inputs.backup, backupOwners(inputs.backup)
	local entry = optIn(deps)
	if entry and entry.profileId ~= inputs.profileId then
		entry = nil
	end
	local public = publicOf(deps)
	local data = Util.DeepCopy(inputs.data)
	local newOwners, conflicts = {}, nil
	if backup.section == "about" then
		if owners.about then
			local stripped, why = AboutDoc.Strip(data, owners.about)
			if not stripped then
				return nil, "Dawnward's part of that backup cannot be separated (" .. tostring(why) .. ")"
			end
			data = stripped
		end
		if featureOn(entry, "about") then
			local plan = planAbout(data, nil, public)
			if plan.action ~= "conflict" and plan.action ~= "unsupported" then
				data, newOwners.about = plan.about, plan.record
			end
		end
		return data, newOwners
	end
	if owners.traits then
		local plan = TraitPlan.Plan(data, owners.traits, {})
		if plan.action == "conflict" then
			return nil, "Dawnward's traits in that backup cannot be separated (" .. tostring(plan.reason) .. ")"
		end
		data = plan.characteristics
	end
	if owners.fields then
		local stripped, why = FieldPlan.WithoutOwned(data, owners.fields)
		if not stripped then
			return nil, "Dawnward's fields in that backup cannot be separated (" .. why .. ")"
		end
		data = stripped
	end
	if owners.misc then
		local stripped, why = MiscPlan.WithoutOwned(data, owners.misc)
		if not stripped then
			return nil, "Dawnward's additional information in that backup cannot be separated (" .. why .. ")"
		end
		data = stripped
	end
	if featureOn(entry, "traits") then
		local plan = TraitPlan.Plan(data, nil, TraitPlan.Desired(public))
		if plan.action ~= "conflict" then
			data, newOwners.traits = plan.characteristics, plan.record
		end
	end
	if featureOn(entry, "fields") then
		local desired, unwritable = FieldPlan.Desired(public)
		local plan = FieldPlan.Plan(data, nil, desired, fieldPolicies(entry), {}, unwritable,
			{ defaults = FieldPlan.GameDefaults(deps.env) })
		data, newOwners.fields, conflicts = plan.characteristics, plan.record, plan.conflicts
	end
	if featureOn(entry, "misc") then
		local desired, unwritable = MiscPlan.Desired(public)
		local plan = MiscPlan.Plan(data, nil, desired, fieldPolicies(entry), {}, unwritable,
			{ names = MiscPlan.PresetNames(deps.env) })
		data, newOwners.misc = plan.characteristics, plan.record
		for id, reason in pairs(plan.conflicts) do
			conflicts = conflicts or {}
			conflicts[id] = reason
		end
	end
	return data, newOwners, conflicts
end

--- Restores a backup for the active profile (the newest, or a chosen one).
-- mode "exact" (the default here): the section comes back exactly as it was,
-- including what Dawnward wrote from data that was public then; Dawnward's
-- ownership records come back with it and the section's features are
-- switched off. mode "own": only the player's own content comes back from
-- the backup; Dawnward's part is planned again from current PUBLIC data
-- (for the features it manages now), so nothing that is no longer public
-- reappears. Either way the same guards as a write apply (except the
-- opt-in, so recovery works after sync was switched off), the current state
-- is backed up first (so a rollback can itself be undone), and the result is
-- read back. Never called automatically.
function Sync.Rollback(deps, backupId, mode)
	mode = mode or "exact"
	if mode ~= "exact" and mode ~= "own" then
		return nil, "choose exact or own"
	end
	local inputs, ierr = rollbackInputs(deps, backupId)
	if not inputs then
		return nil, ierr
	end
	local backup, id = inputs.backup, inputs.profileId
	local record = Ledger.Profile(deps.ledger, id)
	local target, newOwners, conflicts
	if mode == "own" then
		target, newOwners, conflicts = ownOnly(deps, inputs)
		if not target then
			return nil, newOwners
		end
	else
		target, newOwners = inputs.data, backupOwners(backup)
	end
	local safety, serr = Ledger.AddBackup(deps.ledger, id, backup.section, inputs.current,
		{ reason = "before rollback to #" .. backup.id, characterKey = deps.characterKey,
			ownerFeature = SECTION_FEATURES[backup.section][1], owner = record[SECTION_FEATURES[backup.section][1]],
			owners = ownersOf(record, backup.section) }, deps.now())
	if not safety then
		return nil, serr
	end
	local version, rerr, notifyErr = Adapter.WriteSection(deps.env, backup.section, target, id)
	if not version then
		return nil, rerr
	end
	local readBack = Adapter.ReadSection(deps.env, backup.section)
	local expected = Util.DeepCopy(target)
	expected.v = version
	if not readBack or not deepEqual(readBack, expected) then
		restore(deps, id, backup.section, inputs.current)
		Ledger.Log(deps.ledger, deps.now(), "rollback to #" .. backup.id .. " did not read back; restored #" .. safety.id)
		return nil, "Total RP 3 did not read back as restored, so the state before the rollback was put back"
	end
	for _, feature in ipairs(SECTION_FEATURES[backup.section]) do
		record[feature] = Util.DeepCopy(newOwners[feature])
		if ROW_FEATURES[feature] then
			record.fieldConflicts = {}
		else
			record.conflicts[feature] = nil
		end
		if mode == "exact" then
			disableForProfile(deps, id, feature)
		end
	end
	if conflicts then
		pauseFields(deps, record, conflicts, deps.now())
	end
	Ledger.Log(deps.ledger, deps.now(), "rollback (" .. mode .. "): restored " .. backup.section .. " from backup #"
		.. backup.id)
	local note = notifyErr and " Total RP 3 could not be notified; /reload to refresh it." or ""
	if mode == "own" then
		return true, string.format("Restored your own Total RP 3 %s text from backup #%d. Dawnward's part was "
			.. "rebuilt from what is Public now. The state before this rollback is backup #%d.%s", backup.section,
			backup.id, safety.id, note)
	end
	return true, string.format("Restored your Total RP 3 %s from backup #%d (this also undoes any other edits "
		.. "made to that section since then). The state before this rollback is backup #%d. Automatic sync for "
		.. "it is off.%s", backup.section, backup.id, safety.id, note)
end

--- Settles a conflict. Biography and traits: "keep": the player's version
-- stays and Dawnward stops managing it (the feature is switched off).
-- "reclaim": for the biography, the edited text now belongs to the player
-- and Dawnward adds a fresh section of its own on the next sync (nothing the
-- player wrote is changed); for traits, Dawnward takes back the traits
-- carrying its own labels, at their current values, and updates them on the
-- next sync. A field: "keep" hands it to Total RP 3 (never written again
-- unless re-authorised); "reclaim" ("Use Dawnward's") takes the field's
-- current Total RP 3 value as the one Dawnward last wrote, so the next sync
-- replaces it with Dawnward's Public value (after a backup).
function Sync.Resolve(deps, feature, choice)
	if not Sync.FEATURES[feature] and not mappingOf(feature) then
		return nil, "unknown feature '" .. tostring(feature) .. "' (use about, traits or a field such as race)"
	end
	if choice ~= "keep" and choice ~= "reclaim" then
		return nil, "choose keep or reclaim"
	end
	local probe = Adapter.Probe(deps.env)
	local id = probe.profile and probe.profile.id
	local record = id and deps.ledger.profiles[id]
	local m, rowFeature = mappingOf(feature)
	if m then
		if not record or not record.fieldConflicts or not record.fieldConflicts[feature] then
			return nil, "there is no conflict to resolve for " .. m.label .. " on this profile"
		end
		if choice == "keep" then
			record.fieldConflicts[feature] = nil
			if record[rowFeature] then record[rowFeature][feature] = nil end
			disableForProfile(deps, id, rowFeature, { [feature] = true })
			return true, "Kept your " .. m.trp3 .. ". Total RP 3 manages it now; Dawnward will not write it."
		end
		local section, err = Adapter.ReadSection(deps.env, "characteristics")
		if not section then
			return nil, err
		end
		local current
		if rowFeature == "fields" then
			current = section[m.key]
			if current ~= nil and not FieldPlan.IsOwnedValue(m, current) then
				return nil, "Total RP 3's " .. m.trp3 .. " holds formatting Dawnward cannot track; clear it in Total "
					.. "RP 3 first"
			end
		else
			local found = MiscPlan.Find(section, m)
			if #found > 1 then
				return nil, "Total RP 3 has more than one " .. m.trp3 .. " entry; remove the extra one first"
			end
			current = found[1] and found[1].value
			if current ~= nil and (type(current) ~= "string" or FieldPlan.Clean(current) ~= current) then
				return nil, "Total RP 3's " .. m.trp3 .. " holds formatting Dawnward cannot track; clear it in Total "
					.. "RP 3 first"
			end
		end
		-- Keep the player's value safe for good (a pinned backup) before
		-- Dawnward is allowed to replace it.
		local backup, berr = Ledger.AddBackup(deps.ledger, id, "characteristics", section,
			{ reason = "your " .. m.trp3 .. " before Use Dawnward's", characterKey = deps.characterKey,
				ownerFeature = rowFeature, owner = record[rowFeature], owners = ownersOf(record, "characteristics"),
				pin = "reclaim" }, deps.now())
		if not backup then
			return nil, berr
		end
		record.fieldConflicts[feature] = nil
		record[rowFeature] = record[rowFeature] or {}
		record[rowFeature][feature] = current and { value = current } or nil
		if not next(record[rowFeature]) then record[rowFeature] = nil end
		return true, "Dawnward will write its Public " .. m.label .. " to Total RP 3 on the next sync (a backup is "
			.. "taken first, so a rollback can bring yours back)."
	end
	if feature == "fields" then
		return nil, "name the field to resolve (for example: resolve race keep)"
	end
	if not record or not record.conflicts[feature] then
		return nil, "there is no conflict to resolve for this profile"
	end
	if choice == "keep" then
		record.conflicts[feature] = nil
		record[feature] = nil
		disableForProfile(deps, id, feature)
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
		return true, "Dawnward again manages the traits carrying its own labels (for your public axes) and will "
			.. "update them on the next sync."
	end
	record.conflicts[feature] = nil
	record[feature] = nil
	return true, "Your edited version is now yours. Dawnward will add a new section of its own on the next sync."
end
