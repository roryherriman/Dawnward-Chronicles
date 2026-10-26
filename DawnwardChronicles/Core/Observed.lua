-- Compares observed game state with the character's last snapshot and
-- reports what changed. Pure: Platform/Observers reads the client and
-- passes plain tables in.
--
-- The very first comparison only records a baseline. Existing standings and
-- an existing guild are never reported as new events, so installing or
-- upgrading Dawnward cannot flood the story with old history.
local _, ns = ...

local Observed = {}
ns.Observed = Observed

--- factions: { { id, name, standing (1-8) }, ... } as listed by the client.
-- Returns a list of changes { factionId, factionName, standing, previous }
-- (tier changes only) and updates the snapshot. Factions missing from the
-- list (for example under a collapsed header) are left as they were.
function Observed.CompareStandings(char, factions)
	local observed = char.story.observed
	local changes = {}
	local first = not observed.baseline
	for _, f in ipairs(factions or {}) do
		if type(f.id) == "number" and type(f.standing) == "number" and f.standing >= 1 and f.standing <= 8 then
			local known = observed.standings[f.id]
			if known and known.standing ~= f.standing and not first then
				changes[#changes + 1] = { factionId = f.id, factionName = f.name, standing = f.standing,
					previous = known.standing }
			end
			observed.standings[f.id] = { standing = f.standing, name = f.name }
		end
	end
	observed.baseline = true
	return changes
end

--- guild: { name, rank } or nil (confirmed not in a guild). Callers pass
-- only conclusive readings. Returns a change { guildName, guildRank,
-- previousGuild } when the guild changed since the last reading; the very
-- first reading is a silent baseline. Rank changes alone update the snapshot.
function Observed.CompareGuild(char, guild)
	local observed = char.story.observed
	local before = observed.guild
	local now = guild and guild.name and { name = guild.name, rank = guild.rank } or nil
	observed.guild = now
	if not observed.guildSeen then
		observed.guildSeen = true
		return nil
	end
	local beforeName, nowName = before and before.name, now and now.name
	if beforeName == nowName then
		return nil
	end
	return { guildName = nowName, guildRank = now and now.rank, previousGuild = beforeName }
end
