-- Dawnward-owned content inside the TRP3 About section. Pure Lua: it works
-- on copies and returns a plan; it never touches TRP3.
--
-- Ownership is proven by an exact match against the ledger's record of what
-- Dawnward last wrote, so no markers appear in the profile:
--   template 1   an appended block at the end of T1.TX
--   template 2   one whole frame Dawnward added to T2
--   template 3   an appended block at the end of the history text (T3.HI.TX)
-- The owned string includes the blank-line separator Dawnward added, so
-- removing the block restores the player's text byte for byte. If the owned
-- content cannot be found exactly once, the plan is a conflict and nothing
-- is written: the player's edit wins until they decide.
local _, ns = ...
local Util, Schema, Presentation = ns.Util, ns.Schema, ns.TRP3Presentation

local AboutBlock = {}
ns.TRP3AboutBlock = AboutBlock

AboutBlock.HEADING = Presentation.STYLES.neutral.heading
AboutBlock.SEPARATOR = "\n\n"
AboutBlock.MAX_BYTES = 4000
-- New template 2 frames: a neutral book icon and TRP3's first background.
AboutBlock.FRAME_ICON = "INV_Misc_Book_09"
AboutBlock.FRAME_BACKGROUND = 1

-- Defining moments: public journal entries the player wrote or approved as
-- story and marked important. Unapproved drafts can never be public
-- (Journal.SetVisibility), and the public projection holds nothing else.
local function moments(public)
	local out = {}
	for _, entry in ipairs(public and public.journal or {}) do
		if entry.kind == "story" and entry.status == "approved" and entry.important and entry.title
			and entry.visibility == "public" then
			out[#out + 1] = entry.title
		end
	end
	return out
end
AboutBlock.Moments = moments

--- Builds the block from a public projection (never from private data).
-- public.trp3Style picks a presentation style (Presentation.lua); the
-- default style gives exactly the v0.3 block. Returns "" when there is
-- nothing public to show.
function AboutBlock.Compose(public)
	local facts = public and public.facts or {}
	local chosen = moments(public)
	local stances = public and public.stances or {}
	if #facts == 0 and #chosen == 0 and #stances == 0 then
		return ""
	end
	local style = Presentation.Get(public.trp3Style)
	local byCategory = {}
	for _, fact in ipairs(facts) do
		local category = Schema.FACT_CATEGORY_BY_ID[fact.category] or Schema.FACT_CATEGORY_BY_ID.other
		byCategory[category.id] = byCategory[category.id] or {}
		table.insert(byCategory[category.id], fact)
	end
	local lines = { style.heading }
	local used = #lines[1]
	local omitted = 0
	local function add(line)
		-- Leave room for the "more" note so the block never exceeds the cap.
		if used + 1 + #line > AboutBlock.MAX_BYTES - 60 then
			omitted = omitted + 1
		else
			lines[#lines + 1] = line
			used = used + 1 + #line
		end
	end
	for _, category in ipairs(Schema.FACT_CATEGORIES) do
		for _, fact in ipairs(byCategory[category.id] or {}) do
			add(Presentation.FactLine(style, category.label, fact.statement))
		end
	end
	if #stances > 0 then
		add((#facts > 0 and "\n" or "") .. style.stancesHeading)
		for _, stance in ipairs(stances) do
			add(Presentation.StanceLine(style, stance))
		end
	end
	if #chosen > 0 then
		add(((#facts > 0 or #stances > 0) and "\n" or "") .. style.momentsHeading)
		for _, title in ipairs(chosen) do
			add(Presentation.MomentLine(style, title))
		end
	end
	if omitted > 0 then
		lines[#lines + 1] = string.format("(%d more in the character's chronicle)", omitted)
	end
	return table.concat(lines, "\n")
end

-- Finds plain (non-pattern) occurrences of needle that end at a line break
-- or the end of the text. Text typed straight onto the end of the block means
-- the block was edited, so that is not a match. Returns count, first start.
local function findOwned(haystack, needle)
	local count, first, init = 0, nil, 1
	while true do
		local s, e = haystack:find(needle, init, true)
		if not s then
			return count, first
		end
		local after = haystack:sub(e + 1, e + 1)
		if after == "" or after == "\n" then
			count = count + 1
			first = first or s
		end
		init = s + 1
	end
end

local function replaceAt(haystack, start, needle, replacement)
	return haystack:sub(1, start - 1) .. replacement .. haystack:sub(start + #needle)
end

-- Plans a change to an appended block in a text field. Returns
-- newText, ownedString, action or nil, reason.
local function planText(text, owned, block)
	text = text or ""
	if owned then
		local n, at = findOwned(text, owned)
		if n == 0 then
			return nil, "the Dawnward section was edited or removed in Total RP 3"
		elseif n > 1 then
			return nil, "the Dawnward section appears more than once in Total RP 3"
		end
		if block == "" then
			return replaceAt(text, at, owned, ""), nil, "remove"
		end
		-- Keep the same separator choice as the original insert.
		local separator = owned:sub(1, #AboutBlock.SEPARATOR) == AboutBlock.SEPARATOR and AboutBlock.SEPARATOR or ""
		local newOwned = separator .. block
		if newOwned == owned then
			return text, owned, "noop"
		end
		return replaceAt(text, at, owned, newOwned), newOwned, "replace"
	end
	if block == "" then
		return text, nil, "noop"
	end
	local newOwned = (text == "" and "" or AboutBlock.SEPARATOR) .. block
	return text .. newOwned, newOwned, "insert"
end

--- Plans an update of the Dawnward-owned content.
-- about: a COPY of TRP3's about section (it is modified in place).
-- record: the ledger's { block, template } for this profile, or nil.
-- block: the desired text from Compose ("" to remove Dawnward's content).
-- Returns { action, about, record, reason }, where action is "noop",
-- "insert", "replace", "remove", "conflict" or "unsupported", and record is
-- the ledger entry to store after a successful write (nil = none).
function AboutBlock.Plan(about, record, block)
	if type(block) ~= "string" or #block > AboutBlock.MAX_BYTES then
		return { action = "unsupported", reason = "the Dawnward section is too long" }
	end
	local template = about.TE
	if record and record.template ~= template then
		return { action = "conflict", record = record,
			reason = "the About template was changed in Total RP 3 since Dawnward last wrote it" }
	end
	local owned = record and record.block or nil

	if template == 1 or template == 3 then
		local holder
		if template == 1 then
			about.T1 = about.T1 or {}
			holder = about.T1
		else
			about.T3 = about.T3 or {}
			about.T3.HI = about.T3.HI or {}
			holder = about.T3.HI
		end
		local text, newOwned, action = planText(holder.TX, owned, block)
		assert(not newOwned or #newOwned <= AboutBlock.MAX_BYTES + #AboutBlock.SEPARATOR, "owned block too long")
		if not text then
			return { action = "conflict", record = record, reason = newOwned }
		end
		if action ~= "noop" then
			holder.TX = text
		end
		return { action = action, about = about,
			record = newOwned and { block = newOwned, template = template } or nil }
	end

	if template == 2 then
		about.T2 = about.T2 or {}
		local frames = about.T2
		local index, count = nil, 0
		if owned then
			for i, frame in ipairs(frames) do
				if type(frame) == "table" and frame.TX == owned then
					index, count = i, count + 1
				end
			end
			if count == 0 then
				return { action = "conflict", record = record,
					reason = "the Dawnward frame was edited or removed in Total RP 3" }
			elseif count > 1 then
				return { action = "conflict", record = record,
					reason = "the Dawnward frame appears more than once in Total RP 3" }
			end
		end
		if block == "" then
			if not index then
				return { action = "noop", about = about }
			end
			local frame = frames[index]
			if frame.IC ~= AboutBlock.FRAME_ICON or frame.BK ~= AboutBlock.FRAME_BACKGROUND then
				-- The player restyled the frame; removing it would lose their choice.
				return { action = "conflict", record = record,
					reason = "the Dawnward frame's icon or background was changed in Total RP 3" }
			end
			table.remove(frames, index)
			return { action = "remove", about = about }
		end
		if index then
			if frames[index].TX == block then
				return { action = "noop", about = about, record = record }
			end
			frames[index].TX = block
			return { action = "replace", about = about, record = { block = block, template = 2 } }
		end
		frames[#frames + 1] = { TX = block, IC = AboutBlock.FRAME_ICON, BK = AboutBlock.FRAME_BACKGROUND }
		return { action = "insert", about = about, record = { block = block, template = 2 } }
	end

	return { action = "unsupported", reason = "unknown About template " .. tostring(template) }
end

--- What the player's own text looks like without Dawnward's content (for
-- previews and checks). Returns a copy.
function AboutBlock.WithoutOwned(about, record)
	local copy = Util.DeepCopy(about)
	if not record then
		return copy
	end
	local plan = AboutBlock.Plan(copy, record, "")
	return plan.about or copy
end
