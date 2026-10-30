-- L1: the TRP3 sync ledger (DawnwardChroniclesTRP3DB).
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.WithTRP3()
	local Ledger, Util = ns.TRP3Ledger, ns.Util

	t:describe("TRP3 ledger", function()
		t:it("starts empty and round-trips through normalisation", function()
			local l = Ledger.New()
			l.optIn["A-R"] = { about = true, traits = false, profileId = "0123456789", at = 5 }
			local p = Ledger.Profile(l, "0123456789")
			p.about = { block = "\n\nBLOCK", template = 1, at = 6 }
			p.traits = { owned = { courage = { LT = "Cautious", RT = "Bold", V2 = 7 } }, at = 6 }
			p.conflicts.about = "edited in TRP3"
			assert(Ledger.AddBackup(l, "0123456789", "about", { v = 1, TE = 1, T1 = { TX = "x" } }, { reason = "r" }, 7))
			Ledger.Log(l, 8, "hello")
			local again = assert(Ledger.Normalize(Util.DeepCopy(l)))
			-- A v0.7 opt-in (booleans only) gains its policy on load; nothing else changes.
			l.optIn["A-R"].policy = { about = "dawnward" }
			expect.deepEqual(again, l)
			expect.deepEqual(assert(Ledger.Normalize(Util.DeepCopy(again))), again, "idempotent")
		end)

		t:it("never stores default profile IDs", function()
			local l = Ledger.New()
			expect.equal(Ledger.Profile(l, "1234*"), nil)
			expect.falsy(Ledger.AddBackup(l, "1234*", "about", {}))
			local n = assert(Ledger.Normalize({ optIn = { X = { profileId = "9*", about = true } },
				profiles = { ["9*"] = {} } }))
			expect.deepEqual(n.optIn, {})
			expect.deepEqual(n.profiles, {})
		end)

		t:it("refuses to back up sections that are too large, so they are never written", function()
			local l = Ledger.New()
			local big = { T1 = { TX = string.rep("x", Ledger.LIMITS.backupBytes) } }
			local backup, err = Ledger.AddBackup(l, "P1", "about", big)
			expect.falsy(backup)
			expect.truthy(err:find("too large"))
			expect.equal(#l.backups, 0)
		end)

		t:it("keeps the newest backups and decodes them exactly", function()
			local l = Ledger.New()
			for i = 1, Ledger.LIMITS.backups + 3 do
				Ledger.AddBackup(l, "P1", "about", { v = i, T1 = { TX = "text " .. i } }, nil, i)
			end
			expect.equal(#l.backups, Ledger.LIMITS.backups)
			local latest = Ledger.LatestBackup(l, "P1", "about")
			expect.deepEqual(Ledger.BackupData(latest), { v = Ledger.LIMITS.backups + 3,
				T1 = { TX = "text " .. (Ledger.LIMITS.backups + 3) } })
			expect.equal(Ledger.LatestBackup(l, "P1", "characteristics"), nil)
			expect.truthy(Ledger.FindBackup(l, latest.id))
		end)

		t:it("drops damaged parts and refuses a ledger from a newer build", function()
			local n = assert(Ledger.Normalize({ schemaVersion = 1,
				profiles = { P = { about = { block = "", template = 1 }, traits = { owned = {
					courage = { LT = "a", RT = "b", V2 = 30 }, ["Bad Axis"] = { LT = "a", RT = "b", V2 = 1 } } } } },
				backups = { { id = 1, profileId = "P", section = "about", data = "not serialized" },
					{ id = 2, profileId = "P", section = "bank", data = "{}" } },
				log = { { at = 1, text = "ok" }, "junk" } }))
			expect.equal(n.profiles.P.about, nil)
			expect.deepEqual(n.profiles.P.traits.owned, {})
			expect.equal(#n.backups, 0)
			expect.equal(#n.log, 1)
			local newer, err = Ledger.Normalize({ schemaVersion = 99 })
			expect.falsy(newer)
			expect.truthy(err:find("newer"))
		end)
	end)
end
