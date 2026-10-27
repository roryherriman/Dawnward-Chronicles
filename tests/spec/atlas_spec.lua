-- L1/L2: the Zone Atlas (#48): evidence levels and the in-game verifier,
-- against a mocked client. Not in-game evidence.
local Loader = require("support.loader")
local Boot = require("support.boot")

return function(t, expect)
	t:describe("Zone Atlas data (#48)", function()
		t:it("names every mapped area and map, and keeps Forever unverified", function()
			local ns = Loader.Core()
			local data = ns.Places.Data("classic_era")
			for id in pairs(data.areas) do
				expect.truthy(ns.Atlas.EXPECTED.areas[id], "area " .. id .. " has an expected name")
			end
			for id in pairs(data.zones) do
				expect.truthy(ns.Atlas.EXPECTED.maps[id], "map " .. id .. " has an expected name")
			end
			for id in pairs(ns.Atlas.EXPECTED.areas) do
				expect.truthy(data.areas[id], "no name without a mapped area " .. id)
			end
			expect.equal(ns.Places.Data("forever"), nil, "no Forever place data")
			expect.equal(ns.Atlas.Level("forever", "areas", 87), "unverified")
		end)

		t:it("reports in-game confirmations apart from source checks", function()
			local ns = Loader.Core()
			expect.equal(ns.Atlas.Level("classic_era", "areas", 87), "in-game")
			expect.equal(ns.Atlas.Level("classic_era", "areas", 69), "source")
			expect.equal(ns.Atlas.Level("classic_era", "areas", 99999), "unverified")
			expect.equal(ns.Atlas.Level("classic_era", "maps", 1429), "in-game")
		end)

		t:it("compares the client's names: match, renamed (localised) and missing", function()
			local ns = Loader.Core()
			local probe = {
				areaName = function(id)
					if id == 87 then return "Villedoré" end
					if id == 2979 then return nil end
					return ns.Atlas.EXPECTED.areas[id]
				end,
				mapInfo = function(id) return { name = ns.Atlas.EXPECTED.maps[id], parentMapID = 1415 } end,
			}
			local v = ns.Atlas.Verify(probe, "classic_era")
			expect.equal(v.counts.renamed, 1)
			expect.equal(v.counts.missing, 1)
			expect.equal(v.counts.match, #v.rows - 2)
			local report = ns.Atlas.Report({ id = "classic_era", version = "1.15.9", build = "70576", interface = 11509 },
				nil, v)
			expect.truthy(report:find('renamed area 87 expected="Goldshire" got="Villedoré"', 1, true), report)
			expect.truthy(report:find('missing area 2979', 1, true))
		end)

		t:it("scans a bounded range and keeps only named IDs", function()
			local ns = Loader.Core()
			local probe = { areaName = function(id) return id % 2 == 0 and ("Area " .. id) or nil end }
			local found, from, to = ns.Atlas.Scan(probe, 1, 10)
			expect.equal(#found, 5)
			expect.equal(from, 1)
			expect.equal(to, 10)
			local _, _, last = ns.Atlas.Scan(probe, 1, 999999)
			expect.equal(last, ns.Atlas.SCAN_LIMIT)
		end)
	end)

	t:describe("/dawnward atlas (L2)", function()
		local function start(interface)
			local mock, env, ns = Boot.Start(interface and { interface = interface } or nil)
			env.C_Map = {
				GetBestMapForUnit = function() return 1429 end,
				GetAreaInfo = function(id) return ns.Atlas.EXPECTED.areas[id] end,
				GetMapInfo = function(id)
					return { name = ns.Atlas.EXPECTED.maps[id] or "Eastern Kingdoms", parentMapID = 1415, mapType = 3 }
				end,
			}
			mock.zone, mock.subzone = "Elwynn Forest", "Goldshire"
			return mock, env, ns
		end

		t:it("says where you are and how sure the place data is, without saving anything", function()
			local mock, env = start()
			local reply = mock.Slash("atlas")
			expect.truthy(reply:find("uiMap 1429 (Elwynn Forest, parent 1415)", 1, true), reply)
			expect.truthy(reply:find("area 87, settlement (in-game evidence)", 1, true), reply)
			expect.falsy(env.DawnwardChroniclesDB and env.DawnwardChroniclesDB.characters
				and next(env.DawnwardChroniclesDB.characters), "atlas never creates a record")
			mock.subzone = "Lion's Pride Inn"
			reply = mock.Slash("atlas")
			expect.truthy(reply:find("no verified area ID", 1, true), reply)
		end)

		t:it("verifies every expected ID and exports a report to copy", function()
			local mock, _, ns = start()
			local reply = mock.Slash("atlas verify")
			local total = 0
			for _ in pairs(ns.Atlas.EXPECTED.areas) do total = total + 1 end
			for _ in pairs(ns.Atlas.EXPECTED.maps) do total = total + 1 end
			expect.truthy(reply:find(string.format("%d match, 0 renamed, 0 missing (of %d)", total, total), 1, true), reply)
			mock.Slash("atlas export")
			local box = ns.CopyBox and ns.CopyBox.frame
			expect.truthy(box == nil or box:IsShown())
		end)

		t:it("on another client, says results are evidence only", function()
			local mock = start(16001)
			local reply = mock.Slash("atlas")
			expect.truthy(reply:find("evidence only, not a compatibility claim", 1, true), reply)
		end)
	end)
end
