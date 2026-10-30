-- Story continuity review (#42). Rule-based checks that point out things
-- worth a second look, and ask the player what each one is:
--   growth       the character changed; both records stay true for their time
--   unreliable   the character believes something that is not so
--   secret       it is deliberate and should stay hidden
--   correction   a mistake the player will fix themselves
--   ignore       not a problem
--   explained    the player's own explanation, kept with the answer (a note
--                is required)
--
-- The player can also:
--   examine      see the records behind a finding side by side, with their
--                dates, where they came from, canon status and visibility
--                (Continuity.Examine)
--   correct      open either record's own edit form (UI) or chat command;
--                Continuity never edits a record itself
--   undo         take an answer back (Continuity.Undo): the finding returns
--                if the records still disagree, and anything the answer
--                changed is put back as it was (only where the player has
--                not changed it since)
--
-- Continuity never rewrites canon. The only change it makes on its own is
-- recording the answer; "secret" additionally hides the private side of a
-- stance, because the player chose that, and remembers how it was so the
-- answer can be undone.
--
-- Each finding has a stable key, so an answered finding does not come back
-- unless the records behind it change. Rules are cheap and deterministic:
-- plain comparisons of the player's own records and verified game data,
-- never a guess about what a text means.
local _, ns = ...
local Records, RecordTypes, Privacy, Personality = ns.Records, ns.RecordTypes, ns.Privacy, ns.Personality

local Continuity = {}
ns.Continuity = Continuity

Continuity.STRONG = 4 -- an axis at 0-3 or 17-20 counts as a strong lean

-- Words that turn a statement around, for the stance / public fact check.
-- Only whole words; a difference in these between two public texts about the
-- same subject is worth a look, never a verdict.
Continuity.NEGATIONS = { "not", "never", "no", "against", "distrust", "distrusts", "hate", "hates", "despise",
	"despises", "nor", "isn't", "doesn't", "won't", "cannot", "can't" }

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

local NEGATION_SET = {}
for _, w in ipairs(Continuity.NEGATIONS) do NEGATION_SET[w] = true end

local function negated(text)
	for word in lower(text):gmatch("[%a']+") do
		if NEGATION_SET[word] then return true end
	end
	return false
end

-- Rules: each returns a list of { key, kind, message, refs, sides } where
-- sides = { { list, id, part } } names the records behind the finding, for
-- Examine (list: memories, arcs, goals, identity, people, facts,
-- personality, objective).
local RULES = {}

-- A public persona that differs from a private conviction, not marked as deliberate.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, i in ipairs(char.story.identity) do
		if i.status == "established" and not i.deliberate and ns.Identity.Contradicts(i) then
			out[#out + 1] = { key = string.format("persona:%d:%s", i.id, ns.Util.Checksum(i.persona .. "|" .. i.conviction)),
				kind = "persona", refs = { identity = i.id },
				sides = { { list = "identity", id = i.id, part = "persona" },
					{ list = "identity", id = i.id, part = "conviction" } },
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
						sides = { { list = "personality", id = item.axis.id }, { list = "facts", id = fact.id } },
						message = string.format("%s is %d/20 (toward %s), but a trait says \"%s\".", item.axis.id,
							item.value, item.value < 10 and item.axis.left or item.axis.right, fact.statement) }
				end
			end
		end
	end
	return out
end

