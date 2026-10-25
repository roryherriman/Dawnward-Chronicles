-- /dawnward command handling, independent of the WoW client.
--
-- ctx (built by Platform/Bootstrap.lua, or by tests):
--   store         Store instance
--   characterKey  "Name-Realm"
--   now()         current time in seconds
--   print(line)   output one line to the player
--   version       addon version string
--   client        result of Platform Detect (optional)
--   trp3Status()  read-only TRP3 status table (optional)
--   zone()        current zone name, for simulated milestones (optional)
--   ui            { ShowExport(title, text), ShowImport(), ToggleJournal() } (all optional)
--
-- Anything that deletes or replaces data requires the word "confirm".
local _, ns = ...
local Util, Schema, Character, Projection, Transfer, Journal, Actions, Themes, Facts =
	ns.Util, ns.Schema, ns.Character, ns.Projection, ns.Transfer, ns.Journal, ns.Actions, ns.Themes, ns.Facts

local Commands = {}
ns.Commands = Commands

local SHOW_LIMIT = 180 -- bytes of long text shown per line in chat

local HELP = {
	"Dawnward Chronicles: /dawnward (or /dwc) opens and closes the journal.",
	"  status | show [public] | fields | trp3 | theme [neutral|silverhand|arcane]",
	"  journal list | journal add <text> | journal edit <#> <text> | journal vis <#> <level>",
	"  journal remove <#> confirm",
	"  set <field> <text> | vis <field> public|private|secret | clear <field> confirm",
	"  family add <relation> <name> | family list | family set <#> relation|name|status|notes <text>",
	"  family vis <#> <level> | family remove <#> confirm",
	"  history add <text> | history list | history set <#> when|text <text>",
	"  history vis <#> <level> | history remove <#> confirm",
	"  fact list | fact add <category> <statement> | fact vis <#> <level> | fact remove <#> confirm",
	"  export backup [secrets] [biography] | export share | import | import confirm | import undo",
	"  sim on | sim off | sim copy confirm | sim reset confirm | sim levelup <level>",
}

local function out(ctx, line)
	ctx.print(line)
end

local function preview(text)
	if #text > SHOW_LIMIT then
		return Util.TruncateUtf8(text, SHOW_LIMIT) .. "..."
	end
	return text
end

local function modeLabel(ctx)
	return ctx.store:IsSimulation() and "SIMULATION data" or "real data"
end

--- Returns the character for writing, or nil after telling the player why.
local function writable(ctx)
	local reason = ctx.store:ReadOnlyReason()
	if reason then
		out(ctx, "Saved data is read-only (" .. reason .. "). Nothing was changed.")
		return nil
	end
	local char, err = ctx.store:EnsureCharacter(ctx.characterKey, ctx.now())
	if not char then
		out(ctx, "Cannot save: " .. err)
	end
	return char
end

local function report(ctx, ok, err, success)
	if ok then
		out(ctx, success)
	else
		out(ctx, "Not changed: " .. tostring(err))
	end
end

local function parseId(text)
	local n = tonumber(text)
	if Util.IsPositiveInteger(n) then
		return n
	end
	return nil
end

local function itemLine(listName, item)
	if listName == "family" then
		return string.format("  #%d %s: %s (%s) [%s]%s", item.id, item.relation or "relative", item.name or "?",
			item.status, item.visibility, item.notes and (" - " .. preview(item.notes)) or "")
	end
	return string.format("  #%d %s%s [%s]", item.id, item.when and (item.when .. ": ") or "",
		preview(item.text or ""), item.visibility)
end

