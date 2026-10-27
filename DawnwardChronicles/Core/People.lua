-- People the character knows: NPCs (#18), other players' characters (#28)
-- and family or other connections (#37). Only the player creates these;
-- nothing is inferred from groups, guilds, reputation or other players'
-- profiles, and there is no relationship score.
--
-- Another player's character is keyed by name and realm. A second record
-- for the same name-realm is refused rather than merged; the same name on
-- another realm is a different person.
local _, ns = ...
local Records, RecordTypes, Privacy = ns.Records, ns.RecordTypes, ns.Privacy

local People = {}
ns.People = People

local function list(char)
	return char.story.people
end

local function sameIdentity(a, b)
	return a.kind == b.kind and a.name:lower() == b.name:lower()
		and (a.realm or ""):lower() == (b.realm or ""):lower()
end

--- values: { name, kind, realm, relation, feelings, visibility, feelingsVisibility }.
function People.Add(char, values, now)
	local p = Records.New(char.story, "player", now, values.visibility)
	for _, k in ipairs({ "name", "kind", "realm", "relation", "feelings" }) do
		p[k] = values[k]
	end
	p.feelingsVisibility = values.feelingsVisibility or Privacy.PRIVATE
	local clean = RecordTypes.CleanPerson(p)
	if not clean then
		return nil, "a person needs a name"
	end
	if clean.kind == "player" and not clean.realm then
		return nil, "another player's character needs a realm (Name-Realm), so they are never confused"
	end
	for _, other in ipairs(list(char)) do
		if sameIdentity(other, clean) then
			return nil, "#" .. other.id .. " is already " .. clean.name .. "; edit that record instead"
		end
	end
	if not Records.Append(list(char), clean, RecordTypes.LIMITS.people) then
		return nil, "the list of people is full; remove some first"
	end
	return clean
end

function People.Find(char, id) return Records.Find(list(char), id) end
function People.Remove(char, id) return Records.Remove(list(char), id) end
function People.SetVisibility(char, id, level, now) return Records.Visibility(list(char), id, level, now) end

--- The player edits a person: { name, realm, kind, relation, feelings }.
-- nil leaves a field as it is. A rename that would duplicate another
-- record is refused, as when adding.
function People.Edit(char, id, values, now)
	local p = People.Find(char, id)
	if not p then return nil, "no person #" .. tostring(id) end
	local probe = { name = p.name, realm = p.realm, kind = p.kind }
	if values.name ~= nil then
		probe.name = Records.Text(values.name, 100)
		if not probe.name then return nil, "a person needs a name" end
	end
	if values.kind ~= nil then
		if not RecordTypes.PERSON_KINDS[values.kind] then return nil, "unknown kind of person" end
		probe.kind = values.kind
	end
	if values.realm ~= nil then probe.realm = Records.Text(values.realm, 100) end
	if probe.kind ~= "player" then probe.realm = nil end
	if probe.kind == "player" and not probe.realm then
		return nil, "another player's character needs a realm (Name-Realm), so they are never confused"
	end
	for _, other in ipairs(list(char)) do
		if other ~= p and sameIdentity(other, probe) then
			return nil, "#" .. other.id .. " is already " .. probe.name .. "; edit that record instead"
		end
	end
	p.name, p.realm, p.kind = probe.name, probe.realm, probe.kind
	if values.relation ~= nil then p.relation = Records.Text(values.relation, 300, true) end
	if values.feelings ~= nil then p.feelings = Records.Text(values.feelings, 1000, true) end
	p.updatedAt = now or 0
	return p
end

--- Records of one kind, by name.
function People.OfKind(char, kind)
	local out = {}
	for _, p in ipairs(list(char)) do
		if not kind or p.kind == kind then out[#out + 1] = p end
	end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
end