-- A public stance about a subject, and a public fact about the same subject,
-- where one says it the other way round (a "not", "never", "against" in one
-- and not the other). Both are public, so readers would see both.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, i in ipairs(char.story.identity) do
		if i.status == "established" and i.persona and i.visibility == Privacy.PUBLIC and not i.deliberate then
			local subject = lower(i.subject)
			for _, fact in ipairs(char.facts) do
				local about = fact.subject and lower(fact.subject) == subject
					or (#subject >= 4 and lower(fact.statement):find(subject, 1, true) ~= nil)
				if fact.visibility == Privacy.PUBLIC and about and negated(fact.statement) ~= negated(i.persona) then
					out[#out + 1] = { key = string.format("publicfact:%d:%d:%s", i.id, fact.id,
						ns.Util.Checksum(i.persona .. "|" .. fact.statement)), kind = "publicfact",
						refs = { identity = i.id, fact = fact.id },
						sides = { { list = "identity", id = i.id, part = "persona" }, { list = "facts", id = fact.id } },
						message = string.format("Both public: about %s, their stance says \"%s\", but a fact says \"%s\".",
							i.subject, i.persona, fact.statement) }
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
					refs = { [listName] = r.id }, sides = { { list = listName, id = r.id } },
					message = string.format("%s #%d (\"%s\") is marked disputed.", listName, r.id,
						r.title or r.subject or r.text or "?") }
			end
		end
	end
	return out
end

