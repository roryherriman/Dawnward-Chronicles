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
	{ id = "overview", label = "Overview" },
	{ id = "about", label = "Biography" },
	{ id = "traits", label = "Traits" },
	{ id = "mappings", label = "Mappings" },
}
local FEATURE_LABEL = { about = "Biography", traits = "Traits", fields = "Profile fields", mappings = "Mappings",
	misc = "Additional information", glance = "At First Glance", overview = "Overview" }

-- Overview (v0.9): the connected-profile screen. Its choices, each a
-- segmented control writing one story preference (Actions.SetStoryPref).
TRP3Page.OVERVIEW_CHOICES = {
	{ key = "trp3About", label = "About page", items = { { id = "auto", label = "Auto" },
		{ id = "profile", label = "Profile" }, { id = "summary", label = "Summary" } } },
	{ key = "trp3Layout", label = "Template", items = { { id = "current", label = "Keep" },
		{ id = "text", label = "Text" }, { id = "frames", label = "Frames" }, { id = "sections", label = "Sections" } } },
	{ key = "trp3Style", label = "Style", items = { { id = "neutral", label = "Neutral" },
		{ id = "silverhand", label = "Silver Hand" }, { id = "arcane", label = "Arcane" } } },
}
TRP3Page.OVERVIEW_ROW = 22     -- one status line
TRP3Page.OVERVIEW_LABEL = 150  -- the status label column

-- Layout (v0.8, proposed-trp3-sync.png / TRP3Sync.dc.html). The page fills
-- the settings page: the summary strip on top, then the feature card on the
-- left and the right column (conflict callout, backups) 16 px beside it.
-- Mapping rows are two lines: the name with its selector and Import on the
-- first, the detail across the full width on the second. Each selector item
-- is wide enough for "Dawnward" in bold 14 (about 74 px with its insets).
TRP3Page.MAP_ROW_HEIGHT = 37
TRP3Page.MAP_ROW_GAP = 2
TRP3Page.MAP_TOP = 116
TRP3Page.SELECTOR_WIDTH = 240
TRP3Page.SELECTOR_HEIGHT = 20
TRP3Page.IMPORT_WIDTH = 60

-- Selector choices per mapping: the biography and traits are on or off;
-- a field is managed by Dawnward, by Total RP 3, or not synchronised.
TRP3Page.BLOCK_CHOICES = { { id = "dawnward", label = "Dawnward" }, { id = "off", label = "Off" } }
TRP3Page.FIELD_CHOICES = { { id = "dawnward", label = "Dawnward" }, { id = "trp3", label = "TRP3" },
	{ id = "off", label = "Off" } }

TRP3Page.MAPPINGS_EXPLAIN = "Choose who keeps each part up to date. Only Public information is written, never "
	.. "over your own Total RP 3 text, and nothing changes until you Authorize."

TRP3Page.RIGHT_WIDTH = 258
TRP3Page.GAP = 12          -- between the callout and the backups
TRP3Page.COLUMN_GAP = 16   -- between the feature card and the right column
TRP3Page.STRIP_GAP = 12    -- below the summary strip
TRP3Page.SUMMARY_HEIGHT = 62
TRP3Page.CARD_PAD = 18
TRP3Page.PREVIEW_LINES = 4
TRP3Page.REASON_CHARS = 150
TRP3Page.BACKUP_ROWS = 3
TRP3Page.BACKUP_ROW_HEIGHT = 30
TRP3Page.BACKUPS_HEIGHT = 254
TRP3Page.CONFLICT_HEIGHT = 172
TRP3Page.ACTION_HEIGHT = 36   -- Approve and write, Not now, Stop syncing
TRP3Page.LINE = 17            -- one line of 14 px text

-- Chip text and tone per Sync.Check state (labels follow the command's
-- STATE_LABEL: off, waiting, blocked, conflict, up to date, has changes).
TRP3Page.STATE_CHIP = {
	off = { "Sync off", "muted" },
	deferred = { "Waiting", "muted" },
	blocked = { "Blocked", "danger" },
	conflict = { "Conflict", "danger" },
	noop = { "Up to date", "public" },
	ready = { "Needs your approval", "waiting" },
}
local TITLE_PHRASE = {
	off = "sync is off", deferred = "waiting", blocked = "blocked", conflict = "conflict",
	noop = "up to date", ready = "proposed change",
}

TRP3Page.OPTIONAL_TEXT = "Total RP 3 is optional. Dawnward works fully without it: your journal, character, "
	.. "story and chronicle never need it. If you use Total RP 3 3.4.1, Dawnward keeps your Total RP 3 profile "
	.. "up to date from your Dawnward character once you connect it here."

TRP3Page.EXPLAIN = {
	about = "Dawnward only writes its own block inside your \"About\" text. Everything you wrote in Total RP 3 "
		.. "yourself stays exactly as it is.",
	traits = "Dawnward only adds and updates its own personality traits, one per Public axis. Preset traits and "
		.. "traits you made yourself are never changed.",
	glance = "Dawnward only writes the At First Glance entries you wrote for it (/dawnward trp3 glance), into "
		.. "free slots. Slots you filled in Total RP 3 are never changed.",
}

TRP3Page.UNSUPPORTED_TEXT = "Title, race, class, age and homeland: only if you hand them over on Mappings; "
	.. "name, pronouns and the other fields never."
TRP3Page.UNSUPPORTED_DETAIL = "Only Public facts, stances and defining moments go into the biography block, and "
	.. "Public personality axes into traits. Title, race, class, age and homeland are written only if you hand them "
	.. "to Dawnward on the Mappings tab; name, pronouns and the other fields never."

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
		s.profile = "\"" .. plain(profile.name or "?") .. "\" · sync paused: another profile is connected"
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

-- A label in a Dawnward style (default "meta", 14) with a colour role.
local function label(parent, role, wrap, style)
	local fs = Widgets.Label(parent, style or "meta", wrap, ns.Style.TEXT[role] and role or nil)
	if role and not ns.Style.TEXT[role] then
		Widgets.SetTextRole(fs, role) -- a derived tone (navText, ...)
	end
	return fs
end

