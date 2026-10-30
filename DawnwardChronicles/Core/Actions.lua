-- Player actions shared by the journal window and slash commands.
--
-- Every write goes through here: it refuses read-only data, creates the
-- character on first write, and reuses the Character/Journal validation.
-- Each function returns ok (or the changed item) plus a short player-facing
-- message, and never raises for bad input.
--
-- ctx needs: store, characterKey, now()
local _, ns = ...
local Character, Journal, Milestones, Themes, Facts, Personality, GameEvents, Reactions, Decisions, Evolution =
	ns.Character, ns.Journal, ns.Milestones, ns.Themes, ns.Facts, ns.Personality, ns.GameEvents, ns.Reactions,
	ns.Decisions, ns.Evolution

local Actions = {}
ns.Actions = Actions

local function fail(err)
	return nil, "Not changed: " .. tostring(err)
end

-- Runs change(char) on the active character, creating it first if needed.
-- If the character was created for this change and the change fails, it is
-- removed again, so a rejected first edit leaves no empty record behind.
-- change returns result, message (result nil on failure).
local function withCharacter(ctx, change)
	local reason = ctx.store:ReadOnlyReason()
	if reason then
		return nil, "Saved data is read-only (" .. reason .. "). Nothing was changed."
	end
	local existed = ctx.store:GetCharacter(ctx.characterKey) ~= nil
	local char, err = ctx.store:EnsureCharacter(ctx.characterKey, ctx.now())
	if not char then
		return nil, "Cannot save: " .. err
	end
	local result, message = change(char)
	if not result and not existed then
		ctx.store:Root().characters[ctx.characterKey] = nil
	end
	-- A change made in the window may change what is public, so ask an
	-- opted-in Total RP 3 sync to catch up, as slash commands already do
	-- (debounced; nothing happens unless sync was turned on).
	if result and ctx.trp3RequestSync then
		ctx.trp3RequestSync()
	end
	return result, message
end

--- For other core modules' commands (Core/NarrativeCommands.lua): the same
-- read-only, create-on-first-write and rollback-on-failure rules.
Actions.WithCharacter = withCharacter
Actions.Fail = fail

--- Read access (never creates anything).
function Actions.Character(ctx)
	return ctx.store:GetCharacter(ctx.characterKey)
end

function Actions.ThemeOf(char)
	return Themes.Get(char and char.theme)
end

--- Journal -------------------------------------------------------------------

local function prunedNote(pruned)
	if pruned and pruned > 0 then
		return " The journal was full, so the oldest automatic entry was removed."
			.. " Entries you write are never removed automatically."
	end
	return ""
end

function Actions.AddNote(ctx, title, text, visibility)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.AddNote(char, { title = title, text = text, visibility = visibility }, ctx.now())
		if not entry then return fail(result) end
		return entry, "Added journal entry #" .. entry.id .. "." .. prunedNote(result)
	end)
end

function Actions.UpdateNote(ctx, id, title, text, visibility)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.UpdateNote(char, id,
			{ title = title, text = text, visibility = visibility }, ctx.now())
		if not entry then return fail(result) end
		return entry, "Updated journal entry #" .. id .. "."
	end)
end

function Actions.SetEntryVisibility(ctx, id, level)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.SetVisibility(char, id, level, ctx.now())
		if not entry then return fail(result) end
		return entry, "Journal entry #" .. id .. " is now " .. level .. "."
	end)
end

function Actions.RemoveNote(ctx, id)
	return withCharacter(ctx, function(char)
		local entry, result = Journal.RemoveNote(char, id, ctx.now())
		if not entry then return fail(result) end
		return entry, "Deleted journal entry #" .. id .. "."
	end)
end

--- Records a milestone observed in the real game into the real character.
-- Returns entry, message; or nil, reason ("duplicate" is silent for callers).
function Actions.RecordRealMilestone(ctx, typeName, data)
	local existed = ctx.store.real.characters[ctx.characterKey] ~= nil
	local char, err = ctx.store:EnsureRealCharacter(ctx.characterKey, ctx.now())
	if not char then
		return nil, err
	end
	local entry, result = Milestones.Record(char, typeName, data, ctx.now())
	if not entry then
		if not existed then
			ctx.store.real.characters[ctx.characterKey] = nil
		end
		return nil, result
	end
	return entry, "Journal: " .. entry.text .. prunedNote(result)
