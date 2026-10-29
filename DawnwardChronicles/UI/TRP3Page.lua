-- Settings -> Total RP 3: the sync management page (docs/design/mockups/
-- proposed-trp3-sync.png, approved for v0.7).
--
-- This page only DISPLAYS what the existing /dawnward trp3 commands know and
-- runs the SAME functions they run (Integrations/TRP3/Commands.lua and
-- Sync.lua). It adds no write path and bypasses no guard: every write goes
-- through Sync.RunFeature / Sync.Rollback / Sync.Release with the opt-in,
-- profile binding, version allowlist, default-profile, simulation,
-- read-only, combat and open-editor checks, the backup before every write
-- and the read-back with automatic undo. Opening or refreshing the page
-- only reads (Adapter.Probe, Sync.Check, the public projection).
--
-- Private and Secret items are never shown here, only counted.
local _, ns = ...
local Widgets, MainWindow, Commands = ns.Widgets, ns.MainWindow, ns.Commands

local TRP3Page = {}
ns.TRP3Page = TRP3Page

TRP3Page.FEATURES = {
	{ id = "about", label = "Biography" },
	{ id = "traits", label = "Traits" },
}
local FEATURE_LABEL = { about = "Biography", traits = "Traits" }

TRP3Page.RIGHT_WIDTH = 258
TRP3Page.GAP = 12
TRP3Page.SUMMARY_HEIGHT = 54
TRP3Page.PREVIEW_LINES = 6
TRP3Page.REASON_CHARS = 150
TRP3Page.BACKUP_ROWS = 4

-- Chip text and tone per Sync.Check state (labels follow the command's
-- STATE_LABEL: off, waiting, blocked, conflict, up to date, has changes).
TRP3Page.STATE_CHIP = {
	off = { "Sync off", "muted" },
	deferred = { "Waiting", "muted" },
	blocked = { "Blocked", "danger" },
	conflict = { "Conflict", "danger" },
	noop = { "Up to date", "public" },
	ready = { "Needs your approval", "accent" },
}
local TITLE_PHRASE = {
	off = "sync is off", deferred = "waiting", blocked = "blocked", conflict = "conflict",
	noop = "up to date", ready = "proposed change",
}

TRP3Page.OPTIONAL_TEXT = "Total RP 3 is optional. Dawnward works fully without it: your journal, character, "
	.. "story and chronicle never need it. If you use Total RP 3 3.4.1, this page can keep one Dawnward "
	.. "section of your profile up to date, but only after you turn it on, and only with what you made Public."

TRP3Page.EXPLAIN = {
	about = "Dawnward only writes its own block inside your \"About\" text. Everything you wrote in Total RP 3 "
		.. "yourself stays exactly as it is.",
	traits = "Dawnward only adds and updates its own personality traits, one per Public axis. Preset traits and "
		.. "traits you made yourself are never changed.",
}

TRP3Page.UNSUPPORTED_TEXT = "Not written by Dawnward: name, title, pronouns and the other profile fields; "
	.. "Total RP 3 keeps its own. Only Public facts, stances and defining moments go into the biography block, "
	.. "and Public personality axes into traits."

TRP3Page.BACKUP_NOTE = "A backup is taken before every write, and each write is read back and undone at once if "
	.. "anything differs."

-- WoW reads "|" as an escape code; show player text literally.
local function plain(s)
	return (tostring(s or ""):gsub("|", "||"))
end

local function excerpt(s, n)
	s = tostring(s or ""):gsub("%s+", " ")
	if #s > n then
		s = s:sub(1, n - 3) .. "..."
	end
	return plain(s)
end