-- A paragraph capped at maxLines (the full text belongs in a tooltip).
local function paragraph(parent, role, width, maxLines, style)
	local fs = label(parent, role, true, style)
	fs:SetWidth(width)
	fs:SetMaxLines(maxLines)
	return fs
end

-- One line that never wraps; the client cuts it with "..." when too long.
local function oneLine(parent, role, width, style)
	local fs = label(parent, role, false, style)
	fs:SetWidth(width)
	return fs
end

-- A hover area over a region, for the full text of a shortened one.
local function hoverOver(parent, region)
	local h = CreateFrame("Frame", nil, parent)
	h:SetAllPoints(region)
	return h
end

local Style = ns.Style
local WHITE = { 1, 1, 1 }

-- The design's two diff boxes, painted from shared tones (no local tint):
--   "plain" (kept text, never shared): the input well and the track edge
--   "add"   (what would be written, Public only): the Public chip's fill and
--           edge (Widgets.ChipColors), the same colours as a Public chip
local function box(parent, kind)
	local f = CreateFrame("Frame", nil, parent)
	f.bg = Style.Solid(f, "BACKGROUND", -1)
	f.bg:SetAllPoints(f)
	f.edges = Style.Edge(f, "BORDER")
	f.kind = kind or "plain"
	Style.Register(f, function(b, theme)
		if b.kind == "add" then
			local fill, edge = Widgets.ChipColors(ns.Themes.VISIBILITY_COLORS.public, theme, theme.surface)
			Style.Color(b.bg, fill)
			b.edges:Paint(edge, 1)
		else
			local tones = Style.Tones(theme)
			Style.Color(b.bg, tones.field)
			b.edges:Paint(tones.track, 1)
		end
	end)
	return f
end

