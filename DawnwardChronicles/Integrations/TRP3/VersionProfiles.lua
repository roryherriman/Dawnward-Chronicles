-- What Dawnward knows about each Total RP 3 version (docs/TRP3_INTEGRATION.md).
--
-- A version is "audited" once its source has been read and documented, and
-- "verified" (with a level) only after testing in a real client. Unlisted
-- versions get read-only status and the manual copy-and-paste path.
local _, ns = ...

local VersionProfiles = {}
ns.TRP3VersionProfiles = VersionProfiles

VersionProfiles.KNOWN = {
	["3.4.1"] = {
		audited = true,
		verified = nil, -- set to "L3"/"L4" only after in-game testing
		tiers = { read = true, publicSetters = false, manualExport = false, ownedWrite = false },
	},
	-- 3.5.3 is a design target but has not been audited; it is deliberately absent.
}

function VersionProfiles.Get(version)
	local known = type(version) == "string" and VersionProfiles.KNOWN[version]
	if not known then
		return {
			known = false,
			audited = false,
			tiers = { read = true },
			label = "not audited - status only",
		}
	end
	local label
	if known.verified then
		label = "verified in game (" .. known.verified .. ")"
	else
		label = "source audited, not yet tested in game"
	end
	return {
		known = true,
		audited = known.audited,
		verified = known.verified,
		tiers = known.tiers,
		label = label,
	}
end
