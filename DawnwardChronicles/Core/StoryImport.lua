-- Story import (#23, #16): bring a story the player already wrote (a pasted
-- backstory, or the text of their own Total RP 3 About page) into Dawnward.
--
--   1. Capture   the text is stored verbatim as a biography source
--                (Core/Sources.lua): byte for byte, never cleaned, never
--                shortened (text over the size limit is refused, not cut).
--   2. Split     the text is cut into pieces, one per sentence (or per
--                paragraph). This is plain rule-based splitting, not
--                understanding: every piece is a quote of the player's own
--                words, never a rewording, and a piece longer than a fact
--                can hold is cut into consecutive parts at word boundaries.
--   3. Propose   each piece becomes an open suggestion (Core/
--                Interpretations.lua), private, linked to the source version
--                and its position ("p2 s1"). A category is guessed from a
--                few keywords only as a starting point; the player changes it.
--   4. Review    the player approves a piece into canon (Interpretations.
--                Promote, with their edits; Private unless they choose),
--                skips it (remembered, so it is never suggested again), or
--                leaves it for later. Nothing becomes canon without approval.
--
-- Importing the same or an edited text again proposes only pieces that are
-- new: pieces already approved, skipped or waiting, or equal to an existing
-- fact, are not suggested twice. Nothing here writes to Total RP 3; reading
-- the About text (AboutText) works on a copy the TRP3 adapter returned.
local _, ns = ...
local Schema, Util, Privacy, Sources, Interpretations, Facts =
	ns.Schema, ns.Util, ns.Privacy, ns.Sources, ns.Interpretations, ns.Facts

local StoryImport = {}
ns.StoryImport = StoryImport

-- Source kinds the wizard captures, and the fact origin each one records.
StoryImport.ORIGINS = { paste = "paste", trp3 = "trp3-biography" }
StoryImport.ORIGIN_SET = { paste = true, ["trp3-biography"] = true }
StoryImport.MODES = { sentence = true, paragraph = true }
StoryImport.DEFAULT_MODE = "sentence"
-- A piece is at most one fact statement long.
StoryImport.PIECE_BYTES = Schema.FOUNDATION.statement

--- Splitting ----------------------------------------------------------------------