-- Goals and what the game shows, or the player's own steps.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, g in ipairs(char.story.goals) do
		local p = ns.Goals.Progress(char, g)
		if g.state == "active" and p.objective and p.objective.met then
			-- Verified objective met, still active.
			out[#out + 1] = { key = "goalmet:" .. g.id, kind = "goal", refs = { goals = g.id },
				sides = { { list = "goals", id = g.id }, { list = "objective", id = g.id } },
				message = string.format("Goal \"%s\": the game shows %s. Is the goal achieved for them?",
					g.title, ns.Goals.ObjectiveText(p)) }
		elseif g.state == "achieved" then
			-- Achieved, while one of the player's own steps is still open.
			local open = {}
			for _, m in ipairs(g.milestones) do
				if not m.done then open[#open + 1] = m.text end
			end
			if #open > 0 then
				out[#out + 1] = { key = string.format("goalopen:%d:%s", g.id, ns.Util.Checksum(table.concat(open, "|"))),
					kind = "goal", refs = { goals = g.id }, sides = { { list = "goals", id = g.id } },
					message = string.format("Goal \"%s\" is marked achieved, but %d of its steps %s not done (\"%s\").",
						g.title, #open, #open == 1 and "is" or "are", open[1]) }
			end
			-- Achieved, while the game shows the objective is not reached (yet).
			if p.objective and p.objective.current and not p.objective.met then
				out[#out + 1] = { key = string.format("goalunmet:%d:%d:%d", g.id, p.objective.target, p.objective.current),
					kind = "goal", refs = { goals = g.id },
					sides = { { list = "goals", id = g.id }, { list = "objective", id = g.id } },
					message = string.format("Goal \"%s\" is marked achieved, but the game shows %s.", g.title,
						ns.Goals.ObjectiveText(p)) }
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
					sides = { { list = "memories", id = seen[k] }, { list = "memories", id = m.id } },
					message = string.format("Two memories are both called \"%s\" (#%d and #%d).", m.title, seen[k], m.id) }
			else
				seen[k] = m.id
			end
		end
	end
	return out
end

-- A memory dated before the event it remembers. Only when both dates are
-- known (a date of 0 means unknown, as for backstory written before the
-- chronicle began).
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, m in ipairs(char.story.memories) do
		if m.status ~= "superseded" and m.at and m.at > 0 then
			for _, k in ipairs(m.links.events) do
				local e = ns.GameEvents.Find(char, k)
				if e and e.at and e.at > 0 and e.at > m.at then
					out[#out + 1] = { key = string.format("memorydate:%d:%s", m.id, k), kind = "date",
						refs = { memories = m.id }, sides = { { list = "memories", id = m.id }, { list = "events", id = k } },
						message = string.format("Memory \"%s\" is dated before the event it is linked to (%s).",
							m.title or m.text or "?", ns.GameEvents.RecordLabel(e)) }
					break
				end
			end
		end
	end
	return out
end

-- A record marked as replaced by one that no longer exists.
RULES[#RULES + 1] = function(char)
	local out = {}
	for _, listName in ipairs({ "memories", "arcs", "goals", "identity" }) do
		local list = char.story[listName]
		for _, r in ipairs(list) do
			if r.status == "superseded" and r.supersededBy and not Records.Find(list, r.supersededBy) then
				out[#out + 1] = { key = string.format("replaced:%s:%d:%d", listName, r.id, r.supersededBy), kind = "replaced",
					refs = { [listName] = r.id }, sides = { { list = listName, id = r.id } },
					message = string.format("%s #%d (\"%s\") was replaced by #%d, which no longer exists.", listName, r.id,
						r.title or r.subject or r.text or "?", r.supersededBy) }
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
							sides = { { list = listName, id = r.id }, { list = "memories", id = mid } },
							message = string.format("Public %s #%d is linked to a secret memory (#%d).", listName, r.id, mid) }
					end
				end
			end
		end
	end
	return out
end

local function allFindings(char)
	local out = {}
	for _, rule in ipairs(RULES) do
		for _, finding in ipairs(rule(char)) do
			out[#out + 1] = finding
		end
	end
	return out
end

--- Open findings (not yet reviewed), in rule order.
function Continuity.Findings(char)
	local done = reviewed(char)
	local out = {}
	for _, finding in ipairs(allFindings(char)) do
		if not done[finding.key] then
			out[#out + 1] = finding
		end
	end
	return out
end

--- A finding by key, open or answered (nil if the records no longer produce it).
function Continuity.Find(char, key)
	for _, f in ipairs(allFindings(char)) do
		if f.key == key then return f end
	end
	return nil
end

--- Examine ----------------------------------------------------------------------

local LIST_LABELS = { memories = "Memory", arcs = "Arc", goals = "Goal", identity = "Stance", people = "Person",
	facts = "Fact", personality = "Personality", objective = "What the game shows", events = "Event" }
local PROVENANCE = { player = "Your words", observed = "From the game", suggested = "Suggested by Dawnward" }
Continuity.LIST_LABELS = LIST_LABELS
-- Story lists whose records the player can edit from the Chronicle.
Continuity.EDITABLE = { memories = true, arcs = true, goals = true, identity = true, people = true }

-- One side of a finding, described from the stored record only.
local function sideView(char, side)
	local v = { list = side.list, id = side.id, part = side.part, label = LIST_LABELS[side.list] or side.list }
	local list = side.list
	if Continuity.EDITABLE[list] then
		local r = Records.Find(char.story[list], side.id)
		if not r then
			v.missing = true
			v.title = string.format("%s #%s (no longer exists)", v.label, tostring(side.id))
			return v
		end
		v.record = r
		v.editable = true
		v.at, v.updatedAt = r.at, r.updatedAt
		v.provenance = PROVENANCE[r.provenance] or r.provenance
		v.status, v.visibility = r.status, r.visibility
		if list == "identity" then
			v.title = r.subject
			if side.part == "conviction" then
				v.label = "Stance, privately"
				v.text, v.visibility = r.conviction, r.convictionVisibility
			elseif side.part == "persona" then
				v.label = "Stance, in public"
				v.text = r.persona
			else
				v.text = r.persona or r.conviction
			end
		elseif list == "arcs" then
			v.title, v.text = r.title, r.summary
		elseif list == "people" then
			v.title, v.text = r.name, r.relation
		else
			v.title, v.text = r.title, r.text
		end
	elseif list == "facts" then
		local fact = ns.Facts.Find(char, side.id)
		if fact then
			v.title, v.text = ns.Facts.DisplayCategory(fact.category).label, fact.statement
			v.at = fact.createdAt
			v.provenance = fact.provenance and fact.provenance.interpreted and "Your approved interpretation" or "Your words"
			v.status, v.visibility = "established", fact.visibility
			v.where = "Character"
		else
			v.missing = true
		end
	elseif list == "personality" then
		local entry = char.personality and char.personality[side.id]
		local axis = Personality.AXIS_BY_ID and Personality.AXIS_BY_ID[side.id]
		if entry then
			v.title = axis and string.format("%s - %s", axis.left, axis.right) or side.id
			v.text = string.format("%s: %d/20", side.id, entry.value)
			v.at = entry.updatedAt
			v.provenance, v.status, v.visibility = "Your setting and approved changes", "established", entry.visibility
			v.where = "Character"
		else
			v.missing = true
		end
	elseif list == "objective" then
		local g = ns.Goals.Find(char, side.id)
		local p = g and ns.Goals.Progress(char, g)
		v.title = g and g.title
		v.text = p and ns.Goals.ObjectiveText(p) or "No verified objective"
		v.provenance, v.status = "From the game", "observed"
	elseif list == "events" then
		local e = ns.GameEvents.Find(char, side.id)
		if e then
			v.title = ns.GameEvents.RecordLabel(e)
			v.text = (e.meta and e.meta.title) or e.zone
			v.at = e.at
			v.provenance, v.status = "From the game", e.confidence
		else
			v.missing = true
		end
	end
	return v
end

--- The records behind a finding, side by side. Returns { finding, sides =
-- { view, ... }, review = the answer if any } or nil, reason. Each view:
-- { label, title, text, at, updatedAt, provenance, status, visibility,
-- list, id, part, editable, record, where, missing }. Read-only.
function Continuity.Examine(char, key)
	local finding = Continuity.Find(char, key)
	if not finding then
		return nil, "no continuity finding with that key"
	end
	local sides = {}
	for _, side in ipairs(finding.sides or {}) do
		sides[#sides + 1] = sideView(char, side)
	end
	return { finding = finding, sides = sides, review = reviewed(char)[key] }
end

--- Answers ---------------------------------------------------------------------

--- Records the player's answer to a finding. Returns the review or nil, reason.
-- "explained" needs a note (the player's explanation); every answer may carry one.
function Continuity.Review(char, key, choice, note, now)
	if not RecordTypes.REVIEW_CHOICES[choice] then
		return nil, "choose growth, unreliable, secret, correction, ignore or explained"
	end
	local finding
	for _, f in ipairs(Continuity.Findings(char)) do
		if f.key == key then finding = f end
	end
	if not finding then
		return nil, "no open continuity finding with that key"
	end
	if choice == "explained" and not Records.Text(note, 300, true) then
		return nil, "write your explanation first"
	end
	local review = RecordTypes.CleanReview({ key = key, choice = choice, note = note, at = now or 0,
		message = finding.message })
	-- "secret": hide the private side the player wants kept hidden, and
	-- remember how it was, so the answer can be undone.
	if choice == "secret" and finding.refs.identity then
		local i = ns.Identity.Find(char, finding.refs.identity)
		if i then
			review.undo = { identity = i.id, convictionVisibility = i.convictionVisibility, deliberate = i.deliberate == true }
			i.convictionVisibility = Privacy.SECRET
			i.deliberate = true
		end
	end
	local reviews = char.story.reviews
	if #reviews >= RecordTypes.LIMITS.reviews then
		table.remove(reviews, 1)
	end
	reviews[#reviews + 1] = review
	return review, finding
end

--- Answered findings, newest first: { review, index } where index is its
-- place in story.reviews.
function Continuity.Answered(char)
	local out = {}
	local list = char.story.reviews
	for i = #list, 1, -1 do
		out[#out + 1] = { review = list[i], index = i }
	end
	return out
end

--- Takes an answer back. The finding is open again if the records still
-- disagree. What a "secret" answer changed on a stance is restored, field
-- by field, only where it still holds the value the answer set (a later
-- change by the player is kept). Returns the removed review or nil, reason.
function Continuity.Undo(char, key)
	local list = char.story.reviews
	for i = #list, 1, -1 do
		local review = list[i]
		if review.key == key then
			table.remove(list, i)
			local u = review.undo
			if u and u.identity then
				local stance = ns.Identity.Find(char, u.identity)
				if stance then
					if stance.convictionVisibility == Privacy.SECRET then
						stance.convictionVisibility = u.convictionVisibility
					end
					if stance.deliberate == true and not u.deliberate then
						stance.deliberate = nil
					end
				end
			end
			return review
		end
	end
	return nil, "that finding has no answer to undo"
end
