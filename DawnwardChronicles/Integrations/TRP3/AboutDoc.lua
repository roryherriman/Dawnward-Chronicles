-- The About page (v0.10.1): the character's public narrative, laid out in
-- Total RP 3's own About templates. Pure Lua: it works on copies and
-- returns a plan; it never touches TRP3.
--
-- What it publishes (only from the public projection), in the player's
-- order (StorySchema.AboutSections; titles are the player's or defaults):
--   * Character overview   the Summary field, in the player's words
--   * Biography            the current biography, word for word: every
--                          paragraph and line break, and the player's own
--                          chapter headings (a line "# Title" or
--                          "{h2}Title{/h2}"), shown as chapter titles
--   * Appearance           the Appearance field, when written
--   * Personality          a personality description field, when the
--                          character has one (Dawnward has none yet, so it
--                          never appears; nothing is generated from axes,
--                          traits or facts)
--   * Motivation           the Motivation field; off unless the player
--                          switches it on
--   * New developments     approved defining moments the biography does not
--                          already tell; off unless the player switches it on
-- Nothing else: no facts, family lists, stances, beliefs or chronicle notes
-- (those stay in Dawnward, untouched). No section is ever empty, and no
-- text is ever invented to fill one.
--
-- Deduplication (AboutDoc.Dedupe, pure): a sentence of the overview, an
-- optional section or a development that the biography (or a section
-- before it) already says is left out, compared without case, spacing,
-- punctuation or TRP3 tags. The biography itself is never changed. A
-- section with nothing left is not shown (an overview that only repeats
-- the biography's opening, for example).
--
-- Templates (verified in TRP3 3.4.1, Modules/Register/Characters/
-- RegisterAbout.lua): template 1 is one text (T1.TX); template 2 is a list
-- of frames { TX, IC, BK } (showTemplate2, lines 225-290); template 3 is
-- three texts with fixed titles (showTemplate3, lines 516-545): PH
-- (physical), PS (personality), HI (history). Dawnward puts the appearance
-- alone in PH, a personality description alone in PS, and the overview,
-- the biography and the other chosen sections in HI. Template 2 gets one
-- frame per section; the biography stays one frame unless it is over
-- MAX_BYTES, when it is split only at the player's own chapter headings.
--
-- Ownership (as AboutBlock): Dawnward's content is recognised by an exact
-- match against the ledger, never by markers.
--   append mode (default)  Dawnward's text is appended after the player's
--                          own text in each slot it uses (T1, PH, PS, HI),
--                          and template 2 gets frames of its own; the
--                          player's text and frames are never changed
--   adopt mode             the player chose "Replace it with Dawnward's":
--                          Dawnward owns each slot it uses entirely (the
--                          player's previous text stays in the backup taken
--                          before the write). Later edits in TRP3 are
--                          conflicts, never overwritten
-- A slot or frame that cannot be found exactly once is a conflict and
-- nothing is written. Content identical to Dawnward's that Dawnward did not
-- write (for example after its ledger was lost) is also a conflict, so the
-- About text is never duplicated. A record written by v0.9 or v0.10 (record.
-- slots / record.frames) is replaced in place by the next sync: its owned
-- text is found exactly and swapped for the new page; frames it no longer
-- needs are removed (Dawnward's own only). Since v0.10.1 the record also
-- keeps the icon and background Dawnward gave each frame (frameStyles), so
-- a style chosen in Dawnward reaches the frames the player has not
-- restyled, and a frame the player restyled keeps the player's choice.
local _, ns = ...
local Util, Presentation, StorySchema, AboutBlock = ns.Util, ns.TRP3Presentation, ns.StorySchema, ns.TRP3AboutBlock

local AboutDoc = {}
ns.TRP3AboutDoc = AboutDoc

-- Largest text Dawnward writes into one slot or frame. TRP3 has no hard
-- limit (its editor boxes are letters="0"); the biography itself is at most
-- 16 KB. Over this, nothing is written and the reason is shown.
AboutDoc.MAX_BYTES = 30000
AboutDoc.TEXT_SLOTS = { 1, "PH", "PS", "HI" }

-- Which template 3 text a section goes to (the rest go to the history).
-- TRP3 titles these parts itself, so a section alone there has no heading.
AboutDoc.T3_SLOT = { appearance = "PH", personality = "PS" }

-- The profile field each optional section reads.
AboutDoc.FIELD_OF = { overview = "summary", appearance = "appearance", personality = "personality",
	motivation = "motivation" }

-- Coverage compares sentences of at least this many characters (normalised)
-- inside the biography too, not only whole sentences.
AboutDoc.MIN_INSIDE = 24

local escape = Presentation.Escape

local function deepEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function trimBlankLines(text)
	text = text:gsub("^%s*\n", "")
	text = text:gsub("\n[%s]*$", "")
	return text
end

--- Splits a biography at the player's own headings. Returns a list of
-- { title, body }; title is nil for text before the first heading. Bodies
-- are the original text between headings, with only blank lines at their
-- edges removed (line breaks, paragraphs and wording are kept).
function AboutDoc.SplitBiography(text)
	local sections = {}
	if type(text) ~= "string" or text == "" then
		return sections
	end
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	local current = { title = nil, lines = {} }
	local function flush()
		local body = trimBlankLines(table.concat(current.lines, "\n"))
		if body:match("%S") or current.title then
			sections[#sections + 1] = { title = current.title, body = body }
		end
	end
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local title = line:match("^%s*#+%s*(.-)%s*#*%s*$")
		if not title or title == "" then
			title = line:match("^%s*{h%d[:%a]*}(.-){/h%d}%s*$")
		end
		if title and title:match("%S") then
			flush()
			current = { title = title, lines = {} }
		else
			current.lines[#current.lines + 1] = line
		end
	end
	flush()
	return sections
end

--- Deduplication (pure) ------------------------------------------------------------

-- TRP3 tags (Core/Utils.lua structureTags and convertTextTag) that carry no words.
local TAG_NAMES = { col = true, p = true, icon = true, img = true, link = true }

--- A sentence as compared: TRP3 tags and colour codes removed, lower case,
-- punctuation (ASCII and the common typographic marks) as spaces, single
-- spaces, trimmed. Pure.
function AboutDoc.Normalize(text)
	text = tostring(text or "")
	text = text:gsub("{(/?)(%a+%d?)([^}]*)}", function(_, name)
		local lower = name:lower()
		if TAG_NAMES[lower] or lower:match("^h%d$") then return " " end
		return nil
	end)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	-- U+2010-U+202F: dashes, curly quotes, ellipsis and narrow spaces.
	text = text:gsub("\226\128[\144-\175]", " ")
	text = text:lower():gsub("%p", " "):gsub("%s+", " ")
	return (text:match("^%s*(.-)%s*$"))
end

--- The sentences of text, each with the spacing that follows it, so that
-- concatenating them gives text back exactly. A sentence ends at ., ! or ?
-- (with any closing quotes or brackets) before a space, or at a line break.
function AboutDoc.Sentences(text)
	local out = {}
	text = tostring(text or "")
	local pos, n = 1, #text
	while pos <= n do
		local s, e = text:find("[%.!%?]+[\"'%)%]\226\128-\191]*[ \t]+", pos)
		local nl = text:find("\n", pos, true)
		local stop
		if nl and (not s or nl < s) then
			local _, last = text:find("^\n[%s]*", nl)
			stop = last
		elseif s then
			stop = e
		else
			stop = n
		end
		out[#out + 1] = text:sub(pos, stop)
		pos = stop + 1
	end
	return out
end

--- A coverage index: what the page already says. Pure.
function AboutDoc.NewCoverage()
	return { set = {}, parts = {}, joined = nil }
end

--- Adds text's sentences to a coverage index.
function AboutDoc.Cover(coverage, text)
	for _, sentence in ipairs(AboutDoc.Sentences(text)) do
		local n = AboutDoc.Normalize(sentence)
		if n ~= "" then
			coverage.set[n] = true
			coverage.parts[#coverage.parts + 1] = n
		end
	end
	coverage.joined = nil
end

--- Whether a normalised sentence is already said: the same sentence, or
-- (at least MIN_INSIDE characters) a run of whole words inside it.
function AboutDoc.Covered(coverage, normalized)
	if normalized == "" or coverage.set[normalized] then
		return normalized ~= ""
	end
	if #normalized < AboutDoc.MIN_INSIDE then
		return false
	end
	coverage.joined = coverage.joined or (" " .. table.concat(coverage.parts, " ") .. " ")
	return coverage.joined:find(" " .. normalized .. " ", 1, true) ~= nil
end

--- text without the sentences coverage already holds. The kept sentences
-- are unchanged; a dropped sentence's line breaks stay, so paragraphs do
-- not merge. Returns text (possibly ""), dropped count. Pure.
function AboutDoc.Dedupe(text, coverage)
	local kept, dropped = {}, 0
	for _, sentence in ipairs(AboutDoc.Sentences(text)) do
		if AboutDoc.Covered(coverage, AboutDoc.Normalize(sentence)) then
			dropped = dropped + 1
			local breaks = sentence:match("\n[%s]*$")
			if breaks then kept[#kept + 1] = breaks end
		else
			kept[#kept + 1] = sentence
		end
	end
	if dropped == 0 then
		return text, 0
	end
	local out = table.concat(kept):gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
	out = out:match("^%s*(.-)%s*$")
	if not out:match("%w") then
		out = ""
	end
	return out, dropped
end

--- Building ------------------------------------------------------------------------

-- A written profile field's text (raw), or nil.
local function fieldValue(public, key)
	local entry = key and public.fields and public.fields[key]
	if type(entry) == "table" and entry.visibility == "public" and type(entry.value) == "string"
		and entry.value:match("%S") then
		return entry.value
	end
	return nil
end

-- Approved defining moments (the projection holds only publishable ones).
local function moments(public)
	local out = {}
	for _, entry in ipairs(public.journal or {}) do
		if entry.kind == "story" and entry.status == "approved" and entry.important and entry.title then
			out[#out + 1] = entry
		end
	end
	return out
end

--- What each section would say, deduplicated against the biography and the
-- sections before it (in this priority: biography, overview, appearance,
-- personality, motivation, developments), for the sections that are on.
-- Returns { [id] = chapters } where chapters is { { title?, body } }.
-- Bodies of the biography are raw (word for word); the rest are escaped.
local PRIORITY = { "biography", "overview", "appearance", "personality", "motivation", "developments" }

local function contents(public, on)
	local out = {}
	local coverage = AboutDoc.NewCoverage()
	local bio = public.biography and public.biography.text
	local chapters = {}
	for _, part in ipairs(AboutDoc.SplitBiography(bio)) do
		chapters[#chapters + 1] = { title = part.title, body = part.body }
	end
	if on.biography and #chapters > 0 then
		out.biography = chapters
		for _, ch in ipairs(chapters) do
			if ch.title then AboutDoc.Cover(coverage, ch.title) end
			AboutDoc.Cover(coverage, ch.body)
		end
	end
	for _, id in ipairs(PRIORITY) do
		if id == "developments" and on.developments then
			local list = {}
			for _, entry in ipairs(moments(public)) do
				local body = type(entry.text) == "string" and AboutDoc.Dedupe(entry.text, coverage) or ""
				local titleCovered = AboutDoc.Covered(coverage, AboutDoc.Normalize(entry.title))
				if body ~= "" then
					list[#list + 1] = { title = entry.title, body = escape(body) }
				elseif not titleCovered and not (type(entry.text) == "string" and entry.text:match("%S")) then
					-- A moment with only a title: the title is its line.
					list[#list + 1] = { body = escape(entry.title) }
				end
				if body ~= "" or not titleCovered then
					AboutDoc.Cover(coverage, entry.title)
					AboutDoc.Cover(coverage, body)
				end
			end
			if #list > 0 then out.developments = list end
		elseif on[id] and AboutDoc.FIELD_OF[id] then
			local value = fieldValue(public, AboutDoc.FIELD_OF[id])
			if value then
				local text = AboutDoc.Dedupe(value, coverage)
				if text ~= "" then
					out[id] = { { body = escape(text) } }
					AboutDoc.Cover(coverage, text)
				end
			end
		end
	end
	return out
end

--- The document from a public projection: an ordered list of sections
-- { id, title, icon, background, chapters = { { title?, body } } }, and
-- doc.style / doc.accent (the presentation settings the projection carries:
-- trp3Style, trp3Accent; trp3Sections for the order, titles and choices;
-- trp3About "summary" for the overview alone).
function AboutDoc.Build(public)
	public = public or {}
	local chosen = StorySchema.AboutSections({ trp3Sections = public.trp3Sections })
	local on = {}
	for _, s in ipairs(chosen) do
		on[s.id] = s.on and (public.trp3About ~= "summary" or s.id == "overview")
	end
	local said = contents(public, on)
	local doc = { style = public.trp3Style, accent = public.trp3Accent }
	for _, s in ipairs(chosen) do
		local chapters = on[s.id] and said[s.id]
		if chapters and #chapters > 0 then
			doc[#doc + 1] = { id = s.id, title = s.title, icon = s.icon, background = s.background,
				chapters = chapters }
		end
	end
	return doc
end

--- Rendering -----------------------------------------------------------------------

-- A section's chapters as markup: chapter titles as {h3}, bodies in the
-- body colour, one blank line between chapters.
local function chaptersText(style, chapters)
	local parts = {}
	for _, ch in ipairs(chapters) do
		local piece = {}
		if ch.title then piece[#piece + 1] = Presentation.ChapterHeading(style, ch.title) end
		if ch.body and ch.body:match("%S") then piece[#piece + 1] = Presentation.Body(style, ch.body) end
		if #piece > 0 then parts[#parts + 1] = table.concat(piece, "\n") end
	end
	return table.concat(parts, "\n\n")
end

-- A section as text: its heading (unless withoutHeading), then its body.
local function sectionText(style, section, chapters, withoutHeading)
	local body = chaptersText(style, chapters or section.chapters)
	if withoutHeading then
		return body
	end
	return Presentation.SectionHeading(style, section.title, 2, section.id, section.icon) .. "\n" .. body
end

-- A section's frame texts: one, or (over MAX_BYTES) split only between the
-- player's own chapters, the first part with the section's heading.
local function frameTexts(style, section)
	local whole = sectionText(style, section)
	if #whole <= AboutDoc.MAX_BYTES or #section.chapters < 2 then
		return { whole }
	end
	local out, current = {}, {}
	for _, ch in ipairs(section.chapters) do
		local try = {}
		for i, c in ipairs(current) do try[i] = c end
		try[#try + 1] = ch
		if #current > 0 and #sectionText(style, section, try, #out > 0) > AboutDoc.MAX_BYTES then
			out[#out + 1] = sectionText(style, section, current, #out > 0)
			current = { ch }
		else
			current = try
		end
	end
	out[#out + 1] = sectionText(style, section, current, #out > 0)
	return out
end

--- Renders a document for one template. Returns { T1 } (template 1),
-- { frames = { {TX, IC, BK}, ... } } (template 2) or { PH, PS, HI }
-- (template 3); a slot with nothing is "" (and absent frames are none).
-- styleId and accentId default to the document's own.
function AboutDoc.Render(doc, template, styleId, accentId)
	local style = Presentation.Resolve(styleId or doc.style, accentId or doc.accent)
	if template == 2 then
		local frames = {}
		for _, section in ipairs(doc) do
			local icon = Presentation.SafeIcon(section.icon, section.id)
			local background = Presentation.SafeBackground(section.background, style)
			for n, tx in ipairs(frameTexts(style, section)) do
				frames[#frames + 1] = { TX = tx, IC = icon, BK = background,
					id = n == 1 and section.id or (section.id .. "#" .. n) }
			end
		end
		return { frames = frames }
	end
	if template == 3 then
		local parts = { PH = {}, PS = {}, HI = {} }
		for _, section in ipairs(doc) do
			local slot = AboutDoc.T3_SLOT[section.id] or "HI"
			parts[slot][#parts[slot] + 1] = sectionText(style, section, nil, slot ~= "HI")
		end
		return { PH = table.concat(parts.PH, "\n\n"), PS = table.concat(parts.PS, "\n\n"),
			HI = table.concat(parts.HI, "\n\n") }
	end
	local texts = {}
	for _, section in ipairs(doc) do
		texts[#texts + 1] = sectionText(style, section)
	end
	return { T1 = table.concat(texts, "\n\n") }
end

--- Planning -------------------------------------------------------------------

-- A v0.8 record { block, template } as a v0.9 record (same ownership).
function AboutDoc.Upgrade(record)
	if type(record) ~= "table" or record.slots or record.frames then
		return record
	end
	if not record.block then
		return nil
	end
	local out = { template = record.template, mode = "append", slots = {}, frames = {} }
	if record.template == 1 then
		out.slots.T1 = record.block
	elseif record.template == 3 then
		out.slots.HI = record.block
	elseif record.template == 2 then
		-- The v0.8 frame was always added with AboutBlock's icon and background.
		out.frames = { record.block }
		out.frameStyles = { tostring(AboutBlock.FRAME_ICON) .. "|" .. tostring(AboutBlock.FRAME_BACKGROUND) }
	end
	return out
end

-- The holder table of a text slot (created on demand).
local function holder(about, slot)
	if slot == 1 or slot == "T1" then
		about.T1 = type(about.T1) == "table" and about.T1 or {}
		return about.T1
	end
	about.T3 = type(about.T3) == "table" and about.T3 or {}
	about.T3[slot] = type(about.T3[slot]) == "table" and about.T3[slot] or {}
	return about.T3[slot]
end

-- Count of plain occurrences ending at a line break or the end.
local function occurrences(text, needle)
	local count, first, init = 0, nil, 1
	while needle ~= "" do
		local s, e = text:find(needle, init, true)
		if not s then break end
		local after = text:sub(e + 1, e + 1)
		if after == "" or after == "\n" then
			count = count + 1
			first = first or s
		end
		init = s + 1
	end
	return count, first
end

local SEPARATOR = "\n\n"

-- Plans one text slot. Returns newText, newOwned or nil, reason.
local function planSlot(text, owned, want, mode, label)
	text = type(text) == "string" and text or ""
	if mode == "adopt" then
		if owned and text ~= owned then
			return nil, "the " .. label .. " was edited in Total RP 3 since Dawnward last wrote it"
		end
		return want, want ~= "" and want or nil
	end
	if owned then
		local n, at = occurrences(text, owned)
		if n == 0 then
			return nil, "Dawnward's part of the " .. label .. " was edited or removed in Total RP 3"
		elseif n > 1 then
			return nil, "Dawnward's part of the " .. label .. " appears more than once in Total RP 3"
		end
		if want == "" then
			return text:sub(1, at - 1) .. text:sub(at + #owned), nil
		end
		local separator = owned:sub(1, #SEPARATOR) == SEPARATOR and SEPARATOR or ""
		local newOwned = separator .. want
		return text:sub(1, at - 1) .. newOwned .. text:sub(at + #owned), newOwned
	end
	if want == "" then
		return text, nil
	end
	if text:find(want, 1, true) then
		return nil, "the " .. label .. " already contains Dawnward's text, which Dawnward has no record of writing; "
			.. "remove it in Total RP 3 (or choose Keep yours) so it is not duplicated"
	end
	local newOwned = (text == "" and "" or SEPARATOR) .. want
	return text .. newOwned, newOwned
end

local SLOT_LABELS = { T1 = "About text", PH = "physical description", PS = "personality text", HI = "history text" }

-- How a frame looked when Dawnward last styled it ("icon|background").
local function styleKey(frame)
	return tostring(frame.IC) .. "|" .. tostring(frame.BK)
end
AboutDoc.StyleKey = styleKey

-- The section a frame written before v0.10.1 (no frameIds in its record)
-- held, from its first heading: a v0.10 section title, or the biography for
-- any other heading (v0.9/v0.10 gave each of the player's chapters a frame).
local LEGACY_TITLES = { ["Character overview"] = "overview", Appearance = "appearance", Family = "family",
	["Beliefs and motivations"] = "beliefs", Personality = "personality", ["Defining experiences"] = "experiences",
	["Chronicle notes"] = "notes" }
function AboutDoc.LegacyFrameId(tx)
	local title = type(tx) == "string" and tx:match("^{h%d[:%a]*}(.-){/h%d}")
	if not title then
		return nil
	end
	title = title:gsub("{icon:[^}]*}%s*", ""):gsub("{col:%x+}", ""):gsub("{/col}", ""):match("^%s*(.-)%s*$")
	return LEGACY_TITLES[title] or "biography"
end

-- Whether the player restyled one of Dawnward's frames: it is not in the
-- style Dawnward gave it (was), or (style unknown: a record from before
-- v0.10.1) it has an icon or background Dawnward never writes.
local function restyled(frame, was)
	if was and was ~= "" then
		return was ~= styleKey(frame)
	end
	return not (type(frame.IC) == "string" and Presentation.ICONS[frame.IC:lower()]
		and Presentation.BACKGROUNDS[frame.BK])
end

-- Plans template 2 frames. Returns frames, ownedList, styles, ids or nil,
-- reason. wanted: { { TX, IC, BK, id } } in order. owned: the record's
-- frames (texts), frameStyles (styles: what Dawnward gave each, "" unknown)
-- and frameIds (ids: the section each held; absent before v0.10.1, then
-- read from the frame's heading).
-- Each wanted frame reuses the frame that held the same section (so the
-- player's restyling travels with its section); one with none takes
-- another unclaimed Dawnward frame, else a new one. Dawnward's frames keep
-- their places in the list: the wanted frames fill them in order, more go
-- after the last of them (or at the end), and places no longer needed are
-- removed. A reused frame still in Dawnward's style takes the wanted icon
-- and background; a restyled one keeps the player's. A restyled frame
-- that is no longer needed is a conflict, never dropped.
local function planFrames(frames, ownedList, wanted, mode, ownedStyles, ownedIds)
	frames = type(frames) == "table" and frames or {}
	ownedList = ownedList or {}
	ownedStyles = ownedStyles or {}
	local at = {}
	if mode == "adopt" and #ownedList > 0 then
		if #frames ~= #ownedList then
			return nil, "frames were added or removed in Total RP 3 since Dawnward last wrote them"
		end
		for i, tx in ipairs(ownedList) do
			if type(frames[i]) ~= "table" or frames[i].TX ~= tx then
				return nil, "a frame was edited in Total RP 3 since Dawnward last wrote it"
			end
			at[i] = i
		end
	else
		for i, tx in ipairs(ownedList) do
			local found
			for j, frame in ipairs(frames) do
				if type(frame) == "table" and frame.TX == tx then
					if found then return nil, "one of Dawnward's frames appears more than once in Total RP 3" end
					found = j
				end
			end
			if not found then
				return nil, "one of Dawnward's frames was edited or removed in Total RP 3"
			end
			at[i] = found
		end
	end
	local function fresh(want)
		return { TX = want.TX, IC = want.IC, BK = want.BK }
	end
	if mode == "adopt" and #ownedList == 0 then
		-- First takeover: Dawnward's frames replace the player's (kept in the backup).
		local out, owned, styles, ids = {}, {}, {}, {}
		for i, want in ipairs(wanted) do
			out[i] = fresh(want)
			owned[i], styles[i], ids[i] = want.TX, styleKey(want), want.id or ""
		end
		return out, owned, styles, ids
	end
	if #ownedList == 0 then
		for _, want in ipairs(wanted) do
			for _, frame in ipairs(frames) do
				if type(frame) == "table" and frame.TX == want.TX then
					return nil, "a frame already holds Dawnward's text, which Dawnward has no record of writing; "
						.. "remove it in Total RP 3 (or choose Keep yours) so it is not duplicated"
				end
			end
		end
	end
	-- Which owned frame each wanted frame reuses (match[k] = owned index).
	local idOf = {}
	for i, tx in ipairs(ownedList) do
		idOf[i] = ownedIds and ownedIds[i] or AboutDoc.LegacyFrameId(tx) or ""
	end
	local match, claimed = {}, {}
	for k, want in ipairs(wanted) do
		for i = 1, #ownedList do
			if not claimed[i] and want.id and idOf[i] == want.id then
				match[k], claimed[i] = i, true
				break
			end
		end
	end
	for k = 1, #wanted do
		if not match[k] then
			for i = 1, #ownedList do
				if not claimed[i] then
					match[k], claimed[i] = i, true
					break
				end
			end
		end
	end
	for i = 1, #ownedList do
		if not claimed[i] and restyled(frames[at[i]], ownedStyles[i]) then
			return nil, "a frame Dawnward no longer needs has your own icon or background in Total RP 3; remove it "
				.. "there yourself (or choose Keep yours) so your styling is not lost"
		end
	end
	-- The wanted frames, built.
	local built, styles, ids = {}, {}, {}
	for k, want in ipairs(wanted) do
		local i = match[k]
		if i then
			local base = frames[at[i]]
			local copy = Util.DeepCopy(base)
			copy.TX = want.TX
			local was = ownedStyles[i] or ""
			if was ~= "" and was == styleKey(base) then
				copy.IC, copy.BK = want.IC, want.BK
				was = styleKey(copy)
			end
			built[k], styles[k] = copy, was
		else
			built[k], styles[k] = fresh(want), styleKey(want)
		end
		ids[k] = want.id or ""
	end
	-- Dawnward's places in the list, in order.
	local places = {}
	for i = 1, #ownedList do places[#places + 1] = at[i] end
	table.sort(places)
	local placeIndex = {}
	for n, j in ipairs(places) do placeIndex[j] = n end
	local last = places[#places] or #frames
	local out, owned = {}, {}
	local function emit(k)
		out[#out + 1] = built[k]
		owned[#owned + 1] = built[k].TX
	end
	for j, frame in ipairs(frames) do
		local n = placeIndex[j]
		if n then
			if n <= #built then emit(n) end
		else
			out[#out + 1] = frame
		end
		if j == last then
			for k = #places + 1, #built do emit(k) end
		end
	end
	if #frames == 0 then
		for k = 1, #built do emit(k) end
	end
	return out, owned, styles, ids
end

-- Removes Dawnward's content from a copy of the About section. Returns the
-- copy, or nil plus a reason.
local function stripInto(about, record)
	record = AboutDoc.Upgrade(record)
	if not record then
		return about
	end
	for slot, owned in pairs(record.slots or {}) do
		local h = holder(about, slot == "T1" and 1 or slot)
		local text, err = planSlot(h.TX, owned, "", record.mode, SLOT_LABELS[slot] or "About text")
		if not text then
			return nil, err
		end
		h.TX = text ~= "" and text or nil
	end
	if record.frames and #record.frames > 0 then
		local frames, err = planFrames(about.T2, record.frames, {}, record.mode, record.frameStyles, record.frameIds)
		if not frames then
			return nil, err
		end
		about.T2 = frames
	end
	return about
end

--- A copy of the About section without Dawnward's content (any record
-- version), or nil plus a reason when it cannot be separated exactly.
function AboutDoc.Strip(about, record)
	return stripInto(Util.DeepCopy(about), record)
end

--- Plans the About page.
-- about: a COPY of TRP3's about section (modified in place).
-- record: the ledger's about record (v0.8, v0.9/v0.10 or v0.10.1 shape), or nil.
-- doc: from Build. opts: { template = 1|2|3|nil (nil: keep Total RP 3's
-- current template; a number switches it, an explicit player choice),
-- style = id, accent = id (default: the document's), adopt = true (first
-- takeover) }.
-- Returns { action, about, record, reason } like AboutBlock.Plan.
function AboutDoc.Plan(about, record, doc, opts)
	opts = opts or {}
	record = AboutDoc.Upgrade(record)
	local mode = (record and record.mode == "adopt" or (not record and opts.adopt)) and "adopt" or "append"
	if record and opts.adopt and record.mode ~= "adopt" then
		-- A takeover chosen after Dawnward already appended: its own part is
		-- replaced in place first; the player's text is then taken over.
		mode = "adopt"
	end
	local target = opts.template or about.TE
	if target ~= 1 and target ~= 2 and target ~= 3 then
		return { action = "unsupported", reason = "unknown About template " .. tostring(target) }
	end
	if record and record.template ~= about.TE then
		return { action = "conflict", record = record,
			reason = "the About template was changed in Total RP 3 since Dawnward last wrote it" }
	end
	-- A different template chosen in Dawnward: take Dawnward's content out of
	-- the old one, then write the new one fresh.
	if record and record.template ~= target then
		local stripped, err = stripInto(about, record)
		if not stripped then
			return { action = "conflict", record = record, reason = err }
		end
		record = nil
	end
	local rendered = AboutDoc.Render(doc, target, opts.style, opts.accent)
	local newRecord = { template = target, mode = mode, slots = {}, frames = {} }
	local before = Util.DeepCopy(about)
	if target == 2 then
		for _, frame in ipairs(rendered.frames) do
			if #frame.TX > AboutDoc.MAX_BYTES then
				return { action = "unsupported", reason = string.format("a section is %d bytes; Dawnward writes at "
					.. "most %d per frame and never shortens your text", #frame.TX, AboutDoc.MAX_BYTES) }
			end
		end
		local ownedFrames = record and record.frames or {}
		local adoptFirst = mode == "adopt" and not (record and record.mode == "adopt")
		local frames, owned, styles, ids = planFrames(about.T2, adoptFirst and {} or ownedFrames, rendered.frames,
			adoptFirst and "adopt" or (record and record.mode or mode), record and record.frameStyles,
			record and record.frameIds)
		if not frames then
			return { action = "conflict", record = record, reason = owned }
		end
		about.T2 = frames
		newRecord.frames = owned
		newRecord.frameStyles = #owned > 0 and styles or nil
		newRecord.frameIds = #owned > 0 and ids or nil
	else
		local slots = target == 1 and { "T1" } or { "PH", "PS", "HI" }
		for _, slot in ipairs(slots) do
			local want = slot == "T1" and rendered.T1 or rendered[slot]
			if #want > AboutDoc.MAX_BYTES then
				return { action = "unsupported", reason = string.format("the %s would be %d bytes; Dawnward writes "
					.. "at most %d and never shortens your text", SLOT_LABELS[slot], #want, AboutDoc.MAX_BYTES) }
			end
			local h = holder(about, slot == "T1" and 1 or slot)
			local owned = record and record.slots and record.slots[slot]
			local slotMode = mode
			if mode == "adopt" and record and record.mode ~= "adopt" and owned then
				-- Replace Dawnward's appended part in place, then own the slot.
				slotMode = "append"
			end
			local text, newOwned = planSlot(h.TX, owned, want, slotMode, SLOT_LABELS[slot])
			if not text then
				return { action = "conflict", record = record, reason = newOwned }
			end
			if mode == "adopt" then
				text, newOwned = want, want ~= "" and want or nil
			end
			h.TX = text ~= "" and text or nil
			newRecord.slots[slot] = newOwned
		end
	end
	if opts.template and about.TE ~= target then
		about.TE = target
	end
	if not next(newRecord.slots) and #newRecord.frames == 0 then
		newRecord = nil
	end
	if deepEqual(about, before) then
		return { action = "noop", about = about, record = record and AboutDoc.Upgrade(record) or newRecord }
	end
	local action = not record and "insert" or (newRecord and "replace" or "remove")
	return { action = action, about = about, record = newRecord }
end

--- Plain lines of everything a record owns (for the rollback preview).
function AboutDoc.OwnedText(record)
	record = AboutDoc.Upgrade(record)
	local parts = {}
	for _, slot in ipairs({ "T1", "PH", "PS", "HI" }) do
		if record and record.slots and record.slots[slot] then parts[#parts + 1] = record.slots[slot] end
	end
	for _, tx in ipairs(record and record.frames or {}) do parts[#parts + 1] = tx end
	return table.concat(parts, "\n")
end