-- Cuts text longer than limit into parts at word boundaries (never inside a
-- UTF-8 character). Every part is a substring of the text.
function StoryImport.SplitLong(text, limit)
	limit = limit or StoryImport.PIECE_BYTES
	local parts = {}
	local s = Util.Trim(text or "")
	while #s > limit do
		local cut = Util.TruncateUtf8(s, limit)
		-- The last whitespace inside the cut, if it leaves a useful first part.
		local space
		for i = #cut, math.floor(limit / 2), -1 do
			if cut:sub(i, i):match("%s") then
				space = i
				break
			end
		end
		if space then
			parts[#parts + 1] = Util.Trim(s:sub(1, space - 1))
			s = Util.Trim(s:sub(space + 1))
		else
			parts[#parts + 1] = cut
			s = Util.Trim(s:sub(#cut + 1))
		end
	end
	if s ~= "" then
		parts[#parts + 1] = s
	end
	return parts
end

--- The pieces of a text, in order: { { text, ref, paragraph, sentence } }.
-- kind "trp3" removes Total RP 3 text tags first (display only; the stored
-- source keeps them). mode: "sentence" (default) or "paragraph".
function StoryImport.Pieces(text, kind, mode)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	local display = kind == "trp3" and Sources.StripTags(text) or text
	for p, paragraph in ipairs(Sources.Paragraphs(display)) do
		local units = mode == "paragraph" and { paragraph } or Sources.Sentences(paragraph)
		for s, unit in ipairs(units) do
			local parts = StoryImport.SplitLong(unit)
			for k, part in ipairs(parts) do
				local ref = mode == "paragraph" and ("p" .. p) or ("p" .. p .. " s" .. s)
				if #parts > 1 then
					ref = ref .. " part " .. k .. "/" .. #parts
				end
				out[#out + 1] = { text = part, ref = ref, paragraph = p, sentence = s }
			end
		end
	end
	return out
end

--- "p2 s1 part 1/2" -> "Paragraph 2, sentence 1 (part 1 of 2)". Pure.
function StoryImport.RefText(ref)
	if type(ref) ~= "string" then
		return ""
	end
	local p, rest = ref:match("^p(%d+)(.*)$")
	if not p then
		return ref
	end
	local text = "Paragraph " .. p
	local s = rest:match("^ s(%d+)")
	if s then
		text = text .. ", sentence " .. s
	end
	local k, n = rest:match("part (%d+)/(%d+)")
	if k then
		text = text .. " (part " .. k .. " of " .. n .. ")"
	end
	return text
end

--- Category hints ----------------------------------------------------------------
-- A starting point only, shown as "suggested"; the player picks the real one.
-- Matched against whole lower-case words; the first rule that matches wins.
StoryImport.CATEGORY_HINTS = {
	{ "fear", { "fear", "fears", "feared", "afraid", "dread", "dreads", "terrified", "nightmares" } },
	{ "belief", { "believe", "believes", "believed", "faith", "pray", "prays", "prayed", "creed", "vow", "vowed",
		"sworn", "conviction" } },
	{ "motivation", { "want", "wants", "wanted", "seek", "seeks", "sought", "dream", "dreams", "hope", "hopes",
		"goal", "ambition", "determined", "must", "longs" } },
	{ "origin", { "born", "grew", "raised", "childhood", "orphan", "orphaned", "homeland", "hometown", "youth" } },
	{ "relationship", { "mother", "father", "brother", "sister", "son", "daughter", "wife", "husband", "friend",
		"mentor", "lover", "family", "cousin", "uncle", "aunt", "rival" } },
	{ "trait", { "always", "never", "tends", "habit", "known", "stubborn", "quiet", "patient", "temper" } },
}

local HINT_WORDS = {}
for _, rule in ipairs(StoryImport.CATEGORY_HINTS) do
	local set = {}
	for _, word in ipairs(rule[2]) do set[word] = true end
	HINT_WORDS[#HINT_WORDS + 1] = { category = rule[1], words = set }
end

--- A suggested fact category for a piece ("other" when nothing matches). Pure.
function StoryImport.GuessCategory(text)
	local words = {}
	for word in tostring(text or ""):lower():gmatch("%a+") do
		words[word] = true
	end
	for _, rule in ipairs(HINT_WORDS) do
		for word in pairs(rule.words) do
			if words[word] then
				return rule.category
			end
		end
	end
	return "other"
end

--- Total RP 3 About text (read-only) ----------------------------------------------

--- The player's own About text from a copy of their About section, without
-- anything Dawnward added there (record: the sync ledger's record of what
-- it wrote, or nil). Template 1: the text; template 2: each frame's text;
-- template 3: the physical, personality and history texts; parts joined by
-- a blank line. Returns text, or nil plus a reason. Never changes about.
function StoryImport.AboutText(about, record)
	if type(about) ~= "table" then
		return nil, "the About section could not be read"
	end
	local copy = about
	if record and ns.TRP3AboutBlock then
		copy = ns.TRP3AboutBlock.WithoutOwned(about, record)
	end
	local parts = {}
	local function add(holder)
		local text = type(holder) == "table" and holder.TX
		if type(text) == "string" and text:match("%S") then
			parts[#parts + 1] = text
		end
	end
	if copy.TE == 2 then
		for _, frame in ipairs(type(copy.T2) == "table" and copy.T2 or {}) do add(frame) end
	elseif copy.TE == 3 then
		local t3 = type(copy.T3) == "table" and copy.T3 or {}
		add(t3.PH); add(t3.PS); add(t3.HI)
	else
		add(copy.T1)
	end
	if #parts == 0 then
		return nil, "your Total RP 3 About page has no text of your own yet"
	end
	return table.concat(parts, "\n\n")
end

--- Capture and proposals -----------------------------------------------------------

--- Stores text verbatim as the current biography source (kind "paste" or
-- "trp3"). Returns version, "stored" | "unchanged"; or nil plus a reason.
function StoryImport.Capture(char, kind, text, meta, now)
	if not StoryImport.ORIGINS[kind] then
		return nil, "unknown story source '" .. tostring(kind) .. "'"
	end
	if type(text) ~= "string" or not text:match("%S") then
		return nil, "there is no text to import"
	end
	return Sources.Capture(char, kind, text, meta, now)
end

-- Normalised statements of existing facts, so a piece the player already
-- has as canon is not suggested again.
local function factTexts(char)
	local set = {}
	for _, fact in ipairs(char.facts or {}) do
		set[Interpretations.NormalizeText(fact.statement)] = true
	end
	return set
end

--- Proposes every new piece of a stored source version as a private
-- suggestion. Returns { proposed, known, full, total }: proposed now,
-- already known (approved, skipped, waiting or an existing fact), and left
-- out because the suggestion list is full (import again after reviewing).
function StoryImport.Propose(char, version, mode, now)
	local result = { proposed = 0, known = 0, full = 0, total = 0 }
	if type(version) ~= "table" or not StoryImport.ORIGINS[version.kind] then
		return result
	end
	mode = StoryImport.MODES[mode] and mode or StoryImport.DEFAULT_MODE
	local existing = factTexts(char)
	for _, piece in ipairs(StoryImport.Pieces(version.text, version.kind, mode)) do
		result.total = result.total + 1
		if existing[Interpretations.NormalizeText(piece.text)] then
			result.known = result.known + 1
		else
			local item, why = Interpretations.Propose(char, {
				kind = "candidate",
				category = StoryImport.GuessCategory(piece.text),
				statement = piece.text,
				origin = StoryImport.ORIGINS[version.kind],
				sourceId = version.id,
				sourceVersion = version.hash,
				ref = piece.ref,
				excerpt = piece.text,
				visibility = Privacy.DEFAULT,
			}, now)
			if item then
				result.proposed = result.proposed + 1
			elseif why == "full" then
				result.full = result.full + 1
			else
				-- "known", or a piece with nothing left after cleaning.
				result.known = result.known + 1
			end
		end
	end
	return result
end

--- Open suggestions from imported stories, oldest first (stored records).
function StoryImport.Waiting(char)
	local out = {}
	for _, item in ipairs(char and char.interpretations or {}) do
		if StoryImport.ORIGIN_SET[item.origin] then
			out[#out + 1] = item
		end
	end
	return out
end

--- { waiting, approved, skipped } for imported stories. Pure.
function StoryImport.Counts(char)
	local counts = { waiting = #StoryImport.Waiting(char), approved = 0, skipped = 0 }
	for _, fact in ipairs(char and char.facts or {}) do
		local p = fact.provenance
		if p and p.interpreted and StoryImport.ORIGIN_SET[p.origin] then
			counts.approved = counts.approved + 1
		end
	end
	for key, entry in pairs(char and char.interpretationKeys or {}) do
		local origin = key:match("^([^:]+):")
		if entry.status == "rejected" and StoryImport.ORIGIN_SET[origin] then
			counts.skipped = counts.skipped + 1
		end
	end
	return counts
end

--- Approves one waiting piece into canon with the player's edits
-- ({ statement?, category?, visibility? }). Private unless the player chose
-- otherwise. Returns the fact, or nil plus a reason (nothing changes).
function StoryImport.Approve(char, key, edits, now)
	local item = Interpretations.Find(char, key)
	if not item or not StoryImport.ORIGIN_SET[item.origin] then
		return nil, "that piece is no longer waiting"
	end
	edits = edits or {}
	local visibility = edits.visibility or Privacy.DEFAULT
	if not Privacy.IsValid(visibility) then
		return nil, "visibility must be public, private or secret"
	end
	if edits.category ~= nil and not Facts.IsRegistered(edits.category) then
		return nil, "unknown category '" .. tostring(edits.category) .. "'"
	end
	if edits.statement ~= nil then
		if not Schema.CleanStatement(edits.statement) then
			return nil, "the fact would be empty; write something or skip it"
		end
		-- Never shortened silently: a fact holds at most this much.
		if #Util.Trim(edits.statement) > Schema.FOUNDATION.statement then
			return nil, "a fact can be at most " .. Schema.FOUNDATION.statement .. " characters"
		end
	end
	return Interpretations.Promote(char, key, { statement = edits.statement, category = edits.category,
		visibility = visibility }, now)
end

--- Skips a waiting piece: it is removed and never suggested again.
function StoryImport.Skip(char, key, now)
	local item = Interpretations.Find(char, key)
	if not item or not StoryImport.ORIGIN_SET[item.origin] then
		return nil, "that piece is no longer waiting"
	end
	return Interpretations.Reject(char, key, now)
end

--- What a fact would look like once public (for the confirmation before
-- approving a piece as Public). Pure.
function StoryImport.PublicPreview(statement, category)
	local label = Facts.DisplayCategory(category).label
	return label .. ": " .. (Schema.CleanStatement(statement) or "")
end

--- Player actions (window and chat) ------------------------------------------------
-- Every write goes through Actions.WithCharacter: read-only data is refused,
-- and a failed first write leaves no empty character behind.

local function act(ctx, fn)
	local Actions = ns.Actions
	return Actions.WithCharacter(ctx, function(char)
		local result, message = fn(char, ctx.now())
		if not result then return Actions.Fail(message) end
		return result, message
	end)
end

--- Saves the text verbatim and proposes its pieces. Returns
-- { version, status, proposed, known, full, total }, message.
function StoryImport.Import(ctx, kind, text, meta, mode)
	return act(ctx, function(char, now)
		local version, status = StoryImport.Capture(char, kind, text, meta, now)
		if not version then return nil, status end
		local r = StoryImport.Propose(char, version, mode, now)
		r.version, r.status = version, status
		local parts = {}
		parts[#parts + 1] = status == "unchanged" and "This story is already saved, unchanged."
			or "Saved your story exactly as written."
		if r.proposed > 0 then
			parts[#parts + 1] = r.proposed == 1 and "1 piece is ready to review."
				or (r.proposed .. " pieces are ready to review.")
		else
			parts[#parts + 1] = "No new pieces to review."
		end
		if r.known > 0 then
			parts[#parts + 1] = r.known .. " already reviewed or already in your canon."
		end
		if r.full > 0 then
			parts[#parts + 1] = r.full .. " more did not fit in the review list; review some, then import again."
		end
		return r, table.concat(parts, " ")
	end)
end

function StoryImport.ApproveAction(ctx, key, edits)
	return act(ctx, function(char, now)
		local fact, err = StoryImport.Approve(char, key, edits, now)
		if not fact then return nil, err end
		return fact, "Added to your canon as fact #" .. fact.id .. " ("
			.. (ns.Themes.VISIBILITY_LABELS[fact.visibility] or fact.visibility) .. ")."
	end)
end

function StoryImport.SkipAction(ctx, key)
	return act(ctx, function(char, now)
		local item, err = StoryImport.Skip(char, key, now)
		if not item then return nil, err end
		return item, "Skipped. It will not be suggested again."
	end)
end

--- /dawnward biography: open the import window, or "status".
local function statusLines(char)
	local lines = {}
	local current = char and Sources.Current(char)
	if current then
		lines[#lines + 1] = string.format("Stored story: version %d, %d bytes (%s), saved verbatim.", current.id,
			#current.text, current.kind == "trp3" and "from Total RP 3" or "pasted")
	else
		lines[#lines + 1] = "No story stored yet. Open the import window with /dawnward biography."
	end
	local c = StoryImport.Counts(char)
	lines[#lines + 1] = string.format("Imported pieces: %d waiting, %d approved, %d skipped.", c.waiting, c.approved,
		c.skipped)
	return lines
end
StoryImport.StatusLines = statusLines

if ns.Commands and ns.Commands.Register then
	ns.Commands.Register("biography", function(ctx, rest)
		local sub = Util.NextWord(rest or ""):lower()
		if sub == "status" then
			for _, line in ipairs(statusLines(ns.Actions.Character(ctx))) do
				ns.Commands.Out(ctx, line)
			end
		elseif ctx.ui and ctx.ui.ShowStoryImport then
			ctx.ui.ShowStoryImport()
		else
			ns.Commands.Out(ctx, "The story import window opens in the game window. /dawnward biography status "
				.. "shows what is stored.")
		end
	end)
end
