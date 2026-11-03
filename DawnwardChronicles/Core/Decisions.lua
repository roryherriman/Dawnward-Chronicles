-- The player's answers to reactions. A decision is the only thing that can
-- propose a personality change, and the only source of story drafts.
--
-- Deciding:
--   1. records the decision (the answer, or the player's own words)
--   2. proposes the answer's small personality changes (Core/Evolution.lua);
--      a custom answer proposes none, the player adjusts by hand if they wish
--   3. writes a private journal draft (Core/Narrative.lua), unless drafts
--      are switched off
--   4. keeps a notable answer as an established memory, in the same words
--      (Core/Memories.lua), and suggests a reflection for a defining one
--   5. removes the reaction from the queue
local _, ns = ...
local StorySchema, Reactions, Evolution, Narrative, Journal =
	ns.StorySchema, ns.Reactions, ns.Evolution, ns.Narrative, ns.Journal

local Decisions = {}
ns.Decisions = Decisions

local function newId(story)
	local id = story.nextId
	story.nextId = id + 1
	return id
end

function Decisions.Find(char, id)
	for _, decision in ipairs(char.story.decisions) do
		if decision.id == id then
			return decision
		end
	end
	return nil
end

-- Effects in a stable order, so drafts and tests are deterministic.
local function sortedEffects(effects)
	local out = {}
	for axis, delta in pairs(effects or {}) do
		out[#out + 1] = { axis = axis, delta = delta }
	end
	table.sort(out, function(a, b) return a.axis < b.axis end)
	return out
end

--- choice: { optionId = string } or { custom = string }.
-- Returns result { decision, changes, entry, draftError, memory (the answer's
-- established record), reflection (a suggested interpretation), arc, profile
-- (the profile suggestions it made, also through an approved change) } or nil, reason.
function Decisions.Decide(char, reactionId, choice, now)
	local reaction = Reactions.Find(char, reactionId)
	if not reaction then
		return nil, "no waiting reaction #" .. tostring(reactionId)
	end
	local view, err = Reactions.Present(char, reaction, now)
	if not view then
		return nil, err
	end
	local option, custom
	if choice.custom ~= nil then
		custom = ns.Util.CleanText(choice.custom, StorySchema.LIMITS.custom, true)
		if not custom or custom == "" then
			return nil, "write a response first"
		end
	else
		option = Reactions.FindOption(view, choice.optionId)
		if not option then
			return nil, "that is not one of the answers"
		end
	end
	local story = char.story
	local decision = {
		id = newId(story), category = reaction.category, eventKeys = reaction.eventKeys,
		templateId = reaction.templateId, optionId = option and option.id or nil, custom = custom,
		phrase = option and option.phrase or nil, theme = option and option.theme or nil, at = now or 0, effects = {},
	}
	local changes = {}
	-- Profile suggestions made from here on (an automatically approved
	-- change can suggest an At First Glance entry) are reported in result.profile.
	local firstSuggestion = char.profileSuggestions and char.profileSuggestions.nextId or 1
	if option then
		for _, e in ipairs(sortedEffects(option.effects)) do
			decision.effects[e.axis] = e.delta
			local reason = string.format("%s %s", view.name, option.phrase)
			local change = Evolution.Propose(char, e.axis, e.delta, reason, decision.id, now)
			if change then
				changes[#changes + 1] = change
			end
		end
	end
	story.decisions[#story.decisions + 1] = decision
	while #story.decisions > StorySchema.LIMITS.decisions do
		table.remove(story.decisions, 1)
	end
	local result = { decision = decision, changes = changes }
	if story.prefs.drafts then
		local draft = Narrative.Draft({ name = view.name, record = view.record, extra = #reaction.eventKeys - 1,
			option = option, custom = custom, changes = changes })
		local entry, jerr = Journal.AddStoryDraft(char, { title = draft.title, text = draft.text,
			story = { category = reaction.category, decisionId = decision.id, eventKey = reaction.eventKeys[1] } }, now)
		if entry then
			decision.journalId = entry.id
			result.entry = entry
		else
			result.draftError = jerr
		end
	end
	if option and option.contextual then
		ns.Director.Apply(char, option, decision, now)
	end
	-- v0.10.3: the answer itself is kept as an established, private memory
	-- in the same words as the draft (the player chose it: no second
	-- confirmation); only a reflection that adds Dawnward's interpretation,
	-- for a defining moment, waits for the player as a suggestion.
	result.memory, result.reflection = ns.Memories.FromDecision(char, { significance = reaction.significance,
		record = view.record,
		title = result.entry and result.entry.title or (view.record and ns.GameEvents.Label(view.record.category)),
		custom = custom, option = option, name = view.name, eventKeys = reaction.eventKeys, decisionId = decision.id,
		journalId = decision.journalId }, now)
	result.arc = ns.Arcs.SuggestFromPattern(char, now)
	Reactions.Resolve(char, reactionId)
	-- v0.10.2: approved development may suggest a profile change (only a
	-- suggestion; Core/ProfileSuggestions.lua).
	ns.ProfileSuggestions.Generate(char, now, { kind = "decision", decision = decision,
		reaction = reaction, record = view.record })
	result.profile = {}
	for _, s in ipairs(char.profileSuggestions and char.profileSuggestions.list or {}) do
		if s.id >= firstSuggestion and ns.ProfileSuggestions.OPEN[s.status] then
			result.profile[#result.profile + 1] = s
		end
	end
	return result
end

--- Newest first, at most limit.
function Decisions.Recent(char, limit)
	local out, list = {}, char.story.decisions
	for i = #list, 1, -1 do
		if #out >= (limit or 10) then break end
		out[#out + 1] = list[i]
	end
	return out
end
