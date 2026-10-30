-- Character section (v0.7, approved mockups docs/design/mockups/
-- character-profile.png and proposed-character-showcase.png).
--
-- Three views of the same character, switched from the header:
--   Profile    grouped panels: Identity, Background & biography and Summary &
--              motivation (tiles and cards, each with its own visibility chip
--              and Edit button), and beside them Personality (the six axes,
--              real values, changes waiting for approval) and Family &
--              relationships (family and history).
--   Preview    exactly what is public: the core's public projection
--              (Projection.GetPublic, the same one `/dawnward show public`,
--              share exports and Total RP 3 sync use). Nothing is filtered
--              here; the UI only lays it out.
--   Showcase   the live model with what the game says about the character
--              and what the player wrote, kept apart (UI/Showcase.lua).
-- Deliberately small: it is not a copy of Total RP 3's editor. All writes
-- go through Core/Actions.lua.
local _, ns = ...
local Widgets, MainWindow, Schema, Themes, Style = ns.Widgets, ns.MainWindow, ns.Schema, ns.Themes, ns.Style

local CharacterView = {}
ns.CharacterView = CharacterView

CharacterView.FAMILY_HINT = "Parents, siblings, a lost cousin: anyone your character counts as family."
CharacterView.HISTORY_HINT = "Moments from before the story Dawnward records, in your own words."
CharacterView.INTRO = "Only fields marked Public can ever reach Total RP 3 or a shared export."
CharacterView.PREVIEW_INTRO = "This is everything about your character that can leave Dawnward: a share "
	.. "export, and Total RP 3 if you turn sync on. Private and secret details are never included."
CharacterView.NOTHING_PUBLIC = "Nothing is public yet. Use a field's visibility chip to make it Public."

-- The profile's groups, in order (mockup: identity tiles, then background,
-- then the long texts). Any field not named here joins "background", so a
-- new profile field always appears.
CharacterView.GROUPS = {
	{ id = "identity", title = "Identity", keys = { "name", "title", "pronouns", "race", "class", "age" } },
	{ id = "background", title = "Background & biography", keys = { "homeland", "faith", "occupation", "appearance" } },
	{ id = "words", title = "Summary & motivation", keys = { "summary", "motivation" } },
}
do
	local named = {}
	for _, group in ipairs(CharacterView.GROUPS) do
		for _, key in ipairs(group.keys) do named[key] = true end
	end
	for _, field in ipairs(Schema.FIELDS) do
		if not named[field.key] then
			table.insert(CharacterView.GROUPS[2].keys, field.key)
		end
	end
end

-- Layout (UI units, inside the content area).
local L = {
	introHeight = 26,   -- the line under the header
	scrollBar = 22,
	rightWidth = 268,   -- Personality and Family column (mockup: 268)
	colGap = 16,
	panelGap = 12,
	pad = Widgets.PANEL_PAD,
	panelTop = 36,      -- below a panel's eyebrow title
	tileGap = 8,
	tileMin = 86,       -- mockup tile min-height
	tileCols = 3,
	visWidth = 72,
	editWidth = 44,
	cardEditWidth = 56,
	controlHeight = 20,
	headerOffset = 71,  -- header buttons above the content area, level with the close button
}
CharacterView.LAYOUT = L
local EMPTY_VALUE = "Not set"

--- Display text for a family member.
function CharacterView.FamilyText(item)
	local relation = item.relation and (item.relation:sub(1, 1):upper() .. item.relation:sub(2)) or "Relative"
	local status = item.status and item.status ~= "unknown" and (" (" .. item.status .. ")") or ""
	return relation .. ": " .. (item.name or "unnamed") .. status
end

function CharacterView.HistoryText(item)
	return (item.when and (item.when .. ": ") or "") .. (item.text or "")
end

--- Column widths for a content width: { child, left, right, rightX }. Pure.
function CharacterView.Columns(contentWidth)
	local child = contentWidth - L.scrollBar
	local left = child - L.rightWidth - L.colGap
	return { child = child, left = left, right = L.rightWidth, rightX = left + L.colGap }
end

--- Tile width in a group panel of the left column. Pure.
function CharacterView.TileWidth(contentWidth)
	local inner = CharacterView.Columns(contentWidth).left - 2 * L.pad
	return math.floor((inner - (L.tileCols - 1) * L.tileGap) / L.tileCols)
end

