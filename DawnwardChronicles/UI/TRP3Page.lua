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
-- Private and Secret items are never shown here, only counted (the one
-- exception is the rollback confirmation, which names what an exact restore
-- would bring back, so the player can see the risk before accepting it).
--
-- Mappings tab (v0.8): the first-time connection workflow. It lists every
-- mapping with its ownership selector (Dawnward / Total RP 3 / Off) and the
-- fields Dawnward never synchronises; choices are only staged on the page
-- until "Authorize…" shows the proposed initial sync (Public only) in a
-- confirmation and saves them through Sync.Authorize. It also shows, read
-- only, what Total RP 3 holds against Dawnward's Public value, with an
-- explicit per-field Import into Dawnward (Private by default).
local _, ns = ...
local Widgets, MainWindow, Commands = ns.Widgets, ns.MainWindow, ns.Commands

local TRP3Page = {}
ns.TRP3Page = TRP3Page

TRP3Page.FEATURES = {
	{ id = "about", label = "Biography" },
	{ id = "traits", label = "Traits" },
	{ id = "mappings", label = "Mappings" },
}
local FEATURE_LABEL = { about = "Biography", traits = "Traits", fields = "Profile fields", mappings = "Mappings" }

TRP3Page.MAP_ROW_HEIGHT = 34
TRP3Page.MAP_ROW_GAP = 2
TRP3Page.MAP_TOP = 112
TRP3Page.SELECTOR_WIDTH = 162
TRP3Page.IMPORT_WIDTH = 54

-- Selector choices per mapping: the biography and traits are on or off;
-- a field is managed by Dawnward, by Total RP 3, or not synchronised.
TRP3Page.BLOCK_CHOICES = { { id = "dawnward", label = "Dawnward" }, { id = "off", label = "Off" } }
TRP3Page.FIELD_CHOICES = { { id = "dawnward", label = "Dawnward" }, { id = "trp3", label = "TRP3" },
	{ id = "off", label = "Off" } }

TRP3Page.MAPPINGS_EXPLAIN = "Only Public information, never over your own Total RP 3 text. Nothing changes "
	.. "until you Authorize."

TRP3Page.RIGHT_WIDTH = 258
TRP3Page.GAP = 12
TRP3Page.SUMMARY_HEIGHT = 54
TRP3Page.PREVIEW_LINES = 6
TRP3Page.REASON_CHARS = 150
TRP3Page.BACKUP_ROWS = 3
TRP3Page.BACKUP_ROW_HEIGHT = 36
TRP3Page.BACKUPS_HEIGHT = 256

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

TRP3Page.UNSUPPORTED_TEXT = "Title, race, class, age and homeland are written only if you hand them to "
	.. "Dawnward on the Mappings tab; name, pronouns and the other fields never. Only Public facts, stances and "
	.. "defining moments go into the biography block, and Public personality axes into traits."

