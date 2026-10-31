-- The full-profile About text (v0.9): the player's whole biography plus the
-- Public parts of the character, laid out in Total RP 3's own About
-- templates. Pure Lua: it works on copies and returns a plan; it never
-- touches TRP3.
--
-- What it publishes (only from the public projection):
--   * Character overview   the Public Summary field
--   * Appearance           the Public Appearance field (template 3: the
--                          physical description; otherwise its own section)
--   * the biography        the current biography source, word for word,
--                          when the biography itself is Public. It is split
--                          only at the player's own headings (a line
--                          "# Title" or "{h2}Title{/h2}"); text before the
--                          first heading is titled "Background". Nothing
--                          else in it is changed, cut or reordered.
--   * Family               Public family members
--   * Beliefs and motivations  the Public Motivation field and Public
--                          belief, motivation and fear facts
--   * Personality          Public stances and Public trait facts
--   * Defining experiences approved, Public defining moments and Public
--                          history entries
--   * Chronicle notes      the remaining Public facts
-- Section titles are Dawnward's generic container names (or the player's
-- own headings); no fact is ever invented to fill one.
--
-- Templates (verified in TRP3 3.4.1, RegisterAbout.lua): template 1 is one
-- text (T1.TX); template 2 is a list of frames { TX, IC, BK }; template 3 is
-- three texts with fixed titles: PH (physical), PS (personality), HI
-- (history). All are rendered by Utils.str.toHTML, which understands
-- {h1}..{h3}, "#" headings, {col}, {icon} and {p:c} (Presentation.lua).
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
-- About text is never duplicated.
local _, ns = ...
local Util, Schema, Presentation, AboutBlock = ns.Util, ns.Schema, ns.TRP3Presentation, ns.TRP3AboutBlock

local AboutDoc = {}
ns.TRP3AboutDoc = AboutDoc

-- Largest text Dawnward writes into one slot or frame. TRP3 has no hard
-- limit (its editor boxes are letters="0"); the biography itself is at most
-- 16 KB. Over this, nothing is written and the reason is shown.
AboutDoc.MAX_BYTES = 30000
AboutDoc.TEXT_SLOTS = { 1, "PH", "PS", "HI" }

-- Generated section order. Biography sections are inserted at "bio".
AboutDoc.ORDER = { "overview", "appearance", "bio", "family", "beliefs", "personality", "experiences", "notes" }
AboutDoc.TITLES = {
	overview = "Character overview", appearance = "Appearance", bio = "Background", family = "Family",
	beliefs = "Beliefs and motivations", personality = "Personality", experiences = "Defining experiences",
	notes = "Chronicle notes",
}
-- Which template 3 text each section goes to (the rest go to the history).
AboutDoc.T3_SLOT = { appearance = "PH", beliefs = "PS", personality = "PS" }

-- Belief-like fact categories (the rest of the public facts are notes).
local BELIEF_CATEGORIES = { belief = true, motivation = true, fear = true }

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

