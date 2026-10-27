-- Story continuity review (#42). Rule-based checks that point out things
-- worth a second look, and ask the player what each one is:
--   growth       the character changed; both records stay true for their time
--   unreliable   the character believes something that is not so
--   secret       it is deliberate and should stay hidden
--   correction   a mistake the player will fix themselves
--   ignore       not a problem
-- Continuity never rewrites canon. The only change it makes on its own is
-- recording the answer; "secret" additionally hides the private side of the
-- finding, because the player chose that.
--
-- Each finding has a stable key, so an answered finding does not come back
-- unless the records behind it change.
local _, ns = ...
local Records, RecordTypes, Privacy, Personality = ns.Records, ns.RecordTypes, ns.Privacy, ns.Personality

local Continuity = {}
ns.Continuity = Continuity

Continuity.STRONG = 4 -- an axis at 0-3 or 17-20 counts as a strong lean

local function reviewed(char)
	local done = {}
	for _, r in ipairs(char.story.reviews) do
		done[r.key] = r
	end
	return done
end

local function lower(s)
	return (s or ""):lower()
end

-- Rules: each returns a list of { key, kind, message, refs }.
local RULES = {}

-- A public persona that differs from a private conviction, not marked as deliberate.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, i in ipairs(char.story.identity) do
		if i.status == "established" and not i.deliberate and ns.Identity.Contradicts(i) then
			out[#out + 1] = { key = string.format("persona:%d:%s", i.id, ns.Util.Checksum(i.persona .. "|" .. i.conviction)),
				kind = "persona", refs = { identity = i.id },
				message = string.format("About %s, they say \"%s\" in public but believe \"%s\".", i.subject, i.persona,
					i.conviction) }
		end
	end
	return out
end

-- A personality axis strongly on one side while an established trait fact
-- names the opposite pole.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, item in ipairs(Personality.List(char)) do
		local opposite
		if item.value < Continuity.STRONG then
			opposite = item.axis.right
		elseif item.value > Personality.MAX - Continuity.STRONG then
			opposite = item.axis.left
		end
		if opposite then
			for _, fact in ipairs(char.facts) do
				if fact.category == "trait" and lower(fact.statement):find(lower(opposite), 1, true) then
					out[#out + 1] = { key = string.format("axis:%s:%d:%d", item.axis.id, item.value, fact.id),
						kind = "personality", refs = { fact = fact.id, axis = item.axis.id },
						message = string.format("%s is %d/20 (toward %s), but a trait says \"%s\".", item.axis.id,
							item.value, item.value < 10 and item.axis.left or item.axis.right, fact.statement) }
				end
			end
		end
	end
	return out
end

-- Disputed records waiting for a decision.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, listName in ipairs({ "memories", "arcs", "goals", "identity" }) do
		for _, r in ipairs(char.story[listName]) do
			if r.status == "disputed" then
				out[#out + 1] = { key = string.format("disputed:%s:%d", listName, r.id), kind = "disputed",
					refs = { [listName] = r.id },
					message = string.format("%s #%d (\"%s\") is marked disputed.", listName, r.id,
						r.title or r.subject or r.text or "?") }
			end
		end
	end
	return out
end

-- A goal whose verified objective is met but which is still active.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, g in ipairs(char.story.goals) do
		if g.state == "active" then
			local p = ns.Goals.Progress(char, g)
			if p.objective and p.objective.met then
				out[#out + 1] = { key = "goalmet:" .. g.id, kind = "goal", refs = { goals = g.id },
					message = string.format("Goal \"%s\": the game shows %s. Is the goal achieved for them?",
						g.title, ns.Goals.ObjectiveText(p)) }
			end
		end
	end
	return out
end

-- Two established memories with the same title.
RULES[#RULES + 1] = function(char)
	local out, seen = {}, {}
	for _, m in ipairs(char.story.memories) do
		if m.status == "established" and m.title then
			local k = lower(m.title)
			if seen[k] then
				out[#out + 1] = { key = string.format("duplicate:%d:%d", seen[k], m.id), kind = "duplicate",
					refs = { memories = m.id },
					message = string.format("Two memories are both called \"%s\" (#%d and #%d).", m.title, seen[k], m.id) }
			else
				seen[k] = m.id
			end
		end
	end
	return out
end

-- A public record linked to a secret memory: the link itself could hint at it.
RULES[#RULES + 1] = function(char)
	local out = {}
	local secret = {}
	for _, m in ipairs(char.story.memories) do
		if m.visibility == Privacy.SECRET then secret[m.id] = true end
	end
	for _, listName in ipairs({ "memories", "arcs", "goals" }) do
		for _, r in ipairs(char.story[listName]) do
			if Records.IsPublic(r) then
				for _, mid in ipairs(r.links.memories) do
					if secret[mid] then
						out[#out + 1] = { key = string.format("publicsecret:%s:%d:%d", listName, r.id, mid), kind = "privacy",
							refs = { [listName] = r.id },
							message = string.format("Public %s #%d is linked to a secret memory (#%d).", listName, r.id, mid) }
					end
				end
			end
		end
	end
	return out
end

--- Open findings (not yet reviewed), in rule order.
function Continuity.Findings(char)
	local done = reviewed(char)
	local out = {}
	for _, rule in ipairs(RULES) do
		for _, finding in ipairs(rule(char)) do
			if not done[finding.key] then
				out[#out + 1] = finding
			end
		end
	end
	return out
end

--- Records the player's answer to a finding. Returns the review or nil, reason.
function Continuity.Review(char, key, choice, note, now)
	if not RecordTypes.REVIEW_CHOICES[choice] then
		return nil, "choose growth, unreliable, secret, correction or ignore"
	end
	local finding
	for _, f in ipairs(Continuity.Findings(char)) do
		if f.key == key then finding = f end
	end
	if not finding then
		return nil, "no open continuity finding with that key"
	end
	local review = RecordTypes.CleanReview({ key = key, choice = choice, note = note, at = now or 0 })
	local reviews = char.story.reviews
	if #reviews >= RecordTypes.LIMITS.reviews then
		table.remove(reviews, 1)
	end
	reviews[#reviews + 1] = review
	-- "secret": hide the private side the player wants kept hidden.
	if choice == "secret" and finding.refs.identity then
		local i = ns.Identity.Find(char, finding.refs.identity)
		if i then
			i.convictionVisibility = Privacy.SECRET
			i.deliberate = true
		end
	end
	return review, finding
end
