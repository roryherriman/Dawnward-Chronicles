-- Character section (v0.7, refined in v0.8 and v0.10 towards the approved
-- mockups docs/design/mockups/character-profile.png and
-- proposed-character-showcase.png; the remaining differences are in
-- docs/design/audit/v10-character.md).
--
-- Two views of the same character, switched from the header:
--   Profile    the left column scrolls (as the mockup): identity tiles on
--              the window ground (three to a row), Summary and Motivation
--              cards, Background & biography (tiles, Appearance and the
--              imported story with "Read full story"), Details and History.
--              The right column stands still: Personality (the six axes in
--              compact rows, the player's own axis words, "changes need
--              your approval") and Family (name and one meta line per
--              member, "+N more" when the column is full).
--              Race, class and first name read from the game until the
--              player writes their own (Character.FieldOrGame); the game's
--              value is only shown, never saved. An empty field is a dashed
--              tile with "+ Add" (mockup: the Age tile).
--              v0.10: the whole profile is what Total RP 3 shows once it is
--              connected (Core/Publication.lua), so nothing here is sorted
--              into Public / Private / Secret. A character an earlier version
--              kept partly back shows a callout over the profile with the
--              one-time "Publish whole profile..." confirmation.
--   Showcase   the live model with what the game says about the character
--              and what the player wrote, kept apart (UI/Showcase.lua).
-- A reader (the full imported story, or the whole family list) and the
-- field editor cover the section while open. Deliberately small: it is not
-- a copy of Total RP 3's editor. All writes go through Core/Actions.lua.
local _, ns = ...
local Widgets, MainWindow, Schema, Themes, Style = ns.Widgets, ns.MainWindow, ns.Schema, ns.Themes, ns.Style

local CharacterView = {}
ns.CharacterView = CharacterView

CharacterView.FAMILY_HINT = "Parents, siblings, a lost cousin: anyone your character counts as family."
CharacterView.HISTORY_HINT = "Moments from before the story Dawnward records, in your own words."
CharacterView.STORY_EMPTY = "Paste a backstory you already wrote, or read your Total RP 3 About text. "
	.. "It is kept exactly as written."
CharacterView.INTRO = "Who your character is, in your own words. Once Total RP 3 is connected, this whole "
	.. "profile is what it shows."
-- The pending callout (Publication.Status "pending").
CharacterView.PENDING_TEXT = "An earlier version of Dawnward kept part of this profile back from Total RP 3."
CharacterView.PUBLISH_LABEL = "Publish whole profile…"
-- A value the game supplies (race, class, first name) says so under it.
CharacterView.GAME_HINT = "from the game"
CharacterView.EMPTY_VALUE = "Not set"
CharacterView.ADD_LABEL = "+ Add"

-- The profile's groups, in order (mockup: identity tiles, then the Summary
-- and Motivation cards; then what the mockup predates). Any field not named
-- here joins "background", so a new profile field always appears. story:
-- the group ends with the imported-story card; list: the group is a list
-- (History) with its Add line.
CharacterView.GROUPS = {
	{ id = "identity", title = "Identity", heading = false, keys = { "name", "title", "pronouns", "race", "class",
		"age" } },
	-- The long texts carry their own labels (mockup: SUMMARY, MOTIVATION cards), so
	-- this group shows no heading of its own.
	{ id = "words", title = "Summary & motivation", heading = false, keys = { "summary", "motivation" } },
	{ id = "background", title = "Background & biography", keys = { "homeland", "faith", "occupation", "appearance" },
		story = true },
	-- v0.9: the details Total RP 3 shows on its characteristics page.
	{ id = "details", title = "Details", keys = { "firstName", "lastName", "honorific", "eyes", "height", "weight",
		"residence", "relationship", "allegiance" } },
	-- v0.10: History moved from the right column, so the right column fits
	-- without a scroll bar of its own in typical use.
	{ id = "history", title = "History", keys = {}, list = "history" },
}
do
	local named, background = {}, nil
	for _, group in ipairs(CharacterView.GROUPS) do
		for _, key in ipairs(group.keys) do named[key] = true end
		if group.id == "background" then background = group end
	end
	for _, field in ipairs(Schema.FIELDS) do
		if not named[field.key] then
			table.insert(background.keys, field.key)
		end
	end
end

-- Layout (UI units, inside the content area), from Character.dc.html: the
-- intro line under the title (82 from the window top, the content area starts
-- at 96), tiles from 116; a 268 column on the right, 20 apart; tiles 10 apart
-- with 10 / 12 padding and a minimum height of 86; cards with 16 / 18 padding.
local L = {
	introTop = 14,      -- the intro line sits this far above the content area
	scrollTop = 20,     -- the profile starts this far below it (116 from the top)
	scrollBar = 22,
	rightWidth = 268,   -- Personality and Family column (mockup: 268)
	colGap = 20,        -- mockup: 20
	panelGap = 12,
	groupGap = 16,      -- between the field groups
	groupHead = 26,     -- a group's eyebrow and the space under it
	pad = Widgets.PANEL_PAD,
	panelTop = 36,      -- below a panel's eyebrow title
	tileGap = 10,       -- mockup: 10
	tileMin = 86,       -- mockup tile min-height
	tileCols = 3,
	tilePadX = 12,
	tilePadY = 10,
	tileValueTop = 30,  -- the value under the tile's label
	hintGap = 2,        -- "from the game" under the value
	cardPadX = 18,
	cardPadY = 16,
	cardTextTop = 54,   -- card text under the label row (16 + 30 + 8)
	editWidth = 48,
	addWidth = 60,      -- "+ Add" (mockup: ghost sm with a plus)
	cardEditWidth = 60,
	storyButton = 132,  -- "Read full story"
	controlHeight = Style.CONTROL.compact, -- 30: buttons inside tiles and cards
	headerHeight = Style.CONTROL.standard, -- 36: header buttons, as the close button
	headerOffset = 74,  -- header buttons above the content area, level with the close button
	calloutHeight = 44, -- the pending callout over the profile (compact: one line and a button)
	calloutGap = 10,
	-- Personality (mockup: eyebrow and "changes need your approval" on one
	-- row; poles 13 over a 6 px track, 12 apart; 14 px knob).
	axisGap = 10,
	axisTrackTop = 21,  -- the track under the poles (13 px text, 5 px gap)
	knob = 14,          -- personality knob (mockup: 14 with a 2 px ring in the window colour)
	track = 6,
	statusGap = 10,     -- between the eyebrow and the short approval note
	-- Family (mockup: FAMILY eyebrow with a ghost "Add" 28 high on its row).
	famAddWidth = 60,
	famAddHeight = 28,
	famAddTop = 9,      -- the Add button, centred on the eyebrow
	famHead = 47,       -- members start under the eyebrow row
	-- Dashed edge of an empty field (mockup: border-style dashed).
	dash = 6,
	dashGap = 4,
	-- The story card's excerpt (the first paragraphs, then "Read full story").
	storyParagraphs = 2,
	storyChars = 420,
	paraGap = 10,       -- between paragraphs in the reader
	readerTop = 64,     -- the reader's text under its heading and hint
}
CharacterView.LAYOUT = L
local EMPTY_VALUE = CharacterView.EMPTY_VALUE

--- Display text for a family member.
--- A reused action button that is drawn as the mockup's pencil whenever its
-- label is "Edit" (the word moves to the tooltip), and as plain text for
-- every other label ("+ Add", "Read full story"...). Where the client has no
-- line regions it keeps the word "Edit".
function CharacterView.PencilButton(button)
	local setText, getText = button.SetText, button.GetText
	function button.SetText(self, text)
		if text == "Edit" and self:SetIcon("edit") then
			setText(self, "")
			if not self.tooltipTitle then Widgets.Tooltip(self, "Edit", nil) end
			self.pencil = true
		else
			if self.pencil then self:SetIcon(nil) end
			self.pencil = nil
			setText(self, text)
		end
	end
	function button.GetText(self)
		return self.pencil and "Edit" or getText(self)
	end
	button:SetText("Edit")
	return button
end

function CharacterView.FamilyText(item)
	local relation = item.relation and (item.relation:sub(1, 1):upper() .. item.relation:sub(2)) or "Relative"
	local status = item.status and item.status ~= "unknown" and (" (" .. item.status .. ")") or ""
	return relation .. ": " .. (item.name or "unnamed") .. status
