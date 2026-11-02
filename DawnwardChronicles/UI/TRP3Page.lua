-- Settings -> Total RP 3: managing the connected Total RP 3 profile
-- (docs/design/mockups/proposed-trp3-sync.png, approved for v0.7; organised
-- by purpose in v0.10).
--
-- This page only DISPLAYS what the existing /dawnward trp3 commands know and
-- runs the SAME functions they run (Integrations/TRP3/Commands.lua and
-- Sync.lua). It adds no write path and bypasses no guard: every write goes
-- through Sync.RunFeature / Sync.Rollback / Sync.Release / Sync.Authorize
-- with the opt-in, profile binding, version allowlist, default-profile,
-- simulation, read-only, combat and open-editor checks, the backup before
-- every write and the read-back with automatic undo. Opening or refreshing
-- the page only reads (Adapter.Probe, Sync.Check, the profile projection).
--
-- v0.10 layout: the summary strip on top (Total RP 3 · linked profile ·
-- sync), then a section rail on the left and one section card beside it:
--   Connection              the active profile, the connected character,
--                           the last successful sync; Connect everything…,
--                           Create a profile… / Switch profile…, Preview
--                           profile, Refresh connection
--   Character information   who keeps each field and additional-information
--                           entry up to date (Dawnward / TRP3 / Off), staged
--                           on the page until "Authorize…" (with its
--                           confirmation), and an explicit Import per field
--   Biography               the About page: content, template and style, the
--                           proposed change, and a preview of what Total RP 3
--                           will show (headings, order, frames)
--   Personality             Dawnward's traits, the proposed change and a
--                           preview of the trait bars
--   Appearance and At First Glance
--                           the appearance fields and the At First Glance
--                           entries, with the same staging and Authorize…
--   Synchronization status  every part's state, the last successful sync,
--                           the last problem, and what is never sent or not
--                           supported
--   Conflicts and recovery  the conflict callout (Keep yours / Use
--                           Dawnward's) and the backups, with Roll back… and
--                           Exact restore… behind their confirmations
-- A section that needs the player carries a coloured mark in the rail
-- (amber: waiting for a choice; red: blocked or in conflict), so nothing is
-- hidden behind the section that is not open.
local _, ns = ...
local Widgets, MainWindow, Commands = ns.Widgets, ns.MainWindow, ns.Commands

local TRP3Page = {}
ns.TRP3Page = TRP3Page

TRP3Page.SECTIONS = {
	{ id = "connection", label = "Connection" },
	{ id = "character", label = "Character information" },
	{ id = "about", label = "Biography" },
	{ id = "traits", label = "Personality" },
	{ id = "appearance", label = "Appearance and At First Glance" },
	{ id = "status", label = "Synchronization status" },
	{ id = "recovery", label = "Conflicts and recovery" },
}
-- Earlier name of the same list (the rail replaces the feature tabs).
TRP3Page.FEATURES = TRP3Page.SECTIONS
local FEATURE_LABEL = { about = "Biography", traits = "Personality", fields = "Profile fields", mappings = "Mappings",
	misc = "Additional information", glance = "At First Glance", overview = "Overview" }
local SECTION_LABEL = {}
for _, s in ipairs(TRP3Page.SECTIONS) do SECTION_LABEL[s.id] = s.label end

-- Which mappings each section lists (Ledger.MAPPINGS order). The biography
-- and traits are switched on their own sections (Enable syncing… / Stop
-- syncing), so their rows are not repeated.
TRP3Page.APPEARANCE_MAPPINGS = { eyes = true, height = true, weight = true, glance = true }
TRP3Page.SECTION_MAPPINGS = { character = {}, appearance = {} }
for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
	if TRP3Page.APPEARANCE_MAPPINGS[id] then
		table.insert(TRP3Page.SECTION_MAPPINGS.appearance, id)
	elseif id ~= "about" and id ~= "traits" then
		table.insert(TRP3Page.SECTION_MAPPINGS.character, id)
	end
end

-- The Biography's choices, each a segmented control writing one story
-- preference (Actions.SetStoryPref).
TRP3Page.ABOUT_CHOICES = {
	{ key = "trp3About", label = "Content", items = { { id = "auto", label = "Auto" },
		{ id = "profile", label = "Profile" }, { id = "summary", label = "Summary" } } },
	{ key = "trp3Layout", label = "Template", items = { { id = "current", label = "Keep" },
		{ id = "text", label = "Text" }, { id = "frames", label = "Frames" }, { id = "sections", label = "Sections" } } },
	{ key = "trp3Style", label = "Style", items = { { id = "neutral", label = "Neutral" },
		{ id = "silverhand", label = "Silver Hand" }, { id = "arcane", label = "Arcane" } } },
}
TRP3Page.OVERVIEW_CHOICES = TRP3Page.ABOUT_CHOICES
TRP3Page.CHOICE_HELP = {
	trp3About = "Auto: your whole profile once it is published, else a short summary. Profile: your story and "
		.. "details. Summary: a short block only.",
	trp3Layout = "Keep: the template your About page already uses. Text: template 1. Frames: template 2, one framed "
		.. "section each. Sections: template 3 (physical, personality, history).",
	trp3Style = "Neutral: plain headings. Silver Hand: gold headings, marble frames. Arcane: violet headings with "
		.. "section icons. Frames you restyled in Total RP 3 keep your icon and background.",
}
TRP3Page.CHOICE_LABEL = 96    -- the choices' label column
TRP3Page.CHOICE_ITEM = 86     -- one segment ("Silver Hand" gets 100)
TRP3Page.CHOICE_GAP = 6
TRP3Page.STATUS_ROW = 22      -- one status line
TRP3Page.STATUS_LABEL = 170   -- the status label column
TRP3Page.OVERVIEW_ROW = TRP3Page.STATUS_ROW
TRP3Page.OVERVIEW_LABEL = 150 -- the connection lines' label column

-- Layout (v0.10). The strip spans the page; below it the section rail
-- (RAIL_WIDTH) and the section card, COLUMN_GAP apart. Every section card
-- starts with the same header: title (Cinzel 18) and state chip on one row,
-- a two-line explanation under it (HEAD_HEIGHT in all).
TRP3Page.RAIL_WIDTH = 188
TRP3Page.RAIL_ITEM = 44       -- the design's navigation height
TRP3Page.RAIL_GAP = 4
TRP3Page.COLUMN_GAP = 16
TRP3Page.STRIP_GAP = 12
TRP3Page.SUMMARY_HEIGHT = 62
TRP3Page.CARD_PAD = 18
TRP3Page.HEAD_HEIGHT = 84     -- title row and the two-line explanation
TRP3Page.GAP = 12
TRP3Page.LINE = 17            -- one line of 14 px text
TRP3Page.ACTION_HEIGHT = 36   -- Approve and write, Not now, Stop syncing
TRP3Page.REASON_CHARS = 150
TRP3Page.PREVIEW_LINES = 4    -- the plain preview lines kept for copying (Personality)

-- Mapping rows are two lines: the name with its selector and Import on the
-- first, the detail across the full width on the second. Each selector item
-- is wide enough for "Dawnward" in bold 14 (about 74 px with its insets).
TRP3Page.MAP_ROW_HEIGHT = 37
TRP3Page.MAP_ROW_GAP = 2
TRP3Page.MAP_TOP = 110
TRP3Page.SELECTOR_WIDTH = 240
TRP3Page.SELECTOR_HEIGHT = 20
TRP3Page.CHOICE_HEIGHT = 30
TRP3Page.IMPORT_WIDTH = 60

-- Conflicts and recovery: two columns of the card's width.
TRP3Page.BACKUP_ROWS = 5
TRP3Page.BACKUP_ROW_HEIGHT = 30
TRP3Page.CONFLICT_HEIGHT = 196

-- Selector choices per mapping: a block (At First Glance) is on or off; a
-- field is managed by Dawnward, by Total RP 3, or not synchronised.
TRP3Page.BLOCK_CHOICES = { { id = "dawnward", label = "Dawnward" }, { id = "off", label = "Off" } }
TRP3Page.FIELD_CHOICES = { { id = "dawnward", label = "Dawnward" }, { id = "trp3", label = "TRP3" },
	{ id = "off", label = "Off" } }

TRP3Page.MAPPINGS_EXPLAIN = "Choose who keeps each part up to date. Dawnward writes from your character profile, "
	.. "never over your own Total RP 3 text, and nothing changes until you Authorize."
TRP3Page.APPEARANCE_EXPLAIN = "Eye colour, height and build, and the At First Glance entries you wrote for Total "
	.. "RP 3. Nothing changes until you Authorize."
TRP3Page.CONNECTION_EXPLAIN = "Dawnward keeps one Total RP 3 profile up to date from this character. Your own "
	.. "Total RP 3 text is never overwritten, and a backup is taken before every write."
TRP3Page.STATUS_EXPLAIN = "What Dawnward keeps up to date in this profile, when it last wrote, and what it never "
	.. "sends. Hover a line for the details."
TRP3Page.RECOVERY_EXPLAIN = "If something Dawnward wrote was changed in Total RP 3, nothing is overwritten until "
	.. "you choose. Every write is backed up first and can be rolled back."

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
	about = "Dawnward only writes its own part of your \"About\" page. Everything you wrote in Total RP 3 "
		.. "yourself stays exactly as it is.",
	traits = "Dawnward only adds and updates its own personality traits, one per personality axis you set. "
		.. "Preset traits and traits you made yourself are never changed.",
	glance = "Dawnward only writes the At First Glance entries you wrote for it (/dawnward trp3 glance), into "
		.. "free slots. Slots you filled in Total RP 3 are never changed.",
}

