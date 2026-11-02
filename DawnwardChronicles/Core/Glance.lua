-- At First Glance entries the player writes for Total RP 3 (v0.9).
--
-- Total RP 3's Miscellaneous tab has five "At First Glance" slots: a short
-- title, a text and an icon, each shown to other players only while it is
-- active. Dawnward never invents them: an entry exists only because the
-- player wrote it here (/dawnward trp3 glance set). Nothing in Dawnward's
-- character, story or journal is turned into a glance automatically.
--
-- Stored per character as char.glance[n] = { title?, text?, icon?, active }
-- for n = 1..Glance.SLOTS (sparse). An entry needs a title or a text. The
-- number is Dawnward's own; which Total RP 3 slot an entry lands in is
-- decided when it is written (Integrations/TRP3/GlancePlan.lua), never over
-- a slot the player filled in Total RP 3 themselves.
--
-- Loaded before Core/Schema.lua, which cleans this table on load.
local _, ns = ...
local Util = ns.Util

local Glance = {}
ns.Glance = Glance

-- Total RP 3 3.4.1 shows and sends five slots, keyed "1".."5"
-- (RegisterMisc.lua displayPeek and getMiscExchangeData: for i=1,5).
Glance.SLOTS = 5
Glance.LIMITS = { title = 100, text = 2000, icon = 64 }
-- TRP3's own fallback icon (Resources/InterfaceIcons.lua DEFAULT_ICON_NAME),
-- written when the player chose none so TRP3 never meets a slot without IC.
Glance.DEFAULT_ICON = "inv_misc_questionmark"

local function touch(char, now)
	if now then
		char.updatedAt = now
	end
end

local function cleanTitle(v)
	local s = Util.CleanText(v, Glance.LIMITS.title, false)
	return s ~= nil and s ~= "" and s or nil
end

local function cleanText(v)
	local s = Util.CleanText(v, Glance.LIMITS.text, true)
	return s ~= nil and s ~= "" and s or nil
end

--- An icon name as TRP3 stores it ("inv_misc_questionmark"): letters,
-- digits, "_" and "-" only, so it can never carry an escape code. nil if not.
function Glance.CleanIcon(v)
	if type(v) ~= "string" or v == "" or #v > Glance.LIMITS.icon or not v:match("^[%w_%-]+$") then
		return nil
	end
	return v
end

--- The slot number n as an integer 1..SLOTS, or nil.
function Glance.Index(n)
	n = tonumber(n)
	if Util.IsPositiveInteger(n) and n <= Glance.SLOTS then
		return n
	end
	return nil
end

--- A cleaned entry, or nil when it has neither title nor text.
function Glance.CleanEntry(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local entry = { title = cleanTitle(raw.title), text = cleanText(raw.text), icon = Glance.CleanIcon(raw.icon),
		active = raw.active ~= false }
	if not entry.title and not entry.text then
		return nil
	end
	return entry
end

--- Cleans char.glance on load: unknown keys and empty entries are dropped.
function Glance.Clean(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for n = 1, Glance.SLOTS do
		out[n] = Glance.CleanEntry(raw[n])
	end
	return out
end

local function store(char)
	char.glance = char.glance or {}
	return char.glance
end

--- Writes entry n's title and text (the text may be empty). A new entry
-- starts active; an existing one keeps its icon and active flag.
-- Returns the entry, or nil plus a reason.
function Glance.Set(char, n, title, text, now)
	local index = Glance.Index(n)
	if not index then
		return nil, "choose an entry from 1 to " .. Glance.SLOTS
	end
	local existing = store(char)[index]
	local entry = Glance.CleanEntry({ title = title, text = text, icon = existing and existing.icon,
		active = existing == nil or existing.active })
	if not entry then
		return nil, "write a title or a text"
	end
	store(char)[index] = entry
	touch(char, now)
	return entry
end

--- Sets entry n's icon (nil restores the default). Returns the entry, or nil plus a reason.
function Glance.SetIcon(char, n, icon, now)
	local index = Glance.Index(n)
	local entry = index and store(char)[index]
	if not entry then
		return nil, "there is no At First Glance entry " .. tostring(n)
	end
	if icon ~= nil and not Glance.CleanIcon(icon) then
		return nil, "an icon is a Total RP 3 icon name such as inv_misc_questionmark"
	end
	entry.icon = icon
	touch(char, now)
	return entry
end

--- Shows (true) or hides (false) entry n in Total RP 3, as its "active" box does.
function Glance.SetActive(char, n, on, now)
	local index = Glance.Index(n)
	local entry = index and store(char)[index]
	if not entry then
		return nil, "there is no At First Glance entry " .. tostring(n)
	end
	entry.active = on == true
	touch(char, now)
	return entry
end

--- Removes entry n. Returns true, or nil plus a reason.
function Glance.Clear(char, n, now)
	local index = Glance.Index(n)
	if not index or not store(char)[index] then
		return nil, "there is no At First Glance entry " .. tostring(n)
	end
	store(char)[index] = nil
	touch(char, now)
	return true
end

--- The entries to publish, in Dawnward's order: a list of { n, TI, TX, IC,
-- AC } in Total RP 3's slot shape (RegisterMisc.lua applyPeekSlot). Copies;
-- nil when there are none.
function Glance.Published(char)
	local out = {}
	for n = 1, Glance.SLOTS do
		local entry = Glance.CleanEntry(char and char.glance and char.glance[n])
		if entry then
			out[#out + 1] = { n = n, TI = entry.title, TX = entry.text, IC = entry.icon or Glance.DEFAULT_ICON,
				AC = entry.active }
		end
	end
	return out
end
