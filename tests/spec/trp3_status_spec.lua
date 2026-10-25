-- L2: TRP3 status adapter against a fake of the audited 3.4.1 public API.
local Loader = require("support.loader")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local ns = Loader.Load({
		"Integrations/TRP3/VersionProfiles.lua",
		"Integrations/TRP3/Status.lua",
	})
	local Status = ns.TRP3Status

	t:describe("TRP3 status (L2, fake 3.4.1)", function()
		t:it("reads version and active profile through the public API", function()
			local fake = Fake.new({ profileName = "Adventuring" })
			local s = Status.Read(fake.env)
			expect.truthy(s.installed)
			expect.truthy(s.loaded)
			expect.equal(s.version, "3.4.1")
			expect.truthy(s.versionProfile.audited)
			expect.equal(s.versionProfile.verified, nil, "3.4.1 is not verified in game yet")
			expect.equal(s.profile.name, "Adventuring")
			expect.equal(s.profile.isDefault, false)
			expect.equal(s.profile.roleplayName, "Aelin Brightwater")
			expect.equal(s.error, nil)
		end)

		t:it("never calls a setter and never changes TRP3 data", function()
			local fake = Fake.new()
			local before = fake.snapshot()
			Status.Read(fake.env)
			Status.Read(fake.env)
			expect.equal(#fake.setterCalls, 0)
			expect.deepEqual(fake.snapshot(), before)
		end)

		t:it("returns no references to TRP3 tables", function()
			local fake = Fake.new()
			local s = Status.Read(fake.env)
			local function scan(v, seen)
				if type(v) ~= "table" or seen[v] then return end
				seen[v] = true
				expect.falsy(v == fake.profile or v == fake.profile.player
					or v == fake.profile.player.characteristics, "leaked a TRP3 table")
				for _, x in pairs(v) do scan(x, seen) end
			end
			scan(s, {})
		end)

		t:it("flags the default profile", function()
			local s = Status.Read(Fake.new({ isDefault = true }).env)
			expect.truthy(s.profile.isDefault)
		end)

		t:it("handles TRP3 being absent or not loaded", function()
			local absent = Status.Read(Fake.new({ notInstalled = true }).env)
			expect.falsy(absent.installed)
			expect.falsy(absent.loaded)
			local unloaded = Status.Read(Fake.new({ notLoaded = true }).env)
			expect.truthy(unloaded.installed)
			expect.falsy(unloaded.loaded)
			expect.equal(unloaded.profile, nil)
			local empty = Status.Read({})
			expect.falsy(empty.installed)
		end)

		t:it("treats unknown versions as unaudited", function()
			local s = Status.Read(Fake.new({ version = "3.5.3" }).env)
			expect.falsy(s.versionProfile.known)
			expect.truthy(s.versionProfile.label:find("not audited"))
		end)

		t:it("degrades when the public API is missing or misbehaves", function()
			local noApi = Status.Read(Fake.new({ noPlayerApi = true }).env)
			expect.falsy(noApi.api.getCurrentUser)
			expect.equal(noApi.profile, nil)

			local throwing = Status.Read(Fake.new({ override = {
				GetProfileName = function() error("internal change") end,
				IsProfileDefault = function() return "yes" end, -- wrong type
			} }).env)
			expect.equal(throwing.profile.name, nil)
			expect.equal(throwing.profile.isDefault, false)
			expect.equal(throwing.error, nil)
		end)

		t:it("turns an unexpected failure into an error status, not a Lua error", function()
			local env = { C_AddOns = { GetAddOnMetadata = function() error("client API changed") end } }
			local s = Status.Read(env)
			expect.truthy(s.error:find("client API changed"))
		end)

		t:it("falls back to the legacy global addon functions", function()
			local env = {
				IsAddOnLoaded = function() return true end,
				GetAddOnMetadata = function() return "3.4.1" end,
			}
			local s = Status.Read(env)
			expect.truthy(s.loaded)
			expect.equal(s.version, "3.4.1")
		end)
	end)
end