end

function CharacterView.HistoryText(item)
	return (item.when and (item.when .. ": ") or "") .. (item.text or "")
end

--- Column widths for a content width: { child (both columns), left, right,
-- rightX }. The left column scrolls by itself; the right one stands at
-- rightX. Pure.
function CharacterView.Columns(contentWidth)
	local child = contentWidth - L.scrollBar
	local left = child - L.rightWidth - L.colGap
	return { child = child, left = left, right = L.rightWidth, rightX = left + L.colGap }
end

--- Tile width in the left column (three to a row, as the mockup). Pure.
function CharacterView.TileWidth(contentWidth)
	local inner = CharacterView.Columns(contentWidth).left
	return math.floor((inner - (L.tileCols - 1) * L.tileGap) / L.tileCols)
end

--- Display parts of a family member or history entry: a title, a meta line
-- and notes. Family: the name, "Mother · deceased", the notes. History: what
-- happened, and when. Pure.
function CharacterView.ItemParts(list, item)
	if list == "family" then
		local relation = item.relation and (item.relation:sub(1, 1):upper() .. item.relation:sub(2)) or "Relative"
		local meta = relation
		if item.status and item.status ~= "unknown" then meta = meta .. " · " .. item.status end
		return item.name or "unnamed", meta, item.notes
	end
	return item.text or "", item.when, nil
end

--- The one meta line of a family member in the right column (mockup:
-- "Mother · innkeeper, Goldshire"): relation, status, then the first line of
-- the notes. The full notes are in the member's tooltip and the family list.
-- Pure.
function CharacterView.FamilyMeta(item)
	local _, meta, notes = CharacterView.ItemParts("family", item)
	local first = type(notes) == "string" and (notes:match("^%s*([^\n]*)") or ""):gsub("%s+$", "") or nil
	if first and first ~= "" then meta = meta .. " · " .. first end
	return meta
end

--- A profile field as it reads on the profile: value, source ("player" |
-- "game") or nil. Race, class and first name fall back to what the game
-- says (Core/Character.lua FieldOrGame); nothing is written. Pure apart
-- from the game's own functions.
function CharacterView.FieldDisplay(char, key)
	return ns.Character.FieldOrGame(char, key)
end