local function listText(items)
	if #items == 1 then return items[1] end
	return table.concat(items, ", ", 1, #items - 1) .. " and " .. items[#items]
end

local function plural(n, one, many)
	return n .. " " .. (n == 1 and one or many)
end

-- What is NOT shared, as counts only: never names, statements or titles.
local COUNTED = {
	{ list = "facts", one = "fact", many = "facts" },
	{ list = "personality", one = "personality axis", many = "personality axes", map = true },
	{ list = "journal", one = "journal entry", many = "journal entries" },
	{ list = "history", one = "history entry", many = "history entries" },
	{ list = "family", one = "family entry", many = "family entries" },
}

--- Counts of Private and Secret items (no content). Pure.
function TRP3Page.HiddenCounts(char)
	local counts = { private = {}, secret = {} }
	if not char then
		return counts
	end
	for level in pairs(counts) do
		local view = ns.Projection.Filter(char, { [level] = true })
		for _, c in ipairs(COUNTED) do
			local n = 0
			if c.map then
				for _ in pairs(view[c.list] or {}) do n = n + 1 end
			else
				n = #(view[c.list] or {})
			end
			counts[level][c.list] = n
		end
	end
	return counts
end

--- The "Never shared" sentence, from HiddenCounts. Pure.
function TRP3Page.HiddenText(counts)
	local parts = {}
	for _, level in ipairs({ "private", "secret" }) do
		local items, total = {}, 0
		for _, c in ipairs(COUNTED) do
			local n = counts[level][c.list] or 0
			if n > 0 then
				items[#items + 1] = plural(n, c.one, c.many)
				total = total + n
			end
		end
		if #items > 0 then
			parts[#parts + 1] = listText(items) .. (total == 1 and " is " or " are ")
				.. (level == "private" and "Private" or "Secret")
		end
	end
	local head = #parts > 0 and (table.concat(parts, "; ") .. ".") or "Nothing is Private or Secret yet."
	return head .. " Only items marked Public can be written."
end

--- Summary strip texts. Pure. view = TRP3Commands.Overview (or nil).
function TRP3Page.Summary(status, view)
	local s = {}
	if type(status) ~= "table" then
		s.trp3 = "Status unavailable"
	elseif status.error then
		s.trp3 = "Could not be read safely"
	elseif not status.loaded then
		s.trp3 = status.installed and "Installed · not loaded" or "Not installed · optional"
	else
		local vp = status.versionProfile or {}
		local supported = vp.tiers and vp.tiers.experimentalWrite
		s.trp3 = "Installed · " .. tostring(status.version or "?") .. " · "
			.. (supported and "supported" or "status only")
		s.versionNote = vp.label
	end
	local probe = view and view.probe
	local profile = probe and probe.profile
	local entry = view and view.entry
	local on = entry and (entry.about or entry.traits)
	if not profile then
		s.profile = "None"
	elseif profile.isDefault or (profile.id and profile.id:sub(-1) == "*") then
		s.profile = "\"" .. plain(profile.name or "?") .. "\" · default profile, never written"
	elseif on and entry.profileId ~= profile.id then
		s.profile = "\"" .. plain(profile.name or "?") .. "\" · sync was set up for another profile"
	elseif on then
		local shared = profile.sharedWith
		s.profile = "\"" .. plain(profile.name or "?") .. "\" · "
			.. ((shared and shared > 0) and ("shared with " .. plural(shared, "other character", "other characters"))
				or "this character only")
	else
		s.profile = "\"" .. plain(profile.name or "?") .. "\" · not linked"
	end
	local function state(feature)
		return (entry and entry[feature]) and "on" or "off"
	end
	if entry and entry.about == entry.traits then
		s.sync = (entry.about and "On" or "Off") .. " for Biography and Traits"
	elseif entry then
		s.sync = (state("about") == "on" and "On" or "Off") .. " for Biography · " .. state("traits") .. " for Traits"
	else
		s.sync = "Off for Biography and Traits"
	end
	return s
end

local function deps()
	local ctx = ns.ctx
	return ctx and ctx.trp3Deps and ctx.trp3Deps() or nil
end

local function realChar()
	local ctx = ns.ctx
	return ctx and ctx.store.real.characters[ctx.characterKey] or nil
end

-- Runs a TRP3 action safely: a TRP3 surprise must never break the window.
local function act(fn)
	local ok, message = pcall(fn)
	if not ok then
		message = "Total RP 3 action failed safely: " .. tostring(message)
	end
	MainWindow.SetStatus(message or "")
	MainWindow.Refresh()
	return message
end

local function label(parent, role, wrap)
	return Widgets.Label(parent, nil, wrap, role)
end

local function box(parent, tone)
	local f = CreateFrame("Frame", nil, parent)
	f.bg = ns.Style.Solid(f, "BACKGROUND", -1)
	f.bg:SetAllPoints(f)
	f.edges = ns.Style.Edge(f, "BORDER")
	f.tone = tone
	ns.Style.Register(f, function(b, theme)
		if b.tone == "add" then
			ns.Style.Color(b.bg, ns.Themes.VISIBILITY_COLORS.public, 0.10)
			b.edges:Paint(ns.Themes.VISIBILITY_COLORS.public, 0.45)
		else
			ns.Style.Color(b.bg, theme.background)
			b.edges:Paint(theme.edge, 1)
		end
	end)
	return f
end

--- Builds the page inside parent (the settings page frame). Returns page.
function TRP3Page.Build(parent, width, height)
	local page = { frame = parent, feature = nil, backupRows = {} }
	local inset = 10
	local W = width - 2 * inset
	local leftW = W - TRP3Page.RIGHT_WIDTH - TRP3Page.GAP
	local mainTop = -(TRP3Page.SUMMARY_HEIGHT + 10)
	local mainH = height - TRP3Page.SUMMARY_HEIGHT - 10

	-- Summary strip: TRP3 · linked profile · sync, plus "Experimental".
	local strip = Widgets.Panel(parent)
	strip:SetPoint("TOPLEFT", inset, 0)
	strip:SetSize(W, TRP3Page.SUMMARY_HEIGHT)
	page.strip = strip
	local colW = { 220, 270, W - 14 - 490 }
	local x = 14
	page.columns = {}
	for i, title in ipairs({ "Total RP 3", "Linked profile", "Sync" }) do
		local head = Widgets.Label(strip, "GameFontNormalSmall", false, "eyebrow")
		head:SetPoint("TOPLEFT", x, -10)
		head:SetText(title:upper())
		local value = label(strip, "body", false)
		value:SetPoint("TOPLEFT", x, -26)
		value:SetWidth(colW[i] - 12)
		page.columns[i] = value
		if i < 3 then
			local rule = Widgets.Divider(strip)
			rule:SetSize(1, 34)
			rule:SetPoint("TOPLEFT", x + colW[i] - 8, -10)
		end
		x = x + colW[i]
	end
	-- The header cells double as hover targets for details.
	page.trp3Hover = CreateFrame("Frame", nil, strip)
	page.trp3Hover:SetPoint("TOPLEFT", 0, 0)
	page.trp3Hover:SetSize(colW[1], TRP3Page.SUMMARY_HEIGHT)
	page.experimental = Widgets.Chip(strip, "Experimental", "muted")
	page.experimental:SetPoint("TOPRIGHT", -10, -6)
	Widgets.Tooltip(page.experimental, "Experimental", "Writing to Total RP 3 uses its internals with no official "
		.. "support. It is off unless you turn it on, per character and per profile.")

	-- Left: one feature at a time.
	local card = Widgets.Panel(parent)
	card:SetPoint("TOPLEFT", inset, mainTop)
	card:SetSize(leftW, mainH)
	page.card = card
	local innerW = leftW - 28

	-- Shown instead of the feature view when Total RP 3 is not available.
	page.absent = CreateFrame("Frame", nil, card)
	page.absent:SetAllPoints(card)
	page.absentTitle = Widgets.Label(page.absent, "GameFontNormalLarge", false, "title")
	page.absentTitle:SetPoint("TOPLEFT", 14, -16)
	page.absentTitle:SetText("Total RP 3 is optional")
	page.absentText = label(page.absent, "body", true)
	page.absentText:SetPoint("TOPLEFT", 14, -46)
	page.absentText:SetWidth(innerW)
	page.absentStatus = label(page.absent, "muted", true)
	page.absentStatus:SetPoint("TOPLEFT", 14, -150)
	page.absentStatus:SetWidth(innerW)

	local body = CreateFrame("Frame", nil, card)
	body:SetAllPoints(card)
	page.body = body

	page.nav = Widgets.Segmented(body, TRP3Page.FEATURES, 200, 22, function(id)
		page.feature = id
		MainWindow.Refresh()
	end)
	page.nav.buttons[1]:SetPoint("TOPLEFT", 14, -12)
	page.chip = Widgets.Chip(body, "", "muted")
	page.chip:SetPoint("TOPRIGHT", -14, -13)

	page.title = Widgets.Label(body, "GameFontNormalLarge", false, "title")
	page.title:SetPoint("TOPLEFT", 14, -42)
	page.title:SetWidth(innerW)
	page.explain = label(body, "muted", true)
	page.explain:SetPoint("TOPLEFT", 14, -66)
	page.explain:SetWidth(innerW)
	page.reasons = label(body, "small", true)
	page.reasons:SetPoint("TOPLEFT", 14, -96)
	page.reasons:SetWidth(innerW)
	-- Long guard reasons are shortened on the page; the full text is here.
	page.reasonsHover = CreateFrame("Frame", nil, body)
	page.reasonsHover:SetPoint("TOPLEFT", 14, -96)
	page.reasonsHover:SetSize(innerW, 28)

	page.keep = box(body)
	page.keep:SetPoint("TOPLEFT", 14, -128)
	page.keep:SetSize(innerW, 34)
	page.keepText = label(page.keep, "small", true)
	page.keepText:SetPoint("TOPLEFT", 10, -6)
	page.keepText:SetWidth(innerW - 20)

	page.preview = box(body, "add")
	page.preview:SetPoint("TOPLEFT", 14, -168)
	page.preview:SetSize(innerW, 118)
	page.previewHead = Widgets.Label(page.preview, "GameFontNormalSmall", false, "eyebrow")
	page.previewHead:SetPoint("TOPLEFT", 10, -8)
	page.previewHead:SetText("EXACTLY WHAT WOULD BE WRITTEN · PUBLIC ONLY")
	page.copy = Widgets.Button(page.preview, "Copy text", 90, 20, "ghost")
	page.copy:SetPoint("TOPRIGHT", -6, -4)
	Widgets.Tooltip(page.copy, "Copy text", "Show this text (public facts only) to paste into Total RP 3 "
		.. "yourself. Same as /dawnward trp3 paste. Nothing is written.")
	page.copy:SetScript("OnClick", function()
		Commands.Execute(ns.ctx, "trp3 paste")
	end)
	page.previewText = label(page.preview, "small", true)
	page.previewText:SetPoint("TOPLEFT", 10, -28)
	page.previewText:SetWidth(innerW - 20)

	page.hidden = box(body)
	page.hidden:SetPoint("TOPLEFT", 14, -292)
	page.hidden:SetSize(innerW, 104)
	local hiddenHead = Widgets.Label(page.hidden, "GameFontNormalSmall", false, "eyebrow")
	hiddenHead:SetPoint("TOPLEFT", 10, -8)
	hiddenHead:SetText("NEVER SHARED")
	page.hiddenText = label(page.hidden, "small", true)
	page.hiddenText:SetPoint("TOPLEFT", 10, -24)
	page.hiddenText:SetWidth(innerW - 20)
	page.unsupported = label(page.hidden, "muted", true)
	page.unsupported:SetPoint("TOPLEFT", 10, -58)
	page.unsupported:SetWidth(innerW - 20)
	page.unsupported:SetText(TRP3Page.UNSUPPORTED_TEXT)

	local rule = Widgets.Divider(body)
	rule:SetPoint("BOTTOMLEFT", 14, 44)
	rule:SetPoint("BOTTOMRIGHT", -14, 44)
	page.approve = Widgets.Button(body, "Approve and write", 150, 26, "primary")
	page.approve:SetPoint("BOTTOMLEFT", 14, 10)
	page.notNow = Widgets.Button(body, "Not now", 84, 26, "ghost")
	page.notNow:SetPoint("LEFT", page.approve, "RIGHT", 8, 0)
	page.toggle = Widgets.Button(body, "", 196, 26, "danger")
	page.toggle:SetPoint("BOTTOMRIGHT", -14, 10)

	-- Right column: conflict callout (only when there is one), backups.
	local rightX = inset + leftW + TRP3Page.GAP
	page.conflict = Widgets.Callout(parent, "Conflict")
	page.conflict:SetPoint("TOPLEFT", rightX, mainTop)
	page.conflict:SetSize(TRP3Page.RIGHT_WIDTH, 150)
	page.conflictText = label(page.conflict.inner, "small", true)
	page.conflictText:SetPoint("TOPLEFT", 0, 0)
	page.conflictText:SetWidth(TRP3Page.RIGHT_WIDTH - 28)
	local half = math.floor((TRP3Page.RIGHT_WIDTH - 28 - 6) / 2)
	page.keepYours = Widgets.Button(page.conflict.inner, "Keep yours", half, 24)
	page.keepYours:SetPoint("BOTTOMLEFT", 0, 0)
	page.reclaim = Widgets.Button(page.conflict.inner, "Use Dawnward's", half, 24, "ghost")
	page.reclaim:SetPoint("LEFT", page.keepYours, "RIGHT", 6, 0)

	page.backups = Widgets.Panel(parent, "Backups")
	page.backups:SetSize(TRP3Page.RIGHT_WIDTH, 240)
	local rowW = TRP3Page.RIGHT_WIDTH - 28
	for i = 1, TRP3Page.BACKUP_ROWS do
		local row = Widgets.Button(page.backups.inner, "", rowW, 22, "choice")
		row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
		row.date = label(row, "muted", false)
		row.date:SetPoint("RIGHT", -8, 0)
		row:SetScript("OnClick", function(self)
			page.selectedBackup = self.backupId
			MainWindow.Refresh()
		end)
		page.backupRows[i] = row
	end
	page.noBackups = label(page.backups.inner, "muted", true)
	page.noBackups:SetPoint("TOPLEFT", 0, 0)
	page.noBackups:SetWidth(rowW)
	page.noBackups:SetText("No backups yet. Dawnward takes one before its first write.")
	page.rollback = Widgets.Button(page.backups.inner, "Roll back…", rowW, 24)
	page.rollback:SetPoint("TOPLEFT", 0, -(TRP3Page.BACKUP_ROWS * 24 + 6))
	page.backupNote = label(page.backups.inner, "muted", true)
	page.backupNote:SetPoint("TOPLEFT", page.rollback, "BOTTOMLEFT", 0, -8)
	page.backupNote:SetWidth(rowW)
	page.backupNote:SetText(TRP3Page.BACKUP_NOTE)

	-- Actions: the same functions as /dawnward trp3 ... ----------------------------

	page.approve:SetScript("OnClick", function()
		local feature = page.feature
		act(function()
			local d = deps()
			if not d then return "Total RP 3 sync is not available." end
			local result, why = ns.TRP3Commands.Approve(d, feature)
			if not result then return why end
			return ns.TRP3Commands.ResultText(result)
		end)
	end)
	page.notNow:SetScript("OnClick", function()
		MainWindow.SetStatus("Nothing was written. Automatic sync stays as it is; use Stop syncing to keep Dawnward "
			.. "from writing this later.")
	end)
	page.toggle:SetScript("OnClick", function()
		local feature = page.feature
		local d = deps()
		local entry = d and d.ledger.optIn[d.characterKey]
		local on = entry and entry[feature]
		if on then
			act(function()
				local _, message = ns.TRP3Commands.SetFeature(ns.ctx, d, feature, false)
				return message or "Not changed."
			end)
			return
		end
		-- "trp3 enable <feature>" needs the word confirm; here, the dialog.
		Widgets.Confirm(ns.TRP3Commands.EnableWarning(feature), "Turn on", function()
			act(function()
				local _, message = ns.TRP3Commands.SetFeature(ns.ctx, deps(), feature, true)
				return message or "Not changed."
			end)
		end)
	end)
	local function resolve(choice)
		local feature = page.conflictFeature
		act(function()
			local _, message = ns.TRP3Sync.Resolve(deps(), feature, choice)
			return message
		end)
	end
	page.keepYours:SetScript("OnClick", function() resolve("keep") end)
	page.reclaim:SetScript("OnClick", function() resolve("reclaim") end)
	Widgets.Tooltip(page.keepYours, "Keep yours", "Your version stays and Dawnward stops managing it (sync for it "
		.. "is switched off). Same as /dawnward trp3 resolve <feature> keep.")
	Widgets.Tooltip(page.reclaim, "Use Dawnward's", "Biography: your edited text becomes yours and Dawnward adds a "
		.. "fresh section of its own on the next sync. Traits: Dawnward takes back the traits carrying its own labels. "
		.. "Nothing you wrote is overwritten. Same as /dawnward trp3 resolve <feature> reclaim.")
	page.rollback:SetScript("OnClick", function()
		local id = page.selectedBackup
		local text = id and ("Restore your Total RP 3 section from Dawnward's backup #" .. id .. "?")
			or TRP3Page.ROLLBACK_NEWEST
		Widgets.Confirm(text .. "\n\nThis also undoes any other edits made to that section since then. The current "
			.. "state is backed up first, and automatic sync for it is switched off.\n\n"
			.. ns.TRP3Commands.ROLLBACK_PRIVACY, "Roll back", function()
			act(function()
				local _, message = ns.TRP3Sync.Rollback(deps(), id)
				return message
			end)
		end)
	end)

	function page.Refresh(self)
		TRP3Page.Refresh(self)
	end
	return page
end

TRP3Page.ROLLBACK_NEWEST = "Restore your Total RP 3 section from Dawnward's newest backup for this profile?"

local function keepText(feature, check, view)
	local section = check and check.section
	if feature == "about" then
		if not section then
			return "Your own Total RP 3 text is kept and never edited by Dawnward."
		end
		local record = check.profileId and view.ledgerProfiles and view.ledgerProfiles[check.profileId]
		local own = ns.TRP3AboutBlock.WithoutOwned(section, record and record.about)
		local text
		if own.TE == 1 then
			text = own.T1 and own.T1.TX
		elseif own.TE == 3 then
			text = own.T3 and own.T3.HI and own.T3.HI.TX
		elseif own.TE == 2 then
			return "Your own text (kept, never edited by Dawnward): " .. plural(#(own.T2 or {}), "frame", "frames")
				.. " in your About."
		end
		if not text or text == "" then
			return "Your own text (kept, never edited by Dawnward): your About is empty."
		end
		return "Your own text (kept, never edited by Dawnward): \"" .. excerpt(text, 70) .. "\""
	end
	if not section then
		return "Your own personality traits are kept and never changed by Dawnward."
	end
	local record = check.profileId and view.ledgerProfiles and view.ledgerProfiles[check.profileId]
	local owned = 0
	for _ in pairs(record and record.traits and record.traits.owned or {}) do owned = owned + 1 end
	local own = math.max(0, #(section.PS or {}) - owned)
	return "Your own traits (kept, never changed by Dawnward): " .. plural(own, "trait", "traits") .. "."
end

local function previewText(feature, preview)
	local lines = {}
	if feature == "about" then
		if preview.about == "" then
			return "(Nothing Public yet. Mark facts, stances or important approved story entries Public to "
				.. "include them.)"
		end
		for line in (preview.about .. "\n"):gmatch("([^\n]*)\n") do
			lines[#lines + 1] = plain(line)
		end
	else
		if #preview.traits == 0 then
			return "(No Public personality axes yet. Make an axis Public on the Character page to include it.)"
		end
		for _, t in ipairs(preview.traits) do
			lines[#lines + 1] = plain(string.format("%s %d / %d %s", t.LT, t.V2, 20 - t.V2, t.RT))
		end
	end
	local max = TRP3Page.PREVIEW_LINES
	if #lines > max then
		local more = #lines - (max - 1)
		local shown = {}
		for i = 1, max - 1 do shown[i] = lines[i] end
		shown[max] = "(+" .. more .. " more lines; Copy text shows all)"
		lines = shown
	end
	return table.concat(lines, "\n")
end

local function changesText(feature, check)
	local plan = check.plan
	if plan.changes and #plan.changes > 0 then
		return "Proposed changes: " .. table.concat(plan.changes, ", ") .. "."
	end
	return "Proposed change: " .. tostring(plan.action) .. " the Dawnward "
		.. (feature == "about" and "section" or "traits") .. "."
end

local function reasonsText(feature, check, optedIn)
	local state = check.state
	if state == "ready" and check.plan then
		return changesText(feature, check) .. " Written only when you approve it here, or by the automatic "
			.. "sync you turned on."
	elseif state == "noop" then
		return "Total RP 3 already shows this. Nothing to write."
	elseif state == "off" and not optedIn then
		return "Nothing is written while sync is off. Turn it on below, or copy the text and paste it yourself."
	end
	local stateLabel = ns.TRP3Commands.STATE_LABEL[state] or state
	local text = stateLabel:sub(1, 1):upper() .. stateLabel:sub(2)
	if #check.reasons > 0 then
		text = text .. ": " .. table.concat(check.reasons, "; ")
	end
	return text
end

function TRP3Page.Refresh(page)
	local ctx = ns.ctx
	local status = ctx and ctx.trp3Status and ctx.trp3Status() or nil
	local d = deps()
	local view
	if d and status and status.loaded and not status.error then
		local ok, result = pcall(ns.TRP3Commands.Overview, d)
		if ok then
			view = result
			view.ledgerProfiles = d.ledger.profiles
		else
			page.error = tostring(result)
		end
	end
	page.view = view
	local summary = TRP3Page.Summary(status, view)
	page.columns[1]:SetText(summary.trp3)
	page.columns[2]:SetText(summary.profile)
	page.columns[3]:SetText(summary.sync)
	Widgets.Tooltip(page.trp3Hover, "Total RP 3", summary.versionNote
		and ("This version: " .. summary.versionNote .. ". Dawnward writes only to Total RP 3 versions it has "
			.. "audited; any other version is status only.") or "Detected Total RP 3 status (read-only).")

	local available = view ~= nil
	page.absent:SetShown(not available)
	page.body:SetShown(available)
	page.absentText:SetText(TRP3Page.OPTIONAL_TEXT)
	page.absentStatus:SetText(table.concat(Commands.Trp3Lines(status), "\n"))

	-- Feature: the player's choice, else the first one needing attention.
	if available and not page.feature then
		for _, f in ipairs(TRP3Page.FEATURES) do
			local s = view.checks[f.id].state
			if not page.feature and (s == "conflict" or s == "ready") then page.feature = f.id end
		end
	end
	page.feature = page.feature or "about"
	local feature = page.feature

	-- Conflict callout: the shown feature's conflict first.
	page.conflictFeature = nil
	if available then
		if view.checks[feature].state == "conflict" then
			page.conflictFeature = feature
		else
			for _, f in ipairs(TRP3Page.FEATURES) do
				if not page.conflictFeature and view.checks[f.id].state == "conflict" then
					page.conflictFeature = f.id
				end
			end
		end
	end
	page.conflict:SetShown(page.conflictFeature ~= nil)
	if page.conflictFeature then
		local check = view.checks[page.conflictFeature]
		page.conflict:SetTitle("Conflict on " .. FEATURE_LABEL[page.conflictFeature])
		page.conflictText:SetText(excerpt(check.reasons[1] or "Total RP 3 changed since Dawnward last wrote", 120)
			.. ". Nothing will be overwritten until you choose.")
	end
	page.backups:ClearAllPoints()
	if page.conflictFeature then
		page.backups:SetPoint("TOPLEFT", page.conflict, "BOTTOMLEFT", 0, -TRP3Page.GAP)
	else
		page.backups:SetPoint("TOPLEFT", page.conflict, "TOPLEFT", 0, 0)
	end

	-- Backups for the active profile, newest first (pooled rows).
	local backups = view and view.backups or {}
	local selectedSeen = false
	for i, row in ipairs(page.backupRows) do
		local b = backups[i]
		row:SetShown(b ~= nil)
		row.backupId = b and b.id or nil
		if b then
			row:SetText("#" .. b.id .. " " .. (b.section == "about" and "About" or "Traits") .. " · "
				.. plain(b.reason or ""))
			row.date:SetText(b.at and b.at > 0 and date("%d %b", b.at) or "")
			row:SetSelected(page.selectedBackup == b.id)
			if page.selectedBackup == b.id then selectedSeen = true end
		end
	end
	if not selectedSeen then
		page.selectedBackup = nil
	end
	page.noBackups:SetShown(#backups == 0)
	page.rollback:SetEnabled(#backups > 0)

	if not available then
		return
	end

	page.nav:Select(feature)
	-- Each feature's state on hover, so both are visible from either view.
	for i, f in ipairs(TRP3Page.FEATURES) do
		local c = view.checks[f.id]
		local chipDef = TRP3Page.STATE_CHIP[c.state]
		Widgets.Tooltip(page.nav.buttons[i], f.label .. ": " .. (chipDef and chipDef[1] or c.state),
			#c.reasons > 0 and plain(table.concat(c.reasons, "; ")) or nil)
	end
	local check = view.checks[feature]
	local optedIn = view.entry ~= nil and view.entry[feature] == true
	local chip = TRP3Page.STATE_CHIP[check.state] or { check.state, "muted" }
	page.chip:SetChip(chip[1], chip[2])
	page.title:SetText(FEATURE_LABEL[feature] .. ": " .. (TITLE_PHRASE[check.state] or check.state))
	page.explain:SetText(TRP3Page.EXPLAIN[feature])
	local reasons = reasonsText(feature, check, optedIn)
	page.reasons:SetText(excerpt(reasons, TRP3Page.REASON_CHARS))
	Widgets.Tooltip(page.reasonsHover, TRP3Page.STATE_CHIP[check.state] and TRP3Page.STATE_CHIP[check.state][1]
		or "Status", plain(reasons))
	page.keepText:SetText(keepText(feature, check, view))
	page.previewText:SetText(previewText(feature, view.preview))
	page.hiddenText:SetText(TRP3Page.HiddenText(TRP3Page.HiddenCounts(realChar())))

	-- Approve only for an opted-in feature with a change and no conflict;
	-- the click still goes through every guard in Sync.RunFeature.
	page.approve:SetEnabled(optedIn and check.state == "ready")
	Widgets.Tooltip(page.approve, "Approve and write", optedIn
		and "Writes this change now, through every safety check: backup first, read back, undone at once if "
			.. "anything differs. Same as /dawnward trp3 sync."
		or "Turn on syncing for this first.")
	page.notNow:SetEnabled(check.state == "ready")
	local name = feature == "about" and "biography" or "traits"
	if optedIn then
		page.toggle:SetText("Stop syncing " .. name)
		page.toggle:SetVariant("danger")
	else
		page.toggle:SetText("Enable syncing " .. name .. "…")
		page.toggle:SetVariant("default")
	end
end

