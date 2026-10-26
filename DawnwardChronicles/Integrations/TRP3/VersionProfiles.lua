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
		-- experimentalWrite: the About and characteristics layouts, the save
		-- path, the version rule and the update event were audited from the
		-- 3.4.1 source (docs/TRP3_INTEGRATION.md). It only makes the
		-- experimental driver *available*: each character must still opt in,
		-- and every write re-checks the layout and the functions it uses.
		tiers = { read = true, publicSetters = false, manualExport = true, experimentalWrite = true },
	},
	-- Newer versions (3.5.x, main) change icon storage and have not had a
	-- full audit or in-game test; they are deliberately absent (read-only).
}

function VersionProfiles.Get(version)
	local known = type(version) == "string" and VersionProfiles.KNOWN[version]
	if not known then
		return {
			known = false,
			audited = false,
			tiers = { read = true, manualExport = true },
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