end

--- Records a simulated milestone into simulation data only.
function Actions.RecordSimulatedMilestone(ctx, typeName, data)
	if not ctx.store:IsSimulation() then
		return nil, "Simulated milestones need simulation mode: /dawnward sim on"
	end
	return withCharacter(ctx, function(char)
		data.source = "SIMULATION"
		local entry, result = Milestones.Record(char, typeName, data, ctx.now())
		if not entry then
			if result == "duplicate" then
				return nil, "Not recorded: that milestone is already in the simulated journal (duplicate prevented)."
			end
			return fail(result)
		end
		return entry, "Simulated journal: " .. entry.text .. prunedNote(result)
	end)
end

--- Profile -------------------------------------------------------------------

function Actions.SetField(ctx, key, value)
	return withCharacter(ctx, function(char)
		local ok, result = Character.SetField(char, key, value, ctx.now())
		if not ok then return fail(result) end
		return true, "Saved " .. key .. "."
	end)
end

function Actions.ClearField(ctx, key)
	return withCharacter(ctx, function(char)
		local ok, result = Character.ClearField(char, key, ctx.now())
		if not ok then return fail(result) end
		return true, "Cleared " .. key .. "."
	end)
end

function Actions.SetFieldVisibility(ctx, key, level)
	return withCharacter(ctx, function(char)
		local ok, result = Character.SetFieldVisibility(char, key, level, ctx.now())
		if not ok then return fail(result) end
		return true, key .. " is now " .. level .. "."
	end)
end

--- Facts (canon) --------------------------------------------------------------

function Actions.AddFact(ctx, category, statement, visibility)
	return withCharacter(ctx, function(char)
		local fact, err = Facts.Add(char, { category = category, statement = statement, visibility = visibility },
			nil, ctx.now())
		if not fact then return fail(err) end
		return fact, string.format("Added fact #%d (%s) [%s].", fact.id, Facts.DisplayCategory(fact.category).label,
			fact.visibility)
	end)
end

function Actions.SetFactVisibility(ctx, id, level)
	return withCharacter(ctx, function(char)
		local fact, err = Facts.SetVisibility(char, id, level, ctx.now())
		if not fact then return fail(err) end
		return fact, "Fact #" .. id .. " is now " .. level .. "."
	end)
end

function Actions.RemoveFact(ctx, id)
	return withCharacter(ctx, function(char)
		local fact, err = Facts.Remove(char, id, ctx.now())
		if not fact then return fail(err) end
		return fact, "Removed fact #" .. id .. "."
	end)
end

--- Personality ----------------------------------------------------------------

function Actions.SetPersonality(ctx, axisId, value)
	return withCharacter(ctx, function(char)
		local before = char.personality[axisId] and char.personality[axisId].value
		local entry, err = Personality.Set(char, axisId, value, ctx.now())
		if not entry then return fail(err) end
		-- The development history explains every value, including the player's own.
		Evolution.RecordManual(char, axisId, before, value, ctx.now())
		local axis = Personality.AXIS_BY_ID[axisId]
		return entry, string.format("%s: %d/20 (%s %d - %d %s) [%s].", axisId, value, axis.left, 20 - value, value,
			axis.right, entry.visibility)
	end)
end

function Actions.SetPersonalityVisibility(ctx, axisId, level)
	return withCharacter(ctx, function(char)
		local entry, err = Personality.SetVisibility(char, axisId, level, ctx.now())
		if not entry then return fail(err) end
		return entry, axisId .. " is now " .. level .. "."
	end)
end

function Actions.ClearPersonality(ctx, axisId)
	return withCharacter(ctx, function(char)
		local entry, err = Personality.Clear(char, axisId, ctx.now())
		if not entry then return fail(err) end
		return entry, "Cleared " .. axisId .. "."
	end)
end

--- Living chronicle (v0.4) -------------------------------------------------------

-- Records an event and considers it for a reaction. Returns record, reaction,
-- outcome; or nil, reason ("duplicate" and "not tracked" are quiet).
local function recordEvent(char, category, data, now, play)
	local record, err = GameEvents.Record(char, category, data, now)
	if not record then
		return nil, err
	end
	local reaction, outcome = Reactions.Consider(char, record, now, play)
	return record, reaction, outcome