--- The colour of the text inside the "add" box: the Public colour, lighter
-- (the design's #BFE9D5 on #132820). Pure.
function TRP3Page.AddTextColor()
	return Style.Mix(ns.Themes.VISIBILITY_COLORS.public, WHITE, 0.35)
end

-- The conflict callout in the design's amber ("needs you"): a warm dark fill,
-- the waiting chip's edge and an amber title. Local until Widgets.Callout
-- takes a tone (proposal in docs/design/audit/settings-setup-trp3.md).
local function paintAmber(callout)
	local amber = ns.Themes.STATUS_COLORS.waiting
	Style.Register(callout, function(p, theme)
		local _, edge = Widgets.ChipColors(amber, theme, theme.surface)
		Style.Color(p.bg, Style.Mix(theme.background, amber, 0.05))
		p.edges:Paint(edge, 1)
	end)
	if callout.glow then callout.glow:Hide() end
	Style.Register(callout.title, function(fs) Style.TextColor(fs, amber) end)
end

--- Builds the page inside parent (the settings page frame). Returns page.
function TRP3Page.Build(parent, width, height)
	local page = { frame = parent, feature = nil, backupRows = {} }
	local W = width
	local leftW = W - TRP3Page.RIGHT_WIDTH - TRP3Page.COLUMN_GAP
	local mainTop = -(TRP3Page.SUMMARY_HEIGHT + TRP3Page.STRIP_GAP)
	local mainH = height - TRP3Page.SUMMARY_HEIGHT - TRP3Page.STRIP_GAP
	local P = TRP3Page.CARD_PAD
	local LINE = TRP3Page.LINE
	page.width, page.height, page.leftWidth, page.mainHeight = W, height, leftW, mainH

	-- Summary strip: TRP3 · linked profile · sync, plus "Experimental".
	local strip = Widgets.Panel(parent)
	strip:SetPoint("TOPLEFT", 0, 0)
	strip:SetSize(W, TRP3Page.SUMMARY_HEIGHT)
	page.strip = strip
	page.experimental = Widgets.Chip(strip, "Experimental", "muted")
	page.experimental:SetPoint("RIGHT", -16, 0)
	Widgets.Tooltip(page.experimental, "Experimental", "Writing to Total RP 3 uses its internals with no official "
		.. "support. It is off unless you turn it on, per character and per profile.")
	local chipW = page.experimental:GetWidth()
	local colW = { 188, 240 }
	colW[3] = W - 32 - colW[1] - colW[2] - chipW - 12
	page.columnWidths = colW
	local x = 16
	page.columns, page.columnHovers = {}, {}
	for i, title in ipairs({ "Total RP 3", "Linked profile", "Sync" }) do
		local head = Widgets.Label(strip, "GameFontNormalSmall", false, "eyebrow")
		head:SetPoint("TOPLEFT", x, -12)
		head:SetText(title:upper())
		local value = oneLine(strip, "body", colW[i] - 18, "body")
		value:SetPoint("TOPLEFT", x, -31)
		page.columns[i] = value
		page.columnHovers[i] = hoverOver(strip, value)
		if i < 3 then
			local rule = Widgets.Divider(strip)
			rule:SetSize(1, 34)
			rule:SetPoint("TOPLEFT", x + colW[i] - 9, -14)
		end
		x = x + colW[i]
	end
	-- The first column doubles as the hover target for version details.
	page.trp3Hover = page.columnHovers[1]

	-- Left: one feature at a time.
	local card = Widgets.Panel(parent)
	card:SetPoint("TOPLEFT", 0, mainTop)
	card:SetSize(leftW, mainH)
	page.card = card
	local innerW = leftW - 2 * P
	page.innerWidth = innerW

	-- Shown instead of the feature view when Total RP 3 is not available.
	page.absent = CreateFrame("Frame", nil, card)
	page.absent:SetAllPoints(card)
	page.absentTitle = Widgets.Label(page.absent, "GameFontNormalLarge", false, "title")
	page.absentTitle:SetPoint("TOPLEFT", P, -18)
	page.absentTitle:SetText("Total RP 3 is optional")
	page.absentText = label(page.absent, "reading", true, "reading")
	page.absentText:SetPoint("TOPLEFT", P, -50)
	page.absentText:SetWidth(innerW)
	page.absentStatus = label(page.absent, "muted", true)
	page.absentStatus:SetPoint("TOPLEFT", P, -170)
	page.absentStatus:SetWidth(innerW)

	local body = CreateFrame("Frame", nil, card)
	body:SetAllPoints(card)
	page.body = body

	page.nav = Widgets.Segmented(body, TRP3Page.FEATURES, #TRP3Page.FEATURES * 92, Style.CONTROL.compact, function(id)
		page.feature = id
		MainWindow.Refresh()
	end)
	page.nav.buttons[1]:SetPoint("TOPLEFT", P, -16)
	page.chip = Widgets.Chip(body, "", "muted")
	page.chip:SetPoint("TOPRIGHT", -P, -19)
	page.chip:SetMaxWidth(innerW - #TRP3Page.FEATURES * 92 - 12)

	page.title = Widgets.Label(body, "GameFontNormalLarge", false, "title")
	page.title:SetPoint("TOPLEFT", P, -58)
	page.title:SetWidth(innerW)
	page.explain = paragraph(body, "muted", innerW, 2)
	page.explain:SetPoint("TOPLEFT", P, -86)
	page.reasons = oneLine(body, "body", innerW)
	page.reasons:SetPoint("TOPLEFT", P, -122)
	-- The status line is one line on the page; the full text is here.
	page.reasonsHover = CreateFrame("Frame", nil, body)
	page.reasonsHover:SetPoint("TOPLEFT", P, -122)
	page.reasonsHover:SetSize(innerW, LINE)

	page.keep = box(body, "plain")
	page.keep:SetPoint("TOPLEFT", P, -146)
	page.keep:SetSize(innerW, 2 * LINE + 8)
	page.keepText = paragraph(page.keep, "navText", innerW - 20, 2)
	page.keepText:SetPoint("TOPLEFT", 10, -4)

	page.preview = box(body, "add")
	page.preview:SetPoint("TOPLEFT", P, -194)
	page.preview:SetSize(innerW, 28 + TRP3Page.PREVIEW_LINES * 16 + 8)
	page.previewHead = Widgets.Label(page.preview, "GameFontNormalSmall", false, "eyebrow")
	page.previewHead:SetPoint("TOPLEFT", 10, -9)
	page.previewHead:SetText("WHAT WOULD BE WRITTEN · PUBLIC ONLY")
	Style.Register(page.previewHead, function(fs) Style.TextColor(fs, ns.Themes.VISIBILITY_COLORS.public) end)
	page.copy = Widgets.Button(page.preview, "Copy text", 92, 24, "ghost")
	page.copy:SetPoint("TOPRIGHT", -5, -4)
	Widgets.Tooltip(page.copy, "Copy text", "Show this text (public facts only) to paste into Total RP 3 "
		.. "yourself. Same as /dawnward trp3 paste. Nothing is written.")
	page.copy:SetScript("OnClick", function()
		Commands.Execute(ns.ctx, "trp3 paste")
	end)
	page.previewText = paragraph(page.preview, nil, innerW - 20, TRP3Page.PREVIEW_LINES)
	page.previewText:SetPoint("TOPLEFT", 10, -30)
	Style.Register(page.previewText, function(fs) Style.TextColor(fs, TRP3Page.AddTextColor()) end)

	page.hidden = box(body, "plain")
	page.hidden:SetPoint("TOPLEFT", P, -300)
	page.hidden:SetSize(innerW, 100)
	local hiddenHead = Widgets.Label(page.hidden, "GameFontNormalSmall", false, "eyebrow")
	hiddenHead:SetPoint("TOPLEFT", 10, -9)
	hiddenHead:SetText("NEVER SHARED")
	page.hiddenText = paragraph(page.hidden, "navText", innerW - 20, 2)
	page.hiddenText:SetPoint("TOPLEFT", 10, -28)
	page.unsupported = paragraph(page.hidden, "muted", innerW - 20, 2)
	page.unsupported:SetPoint("TOPLEFT", 10, -64)
	page.unsupported:SetText(TRP3Page.UNSUPPORTED_TEXT)
	page.hiddenHover = hoverOver(page.hidden, page.hidden)
	Widgets.Tooltip(page.hiddenHover, "Never shared", TRP3Page.UNSUPPORTED_DETAIL)

	local A = TRP3Page.ACTION_HEIGHT
	local rule = Widgets.Divider(body)
	rule:SetPoint("BOTTOMLEFT", P, 14 + A + 8)
	rule:SetPoint("BOTTOMRIGHT", -P, 14 + A + 8)
	page.actionRule = rule
	page.approve = Widgets.Button(body, "Approve and write", 150, A, "primary")
	page.approve:SetPoint("BOTTOMLEFT", P, 14)
	page.notNow = Widgets.Button(body, "Not now", 90, A, "ghost")
	page.notNow:SetPoint("LEFT", page.approve, "RIGHT", 8, 0)
	page.toggle = Widgets.Button(body, "", 194, A, "danger")
	page.toggle:SetPoint("BOTTOMRIGHT", -P, 14)

	-- Mappings view (first-time connection, ownership, differences).
	page.map = CreateFrame("Frame", nil, body)
	page.map:SetAllPoints(body)
	page.mapExplain = paragraph(page.map, "muted", innerW, 2)
	page.mapExplain:SetPoint("TOPLEFT", P, -58)
	page.mapExplain:SetText(TRP3Page.MAPPINGS_EXPLAIN)
	page.sharedWarn = oneLine(page.map, "body", innerW)
	page.sharedWarn:SetPoint("TOPLEFT", P, -96)
	page.sharedWarnHover = hoverOver(page.map, page.sharedWarn)
	page.staged = {}
	page.mapRows = {}
	page.mapPage = 1
	local S, I = TRP3Page.SELECTOR_WIDTH, TRP3Page.IMPORT_WIDTH
	local nameW = innerW - S - I - 12
	-- v0.9: more mappings than fit at once, so the rows are paged; the
	-- page size follows the card's height (rows, the one-line note and the
	-- Authorize row; TRP3Page.MapPageSize).
	local perPage = TRP3Page.MapPageSize(mainH)
	page.mapPerPage = perPage
	for i, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
		local slot = (i - 1) % perPage
		local row = CreateFrame("Frame", nil, page.map)
		row:SetSize(innerW, TRP3Page.MAP_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", P, -(TRP3Page.MAP_TOP + slot * (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP)))
		row.id = id
		row.slot = slot
		row.mapPage = math.floor((i - 1) / perPage) + 1
		row.block = ns.TRP3Ledger.BLOCK_FEATURES[id] == true
		if slot > 0 then
			row.rule = Widgets.Divider(row)
			row.rule:SetPoint("TOPLEFT", 0, TRP3Page.MAP_ROW_GAP)
			row.rule:SetPoint("TOPRIGHT", 0, TRP3Page.MAP_ROW_GAP)
		end
		row.name = oneLine(row, "body", nameW, "body")
		row.name:SetPoint("TOPLEFT", 0, -1)
		-- The detail runs the full width under the name and the selector.
		row.detail = oneLine(row, "muted", innerW)
		row.detail:SetPoint("TOPLEFT", 0, -20)
		row.hover = CreateFrame("Frame", nil, row)
		row.hover:SetPoint("TOPLEFT", 0, 0)
		row.hover:SetSize(nameW, TRP3Page.MAP_ROW_HEIGHT)
		local choices = row.block and TRP3Page.BLOCK_CHOICES or TRP3Page.FIELD_CHOICES
		row.selector = Widgets.Segmented(row, choices, S, TRP3Page.SELECTOR_HEIGHT, function(policy)
			TRP3Page.Stage(page, id, policy)
		end)
		row.selector.buttons[1]:SetPoint("TOPLEFT", row, "TOPLEFT", innerW - S, 0)
		if ns.TRP3FieldPlan.BY_ID[id] then
			row.import = Widgets.Button(row, "Import", I, TRP3Page.SELECTOR_HEIGHT, "ghost")
			row.import:SetPoint("TOPLEFT", row, "TOPLEFT", innerW - S - 6 - I, 0)
			row.import:SetScript("OnClick", function() TRP3Page.AskImport(page, id) end)
		end
		page.mapRows[i] = row
	end
	local rowsEnd = TRP3Page.MAP_TOP + math.min(perPage, #ns.TRP3Ledger.MAPPINGS)
		* (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP) - TRP3Page.MAP_ROW_GAP
	page.unsupportedNote = oneLine(page.map, "muted", innerW)
	page.unsupportedNote:SetPoint("TOPLEFT", P, -(rowsEnd + 4))
	page.unsupportedNote:SetText(TRP3Page.UnsupportedText())
	page.unsupportedHover = hoverOver(page.map, page.unsupportedNote)
	local reasons = {}
	for _, u in ipairs(ns.TRP3FieldPlan.UNSUPPORTED) do reasons[#reasons + 1] = u.label .. ": " .. u.reason .. "." end
	Widgets.Tooltip(page.unsupportedHover, "Not synchronised automatically", table.concat(reasons, "\n"))
	page.authorize = Widgets.Button(page.map, "Authorize…", 150, Style.CONTROL.compact, "primary")
	page.authorize:SetPoint("BOTTOMLEFT", P, 14)
	page.resetChoices = Widgets.Button(page.map, "Reset choices", 120, Style.CONTROL.compact, "ghost")
	page.resetChoices:SetPoint("LEFT", page.authorize, "RIGHT", 8, 0)
	page.authorize:SetScript("OnClick", function() TRP3Page.AskAuthorize(page) end)
	page.resetChoices:SetScript("OnClick", function()
		page.staged = {}
		MainWindow.SetStatus("Choices reset. Nothing was changed.")
		MainWindow.Refresh()
	end)
	-- The pager (right of the Authorize row): ‹ Page n of m ›.
	page.mapPages = math.ceil(#ns.TRP3Ledger.MAPPINGS / perPage)
	page.mapNext = Widgets.Button(page.map, "\226\128\186", 30, Style.CONTROL.compact, "ghost")
	page.mapNext:SetPoint("BOTTOMRIGHT", -P, 14)
	page.mapPrev = Widgets.Button(page.map, "\226\128\185", 30, Style.CONTROL.compact, "ghost")
	page.mapPrev:SetPoint("RIGHT", page.mapNext, "LEFT", -86, 0)
	page.mapPageLabel = oneLine(page.map, "muted", 80, "small")
	page.mapPageLabel:SetPoint("RIGHT", page.mapNext, "LEFT", -4, 0)
	page.mapPageLabel:SetJustifyH("CENTER")
	page.mapPrev:SetScript("OnClick", function()
		page.mapPage = math.max(1, page.mapPage - 1)
		MainWindow.Refresh()
	end)
	page.mapNext:SetScript("OnClick", function()
		page.mapPage = math.min(page.mapPages, page.mapPage + 1)
		MainWindow.Refresh()
	end)
	Widgets.Tooltip(page.mapPrev, "Previous", "The previous mappings.")
	Widgets.Tooltip(page.mapNext, "Next", "More mappings.")
	TRP3Page.BuildOverview(page, P, innerW)
	page.featureWidgets = { page.title, page.explain, page.reasons, page.reasonsHover, page.keep, page.preview,
		page.hidden, page.approve, page.notNow, page.toggle, rule }

	-- Right column: conflict callout (only when there is one), backups.
	local RW = TRP3Page.RIGHT_WIDTH
	local rightX = leftW + TRP3Page.COLUMN_GAP
	local colInner = RW - 2 * Widgets.PANEL_PAD
	page.conflict = Widgets.Callout(parent, "Conflict")
	page.conflict:SetPoint("TOPLEFT", rightX, mainTop)
	page.conflict:SetSize(RW, TRP3Page.CONFLICT_HEIGHT)
	paintAmber(page.conflict)
	page.conflictText = paragraph(page.conflict.inner, "reading", colInner, 5)
	page.conflictText:SetPoint("TOPLEFT", 0, 0)
	page.conflictHover = hoverOver(page.conflict.inner, page.conflictText)
	local half = math.floor((colInner - 6) / 2)
	page.keepYours = Widgets.Button(page.conflict.inner, "Keep yours", half, Style.CONTROL.compact)
	page.keepYours:SetPoint("BOTTOMLEFT", 0, 0)
	page.reclaim = Widgets.Button(page.conflict.inner, "Use Dawnward's", colInner - half - 6, Style.CONTROL.compact,
		"ghost")
	page.reclaim:SetPoint("LEFT", page.keepYours, "RIGHT", 6, 0)

	-- Each backup is one selectable row: what it is on the left, the short
	-- date on the right (the design's "About · before last write   27 Oct");
	-- the full name and date are its tooltip.
	page.backups = Widgets.Panel(parent, "Backups")
	page.backups:SetSize(RW, TRP3Page.BACKUPS_HEIGHT)
	local rowH = TRP3Page.BACKUP_ROW_HEIGHT
	for i = 1, TRP3Page.BACKUP_ROWS do
		local row = Widgets.Button(page.backups.inner, "", colInner, rowH, "choice")
		row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 4))
		row.date = oneLine(row, "muted", 52, "small")
		row.date:SetPoint("RIGHT", -8, 0)
		row.date:SetJustifyH("RIGHT")
		row.date:SetJustifyV("MIDDLE")
		row.name = oneLine(row, "body", colInner - 8 - 52 - 16)
		row.name:SetPoint("LEFT", 8, 0)
		row.name:SetJustifyV("MIDDLE")
		Widgets.Tooltip(row, "Backup", "")
		row:SetScript("OnClick", function(self)
			page.selectedBackup = self.backupId
			MainWindow.Refresh()
		end)
		page.backupRows[i] = row
	end
	page.noBackups = paragraph(page.backups.inner, "muted", colInner, 3)
	page.noBackups:SetPoint("TOPLEFT", 0, 0)
	page.noBackups:SetText("No backups yet. Dawnward takes one before its first write.")
	local listH = TRP3Page.BACKUP_ROWS * (rowH + 4) - 4
	local rollW = math.floor((colInner - 6) / 2)
	page.rollback = Widgets.Button(page.backups.inner, "Roll back…", rollW, Style.CONTROL.compact)
	page.rollback:SetPoint("TOPLEFT", 0, -(listH + 8))
	page.exact = Widgets.Button(page.backups.inner, "Exact restore…", colInner - rollW - 6, Style.CONTROL.compact,
		"ghost")
	page.exact:SetPoint("LEFT", page.rollback, "RIGHT", 6, 0)
	Widgets.Tooltip(page.rollback, "Roll back (safe)", "Restores your own text from the backup; Dawnward's part is "
		.. "rebuilt from what is Public now. Same as /dawnward trp3 rollback [#] confirm.")
	Widgets.Tooltip(page.exact, "Exact restore", "Restores the section exactly as it was, including Dawnward "
		.. "content that may no longer be Public. Same as /dawnward trp3 rollback [#] exact confirm.")
	page.backupNote = paragraph(page.backups.inner, "muted", colInner, 4, "small")
	page.backupNote:SetPoint("TOPLEFT", page.rollback, "BOTTOMLEFT", 0, -8)
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
		local own = ns.TRP3AboutDoc.Strip(section, record and record.about)
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
	Widgets.Tooltip(page.columnHovers[2], "Linked profile", summary.profile)
	Widgets.Tooltip(page.columnHovers[3], "Sync", summary.sync)

	local available = view ~= nil
	page.absent:SetShown(not available)
	page.body:SetShown(available)
	page.absentText:SetText(TRP3Page.OPTIONAL_TEXT)
	page.absentStatus:SetText(table.concat(Commands.Trp3Lines(status), "\n"))

	-- Feature: the player's choice, else the Overview when the connection
	-- itself needs the player (default profile, a profile another character
	-- keeps, or a switched profile), else the first one needing attention,
	-- else the Mappings tab while nothing is set up yet (first connection).
	local state = available and view.connection and view.connection.state
	if available and not page.feature and (state == "default" or state == "linked" or state == "switched") then
		page.feature = "overview"
	end
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
		for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
			if not page.conflictFeature and ns.TRP3Sync.MappingOf(id) and view.fieldConflicts[id] then
				page.conflictFeature = id
			end
		end
	end
	page.conflict:SetShown(page.conflictFeature ~= nil)
	if page.conflictFeature then
		local fieldMap = ns.TRP3Sync.MappingOf(page.conflictFeature)
		local reason = fieldMap and view.fieldConflicts[page.conflictFeature]
			or view.checks[page.conflictFeature].reasons[1]
		page.conflict:SetTitle("Conflict on " .. (fieldMap and fieldMap.label or FEATURE_LABEL[page.conflictFeature]))
		page.conflictText:SetText(excerpt(reason or "Total RP 3 changed since Dawnward last wrote", 120)
			.. ". Nothing will be overwritten until you choose.")
		Widgets.Tooltip(page.conflictHover, page.conflict.title:GetText(), plain(reason or
			"Total RP 3 changed since Dawnward last wrote") .. ". Nothing will be overwritten until you choose.")
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
			row.date:SetText(TRP3Page.ShortDate(b.at))
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
		if c then
			local chipDef = TRP3Page.STATE_CHIP[c.state]
			Widgets.Tooltip(page.nav.buttons[i], f.label .. ": " .. (chipDef and chipDef[1] or c.state),
				#c.reasons > 0 and plain(table.concat(c.reasons, "; ")) or nil)
		else
			Widgets.Tooltip(page.nav.buttons[i], f.label, "Your connected profile at a glance.")
		end
	end
	local mappings = feature == "mappings"
	local overview = feature == "overview"
	page.map:SetShown(mappings)
	page.overview:SetShown(overview)
	for _, w in ipairs(page.featureWidgets) do
		w:SetShown(not mappings and not overview)
	end
	if mappings then
		TRP3Page.RefreshMappings(page, view)
		return
	end
	if overview then
		TRP3Page.RefreshOverview(page, view)
		return
	end
	Widgets.Tooltip(page.hiddenHover, "Never shared", TRP3Page.HiddenText(TRP3Page.HiddenCounts(realChar()))
		.. "\n\n" .. TRP3Page.UNSUPPORTED_DETAIL)
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

--- "27 Oct" for a backup row ("?" when unknown); the full date is its tooltip.
--- Overview (v0.9) ----------------------------------------------------------------

-- A feature's state as a short phrase ("Up to date", "Sync off", ...).
local function stateText(check)
	if not check then return "Not available" end
	local chipDef = TRP3Page.STATE_CHIP[check.state]
	return chipDef and chipDef[1] or check.state
end

--- When Dawnward last wrote to this profile (from its log), or nil.
function TRP3Page.LastWrite(log)
	for i = #(log or {}), 1, -1 do
		local line = log[i]
		if line.text and line.text:find("(version ", 1, true) and line.at and line.at > 0 then
			return line.at
		end
	end
	return nil
end

--- The Overview's status lines: { { label, value }, ... }. Pure (from view).
function TRP3Page.OverviewLines(view, char, characterKey)
	local lines = {}
	local function add(name, value) lines[#lines + 1] = { name, value } end
	local profile = view.probe.profile
	local shared = profile and profile.sharedWith or 0
	local c = view.connection or {}
	local kind = shared > 0 and (" · shared with " .. plural(shared, "other character", "other characters"))
		or " · this character only"
	if c.state == "default" then
		kind = " · Total RP 3's default profile, never written"
	elseif c.state == "linked" then
		kind = " · already connected to " .. plain(c.linkedBy)
	elseif c.state == "switched" then
		kind = " · not the connected profile"
	end
	add("Active profile", profile and profile.name and (plain(profile.name) .. kind) or "None readable")
	local managed, total, conflicts = 0, 0, 0
	for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
		total = total + 1
		if view.bound and view.policies[id] == "dawnward" then managed = managed + 1 end
		if view.fieldConflicts[id] then conflicts = conflicts + 1 end
	end
	for _, f in ipairs({ "about", "traits" }) do
		if view.checks[f] and view.checks[f].state == "conflict" then conflicts = conflicts + 1 end
	end
	if c.state == "switched" then
		add("Connected character", "Paused · connected to " .. (c.connectedName and ("\"" .. plain(c.connectedName)
			.. "\"") or "another profile") .. ", not the active one")
	else
		add("Connected character", managed > 0 and (tostring(characterKey) .. " · " .. managed .. " of " .. total
			.. " items kept up to date") or "Not connected")
	end
	local last = TRP3Page.LastWrite(view.log)
	add("Last update", last and date("%d %b %Y, %H:%M", last) or "Nothing written yet")
	local prefs = char and char.story and char.story.prefs or {}
	local public = ns.TRP3Sync.ApplySettings({}, char)
	local layout = ({ current = "your Total RP 3 template", text = "template 1", frames = "template 2 (frames)",
		sections = "template 3 (sections)" })[prefs.trp3Layout or "current"]
	add("Biography", stateText(view.checks.about) .. " · " .. (ns.TRP3Sync.UsesProfile(public)
		and "whole story and profile" or "summary block") .. " in " .. layout)
	add("Identity and details", stateText(view.checks.fields))
	add("Personality", stateText(view.checks.traits))
	add("Additional information", stateText(view.checks.misc))
	add("Conflicts", conflicts == 0 and "None" or (plural(conflicts, "item waits", "items wait")
		.. " for your choice (Mappings tab)"))
	return lines
end

function TRP3Page.BuildOverview(page, P, innerW)
	local o = CreateFrame("Frame", nil, page.body)
	o:SetAllPoints(page.body)
	o:Hide()
	page.overview = o
	page.overviewTitle = Widgets.Label(o, "GameFontNormalLarge", false, "title")
	page.overviewTitle:SetPoint("TOPLEFT", P, -58)
	page.overviewTitle:SetText("Your Total RP 3 profile")
	page.overviewRows = {}
	local R, LW = TRP3Page.OVERVIEW_ROW, TRP3Page.OVERVIEW_LABEL
	for i = 1, 8 do
		local y = -(88 + (i - 1) * R)
		local name = oneLine(o, "muted", LW - 8)
		name:SetPoint("TOPLEFT", P, y)
		local value = oneLine(o, "body", innerW - LW)
		value:SetPoint("TOPLEFT", P + LW, y)
		local hover = hoverOver(o, value)
		page.overviewRows[i] = { name = name, value = value, hover = hover }
	end
	local top = 88 + 8 * R + 10
	page.overviewChoices = {}
	for i, choice in ipairs(TRP3Page.OVERVIEW_CHOICES) do
		local y = -(top + (i - 1) * (TRP3Page.SELECTOR_HEIGHT + 10))
		local name = oneLine(o, "body", LW - 8, "body")
		name:SetPoint("TOPLEFT", P, y - 2)
		name:SetText(choice.label)
		local width = #choice.items * 86
		local seg = Widgets.Segmented(o, choice.items, width, TRP3Page.SELECTOR_HEIGHT, function(id)
			act(function()
				local _, message = ns.Actions.SetStoryPref(ns.ctx, choice.key, id)
				return message
			end)
		end)
		seg.buttons[1]:SetPoint("TOPLEFT", o, "TOPLEFT", P + LW, y)
		seg.key = choice.key
		page.overviewChoices[i] = seg
	end
	-- The connection (v0.9): what is connected or what stops it, under the
	-- choices; the primary and second buttons change with the state
	-- (TRP3Page.ConnectionButtons) and Refresh connection reads Total RP 3 again.
	local B = TRP3Page.CONNECTION_BUTTONS
	page.connectionNote = paragraph(o, "body", innerW, 2)
	page.connectionNote:SetPoint("TOPLEFT", P, -TRP3Page.CONNECTION_NOTE_TOP)
	page.connectAll = Widgets.Button(o, "Connect everything…", B.primary, Style.CONTROL.compact, "primary")
	page.connectAll:SetPoint("BOTTOMLEFT", P, 14)
	page.connectAll:SetScript("OnClick", function() TRP3Page.RunConnectionAction(page, page.connectAll.action) end)
	page.previewProfile = Widgets.Button(o, "Preview profile", B.second, Style.CONTROL.compact)
	page.previewProfile:SetPoint("LEFT", page.connectAll, "RIGHT", 8, 0)
	page.previewProfile:SetScript("OnClick", function()
		TRP3Page.RunConnectionAction(page, page.previewProfile.action)
	end)
	page.refreshConnection = Widgets.Button(o, "Refresh connection", B.refresh, Style.CONTROL.compact, "ghost")
	page.refreshConnection:SetPoint("BOTTOMRIGHT", -P, 14)
	page.refreshConnection:SetScript("OnClick", function()
		MainWindow.SetStatus("Read Total RP 3 again. Nothing was written.")
		MainWindow.Refresh()
	end)
	Widgets.Tooltip(page.refreshConnection, "Refresh connection", "Reads Total RP 3 again, for example after you "
		.. "create or select a profile there. Nothing is written.")
	-- Only for older characters, at the right of the title line.
	page.switchModel = Widgets.Button(o, "Publish whole profile…", 190, Style.CONTROL.compact, "ghost")
	page.switchModel:SetPoint("TOPRIGHT", -P, -54)
	page.switchModel:SetScript("OnClick", function() TRP3Page.AskSwitchModel() end)
	Widgets.Tooltip(page.switchModel, "Publish whole profile", "An earlier version kept part of this character's "
		.. "profile back from Total RP 3. This one-time confirmation lists it first and can be undone. "
		.. "Same as /dawnward publish.")
end

function TRP3Page.RefreshOverview(page, view)
	local char = realChar()
	page.title:SetText("")
	local managed = ns.TRP3Commands.AnyManaged(view.bound and view.entry or nil)
	page.chip:SetChip(managed and "Connected" or "Not connected", managed and "public" or "muted")
	local lines = TRP3Page.OverviewLines(view, char, ns.ctx and ns.ctx.characterKey)
	for i, row in ipairs(page.overviewRows) do
		local line = lines[i]
		row.name:SetShown(line ~= nil)
		row.value:SetShown(line ~= nil)
		if line then
			row.name:SetText(line[1])
			row.value:SetText(line[2])
			Widgets.Tooltip(row.hover, line[1], line[2])
		end
	end
	local prefs = char and char.story and char.story.prefs or ns.StorySchema.NewPrefs()
	for _, seg in ipairs(page.overviewChoices) do
		seg:Select(prefs[seg.key] or ns.StorySchema.DEFAULT_PREFS[seg.key])
	end
	local c = view.connection or {}
	if c.state == "switched" then
		page.chip:SetChip("Paused", "waiting")
	end
	page.connectionNote:SetText(TRP3Page.ConnectionNote(c))
	local text = ns.TRP3Commands.ConnectionText(c)
	TRP3Page.SetWarning(page.connectionNote, text.guide ~= nil and text.guideTone ~= "muted")
	local primary, second = TRP3Page.ConnectionButtons(c)
	for _, pair in ipairs({ { page.connectAll, primary }, { page.previewProfile, second } }) do
		local button, spec = pair[1], pair[2]
		button:SetText(spec[1])
		button.action = spec[2]
		button:SetEnabled(spec[3])
		Widgets.Tooltip(button, (spec[1]:gsub("…$", "")), TRP3Page.ACTION_TIPS[spec[2]])
	end
	page.switchModel:SetShown(char ~= nil and ns.Publication.Status(char) == "pending")
end

-- Overview button sizes and the connection note's place (below the choices).
TRP3Page.CONNECTION_BUTTONS = { primary = 168, second = 128, refresh = 150 }
TRP3Page.CONNECTION_NOTE_TOP = 88 + 8 * TRP3Page.OVERVIEW_ROW + 10 + 3 * (TRP3Page.SELECTOR_HEIGHT + 10) + 4

TRP3Page.ACTION_TIPS = {
	connect = "Dawnward keeps every supported part of this Total RP 3 profile up to date from your Dawnward "
		.. "character: names, titles, details, About page, personality and additional information. Your own Total "
		.. "RP 3 text is never overwritten; a backup is taken before every write. You confirm first.",
	preview = "Everything Dawnward would publish, in a window you can copy from. Nothing is written. Same as "
		.. "/dawnward trp3 profile.",
	create = "Creates a Total RP 3 profile named after this character and starts using it (you confirm first). "
		.. "No other profile is changed.",
	switch = "Uses one of your own Total RP 3 profiles for this character (you confirm first). No profile is "
		.. "changed.",
	switchBack = "Goes back to the Total RP 3 profile this character is connected to, so sync carries on (you "
		.. "confirm first).",
}

--- The Overview's connection note (what Connect will do, or what stops
-- it and what to do). Pure, from TRP3Commands.Connection.
function TRP3Page.ConnectionNote(c)
	local guide = ns.TRP3Commands.ConnectionText(c).guide
	if guide then
		return guide
	end
	local name = c.profile and c.profile.name and ("\"" .. plain(c.profile.name) .. "\"") or "this profile"
	if c.state == "connected" then
		return "Dawnward keeps " .. name .. " up to date from your Dawnward character. A backup is taken before every "
			.. "write; any write can be rolled back."
	elseif c.state == "ready" then
		return "Connect everything… links " .. name .. " to this character: your one authorisation. Dawnward then "
			.. "keeps it up to date from your Dawnward character."
	end
	return ""
end

--- The Overview's primary and second buttons for a connection state:
-- { label, action, enabled } each. Pure.
function TRP3Page.ConnectionButtons(c)
	local preview = { "Preview profile", "preview", true }
	local connect = { "Connect everything…", "connect", c.canConnect == true }
	if c.state == "default" or c.state == "linked" then
		return c.canCreate and { "Create a profile…", "create", true } or connect,
			c.canSwitch and { "Switch profile…", "switch", true } or preview
	elseif c.state == "switched" then
		local reconnect = { "Reconnect…", "connect", c.canConnect == true }
		if c.canSwitchBack then
			return { "Switch back…", "switchBack", true }, c.canConnect and reconnect or preview
		end
		return reconnect, preview
	end
	return connect, c.canCreate and { "Create a profile…", "create", true } or preview
end

--- Runs an Overview connection button's action (each asks first).
function TRP3Page.RunConnectionAction(page, action)
	local c = page.view and page.view.connection
	if action == "preview" then
		Commands.Execute(ns.ctx, "trp3 profile")
	elseif action == "connect" then
		TRP3Page.AskConnectAll(page)
	elseif action == "create" and c and c.suggestedName then
		Widgets.Confirm(ns.TRP3Commands.CreateQuestion(c.suggestedName), "Create", function()
			act(function()
				local _, message = ns.TRP3Commands.CreateProfile(ns.ctx, c.suggestedName)
				return message
			end)
		end)
	elseif (action == "switch" or action == "switchBack") and c then
		local target, question
		if action == "switchBack" then
			target = { id = c.connectedProfileId, name = c.connectedName, sharedWith = 0 }
			question = ns.TRP3Commands.SwitchQuestion(target, nil, nil, true)
		elseif #c.candidates > 0 then
			page.switchPick = (page.switchPick or 0) % #c.candidates + 1
			target = c.candidates[page.switchPick]
			question = ns.TRP3Commands.SwitchQuestion(target, page.switchPick, #c.candidates)
		end
		if not target then return end
		Widgets.Confirm(question, "Switch", function()
			act(function()
				local _, message = ns.TRP3Commands.SelectProfile(ns.ctx, target.id, target.name)
				return message
			end)
		end)
	end
end

--- "Connect everything…": the same single authorisation as setup's
-- Total RP 3 stage (TRP3Commands.ConnectAll); keeps the player's own text.
function TRP3Page.AskConnectAll(page)
	local view = page.view
	if not view then return end
	local shared = view.probe.profile and view.probe.profile.sharedWith or 0
	Widgets.Confirm("Connect Total RP 3 profile \"" .. plain(view.probe.profile and view.probe.profile.name or "?")
		.. "\" to this character?\n\nThis is your one authorisation: Dawnward will keep your names, titles, details, "
		.. "About page (your whole story), personality and additional information up to date from your Dawnward "
		.. "character. Where Total RP 3 already has your own text, it is kept and that item waits for your choice. "
		.. "A backup is taken before every write."
		.. (shared > 0 and ("\n\nThis profile is shared with " .. plural(shared, "other character",
			"other characters") .. "; they will show the same.") or ""), "Connect", function()
		act(function()
			local _, message = ns.TRP3Commands.ConnectAll(ns.ctx, { existing = "keep" })
			return message
		end)
	end)
end

--- The one-time confirmation for a character an earlier version kept
-- partly back (Publication.Status "pending").
function TRP3Page.AskSwitchModel()
	local char = realChar()
	if not char or ns.Publication.Status(char) ~= "pending" then return end
	local lines = ns.Publication.PreviewLines(char)
	Widgets.Confirm("Publish your whole character profile?\n\nAn earlier version of Dawnward kept part of this "
		.. "character back from Total RP 3:\n\n" .. table.concat(lines, "\n")
		.. "\n\nFrom now on your whole Dawnward profile is the source for Total RP 3. You can undo this with "
		.. "/dawnward publish undo.", "Publish", function()
		act(function()
			local _, message = ns.Actions.TransitionPublication(ns.ctx)
			return message
		end)
	end)
end

function TRP3Page.ShortDate(at)
	if type(at) ~= "number" or at <= 0 then return "?" end
	return tostring(tonumber(date("%d", at))) .. " " .. date("%b", at)
end

--- Paints a line as a warning (the design's amber) or as plain text.
function TRP3Page.SetWarning(fs, on)
	fs.warning = on and true or nil
	ns.Style.Register(fs, function(f, theme)
		ns.Style.TextColor(f, f.warning and ns.Themes.STATUS_COLORS.waiting or theme.text)
	end)
end

--- Mappings ------------------------------------------------------------------

--- The unsupported-fields note (names only; FieldPlan.UNSUPPORTED, with the
-- reasons, is its tooltip). Pure.
function TRP3Page.UnsupportedText()
	return "Never written (hover for why): Currently, OOC and RP status, icon and colours, walk-up and music. "
		.. "They stay yours in Total RP 3."
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

--- How many mapping rows fit on one page of a card mainH high: the rows,
-- the one-line note under them and the Authorize row (14 + 30 + 8). Pure.
function TRP3Page.MapPageSize(mainH)
	local free = mainH - TRP3Page.MAP_TOP - 4 - TRP3Page.LINE - (14 + Style.CONTROL.compact + 8)
	return math.max(1, math.floor((free + TRP3Page.MAP_ROW_GAP) / (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP)))
end

--- One mapping row's text: name line and detail line. Pure (from view).
function TRP3Page.RowText(page, id)
	local view = page.view
	local m = ns.TRP3Sync.MappingOf(id)
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
	local warns = (shared and shared > 0) or not view.probe.experimental.allowed
	TRP3Page.SetWarning(page.sharedWarn, warns)
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
	Widgets.Tooltip(page.sharedWarnHover, warns and "Before you authorize" or "Linked profile",
		page.sharedWarn:GetText())
	page.mapPage = math.max(1, math.min(page.mapPage or 1, page.mapPages))
	page.mapPageLabel:SetText(string.format("Page %d of %d", page.mapPage, page.mapPages))
	page.mapPrev:SetEnabled(page.mapPage > 1)
	page.mapNext:SetEnabled(page.mapPage < page.mapPages)
	for _, row in ipairs(page.mapRows) do
		row:SetShown(row.mapPage == page.mapPage)
		local name, detail = TRP3Page.RowText(page, row.id)
		row.name:SetText(name)
		row.detail:SetText(detail)
		row.selector:Select(TRP3Page.Shown(page, row.id))
		local m = ns.TRP3Sync.MappingOf(row.id)
		local where = m and (m.key and ("Total RP 3 field " .. m.key) or "Total RP 3 additional information")
		local about = m and (where .. (m.msp and (" (MSP " .. m.msp .. "). ") or ". ")
			.. (m.risk == "high" and "Players usually write this themselves in Total RP 3; it stays managed by "
				.. "Total RP 3 unless you choose otherwise. " or "")
			.. "Dawnward writes it only from your Public " .. m.label .. ", only while Total RP 3 still holds the "
			.. "value Dawnward last wrote.") or TRP3Page.EXPLAIN[row.id]
		-- The detail line may be cut on the page; the tooltip has it whole.
		Widgets.Tooltip(row.hover, name, detail .. "\n\n" .. about)
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
			local m = ns.TRP3Sync.MappingOf(id)
			local itemLabel = m and m.label or FEATURE_LABEL[id]
			if policy == "dawnward" then
				local what
				if m then
					what = fieldProposal(view, m)
				elseif id == "about" then
					what = view.preview.about == "" and "nothing Public yet" or "adds Dawnward's own block to your About"
				elseif id == "glance" then
					what = "writes the At First Glance entries you wrote for it, into free slots"
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