TRP3Page.BACKUP_NOTE = "A backup is taken before every write, and each write is read back and undone at once if "
	.. "anything differs. Older backups: /dawnward trp3 backups."

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
	local on = ns.TRP3Commands.AnyManaged(entry)
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
	local fields = 0
	for _, m in ipairs(ns.TRP3FieldPlan.MAPPINGS) do
		if entry and ns.TRP3Ledger.Policy(entry, m.id) == "dawnward" then fields = fields + 1 end
	end
	if fields > 0 then
		s.sync = s.sync .. " · " .. plural(fields, "field", "fields")
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

	page.nav = Widgets.Segmented(body, TRP3Page.FEATURES, 288, 22, function(id)
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

	-- Mappings view (first-time connection, ownership, differences).
	page.map = CreateFrame("Frame", nil, body)
	page.map:SetAllPoints(body)
	page.mapExplain = label(page.map, "muted", true)
	page.mapExplain:SetPoint("TOPLEFT", 14, -66)
	page.mapExplain:SetWidth(innerW)
	page.mapExplain:SetText(TRP3Page.MAPPINGS_EXPLAIN)
	page.sharedWarn = label(page.map, "small", true)
	page.sharedWarn:SetPoint("TOPLEFT", 14, -84)
	page.sharedWarn:SetWidth(innerW)
	page.staged = {}
	page.mapRows = {}
	local detailW = innerW - TRP3Page.SELECTOR_WIDTH - TRP3Page.IMPORT_WIDTH - 12
	for i, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
		local row = CreateFrame("Frame", nil, page.map)
		row:SetSize(innerW, TRP3Page.MAP_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 14, -(TRP3Page.MAP_TOP + (i - 1) * (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP)))
		row.id = id
		row.block = ns.TRP3Ledger.BLOCK_FEATURES[id] == true
		row.name = label(row, "body", false)
		row.name:SetPoint("TOPLEFT", 0, -1)
		row.name:SetWidth(detailW)
		row.detail = label(row, "muted", false)
		row.detail:SetPoint("TOPLEFT", 0, -19)
		row.detail:SetWidth(detailW)
		row.hover = CreateFrame("Frame", nil, row)
		row.hover:SetPoint("TOPLEFT", 0, 0)
		row.hover:SetSize(detailW, TRP3Page.MAP_ROW_HEIGHT)
		local choices = row.block and TRP3Page.BLOCK_CHOICES or TRP3Page.FIELD_CHOICES
		row.selector = Widgets.Segmented(row, choices, TRP3Page.SELECTOR_WIDTH, 20, function(policy)
			TRP3Page.Stage(page, id, policy)
		end)
		row.selector.buttons[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT",
			-(TRP3Page.SELECTOR_WIDTH - math.floor(TRP3Page.SELECTOR_WIDTH / #choices)), 0)
		if not row.block then
			row.import = Widgets.Button(row, "Import", TRP3Page.IMPORT_WIDTH, 20, "ghost")
			row.import:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(TRP3Page.SELECTOR_WIDTH + 6), 0)
			row.import:SetScript("OnClick", function() TRP3Page.AskImport(page, id) end)
		end
		page.mapRows[i] = row
	end
	page.unsupportedNote = label(page.map, "muted", true)
	page.unsupportedNote:SetPoint("TOPLEFT", 14, -(TRP3Page.MAP_TOP + #ns.TRP3Ledger.MAPPINGS
		* (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP) + 4))
	page.unsupportedNote:SetWidth(innerW)
	page.unsupportedNote:SetText(TRP3Page.UnsupportedText())
	page.unsupportedHover = CreateFrame("Frame", nil, page.map)
	page.unsupportedHover:SetAllPoints(page.unsupportedNote)
	local reasons = {}
	for _, u in ipairs(ns.TRP3FieldPlan.UNSUPPORTED) do reasons[#reasons + 1] = u.label .. ": " .. u.reason .. "." end
	Widgets.Tooltip(page.unsupportedHover, "Not synchronised automatically", table.concat(reasons, "\n"))
	page.authorize = Widgets.Button(page.map, "Authorize…", 150, 26, "primary")
	page.authorize:SetPoint("BOTTOMLEFT", 14, 10)
	page.resetChoices = Widgets.Button(page.map, "Reset choices", 110, 26, "ghost")
	page.resetChoices:SetPoint("LEFT", page.authorize, "RIGHT", 8, 0)
	page.authorize:SetScript("OnClick", function() TRP3Page.AskAuthorize(page) end)
	page.resetChoices:SetScript("OnClick", function()
		page.staged = {}
		MainWindow.SetStatus("Choices reset. Nothing was changed.")
		MainWindow.Refresh()
	end)
	page.featureWidgets = { page.explain, page.reasons, page.reasonsHover, page.keep, page.preview, page.hidden,
		page.approve, page.notNow, page.toggle, rule }

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

	-- Each backup is a two-line row: what it is, then when, so the name and
	-- the date never crowd each other in the narrow column.
	page.backups = Widgets.Panel(parent, "Backups")
	page.backups:SetSize(TRP3Page.RIGHT_WIDTH, TRP3Page.BACKUPS_HEIGHT)
	local rowW = TRP3Page.RIGHT_WIDTH - 28
	for i = 1, TRP3Page.BACKUP_ROWS do
		local row = Widgets.Button(page.backups.inner, "", rowW, TRP3Page.BACKUP_ROW_HEIGHT, "choice")
		row:SetPoint("TOPLEFT", 0, -(i - 1) * (TRP3Page.BACKUP_ROW_HEIGHT + 4))
		row.name = label(row, "small", false)
		row.name:SetPoint("TOPLEFT", 10, -4)
		row.name:SetPoint("TOPRIGHT", -10, -4)
		row.name:SetJustifyH("LEFT")
		row.date = label(row, "muted", false)
		row.date:SetPoint("BOTTOMLEFT", 10, 4)
		row.date:SetPoint("BOTTOMRIGHT", -10, 4)
		row.date:SetJustifyH("LEFT")
		Widgets.Tooltip(row, "Backup", "")
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
	local rollW = math.floor((rowW - 6) * 0.55)
	page.rollback = Widgets.Button(page.backups.inner, "Roll back…", rollW, 24)
	page.rollback:SetPoint("TOPLEFT", 0, -(TRP3Page.BACKUP_ROWS * (TRP3Page.BACKUP_ROW_HEIGHT + 4) + 6))
	page.exact = Widgets.Button(page.backups.inner, "Exact restore…", rowW - rollW - 6, 24, "ghost")
	page.exact:SetPoint("LEFT", page.rollback, "RIGHT", 6, 0)
	Widgets.Tooltip(page.rollback, "Roll back (safe)", "Restores your own text from the backup; Dawnward's part is "
		.. "rebuilt from what is Public now. Same as /dawnward trp3 rollback [#] confirm.")
	Widgets.Tooltip(page.exact, "Exact restore", "Restores the section exactly as it was, including Dawnward "
		.. "content that may no longer be Public. Same as /dawnward trp3 rollback [#] exact confirm.")
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
			if choice == "reclaim" and ns.ctx and ns.ctx.trp3RequestSync then
				ns.ctx.trp3RequestSync()
			end
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
	page.rollback:SetScript("OnClick", function() TRP3Page.AskRollback(page, "own") end)
	page.exact:SetScript("OnClick", function() TRP3Page.AskRollback(page, "exact") end)

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
		if not own then
			return "Your own text is kept and never edited by Dawnward (Dawnward's section was changed in Total RP 3, "
				.. "so it is not shown separately)."
		end
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

	-- Feature: the player's choice, else the first one needing attention,
	-- else the Mappings tab while nothing is set up yet (first connection).
	if available and not page.feature then
		for _, f in ipairs(TRP3Page.FEATURES) do
			local c = view.checks[f.id]
			if not page.feature and c and (c.state == "conflict" or c.state == "ready") then page.feature = f.id end
		end
		if not page.feature and not ns.TRP3Commands.AnyManaged(view.entry) then
			page.feature = "mappings"
		end
	end
	page.feature = page.feature or "about"
	local feature = page.feature

	-- Conflict callout: the shown feature's conflict first, then any field.
	page.conflictFeature = nil
	if available then
		if view.checks[feature] and view.checks[feature].state == "conflict" and feature ~= "fields" then
			page.conflictFeature = feature
		else
			for _, f in ipairs({ "about", "traits" }) do
				if not page.conflictFeature and view.checks[f].state == "conflict" then
					page.conflictFeature = f
				end
			end
		end
		for _, m in ipairs(ns.TRP3FieldPlan.MAPPINGS) do
			if not page.conflictFeature and view.fieldConflicts[m.id] then
				page.conflictFeature = m.id
			end
		end
	end
	page.conflict:SetShown(page.conflictFeature ~= nil)
	if page.conflictFeature then
		local fieldMap = ns.TRP3FieldPlan.BY_ID[page.conflictFeature]
		local reason = fieldMap and view.fieldConflicts[page.conflictFeature]
			or view.checks[page.conflictFeature].reasons[1]
		page.conflict:SetTitle("Conflict on " .. (fieldMap and fieldMap.label or FEATURE_LABEL[page.conflictFeature]))
		page.conflictText:SetText(excerpt(reason or "Total RP 3 changed since Dawnward last wrote", 120)
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
			local name = "#" .. b.id .. " " .. (b.section == "about" and "About" or "Characteristics") .. " · "
				.. plain(b.reason or "")
			local when = b.at and b.at > 0 and date("%d %b %Y, %H:%M", b.at) or "Date unknown"
			row:SetText("")
			row.name:SetText(name)
			row.date:SetText(when)
			Widgets.Tooltip(row, name, when .. ". Select it, then Roll back… to restore it.")
			row:SetSelected(page.selectedBackup == b.id)
			if page.selectedBackup == b.id then selectedSeen = true end
		end
	end
	if not selectedSeen then
		page.selectedBackup = nil
	end
	page.noBackups:SetShown(#backups == 0)
	page.rollback:SetEnabled(#backups > 0)
	page.exact:SetEnabled(#backups > 0)

	if not available then
		return
	end

	page.nav:Select(feature)
	-- Each feature's state on hover, so every one is visible from any view.
	for i, f in ipairs(TRP3Page.FEATURES) do
		local c = view.checks[f.id] or (f.id == "mappings" and view.checks.fields)
		local chipDef = TRP3Page.STATE_CHIP[c.state]
		Widgets.Tooltip(page.nav.buttons[i], f.label .. ": " .. (chipDef and chipDef[1] or c.state),
			#c.reasons > 0 and plain(table.concat(c.reasons, "; ")) or nil)
	end
	local mappings = feature == "mappings"
	page.map:SetShown(mappings)
	for _, w in ipairs(page.featureWidgets) do
		w:SetShown(not mappings)
	end
	if mappings then
		TRP3Page.RefreshMappings(page, view)
		return
	end
	local check = view.checks[feature]
	local optedIn = view.bound and view.policies[feature] == "dawnward"
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

--- Mappings ------------------------------------------------------------------

--- The unsupported-fields note (names only; FieldPlan.UNSUPPORTED, with the
-- reasons, is its tooltip). Pure.
function TRP3Page.UnsupportedText()
	return "Never written by Dawnward: first and last name, short title, pronouns, faith, occupation, appearance, "
		.. "summary, Currently and RP status, other characteristics (hover for why). Copy text pastes them yourself."
end

--- The policy shown for a mapping: the staged choice, else the saved one.
function TRP3Page.Shown(page, id)
	local view = page.view
	return page.staged[id] or (view and view.policies[id]) or ns.TRP3Ledger.Policy(nil, id)
end

--- Stages a choice (nothing is saved until Authorize).
function TRP3Page.Stage(page, id, policy)
	local saved = page.view and page.view.policies[id]
	page.staged[id] = (policy ~= saved) and policy or nil
	MainWindow.SetStatus(next(page.staged) and "Choice noted. Nothing changes until you Authorize."
		or "No pending changes.")
	MainWindow.Refresh()
end

-- The differences row of a field, or nil.
local function diffRow(view, id)
	for _, row in ipairs(view.differences and view.differences.rows or {}) do
		if row.id == id then return row end
	end
	return nil
end

-- What a Dawnward-managed field would do on the first sync (Public only).
local function fieldProposal(view, m)
	local public
	for _, f in ipairs(view.preview.fields or {}) do
		if f.id == m.id then public = f.value end
	end
	local row = diffRow(view, m.id)
	local current = row and row.trp3
	if row and row.unwritable then
		return "not writable: " .. excerpt(row.unwritable, 80)
	end
	if not public then
		return "nothing Public to write"
	elseif current == nil then
		return "writes \"" .. excerpt(public, 40) .. "\""
	elseif current == public then
		return "already shows the same text (stays yours)"
	end
	return "Total RP 3 has your own value: paused until you choose, never overwritten"
end

--- One mapping row's text: name line and detail line. Pure (from view).
function TRP3Page.RowText(page, id)
	local view = page.view
	local m = ns.TRP3FieldPlan.BY_ID[id]
	local policy = TRP3Page.Shown(page, id)
	local staged = page.staged[id] ~= nil
	local name, detail
	if not m then
		name = FEATURE_LABEL[id]
		local check = view.checks[id]
		if policy == "dawnward" then
			local chipDef = TRP3Page.STATE_CHIP[check.state]
			detail = staged and "Dawnward's own block, from Public data (after you authorize)"
				or ("Managed by Dawnward · " .. (chipDef and chipDef[1] or check.state))
		else
			detail = "Not synchronised · Total RP 3 keeps yours"
		end
		return name, detail
	end
	name = m.label .. " → " .. m.trp3
	local row = diffRow(view, id)
	local conflict = view.fieldConflicts[id]
	local risk = view.risks and view.risks[id]
	if staged and policy ~= "dawnward" and risk then
		detail = "Dawnward's old value will be removed from TRP3 first (no longer Public)"
	elseif policy == "off" then
		detail = "Not synchronised"
	elseif conflict then
		detail = "Paused: " .. excerpt(conflict, 60)
	elseif policy == "dawnward" and staged then
		detail = fieldProposal(view, m)
	elseif row and row.unwritable and policy == "dawnward" then
		detail = "Not writable: " .. excerpt(row.unwritable, 60)
	elseif row then
		local mine = row.dawnward and ("\"" .. excerpt(row.dawnward, 22) .. "\"")
			or (row.hidden and "not Public" or "empty")
		detail = "TRP3: " .. (row.trp3 and ("\"" .. excerpt(row.trp3, 22) .. "\"") or "empty") .. " · Yours: " .. mine
			.. (row.differ and "" or " · same")
	else
		detail = policy == "dawnward" and "Managed by Dawnward" or "Managed by Total RP 3"
	end
	return name, detail
end

function TRP3Page.RefreshMappings(page, view)
	local managed, total = 0, 0
	for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
		total = total + 1
		if TRP3Page.Shown(page, id) == "dawnward" then managed = managed + 1 end
	end
	page.chip:SetChip(next(page.staged) and "Not saved yet" or (managed .. " of " .. total .. " by Dawnward"),
		next(page.staged) and "accent" or "muted")
	page.title:SetText("Mappings: who keeps each part up to date")
	local shared = view.probe.profile and view.probe.profile.sharedWith
	if shared and shared > 0 then
		page.sharedWarn:SetText("Warning: this Total RP 3 profile is shared with "
			.. plural(shared, "other character", "other characters")
			.. "; they all show what Dawnward writes, and only one character per profile can manage each item.")
	elseif not view.probe.experimental.allowed then
		page.sharedWarn:SetText("Writing is not possible right now: "
			.. excerpt(table.concat(view.probe.experimental.reasons, "; "), 110))
	else
		page.sharedWarn:SetText("Profile \"" .. plain(view.probe.profile and view.probe.profile.name or "?")
			.. "\" is used by this character only.")
	end
	for _, row in ipairs(page.mapRows) do
		local name, detail = TRP3Page.RowText(page, row.id)
		row.name:SetText(name)
		row.detail:SetText(detail)
		row.selector:Select(TRP3Page.Shown(page, row.id))
		local m = ns.TRP3FieldPlan.BY_ID[row.id]
		Widgets.Tooltip(row.hover, name, m and ("Total RP 3 field " .. m.key .. " (MSP " .. m.msp .. "). "
			.. (m.risk == "high" and "Players usually write this themselves in Total RP 3; it stays managed by "
				.. "Total RP 3 unless you choose otherwise. " or "")
			.. "Dawnward writes it only from your Public " .. m.label .. ", only while Total RP 3 still holds the "
			.. "value Dawnward last wrote.") or TRP3Page.EXPLAIN[row.id])
		if row.import then
			local diff = diffRow(view, row.id)
			row.import:SetEnabled(diff ~= nil and diff.importable == true)
			Widgets.Tooltip(row.import, "Import into Dawnward", "Copies Total RP 3's " .. m.trp3 .. " into your "
				.. "Dawnward " .. m.label .. " as a Private value (you confirm first). Never automatic.")
		end
	end
	page.authorize:SetEnabled(next(page.staged) ~= nil)
	page.resetChoices:SetEnabled(next(page.staged) ~= nil)
end

--- The confirmation text for the staged choices: what the first sync would
-- write (Public only), what stops, and the warnings. Pure (from page.view).
function TRP3Page.AuthorizeText(page)
	local view = page.view
	local lines = { "Authorize these Total RP 3 choices for profile \""
		.. plain(view.probe.profile and view.probe.profile.name or "?") .. "\"?", "" }
	for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
		local policy = page.staged[id]
		if policy then
			local m = ns.TRP3FieldPlan.BY_ID[id]
			local itemLabel = m and m.label or FEATURE_LABEL[id]
			if policy == "dawnward" then
				local what
				if m then
					what = fieldProposal(view, m)
				elseif id == "about" then
					what = view.preview.about == "" and "nothing Public yet" or "adds Dawnward's own block to your About"
				else
					what = #view.preview.traits == 0 and "nothing Public yet"
						or ("adds " .. plural(#view.preview.traits, "trait", "traits") .. " of its own")
				end
				lines[#lines + 1] = "+ " .. itemLabel .. ": managed by Dawnward - " .. what
			else
				lines[#lines + 1] = "- " .. itemLabel .. ": " .. ns.TRP3Sync.POLICY_LABEL[policy]
				local risk = view.risks and view.risks[id]
				if risk then
					lines[#lines + 1] = "  ! " .. plain(risk.reason) .. ". It will be removed from Total RP 3 first "
						.. "(a backup is taken). To leave it showing, use /dawnward trp3 field " .. id .. " "
						.. policy .. " keep confirm."
				end
			end
		end
	end
	local shared = view.probe.profile and view.probe.profile.sharedWith
	if shared and shared > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "This profile is shared with " .. plural(shared, "other character", "other characters")
			.. "; they will show the same content."
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "EXPERIMENTAL: uses Total RP 3 internals with no official support. Only Public "
		.. "information is written, a backup is taken before every write, and every write can be rolled back."
	return table.concat(lines, "\n")
end

function TRP3Page.AskAuthorize(page)
	if not next(page.staged) or not page.view then
		return
	end
	Widgets.Confirm(TRP3Page.AuthorizeText(page), "Authorize", function()
		act(function()
			local d = deps()
			if not d then return "Total RP 3 sync is not available." end
			local ok, message = ns.TRP3Sync.Authorize(d, page.staged)
			if ok then
				page.staged = {}
				if ns.ctx.trp3RequestSync then ns.ctx.trp3RequestSync() end
			end
			return message
		end)
	end)
end

function TRP3Page.AskImport(page, id)
	local m = ns.TRP3FieldPlan.BY_ID[id]
	local row = page.view and diffRow(page.view, id)
	if not m or not row or not row.importable then
		return
	end
	Widgets.Confirm("Copy Total RP 3's " .. m.trp3 .. " \"" .. plain(row.trp3) .. "\" into your Dawnward "
		.. m.label .. "?\n\nIt is saved as Private; change its visibility on the Character page if you want it "
		.. "shared. Nothing is written to Total RP 3.", "Import", function()
		act(function()
			local _, message = ns.TRP3Commands.Import(ns.ctx, id, "private")
			return message
		end)
	end)
end

--- The rollback confirmation for a mode ("own" or "exact"), naming what an
-- exact restore would bring back that is no longer Public.
function TRP3Page.RollbackText(preview, mode, id)
	local head = id and ("Restore your Total RP 3 section from Dawnward's backup #" .. id .. "?")
		or TRP3Page.ROLLBACK_NEWEST
	local lines = { head, "" }
	if mode == "own" then
		lines[#lines + 1] = "Safe restore: your own text comes back from the backup; Dawnward's part is rebuilt from "
			.. "what is Public now. Other edits made to that section since then are undone. The current state is "
			.. "backed up first."
	else
		lines[#lines + 1] = "Exact restore: the section comes back exactly as it was, including what Dawnward "
			.. "wrote then. Other edits made since are undone, the current state is backed up first, and automatic "
			.. "sync for that section is switched off."
		lines[#lines + 1] = ""
		lines[#lines + 1] = ns.TRP3Commands.ROLLBACK_PRIVACY
	end
	if preview and mode == "exact" then
		lines[#lines + 1] = ""
		for _, line in ipairs(ns.TRP3Commands.RollbackRiskLines(preview, 6)) do
			lines[#lines + 1] = plain(line)
		end
	end
	return table.concat(lines, "\n")
end

function TRP3Page.AskRollback(page, mode)
	local id = page.selectedBackup
	local d = deps()
	if not d then return end
	local ok, preview, why = pcall(ns.TRP3Sync.RollbackPreview, d, id)
	if not ok or not preview then
		MainWindow.SetStatus(tostring(ok and why or preview))
		return
	end
	if mode == "own" and not preview.ownPossible then
		MainWindow.SetStatus("Your own text cannot be separated from this backup (" .. tostring(preview.ownReason)
			.. "). Use Exact restore… if you want it back as it was.")
		return
	end
	Widgets.Confirm(TRP3Page.RollbackText(preview, mode, id),
		mode == "exact" and (#preview.items > 0 and "Restore, including these" or "Restore exactly") or "Roll back",
		function()
			act(function()
				local _, message = ns.TRP3Sync.Rollback(deps(), id, mode)
				return message
			end)
		end)
end