local function showCharacter(ctx, char, title)
	out(ctx, title)
	local any = false
	for _, field in ipairs(Schema.FIELDS) do
		local entry = char.fields[field.key]
		if entry then
			out(ctx, string.format("  %s: %s [%s]", field.label, preview(entry.value), entry.visibility))
			any = true
		end
	end
	if not any then
		out(ctx, "  (no profile fields set)")
	end
	for _, listName in ipairs({ "family", "history" }) do
		out(ctx, string.format("%s (%d):", listName == "family" and "Family" or "History", #char[listName]))
		for _, item in ipairs(char[listName]) do
			out(ctx, itemLine(listName, item))
		end
	end
end

--- Handlers -------------------------------------------------------------------

local handlers = {}

handlers.help = function(ctx)
	for _, line in ipairs(HELP) do
		out(ctx, line)
	end
end

handlers.fields = function(ctx)
	local keys = {}
	for _, field in ipairs(Schema.FIELDS) do
		keys[#keys + 1] = field.key .. (field.kind == "long" and "*" or "")
	end
	out(ctx, "Profile fields (* = long text): " .. table.concat(keys, ", "))
	out(ctx, "Family status: living, deceased, missing, unknown")
end

handlers.status = function(ctx)
	out(ctx, "Dawnward Chronicles " .. tostring(ctx.version) .. " - using " .. modeLabel(ctx))
	if ctx.client then
		out(ctx, string.format("Client: %s (interface %s)%s", ctx.client.label, tostring(ctx.client.interface),
			ctx.client.verified and "" or " - not yet verified for this addon"))
	end
	local reason = ctx.store:ReadOnlyReason()
	if reason then
		out(ctx, "Saved data is READ-ONLY: " .. reason)
	end
	local char = ctx.store:GetCharacter(ctx.characterKey)
	if char then
		local c = Character.CountByVisibility(char)
		out(ctx, string.format("Profile: %d public, %d private, %d secret facts", c.public, c.private, c.secret))
	else
		out(ctx, "Profile: none yet. Start with /dawnward set name <your character's name>")
	end
	local f = char and Character.FoundationCounts(char) or { facts = 0, suggestions = 0, biography = false }
	out(ctx, string.format("Foundations: %d facts, %d suggestions, biography stored: %s",
		f.facts, f.suggestions, f.biography and "yes" or "no"))
	handlers.trp3(ctx)
end

--- Read-only TRP3 status as display lines (used by chat and the settings panel).
function Commands.Trp3Lines(status)
	if not status then
		return { "Total RP 3: status unavailable" }
	end
	if status.error then
		return { "Total RP 3: could not be read safely (" .. status.error .. "). Integration disabled." }
	end
	if not status.loaded then
		return { "Total RP 3: " .. (status.installed and "installed but not loaded" or "not installed") }
	end
	local lines = {}
	local vp = status.versionProfile or {}
	lines[#lines + 1] = string.format("Total RP 3 %s: %s", tostring(status.version or "?"), vp.label or "unknown version")
	if status.profile then
		lines[#lines + 1] = string.format("  Active profile: %s%s", status.profile.name or "?",
			status.profile.isDefault and " (TRP3 default profile - Dawnward will never write to it)" or "")
	elseif status.api and not status.api.getCurrentUser then
		lines[#lines + 1] = "  Public API not found; integration unavailable for this version."
	end
	lines[#lines + 1] = "  Dawnward only reads from Total RP 3. It never changes your TRP3 profiles."
	return lines
end

handlers.trp3 = function(ctx)
	for _, line in ipairs(Commands.Trp3Lines(ctx.trp3Status and ctx.trp3Status())) do
		out(ctx, line)
	end
end

handlers.theme = function(ctx, rest)
	local id = Util.NextWord(rest):lower()
	if id == "" then
		local char = Actions.Character(ctx)
		local current = Actions.ThemeOf(char)
		local names = {}
		for _, theme in ipairs(Themes.LIST) do
			names[#names + 1] = theme.id
		end
		out(ctx, "Theme: " .. current.name .. ". Available: " .. table.concat(names, ", ")
			.. ". Themes only change how the journal looks.")
		return
	end
	local _, message = Actions.SetTheme(ctx, id)
	out(ctx, message)
end

local function journalLine(entry)
	local label
	if entry.kind == "event" then
		label = "[auto] "
	else
		label = entry.title and (entry.title .. ": ") or ""
	end
	return string.format("  #%d %s%s [%s]", entry.id, label, preview(entry.text or ""), entry.visibility)
end

handlers.journal = function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	if sub == "" or sub == "list" then
		local char = Actions.Character(ctx)
		if not char or #char.journal == 0 then
			out(ctx, "The journal is empty (" .. modeLabel(ctx) .. ").")
			return
		end
		local entries = Journal.NewestFirst(char)
		out(ctx, string.format("Journal, newest first (%d of %d):", math.min(#entries, 10), #entries))
		for i = 1, math.min(#entries, 10) do
			out(ctx, journalLine(entries[i]))
		end
		return
	end
	if sub == "add" then
		if args == "" then
			out(ctx, "Usage: /dawnward journal add <text>")
			return
		end
		local _, message = Actions.AddNote(ctx, nil, args, nil)
		out(ctx, message)
		return
	end
	local idText, tail = Util.NextWord(args)
	local id = tonumber(idText)
	if not Util.IsPositiveInteger(id) then
		out(ctx, "Usage: /dawnward journal edit|vis|remove <#> ...   (see /dawnward journal list)")
		return
	end
	local message
	if sub == "edit" then
		if tail == "" then
			out(ctx, "Usage: /dawnward journal edit <#> <new text>")
			return
		end
		_, message = Actions.UpdateNote(ctx, id, nil, tail, nil)
	elseif sub == "vis" then
		_, message = Actions.SetEntryVisibility(ctx, id, Util.NextWord(tail):lower())
	elseif sub == "remove" then
		if Util.NextWord(tail):lower() ~= "confirm" then
			out(ctx, string.format("This deletes journal entry #%d. Type: /dawnward journal remove %d confirm", id, id))
			return
		end
		_, message = Actions.RemoveNote(ctx, id)
	else
		message = "Unknown journal command '" .. sub .. "'. Try /dawnward help"
	end
	out(ctx, message)
end

handlers.fact = function(ctx, rest)
	local sub, args = Util.NextWord(rest)
	sub = sub:lower()
	if sub == "" or sub == "list" then
		local char = Actions.Character(ctx)
		if not char or #char.facts == 0 then
			out(ctx, "No facts yet (" .. modeLabel(ctx) .. "). Add one: /dawnward fact add <category> <statement>")
			out(ctx, "Categories: " .. Facts.CategoryList())
			return
		end
		out(ctx, string.format("Facts (%d of %d):", #char.facts, Schema.FOUNDATION.facts))
		for _, group in ipairs(Facts.ByCategory(char)) do
			out(ctx, "  " .. group.category.label .. ":")
			for _, fact in ipairs(group.facts) do
				out(ctx, string.format("    #%d %s [%s]", fact.id, preview(fact.statement), fact.visibility))
			end
		end
		return
	end
	if sub == "add" then
		local category, statement = Util.NextWord(args)
		if category == "" or statement == "" then
			out(ctx, "Usage: /dawnward fact add <category> <statement>   Categories: " .. Facts.CategoryList())
			return
		end
		local _, message = Actions.AddFact(ctx, category:lower(), statement, nil)
		out(ctx, message)
		return
	end
	local idText, tail = Util.NextWord(args)
	local id = parseId(idText)
	if not id or (sub ~= "vis" and sub ~= "remove") then
		out(ctx, "Usage: /dawnward fact list | add <category> <statement> | vis <#> <level> | remove <#> confirm")
		return
	end
	local message
	if sub == "vis" then
		_, message = Actions.SetFactVisibility(ctx, id, Util.NextWord(tail):lower())
	else
		if Util.NextWord(tail):lower() ~= "confirm" then
			out(ctx, string.format("This deletes fact #%d. Type: /dawnward fact remove %d confirm", id, id))
			return
		end
		_, message = Actions.RemoveFact(ctx, id)
	end
	out(ctx, message)
end

handlers.show = function(ctx, rest)
	local char = ctx.store:GetCharacter(ctx.characterKey)
	if not char then
		out(ctx, "No profile yet (" .. modeLabel(ctx) .. "). Start with /dawnward set name <name>")
		return
	end
	if Util.NextWord(rest):lower() == "public" then
		showCharacter(ctx, Projection.GetPublic(char), "Public view - the only facts that can ever be shared:")
	else
		showCharacter(ctx, char, "Profile (" .. modeLabel(ctx) .. "):")
	end
end

handlers.set = function(ctx, rest)
	local key, value = Util.NextWord(rest)
	key = key:lower()
	if key == "" or value == "" then
		out(ctx, "Usage: /dawnward set <field> <text>   (see /dawnward fields)")
		return
	end
	local char = writable(ctx)
	if not char then return end
	local ok, err = Character.SetField(char, key, value, ctx.now())
	local entry = char.fields[key]
	report(ctx, ok, err, ok and string.format("Set %s [%s].", key, entry.visibility))
end

handlers.vis = function(ctx, rest)
	local key, level = Util.NextWord(rest)
	key, level = key:lower(), Util.NextWord(level):lower()
	local char = writable(ctx)
	if not char then return end
	local ok, err = Character.SetFieldVisibility(char, key, level, ctx.now())
	report(ctx, ok, err, "Visibility of " .. key .. " is now " .. level .. ".")
end

handlers.clear = function(ctx, rest)
	local key, confirm = Util.NextWord(rest)
	key = key:lower()
	if Util.NextWord(confirm):lower() ~= "confirm" then
		out(ctx, "This deletes the field. Type: /dawnward clear " .. key .. " confirm")
		return
	end
	local char = writable(ctx)
	if not char then return end
	local ok, err = Character.ClearField(char, key, ctx.now())
	report(ctx, ok, err, "Cleared " .. key .. ".")
end

local function listCommand(listName)
	return function(ctx, rest)
		local sub, args = Util.NextWord(rest)
		sub = sub:lower()
		local label = listName == "family" and "family member" or "history entry"

		if sub == "" or sub == "list" then
			local char = ctx.store:GetCharacter(ctx.characterKey)
			local items = char and char[listName] or {}
			out(ctx, string.format("%s (%d):", listName == "family" and "Family" or "History", #items))
			for _, item in ipairs(items) do
				out(ctx, itemLine(listName, item))
			end
			return
		end

		if sub == "add" then
			local values
			if listName == "family" then
				local relation, name = Util.NextWord(args)
				if relation == "" or name == "" then
					out(ctx, "Usage: /dawnward family add <relation> <name>   e.g. family add mother Ilsa Brightwater")
					return
				end
				values = { relation = relation, name = name }
			else
				if args == "" then
					out(ctx, "Usage: /dawnward history add <text>")
					return
				end
				values = { text = args }
			end
			local char = writable(ctx)
			if not char then return end
			local item, err = Character.AddItem(char, listName, values, ctx.now())
			report(ctx, item, err, item and string.format("Added %s #%d [%s].", label, item.id, item.visibility))
			return
		end

		local idText, tail = Util.NextWord(args)
		local id = parseId(idText)
		if not id then
			out(ctx, "Usage: /dawnward " .. listName .. " " .. sub .. " <#> ...   (see /dawnward " .. listName .. " list)")
			return
		end

		if sub == "set" then
			local field, value = Util.NextWord(tail)
			local char = writable(ctx)
			if not char then return end
			local ok, err = Character.UpdateItem(char, listName, id, field:lower(), value, ctx.now())
			report(ctx, ok, err, string.format("Updated %s #%d.", label, id))
		elseif sub == "vis" then
			local level = Util.NextWord(tail):lower()
			local char = writable(ctx)
			if not char then return end
			local ok, err = Character.SetItemVisibility(char, listName, id, level, ctx.now())
			report(ctx, ok, err, string.format("%s #%d is now %s.", label, id, level))
		elseif sub == "remove" then
			if Util.NextWord(tail):lower() ~= "confirm" then
				out(ctx, string.format("This deletes %s #%d. Type: /dawnward %s remove %d confirm", label, id, listName, id))
				return
			end
			local char = writable(ctx)
			if not char then return end
			local ok, err = Character.RemoveItem(char, listName, id, ctx.now())
			report(ctx, ok, err, string.format("Removed %s #%d.", label, id))
		else
			out(ctx, "Unknown " .. listName .. " command '" .. sub .. "'. Try /dawnward help")
		end
	end
end

handlers.family = listCommand("family")
handlers.history = listCommand("history")

handlers.export = function(ctx, rest)
	local kind, opt = Util.NextWord(rest)
	kind = kind:lower()
	if kind == "" then
		kind = Transfer.KIND_BACKUP
	end
	if kind ~= Transfer.KIND_BACKUP and kind ~= Transfer.KIND_SHARE then
		out(ctx, "Usage: /dawnward export backup [secrets] [biography] | /dawnward export share")
		return
	end
	local char = ctx.store:GetCharacter(ctx.characterKey)
	if not char then
		out(ctx, "Nothing to export yet.")
		return
	end
	local options = {}
	for word in opt:lower():gmatch("%S+") do
		options[word] = true
	end
	local includeSecrets = kind == Transfer.KIND_BACKUP and options.secrets == true
	local includeBiography = kind == Transfer.KIND_BACKUP and options.biography == true
	local text, err = Transfer.Export(char, kind, { includeSecrets = includeSecrets,
		includeBiography = includeBiography, addonVersion = ctx.version })
	if not text then
		out(ctx, "Export failed: " .. tostring(err))
		return
	end
	local title
	if kind == Transfer.KIND_SHARE then
		title = "Share export - public facts only"
	elseif includeSecrets then
		title = "Backup WITH SECRETS - do not share this text"
	else
		title = "Personal backup - includes private facts, not secrets"
	end
	if includeBiography then
		title = title .. " (with stored biography)"
	end
	if ctx.ui and ctx.ui.ShowExport then
		ctx.ui.ShowExport(title, text)
		out(ctx, title .. ": copy it from the window (Ctrl+C).")
	else
		out(ctx, title .. " is ready, but no window is available to show it.")
	end
end

--- Validates pasted text and holds it until "import confirm".
-- Returns ok, message (also printed) so the import window can show it.
function Commands.StageImport(ctx, text)
	ctx.pendingImport = nil
	local plan, err = Transfer.Decode(text)
	if not plan then
		local message = "Import rejected: " .. err
		out(ctx, message)
		return false, message
	end
	if plan.kind ~= Transfer.KIND_BACKUP then
		local message = "Import rejected: share exports are summaries for others to read, not backups."
		out(ctx, message)
		return false, message
	end
	ctx.pendingImport = plan
	local message = "Ready to import " .. Transfer.Describe(plan)
		.. ". This replaces the " .. modeLabel(ctx) .. " profile for this character; "
		.. "the current one is kept for /dawnward import undo."
	out(ctx, message)
	out(ctx, "Type /dawnward import confirm (or press Import) to apply.")
	return true, message
end

handlers.import = function(ctx, rest)
	local sub = Util.NextWord(rest):lower()
	if sub == "" then
		if ctx.ui and ctx.ui.ShowImport then
			ctx.ui.ShowImport()
		else
			out(ctx, "No import window is available.")
		end
		return
	end
	if sub == "confirm" then
		local plan = ctx.pendingImport
		if not plan then
			out(ctx, "Nothing to import. Use /dawnward import and paste an export first.")
			return
		end
		if ctx.store:ReadOnlyReason() then
			out(ctx, "Saved data is read-only (" .. ctx.store:ReadOnlyReason() .. "). Nothing was changed.")
			return
		end
		local current = ctx.store:GetCharacter(ctx.characterKey)
		if not current and not ctx.store:EnsureCharacter(ctx.characterKey, ctx.now()) then
			out(ctx, "Cannot import: no room for another character.")
			return
		end
		local merged, carried = Transfer.MergeForImport(current, plan.character, plan.includesSecrets, ctx.now(),
			plan.includesBiography)
		ctx.store:ReplaceCharacter(ctx.characterKey, merged)
		ctx.pendingImport = nil
		out(ctx, "Imported into " .. modeLabel(ctx) .. "." ..
			(carried > 0 and (" Kept " .. carried .. " existing secret facts.") or "") ..
			" Use /dawnward import undo to go back.")
		return
	end
	if sub == "undo" then
		if ctx.store:ReadOnlyReason() then
			out(ctx, "Saved data is read-only. Nothing was changed.")
			return
		end
		if ctx.store:UndoReplace(ctx.characterKey) then
			out(ctx, "Restored the profile from before the last import. Run undo again to switch back.")
		else
			out(ctx, "There is no earlier profile to restore.")
		end
		return
	end
	out(ctx, "Usage: /dawnward import | import confirm | import undo")
end

handlers.sim = function(ctx, rest)
	local sub, tail = Util.NextWord(rest)
	sub = sub:lower()
	local confirmed = Util.NextWord(tail):lower() == "confirm"
	local store = ctx.store
	if sub == "on" then
		store:SetSimulation(true)
		ctx.pendingImport = nil
		out(ctx, "Simulation mode ON. All changes now go to separate test data; your real profile is untouched.")
	elseif sub == "off" then
		store:SetSimulation(false)
		ctx.pendingImport = nil
		out(ctx, "Simulation mode OFF. Using real data.")
	elseif sub == "copy" then
		if not confirmed then
			out(ctx, "This overwrites this character's simulation profile with a copy of the real one. "
				.. "Type: /dawnward sim copy confirm")
			return
		end
		local ok, err = store:CopyRealToSimulation(ctx.characterKey)
		report(ctx, ok, err, "Copied the real profile into simulation data.")
	elseif sub == "reset" then
		if not confirmed then
			out(ctx, "This deletes ALL simulation data for every character. Type: /dawnward sim reset confirm")
			return
		end
		local ok, err = store:ResetSimulation()
		report(ctx, ok, err, "Simulation data wiped. Real data was not touched.")
	elseif sub == "levelup" then
		-- Lets testers exercise milestone recording and duplicate prevention
		-- without levelling a character. Writes to simulation data only.
		local level = tonumber((Util.NextWord(tail))) -- parentheses: NextWord returns two values
		if not level then
			out(ctx, "Usage: /dawnward sim levelup <level>   (simulation mode only)")
			return
		end
		local _, message = Actions.RecordSimulatedMilestone(ctx, "levelup",
			{ level = level, zone = ctx.zone and ctx.zone() or nil })
		out(ctx, message)
	elseif sub == "" or sub == "status" then
		out(ctx, "Simulation mode is " .. (store:IsSimulation() and "ON" or "OFF") .. ".")
	else
		out(ctx, "Usage: /dawnward sim on | off | copy confirm | reset confirm | levelup <level>")
	end
end

function Commands.Execute(ctx, message)
	local command, rest = Util.NextWord(message)
	command = command:lower()
	if command == "" then
		-- The bare command opens or closes the journal; without a window
		-- (tests, or a UI failure) it falls back to the status report.
		if ctx.ui and ctx.ui.ToggleJournal then
			ctx.ui.ToggleJournal()
			return
		end
		command = "status"
	end
	local handler = handlers[command]
	if not handler then
		out(ctx, "Unknown command '" .. command .. "'. Try /dawnward help")
		return
	end
	handler(ctx, rest)
end