-- What is not supported (v0.10: accurate for the v0.9 profile model, where
-- every field in Character information can be handed to Dawnward).
TRP3Page.UNSUPPORTED_TEXT = "Never written: Currently and RP status, icon and colours, walk-up, roleplay "
	.. "experience and music. Your one Name is never split; first and last name come from their own details."
TRP3Page.UNSUPPORTED_DETAIL = "Your story, profile details, family, beliefs, stances and defining moments go into "
	.. "the About page, and your personality axes into traits. Each field in Character information and in "
	.. "Appearance is written only while you hand it to Dawnward there."

TRP3Page.BACKUP_NOTE = "Every write is backed up first, read back, and undone at once if anything differs. "
	.. "Select a backup to restore it."

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

local function plural(n, one, many)
	return n .. " " .. (n == 1 and one or many)
end

--- What never reaches Total RP 3, and anything an earlier version kept
-- back (counts only, never content). Pure apart from reading char.
function TRP3Page.HiddenText(char)
	local text = "Journal notes, drafts, story answers, memories and inner convictions are never sent."
	if char and ns.Publication.Status(char) == "pending" then
		local n = ns.Publication.HiddenCount(char)
		text = text .. " " .. plural(n, "item", "items") .. " an earlier version kept back "
			.. (n == 1 and "waits" or "wait") .. " for your one-time confirmation (Publish whole profile…)."
	end
	return text
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

--- The About preview -------------------------------------------------------------
-- What Total RP 3 will show, drawn from TRP3Presentation.Display: headings in
-- the order and levels TRP3 uses (h1, h2, h3 in decreasing size), paragraphs,
-- template 2 frames with their icon (left, then right, alternating as TRP3
-- does) and their tiled background, template 3's three titled parts. Text
-- regions and frames are pooled and reused on every refresh.
TRP3Page.RENDER_STYLE = { h1 = "railName", h2 = "title", h3 = "button", p = "meta" }
TRP3Page.RENDER_LINE = { h1 = 26, h2 = 22, h3 = 19, p = 17 }
TRP3Page.RENDER_GAP = 6       -- between items
TRP3Page.RENDER_ICON = 32     -- a template 2 frame's icon
TRP3Page.RENDER_FRAME_PAD = 10

local function newRenderer(parent, width, height)
	local r = { pools = { h1 = {}, h2 = {}, h3 = {}, p = {} }, frames = {}, order = {} }
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("TRP3Preview"), parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -30)
	scroll:SetSize(width - 28, height - 38)
	r.scroll, r.width = scroll, width - 28
	r.child = CreateFrame("Frame", nil, scroll)
	r.child:SetSize(r.width, 1)
	scroll:SetScrollChild(r.child)
	r.bar = Widgets.SlimScrollBar(scroll, 4)
	Widgets.WheelScroll(scroll)
	-- Text above the frames' backgrounds.
	r.top = CreateFrame("Frame", nil, r.child)
	r.top:SetAllPoints(r.child)
	if r.top.SetFrameLevel and r.child.GetFrameLevel then
		r.top:SetFrameLevel((r.child:GetFrameLevel() or 0) + 3)
	end
	return r
end