end

--- Seconds of play on this character's narrative clock, adding the play
-- since the last reading (Core/NarrativeClock.lua).
function Actions.Play(ctx, char)
	return ns.NarrativeClock.Read(char, ctx)
end

--- A gameplay event observed in the real game always goes to the real
-- character, even in simulation mode (like milestones). Story events are
-- recorded only for characters that already use Dawnward (any saved
-- change, or a v0.2 level-up milestone), so upgrading never starts storing
-- data or asking questions on every alt of an account.
function Actions.RecordRealEvent(ctx, category, data)
	if ctx.store.realReadOnly then
		return nil, "saved data is read-only"
	end
	local char = ctx.store.real.characters[ctx.characterKey]
	if not char then
		return nil, "no profile"
	end
	return recordEvent(char, category, data, ctx.now(), Actions.Play(ctx, char))
end

--- Observed reputation standings (from Platform/Observers): records a
-- reputation event for each tier change. The first reading is a silent
-- baseline. Snapshots are kept only for characters that already use
-- Dawnward (nothing is created for an alt just by logging in).
-- Returns the list of records created.
function Actions.ObserveStandings(ctx, factions, context)
	local char = ctx.store.real.characters[ctx.characterKey]
	if not char or ctx.store.realReadOnly then
		return {}
	end
	local created = {}
	for _, change in ipairs(ns.Observed.CompareStandings(char, factions)) do
		for k, v in pairs(context or {}) do
			if change[k] == nil then change[k] = v end
		end
		local record, reaction, outcome = recordEvent(char, "reputation", change, ctx.now(), Actions.Play(ctx, char))
		if record then
			created[#created + 1] = { record = record, reaction = reaction, outcome = outcome }
		end
	end
	return created
end

--- An observed guild reading (conclusive only). Returns record, reaction, outcome or nil.
function Actions.ObserveGuild(ctx, guild, context)
	local char = ctx.store.real.characters[ctx.characterKey]
	if not char or ctx.store.realReadOnly then
		return nil
	end
	local change = ns.Observed.CompareGuild(char, guild)
	if not change then
		return nil
	end
	for k, v in pairs(context or {}) do
		if change[k] == nil then change[k] = v end
	end
	return recordEvent(char, "guild", change, ctx.now(), Actions.Play(ctx, char))
end

--- An observed location (Platform/Observers): logs the visit and records
-- the events it produces (Core/Places.lua). Only the most meaningful one may
-- become a moment; the rest are records only. Real data only, and only for
-- characters that already use Dawnward. Returns the list created, and
-- keeps the decision in ctx.lastLocation for this session.
function Actions.ObserveLocation(ctx, data)
	local char = ctx.store.real.characters[ctx.characterKey]
	if not char or ctx.store.realReadOnly then
		return {}
	end
	local now = ctx.now()
	local play = Actions.Play(ctx, char)
	local created, considered = {}, false
	local steps, diag = ns.Places.Observe(char, data, now, play)
	-- The last decision, for /dawnward dev story status. Session only: never saved.
	ctx.lastLocation = { at = now, play = play, zone = data.zone, subzone = data.subzone, diag = diag,
		created = created }
	for _, step in ipairs(steps) do
		local record = GameEvents.Record(char, step.category, step.data, now)
		if record then
			local reaction, outcome
			if considered then
				record.status = "recorded"
			else
				considered = true
				reaction, outcome = Reactions.Consider(char, record, now, play)
			end
			created[#created + 1] = { record = record, reaction = reaction, outcome = outcome }
		end
	end
	return created
end

--- The player marks a visited place as meaningful to their character, or
-- unmarks it. Nothing else changes: no memory, journal entry or fact is made.
function Actions.MarkPlace(ctx, name, on)
	return withCharacter(ctx, function(char)
		local entry, err = ns.Places.Mark(char, name, on)
		if not entry then
			return nil, "Not changed: " .. err .. "."
		end
		return entry, string.format("%s is %s.", ns.Places.Label(entry),
			on and "now marked as meaningful to your character (private)" or "no longer marked as meaningful")
	end)
end

--- A simulated event, into simulation data only (for testing the story loop).
function Actions.RecordSimulatedEvent(ctx, category, data)
	if not ctx.store:IsSimulation() then
		return nil, "Simulated events need simulation mode: /dawnward sim on"
	end
	return withCharacter(ctx, function(char)
		data.source = "SIMULATION"
		local record, reaction, outcome = recordEvent(char, category, data, ctx.now(), Actions.Play(ctx, char))
		if not record then
			if reaction == "duplicate" then
				return nil, "Not recorded: that event is already in the simulated record (duplicate prevented)."
			end
			return fail(reaction)
		end
		local message = "Simulated " .. GameEvents.Label(category):lower() .. " recorded"
		if outcome == "queued" then
			message = message .. "; a story reaction is waiting (/dawnward story)."
		elseif outcome == "coalesced" then
			message = message .. "; added to the reaction already waiting."
		else
			message = message .. " (no reaction: " .. tostring(outcome) .. ")."
		end
		return record, message
	end)
end

--- choice: { optionId } or { custom }. Returns result, message.
function Actions.Decide(ctx, reactionId, choice)
	return withCharacter(ctx, function(char)
		local result, err = Decisions.Decide(char, reactionId, choice, ctx.now())
		if not result then return fail(err) end
		local parts = { "Decision recorded." }
		if #result.changes > 0 then
			local pending = result.changes[1].status == "pending"
			parts[#parts + 1] = string.format("%d personality change%s %s.", #result.changes,
				#result.changes == 1 and "" or "s", pending and "waiting for your approval (/dawnward develop)"
					or "applied (reversible)")
		end
		if result.entry then
			parts[#parts + 1] = "Private journal draft #" .. result.entry.id .. " written."
		elseif result.draftError then
			parts[#parts + 1] = "No journal draft: " .. result.draftError
		end
		return result, table.concat(parts, " ")
	end)
end

local function reactionAction(fn, done)
	return function(ctx, id)
		return withCharacter(ctx, function(char)
			local r, err = fn(char, id, ctx.now())
			if not r then return fail(err) end
			return r, string.format(done, id)
		end)
	end
end

Actions.PostponeReaction = reactionAction(Reactions.Postpone, "Reaction #%d is kept for later in the Story section.")
Actions.IgnoreReaction = reactionAction(Reactions.Ignore,
	"Reaction #%d stays in the Story section; no more reminders.")
Actions.DismissReaction = reactionAction(Reactions.Dismiss, "Reaction #%d dismissed. The event stays in your record.")

function Actions.ApplyChange(ctx, id)
	return withCharacter(ctx, function(char)
		local change, err = Evolution.Apply(char, id, ctx.now())
		if not change then return fail(err) end
		return change, string.format("Applied: %s is now %d/20 (%s).", change.axis, change.to,
			Evolution.Describe(change))
	end)
end

function Actions.RejectChange(ctx, id)
	return withCharacter(ctx, function(char)
		local change, err = Evolution.Reject(char, id, ctx.now())
		if not change then return fail(err) end
		return change, "Rejected change #" .. id .. ". Nothing changed."
	end)
end

function Actions.ReverseChange(ctx, id)
	return withCharacter(ctx, function(char)
		local change, err = Evolution.Reverse(char, id, ctx.now())
		if not change then return fail(err) end
		return change, string.format("Reversed change #%d: %s is back to %d/20.", id, change.axis,
			char.personality[change.axis].value)
	end)
end

function Actions.ApproveEntry(ctx, id)
	return withCharacter(ctx, function(char)
		local entry, err = Journal.Approve(char, id, ctx.now())
		if not entry then return fail(err) end
		return entry, "Approved journal entry #" .. id .. ". It is still " .. entry.visibility
			.. "; make it public with: /dawnward journal vis " .. id .. " public"
	end)
end

function Actions.SetEntryImportant(ctx, id, on)
	return withCharacter(ctx, function(char)
		local entry, err = Journal.SetImportant(char, id, on, ctx.now())
		if not entry then return fail(err) end
		return entry, "Journal entry #" .. id .. (on and " is now a defining moment." or " is no longer a defining moment.")
	end)
end

-- Story preferences and how each is validated.
local PREFS = {
	frequency = function(v) return ns.StorySchema.FREQUENCY[v] and v or nil end,
	threshold = function(v) local n = tonumber(v); return n and n >= 1 and n <= 3 and n == math.floor(n) and n or nil end,
	approval = function(v) return ns.StorySchema.APPROVAL[v] and v or nil end,
	trp3Style = function(v) return ns.StorySchema.TRP3_STYLES[v] and v or nil end,
	places = function(v) return ns.StorySchema.PLACE_PROMPTS[v] and v or nil end,
	pace = function(v) return ns.NarrativeClock.PACES[v] and v or nil end,
	repeatDays = function(v)
		local n = tonumber(v)
		return n and n >= 0 and n <= 14 and n == math.floor(n) and n or nil
	end,
	drafts = function(v)
		if v == "on" or v == true then return true end
		if v == "off" or v == false then return false end
		return nil
	end,
}
PREFS.flavor, PREFS.card = PREFS.drafts, PREFS.drafts

function Actions.SetStoryPref(ctx, name, value)
	local check = PREFS[name]
	if not check then
		return nil, "Unknown story setting '" .. tostring(name) .. "'."
	end
	local clean = check(value)
	if clean == nil then
		return nil, "Not changed: invalid value for " .. name .. "."
	end
	return withCharacter(ctx, function(char)
		char.story.prefs[name] = clean
		return true, string.format("Story setting %s: %s.", name, tostring(clean))
	end)
end

function Actions.SetTracking(ctx, category, on)
	if not ns.StorySchema.CATEGORIES[category] then
		return nil, "Unknown event category '" .. tostring(category) .. "' (quest, levelup, death, zone, place)."
	end
	return withCharacter(ctx, function(char)
		char.story.prefs.tracking[category] = on and true or false
		return true, string.format("Tracking %s events: %s.", category, on and "on" or "off")
	end)
end

--- Window preferences (account-wide, stored in real data only) ------------------

function Actions.WindowPosition(ctx)
	local ui = ctx.store.real.ui
	return ui and ui.position
end

--- left, top: the window's corner in its own units; scale: the window's
-- scale then (so the position can be converted at another scale).
function Actions.SaveWindowPosition(ctx, left, top, scale)
	if ctx.store.realReadOnly then
		return nil, "saved data is read-only"
	end
	if type(left) ~= "number" or type(top) ~= "number" then
		return nil, "invalid position"
	end
	ctx.store.real.ui = ctx.store.real.ui or {}
	ctx.store.real.ui.position = { left = left, top = top, scale = type(scale) == "number" and scale or nil }
	return true
end

--- The window scale the player chose by resizing (nil: the design's size).
function Actions.WindowScale(ctx)
	local ui = ctx.store.real.ui
	return ui and ui.windowScale
end

--- Saves the chosen window scale; nil resets it to the design's size.
function Actions.SaveWindowScale(ctx, scale)
	if ctx.store.realReadOnly then
		return nil, "saved data is read-only"
	end
	if scale ~= nil and (type(scale) ~= "number" or scale ~= scale or scale <= 0) then
		return nil, "invalid scale"
	end
	ctx.store.real.ui = ctx.store.real.ui or {}
	ctx.store.real.ui.windowScale = scale
	return true
end

--- The player closed the guide (#51): remember it for this character so it
-- does not open by itself again. Creates the character record only if the
-- player already has one or the data is writable; never raises.
function Actions.FinishGuide(ctx)
	if not ctx or ctx.store:ReadOnlyReason() then
		return nil
	end
	return withCharacter(ctx, function(char)
		char.guide = char.guide or {}
		char.guide.done = true
		return true, "Guide closed. Reopen it with the ? button or /dawnward guide."
	end)
end

--- First-time setup (v0.6) ---------------------------------------------------

local function drafts(ctx, create)
	local ui = ctx.store.real.ui
	if not ui and create then
		ui = {}
		ctx.store.real.ui = ui
	end
	if ui and not ui.wizardDrafts and create then
		ui.wizardDrafts = {}
	end
	return ui and ui.wizardDrafts
end

--- This character's unfinished setup draft, or nil (never creates anything).
function Actions.SetupDraft(ctx)
	local list = drafts(ctx, false)
	return list and list[ctx.characterKey]
end

--- Saves an unfinished setup (account-wide, by character key). It does not
-- create a character record. Refused on read-only data.
function Actions.SaveSetupDraft(ctx, draft)
	if ctx.store.realReadOnly then
		return nil, "Saved data is read-only. The draft was not kept."
	end
	local clean = ns.Onboarding.CleanDraft(draft)
	if not clean then
		return nil, "Nothing to keep."
	end
	drafts(ctx, true)[ctx.characterKey] = clean
	return true
end

function Actions.ClearSetupDraft(ctx)
	local list = drafts(ctx, false)
	if list and not ctx.store.realReadOnly then
		list[ctx.characterKey] = nil
	end
end

--- Finish: writes the wizard's choices for the active character and marks
-- setup complete. opts.test (developer preview): the choices are saved,
-- but completion and the real draft are left exactly as they were.
-- Never writes to Total RP 3; profile fields are only added or changed,
-- never cleared. opts.only: the set of keys the player changed (only those
-- are applied); the minimap setting only when it is in that set.
function Actions.CompleteSetup(ctx, values, opts)
	opts = opts or {}
	local ok, message = withCharacter(ctx, function(char)
		local changed = ns.Onboarding.Apply(char, values, ctx.now(), { complete = not opts.test, only = opts.only })
		return changed, opts.test and "Preview choices saved. Setup status was not changed."
			or "Setup complete. Welcome to your chronicle."
	end)
	if not ok then
		return nil, message
	end
	if values.minimap ~= nil and (not opts.only or opts.only.minimap) then
		Actions.SaveMinimap(ctx, { hidden = values.minimap == false })
	end
	if not opts.test then
		Actions.ClearSetupDraft(ctx)
	end
	return ok, message
end

--- Developer reset: forgets only this character's setup completion and
-- draft. Nothing else is touched, and no character record is created.
function Actions.ResetSetup(ctx)
	if ctx.store.realReadOnly then
		return nil, "Saved data is read-only. Nothing was changed."
	end
	local char = ctx.store.real.characters[ctx.characterKey]
	if char then
		char.wizard = {}
	end
	Actions.ClearSetupDraft(ctx)
	return true, "Setup state reset for this character. Its profile, journal and story were not touched."
end

--- The minimap button's settings: { angle, hidden } (never nil).
function Actions.MinimapSettings(ctx)
	local ui = ctx.store.real.ui
	return ui and ui.minimap or {}
end

--- Saves the minimap button's angle (degrees) and/or hidden state.
function Actions.SaveMinimap(ctx, values)
	if ctx.store.realReadOnly then
		return nil, "Saved data is read-only. Nothing was changed."
	end
	ctx.store.real.ui = ctx.store.real.ui or {}
	local m = ctx.store.real.ui.minimap or {}
	if values.angle ~= nil then
		local a = values.angle
		if type(a) ~= "number" or a ~= a then return nil, "invalid angle" end
		m.angle = a % 360
	end
	if values.hidden ~= nil then m.hidden = values.hidden == true or nil end
	ctx.store.real.ui.minimap = m
	return true, m.hidden and "Minimap button hidden. Show it again from Settings or with /dawnward minimap."
		or "Minimap button shown."
end

--- Character Showcase: show the portrait instead of the live model (v0.7).
-- A per-character display choice, stored with the other window preferences
-- (real data only, like the window position): ui.showcase[characterKey].
function Actions.ShowcasePortrait(ctx)
	local ui = ctx.store.real.ui
	local prefs = ui and ui.showcase and ui.showcase[ctx.characterKey]
	return prefs ~= nil and prefs.portrait == true
end

function Actions.SetShowcasePortrait(ctx, on)
	if ctx.store.realReadOnly then
		return nil, "Saved data is read-only. Nothing was changed."
	end
	local ui = ctx.store.real.ui or {}
	ctx.store.real.ui = ui
	ui.showcase = ui.showcase or {}
	-- Only a "yes" is stored; the default (the live model) leaves no trace.
	ui.showcase[ctx.characterKey] = on and { portrait = true } or nil
	if next(ui.showcase) == nil then ui.showcase = nil end
	return true, on and "The showcase shows your portrait." or "The showcase shows your live model."
end

--- Theme (cosmetic only) -----------------------------------------------------

function Actions.SetTheme(ctx, themeId)
	if not Themes.IsValid(themeId) then
		return nil, "Unknown theme '" .. tostring(themeId) .. "'."
	end
	return withCharacter(ctx, function(char)
		char.theme = themeId
		return true, "Theme set to " .. Themes.Get(themeId).name .. "."
	end)
end