-- Lines of generated sections (player text in them is escaped).
local function familyLines(public)
	local lines = {}
	for _, item in ipairs(public.family or {}) do
		local relation = item.relation and (item.relation:sub(1, 1):upper() .. item.relation:sub(2)) or "Relative"
		local line = relation .. ": " .. (item.name or "unnamed")
		if item.status and item.status ~= "unknown" then line = line .. " (" .. item.status .. ")" end
		if item.notes then line = line .. ". " .. item.notes:gsub("\n", " ") end
		lines[#lines + 1] = escape(line)
	end
	return lines
end

local function factLines(public, wanted)
	local lines = {}
	for _, category in ipairs(Schema.FACT_CATEGORIES) do
		for _, fact in ipairs(public.facts or {}) do
			local id = Schema.FACT_CATEGORY_BY_ID[fact.category] and fact.category or "other"
			if id == category.id and wanted(id) then
				lines[#lines + 1] = escape(fact.statement:gsub("\n", " "))
			end
		end
	end
	return lines
end

local function fieldText(public, key)
	local entry = public.fields and public.fields[key]
	if type(entry) == "table" and entry.visibility == "public" and type(entry.value) == "string"
		and entry.value:match("%S") then
		return escape(entry.value)
	end
	return nil
end

--- The document: an ordered list of { id, title, body }, from a public
-- projection only. public.biography is set only when the biography is Public.
function AboutDoc.Build(public)
	public = public or {}
	local sections = {}
	local function add(id, body, title)
		if body and body:match("%S") then
			sections[#sections + 1] = { id = id, title = title or AboutDoc.TITLES[id], body = body }
		end
	end
	for _, id in ipairs(AboutDoc.ORDER) do
		if id == "overview" then
			add(id, fieldText(public, "summary"))
		elseif id == "appearance" then
			add(id, fieldText(public, "appearance"))
		elseif id == "bio" then
			local text = public.biography and public.biography.text
			for _, part in ipairs(AboutDoc.SplitBiography(text)) do
				add("bio", part.body ~= "" and part.body or " ", part.title)
			end
		elseif id == "family" then
			add(id, table.concat(familyLines(public), "\n"))
		elseif id == "beliefs" then
			local lines = {}
			local motivation = fieldText(public, "motivation")
			if motivation then lines[#lines + 1] = motivation end
			for _, line in ipairs(factLines(public, function(c) return BELIEF_CATEGORIES[c] end)) do
				lines[#lines + 1] = line
			end
			add(id, table.concat(lines, "\n"))
		elseif id == "personality" then
			local lines = {}
			for _, stance in ipairs(public.stances or {}) do
				lines[#lines + 1] = Presentation.StanceLine(Presentation.Get(public.trp3Style), stance)
			end
			for _, line in ipairs(factLines(public, function(c) return c == "trait" end)) do
				lines[#lines + 1] = line
			end
			add(id, table.concat(lines, "\n"))
		elseif id == "experiences" then
			local lines = {}
			for _, title in ipairs(AboutBlock.Moments(public)) do
				lines[#lines + 1] = "- " .. escape(title:gsub("\n", " "))
			end
			for _, item in ipairs(public.history or {}) do
				lines[#lines + 1] = "- " .. escape(((item.when and (item.when .. ": ")) or "") .. (item.text or ""))
			end
			add(id, table.concat(lines, "\n"))
		elseif id == "notes" then
			local lines = {}
			for _, category in ipairs(Schema.FACT_CATEGORIES) do
				if not BELIEF_CATEGORIES[category.id] and category.id ~= "trait" then
					for _, line in ipairs(factLines(public, function(c) return c == category.id end)) do
						lines[#lines + 1] = category.label .. ": " .. line
					end
				end
			end
			add(id, table.concat(lines, "\n"))
		end
	end
	return sections
end

-- A section as text: its styled heading, then its body.
local function sectionText(style, section, level)
	if section.raw then
		return section.body
	end
	return Presentation.SectionHeading(style, section.title, level, section.id) .. "\n" .. section.body
end

--- Renders a document for one template. Returns { T1 } (template 1),
-- { frames = { {TX, IC, BK}, ... } } (template 2) or { PH, PS, HI }
-- (template 3); a slot with nothing is "" (and absent frames are none).
function AboutDoc.Render(doc, template, styleId)
	local style = Presentation.Get(styleId)
	if template == 2 then
		local frames = {}
		for _, section in ipairs(doc) do
			frames[#frames + 1] = { TX = sectionText(style, section, 2),
				IC = section.raw and AboutBlock.FRAME_ICON or Presentation.SectionIcon(section.id),
				BK = section.raw and AboutBlock.FRAME_BACKGROUND or style.background or 1 }
		end
		return { frames = frames }
	end
	if template == 3 then
		local parts = { PH = {}, PS = {}, HI = {} }
		for _, section in ipairs(doc) do
			local slot = AboutDoc.T3_SLOT[section.id] or "HI"
			-- The physical description has TRP3's own title; one section
			-- there needs no heading of its own.
			if slot == "PH" then
				parts.PH[#parts.PH + 1] = section.body
			else
				parts[slot][#parts[slot] + 1] = sectionText(style, section, 3)
			end
		end
		return { PH = table.concat(parts.PH, "\n\n"), PS = table.concat(parts.PS, "\n\n"),
			HI = table.concat(parts.HI, "\n\n") }
	end
	local texts = {}
	for _, section in ipairs(doc) do
		texts[#texts + 1] = sectionText(style, section, 2)
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
		out.frames = { record.block }
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
		local separator = owned:sub(1, #AboutBlock.SEPARATOR) == AboutBlock.SEPARATOR and AboutBlock.SEPARATOR or ""
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
	local newOwned = (text == "" and "" or AboutBlock.SEPARATOR) .. want
	return text .. newOwned, newOwned
end

local SLOT_LABELS = { T1 = "About text", PH = "physical description", PS = "personality text", HI = "history text" }

-- Plans template 2 frames. Returns frames, ownedList or nil, reason.
local function planFrames(frames, ownedList, wanted, mode)
	frames = type(frames) == "table" and frames or {}
	ownedList = ownedList or {}
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
	if mode == "adopt" and #ownedList == 0 then
		-- First takeover: Dawnward's frames replace the player's (kept in the backup).
		local out, owned = {}, {}
		for i, want in ipairs(wanted) do
			out[i] = { TX = want.TX, IC = want.IC, BK = want.BK }
			owned[i] = want.TX
		end
		return out, owned
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
	-- Reuse Dawnward's frames in order (their icon and background stay as
	-- the player may have restyled them), add new ones after the last of
	-- them (or at the end), and remove the ones no longer needed.
	local out, owned, removed = {}, {}, {}
	local mine = {}
	for i, index in ipairs(at) do mine[index] = i end
	local lastOwnedIndex = 0
	for _, index in ipairs(at) do
		if index > lastOwnedIndex then lastOwnedIndex = index end
	end
	for i = #wanted + 1, #ownedList do
		removed[at[i]] = true
	end
	for j, frame in ipairs(frames) do
		local i = mine[j]
		if i and i <= #wanted then
			local copy = Util.DeepCopy(frame)
			copy.TX = wanted[i].TX
			out[#out + 1] = copy
			owned[#owned + 1] = copy.TX
		elseif not removed[j] then
			out[#out + 1] = frame
		end
		if j == lastOwnedIndex or (lastOwnedIndex == 0 and j == #frames) then
			for k = #ownedList + 1, #wanted do
				out[#out + 1] = { TX = wanted[k].TX, IC = wanted[k].IC, BK = wanted[k].BK }
				owned[#owned + 1] = wanted[k].TX
			end
		end
	end
	if #frames == 0 then
		for k = 1, #wanted do
			out[#out + 1] = { TX = wanted[k].TX, IC = wanted[k].IC, BK = wanted[k].BK }
			owned[#owned + 1] = wanted[k].TX
		end
	end
	return out, owned
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
		local frames, err = planFrames(about.T2, record.frames, {}, record.mode)
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

--- Plans the full-profile About.
-- about: a COPY of TRP3's about section (modified in place).
-- record: the ledger's about record (v0.8 or v0.9 shape), or nil.
-- doc: from Build. opts: { template = 1|2|3|nil (nil: keep Total RP 3's
-- current template; a number switches it, an explicit player choice),
-- style = id, adopt = true (first takeover) }.
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
	local rendered = AboutDoc.Render(doc, target, opts.style)
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
		local frames, owned = planFrames(about.T2, adoptFirst and {} or ownedFrames, rendered.frames,
			adoptFirst and "adopt" or (record and record.mode or mode))
		if not frames then
			return { action = "conflict", record = record, reason = owned }
		end
		about.T2 = frames
		newRecord.frames = owned
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
