local Loader = require("support.loader")

return function(t, expect)
	local function setup(opts)
		opts = opts or {}
		local ns = Loader.Core()
		local real = opts.real or ns.Schema.NewDatabase()
		local sim = opts.sim or ns.Schema.NewDatabase()
		local store = ns.Store.new(real, sim, opts.storeOpts)
		local clock = 1000
		local ctx = {
			store = store,
			characterKey = "Aelin-TestRealm",
			now = function() clock = clock + 1; return clock end,
			version = "0.1.0",
			lines = {},
			exports = {},
			importShown = 0,
		}
		ctx.print = function(line) ctx.lines[#ctx.lines + 1] = line end
		ctx.ui = {
			ShowExport = function(title, text) ctx.exports[#ctx.exports + 1] = { title = title, text = text } end,
			ShowImport = function() ctx.importShown = ctx.importShown + 1 end,
		}
		local function run(msg)
			ctx.lines = {}
			ns.Commands.Execute(ctx, msg)
			return table.concat(ctx.lines, "\n")
		end
		return ns, ctx, run, real, sim
	end

	t:describe("profile commands", function()
		t:it("creates a profile on first set, with no visibility to choose", function()
			local _, _, run, real = setup()
			local output = run("set name Aelin Brightwater")
			expect.equal(output, "Set name.")
			expect.equal(real.characters["Aelin-TestRealm"].fields.name.value, "Aelin Brightwater")
		end)

		t:it("shows the published profile: everything for a v0.10 character, the old Public part before", function()
			local ns, ctx, run = setup()
			run("set name Aelin")
			run("set summary A quiet past")
			local char = ctx.store:GetCharacter(ctx.characterKey)
			ns.Character.SetFieldVisibility(char, "name", "public", 1)
			local output = run("show public")
			expect.truthy(output:find("Aelin"))
			expect.falsy(output:find("quiet past"), "an older character: only what it marked Public")
			expect.falsy(output:find("%[public%]") or output:find("%[private%]"), "no visibility tags")
			ns.Publication.Adopt(char, 2)
			output = run("show profile")
			expect.truthy(output:find("Aelin") and output:find("quiet past"))
			expect.truthy(run("show"):find("quiet past"))
		end)

		t:it("rejects unknown fields without changing anything", function()
			local _, _, run = setup()
			expect.truthy(run("set eyecolour green"):find("Not changed"))
		end)

		t:it("retired visibility commands say so in one line and change nothing", function()
			local ns, _, run, real = setup()
			run("set name A")
			run("family add mother Ilsa")
			run("history add Took the oath")
			run("fact add belief Mercy")
			run("personality set courage 14")
			run("journal add A day")
			local before = ns.Util.DeepCopy(real.characters["Aelin-TestRealm"])
			for _, cmd in ipairs({ "vis name public", "vis name secret", "family vis 1 secret", "history vis 1 public",
				"fact vis 1 public", "personality vis courage public", "journal vis 1 public", "vis nonsense x" }) do
				local output = run(cmd)
				expect.equal(output, ns.Commands.RETIRED_VISIBILITY, cmd)
			end
			expect.deepEqual(real.characters["Aelin-TestRealm"], before, "nothing changed")
		end)

		t:it("a retired visibility command never creates a character", function()
			local ns, _, run, real = setup()
			expect.equal(run("vis name public"), ns.Commands.RETIRED_VISIBILITY)
			expect.equal(run("fact vis 1 public"), ns.Commands.RETIRED_VISIBILITY)
			expect.equal(real.characters["Aelin-TestRealm"], nil)
		end)

		t:it("requires confirm to clear a field", function()
			local _, _, run, real = setup()
			run("set title Knight")
			expect.truthy(run("clear title"):find("confirm"))
			expect.truthy(real.characters["Aelin-TestRealm"].fields.title)
			run("clear title confirm")
			expect.equal(real.characters["Aelin-TestRealm"].fields.title, nil)
		end)

		t:it("prints help and handles unknown commands", function()
			local _, _, run = setup()
			expect.truthy(run("help all"):find("family add"))
			expect.truthy(run("dance"):find("Unknown command"))
		end)
	end)

	t:describe("family and history commands", function()
		t:it("adds, edits and removes family with confirmation", function()
			local _, _, run, real = setup()
			expect.truthy(run("family add mother Ilsa Brightwater"):find("#1"))
			run("family set 1 status deceased")
			local member = real.characters["Aelin-TestRealm"].family[1]
			expect.equal(member.name, "Ilsa Brightwater")
			expect.equal(member.status, "deceased")
			expect.falsy(run("family list"):find("%[private%]"), "no visibility tags")
			expect.truthy(run("family remove 1"):find("confirm"))
			expect.equal(#real.characters["Aelin-TestRealm"].family, 1)
			run("family remove 1 confirm")
			expect.equal(#real.characters["Aelin-TestRealm"].family, 0)
		end)

		t:it("records history entries", function()
			local _, _, run, real = setup()
			run("history add Took the oath at the chapel")
			run("history set 1 when Year 12")
			expect.truthy(run("history list"):find("Year 12: Took the oath"))
			expect.equal(#real.characters["Aelin-TestRealm"].history, 1)
		end)

		t:it("reports bad IDs and invalid status", function()
			local _, _, run = setup()
			expect.truthy(run("family set x name Bob"):find("Usage"))
			run("family add brother Tam")
			expect.truthy(run("family set 1 status undead"):find("Not changed"))
			expect.truthy(run("family set 99 name Bob"):find("Not changed"))
		end)
	end)

	t:describe("export and import", function()
		t:it("exports a backup with everything to the window and imports it into another character", function()
			local ns, ctx, run, real = setup()
			run("set name Aelin")
			run("set motivation A hidden vow")
			ns.Character.SetFieldVisibility(ctx.store:GetCharacter(ctx.characterKey), "motivation", "secret", 1)
			run("export backup")
			expect.equal(#ctx.exports, 1)
			local text = ctx.exports[1].text
			expect.truthy(text:find("hidden vow", 1, true), "a backup holds everything")
			expect.truthy(ctx.exports[1].title:find("everything"))

			ctx.characterKey = "Alt-TestRealm"
			expect.truthy(ns.Commands.StageImport(ctx, text))
			run("import confirm")
			local alt = real.characters["Alt-TestRealm"]
			expect.equal(alt.fields.name.value, "Aelin")
			expect.equal(alt.fields.motivation.value, "A hidden vow")
			expect.equal(real.characters["Aelin-TestRealm"].fields.motivation.value, "A hidden vow")
		end)

		t:it("stages, confirms and undoes an import", function()
			local ns, ctx, run, real = setup()
			run("set name Original")
			run("set motivation Secret thing")
			ns.Character.SetFieldVisibility(ctx.store:GetCharacter(ctx.characterKey), "motivation", "secret", 1)
			local backupChar = ns.Schema.NewCharacter(1)
			ns.Character.SetField(backupChar, "name", "Imported")
			-- A backup as versions before 0.10 made it by default: no secrets.
			local text = assert(ns.Transfer.Export(backupChar, "backup", { includeSecrets = false }))

			expect.truthy(run("import"):len() >= 0)
			expect.equal(ctx.importShown, 1)
			expect.truthy(run("import confirm"):find("Nothing to import"))

			local ok = ns.Commands.StageImport(ctx, text)
			expect.truthy(ok)
			expect.equal(real.characters["Aelin-TestRealm"].fields.name.value, "Original", "staging changes nothing")

			local output = run("import confirm")
			expect.truthy(output:find("Kept 1 existing record"))
			local char = real.characters["Aelin-TestRealm"]
			expect.equal(char.fields.name.value, "Imported")
			expect.equal(char.fields.motivation.value, "Secret thing")

			run("import undo")
			expect.equal(real.characters["Aelin-TestRealm"].fields.name.value, "Original")
		end)

		t:it("rejects share exports and damaged text on import", function()
			local ns, ctx, run = setup()
			run("set name A")
			run("export share")
			local shareText = ctx.exports[1].text
			expect.falsy(ns.Commands.StageImport(ctx, shareText))
			expect.falsy(ns.Commands.StageImport(ctx, "not an export"))
			expect.equal(ctx.pendingImport, nil)
		end)

		t:it("titles a backup as personal, and still accepts the older options without changing it", function()
			local _, ctx, run = setup()
			run("set name A")
			run("export backup secrets")
			run("export backup")
			expect.truthy(ctx.exports[1].title:find("keep it to yourself"))
			expect.equal(ctx.exports[1].title, ctx.exports[2].title)
			run("export share")
			expect.falsy(ctx.exports[3].title:find("Public") or ctx.exports[3].title:find("public"))
		end)
	end)

	t:describe("simulation mode", function()
		t:it("keeps simulation writes out of real data", function()
			local _, _, run, real, sim = setup()
			run("set name Real Name")
			run("sim on")
			run("set name Test Name")
			run("family add sister Test Sister")
			expect.equal(real.characters["Aelin-TestRealm"].fields.name.value, "Real Name")
			expect.equal(#real.characters["Aelin-TestRealm"].family, 0)
			expect.equal(sim.characters["Aelin-TestRealm"].fields.name.value, "Test Name")
			expect.truthy(run("show"):find("SIMULATION"))
			run("sim off")
			expect.truthy(run("show"):find("Real Name"))
		end)

		t:it("copies real data in and resets only with confirm", function()
			local _, _, run, real, sim = setup()
			run("set name Real")
			run("sim copy")
			expect.equal(sim.characters["Aelin-TestRealm"], nil)
			run("sim copy confirm")
			sim.characters["Aelin-TestRealm"].fields.name.value = "Changed in sim"
			expect.equal(real.characters["Aelin-TestRealm"].fields.name.value, "Real", "copy is independent")
			local simTable = sim
			run("sim reset")
			expect.truthy(sim.characters["Aelin-TestRealm"])
			run("sim reset confirm")
			expect.equal(sim.characters["Aelin-TestRealm"], nil)
			expect.truthy(sim == simTable, "the saved table is reset in place")
			expect.equal(real.characters["Aelin-TestRealm"].fields.name.value, "Real")
		end)
	end)

	t:describe("read-only data", function()
		t:it("refuses every write and says why", function()
			local _, _, run, real = setup({ storeOpts = { realReadOnly = "saved data comes from a newer version" } })
			for _, cmd in ipairs({ "set name A", "family add mother B", "history add C", "import confirm" }) do
				local output = run(cmd)
				expect.truthy(output:find("read%-only") or output:find("Nothing to import"), cmd .. " -> " .. output)
			end
			expect.equal(next(real.characters), nil)
			expect.truthy(run("status"):find("READ%-ONLY"))
		end)
	end)

	t:describe("v0.2 commands", function()
		t:it("bare /dawnward toggles the journal when a window exists, else shows status", function()
			local _, ctx, run = setup()
			expect.truthy(run(""):find("Dawnward Chronicles"), "status without a window")
			local toggles = 0
			ctx.ui.ToggleJournal = function() toggles = toggles + 1 end
			run("")
			run("   ")
			expect.equal(toggles, 2)
			expect.truthy(run("status"):find("Dawnward Chronicles"))
		end)

		t:it("adds, edits and deletes journal entries", function()
			local _, _, run, real = setup()
			expect.truthy(run("journal add Arrived in Goldshire"):find("#1"))
			run("journal edit 1 Arrived in Goldshire at dusk")
			local entry = real.characters["Aelin-TestRealm"].journal[1]
			expect.equal(entry.text, "Arrived in Goldshire at dusk")
			expect.truthy(run("journal list"):find("Goldshire"))
			expect.truthy(run("journal remove 1"):find("confirm"))
			expect.equal(#real.characters["Aelin-TestRealm"].journal, 1)
			run("journal remove 1 confirm")
			expect.equal(#real.characters["Aelin-TestRealm"].journal, 0)
		end)

		t:it("sets and lists themes", function()
			local _, _, run, real = setup()
			expect.truthy(run("theme"):find("Classic Dawnward"))
			run("theme silverhand")
			expect.equal(real.characters["Aelin-TestRealm"].theme, "silverhand")
			expect.truthy(run("theme paladin"):find("Unknown theme"))
		end)

		t:it("records simulated level-ups only in simulation mode, once", function()
			local _, ctx, run, real, sim = setup()
			ctx.zone = function() return "Elwynn Forest" end
			expect.truthy(run("sim levelup 5"):find("simulation mode"))
			run("sim on")
			expect.truthy(run("sim levelup 5"):find("Reached level 5 in Elwynn Forest"))
			expect.truthy(run("sim levelup 5"):find("duplicate"))
			expect.equal(#sim.characters["Aelin-TestRealm"].journal, 1)
			expect.equal(real.characters["Aelin-TestRealm"], nil)
		end)
	end)

	t:describe("status and trp3 output", function()
		t:it("reports TRP3 states without failing", function()
			local _, ctx, run = setup()
			expect.truthy(run("trp3"):find("unavailable"))
			ctx.trp3Status = function() return { installed = false, loaded = false } end
			expect.truthy(run("trp3"):find("not installed"))
			ctx.trp3Status = function()
				return { installed = true, loaded = true, version = "3.4.1",
					versionProfile = { label = "source audited, not yet tested in game" },
					api = { getCurrentUser = true }, profile = { name = "Main", isDefault = true } }
			end
			local output = run("trp3")
			expect.truthy(output:find("3.4.1"))
			expect.truthy(output:find("never write to it"))
			ctx.trp3Status = function() return { error = "boom" } end
			expect.truthy(run("trp3"):find("disabled"))
		end)
	end)

	t:describe("fact commands (v0.3 M1)", function()
		t:it("adds, lists and removes facts with confirm", function()
			local _, _, run, real = setup()
			local output = run("fact add belief Protect those who cannot protect themselves")
			expect.equal(output, "Added fact #1 (Belief).")
			run("fact add origin Born in Stormwind")
			output = run("fact list")
			expect.truthy(output:find("Facts %(2 of 200%)"), output)
			expect.truthy(output:find("Origin:.*Belief:"), "grouped in category order")
			expect.truthy(output:find("#1 Protect those who cannot protect themselves"))
			expect.falsy(output:find("%[private%]"), "no visibility tags")
			expect.truthy(run("fact remove 1"):find("confirm"))
			expect.equal(#real.characters["Aelin-TestRealm"].facts, 2)
			expect.truthy(run("fact remove 1 confirm"):find("Removed fact #1"))
			expect.equal(#real.characters["Aelin-TestRealm"].facts, 1)
		end)

		t:it("refuses bad input without creating an empty character", function()
			local _, _, run, real = setup()
			expect.truthy(run("fact add hobby Fishing"):find("unknown category"))
			expect.truthy(run("fact remove 1 confirm"):find("no fact #1"))
			expect.truthy(run("fact add belief"):find("Usage"))
			expect.truthy(run("fact remove x"):find("Usage"))
			expect.truthy(run("fact list"):find("No facts yet"))
			expect.equal(real.characters["Aelin-TestRealm"], nil)
		end)

		t:it("refuses writes to read-only data", function()
			local _, _, run, real = setup({ storeOpts = { realReadOnly = "newer data" } })
			expect.truthy(run("fact add belief X"):find("read%-only"))
			expect.equal(real.characters["Aelin-TestRealm"], nil)
		end)

		t:it("shows the Foundations line in status", function()
			local ns, ctx, run = setup()
			expect.truthy(run("status"):find("Foundations: 0 facts, 0 suggestions, biography stored: no"))
			run("fact add trait Stubborn")
			local char = ctx.store:GetCharacter(ctx.characterKey)
			ns.Sources.Capture(char, "paste", "A biography.", nil, 1)
			ns.Interpretations.Propose(char, { kind = "insight", category = "trait", statement = "Loyal",
				origin = "paste" }, 2)
			expect.truthy(run("status"):find("Foundations: 1 facts, 1 suggestions, biography stored: yes"))
		end)

		t:it("a backup always holds the stored biography; a share export only once it is published", function()
			local ns, ctx, run = setup()
			run("set name Aelin")
			local char = ctx.store:GetCharacter(ctx.characterKey)
			ns.Sources.Capture(char, "paste", "BIO-MARKER text", nil, 1)
			run("export backup")
			expect.truthy(ctx.exports[#ctx.exports].text:find("BIO-MARKER", 1, true))
			run("export backup biography secrets")
			expect.truthy(ctx.exports[#ctx.exports].text:find("BIO-MARKER", 1, true))
			run("export share biography")
			expect.falsy(ctx.exports[#ctx.exports].text:find("BIO-MARKER", 1, true), "older model, kept back")
			ns.Publication.Adopt(char, 2)
			run("export share")
			expect.truthy(ctx.exports[#ctx.exports].text:find("BIO-MARKER", 1, true), "v0.10: part of the profile")
		end)

		t:it("restoring a backup made before any story was stored keeps the current one", function()
			local ns, ctx, run = setup()
			run("set name Aelin")
			run("export backup")
			local text = ctx.exports[#ctx.exports].text
			local char = ctx.store:GetCharacter(ctx.characterKey)
			ns.Sources.Capture(char, "paste", "Stored after the backup", nil, 1)
			ns.Commands.StageImport(ctx, text)
			expect.truthy(table.concat(ctx.lines, " "):find("current one is kept"))
			run("import confirm")
			local restored = ctx.store:GetCharacter(ctx.characterKey)
			expect.truthy(restored ~= char)
			expect.equal(ns.Sources.Current(restored).text, "Stored after the backup")
		end)
	end)
end
