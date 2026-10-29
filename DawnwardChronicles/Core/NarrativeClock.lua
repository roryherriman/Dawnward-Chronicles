-- The narrative clock: gameplay time per character, for story pacing.
--
-- Why not the game's own clocks (checked against the Classic Era 1.15.9
-- UI source, docs/ARCHITECTURE.md "Gameplay time"):
--   time()          the computer's wall clock: runs while offline and can be
--                   changed by the player
--   GetGameTime()   the realm's time of day (hours, minutes); Blizzard's own
--                   clock shows it as "server time". It runs at real speed
--                   and is not per character: there is no faster in-game day
--   RequestTimePlayed / TIME_PLAYED_MSG
--                   the server's /played total, but every chat frame prints
--                   it, so asking for it would spam chat
--   GetTime()       seconds since the computer started; only differences
--                   within one session mean anything
-- So Dawnward keeps its own clock: seconds of play, counted from GetTime()
-- differences while this character is logged in and not AFK, added up and
-- saved with the character. Offline time never counts.
--
-- A narrative day is a fixed amount of play (the "pace" story setting).
-- Place returns, story cooldowns and the expiry of waiting moments are
-- measured on this clock. Dates shown to the player stay real dates.
--
-- Saved (additive, schema stays 5):
--   char.story.clock = { v = 1, played = seconds of play }
-- Not saved: the session (when the clock was last read, AFK pause).
--
-- Pure: the platform passes the session and its GetTime() reading.
local _, ns = ...

local NarrativeClock = {}
ns.NarrativeClock = NarrativeClock

NarrativeClock.VERSION = 1
-- Seconds of play per narrative day, by pace.
NarrativeClock.PACES = { brisk = 3600, standard = 7200, slow = 14400 }
NarrativeClock.PACE_LABELS = { brisk = "Brisk", standard = "Standard", slow = "Slow" }
NarrativeClock.DEFAULT_PACE = "standard"
-- The platform reads the clock at least once a minute while playing. A
-- longer gap between two readings (the computer slept, the game froze)
-- counts as this much at most, so a stall never becomes hours of play.
NarrativeClock.MAX_STEP = 300
NarrativeClock.MAX = 2 ^ 40

--- A cleaned clock record. Anything invalid (negative, fractional beyond a
-- second, not a number, NaN, absurdly large) becomes a fresh clock at 0.
function NarrativeClock.Clean(raw)
	local played = type(raw) == "table" and raw.played or nil
	if type(played) ~= "number" or played ~= played or played < 0 or played > NarrativeClock.MAX then
		played = 0
	end
	return { v = NarrativeClock.VERSION, played = math.floor(played) }
end

--- Seconds of play in one narrative day for this character's pace.
function NarrativeClock.DayLength(char)
	local pace = char and char.story and char.story.prefs and char.story.prefs.pace
	return NarrativeClock.PACES[pace] or NarrativeClock.PACES[NarrativeClock.DEFAULT_PACE]
end

local function record(char)
	local story = char.story
	if type(story.clock) ~= "table" then
		story.clock = NarrativeClock.Clean(nil)
	end
	return story.clock
end

--- Seconds of play saved for this character (no session time added).
function NarrativeClock.Peek(char)
	return record(char).played
end

--- A new session: { anchors = { [char] = last reading }, paused = bool }.
function NarrativeClock.NewSession()
	return { anchors = setmetatable({}, { __mode = "k" }), paused = false }
end

--- Adds the play since the last reading to the character's clock and
-- returns the total. session and mono (a GetTime() reading) may be nil,
-- then nothing is added. The first reading for a character only starts
-- counting. Time while paused (AFK) is skipped.
function NarrativeClock.Advance(char, session, mono)
	local clock = record(char)
	if not session or type(mono) ~= "number" or mono ~= mono then
		return clock.played
	end
	local last = session.anchors[char]
	if last and not session.paused then
		local delta = mono - last
		if delta > 0 then
			-- A reading going backwards (or a huge gap) is never trusted as play.
			delta = math.min(math.floor(delta), NarrativeClock.MAX_STEP)
			clock.played = math.min(clock.played + delta, NarrativeClock.MAX)
		end
	end
	session.anchors[char] = mono
	return clock.played
end

--- Stops counting (AFK). The play so far is kept.
function NarrativeClock.Pause(char, session, mono)
	if char then NarrativeClock.Advance(char, session, mono) end
	if session then session.paused = true end
end

--- Starts counting again from this reading.
function NarrativeClock.Resume(char, session, mono)
	if not session then return end
	session.paused = false
	if char and type(mono) == "number" then
		session.anchors[char] = mono
	end
end

--- The narrative day for an amount of play (day 1 starts at 0).
function NarrativeClock.Day(char, played)
	return math.floor((played or NarrativeClock.Peek(char)) / NarrativeClock.DayLength(char)) + 1
end

--- Seconds of play now, for a context: ctx.narrative is the session and
-- ctx.monotonic() reads GetTime(). Without them, the saved total.
function NarrativeClock.Read(char, ctx)
	local mono = ctx and ctx.monotonic and ctx.monotonic() or nil
	return NarrativeClock.Advance(char, ctx and ctx.narrative, mono)
end

--- Like Read, but changes nothing: the saved total plus the session's
-- play since the last reading (for read-only diagnostics).
function NarrativeClock.Current(char, ctx)
	local played = NarrativeClock.Peek(char)
	local session = ctx and ctx.narrative
	local mono = ctx and ctx.monotonic and ctx.monotonic() or nil
	local last = session and session.anchors[char]
	if last and not session.paused and type(mono) == "number" and mono > last then
		played = played + math.min(math.floor(mono - last), NarrativeClock.MAX_STEP)
	end
	return played
end