--- The first paragraphs of an imported story, for the Biography card:
-- excerpt, truncated (true when the full story says more). TRP3 tags are
-- removed for display (Sources.StripTags); the stored text is untouched.
-- Pure.
function CharacterView.StoryExcerpt(text, paragraphs, maxChars)
	paragraphs, maxChars = paragraphs or L.storyParagraphs, maxChars or L.storyChars
	local all = ns.Sources.Paragraphs(ns.Sources.StripTags(text))
	local parts, used, truncated = {}, 0, #all > paragraphs
	for i = 1, math.min(paragraphs, #all) do
		local p = all[i]
		local room = maxChars - used
		if #p > room then
			if room > 40 or i == 1 then
				local cut = p:sub(1, math.max(room, 1)):gsub("%s+%S*$", "")
				parts[#parts + 1] = cut .. "…"
			end
			truncated = true
			break
		end
		parts[#parts + 1] = p
		used = used + #p
	end
	return table.concat(parts, "\n\n"), truncated
end

-- How a saved story came to Dawnward (Schema.SOURCE_KINDS).
CharacterView.STORY_KINDS = { trp3 = "Read from Total RP 3", paste = "Pasted", written = "Written in Dawnward",
	answers = "From your answers" }

--- "Read from Total RP 3 · 1240 words" for a saved story. Pure.
function CharacterView.StoryMeta(source)
	local words = 0
	for _ in ns.Sources.StripTags(source.text or ""):gmatch("%S+") do words = words + 1 end
	return (CharacterView.STORY_KINDS[source.kind] or "Saved story") .. " · " .. words
		.. (words == 1 and " word" or " words")
end

--- Rows to show, in order (pure; tested). Each carries its group: the left
-- column's groups (fields, the story card, History), then Family on the
-- right.
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
		if group.story then
			specs[#specs + 1] = { kind = "story", group = group.id,
				source = char and char.sources and ns.Sources.Current(char) or nil }
		end
		if group.list then
			for _, item in ipairs(char and char[group.list] or {}) do
				specs[#specs + 1] = { kind = "item", list = group.list, group = group.id, item = item,
					text = CharacterView.HistoryText(item) }
			end
			specs[#specs + 1] = { kind = "add", list = group.list, group = group.id, text = CharacterView.HISTORY_HINT }
		end
	end
	for _, item in ipairs(char and char.family or {}) do
		specs[#specs + 1] = { kind = "item", list = "family", group = "family", item = item,
			text = CharacterView.FamilyText(item), detail = item.notes }
	end
	specs[#specs + 1] = { kind = "add", list = "family", group = "family", text = CharacterView.FAMILY_HINT }
	return specs
end

--- How many family members fit the room left in the right column, given
-- their heights: shown, hidden. When some are hidden, room is kept for the
-- "+N more" button. Pure.
function CharacterView.FamilyFit(heights, room, gap, moreHeight)
	local total = 0
	for i, h in ipairs(heights) do
		total = total + h + (i > 1 and gap or 0)
	end
	if total <= room then return #heights, 0 end
	local shown, used = 0, 0
	for i, h in ipairs(heights) do
		local next = used + h + (i > 1 and gap or 0)
		if next + gap + moreHeight > room then break end
		shown, used = i, next
	end
	return shown, #heights - shown
end

--- Personality rows (pure; tested): one per axis, in registry order,
-- { axis, value (nil when not set), pending = net waiting delta,
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
		rows[#rows + 1] = { axis = axis, value = entry and entry.value, pending = p and p.delta or 0,
			waiting = p and p.count or 0, left = left, right = right, meaning = meaning, custom = custom,
			locked = ns.AxisMeanings.IsLocked(char, axis.id) }
	end
	return rows, total
end

--- The approval sentence (the personality note's tooltip). Pure.
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

--- The short note beside the PERSONALITY eyebrow (mockup: "changes need
-- your approval"). Pure.
function CharacterView.ApprovalShort(char, waiting)
	if waiting > 0 then
		return waiting == 1 and "1 change waiting" or (waiting .. " changes waiting")
	end
	local approval = char and char.story and char.story.prefs and char.story.prefs.approval
	if approval == "auto" then return "changes apply on their own" end
	return "changes need your approval"
end

--- Whether the Character page shows the one-time publish callout: only for
-- a character an earlier version kept partly back. Pure.
function CharacterView.ShowsPublishCallout(char)
	return char ~= nil and ns.Publication.Status(char) == "pending"
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

--- Opens the import window on the saved story (or empty when none is saved).
function CharacterView.OpenImport()
	if not (ns.ImportWizard and ns.ImportWizard.Open) then return end
	ns.ImportWizard.Open({ from = "character", page = "text" })
	local char = ns.Actions.Character(ns.ctx)
	if char and char.sources and ns.Sources.Current(char) and ns.ImportWizard.FillFromSaved then
		ns.ImportWizard.FillFromSaved()
	end
end

--- A dashed 1 px edge (mockup: the empty Age tile's border-style dashed):
-- short textures along each side. :Layout(w, h) places them (only when the
-- size changed; textures are created once and reused), :Paint(color, alpha),
-- :SetShown(on). Built only for rows that have been empty.
function CharacterView.DashedEdge(frame)
	local d = { textures = {}, used = 0 }
	local function dash(i)
		local t = d.textures[i]
		if not t then
			t = Style.Solid(frame, "BORDER")
			d.textures[i] = t
		end
		return t
	end
	-- Dashes along one side of length len, centred so both corners match.
	local function side(i, len, place)
		local n = math.max(1, math.floor((len + L.dashGap) / (L.dash + L.dashGap)))
		local start = math.floor((len - (n * L.dash + (n - 1) * L.dashGap)) / 2)
		for k = 0, n - 1 do
			i = i + 1
			place(dash(i), start + k * (L.dash + L.dashGap))
		end
		return i
	end
	function d.Layout(_, w, h)
		if d.w == w and d.h == h then return end
		d.w, d.h = w, h
		local i = 0
		i = side(i, w, function(t, x) t:ClearAllPoints(); t:SetPoint("TOPLEFT", x, 0); t:SetSize(L.dash, 1) end)
		i = side(i, w, function(t, x) t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", x, 0); t:SetSize(L.dash, 1) end)
		i = side(i, h, function(t, y) t:ClearAllPoints(); t:SetPoint("TOPLEFT", 0, -y); t:SetSize(1, L.dash) end)
		i = side(i, h, function(t, y) t:ClearAllPoints(); t:SetPoint("TOPRIGHT", 0, -y); t:SetSize(1, L.dash) end)
		d.used = i
		for k, t in ipairs(d.textures) do t:SetShown(d.shown and k <= i) end
		if d.color then d:Paint(d.color, d.alpha) end
	end
	function d.Paint(_, color, alpha)
		d.color, d.alpha = color, alpha
		for k = 1, d.used do Style.Color(d.textures[k], color, alpha) end
	end
	function d.SetShown(_, on)
		d.shown = on and true or false
		for k, t in ipairs(d.textures) do t:SetShown(d.shown and k <= d.used) end
	end
	return d
end

-- Field tiles and cards are entry cards (Widgets.Card) with one extra state:
-- an empty field (mockup: the dashed "Age" tile) has no fill and a dashed
-- edge, so set fields stand out. Same colours as Widgets.Card otherwise.
local function paintFieldCard(c, theme)
	local tones = Style.Tones(theme)
	local boxed = not c.plain
	local dashed = boxed and c.emptyField and true or false
	local fillAlpha = boxed and not (dashed and not c.hover) and 1 or 0
	Style.Color(c.bg, c.hover and tones.cardHover or theme.surface, fillAlpha)
	local edge = c.highlight and theme.accent or (c.hover and tones.selectedEdge or theme.edge)
	c.edges:Paint(edge, (boxed and not dashed) and 1 or 0)
	if dashed and not c.dashes then c.dashes = CharacterView.DashedEdge(c) end
	if c.dashes then
		c.dashes:SetShown(dashed)
		c.dashes:Paint(c.hover and tones.selectedEdge or tones.edgeStrong, 1)
	end
	c.bar:SetShown(boxed and c.highlight and true or false)
	Style.Color(c.bar, theme.accent)
end

local function create(parent)
	local section = { frame = CreateFrame("Frame", nil, parent), rows = {}, pool = {}, groups = {},
		mode = "profile" }
	local f = section.frame
	local contentWidth, contentHeight = MainWindow.ContentWidth(), MainWindow.ContentHeight()
	local cols = CharacterView.Columns(contentWidth)

	-- Header actions, level with the close button above the content area
	-- (mockup: 36 px buttons, the secondary one at the right).
	local H = L.headerHeight
	local header = CreateFrame("Frame", nil, f)
	header:SetSize(540, H)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(36 + 12), L.headerOffset)
	section.header = header
	section.showcaseButton = Widgets.Button(header, "Showcase", 128, H)
	section.showcaseButton:SetPoint("TOPRIGHT", 0, 0)
	Widgets.Tooltip(section.showcaseButton, "Character Showcase",
		"Your character's live model, what the game says about them, and what you wrote.")
	section.trp3Button = Widgets.Button(header, "Total RP 3...", 112, H, "ghost")
	section.trp3Button:SetPoint("RIGHT", section.showcaseButton, "LEFT", -8, 0)
	section.trp3Button:SetScript("OnClick", function() CharacterView.OpenTRP3() end)
	Widgets.Tooltip(section.trp3Button, "Total RP 3",
		"Sync status, preview, approval and backups for Total RP 3 (optional).")
	-- Story import (#23): paste a backstory, or read your Total RP 3 About text.
	section.importButton = Widgets.Button(header, "Import story", 108, H, "ghost")
	section.importButton:SetPoint("RIGHT", section.trp3Button, "LEFT", -8, 0)
	section.importButton:SetScript("OnClick", function() ns.ImportWizard.Open({ from = "character" }) end)
	Widgets.Tooltip(section.importButton, "Import your story",
		"Paste a backstory you already wrote (or read your Total RP 3 About text). It is kept exactly as written; "
		.. "you approve each piece before it becomes part of your character.")

	-- The intro line under the title (mockup: muted 15, under "Who she is").
	section.intro = Widgets.Label(f, "GameFontHighlight", false, "muted")
	section.intro:SetPoint("TOPLEFT", 0, L.introTop)
	section.intro:SetWidth(contentWidth - 2)
	section.intro:SetText(CharacterView.INTRO)

	-- Only for a character an earlier version kept partly back from Total
	-- RP 3: one compact line over the profile and the one-time confirmation
	-- (the same as the Total RP 3 page's, MainWindow.AskPublishWholeProfile).
	local callout = Widgets.Callout(f)
	callout:SetPoint("TOPLEFT", 0, -L.scrollTop)
	callout:SetSize(contentWidth - L.scrollBar, L.calloutHeight)
	callout.button = Widgets.Button(callout, CharacterView.PUBLISH_LABEL, 190, L.controlHeight, "primary")
	callout.button:SetPoint("RIGHT", -L.pad, 0)
	callout.button:SetScript("OnClick", function() MainWindow.AskPublishWholeProfile() end)
	Widgets.Tooltip(callout.button, "Publish whole profile", "Lists what an earlier version kept back, then "
		.. "publishes your whole profile to Total RP 3 once it is connected. One time only; undo with "
		.. "/dawnward publish undo.")
	callout.text = Widgets.Label(callout, "GameFontHighlight", false, "body")
	callout.text:SetPoint("LEFT", L.pad, 0)
	callout.text:SetPoint("RIGHT", callout.button, "LEFT", -12, 0)
	callout.text:SetText(CharacterView.PENDING_TEXT)
	callout:Hide()
	section.callout = callout

	-- Profile: only the left column scrolls, with the slim bar in the column
	-- gap; the right column (Personality, Family) and the header stay put
	-- (mockup: character-profile.png). Both views have fixed sizes in layout
	-- units, so the window's SetScale changes nothing here.
	local viewHeight = contentHeight - L.scrollTop
	local scroll = CreateFrame("ScrollFrame", Widgets.NextName("CharacterScroll"), f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -L.scrollTop)
	scroll:SetSize(cols.left, viewHeight)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(cols.left, 1)
	scroll:SetScrollChild(child)
	section.scroll, section.child = scroll, child
	section.scrollBar = Widgets.SlimScrollBar(scroll, math.floor((L.colGap - Widgets.SLIM_BAR.width) / 2))
	Widgets.WheelScroll(scroll)
	section.viewHeight = viewHeight
	section.sideHeight = viewHeight

	-- The right column does not move with the left. It is laid out to fit
	-- (compact personality rows; family members up to the room left, then
	-- "+N more" opening the whole list), so in typical use it never scrolls.
	-- It stays a scroll frame so that an extreme case (every axis with a
	-- waiting change and a lock note) is still all in reach: its slim bar,
	-- in the gutter at the window's right, shows only then.
	local sideScroll = CreateFrame("ScrollFrame", Widgets.NextName("CharacterSide"), f, "UIPanelScrollFrameTemplate")
	sideScroll:SetPoint("TOPLEFT", cols.rightX, -L.scrollTop)
	sideScroll:SetSize(cols.right, viewHeight)
	local side = CreateFrame("Frame", nil, sideScroll)
	side:SetSize(cols.right, 1)
	sideScroll:SetScrollChild(side)
	section.sideScroll, section.side = sideScroll, side
	section.sideBar = Widgets.SlimScrollBar(sideScroll, L.scrollBar - Widgets.SLIM_BAR.width - 4)
	Widgets.WheelScroll(sideScroll)

	-- Field groups: unboxed, so their tiles sit on the window ground as in the
	-- mockup; a group after the first ones names itself with an eyebrow (more
	-- fields than the mockup's six, so they are grouped).
	for _, group in ipairs(CharacterView.GROUPS) do
		local g = CreateFrame("Frame", nil, child)
		g.title = Widgets.TrackedLabel(g, "eyebrow", "eyebrow")
		g.title:SetPoint("TOPLEFT", 0, 0)
		g.title:SetText(group.title:upper())
		g.title:SetShown(group.heading ~= false)
		section.groups[group.id] = g
	end

	-- Right-hand panels sit behind their entries: same level as the column's
	-- scroll child, so the entries (one level up) draw over them.
	local function backPanel(title)
		local panel = Widgets.Panel(side, title)
		local level = side.GetFrameLevel and side:GetFrameLevel()
		if type(level) == "number" and panel.SetFrameLevel then panel:SetFrameLevel(level) end
		return panel
	end
	-- Family (mockup: FAMILY with its Add on the eyebrow row).
	section.familyPanel = backPanel("Family")
	section.familyPanel.empty = Widgets.Label(section.familyPanel, "meta", true, "muted")
	section.familyPanel.empty:SetPoint("TOPLEFT", L.pad, -L.famHead)
	section.familyPanel.empty:SetWidth(cols.right - 2 * L.pad)
	section.familyPanel.empty:SetText(CharacterView.FAMILY_HINT)
	section.familyMore = Widgets.Button(side, "", cols.right - 2 * L.pad, L.controlHeight, "ghost")
	section.familyMore:SetScript("OnClick", function() section:OpenReader("family") end)
	section.familyMore:Hide()

	-- Personality: the six axes with their real values (mockup: poles over a
	-- 6 px track, a 14 px gold knob ringed in the window colour, the pole the
	-- character leans to in bright gold; an unset axis a hollow ring).
	local pers = backPanel("Personality")
	section.personality = pers
	local innerRight = cols.right - 2 * L.pad
	local eyebrowWidth = math.ceil(Style.TextWidth("PERSONALITY", "eyebrow"))
	pers.status = Widgets.Label(pers, "GameFontHighlightSmall", true, "muted")
	pers.status:SetPoint("TOPRIGHT", -L.pad, -L.pad)
	pers.status:SetWidth(innerRight - eyebrowWidth - L.statusGap)
	pers.status:SetJustifyH("RIGHT")
	pers.review = Widgets.Button(side, "Review in Story", 140, L.controlHeight, "primary")
	pers.review:SetScript("OnClick", function() MainWindow.Select("story") end)
	Widgets.Tooltip(pers.review, "Review in Story", "Approve or reject personality changes from your choices.")
	pers.review:Hide()
	pers.axes = {}
	for i = 1, #Schema.PERSONALITY_AXES do
		local a = CreateFrame("Frame", nil, side)
		a:SetSize(innerRight, 30)
		if a.EnableMouse then a:EnableMouse(true) end
		a.left = Widgets.Label(a, "GameFontHighlightSmall", false)
		a.left:SetPoint("TOPLEFT", 0, 0)
		a.left:SetWidth(innerRight / 2 - 4)
		a.right = Widgets.Label(a, "GameFontHighlightSmall", false)
		a.right:SetPoint("TOPRIGHT", 0, 0)
		a.right:SetWidth(innerRight / 2 - 4)
		a.right:SetJustifyH("RIGHT")
		a.track = Style.Solid(a, "ARTWORK")
		a.track:SetPoint("TOPLEFT", 0, -L.axisTrackTop)
		a.track:SetPoint("TOPRIGHT", 0, -L.axisTrackTop)
		a.track:SetHeight(L.track)
		-- Where a waiting change would move the value (amber, under the knob).
		a.pendingMark = Style.Disc(a, "ARTWORK", 2, 8)
		a.pendingMark:Hide()
		a.knob = Style.Disc(a, "OVERLAY", 0, L.knob)
		a.knobDot = Style.Disc(a, "OVERLAY", 1, L.knob - 4)
		a.knobDot:SetPoint("CENTER", a.knob, "CENTER", 0, 0)
		a.note = Widgets.Label(a, "GameFontHighlightSmall", true)
		a.note:SetPoint("TOPLEFT", 0, -(L.axisTrackTop + L.track + 6))
		a.note:SetWidth(innerRight)
		a.axisIndex = i
		-- Click: the player's own words, meaning and lock for this axis (#21).
		a:SetScript("OnMouseUp", function(self)
			if section.OpenAxisForm then section:OpenAxisForm(Schema.PERSONALITY_AXES[self.axisIndex]) end
		end)
		pers.axes[i] = a
	end

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

	-- column: the scroll child the row belongs in (child for the left
	-- column, side for family). A pooled row normally stays in its column.
	local function getRow(index, column)
		column = column or child
		local row = section.pool[index]
		if row then
			if row.GetParent and row:GetParent() ~= column and row.SetParent then row:SetParent(column) end
			return row
		end
		-- Each field, family member and history entry is its own card, with
		-- its Edit button inside it (Widgets.EntryRow).
		row = Widgets.EntryRow(column)
		Style.Register(row, paintFieldCard)
		row.key = Widgets.TrackedLabel(row, "eyebrow", "eyebrow") -- field label, Cinzel 13
		row.label = Widgets.Label(row, "GameFontNormal", true)                -- list headings, bold 14
		row.value = Widgets.Label(row, "nav", true)                            -- tile value, 17
		row.reading = Widgets.Label(row, "reading", true, "reading")           -- card text, 16 with leading
		row.title = Widgets.Label(row, "GameFontHighlight", true)              -- family name, 15
		row.detail = Widgets.Label(row, "meta", true, "muted")                 -- meta line, 14
		row.notes = Widgets.Label(row, "meta", true, "muted")                  -- notes and hints, 14
		row.rule = Widgets.Divider(row)
		row.rule:SetPoint("BOTTOMLEFT", 0, 2)
		row.rule:SetPoint("BOTTOMRIGHT", 0, 2)
		row.rule:Hide()
		-- An empty field's whole tile opens its editor, as its "+ Add" does.
		row:SetScript("OnMouseUp", function(self)
			local spec = self.spec
			if self.emptyField and spec and spec.kind == "field" and section.OpenEditor then
				section:OpenEditor(spec.field)
			end
		end)
		if section.decorateRow then
			section.decorateRow(row)
		end
		section.pool[index] = row
		return row
	end

	local function place(row, x, y, width, height)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", row:GetParent() or child, "TOPLEFT", x, -y)
		row:SetWidth(width)
		if height then row:SetHeight(height) end
		if row.dashes then row.dashes:Layout(width, height or row:GetHeight()) end
		row:Show()
	end

	local function resetRow(row, spec, theme)
		row.spec = spec
		for _, fs in ipairs({ row.key, row.label, row.value, row.reading, row.title, row.detail, row.notes }) do
			fs:Hide()
		end
		row.title:SetWordWrap(true)
		row.detail:SetWordWrap(true)
		row.rule:Hide()
		row.edit:Hide()
		row.theme = theme
		row.emptyField = nil
		-- A pooled row takes the mouse only for what it shows now (a click on an
		-- empty field, or a tooltip); a Frame's OnMouseUp needs EnableMouse.
		if row.EnableMouse then row:EnableMouse(row.tooltipHooked == true) end
		row.gameValue = nil
		-- Tooltips are per use: a pooled row keeps none from an earlier one.
		if row.tooltipHooked then row.tooltipTitle, row.tooltipText = nil, nil end
		row:SetPlain(false)
	end

	local function fieldKey(row, text, x, y)
		row.key:Show()
		row.key:ClearAllPoints()
		row.key:SetPoint("TOPLEFT", x, y)
		row.key:SetText(text:upper())
	end

	-- A short field: a tile in a three-column grid (label, value in title
	-- white 17, then Edit along the bottom). A value from the game reads in
	-- body text with "from the game" under it; an empty field is a dashed
	-- tile with "Not set" and "+ Add". Returns its height.
	local function measureTile(row, spec, width, theme)
		resetRow(row, spec, theme)
		local value, source = CharacterView.FieldDisplay(section.char, spec.field.key)
		row.emptyField = value == nil
		if row.emptyField and row.EnableMouse then row:EnableMouse(true) end
		row.gameValue = source == "game" and value or nil
		Style.Repaint(row)
		fieldKey(row, spec.field.label, L.tilePadX, -L.tilePadY)
		row.key:SetWidth(width - 2 * L.tilePadX)
		row.value:Show()
		row.value:ClearAllPoints()
		row.value:SetPoint("TOPLEFT", L.tilePadX, -L.tileValueTop)
		row.value:SetWidth(width - 2 * L.tilePadX)
		row.value:SetText(value or EMPTY_VALUE)
		Widgets.SetTextRole(row.value, source == "player" and "heading" or source == "game" and "text" or "muted")
		local bottom = L.tileValueTop + math.max(row.value:GetStringHeight(), 20)
		if row.gameValue then
			row.notes:Show()
			row.notes:ClearAllPoints()
			row.notes:SetPoint("TOPLEFT", L.tilePadX, -(bottom + L.hintGap))
			row.notes:SetWidth(width - 2 * L.tilePadX)
			row.notes:SetText(CharacterView.GAME_HINT)
			Widgets.SetTextRole(row.notes, "muted")
			bottom = bottom + L.hintGap + math.max(row.notes:GetStringHeight(), 16)
			Widgets.Tooltip(row, spec.field.label .. ": from the game", "The game says your character is \""
				.. value .. "\". It is shown until you write your own with Edit; it is never saved for you.")
		end
		section.updateFieldActions(row, spec, "tile")
		return math.max(L.tileMin, bottom + 8 + L.controlHeight + L.tilePadY)
	end

	-- A long field: a full-width card (label and Edit on one row, then the
	-- text in the reading style). Returns its height.
	local function measureCard(row, spec, width, theme)
		resetRow(row, spec, theme)
		local entry = spec.entry
		row.emptyField = entry == nil
		if row.emptyField and row.EnableMouse then row:EnableMouse(true) end
		Style.Repaint(row)
		fieldKey(row, spec.field.label, L.cardPadX, -(L.cardPadY + 7))
		row.reading:Show()
		row.reading:ClearAllPoints()
		row.reading:SetPoint("TOPLEFT", L.cardPadX, -L.cardTextTop)
		row.reading:SetWidth(width - 2 * L.cardPadX)
		row.reading:SetText(entry and entry.value or EMPTY_VALUE)
		Widgets.SetTextRole(row.reading, entry and "reading" or "muted")
		section.updateFieldActions(row, spec, "card")
		return math.max(L.tileMin, L.cardTextTop + math.max(row.reading:GetStringHeight(), 20) + L.cardPadY)
	end

	-- The imported story (Biography): its first paragraphs in the reading
	-- style, how it came and how long it is, and "Read full story" on the
	-- label row. Without a story: a dashed card with "+ Import".
	local function measureStory(row, spec, width, theme)
		resetRow(row, spec, theme)
		local source = spec.source
		row.emptyField = source == nil
		Style.Repaint(row)
		fieldKey(row, "Biography", L.cardPadX, -(L.cardPadY + 7))
		row.reading:Show()
		row.reading:ClearAllPoints()
		row.reading:SetPoint("TOPLEFT", L.cardPadX, -L.cardTextTop)
		row.reading:SetWidth(width - 2 * L.cardPadX)
		local h = L.cardTextTop
		if source then
			local excerpt, truncated = CharacterView.StoryExcerpt(source.text)
			row.storyTruncated = truncated
			row.reading:SetText(excerpt ~= "" and excerpt or EMPTY_VALUE)
			Widgets.SetTextRole(row.reading, "reading")
			h = h + math.max(row.reading:GetStringHeight(), 20)
			row.detail:Show()
			row.detail:ClearAllPoints()
			row.detail:SetPoint("TOPLEFT", L.cardPadX, -(h + 8))
			row.detail:SetWidth(width - 2 * L.cardPadX)
			row.detail:SetText(CharacterView.StoryMeta(source))
			Widgets.SetTextRole(row.detail, "muted")
			h = h + 8 + row.detail:GetStringHeight()
			row.edit:SetText("Read full story")
			row.edit:SetVariant("default")
			row.edit:SetSize(L.storyButton, L.controlHeight)
			Widgets.Tooltip(row.edit, "Read full story", "Your whole imported story, exactly as you wrote it.")
		else
			row.reading:SetText(CharacterView.STORY_EMPTY)
			Widgets.SetTextRole(row.reading, "muted")
			h = h + math.max(row.reading:GetStringHeight(), 20)
			row.edit:SetText("+ Import")
			row.edit:SetVariant("ghost")
			row.edit:SetSize(84, L.controlHeight)
			Widgets.Tooltip(row.edit, "Import your story", "Opens Import story.")
		end
		row.edit:ClearAllPoints()
		row.edit:SetPoint("TOPRIGHT", -L.cardPadX, -L.cardPadY)
		row.edit:Show()
		return math.max(L.tileMin, h + L.cardPadY)
	end

	-- A family member or history entry: a card with the name (or what
	-- happened), a meta line and notes; Edit at the top right. compact (the
	-- right column's family): the name and one meta line, never wrapped
	-- (mockup: "Mother · innkeeper, Goldshire"); the full notes are the tooltip.
	local function measureItem(row, spec, width, theme, compact)
		resetRow(row, spec, theme)
		local title, meta, notes = CharacterView.ItemParts(spec.list, spec.item)
		if compact then
			Widgets.Tooltip(row, title, meta .. (notes and notes ~= "" and ("\n\n" .. notes) or ""))
			meta, notes = CharacterView.FamilyMeta(spec.item), nil
			row.title:SetWordWrap(false)
			row.detail:SetWordWrap(false)
		end
		local textWidth = width - 2 * 10 - L.editWidth - 8
		local y = 10
		row.title:Show()
		row.title:ClearAllPoints()
		row.title:SetPoint("TOPLEFT", 10, -y)
		row.title:SetWidth(textWidth)
		row.title:SetText(title)
		Widgets.SetTextRole(row.title, "text")
		y = y + row.title:GetStringHeight()
		for _, part in ipairs({ { row.detail, meta }, { row.notes, notes } }) do
			local fs, text = part[1], part[2]
			if text and text ~= "" then
				fs:Show()
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", 10, -(y + 2))
				fs:SetWidth(textWidth)
				fs:SetText(text)
				Widgets.SetTextRole(fs, "muted")
				y = y + 2 + fs:GetStringHeight()
			end
		end
		section.updateItemActions(row, spec)
		return math.max(y + 10, 10 + L.controlHeight + 10)
	end

	-- The History Add line (a hint and a quiet "+ Add"), or Family's Add on
	-- its panel's eyebrow row (the button alone).
	local function measurePlain(row, spec, width, theme)
		resetRow(row, spec, theme)
		row:SetPlain(true)
		row.edit:SetText(CharacterView.ADD_LABEL)
		row.edit:SetVariant("ghost")
		row.edit:ClearAllPoints()
		row.edit:SetPoint("TOPRIGHT", 0, 0)
		Widgets.Tooltip(row.edit, spec.list == "family" and "Add a family member" or "Add a history entry")
		row.edit:Show()
		if spec.list == "family" then
			row.edit:SetSize(L.famAddWidth, L.famAddHeight)
			return L.famAddHeight
		end
		row.edit:SetSize(L.addWidth, L.controlHeight)
		row.notes:Show()
		row.notes:ClearAllPoints()
		row.notes:SetPoint("TOPLEFT", 0, -4)
		row.notes:SetWidth(width - L.addWidth - 8)
		row.notes:SetText(spec.text)
		Widgets.SetTextRole(row.notes, "muted")
		return math.max(row.notes:GetStringHeight() + 10, L.controlHeight + 4)
	end

	local function paintAxis(a, row, theme, width)
		local tones = Style.Tones(theme)
		local waitingColor = Themes.STATUS_COLORS.waiting
		-- The player's own words where they wrote any (#21).
		local axis = { left = row.left or row.axis.left, right = row.right or row.axis.right }
		a.left:SetText(axis.left)
		a.right:SetText(axis.right)
		local lean = row.value and (row.value > 10 and "right" or row.value < 10 and "left") or nil
		Style.TextColor(a.left, lean == "left" and tones.accentBright or theme.muted)
		Style.TextColor(a.right, lean == "right" and tones.accentBright or theme.muted)
		Style.Color(a.track, tones.track)
		Style.Color(a.pendingMark, waitingColor)
		-- The knob's centre sits at the value along the track (mockup: left %).
		local function centreAt(value)
			local x = math.floor(width * value / 20 + 0.5)
			return math.max(L.knob / 2, math.min(width - L.knob / 2, x))
		end
		a.knob:ClearAllPoints()
		a.pendingMark:ClearAllPoints()
		a.pendingMark:Hide()
		local knobY = -(L.axisTrackTop + L.track / 2 - L.knob / 2)
		a.unset = row.value == nil
		if row.value then
			Style.Color(a.knob, theme.background)
			Style.Color(a.knobDot, theme.accent)
			a.knob:SetPoint("TOPLEFT", centreAt(row.value) - L.knob / 2, knobY)
			if row.waiting > 0 and row.pending ~= 0 then
				local target = math.max(0, math.min(20, row.value + row.pending))
				a.pendingMark:SetPoint("CENTER", a.track, "LEFT", centreAt(target), 0)
				a.pendingMark:Show()
			end
		else
			-- Not set: a hollow ring in the middle (no value is invented); the
			-- tooltip says "Not set". Keeps the row as compact as a set one.
			Style.Color(a.knob, theme.muted)
			Style.Color(a.knobDot, theme.background)
			a.knob:SetPoint("TOPLEFT", centreAt(10) - L.knob / 2, knobY)
		end
		a.knob:Show()
		a.knobDot:Show()
		local note, noteColor
		if row.waiting > 0 then
			local toward = row.pending > 0 and axis.right or row.pending < 0 and axis.left or nil
			note = (row.waiting == 1 and "1 change waiting" or (row.waiting .. " changes waiting"))
				.. (toward and (": toward " .. toward) or "")
			noteColor = waitingColor
		end
		if row.locked then
			note = (note and (note .. " · ") or "") .. "Locked: story answers never change it"
			noteColor = noteColor or theme.muted
		end
		a.note:SetText(note or "")
		a.note:SetShown(note ~= nil)
		if noteColor then Style.TextColor(a.note, noteColor) end
		local value = row.value and (row.value .. "/20 (" .. axis.left .. " " .. (20 - row.value) .. ", "
			.. axis.right .. " " .. row.value .. ")") or "Not set"
		Widgets.Tooltip(a, axis.left .. " - " .. axis.right, value
			.. (row.meaning and ("\n\n" .. row.meaning) or "")
			.. (row.waiting > 0 and "\nA change from your story choices waits in Story." or "")
			.. "\n\nClick to name this axis in your own words, say what it means, or lock it.")
		if note then
			return L.axisTrackTop + L.track + 6 + math.max(a.note:GetStringHeight(), 16)
		end
		return L.axisTrackTop + L.track
	end

	-- Personality panel at (x, y); returns its height.
	local function layoutPersonality(char, x, y, theme)
		local width = cols.right - 2 * L.pad
		local rows, waiting = CharacterView.PersonalityRows(char)
		pers:ClearAllPoints()
		pers:SetPoint("TOPLEFT", side, "TOPLEFT", x, -y)
		pers:SetWidth(cols.right)
		pers.status:SetText(CharacterView.ApprovalShort(char, waiting))
		Style.TextColor(pers.status, waiting > 0 and Themes.STATUS_COLORS.waiting or theme.muted)
		-- The full sentence on the panel (a font string takes no mouse input).
		Widgets.Tooltip(pers, "Personality", CharacterView.ApprovalText(char, waiting))
		local h = L.pad + math.max(18, pers.status:GetStringHeight()) + 12
		pers.waiting = waiting
		if waiting > 0 then
			pers.review:ClearAllPoints()
			pers.review:SetPoint("TOPLEFT", side, "TOPLEFT", x + L.pad, -(y + h))
			pers.review:Show()
			h = h + L.controlHeight + 12
		else
			pers.review:Hide()
		end
		for i, row in ipairs(rows) do
			local a = pers.axes[i]
			a:ClearAllPoints()
			a:SetPoint("TOPLEFT", side, "TOPLEFT", x + L.pad, -(y + h))
			local ah = paintAxis(a, row, theme, width)
			a:SetHeight(ah)
			a:Show()
			h = h + ah + L.axisGap
		end
		pers.rows = rows
		h = h + L.pad - L.axisGap
		pers:SetHeight(h)
		return h
	end

	-- Family panel from famTop in the right column: the Add on the eyebrow
	-- row, then as many members as fit the room left, then "+N more".
	-- Returns its height.
	local function layoutFamily(specs, first, rows, famTop, theme)
		local panel = section.familyPanel
		local itemWidth = cols.right - 2 * L.pad
		local members, heights, addIndex = {}, {}, nil
		for j = first, #specs do
			local spec, row = specs[j], getRow(j, side)
			rows[j] = row
			if spec.kind == "item" then
				members[#members + 1] = j
				heights[#heights + 1] = measureItem(row, spec, itemWidth, theme, true)
			else
				addIndex = j
				-- Only the button's size, so the row never covers the eyebrow.
				measurePlain(row, spec, L.famAddWidth, theme)
				place(row, L.pad + itemWidth - L.famAddWidth, famTop + L.famAddTop, L.famAddWidth, L.famAddHeight)
			end
		end
		local gap = Widgets.ENTRY.gap
		local room = section.sideHeight - famTop - L.famHead - L.pad
		local shown, hidden = CharacterView.FamilyFit(heights, room, gap, L.controlHeight)
		local y = L.famHead
		for k, j in ipairs(members) do
			local row = rows[j]
			if k <= shown then
				place(row, L.pad, famTop + y, itemWidth, heights[k])
				y = y + heights[k] + gap
			else
				row:Hide()
			end
		end
		panel.empty:SetShown(#members == 0)
		if #members == 0 then
			y = y + math.max(panel.empty:GetStringHeight(), 16) + gap
		end
		section.familyShown, section.familyHidden = shown, hidden
		local more = section.familyMore
		if hidden > 0 then
			more:SetText("+" .. hidden .. " more")
			Widgets.Tooltip(more, "Family", "Shows your whole family list, with Edit for each member.")
			more:ClearAllPoints()
			more:SetPoint("TOPLEFT", side, "TOPLEFT", L.pad, -(famTop + y))
			more:Show()
			y = y + L.controlHeight + gap
		else
			more:Hide()
		end
		local height = y - gap + L.pad
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -famTop)
		panel:SetSize(cols.right, height)
		section.familyAdd = addIndex and rows[addIndex] or nil
		return height
	end

	function section:RenderList(view)
		local specs = CharacterView.BuildSpecs(view.char)
		local theme = view.theme
		self.char = view.char
		self.child:SetWidth(cols.left)
		self.side:SetWidth(cols.right)
		local rows = {}
		local tileWidth = CharacterView.TileWidth(contentWidth)

		-- Left column: the field groups, the story card and History.
		local y, i = 0, 1
		for _, group in ipairs(CharacterView.GROUPS) do
			local g = self.groups[group.id]
			local top = y
			local inner = group.heading == false and 0 or L.groupHead
			local pending = {} -- tiles waiting to be placed in a grid row
			local function flush()
				if #pending == 0 then return end
				local h = 0
				for _, p in ipairs(pending) do h = math.max(h, p.height) end
				for col, p in ipairs(pending) do
					place(p.row, (col - 1) * (tileWidth + L.tileGap), top + inner, tileWidth, h)
				end
				inner = inner + h + L.tileGap
				pending = {}
			end
			while specs[i] and specs[i].group == group.id do
				local spec, row = specs[i], getRow(i, child)
				rows[i] = row
				if spec.kind == "field" and spec.field.kind ~= "long" then
					pending[#pending + 1] = { row = row, height = measureTile(row, spec, tileWidth, theme) }
					if #pending == L.tileCols then flush() end
				else
					flush()
					local h
					if spec.kind == "field" then
						h = measureCard(row, spec, cols.left, theme)
					elseif spec.kind == "story" then
						h = measureStory(row, spec, cols.left, theme)
					elseif spec.kind == "item" then
						h = measureItem(row, spec, cols.left, theme)
					else
						h = measurePlain(row, spec, cols.left, theme)
					end
					place(row, 0, top + inner, cols.left, h)
					inner = inner + h + L.tileGap
				end
				i = i + 1
			end
			flush()
			local height = math.max(inner - L.tileGap, 1)
			g:ClearAllPoints()
			g:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -top)
			g:SetSize(cols.left, height)
			y = top + height + L.groupGap
		end
		local leftHeight = y - L.groupGap

		-- Right column (its own scroll child): Personality, then Family.
		local famTop = layoutPersonality(view.char, 0, 0, theme) + L.panelGap
		local rightHeight = famTop + layoutFamily(specs, i, rows, famTop, theme)

		for k = #specs + 1, #self.pool do
			self.pool[k]:Hide()
		end
		-- Each column scrolls over its own height. The client recomputes the
		-- range from the child's size (OnScrollRangeChanged: the template's bar
		-- and the slim thumb follow); a view that got shorter keeps its place
		-- when it can and otherwise stops at its new end.
		self.child:SetHeight(math.max(leftHeight, 1))
		self.side:SetHeight(math.max(rightHeight, 1))
		Widgets.ScrollTo(self.scroll, self.scroll:GetVerticalScroll())
		Widgets.ScrollTo(self.sideScroll, self.sideScroll:GetVerticalScroll())
		self.leftHeight, self.rightHeight = leftHeight, rightHeight
		self.rows, self.specs = rows, specs
	end

	-- The pending callout (shown only while it applies) and the two columns
	-- under it: they start below the callout and lose its height.
	function section:LayoutCallout(char)
		local shown = self.mode == "profile" and CharacterView.ShowsPublishCallout(char)
		self.callout:SetShown(shown)
		local drop = shown and (L.calloutHeight + L.calloutGap) or 0
		if self.calloutDrop == drop then return end
		self.calloutDrop = drop
		local height = self.viewHeight - drop
		self.sideHeight = height
		self.scroll:ClearAllPoints()
		self.scroll:SetPoint("TOPLEFT", 0, -(L.scrollTop + drop))
		self.scroll:SetSize(cols.left, height)
		self.sideScroll:ClearAllPoints()
		self.sideScroll:SetPoint("TOPLEFT", cols.rightX, -(L.scrollTop + drop))
		self.sideScroll:SetSize(cols.right, height)
	end

	--- The header's eyebrow names the view (mockup: "CHARACTER · SHOWCASE").
	CharacterView.EYEBROWS = { profile = "CHARACTER", showcase = "CHARACTER · SHOWCASE" }
	local function setEyebrow(mode)
		local window = MainWindow.GetFrame and MainWindow.GetFrame()
		if window and window.eyebrow and MainWindow.CurrentSection() == "character" then
			window.eyebrow:SetText(CharacterView.EYEBROWS[mode] or CharacterView.EYEBROWS.profile)
		end
	end

	--- profile | showcase. Only the chosen view is shown, so the model
	-- renders only in the showcase. quiet: only show and hide (while the
	-- window is still being built).
	function section:SetMode(mode, quiet)
		if mode ~= "showcase" then mode = "profile" end
		self.mode = mode
		local showcase = mode == "showcase"
		local reading = self.reader and self.reader:IsShown()
		self.intro:SetShown(not showcase and not reading)
		self.scroll:SetShown(not showcase and not reading)
		self.sideScroll:SetShown(not showcase and not reading)
		if showcase or reading then self.callout:Hide() end
		if showcase and not reading then
			self.showcaseView:Show()
			self.showcase:Show()
		else
			self.showcase:Hide()
			self.showcaseView:Hide()
		end
		-- The showcase's header has only the way back (mockup: "Profile fields");
		-- the other actions are one click away on the profile.
		for _, b in ipairs({ self.trp3Button, self.importButton }) do
			b:SetShown(not showcase)
		end
		self.showcaseButton:SetText(showcase and "Profile fields" or "Showcase")
		if quiet then return end
		MainWindow.SetStatus("")
		MainWindow.Refresh()
	end

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
		local reading = self.reader:IsShown()
		self.header:SetShown(not self.form:IsOpen() and not reading)
		setEyebrow(self.mode)
		if reading then
			self:RenderReader(view.char)
		elseif self.mode == "showcase" then
			self.showcaseView:Refresh(view.char, ns.Actions.ShowcasePortrait(ns.ctx))
		else
			self:LayoutCallout(view.char)
			self:RenderList(view)
		end
	end

	section.getRow = getRow
	section.BuildSpecs = CharacterView.BuildSpecs
	CharacterView.AttachEditing(section)
	CharacterView.AttachReader(section)
	CharacterView.section = section
	section:SetMode("profile", true)
	return section
end

--- Reader ----------------------------------------------------------------------
-- A full view over the section: the whole imported story ("Read full story")
-- or the whole family list ("+N more"). One scrolling column with the slim
-- bar; "Back to profile" returns. Paragraph labels and member cards are
-- pooled and reused.

CharacterView.READER = {
	story = { heading = "Your story", action = "Open in Import story" },
	family = { heading = "Family", action = "+ Add family member" },
}

function CharacterView.AttachReader(section)
	local f = section.frame
	local contentWidth, contentHeight = MainWindow.ContentWidth(), MainWindow.ContentHeight()
	local B = Style.CONTROL.standard
	local INSET = 8
	local width = contentWidth - L.scrollBar
	local reader = CreateFrame("Frame", nil, f)
	reader:SetAllPoints(f)
	reader:Hide()
	section.reader = reader

	reader.heading = Widgets.Label(reader, "GameFontNormalLarge", false, "title")
	reader.heading:SetPoint("TOPLEFT", INSET, -10)
	reader.hint = Widgets.Label(reader, "meta", true, "muted")
	reader.hint:SetPoint("TOPLEFT", INSET, -36)
	reader.hint:SetWidth(width - 2 * INSET)

	local viewHeight = contentHeight - L.readerTop - (12 + B + 12)
	reader.scroll = CreateFrame("ScrollFrame", Widgets.NextName("CharacterReader"), reader,
		"UIPanelScrollFrameTemplate")
	reader.scroll:SetPoint("TOPLEFT", 0, -L.readerTop)
	reader.scroll:SetSize(width, viewHeight)
	reader.child = CreateFrame("Frame", nil, reader.scroll)
	reader.child:SetSize(width, 1)
	reader.scroll:SetScrollChild(reader.child)
	reader.bar = Widgets.SlimScrollBar(reader.scroll, math.floor((L.scrollBar - Widgets.SLIM_BAR.width) / 2))
	Widgets.WheelScroll(reader.scroll)
	reader.viewHeight = viewHeight

	reader.back = Widgets.Button(reader, "Back to profile", 140, B)
	reader.back:SetPoint("BOTTOMRIGHT", -INSET, 12)
	reader.back:SetScript("OnClick", function() section:CloseReader() end)
	reader.action = Widgets.Button(reader, "", 190, B, "ghost")
	reader.action:SetPoint("BOTTOMLEFT", INSET, 12)
	reader.action:SetScript("OnClick", function()
		if section.readerKind == "story" then
			CharacterView.OpenImport()
		else
			section:OpenItemForm("family")
		end
	end)

	reader.paras, reader.cards = {}, {}
	local function para(i)
		local fs = reader.paras[i]
		if not fs then
			fs = Widgets.Label(reader.child, "reading", true, "reading")
			reader.paras[i] = fs
		end
		return fs
	end
	local function card(i)
		local c = reader.cards[i]
		if not c then
			c = Widgets.EntryRow(reader.child)
			c.title = Widgets.Label(c, "GameFontHighlight", true, "body")
			c.title:SetPoint("TOPLEFT", 10, -10)
			c.detail = Widgets.Label(c, "meta", true, "muted")
			c.notes = Widgets.Label(c, "meta", true, "muted")
			c.edit = Widgets.Button(c, "Edit", L.editWidth, L.controlHeight, "ghost")
			CharacterView.PencilButton(c.edit)
			c.edit:SetPoint("TOPRIGHT", -10, -10)
			c.edit:SetScript("OnClick", function() section:OpenItemForm("family", c.item) end)
			reader.cards[i] = c
		end
		return c
	end

	--- Fills the reader for its kind from char.
	function section:RenderReader(char)
		local kind = self.readerKind
		local def = CharacterView.READER[kind]
		reader.heading:SetText(def.heading)
		reader.action:SetText(def.action)
		local y, p, c = 0, 0, 0
		if kind == "story" then
			local source = char and char.sources and ns.Sources.Current(char)
			reader.hint:SetText(source and (CharacterView.StoryMeta(source) .. ". Kept exactly as you wrote it; "
				.. "open it in Import story to add to it.") or "No story is saved yet.")
			local paragraphs = source and ns.Sources.Paragraphs(ns.Sources.StripTags(source.text)) or {}
			for _, text in ipairs(paragraphs) do
				p = p + 1
				local fs = para(p)
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", 0, -y)
				fs:SetWidth(width - 8)
				fs:SetText(text)
				fs:Show()
				y = y + fs:GetStringHeight() + L.paraGap
			end
		else
			reader.hint:SetText(CharacterView.FAMILY_HINT)
			for _, item in ipairs(char and char.family or {}) do
				c = c + 1
				local row = card(c)
				row.item = item
				local title, meta, notes = CharacterView.ItemParts("family", item)
				local textWidth = width - 8 - 2 * 10 - L.editWidth - 8
				local h = 10
				row.title:SetWidth(textWidth)
				row.title:SetText(title)
				h = h + row.title:GetStringHeight()
				for _, part in ipairs({ { row.detail, meta }, { row.notes, notes } }) do
					local fs, text = part[1], part[2]
					fs:ClearAllPoints()
					if text and text ~= "" then
						fs:SetPoint("TOPLEFT", 10, -(h + 2))
						fs:SetWidth(textWidth)
						fs:SetText(text)
						fs:Show()
						h = h + 2 + fs:GetStringHeight()
					else
						fs:Hide()
					end
				end
				h = math.max(h + 10, 10 + L.controlHeight + 10)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetSize(width - 8, h)
				row:Show()
				Widgets.Tooltip(row.edit, "Edit " .. title)
				y = y + h + Widgets.ENTRY.gap
			end
		end
		for k = p + 1, #reader.paras do reader.paras[k]:Hide() end
		for k = c + 1, #reader.cards do reader.cards[k]:Hide() end
		reader.child:SetHeight(math.max(y, 1))
		Widgets.ScrollTo(reader.scroll, reader.scroll:GetVerticalScroll())
		reader.height = y
	end

	--- Opens the reader: "story" or "family".
	function section:OpenReader(kind)
		if not CharacterView.READER[kind] then return end
		self.readerKind = kind
		reader:Show()
		Widgets.ScrollTo(reader.scroll, 0)
		self.header:Hide()
		self:SetMode(self.mode, true)
		self:RenderReader(ns.Actions.Character(ns.ctx))
		MainWindow.SetStatus("")
	end

	function section:CloseReader()
		reader:Hide()
		self.readerKind = nil
		self.header:Show()
		self:SetMode(self.mode)
	end
end
--- Editing ---------------------------------------------------------------------

--- The field editor's hint. A field the game knows (race, class, first
-- name) says what the game shows while the player has written nothing, and
-- that clearing their own brings it back. Pure.
function CharacterView.EditorHint(field, entry, gameValue)
	if gameValue then
		if entry then
			return "Your own words, shown instead of the game's \"" .. gameValue .. "\". Clear it to show the "
				.. "game's again."
		end
		return "The game says \"" .. gameValue .. "\", and that is shown until you write your own (for example "
			.. "a people, order or calling of your character's). Nothing is saved until you do."
	end
	return field.kind == "long"
		and "A few sentences are plenty. Your profile is what Total RP 3 shows once it is connected."
		or "One line. Your profile is what Total RP 3 shows once it is connected."
end

--- Adds per-field Edit buttons and the field editor.
function CharacterView.AttachEditing(section)
	local f = section.frame
	local Actions = ns.Actions

	function section.decorateRow(row)
		row.edit = Widgets.Button(row, "Edit", L.editWidth, L.controlHeight, "ghost")
		CharacterView.PencilButton(row.edit)
		row.edit:SetScript("OnClick", function()
			local spec = row.spec
			if spec.kind == "field" then
				section:OpenEditor(spec.field)
			elseif spec.kind == "story" then
				if spec.source then section:OpenReader("story") else CharacterView.OpenImport() end
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
			hint = "Only you write this.",
			fields = {
				{ key = "relation", label = "Relation", kind = "line", max = Schema.LIMITS.short },
				{ key = "name", label = "Name", kind = "line", max = Schema.LIMITS.short },
				{ key = "status", label = "Status", kind = "cycle", values = STATUS },
				{ key = "notes", label = "Notes", kind = "area", max = Schema.LIMITS.long },
			},
		},
		history = {
			noun = "history entry",
			hint = "When it happened, in any words (\"as a child\", \"the Third War\"), and what happened.",
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
				.. axis.right .. "). Values, history and Total RP 3 traits are not changed.",
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

	-- Fields always offer Edit ("+ Add" while empty; a value from the game
	-- is edited to write the player's own). shape: "tile" (a quiet button at
	-- the bottom right, as the mockup's tiles) or "card" (a secondary Edit on
	-- the label row, as the mockup's Summary card).
	function section.updateFieldActions(row, spec, shape)
		local empty = row.emptyField
		row.edit:SetText(empty and CharacterView.ADD_LABEL or "Edit")
		row.edit:ClearAllPoints()
		local width = empty and L.addWidth or (shape == "card" and L.cardEditWidth or L.editWidth)
		row.edit:SetSize(width, L.controlHeight)
		if shape == "card" then
			row.edit:SetVariant(empty and "ghost" or "default")
			row.edit:SetPoint("TOPRIGHT", -L.cardPadX, -L.cardPadY)
		else
			row.edit:SetVariant("ghost")
			row.edit:SetPoint("BOTTOMRIGHT", -L.tilePadY, L.tilePadY)
		end
		local label = spec.field.label
		if row.gameValue then
			Widgets.Tooltip(row.edit, "Write your own " .. label:lower(), "Shown instead of the game's \""
				.. row.gameValue .. "\". Clear it later to show the game's again.")
		else
			Widgets.Tooltip(row.edit, (empty and "Add " or "Edit ") .. label)
		end
		row.edit:Show()
	end

	-- Family members and history entries: Edit at the top right.
	function section.updateItemActions(row)
		row.edit:SetText("Edit")
		row.edit:SetVariant("ghost")
		row.edit:SetSize(L.editWidth, L.controlHeight)
		row.edit:ClearAllPoints()
		row.edit:SetPoint("TOPRIGHT", -10, -10)
		Widgets.Tooltip(row.edit, "Edit")
		row.edit:Show()
	end

	local INSET = 8
	local editor = CreateFrame("Frame", nil, f)
	editor:SetAllPoints(f)
	editor:Hide()
	section.editor = editor

	editor.heading = Widgets.Label(editor, "GameFontNormalLarge", false, "title")
	editor.heading:SetPoint("TOPLEFT", INSET, -10)
	editor.hint = Widgets.Label(editor, "meta", true, "muted")
	editor.hint:SetPoint("TOPLEFT", INSET, -36)
	editor.hint:SetWidth(540)

	editor.line = Widgets.EditLine(editor, 101, Style.CONTROL.input)
	editor.line:SetPoint("TOPLEFT", INSET, -64)
	editor.line:SetPoint("TOPRIGHT", -INSET, -64)
	editor.area = Widgets.TextArea(editor, 2001, MainWindow.ContentWidth() - 2 * INSET)
	editor.area.frame:SetPoint("TOPLEFT", INSET, -64)
	editor.area.frame:SetPoint("BOTTOMRIGHT", -INSET, 76) -- leaves room for an error line above the buttons
	Widgets.FieldError(editor.line, 540)
	Widgets.FieldError(editor.area.edit, 540)
	-- Keyboard: Enter saves a one-line field (refused input stays, with its
	-- reason beneath); Escape cancels, asking first if something was typed.
	editor.chain = Widgets.FocusChain({
		onSubmit = function() section.SaveEditor() end,
		onEscape = function(dirty) editor.chain.ConfirmDiscard(dirty, function() section.CloseEditor() end) end,
	})

	local B = Style.CONTROL.standard
	editor.cancel = Widgets.Button(editor, "Cancel", 96, B)
	editor.cancel:SetPoint("BOTTOMRIGHT", -INSET, 12)
	editor.save = Widgets.Button(editor, "Save", 96, B, "primary")
	editor.save:SetPoint("RIGHT", editor.cancel, "LEFT", -8, 0)
	editor.clear = Widgets.Button(editor, "Clear", 96, B, "danger")
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
		editor.hint:SetText(CharacterView.EditorHint(field, entry, ns.Character.GameValue(field.key)))
		local long = field.kind == "long"
		editor.area.frame:SetShown(long)
		editor.line:SetShown(not long)
		editor.clear:SetShown(entry ~= nil)
		Widgets.SetFieldError(editor.line, nil)
		Widgets.SetFieldError(editor.area.edit, nil)
		input():SetText(entry and entry.value or "")
		-- The editor takes the whole section; the other views step aside.
		section.scroll:Hide()
		section.sideScroll:Hide()
		section.callout:Hide()
		section.reader:Hide()
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

MainWindow.RegisterSection({ id = "character", label = "Character", order = 2, heading = "Profile", titleInset = 540,
	icon = "Interface\\Icons\\INV_Misc_Head_Human_01", create = create })