-- Height of a wrapped text region: the client's own measure, else an
-- estimate from the bundled fonts' advance widths.
local function textHeight(fs, text, kind, width)
	local h = fs.GetStringHeight and fs:GetStringHeight() or 0
	if h and h > 0 then return h end
	local plainText = text:gsub("|T.-|t", "WW"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local lines = 0
	for line in (plainText .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + math.max(1, math.ceil(ns.Style.TextWidth(line, TRP3Page.RENDER_STYLE[kind]) / width))
	end
	return lines * TRP3Page.RENDER_LINE[kind]
end

local function acquireText(r, kind)
	r.used[kind] = r.used[kind] + 1
	local fs = r.pools[kind][r.used[kind]]
	if not fs then
		fs = Widgets.Label(r.top, TRP3Page.RENDER_STYLE[kind], true, kind == "p" and "reading" or "title")
		r.pools[kind][r.used[kind]] = fs
	end
	fs:SetJustifyH("LEFT") -- a template 3 title may have centred it last time
	fs:Show()
	return fs
end

local function acquireFrame(r)
	r.usedFrames = r.usedFrames + 1
	local f = r.frames[r.usedFrames]
	if not f then
		f = CreateFrame("Frame", nil, r.child)
		if f.SetFrameLevel and r.child.GetFrameLevel then f:SetFrameLevel((r.child:GetFrameLevel() or 0) + 1) end
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetAllPoints(f)
		f.edges = ns.Style.Edge(f, "BORDER")
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetSize(TRP3Page.RENDER_ICON, TRP3Page.RENDER_ICON)
		ns.Style.Register(f, function(frame, theme) frame.edges:Paint(theme.edge, 1) end)
		r.frames[r.usedFrames] = f
	end
	f:Show()
	return f
end

--- Draws blocks (TRP3Presentation.Display) into the renderer. Returns the
-- height of what was drawn.
function TRP3Page.Render(r, blocks)
	for _, pool in pairs(r.pools) do
		for _, fs in ipairs(pool) do fs:Hide() end
	end
	for _, f in ipairs(r.frames) do f:Hide() end
	r.used = { h1 = 0, h2 = 0, h3 = 0, p = 0 }
	r.usedFrames = 0
	r.order = {}
	local y, W = 0, r.width
	local gap = TRP3Page.RENDER_GAP
	local function items(list, x, width)
		for _, item in ipairs(list) do
			local fs = acquireText(r, item.kind)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", r.top, "TOPLEFT", x, -y)
			fs:SetWidth(width)
			fs:SetText(item.text)
			r.order[#r.order + 1] = fs
			y = y + textHeight(fs, item.text, item.kind, width) + gap
		end
	end
	for i, block in ipairs(blocks) do
		if block.kind == "frame" or block.kind == "part" then
			local f = acquireFrame(r)
			local top = y
			local P = TRP3Page.RENDER_FRAME_PAD
			local bk = ns.TRP3Presentation.BACKGROUNDS[block.background or 1] or ns.TRP3Presentation.BACKGROUNDS[1]
			f.bg:SetTexture(bk.file, "REPEAT", "REPEAT")
			if f.bg.SetHorizTile then f.bg:SetHorizTile(true); f.bg:SetVertTile(true) end
			f.icon:ClearAllPoints()
			f.icon:SetTexture("Interface\\ICONS\\" .. tostring(block.icon or "inv_misc_questionmark"))
			y = y + P
			if block.kind == "part" then
				-- TRP3: "icon    Title    icon", centred above the part.
				local title = acquireText(r, "h2")
				title:ClearAllPoints()
				title:SetPoint("TOPLEFT", r.top, "TOPLEFT", P, -y)
				title:SetWidth(W - 2 * P)
				local icon = "|TInterface\\ICONS\\" .. block.icon .. ":18|t"
				title:SetText(icon .. "  " .. block.title .. "  " .. icon)
				title:SetJustifyH("CENTER")
				r.order[#r.order + 1] = title
				y = y + TRP3Page.RENDER_LINE.h2 + gap
				f.icon:Hide()
				items(block.items, P, W - 2 * P)
			else
				f.icon:Show()
				local left = (i % 2) == 1
				local textW = W - 2 * P - TRP3Page.RENDER_ICON - P
				f.icon:SetPoint(left and "LEFT" or "RIGHT", f, left and "LEFT" or "RIGHT", left and P or -P, 0)
				items(block.items, left and (P + TRP3Page.RENDER_ICON + P) or P, textW)
			end
			y = math.max(y - gap + P, top + TRP3Page.RENDER_ICON + 2 * P)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", r.child, "TOPLEFT", 0, -top)
			f:SetSize(W, y - top)
			y = y + 10
		else
			items(block.items, 0, W)
		end
	end
	r.child:SetHeight(math.max(1, y))
	r.height = y
	if r.bar and r.bar.UpdateThumb then r.bar.UpdateThumb() end
	return y
end

--- The preview's text in reading order (tests and diagnostics).
function TRP3Page.PreviewText(page)
	local out = {}
	for _, fs in ipairs(page.render and page.render.order or {}) do
		out[#out + 1] = fs:GetText() or ""
	end
	return table.concat(out, "\n")
end

--- Building -------------------------------------------------------------------------

-- A section view: a frame over the card, shown when its section is.
local function sectionView(page, id)
	local v = CreateFrame("Frame", nil, page.card)
	v:SetAllPoints(page.card)
	v:Hide()
	page.views[id] = v
	return v
end

-- The rail: one raised item per section (the design's navigation), the
-- section's name over up to two lines, a state mark at the right and a gold
-- bar on the selected one.
local function buildRail(page, parent)
	local railW = TRP3Page.RAIL_WIDTH
	local nav = { buttons = {} }
	for i, s in ipairs(TRP3Page.SECTIONS) do
		local b = Widgets.Button(parent, "", railW, TRP3Page.RAIL_ITEM, "choice")
		b:SetPoint("TOPLEFT", 0, -(i - 1) * (TRP3Page.RAIL_ITEM + TRP3Page.RAIL_GAP))
		b.segmentId = s.id
		b.name = Widgets.Label(b, "body", true, nil)
		b.name:SetPoint("LEFT", 14, 0)
		b.name:SetWidth(railW - 14 - 30)
		b.name:SetMaxLines(2)
		b.name:SetJustifyV("MIDDLE")
		b.name:SetText(s.label)
		ns.Style.Register(b.name, function(fs, theme)
			local tones = ns.Style.Tones(theme)
			ns.Style.TextColor(fs, b.selected and tones.heading or tones.navText)
		end)
		b.dot = ns.Style.Disc(b, "ARTWORK", 1, 8)
		b.dot:SetPoint("RIGHT", -14, 0)
		b.mark = ns.Style.Solid(b, "ARTWORK", 2)
		b.mark:SetPoint("TOPLEFT", 0, 0)
		b.mark:SetPoint("BOTTOMLEFT", 0, 0)
		b.mark:SetWidth(3)
		ns.Style.Register(b.mark, function(t, theme) ns.Style.Color(t, theme.accent) end)
		b.mark:Hide()
		b:SetScript("OnClick", function()
			page.feature = s.id
			page.mapPage = 1
			MainWindow.Refresh()
		end)
		nav.buttons[i] = b
	end
	function nav.Select(_, id)
		for _, b in ipairs(nav.buttons) do
			b:SetSelected(b.segmentId == id)
			b.mark:SetShown(b.segmentId == id)
			ns.Style.Repaint(b.name)
		end
	end
	return nav
end

--- Builds the page inside parent (the settings page frame). Returns page.
function TRP3Page.Build(parent, width, height)
	local page = { frame = parent, feature = nil, backupRows = {}, views = {}, staged = {}, mapRows = {}, mapPage = 1 }
	local W = width
	local P = TRP3Page.CARD_PAD
	local LINE = TRP3Page.LINE
	local HEAD = TRP3Page.HEAD_HEIGHT
	local mainTop = -(TRP3Page.SUMMARY_HEIGHT + TRP3Page.STRIP_GAP)
	local mainH = height - TRP3Page.SUMMARY_HEIGHT - TRP3Page.STRIP_GAP
	local cardW = W - TRP3Page.RAIL_WIDTH - TRP3Page.COLUMN_GAP
	local innerW = cardW - 2 * P
	page.width, page.height, page.mainHeight, page.leftWidth, page.innerWidth = W, height, mainH, cardW, innerW

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

	-- Shown instead of the rail and the card when Total RP 3 is not available.
	page.absent = Widgets.Panel(parent)
	page.absent:SetPoint("TOPLEFT", 0, mainTop)
	page.absent:SetSize(W, mainH)
	page.absentTitle = Widgets.Label(page.absent, "GameFontNormalLarge", false, "title")
	page.absentTitle:SetPoint("TOPLEFT", P, -18)
	page.absentTitle:SetText("Total RP 3 is optional")
	page.absentText = label(page.absent, "reading", true, "reading")
	page.absentText:SetPoint("TOPLEFT", P, -50)
	page.absentText:SetWidth(W - 2 * P)
	page.absentStatus = label(page.absent, "muted", true)
	page.absentStatus:SetPoint("TOPLEFT", P, -150)
	page.absentStatus:SetWidth(W - 2 * P)

	local body = CreateFrame("Frame", nil, parent)
	body:SetPoint("TOPLEFT", 0, mainTop)
	body:SetSize(W, mainH)
	page.body = body
	page.nav = buildRail(page, body)

	local card = Widgets.Panel(body)
	card:SetPoint("TOPLEFT", TRP3Page.RAIL_WIDTH + TRP3Page.COLUMN_GAP, 0)
	card:SetSize(cardW, mainH)
	page.card = card

	-- Every section's header: title and state chip, then two muted lines.
	page.title = Widgets.Label(card, "GameFontNormalLarge", false, "title")
	page.title:SetPoint("TOPLEFT", P, -16)
	page.title:SetWidth(innerW)
	page.overviewTitle = page.title
	page.chip = Widgets.Chip(card, "", "muted")
	page.chip:SetPoint("TOPRIGHT", -P, -17)
	page.chip:SetMaxWidth(180)
	page.explain = paragraph(card, "muted", innerW, 2)
	page.explain:SetPoint("TOPLEFT", P, -46)

	-- Biography and Personality ------------------------------------------------------
	local fv = sectionView(page, "about")
	page.views.traits = fv
	page.featureView = fv
	page.reasons = oneLine(fv, "body", innerW)
	page.reasons:SetPoint("TOPLEFT", P, -HEAD)
	-- The status line is one line on the page; the full text is here.
	page.reasonsHover = CreateFrame("Frame", nil, fv)
	page.reasonsHover:SetPoint("TOPLEFT", P, -HEAD)
	page.reasonsHover:SetSize(innerW, LINE)

	page.keep = box(fv, "plain")
	page.keep:SetPoint("TOPLEFT", P, -(HEAD + 22))
	page.keep:SetSize(innerW, LINE + 10)
	page.keepText = oneLine(page.keep, "navText", innerW - 20)
	page.keepText:SetPoint("TOPLEFT", 10, -5)
	page.keepHover = hoverOver(page.keep, page.keep)

	-- The About page's choices (Biography only).
	local C = TRP3Page.CHOICE_HEIGHT
	page.choices = CreateFrame("Frame", nil, fv)
	page.choices:SetPoint("TOPLEFT", P, -(HEAD + 22 + LINE + 10 + 10))
	page.choices:SetSize(innerW, #TRP3Page.ABOUT_CHOICES * (C + TRP3Page.CHOICE_GAP) - TRP3Page.CHOICE_GAP)
	page.overviewChoices = {}
	for i, choice in ipairs(TRP3Page.ABOUT_CHOICES) do
		local y = -(i - 1) * (C + TRP3Page.CHOICE_GAP)
		local name = oneLine(page.choices, "body", TRP3Page.CHOICE_LABEL - 8, "body")
		name:SetPoint("TOPLEFT", 0, y - 7)
		name:SetText(choice.label)
		local item = choice.key == "trp3Style" and 100 or TRP3Page.CHOICE_ITEM
		local seg = Widgets.Segmented(page.choices, choice.items, #choice.items * item, C, function(id)
			act(function()
				local _, message = ns.Actions.SetStoryPref(ns.ctx, choice.key, id)
				return message
			end)
		end)
		seg.buttons[1]:SetPoint("TOPLEFT", page.choices, "TOPLEFT", TRP3Page.CHOICE_LABEL, y)
		seg.key = choice.key
		seg.name = name
		for _, b in ipairs(seg.buttons) do
			Widgets.Tooltip(b, choice.label .. ": " .. b:GetText(), TRP3Page.CHOICE_HELP[choice.key])
		end
		page.overviewChoices[i] = seg
	end

	-- What Total RP 3 will show (the "add" box: the design's proposed-write
	-- box), with Copy text for pasting by hand.
	page.preview = box(fv, "add")
	page.previewHead = Widgets.Label(page.preview, "GameFontNormalSmall", false, "eyebrow")
	page.previewHead:SetPoint("TOPLEFT", 10, -9)
	Style.Register(page.previewHead, function(fs) Style.TextColor(fs, ns.Themes.VISIBILITY_COLORS.public) end)
	page.copy = Widgets.Button(page.preview, "Copy text", 92, 24, "ghost")
	page.copy:SetPoint("TOPRIGHT", -5, -4)
	Widgets.Tooltip(page.copy, "Copy text", "Show this text (your character profile) to paste into Total RP 3 "
		.. "yourself. Same as /dawnward trp3 paste. Nothing is written.")
	page.copy:SetScript("OnClick", function()
		Commands.Execute(ns.ctx, "trp3 paste")
	end)
	page.previewText = paragraph(page.preview, nil, innerW - 20, TRP3Page.PREVIEW_LINES)
	page.previewText:SetPoint("TOPLEFT", 10, -30)
	Style.Register(page.previewText, function(fs) Style.TextColor(fs, TRP3Page.AddTextColor()) end)
	-- Personality: one bar per trait, as Total RP 3 draws them (left word,
	-- the bar leaning by value, right word).
	page.traitRows = {}
	local barW = innerW - 20 - 2 * 150 - 16
	for i = 1, 6 do
		local row = CreateFrame("Frame", nil, page.preview)
		row:SetSize(innerW - 20, 24)
		row:SetPoint("TOPLEFT", 10, -(30 + (i - 1) * 28))
		row.left = oneLine(row, "body", 150, "meta")
		row.left:SetPoint("LEFT", 0, 0)
		row.left:SetJustifyH("RIGHT")
		row.track = Style.Solid(row, "ARTWORK", 0)
		row.track:SetPoint("LEFT", 158, 0)
		row.track:SetSize(barW, 10)
		row.fill = Style.Solid(row, "ARTWORK", 1)
		row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
		row.fill:SetHeight(10)
		row.right = oneLine(row, "body", 150, "meta")
		row.right:SetPoint("LEFT", 158 + barW + 8, 0)
		row.barWidth = barW
		Style.Register(row, function(r, theme)
			Style.Color(r.track, Style.Tones(theme).track)
			Style.Color(r.fill, theme.accent)
		end)
		row:Hide()
		page.traitRows[i] = row
	end

	local A = TRP3Page.ACTION_HEIGHT
	local rule = Widgets.Divider(fv)
	rule:SetPoint("BOTTOMLEFT", P, 14 + A + 8)
	rule:SetPoint("BOTTOMRIGHT", -P, 14 + A + 8)
	page.actionRule = rule
	page.approve = Widgets.Button(fv, "Approve and write", 150, A, "primary")
	page.approve:SetPoint("BOTTOMLEFT", P, 14)
	page.notNow = Widgets.Button(fv, "Not now", 90, A, "ghost")
	page.notNow:SetPoint("LEFT", page.approve, "RIGHT", 8, 0)
	page.toggle = Widgets.Button(fv, "", 194, A, "danger")
	page.toggle:SetPoint("BOTTOMRIGHT", -P, 14)
	-- The preview fills the room between the choices (or the kept-text box)
	-- and the action rule; placed per section in Refresh.
	page.previewBottom = 14 + A + 8 + 8
	page.previewTop = { traits = HEAD + 22 + LINE + 10 + 10 }
	page.previewTop.about = page.previewTop.traits + page.choices:GetHeight() + 10
	page.render = newRenderer(page.preview, innerW, mainH - page.previewBottom - page.previewTop.about)

	-- Character information and Appearance: who keeps each item ------------------------
	local mv = sectionView(page, "character")
	page.views.appearance = mv
	page.map = mv
	page.sharedWarn = oneLine(mv, "body", innerW)
	page.sharedWarn:SetPoint("TOPLEFT", P, -HEAD)
	page.sharedWarnHover = hoverOver(mv, page.sharedWarn)
	local S, I = TRP3Page.SELECTOR_WIDTH, TRP3Page.IMPORT_WIDTH
	local nameW = innerW - S - I - 12
	local perPage = TRP3Page.MapPageSize(mainH)
	page.mapPerPage = perPage
	for _, sectionId in ipairs({ "character", "appearance" }) do
		for i, id in ipairs(TRP3Page.SECTION_MAPPINGS[sectionId]) do
			local slot = (i - 1) % perPage
			local row = CreateFrame("Frame", nil, mv)
			row:SetSize(innerW, TRP3Page.MAP_ROW_HEIGHT)
			row:SetPoint("TOPLEFT", P, -(TRP3Page.MAP_TOP + slot * (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP)))
			row.id = id
			row.section = sectionId
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
			page.mapRows[#page.mapRows + 1] = row
		end
	end
	local rowsEnd = TRP3Page.MAP_TOP + perPage * (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP) - TRP3Page.MAP_ROW_GAP
	page.unsupportedNote = oneLine(mv, "muted", innerW)
	page.unsupportedNote:SetPoint("TOPLEFT", P, -(rowsEnd + 4))
	page.unsupportedNote:SetText(TRP3Page.UnsupportedText())
	page.unsupportedHover = hoverOver(mv, page.unsupportedNote)
	local reasons = {}
	for _, u in ipairs(ns.TRP3FieldPlan.UNSUPPORTED) do reasons[#reasons + 1] = u.label .. ": " .. u.reason .. "." end
	Widgets.Tooltip(page.unsupportedHover, "Not synchronised automatically", table.concat(reasons, "\n"))
	-- Appearance: the At First Glance entries under the rows.
	local appearanceRows = #TRP3Page.SECTION_MAPPINGS.appearance
	local glanceTop = TRP3Page.MAP_TOP + appearanceRows * (TRP3Page.MAP_ROW_HEIGHT + TRP3Page.MAP_ROW_GAP) + 8
	page.glance = box(mv, "plain")
	page.glance:SetPoint("TOPLEFT", P, -glanceTop)
	page.glance:SetSize(innerW, mainH - glanceTop - (14 + Style.CONTROL.compact + 12))
	local glanceHead = Widgets.Label(page.glance, "GameFontNormalSmall", false, "eyebrow")
	glanceHead:SetPoint("TOPLEFT", 10, -9)
	glanceHead:SetText("YOUR AT FIRST GLANCE ENTRIES")
	page.glanceText = paragraph(page.glance, "navText", innerW - 20,
		math.max(1, math.floor((page.glance:GetHeight() - 36) / LINE)))
	page.glanceText:SetPoint("TOPLEFT", 10, -28)
	page.glanceHover = hoverOver(page.glance, page.glance)

	page.authorize = Widgets.Button(mv, "Authorize…", 150, Style.CONTROL.compact, "primary")
	page.authorize:SetPoint("BOTTOMLEFT", P, 14)
	page.resetChoices = Widgets.Button(mv, "Reset choices", 120, Style.CONTROL.compact, "ghost")
	page.resetChoices:SetPoint("LEFT", page.authorize, "RIGHT", 8, 0)
	page.authorize:SetScript("OnClick", function() TRP3Page.AskAuthorize(page) end)
	page.resetChoices:SetScript("OnClick", function()
		page.staged = {}
		MainWindow.SetStatus("Choices reset. Nothing was changed.")
		MainWindow.Refresh()
	end)
	-- The pager (right of the Authorize row): ‹ Page n of m ›.
	page.mapPages = 1
	page.mapNext = Widgets.Button(mv, "\226\128\186", 30, Style.CONTROL.compact, "ghost")
	page.mapNext:SetPoint("BOTTOMRIGHT", -P, 14)
	page.mapPrev = Widgets.Button(mv, "\226\128\185", 30, Style.CONTROL.compact, "ghost")
	page.mapPrev:SetPoint("RIGHT", page.mapNext, "LEFT", -86, 0)
	page.mapPageLabel = oneLine(mv, "muted", 80, "small")
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
	Widgets.Tooltip(page.mapPrev, "Previous", "The previous items.")
	Widgets.Tooltip(page.mapNext, "Next", "More items.")

	TRP3Page.BuildConnection(page, P, innerW)
	TRP3Page.BuildStatus(page, P, innerW)
	TRP3Page.BuildRecovery(page, P, innerW)

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

-- Conflicts and recovery: the conflict callout (or a calm note) on the left,
-- the backups with their two restores on the right.
function TRP3Page.BuildRecovery(page, P, innerW)
	local rv = sectionView(page, "recovery")
	local HEAD = TRP3Page.HEAD_HEIGHT
	local colW = math.floor((innerW - TRP3Page.GAP) / 2)
	local colInner = colW - 2 * Widgets.PANEL_PAD
	local C = Style.CONTROL.compact
	page.recoveryColumn = colW
	page.conflict = Widgets.Callout(rv, "Conflict")
	page.conflict:SetPoint("TOPLEFT", P, -HEAD)
	page.conflict:SetSize(colW, TRP3Page.CONFLICT_HEIGHT)
	paintAmber(page.conflict)
	page.conflictText = paragraph(page.conflict.inner, "reading", colInner, 4)
	page.conflictText:SetPoint("TOPLEFT", 0, 0)
	page.conflictHover = hoverOver(page.conflict.inner, page.conflictText)
	page.reclaim = Widgets.Button(page.conflict.inner, "Use Dawnward's", colInner, C, "ghost")
	page.reclaim:SetPoint("BOTTOMLEFT", 0, 0)
	page.keepYours = Widgets.Button(page.conflict.inner, "Keep yours", colInner, C)
	page.keepYours:SetPoint("BOTTOMLEFT", page.reclaim, "TOPLEFT", 0, 6)
	page.otherConflicts = paragraph(rv, "muted", colW, 3)
	page.otherConflicts:SetPoint("TOPLEFT", P, -(HEAD + TRP3Page.CONFLICT_HEIGHT + 8))
	page.noConflict = Widgets.Panel(rv, "Conflicts")
	page.noConflict:SetPoint("TOPLEFT", P, -HEAD)
	page.noConflict:SetSize(colW, 120)
	page.noConflictText = paragraph(page.noConflict.inner, "body", colInner, 4)
	page.noConflictText:SetPoint("TOPLEFT", 0, 0)
	page.noConflictText:SetText("No conflicts. Everything Dawnward wrote is as it left it in Total RP 3.")

	-- Each backup is one selectable row: what it is on the left, the short
	-- date on the right (the design's "About · before last write   27 Oct");
	-- the full name and date are its tooltip.
	local backupsH = page.mainHeight - HEAD - 18
	page.backups = Widgets.Panel(rv, "Backups")
	page.backups:SetPoint("TOPLEFT", P + colW + TRP3Page.GAP, -HEAD)
	page.backups:SetSize(innerW - colW - TRP3Page.GAP, backupsH)
	local listW = innerW - colW - TRP3Page.GAP - 2 * Widgets.PANEL_PAD
	local rowH = TRP3Page.BACKUP_ROW_HEIGHT
	for i = 1, TRP3Page.BACKUP_ROWS do
		local row = Widgets.Button(page.backups.inner, "", listW, rowH, "choice")
		row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 4))
		row.date = oneLine(row, "muted", 52, "small")
		row.date:SetPoint("RIGHT", -8, 0)
		row.date:SetJustifyH("RIGHT")
		row.date:SetJustifyV("MIDDLE")
		row.name = oneLine(row, "body", listW - 8 - 52 - 16)
		row.name:SetPoint("LEFT", 8, 0)
		row.name:SetJustifyV("MIDDLE")
		Widgets.Tooltip(row, "Backup", "")
		row:SetScript("OnClick", function(self)
			page.selectedBackup = self.backupId
			MainWindow.Refresh()
		end)
		page.backupRows[i] = row
	end
	page.noBackups = paragraph(page.backups.inner, "muted", listW, 3)
	page.noBackups:SetPoint("TOPLEFT", 0, 0)
	page.noBackups:SetText("No backups yet. Dawnward takes one before its first write.")
	local listH = TRP3Page.BACKUP_ROWS * (rowH + 4) - 4
	page.rollback = Widgets.Button(page.backups.inner, "Roll back…", listW, C)
	page.rollback:SetPoint("TOPLEFT", 0, -(listH + 10))
	page.exact = Widgets.Button(page.backups.inner, "Exact restore…", listW, C, "ghost")
	page.exact:SetPoint("TOPLEFT", page.rollback, "BOTTOMLEFT", 0, -6)
	Widgets.Tooltip(page.rollback, "Roll back (safe)", "Restores your own text from the backup; Dawnward's part is "
		.. "rebuilt from your profile as it is now. You confirm first.")
	Widgets.Tooltip(page.exact, "Exact restore", "Restores the section exactly as it was, including Dawnward "
		.. "content your profile no longer has. You confirm first, and see what would come back.")
	page.backupNote = paragraph(page.backups.inner, "muted", listW, 3, "small")
	page.backupNote:SetPoint("TOPLEFT", page.exact, "BOTTOMLEFT", 0, -10)
	page.backupNote:SetText(TRP3Page.BACKUP_NOTE)
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
			return "(Nothing to write yet. Import your story, or add details, facts, stances or defining "
				.. "moments to your character.)"
		end
		for line in (preview.about .. "\n"):gmatch("([^\n]*)\n") do
			lines[#lines + 1] = plain(line)
		end
	else
		if #preview.traits == 0 then
			return "(No personality axes set yet. Set one on the Character page to include it.)"
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

--- Every conflict waiting on the player, the shown section's first:
-- { { id, label, reason }, ... } (Biography, Personality, then managed
-- fields). Pure (from view).
function TRP3Page.Conflicts(view, first)
	local list = {}
	for _, f in ipairs({ "about", "traits" }) do
		if view.checks[f] and view.checks[f].state == "conflict" then
			list[#list + 1] = { id = f, label = FEATURE_LABEL[f], reason = view.checks[f].reasons[1] }
		end
	end
	for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
		local m = ns.TRP3Sync.MappingOf(id)
		if m and view.fieldConflicts[id] then
			list[#list + 1] = { id = id, label = m.label, reason = view.fieldConflicts[id] }
		end
	end
	for i, c in ipairs(list) do
		if c.id == first and i > 1 then
			table.remove(list, i)
			table.insert(list, 1, c)
			break
		end
	end
	return list
end

--- The section a fresh page opens on: Connection when the connection
-- itself needs the player (default profile, a profile another character
-- keeps, a switched profile) or nothing is connected yet; Conflicts and
-- recovery when something waits for a choice; the first part with a
-- proposed change; else the Biography. Pure (from view).
function TRP3Page.DefaultSection(view)
	local state = view.connection and view.connection.state
	if state == "default" or state == "linked" or state == "switched" then
		return "connection"
	end
	if #TRP3Page.Conflicts(view) > 0 then
		return "recovery"
	end
	for _, f in ipairs({ "about", "traits" }) do
		if view.checks[f] and view.checks[f].state == "ready" then return f end
	end
	if not ns.TRP3Commands.AnyManaged(view.entry) then
		return "connection"
	end
	return "about"
end

-- Each section's mark in the rail: a tone (as the chips') and a tooltip.
local function sectionState(page, view, id)
	local function chipOf(check)
		local def = check and TRP3Page.STATE_CHIP[check.state]
		return def and def[2] or "muted", def and def[1] or "Not available"
	end
	if id == "about" or id == "traits" then
		local tone, text = chipOf(view.checks[id])
		return tone, text
	elseif id == "connection" then
		local s = view.connection and view.connection.state
		if s == "connected" then return "public", "Connected" end
		if s == "default" or s == "linked" or s == "switched" then return "waiting", "Needs your choice" end
		return "muted", "Not connected"
	elseif id == "character" or id == "appearance" then
		local managed, conflict, staged = 0, false, false
		for _, mid in ipairs(TRP3Page.SECTION_MAPPINGS[id]) do
			if view.fieldConflicts[mid] then conflict = true end
			if page.staged[mid] then staged = true end
			if view.bound and view.policies[mid] == "dawnward" then managed = managed + 1 end
		end
		if id == "appearance" and view.checks.glance and view.checks.glance.state == "conflict" then conflict = true end
		if conflict then return "danger", "Conflict: see Conflicts and recovery" end
		if staged then return "waiting", "Not saved yet: Authorize… to save" end
		return managed > 0 and "public" or "muted", managed .. " of " .. #TRP3Page.SECTION_MAPPINGS[id]
			.. " kept up to date by Dawnward"
	elseif id == "status" then
		for _, f in ipairs(ns.TRP3Sync.ORDER) do
			if view.checks[f] and view.checks[f].state == "blocked" then return "danger", "Something is blocked" end
		end
		return ns.TRP3Commands.AnyManaged(view.bound and view.entry or nil) and "public" or "muted", "Status"
	elseif id == "recovery" then
		local n = #TRP3Page.Conflicts(view)
		return n > 0 and "waiting" or "muted", n > 0 and (plural(n, "conflict waits", "conflicts wait")
			.. " for your choice") or "No conflicts"
	end
	return "muted", ""
end

local function toneColor(tone, theme)
	if tone == "public" then return ns.Themes.VISIBILITY_COLORS.public end
	if tone == "waiting" then return ns.Themes.STATUS_COLORS.waiting end
	if tone == "danger" then return theme.danger end
	if tone == "accent" then return theme.accent end
	return Style.Tones(theme).dot
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

	-- Earlier names of the sections (v0.9 tabs).
	if page.feature == "overview" then page.feature = "connection" end
	if page.feature == "mappings" then page.feature = "character" end
	if available and not page.feature then
		page.feature = TRP3Page.DefaultSection(view)
	end
	page.feature = page.feature or "about"
	local feature = page.feature

	-- The conflicts (the shown part's first) and the callout.
	page.conflicts = available and TRP3Page.Conflicts(view, feature) or {}
	page.conflictFeature = page.conflicts[1] and page.conflicts[1].id or nil
	page.conflict:SetShown(page.conflictFeature ~= nil)
	page.noConflict:SetShown(page.conflictFeature == nil)
	if page.conflictFeature then
		local c = page.conflicts[1]
		local reason = c.reason or "Total RP 3 changed since Dawnward last wrote"
		page.conflict:SetTitle("Conflict on " .. c.label)
		page.conflictText:SetText(excerpt(reason, 120) .. ". Nothing will be overwritten until you choose.")
		Widgets.Tooltip(page.conflictHover, page.conflict.title:GetText(), plain(reason)
			.. ". Nothing will be overwritten until you choose.")
		local others = {}
		for i = 2, #page.conflicts do others[#others + 1] = page.conflicts[i].label end
		page.otherConflicts:SetText(#others > 0 and ("Also waiting: " .. table.concat(others, ", ")
			.. ". Each shows here once the one above is settled.") or "")
	else
		page.otherConflicts:SetText("")
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

	-- The rail: the open section, and every section's state at a glance.
	page.nav:Select(feature)
	local theme = Style.Current()
	for _, b in ipairs(page.nav.buttons) do
		local tone, text = sectionState(page, view, b.segmentId)
		Style.Color(b.dot, toneColor(tone, theme))
		b.state = tone
		Widgets.Tooltip(b, SECTION_LABEL[b.segmentId], text)
	end
	-- Biography and Personality share one view, as do the two mapping
	-- sections: show the open section's view, hide every other one.
	local open = page.views[feature]
	for _, v in pairs(page.views) do
		if v ~= open then v:Hide() end
	end
	open:Show()
	page.title:SetText(SECTION_LABEL[feature])
	page.title:SetWidth(page.innerWidth)
	if feature == "character" or feature == "appearance" then
		TRP3Page.RefreshMappings(page, view)
	elseif feature == "connection" then
		TRP3Page.RefreshOverview(page, view)
	elseif feature == "status" then
		TRP3Page.RefreshStatus(page, view)
	elseif feature == "recovery" then
		local n = #page.conflicts
		page.chip:SetChip(n > 0 and plural(n, "conflict", "conflicts") or "No conflicts", n > 0 and "waiting" or "muted")
		page.explain:SetText(TRP3Page.RECOVERY_EXPLAIN)
	else
		TRP3Page.RefreshFeature(page, view, feature)
	end
	-- The title never runs under the chip.
	page.title:SetWidth(page.innerWidth - page.chip:GetWidth() - 12)
end

--- Biography and Personality: the proposed change, the choices (Biography)
-- and the preview of what Total RP 3 will show.
function TRP3Page.RefreshFeature(page, view, feature)
	local P = TRP3Page.CARD_PAD
	local check = view.checks[feature]
	local optedIn = view.bound and view.policies[feature] == "dawnward"
	local chip = TRP3Page.STATE_CHIP[check.state] or { check.state, "muted" }
	page.chip:SetChip(chip[1], chip[2])
	page.title:SetText(FEATURE_LABEL[feature] .. ": " .. (TITLE_PHRASE[check.state] or check.state))
	page.explain:SetText(TRP3Page.EXPLAIN[feature])
	local reasons = reasonsText(feature, check, optedIn)
	page.reasons:SetText(excerpt(reasons, TRP3Page.REASON_CHARS))
	TRP3Page.SetWarning(page.reasons, check.state == "conflict" or check.state == "blocked")
	Widgets.Tooltip(page.reasonsHover, chip[1], plain(reasons)
		.. (check.state == "conflict" and "\n\nChoose what happens in Conflicts and recovery." or ""))
	local kept = keepText(feature, check, view)
	page.keepText:SetText(kept)
	Widgets.Tooltip(page.keepHover, "Your own text", kept)

	local about = feature == "about"
	page.choices:SetShown(about)
	local top = page.previewTop[feature]
	page.preview:ClearAllPoints()
	page.preview:SetPoint("TOPLEFT", P, -top)
	page.preview:SetSize(page.innerWidth, page.mainHeight - page.previewBottom - top)
	page.render.scroll:SetShown(about)
	if about then
		local char = realChar()
		local prefs = char and char.story and char.story.prefs or ns.StorySchema.NewPrefs()
		for _, seg in ipairs(page.overviewChoices) do
			seg:Select(prefs[seg.key] or ns.StorySchema.DEFAULT_PREFS[seg.key])
		end
		local section = check.section
		local blocks, template = ns.TRP3Commands.AboutDisplay(char, section and section.TE)
		page.previewHead:SetText("HOW TOTAL RP 3 WILL SHOW IT · TEMPLATE " .. template)
		page.previewText:SetShown(#blocks == 0 or (#blocks == 1 and #blocks[1].items == 0))
		page.previewText:SetText(previewText("about", { about = "" }))
		for _, row in ipairs(page.traitRows) do row:Hide() end
		TRP3Page.Render(page.render, page.previewText:IsShown() and {} or blocks)
	else
		page.previewHead:SetText("DAWNWARD'S TRAITS IN TOTAL RP 3")
		local traits = view.preview.traits
		page.previewText:SetText(previewText("traits", view.preview))
		page.previewText:SetShown(#traits == 0)
		TRP3Page.Render(page.render, {})
		for i, row in ipairs(page.traitRows) do
			local t = traits[i]
			row:SetShown(t ~= nil)
			if t then
				row.left:SetText(plain(t.LT))
				row.right:SetText(plain(t.RT))
				-- V2 of 20 leans to the left word (TRP3's own bar).
				row.fill:SetWidth(math.max(1, math.floor(row.barWidth * t.V2 / 20)))
			end
		end
	end

	-- Approve only for an opted-in feature with a change and no conflict;
	-- the click still goes through every guard in Sync.RunFeature.
	page.approve:SetEnabled(optedIn and check.state == "ready")
	Widgets.Tooltip(page.approve, "Approve and write", optedIn
		and "Writes this change now, through every safety check: backup first, read back, undone at once if "
			.. "anything differs. Same as /dawnward trp3 sync."
		or "Turn on syncing for this first.")
	page.notNow:SetEnabled(check.state == "ready")
	local name = about and "biography" or "traits"
	if optedIn then
		page.toggle:SetText("Stop syncing " .. name)
		page.toggle:SetVariant("danger")
	else
		page.toggle:SetText("Enable syncing " .. name .. "…")
		page.toggle:SetVariant("default")
	end
end

--- Connection and status ------------------------------------------------------------

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

-- Log lines that report a write that did not happen or was undone.
local PROBLEM = { "write failed", "not written", "did not read back" }

--- The newest problem in the log: { at, text }, or nil. Pure.
function TRP3Page.LastProblem(log)
	for i = #(log or {}), 1, -1 do
		local line = log[i]
		for _, word in ipairs(PROBLEM) do
			if line.text and line.text:find(word, 1, true) then
				return line
			end
		end
	end
	return nil
end

--- The Connection lines: { { label, value }, ... }. Pure (from view).
function TRP3Page.OverviewLines(view, _, characterKey)
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
	local managed, total = 0, 0
	for _, id in ipairs(ns.TRP3Ledger.MAPPINGS) do
		total = total + 1
		if view.bound and view.policies[id] == "dawnward" then managed = managed + 1 end
	end
	if c.state == "switched" then
		add("Connected character", "Paused · connected to " .. (c.connectedName and ("\"" .. plain(c.connectedName)
			.. "\"") or "another profile") .. ", not the active one")
	else
		add("Connected character", managed > 0 and (tostring(characterKey) .. " · " .. managed .. " of " .. total
			.. " items kept up to date") or "Not connected")
	end
	local last = TRP3Page.LastWrite(view.log)
	add("Last successful sync", last and date("%d %b %Y, %H:%M", last) or "Nothing written yet")
	return lines
end
TRP3Page.ConnectionLines = TRP3Page.OverviewLines

--- The Synchronization status lines: { { label, value, detail }, ... }.
-- Pure (from view and the character's settings).
function TRP3Page.StatusLines(view, char)
	local lines = {}
	local function add(name, value, detail) lines[#lines + 1] = { name, value, detail } end
	local function reasons(check)
		return check and #check.reasons > 0 and plain(table.concat(check.reasons, "; ")) or nil
	end
	local prefs = char and char.story and char.story.prefs or {}
	local public = ns.TRP3Sync.ApplySettings({}, char)
	local layout = ({ current = "your Total RP 3 template", text = "template 1", frames = "template 2 (frames)",
		sections = "template 3 (sections)" })[prefs.trp3Layout or "current"]
	add("Biography", stateText(view.checks.about) .. " · " .. (ns.TRP3Sync.UsesProfile(public)
		and "whole story and profile" or "summary block") .. " in " .. layout, reasons(view.checks.about))
	add("Personality", stateText(view.checks.traits), reasons(view.checks.traits))
	local fields, fieldTotal = 0, 0
	for _, id in ipairs(TRP3Page.SECTION_MAPPINGS.character) do
		fieldTotal = fieldTotal + 1
		if view.bound and view.policies[id] == "dawnward" then fields = fields + 1 end
	end
	add("Character information", stateText(view.checks.fields) .. " · " .. fields .. " of " .. fieldTotal
		.. " by Dawnward", reasons(view.checks.fields))
	add("Additional information", stateText(view.checks.misc), reasons(view.checks.misc))
	add("At First Glance", stateText(view.checks.glance), reasons(view.checks.glance))
	local last = TRP3Page.LastWrite(view.log)
	add("Last successful sync", last and date("%d %b %Y, %H:%M", last) or "Nothing written yet",
		"Each write is read back from Total RP 3 and counts only when it matched.")
	local problem = TRP3Page.LastProblem(view.log)
	add("Last problem", problem and ((problem.at and problem.at > 0 and (date("%d %b, %H:%M", problem.at) .. " · ")
		or "") .. excerpt(problem.text, 90)) or "None", problem and plain(problem.text) or nil)
	local n = #TRP3Page.Conflicts(view)
	add("Conflicts", n == 0 and "None" or (plural(n, "item waits", "items wait") .. " for your choice (Conflicts "
		.. "and recovery)"))
	return lines
end

-- Connection: the profile lines, the connection note and its buttons.
function TRP3Page.BuildConnection(page, P, innerW)
	local o = sectionView(page, "connection")
	page.overview = o
	page.overviewRows = {}
	local R, LW = TRP3Page.STATUS_ROW, TRP3Page.OVERVIEW_LABEL
	for i = 1, 3 do
		local y = -(TRP3Page.HEAD_HEIGHT + (i - 1) * R)
		local name = oneLine(o, "muted", LW - 8)
		name:SetPoint("TOPLEFT", P, y)
		local value = oneLine(o, "body", innerW - LW)
		value:SetPoint("TOPLEFT", P + LW, y)
		local hover = hoverOver(o, value)
		page.overviewRows[i] = { name = name, value = value, hover = hover }
	end
	-- What is connected or what stops it, under the lines; the primary and
	-- second buttons change with the state (TRP3Page.ConnectionButtons) and
	-- Refresh connection reads Total RP 3 again.
	local B = TRP3Page.CONNECTION_BUTTONS
	page.connectionNote = paragraph(o, "body", innerW, 3)
	page.connectionNote:SetPoint("TOPLEFT", P, -TRP3Page.CONNECTION_NOTE_TOP)
	-- Only for older characters, under the note.
	page.switchModel = Widgets.Button(o, "Publish whole profile…", 190, Style.CONTROL.compact, "ghost")
	page.switchModel:SetPoint("TOPLEFT", P, -(TRP3Page.CONNECTION_NOTE_TOP + 3 * TRP3Page.LINE + 12))
	page.switchModel:SetScript("OnClick", function() TRP3Page.AskSwitchModel() end)
	Widgets.Tooltip(page.switchModel, "Publish whole profile", "An earlier version kept part of this character's "
		.. "profile back from Total RP 3. This one-time confirmation lists it first and can be undone. "
		.. "Same as /dawnward publish.")
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
end
TRP3Page.BuildOverview = TRP3Page.BuildConnection

function TRP3Page.RefreshOverview(page, view)
	local char = realChar()
	local managed = ns.TRP3Commands.AnyManaged(view.bound and view.entry or nil)
	page.chip:SetChip(managed and "Connected" or "Not connected", managed and "public" or "muted")
	page.explain:SetText(TRP3Page.CONNECTION_EXPLAIN)
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

-- Synchronization status: one line per part and the never-sent box.
function TRP3Page.BuildStatus(page, P, innerW)
	local sv = sectionView(page, "status")
	page.statusRows = {}
	local R, LW = TRP3Page.STATUS_ROW, TRP3Page.STATUS_LABEL
	for i = 1, 8 do
		local y = -(TRP3Page.HEAD_HEIGHT + (i - 1) * R)
		local name = oneLine(sv, "muted", LW - 8)
		name:SetPoint("TOPLEFT", P, y)
		local value = oneLine(sv, "body", innerW - LW)
		value:SetPoint("TOPLEFT", P + LW, y)
		local hover = CreateFrame("Frame", nil, sv)
		hover:SetPoint("TOPLEFT", P, y)
		hover:SetSize(innerW, R)
		page.statusRows[i] = { name = name, value = value, hover = hover }
	end
	local top = TRP3Page.HEAD_HEIGHT + 8 * R + 10
	page.hidden = box(sv, "plain")
	page.hidden:SetPoint("TOPLEFT", P, -top)
	page.hidden:SetSize(innerW, 28 + 4 * TRP3Page.LINE + 18)
	local hiddenHead = Widgets.Label(page.hidden, "GameFontNormalSmall", false, "eyebrow")
	hiddenHead:SetPoint("TOPLEFT", 10, -9)
	hiddenHead:SetText("NEVER SENT, OR NOT SUPPORTED")
	page.hiddenText = paragraph(page.hidden, "navText", innerW - 20, 2)
	page.hiddenText:SetPoint("TOPLEFT", 10, -28)
	page.unsupported = paragraph(page.hidden, "muted", innerW - 20, 2)
	page.unsupported:SetPoint("TOPLEFT", 10, -(28 + 2 * TRP3Page.LINE + 8))
	page.unsupported:SetText(TRP3Page.UNSUPPORTED_TEXT)
	page.hiddenHover = hoverOver(page.hidden, page.hidden)
	Widgets.Tooltip(page.hiddenHover, "Never sent", TRP3Page.UNSUPPORTED_DETAIL)
end

function TRP3Page.RefreshStatus(page, view)
	local char = realChar()
	local lines = TRP3Page.StatusLines(view, char)
	local attention = 0
	for _, f in ipairs(ns.TRP3Sync.ORDER) do
		local s = view.checks[f] and view.checks[f].state
		if s == "blocked" or s == "conflict" or s == "ready" then attention = attention + 1 end
	end
	page.chip:SetChip(attention > 0 and plural(attention, "part needs you", "parts need you") or "Nothing waiting",
		attention > 0 and "waiting" or "muted")
	page.explain:SetText(TRP3Page.STATUS_EXPLAIN)
	for i, row in ipairs(page.statusRows) do
		local line = lines[i]
		row.name:SetShown(line ~= nil)
		row.value:SetShown(line ~= nil)
		if line then
			row.name:SetText(line[1])
			row.value:SetText(line[2])
			TRP3Page.SetWarning(row.value, line[1] == "Last problem" and line[2] ~= "None")
			Widgets.Tooltip(row.hover, line[1], line[3] and (line[2] .. "\n\n" .. line[3]) or line[2])
		end
	end
	-- The Biography line's hover traces the About page from your story to
	-- Total RP 3, link by link (the same read-only lines as trp3 diagnose).
	local d = deps()
	local ok, trace = pcall(function() return d and ns.TRP3Commands.AboutDiagnostics(d) end)
	if ok and type(trace) == "table" and lines[1] then
		Widgets.Tooltip(page.statusRows[1].hover, lines[1][1], lines[1][2] .. "\n\n" .. plain(table.concat(trace, "\n")))
	end
	page.hiddenText:SetText(TRP3Page.HiddenText(char))
	Widgets.Tooltip(page.hiddenHover, "Never sent", TRP3Page.HiddenText(char) .. "\n\n" .. TRP3Page.UNSUPPORTED_DETAIL)
end

-- Connection button sizes and the connection note's place (under the lines).
TRP3Page.CONNECTION_BUTTONS = { primary = 168, second = 128, refresh = 150 }
TRP3Page.CONNECTION_NOTE_TOP = TRP3Page.HEAD_HEIGHT + 3 * TRP3Page.STATUS_ROW + 10

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
	ns.MainWindow.AskPublishWholeProfile()
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
		return "nothing to write"
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
			detail = staged and "Dawnward's own block, from your profile (after you authorize)"
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
		detail = "Dawnward's old value will be removed from TRP3 first (no longer in your profile)"
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
	local section = page.feature
	local ids = TRP3Page.SECTION_MAPPINGS[section]
	local managed = 0
	for _, id in ipairs(ids) do
		if TRP3Page.Shown(page, id) == "dawnward" then managed = managed + 1 end
	end
	page.chip:SetChip(next(page.staged) and "Not saved yet" or (managed .. " of " .. #ids .. " by Dawnward"),
		next(page.staged) and "waiting" or "muted")
	page.explain:SetText(section == "appearance" and TRP3Page.APPEARANCE_EXPLAIN or TRP3Page.MAPPINGS_EXPLAIN)
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
	page.mapPages = math.max(1, math.ceil(#ids / page.mapPerPage))
	page.mapPage = math.max(1, math.min(page.mapPage or 1, page.mapPages))
	local paged = page.mapPages > 1
	page.mapPageLabel:SetShown(paged)
	page.mapPrev:SetShown(paged)
	page.mapNext:SetShown(paged)
	page.mapPageLabel:SetText(string.format("Page %d of %d", page.mapPage, page.mapPages))
	page.mapPrev:SetEnabled(page.mapPage > 1)
	page.mapNext:SetEnabled(page.mapPage < page.mapPages)
	page.unsupportedNote:SetShown(section == "character")
	page.glance:SetShown(section == "appearance")
	if section == "appearance" then
		local lines = ns.TRP3Commands.GlanceLines(realChar())
		table.remove(lines, 1)
		for i, line in ipairs(lines) do lines[i] = plain((line:gsub("^%s+", ""))) end
		page.glanceText:SetText(table.concat(lines, "\n"))
		Widgets.Tooltip(page.glanceHover, "At First Glance", TRP3Page.EXPLAIN.glance)
	end
	for _, row in ipairs(page.mapRows) do
		row:SetShown(row.section == section and row.mapPage == page.mapPage)
		if row.section == section then
			local name, detail = TRP3Page.RowText(page, row.id)
			row.name:SetText(name)
			row.detail:SetText(detail)
			row.selector:Select(TRP3Page.Shown(page, row.id))
			local m = ns.TRP3Sync.MappingOf(row.id)
			local where = m and (m.key and ("Total RP 3 field " .. m.key) or "Total RP 3 additional information")
			local about = m and (where .. (m.msp and (" (MSP " .. m.msp .. "). ") or ". ")
				.. (m.risk == "high" and "Players usually write this themselves in Total RP 3; it stays managed by "
					.. "Total RP 3 unless you choose otherwise. " or "")
				.. "Dawnward writes it only from your " .. m.label .. ", only while Total RP 3 still holds the "
				.. "value Dawnward last wrote.") or TRP3Page.EXPLAIN[row.id]
			-- The detail line may be cut on the page; the tooltip has it whole.
			Widgets.Tooltip(row.hover, name, detail .. "\n\n" .. about)
			if row.import then
				local diff = diffRow(view, row.id)
				row.import:SetEnabled(diff ~= nil and diff.importable == true)
				Widgets.Tooltip(row.import, "Import into Dawnward", "Copies Total RP 3's " .. m.trp3 .. " into your "
					.. "Dawnward " .. m.label .. " (you confirm first). Never automatic.")
			end
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
					what = view.preview.about == "" and "nothing to write yet" or "adds Dawnward's own block to your About"
				elseif id == "glance" then
					what = "writes the At First Glance entries you wrote for it, into free slots"
				else
					what = #view.preview.traits == 0 and "nothing to write yet"
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
	lines[#lines + 1] = "EXPERIMENTAL: uses Total RP 3 internals with no official support. Dawnward writes "
		.. "from your character profile, a backup is taken before every write, and every write can be rolled back."
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
		.. m.label .. "?\n\nIt becomes part of your Dawnward profile. Nothing is written to Total RP 3.", "Import", function()
		act(function()
			local _, message = ns.TRP3Commands.Import(ns.ctx, id, "private")
			return message
		end)
	end)
end

--- The rollback confirmation for a mode ("own" or "exact"), naming what an
-- exact restore would bring back that your profile no longer has.
function TRP3Page.RollbackText(preview, mode, id)
	local head = id and ("Restore your Total RP 3 section from Dawnward's backup #" .. id .. "?")
		or TRP3Page.ROLLBACK_NEWEST
	local lines = { head, "" }
	if mode == "own" then
		lines[#lines + 1] = "Safe restore: your own text comes back from the backup; Dawnward's part is rebuilt from "
			.. "your profile as it is now. Other edits made to that section since then are undone. The current state is "
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