--- Rows to show, in order (pure; tested). Fields carry their group; family
-- and history are in the right-hand column.
function CharacterView.BuildSpecs(char)
	local specs = {}
	for _, group in ipairs(CharacterView.GROUPS) do
		for _, key in ipairs(group.keys) do
			local field = Schema.FIELD_BY_KEY[key]
			if field then
				specs[#specs + 1] = { kind = "field", field = field, group = group.id,
					entry = char and char.fields[field.key] }
			end
		end
	end
	specs[#specs + 1] = { kind = "heading", text = "Family" }
	for _, item in ipairs(char and char.family or {}) do
		specs[#specs + 1] = { kind = "item", list = "family", item = item, text = CharacterView.FamilyText(item),
			detail = item.notes }
	end
	specs[#specs + 1] = { kind = "add", list = "family", text = CharacterView.FAMILY_HINT }
	specs[#specs + 1] = { kind = "heading", text = "History" }
	for _, item in ipairs(char and char.history or {}) do
		specs[#specs + 1] = { kind = "item", list = "history", item = item, text = CharacterView.HistoryText(item) }
	end
	specs[#specs + 1] = { kind = "add", list = "history", text = CharacterView.HISTORY_HINT }
	return specs
end

--- Personality rows (pure; tested): one per axis, in registry order,
-- { axis, value (nil when not set), visibility, pending = net waiting delta,
-- waiting = number of waiting changes, left / right / meaning = the words
-- shown (the player's own where they wrote any, #21), custom, locked },
-- plus the total waiting.
function CharacterView.PersonalityRows(char)
	local pendingBy, total = {}, 0
	if char and char.story and ns.Evolution then
		for _, change in ipairs(ns.Evolution.Pending(char)) do
			local p = pendingBy[change.axis] or { delta = 0, count = 0 }
			p.delta, p.count = p.delta + change.delta, p.count + 1
			pendingBy[change.axis] = p
			total = total + 1
		end
	end
	local rows = {}
	for _, axis in ipairs(Schema.PERSONALITY_AXES) do
		local entry = char and char.personality and char.personality[axis.id]
		local p = pendingBy[axis.id]
		local left, right, meaning, custom = ns.AxisMeanings.Labels(char, axis)
		rows[#rows + 1] = { axis = axis, value = entry and entry.value, visibility = entry and entry.visibility,
			pending = p and p.delta or 0, waiting = p and p.count or 0, left = left, right = right,
			meaning = meaning, custom = custom, locked = ns.AxisMeanings.IsLocked(char, axis.id) }
	end
	return rows, total
end

--- The approval line over the personality axes. Pure.
function CharacterView.ApprovalText(char, waiting)
	if waiting > 0 then
		return waiting == 1 and "1 change waits for your approval in Story."
			or (waiting .. " changes wait for your approval in Story.")
	end
	local approval = char and char.story and char.story.prefs and char.story.prefs.approval
	if approval == "auto" then
		return "Story changes apply on their own; you can reverse them in Story."
	end
	return "Changes from your story choices need your approval."
end

--- The public preview, from a public projection (Projection.GetPublic).
-- Returns { { title, lines = { text } } } and whether anything is public.
-- Pure: it only lays out what the projection already contains.
function CharacterView.PublicPreview(public)
	local sections, any = {}, false
	local function add(title, lines)
		if #lines > 0 then
			any = true
			sections[#sections + 1] = { title = title, lines = lines }
		end
	end
	local lines = {}
	for _, field in ipairs(Schema.FIELDS) do
		local entry = public.fields and public.fields[field.key]
		if entry then lines[#lines + 1] = field.label .. ": " .. tostring(entry.value) end
	end
	add("Profile", lines)
	lines = {}
	for _, axis in ipairs(Schema.PERSONALITY_AXES) do
		local entry = public.personality and public.personality[axis.id]
		if entry then
			lines[#lines + 1] = string.format("%s - %s: %d/20", axis.left, axis.right, entry.value or 0)
		end
	end
	add("Personality", lines)
	lines = {}
	for _, item in ipairs(public.family or {}) do
		lines[#lines + 1] = CharacterView.FamilyText(item) .. (item.notes and (" - " .. item.notes) or "")
	end
	add("Family", lines)
	lines = {}
	for _, item in ipairs(public.history or {}) do lines[#lines + 1] = CharacterView.HistoryText(item) end
	add("History", lines)
	lines = {}
	for _, fact in ipairs(public.facts or {}) do lines[#lines + 1] = tostring(fact.statement or "") end
	add("Facts", lines)
	lines = {}
	for _, stance in ipairs(public.stances or {}) do
		local parts = {}
		if stance.persona then parts[#parts + 1] = stance.persona end
		if stance.conviction then parts[#parts + 1] = stance.conviction end
		lines[#lines + 1] = tostring(stance.subject or "") .. ": " .. table.concat(parts, "; ")
	end
	add("Identity", lines)
	local journal = #(public.journal or {})
	if journal > 0 then
		add("Journal", { journal == 1 and "1 public journal entry" or (journal .. " public journal entries") })
	end
	return sections, any
end

local function hex(color)
	return string.format("%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5))
end

--- Opens the Total RP 3 page of Settings (UI/SettingsPanel.lua).
function CharacterView.OpenTRP3()
	local SettingsPanel = ns.SettingsPanel
	if SettingsPanel and SettingsPanel.OpenPage then
		SettingsPanel.OpenPage("trp3")
		return
	end
	-- Older settings panel without OpenPage: open Settings on its Total RP 3 page.
	if MainWindow.CurrentSection() ~= "settings" then MainWindow.ToggleSettings() end
	if MainWindow.settings then
		MainWindow.settings.page = "trp3"
		MainWindow.Refresh()
	end
end

-- Visibility as a chip (approved mockup): tinted fill and edge in the fixed
-- visibility colour; it stays a button that cycles the level.
local function paintVisibilityChip(b, theme)
	local color = Themes.VISIBILITY_COLORS[b.level] or Themes.VISIBILITY_COLORS.private
	Style.Color(b.bg, color, b.hover and 0.26 or 0.14)
	b.edges:Paint(color, b.hover and 0.9 or 0.55)
	Style.TextColor(b.label, color)
	if not b:IsEnabled() then Style.TextColor(b.label, theme.muted) end
end

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), rows = {}, pool = {}, groups = {},
		mode = "profile" }
	local f = section.frame
	local contentWidth, contentHeight = MainWindow.ContentWidth(), MainWindow.ContentHeight()
	local cols = CharacterView.Columns(contentWidth)

	-- Header actions, level with the close button above the content area.
	local header = CreateFrame("Frame", nil, f)
	header:SetSize(540, 30)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(36 + 12), L.headerOffset)
	section.header = header
	section.previewButton = Widgets.Button(header, "Preview public view", 150, 30)
	section.previewButton:SetPoint("TOPRIGHT", 0, 0)
	Widgets.Tooltip(section.previewButton, "Public profile preview",
		"Shows exactly what can be shared: share exports, and Total RP 3 if you turn sync on.")
	section.showcaseButton = Widgets.Button(header, "Showcase", 120, 30)
	section.showcaseButton:SetPoint("RIGHT", section.previewButton, "LEFT", -8, 0)
	Widgets.Tooltip(section.showcaseButton, "Character Showcase",
		"Your character's live model, what the game says about them, and what you wrote.")
	section.trp3Button = Widgets.Button(header, "Total RP 3...", 110, 30, "ghost")
	section.trp3Button:SetPoint("RIGHT", section.showcaseButton, "LEFT", -8, 0)
	section.trp3Button:SetScript("OnClick", function() CharacterView.OpenTRP3() end)
	Widgets.Tooltip(section.trp3Button, "Total RP 3",
		"Sync status, preview, approval and backups for Total RP 3 (optional).")
	-- Story import (#23): paste a backstory, or read your Total RP 3 About text.
	section.importButton = Widgets.Button(header, "Import story", 110, 30, "ghost")
	section.importButton:SetPoint("RIGHT", section.trp3Button, "LEFT", -8, 0)
	section.importButton:SetScript("OnClick", function() ns.ImportWizard.Open({ from = "character" }) end)
	Widgets.Tooltip(section.importButton, "Import your story",
		"Paste a backstory you already wrote (or read your Total RP 3 About text). It is kept exactly as written; "
		.. "you approve each piece before it becomes part of your character.")

	section.intro = Widgets.Label(f, "GameFontHighlight", false, "muted")
	section.intro:SetPoint("TOPLEFT", 0, -2)
	section.intro:SetWidth(contentWidth)
	section.intro:SetText(CharacterView.INTRO)

	-- Profile: one scroll frame, two columns.
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("CharacterScroll"), f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -L.introHeight)
	scroll:SetPoint("BOTTOMRIGHT", -L.scrollBar, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(cols.child, 100)
	scroll:SetScrollChild(child)
	section.scroll, section.child = scroll, child

	-- Group panels sit behind their tiles: same level as the scroll child,
	-- so the entries (one level up) draw over them.
	local function backPanel(title)
		local panel = Widgets.Panel(child, title)
		local level = child.GetFrameLevel and child:GetFrameLevel()
		if type(level) == "number" and panel.SetFrameLevel then panel:SetFrameLevel(level) end
		return panel
	end
	for _, group in ipairs(CharacterView.GROUPS) do
		section.groups[group.id] = backPanel(group.title)
	end
	section.familyPanel = backPanel("Family & relationships")

	-- Personality: the six axes with their real values.
	local pers = backPanel("Personality")
	section.personality = pers
	pers.status = Widgets.Label(pers, "GameFontHighlightSmall", true, "muted")
	pers.status:SetWidth(cols.right - 2 * L.pad)
	pers.review = Widgets.Button(child, "Review in Story", 130, 22, "primary")
	pers.review:SetScript("OnClick", function() MainWindow.Select("story") end)
	Widgets.Tooltip(pers.review, "Review in Story", "Approve or reject personality changes from your choices.")
	pers.review:Hide()
	pers.axes = {}
	for i = 1, #Schema.PERSONALITY_AXES do
		local a = CreateFrame("Frame", nil, child)
		a:SetSize(cols.right - 2 * L.pad, 34)
		if a.EnableMouse then a:EnableMouse(true) end
		a.left = Widgets.Label(a, "GameFontHighlightSmall", false)
		a.left:SetPoint("TOPLEFT", 0, 0)
		a.right = Widgets.Label(a, "GameFontHighlightSmall", false)
		a.right:SetPoint("TOPRIGHT", 0, 0)
		a.right:SetJustifyH("RIGHT")
		a.track = Style.Solid(a, "ARTWORK")
		a.track:SetPoint("TOPLEFT", 0, -20)
		a.track:SetPoint("TOPRIGHT", 0, -20)
		a.track:SetHeight(4)
		a.knob = Style.Solid(a, "OVERLAY")
		a.knob:SetSize(10, 10)
		a.note = Widgets.Label(a, "GameFontHighlightSmall", false)
		a.note:SetPoint("TOPLEFT", 0, -30)
		a.axisIndex = i
		-- Click: the player's own words, meaning and lock for this axis (#21).
		a:SetScript("OnMouseUp", function(self)
			if section.OpenAxisForm then section:OpenAxisForm(Schema.PERSONALITY_AXES[self.axisIndex]) end
		end)
		pers.axes[i] = a
	end

	-- Preview: the public projection, read-only.
	local preview = CreateFrame("ScrollFrame", Widgets.NextName("CharacterPreview"), f, "UIPanelScrollFrameTemplate")
	preview:SetPoint("TOPLEFT", 0, -L.introHeight)
	preview:SetPoint("BOTTOMRIGHT", -L.scrollBar, 0)
	local previewChild = CreateFrame("Frame", nil, preview)
	previewChild:SetSize(cols.child, 100)
	preview:SetScrollChild(previewChild)
	section.previewScroll = preview
	section.previewPanel = Widgets.Panel(previewChild, "Public profile preview")
	section.previewPanel:SetPoint("TOPLEFT", 0, 0)
	section.previewPanel:SetWidth(cols.child)
	section.previewText = Widgets.Label(section.previewPanel, "GameFontHighlight", true, "body")
	section.previewText:SetPoint("TOPLEFT", L.pad, -L.panelTop)
	section.previewText:SetWidth(cols.child - 2 * L.pad)
	preview:Hide()

	-- Showcase: model, game identity and the player's own words.
	section.showcaseView = ns.Showcase.View(f, contentWidth, contentHeight, {
		onPreferPortrait = function(on)
			local ok, message = ns.Actions.SetShowcasePortrait(ns.ctx, on)
			MainWindow.SetStatus(message)
			return ok
		end,
		onEditProfile = function() section:SetMode("profile") end,
	})
	section.showcaseView:SetPoint("TOPLEFT", 0, 0)
	-- The model card (kept as section.showcase for callers and tests).
	section.showcase = section.showcaseView.model

	local function getRow(index)
		local row = section.pool[index]
		if row then
			return row
		end
		-- Each field, family member and history entry is its own panel, with
		-- its Edit and visibility controls inside it (Widgets.EntryRow).
		row = Widgets.EntryRow(child)
		row.key = Widgets.Label(row, "GameFontNormalSmall", false, "eyebrow")
		row.label = Widgets.Label(row, "GameFontNormal", true)
		row.value = Widgets.Label(row, "GameFontHighlight", true)
		row.detail = Widgets.Label(row, "GameFontHighlightSmall", true)
		row.rule = Widgets.Divider(row)
		row.rule:SetPoint("BOTTOMLEFT", 0, 2)
		row.rule:SetPoint("BOTTOMRIGHT", 0, 2)
		row.rule:Hide()
		if section.decorateRow then
			section.decorateRow(row)
		end
		section.pool[index] = row
		return row
	end

	local function place(row, x, y, width, height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
		row:SetWidth(width)
		if height then row:SetHeight(height) end
		row:Show()
	end

	local function resetRow(row, spec, theme)
		row.spec = spec
		row.key:Hide()
		row.label:Hide()
		row.value:Hide()
		row.detail:Hide()
		row.rule:Hide()
		row.vis:Hide()
		row.edit:Hide()
		row.theme = theme
	end

	local function setValue(row, spec, width, theme)
		local entry = spec.entry
		row.value:Show()
		row.value:SetWidth(width)
		row.value:SetText(entry and entry.value or EMPTY_VALUE)
		Widgets.TextColor(row.value, entry and theme.text or theme.muted)
	end

	local function fieldKey(row, spec, x, y)
		row.key:Show()
		row.key:ClearAllPoints()
		row.key:SetPoint("TOPLEFT", x, y)
		row.key:SetText(spec.field.label:upper())
	end

	-- A short field: a tile in a three-column grid. Returns its height.
	local function measureTile(row, spec, width, theme)
		resetRow(row, spec, theme)
		row:SetPlain(false)
		fieldKey(row, spec, 10, -10)
		row.value:ClearAllPoints()
		row.value:SetPoint("TOPLEFT", 10, -28)
		setValue(row, spec, width - 20, theme)
		section.updateFieldActions(row, spec, "tile")
		return math.max(L.tileMin, 28 + math.max(row.value:GetStringHeight(), 16) + 10 + L.controlHeight + 8)
	end

	-- A long field: a full-width card. Returns its height.
	local function measureCard(row, spec, width, theme)
		resetRow(row, spec, theme)
		row:SetPlain(false)
		fieldKey(row, spec, 12, -14)
		row.value:ClearAllPoints()
		row.value:SetPoint("TOPLEFT", 12, -38)
		setValue(row, spec, width - 24, theme)
		section.updateFieldActions(row, spec, "card")
		return math.max(64, 38 + math.max(row.value:GetStringHeight(), 16) + 12)
	end

	-- A family member or history entry: text, notes, then its controls.
	local function measureItem(row, spec, width, theme)
		resetRow(row, spec, theme)
		row:SetPlain(false)
		row.label:Show()
		row.label:ClearAllPoints()
		row.label:SetPoint("TOPLEFT", 8, -8)
		row.label:SetWidth(width - 16)
		row.label:SetText(spec.text)
		Widgets.TextColor(row.label, theme.text)
		local h = 8 + row.label:GetStringHeight()
		if spec.detail then
			row.detail:Show()
			row.detail:ClearAllPoints()
			row.detail:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
			row.detail:SetWidth(width - 16)
			row.detail:SetText(spec.detail)
			Widgets.TextColor(row.detail, theme.muted)
			h = h + 2 + row.detail:GetStringHeight()
		end
		section.updateItemActions(row, spec)
		return math.max(h + 6 + L.controlHeight + 6, 40)
	end

	-- Headings and the Add line inside the Family & relationships panel.
	local function measurePlain(row, spec, width, theme)
		resetRow(row, spec, theme)
		row:SetPlain(true)
		row.label:Show()
		row.label:ClearAllPoints()
		row.label:SetPoint("TOPLEFT", 0, -4)
		row.label:SetText(spec.text)
		if spec.kind == "heading" then
			row.label:SetWidth(width)
			Widgets.TextColor(row.label, theme.accent)
			row.rule:Show()
			return row.label:GetStringHeight() + 12
		end
		row.label:SetWidth(width - 64)
		Widgets.TextColor(row.label, theme.muted)
		row.edit:SetText("Add")
		row.edit:SetVariant("primary")
		row.edit:SetWidth(56)
		row.edit:ClearAllPoints()
		row.edit:SetPoint("TOPRIGHT", 0, -2)
		Widgets.Tooltip(row.edit, spec.list == "family" and "Add a family member" or "Add a history entry")
		row.edit:Show()
		return math.max(row.label:GetStringHeight() + 10, 28)
	end

	local function paintAxis(a, row, theme, width)
		-- The player's own words where they wrote any (#21).
		local axis = { left = row.left or row.axis.left, right = row.right or row.axis.right }
		a.left:SetText(axis.left)
		a.right:SetText(axis.right)
		local lean = row.value and (row.value > 10 and "right" or row.value < 10 and "left") or nil
		Widgets.TextColor(a.left, lean == "left" and theme.accent or theme.muted)
		Widgets.TextColor(a.right, lean == "right" and theme.accent or theme.muted)
		Style.Color(a.track, theme.edge)
		Style.Color(a.knob, theme.accent)
		a.knob:ClearAllPoints()
		if row.value then
			a.knob:SetPoint("TOPLEFT", math.floor((width - 10) * row.value / 20 + 0.5), -17)
			a.knob:Show()
		else
			a.knob:Hide()
		end
		local note
		if row.waiting > 0 then
			local toward = row.pending > 0 and axis.right or row.pending < 0 and axis.left or nil
			note = (row.waiting == 1 and "1 change waiting" or (row.waiting .. " changes waiting"))
				.. (toward and (": toward " .. toward) or "")
			Widgets.TextColor(a.note, theme.accent)
		elseif not row.value then
			note = "Not set"
			Widgets.TextColor(a.note, theme.muted)
		end
		if row.locked then
			note = (note and (note .. " · ") or "") .. "Locked: story answers never change it"
			if row.waiting == 0 then Widgets.TextColor(a.note, theme.muted) end
		end
		a.note:SetText(note or "")
		a.note:SetShown(note ~= nil)
		local value = row.value and (row.value .. "/20 (" .. axis.left .. " " .. (20 - row.value) .. ", "
			.. axis.right .. " " .. row.value .. ")") or "Not set"
		local vis = row.visibility and Themes.VISIBILITY_LABELS[row.visibility] or nil
		Widgets.Tooltip(a, axis.left .. " - " .. axis.right, value .. (vis and ("\nVisibility: " .. vis) or "")
			.. (row.meaning and ("\n\n" .. row.meaning) or "")
			.. (row.waiting > 0 and "\nA change from your story choices waits in Story." or "")
			.. "\n\nClick to name this axis in your own words, say what it means, or lock it.")
		return note and 46 or 30
	end

	-- Personality panel at (x, y); returns its height.
	local function layoutPersonality(char, x, y, theme)
		local width = cols.right - 2 * L.pad
		local rows, waiting = CharacterView.PersonalityRows(char)
		pers:ClearAllPoints()
		pers:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
		pers:SetWidth(cols.right)
		pers.status:ClearAllPoints()
		pers.status:SetPoint("TOPLEFT", L.pad, -L.panelTop)
		pers.status:SetText(CharacterView.ApprovalText(char, waiting))
		Widgets.TextColor(pers.status, waiting > 0 and theme.accent or theme.muted)
		local h = L.panelTop + pers.status:GetStringHeight() + 10
		pers.waiting = waiting
		if waiting > 0 then
			pers.review:ClearAllPoints()
			pers.review:SetPoint("TOPLEFT", child, "TOPLEFT", x + L.pad, -(y + h))
			pers.review:Show()
			h = h + 22 + 10
		else
			pers.review:Hide()
		end
		for i, row in ipairs(rows) do
			local a = pers.axes[i]
			a:ClearAllPoints()
			a:SetPoint("TOPLEFT", child, "TOPLEFT", x + L.pad, -(y + h))
			local ah = paintAxis(a, row, theme, width)
			a:SetHeight(ah)
			a:Show()
			h = h + ah + 6
		end
		pers.rows = rows
		h = h + L.pad - 6
		pers:SetHeight(h)
		return h
	end

	function section:RenderList(view)
		local specs = CharacterView.BuildSpecs(view.char)
		local theme = view.theme
		self.child:SetWidth(cols.child)
		local rows = {}
		local tileWidth = CharacterView.TileWidth(contentWidth)
		local innerLeft = cols.left - 2 * L.pad

		-- Left column: the field groups.
		local y, i = 0, 1
		for _, group in ipairs(CharacterView.GROUPS) do
			local panel = self.groups[group.id]
			local top = y
			local inner = L.panelTop
			local pending = {} -- tiles waiting to be placed in a grid row
			local function flush()
				if #pending == 0 then return end
				local h = 0
				for _, p in ipairs(pending) do h = math.max(h, p.height) end
				for col, p in ipairs(pending) do
					place(p.row, L.pad + (col - 1) * (tileWidth + L.tileGap), top + inner, tileWidth, h)
				end
				inner = inner + h + L.tileGap
				pending = {}
			end
			while specs[i] and specs[i].kind == "field" and specs[i].group == group.id do
				local spec, row = specs[i], getRow(i)
				rows[i] = row
				if spec.field.kind == "long" then
					flush()
					local h = measureCard(row, spec, innerLeft, theme)
					place(row, L.pad, top + inner, innerLeft, h)
					inner = inner + h + L.tileGap
				else
					pending[#pending + 1] = { row = row, height = measureTile(row, spec, tileWidth, theme) }
					if #pending == L.tileCols then flush() end
				end
				i = i + 1
			end
			flush()
			local height = inner - L.tileGap + L.pad
			panel:ClearAllPoints()
			panel:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -top)
			panel:SetSize(cols.left, height)
			y = top + height + L.panelGap
		end
		local leftHeight = y

		-- Right column: Personality, then Family & relationships.
		local x = cols.rightX
		local ry = layoutPersonality(view.char, x, 0, theme) + L.panelGap
		local famTop = ry
		local famInner = L.panelTop
		local itemWidth = cols.right - 2 * L.pad
		for j = i, #specs do
			local spec, row = specs[j], getRow(j)
			rows[j] = row
			local h
			if spec.kind == "item" then
				h = measureItem(row, spec, itemWidth, theme)
			else
				h = measurePlain(row, spec, itemWidth, theme)
			end
			place(row, x + L.pad, famTop + famInner, itemWidth, h)
			local boxed = spec.kind == "item"
			famInner = famInner + h + (boxed and Widgets.ENTRY.gap or 6)
		end
		local famHeight = famInner + L.pad - 6
		self.familyPanel:ClearAllPoints()
		self.familyPanel:SetPoint("TOPLEFT", child, "TOPLEFT", x, -famTop)
		self.familyPanel:SetSize(cols.right, famHeight)
		local rightHeight = famTop + famHeight

		for k = #specs + 1, #self.pool do
			self.pool[k]:Hide()
		end
		self.child:SetHeight(math.max(leftHeight, rightHeight, 1))
		self.rows, self.specs = rows, specs
	end

	function section:RenderPreview(char)
		local public = char and ns.Projection.GetPublic(char) or nil
		local sections, any = CharacterView.PublicPreview(public or {})
		local theme = self.theme or Style.Current()
		local accent = "|cff" .. hex(theme.accent)
		local out = { CharacterView.PREVIEW_INTRO, "" }
		if not any then
			out[#out + 1] = CharacterView.NOTHING_PUBLIC
		end
		for _, s in ipairs(sections) do
			out[#out + 1] = accent .. s.title:upper() .. "|r"
			for _, line in ipairs(s.lines) do out[#out + 1] = line end
			out[#out + 1] = ""
		end
		self.previewText:SetText(table.concat(out, "\n"))
		self.previewSections, self.previewAny = sections, any
		local h = L.panelTop + self.previewText:GetStringHeight() + L.pad
		self.previewPanel:SetHeight(h)
		previewChild:SetHeight(math.max(h, 1))
	end

	--- profile | preview | showcase. Only the chosen view is shown, so the
	-- model renders only in the showcase. quiet: only show and hide (while
	-- the window is still being built).
	function section:SetMode(mode, quiet)
		self.mode = mode
		local showcase = mode == "showcase"
		self.intro:SetShown(not showcase)
		self.scroll:SetShown(mode == "profile")
		self.previewScroll:SetShown(mode == "preview")
		if showcase then
			self.showcaseView:Show()
			self.showcase:Show()
		else
			self.showcase:Hide()
			self.showcaseView:Hide()
		end
		self.previewButton:SetSelected(mode == "preview")
		self.previewButton:SetText(mode == "preview" and "Back to profile" or "Preview public view")
		self.showcaseButton:SetText(showcase and "Profile fields" or "Showcase")
		if quiet then return end
		MainWindow.SetStatus("")
		MainWindow.Refresh()
	end

	section.previewButton:SetScript("OnClick", function()
		section:SetMode(section.mode == "preview" and "profile" or "preview")
	end)
	section.showcaseButton:SetScript("OnClick", function()
		section:SetMode(section.mode == "showcase" and "profile" or "showcase")
	end)

	function section:ApplyTheme(theme)
		self.theme = theme
		if self.form then self.form:ApplyTheme(theme) end
	end

	function section:Refresh(view)
		self.theme = view.theme
		if self.editor:IsShown() then
			self.ThemeEditor(view.theme)
			return
		end
		self.header:SetShown(not self.form:IsOpen())
		if self.mode == "preview" then
			self:RenderPreview(view.char)
		elseif self.mode == "showcase" then
			self.showcaseView:Refresh(view.char, ns.Actions.ShowcasePortrait(ns.ctx))
		else
			self:RenderList(view)
		end
	end

	section.getRow = getRow
	section.BuildSpecs = CharacterView.BuildSpecs
	CharacterView.AttachEditing(section)
	CharacterView.section = section
	section:SetMode("profile", true)
	return section
end

--- Editing ---------------------------------------------------------------------

--- Adds per-field Edit and visibility buttons and the field editor.
function CharacterView.AttachEditing(section)
	local f = section.frame
	local Actions = ns.Actions

	function section.decorateRow(row)
		row.vis = Widgets.VisibilityButton(row, function(level)
			local spec, _, message = row.spec
			if spec.kind == "item" then
				_, message = section.ChangeItem(function(char, now)
					return ns.Character.SetItemVisibility(char, spec.list, spec.item.id, level, now)
				end)
			else
				_, message = Actions.SetFieldVisibility(ns.ctx, spec.field.key, level)
			end
			MainWindow.SetStatus(message)
			MainWindow.Refresh()
		end)
		-- Drawn as a chip, like the mockup's privacy badges.
		Style.Register(row.vis, paintVisibilityChip)
		row.edit = Widgets.Button(row, "Edit", L.editWidth, L.controlHeight, "ghost")
		row.edit:SetScript("OnClick", function()
			local spec = row.spec
			if spec.kind == "field" then
				section:OpenEditor(spec.field)
			else
				section:OpenItemForm(spec.list, spec.item)
			end
		end)
	end

	--- Family and history: one form for adding and editing (#17). -------------

	section.form = ns.Forms.Create(f, MainWindow.ContentWidth())

	function section.ChangeItem(fn)
		return Actions.WithCharacter(ns.ctx, function(char)
			local r, err = fn(char, ns.ctx.now())
			if not r then return Actions.Fail(err) end
			return r, "Saved."
		end)
	end

	local STATUS = { { "unknown", "Unknown" }, { "living", "Living" }, { "deceased", "Deceased" },
		{ "missing", "Missing" } }
	CharacterView.ITEM_FORMS = {
		family = {
			noun = "family member",
			hint = "Only you write this. New entries start private.",
			fields = {
				{ key = "relation", label = "Relation", kind = "line", max = Schema.LIMITS.short },
				{ key = "name", label = "Name", kind = "line", max = Schema.LIMITS.short },
				{ key = "status", label = "Status", kind = "cycle", values = STATUS },
				{ key = "notes", label = "Notes", kind = "area", max = Schema.LIMITS.long },
			},
		},
		history = {
			noun = "history entry",
			hint = "When it happened, in any words (\"as a child\", \"the Third War\"), and what happened. "
				.. "New entries start private.",
			fields = {
				{ key = "when", label = "When", kind = "line", max = Schema.LIMITS.short },
				{ key = "text", label = "What happened", kind = "area", max = Schema.LIMITS.long },
			},
		},
	}

	-- Saves an edited item field by field; refuses to leave it empty.
	local function updateItem(char, listName, item, values, now)
		local content = false
		for _, field in ipairs(CharacterView.ITEM_FORMS[listName].fields) do
			local v = values[field.key]
			if field.kind ~= "cycle" and type(v) == "string" and v:match("%S") then content = true end
		end
		if not content then return nil, "nothing to save; use Remove to delete it" end
		for _, field in ipairs(CharacterView.ITEM_FORMS[listName].fields) do
			local ok, err = ns.Character.UpdateItem(char, listName, item.id, field.key, values[field.key], now)
			if not ok then return nil, err end
		end
		return item
	end

	function section:OpenItemForm(listName, item)
		local def = CharacterView.ITEM_FORMS[listName]
		local values = {}
		for _, field in ipairs(def.fields) do
			values[field.key] = item and item[field.key]
		end
		self.form:Open({
			title = (item and "Edit " or "Add ") .. def.noun,
			hint = def.hint,
			fields = def.fields,
			values = values,
			deleteLabel = "Remove",
			onDelete = item and function()
				return section.ChangeItem(function(char, now)
					return ns.Character.RemoveItem(char, listName, item.id, now)
				end)
			end or nil,
			onSave = function(v)
				return section.ChangeItem(function(char, now)
					if item then return updateItem(char, listName, item, v, now) end
					return ns.Character.AddItem(char, listName, v, now)
				end)
			end,
		})
		-- The form covers the section; its header actions wait until it closes.
		self.header:Hide()
	end

	--- Personality axes in the player's own words (#21). ---------------------

	CharacterView.AXIS_LOCK_VALUES = { { false, "Story answers may suggest changes" },
		{ true, "Locked: story answers never change it" } }

	function section:OpenAxisForm(axis)
		if not axis then return end
		local entry = ns.AxisMeanings.Get(Actions.Character(ns.ctx), axis.id) or {}
		local L2 = ns.AxisMeanings.LIMITS
		self.form:Open({
			title = "Personality: " .. axis.left .. " - " .. axis.right,
			hint = "Your own words for this axis. Leave a label empty to keep Dawnward's (" .. axis.left .. " / "
				.. axis.right .. "). Values, history and Total RP 3 traits are not changed. Private.",
			fields = {
				{ key = "left", label = "Left end", kind = "line", max = L2.label },
				{ key = "right", label = "Right end", kind = "line", max = L2.label },
				{ key = "meaning", label = "What it means", kind = "area", max = L2.meaning },
				{ key = "locked", label = "Story changes", kind = "cycle", values = CharacterView.AXIS_LOCK_VALUES },
			},
			values = { left = entry.left, right = entry.right, meaning = entry.meaning, locked = entry.locked == true },
			deleteLabel = "Use Dawnward's words",
			onDelete = (entry.left or entry.right or entry.meaning or entry.locked) and function()
				return section.ChangeItem(function(char, now) return ns.AxisMeanings.Reset(char, axis.id, now) end)
			end or nil,
			onSave = function(v)
				return section.ChangeItem(function(char, now)
					return ns.AxisMeanings.Set(char, axis.id, { left = v.left or "", right = v.right or "",
						meaning = v.meaning or "", locked = v.locked == true }, now)
				end)
			end,
		})
		self.header:Hide()
	end

	-- Fields always offer Edit (Add while empty); visibility only once a
	-- value exists. shape: "tile" (controls along the bottom) or "card"
	-- (controls top right).
	function section.updateFieldActions(row, spec, shape)
		local entry = spec.entry
		row.edit:SetText(entry and "Edit" or "Add")
		row.edit:SetVariant("ghost")
		row.edit:ClearAllPoints()
		row.vis:ClearAllPoints()
		if shape == "card" then
			row.edit:SetWidth(L.cardEditWidth)
			row.edit:SetPoint("TOPRIGHT", -10, -8)
			row.vis:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
		else
			row.edit:SetWidth(L.editWidth)
			row.edit:SetPoint("BOTTOMRIGHT", -8, 8)
			row.vis:SetPoint("BOTTOMLEFT", 8, 8)
		end
		Widgets.Tooltip(row.edit, (entry and "Edit " or "Add ") .. spec.field.label)
		row.edit:Show()
		if entry then
			row.vis:Show()
			row.vis:SetLevel(entry.visibility)
		else
			row.vis:Hide()
		end
	end

	-- Family members and history entries: visibility and Edit at the bottom right.
	function section.updateItemActions(row, spec)
		row.edit:SetText("Edit")
		row.edit:SetVariant("ghost")
		row.edit:SetWidth(L.editWidth)
		row.edit:ClearAllPoints()
		row.edit:SetPoint("BOTTOMRIGHT", -8, 6)
		Widgets.Tooltip(row.edit, "Edit")
		row.edit:Show()
		row.vis:ClearAllPoints()
		row.vis:SetPoint("RIGHT", row.edit, "LEFT", -6, 0)
		row.vis:Show()
		row.vis:SetLevel(spec.item.visibility)
	end

	local INSET = 8
	local editor = CreateFrame("Frame", nil, f)
	editor:SetAllPoints(f)
	editor:Hide()
	section.editor = editor

	editor.heading = Widgets.Label(editor, "GameFontNormalLarge", false, "title")
	editor.heading:SetPoint("TOPLEFT", INSET, -10)
	editor.hint = Widgets.Label(editor, "GameFontHighlightSmall", true, "muted")
	editor.hint:SetPoint("TOPLEFT", INSET, -36)
	editor.hint:SetWidth(540)

	editor.line = Widgets.EditLine(editor, 101)
	editor.line:SetPoint("TOPLEFT", INSET + 6, -64)
	editor.line:SetPoint("TOPRIGHT", -INSET, -64)
	editor.area = Widgets.TextArea(editor, 2001, MainWindow.ContentWidth() - 2 * INSET)
	editor.area.frame:SetPoint("TOPLEFT", INSET, -64)
	editor.area.frame:SetPoint("BOTTOMRIGHT", -INSET, 62) -- leaves room for an error line above the buttons
	Widgets.FieldError(editor.line, 540)
	Widgets.FieldError(editor.area.edit, 540)
	-- Keyboard: Enter saves a one-line field (refused input stays, with its
	-- reason beneath); Escape cancels, asking first if something was typed.
	editor.chain = Widgets.FocusChain({
		onSubmit = function() section.SaveEditor() end,
		onEscape = function(dirty) editor.chain.ConfirmDiscard(dirty, function() section.CloseEditor() end) end,
	})

	editor.cancel = Widgets.Button(editor, "Cancel", 90, 22)
	editor.cancel:SetPoint("BOTTOMRIGHT", -INSET, 12)
	editor.save = Widgets.Button(editor, "Save", 90, 22, "primary")
	editor.save:SetPoint("RIGHT", editor.cancel, "LEFT", -6, 0)
	editor.clear = Widgets.Button(editor, "Clear", 90, 22, "danger")
	editor.clear:SetPoint("BOTTOMLEFT", INSET, 12)

	-- The editor's controls paint themselves (UI/Style.lua).
	function section.ThemeEditor() end

	local function input()
		return editor.field.kind == "long" and editor.area.edit or editor.line
	end

	function section:OpenEditor(field)
		local char = Actions.Character(ns.ctx)
		local entry = char and char.fields[field.key]
		editor.field = field
		editor.heading:SetText(field.label)
		editor.hint:SetText(field.kind == "long"
			and "A few sentences are plenty. New fields start private; change visibility from the profile."
			or "One line. New fields start private; change visibility from the profile.")
		local long = field.kind == "long"
		editor.area.frame:SetShown(long)
		editor.line:SetShown(not long)
		editor.clear:SetShown(entry ~= nil)
		Widgets.SetFieldError(editor.line, nil)
		Widgets.SetFieldError(editor.area.edit, nil)
		input():SetText(entry and entry.value or "")
		-- The editor takes the whole section; the other views step aside.
		section.scroll:Hide()
		section.previewScroll:Hide()
		section.showcase:Hide()
		section.showcaseView:Hide()
		section.intro:Hide()
		section.header:Hide()
		editor:Show()
		if self.theme then
			self.ThemeEditor(self.theme)
		end
		editor.chain.SetFields({ input() })
		editor.chain.FocusFirst()
		MainWindow.SetStatus("")
	end

	function section.CloseEditor()
		editor:Hide()
		editor.line:ClearFocus()
		editor.area.edit:ClearFocus()
		section.header:Show()
		-- Back to the view the player was in (this also refreshes).
		section:SetMode(section.mode)
	end

	function section.SaveEditor()
		local ok, message = Actions.SetField(ns.ctx, editor.field.key, input():GetText())
		if ok then
			section.CloseEditor()
			MainWindow.SetStatus(message)
		else
			-- Beside the field, which keeps what was typed and the focus.
			Widgets.SetFieldError(input(), message)
			input():SetFocus()
		end
	end

	function section.ConfirmClear()
		local field = editor.field
		Widgets.Confirm("Clear " .. field.label .. "?\n\nThis removes the saved value.", "Clear", function()
			local _, message = Actions.ClearField(ns.ctx, field.key)
			section.CloseEditor()
			MainWindow.SetStatus(message)
		end)
	end

	editor.save:SetScript("OnClick", section.SaveEditor)
	editor.cancel:SetScript("OnClick", section.CloseEditor)
	editor.clear:SetScript("OnClick", section.ConfirmClear)
end

MainWindow.RegisterSection({ id = "character", label = "Character", order = 2, heading = "Profile", titleInset = 420,
	icon = "Interface\\Icons\\INV_Misc_Head_Human_01", create = create })
