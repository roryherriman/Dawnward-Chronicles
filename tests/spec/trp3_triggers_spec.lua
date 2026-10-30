-- L2: when automatic Total RP 3 sync is requested, and how bounded it is,
-- through the whole addon under the WoW mock and the 3.4.1 fake (mocked
-- client; not in-game evidence).
local Boot = require("support.boot")
local Fake = require("fakes.trp3_341")

return function(t, expect)
	local function start(fakeOpts)
		local fake = Fake.new(fakeOpts or {})
		local extra = {}
		for k, v in pairs(fake.env) do
			if k ~= "C_AddOns" then extra[k] = v end
		end
		local mock, env, ns = Boot.Load({ extra = extra })
		mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
		local meta = mock.env.C_AddOns.GetAddOnMetadata
		mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
			return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
		end
		Boot.Login(mock)
		return mock, env, ns, fake
	end

	local function managedAge(mock)
		mock.Slash("set age 31")
		mock.Slash("vis age public")
		mock.Slash("trp3 field age dawnward confirm")
	end

	t:describe("TRP3 sync triggers (L2)", function()
		t:it("a field policy needs confirm through the command, then one debounced run writes", function()
			local mock, env, _, fake = start()
			mock.Slash("set age 31")
			mock.Slash("vis age public")
			expect.equal(#mock.timers, 0, "nothing managed: no run is even scheduled")
			expect.truthy(mock.Slash("trp3 field age dawnward"):find("Type: /dawnward trp3 field age dawnward confirm",
				1, true))
			expect.equal(env.DawnwardChroniclesTRP3DB.optIn["Testchar-TestRealm"], nil)
			expect.truthy(mock.Slash("trp3 field age dawnward confirm"):find("sync is ON", 1, true))
			expect.equal(#mock.timers, 1)
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.AG, "31")
			expect.truthy(mock.Slash("trp3 fields"):find("Age: Managed by Dawnward", 1, true))
		end)

		t:it("Dawnward's own write does not request another run, and later commands with nothing new write nothing",
			function()
			local mock, _, _, fake = start()
			managedAge(mock)
			mock.RunTimers()
			expect.equal(#mock.timers, 0, "TRP3's update event for Dawnward's own write is ignored")
			local v = fake.profile.player.characteristics.v
			mock.Slash("status")
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.v, v)
		end)

		t:it("editing a mapped public field, its visibility or the TRP3 style requests a run (window path too)",
			function()
			local _, _, ns = start()
			local requests = 0
			ns.ctx.trp3RequestSync = function() requests = requests + 1 end
			local A, ctx = ns.Actions, ns.ctx
			local noteId
			local calls = {
				function() return A.SetField(ctx, "race", "Elf") end,
				function() return A.SetFieldVisibility(ctx, "race", "public") end,
				function() return A.AddFact(ctx, "origin", "Born in Stormwind", "public") end,
				function() return A.SetFactVisibility(ctx, 1, "private") end,
				function() return A.SetPersonality(ctx, "courage", 14) end,
				function() return A.SetPersonalityVisibility(ctx, "courage", "public") end,
				function()
					local entry, message = A.AddNote(ctx, "A day", "Text", "private")
					noteId = entry and entry.id
					return entry, message
				end,
				function() return A.SetEntryVisibility(ctx, noteId, "public") end,
				function() return A.SetStoryPref(ctx, "trp3Style", "arcane") end,
			}
			for i, call in ipairs(calls) do
				local before = requests
				local ok, message = call()
				expect.truthy(ok, "call " .. i .. ": " .. tostring(message))
				expect.equal(requests, before + 1, "call " .. i .. " requested a run")
			end
		end)

		t:it("approvals of story entries, defining moments, changes and decisions go through the same path", function()
			-- Structural check: these window actions are wrapped by withCharacter,
			-- which requests a sync after every successful change.
			local source = assert(io.open("DawnwardChronicles/Core/Actions.lua")):read("*a")
			for _, name in ipairs({ "ApproveEntry", "SetEntryImportant", "ApplyChange", "ReverseChange", "Decide",
				"SetEntryVisibility", "CompleteSetup" }) do
				local body = source:match("function Actions%." .. name .. "%(.-\nend")
				expect.truthy(body and body:find("withCharacter", 1, true), name .. " uses withCharacter")
			end
		end)

		t:it("retries a waiting run a bounded number of times, says so once, and a new request starts afresh",
			function()
			local mock, _, ns, fake = start()
			managedAge(mock)
			fake.openEditor("characteristics")
			local runs = 0
			while #mock.timers > 0 and runs < 100 do
				mock.chat = {}
				mock.RunTimers()
				runs = runs + 1
			end
			expect.equal(runs, 1 + ns.TRP3Bridge.MAX_RETRIES, "first run plus the bounded retries")
			expect.equal(fake.profile.player.characteristics.AG, nil)
			expect.truthy(table.concat(mock.chat, "\n"):find("still waiting", 1, true))
			mock.Slash("status")
			expect.equal(#mock.timers, 1, "a new change schedules a fresh run")
			mock.chat = {}
			mock.RunTimers()
			expect.falsy(table.concat(mock.chat, "\n"):find("still waiting", 1, true), "not repeated")
			fake.cancelEditor("characteristics")
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.AG, "31")
		end)

		t:it("combat ending releases a waiting run at once, and a stale retry timer does nothing", function()
			local mock, _, _, fake = start()
			managedAge(mock)
			mock.inCombat = true
			mock.RunTimers()
			expect.equal(#mock.timers, 1, "retry scheduled")
			local stale = mock.timers
			mock.timers = {}
			mock.inCombat = false
			mock.Fire("PLAYER_REGEN_ENABLED")
			expect.equal(#mock.timers, 1, "combat end requested a run")
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.AG, "31")
			local events = #fake.events
			for _, timer in ipairs(stale) do timer.fn() end
			expect.equal(#fake.events, events, "the old retry timer is ignored")
			mock.Fire("PLAYER_REGEN_ENABLED")
			expect.equal(#mock.timers, 0, "combat end does nothing when no run is waiting")
		end)

		t:it("a TRP3 profile switch or an editor save is a hint that requests a run", function()
			local mock, _, _, fake = start()
			managedAge(mock)
			mock.RunTimers()
			fake.openEditor("characteristics")
			fake.saveEditor("characteristics")
			expect.equal(#mock.timers, 1, "TRP3's save requested a run")
			mock.RunTimers()
			fake.switchProfile("1700000099ZZZZZ", "Other", { about = { v = 1, TE = 1, T1 = { TX = "Other" } },
				characteristics = { v = 1, PS = {} }, character = { v = 1 } })
			expect.equal(#mock.timers, 1)
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.AG, nil, "never written to another profile")
		end)

		t:it("rollback through the command previews the risk and never runs by itself", function()
			local mock, _, _, fake = start()
			managedAge(mock)
			mock.RunTimers()
			mock.Slash("vis age secret")
			mock.RunTimers()
			expect.equal(fake.profile.player.characteristics.AG, nil)
			local out = mock.Slash("trp3 rollback 2")
			expect.truthy(out:find("Age: 31", 1, true), out)
			expect.truthy(out:find("no longer Public", 1, true))
			expect.equal(fake.profile.player.characteristics.AG, nil, "a preview restores nothing")
			mock.Slash("trp3 rollback 2 confirm")
			expect.equal(fake.profile.player.characteristics.AG, nil, "the safe default keeps it hidden")
			mock.Slash("trp3 rollback 2 exact confirm")
			expect.equal(fake.profile.player.characteristics.AG, "31", "only the explicit exact restore brings it back")
		end)

		t:it("import through the command is explicit", function()
			local mock, _, ns = start({ characteristics = { v = 3, FN = "Aelin", RA = "Half-elf", PS = {} } })
			expect.truthy(mock.Slash("trp3 import race"):find("confirm", 1, true))
			expect.equal(ns.store.real.characters["Testchar-TestRealm"], nil)
			expect.truthy(mock.Slash("trp3 import race confirm"):find("Imported", 1, true))
			local field = ns.store.real.characters["Testchar-TestRealm"].fields.race
			expect.deepEqual(field, { value = "Half-elf", visibility = "private" })
		end)
	end)
end
