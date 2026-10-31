-- Public persona and private convictions (#30). For any subject (a faction,
-- a city, an order, a person, an idea) a character can present one face in
-- public and believe something else in private, on purpose.
--
--   persona        how they present themselves; follows the record's visibility
--   conviction     what they really believe; its own visibility, private by default
--   deliberate     the player marked the contradiction as intended
--
-- Observed facts (for example a reputation standing, #18) never become a
-- persona or a conviction: Exalted with a faction does not mean loyal to it.
-- Only the player writes these. Public output contains the persona alone,
-- never the conviction or the reason for the difference, unless the player
-- separately made the conviction public.
local _, ns = ...
local Records, RecordTypes, Privacy = ns.Records, ns.RecordTypes, ns.Privacy

local Identity = {}
ns.Identity = Identity

local function list(char)
	return char.story.identity
end

--- values: { subject, persona, conviction, visibility (persona),
--   convictionVisibility, deliberate }.
function Identity.Add(char, values, now)
	-- The public persona is what others see; under the profile model it
	-- starts Public. The private conviction always starts Private.
	local i = Records.New(char.story, "player", now, values.visibility or Privacy.DefaultFor(char, "stance"))
	i.subject = values.subject
	i.persona = values.persona
	i.conviction = values.conviction
	i.convictionVisibility = values.convictionVisibility or Privacy.PRIVATE
	i.deliberate = values.deliberate
	local clean = RecordTypes.CleanIdentity(i)
	if not clean then
		return nil, "an identity statement needs a subject and a public stance or a private conviction"
	end
	if not Records.Append(list(char), clean, RecordTypes.LIMITS.identity) then
		return nil, "there are too many identity statements; remove some first"
	end
	return clean
end

function Identity.Find(char, id) return Records.Find(list(char), id) end
function Identity.Remove(char, id) return Records.Remove(list(char), id) end
function Identity.SetVisibility(char, id, level, now) return Records.Visibility(list(char), id, level, now) end

--- The player edits a stance: { subject, persona, conviction, deliberate }.
-- nil leaves a field as it is; "" clears persona or conviction, but one of
-- the two must remain.
function Identity.Edit(char, id, values, now)
	local i = Identity.Find(char, id)
	if not i then return nil, "no identity statement #" .. tostring(id) end
	local subject, persona, conviction = i.subject, i.persona, i.conviction
	if values.subject ~= nil then
		subject = Records.Text(values.subject, 100)
		if not subject then return nil, "a stance needs a subject" end
	end
	if values.persona ~= nil then persona = Records.Text(values.persona, 300, true) end
	if values.conviction ~= nil then conviction = Records.Text(values.conviction, 300, true) end
	if not persona and not conviction then
		return nil, "a stance needs a public stance or a private conviction"
	end
	i.subject, i.persona, i.conviction = subject, persona, conviction
	if values.deliberate ~= nil then i.deliberate = values.deliberate == true or nil end
	i.updatedAt = now or 0
	return i
end

function Identity.SetConvictionVisibility(char, id, level, now)
	local i = Identity.Find(char, id)
	if not i then return nil, "no identity statement #" .. tostring(id) end
	if not Privacy.IsValid(level) then return nil, "visibility must be public, private or secret" end
	i.convictionVisibility, i.updatedAt = level, now or 0
	return i
end

--- Whether persona and conviction differ (both present and not equal).
function Identity.Contradicts(i)
	return i.persona ~= nil and i.conviction ~= nil and i.persona:lower() ~= i.conviction:lower()
end

--- Public view of identity statements: { subject, persona, conviction? }.
-- Only established records; the conviction only if itself public.
function Identity.Public(char)
	local out = {}
	for _, i in ipairs(list(char)) do
		if i.status == "established" then
			local entry = { subject = i.subject }
			if i.visibility == Privacy.PUBLIC and i.persona then
				entry.persona = i.persona
			end
			if i.convictionVisibility == Privacy.PUBLIC and i.conviction then
				entry.conviction = i.conviction
			end
			if entry.persona or entry.conviction then
				out[#out + 1] = entry
			end
		end
	end
	return out
end
