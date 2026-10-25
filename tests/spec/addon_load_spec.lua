-- L2: loads the whole addon in TOC order against the WoW mock and drives it
-- through the same entry points the client uses (events and /dawnward).
local Loader = require("support.loader")
local Mock = require("support.wow_mock")
local Fake = require("fakes.trp3_341")

local TOC_PATH = "DawnwardChronicles/DawnwardChronicles.toc"

local function readToc()
	local f = assert(io.open(TOC_PATH, "rb"))
	local text = f:read("*a")
	f:close()
	local files, meta = {}, {}
	for line in text:gmatch("[^\r\n]+") do
		local key, value = line:match("^## ([%w%-]+): (.+)$")
		if key then
			meta[key] = value
		elseif not line:match("^#") and line:match("%S") then
			files[#files + 1] = line:gsub("\\", "/")
		end
	end
	return files, meta
end

local function boot(opts)
	local files = readToc()
	local mock = Mock.new(opts)
	local env = Loader.NewEnv(mock.env)
	local ns = Loader.Load(files, env, {})
	return mock, env, ns
end

local function login(mock)
	mock.Fire("ADDON_LOADED", "SomeOtherAddon")
	mock.Fire("ADDON_LOADED", "DawnwardChronicles")
	mock.Fire("PLAYER_LOGIN")
end

return function(t, expect)
	t:describe("TOC", function()
		t:it("lists core modules in the same order as the test loader", function()
			local files = readToc()
			local core = {}
			for _, path in ipairs(files) do
				if path:match("^Core/") then
					core[#core + 1] = path
				end
			end
			expect.deepEqual(core, Loader.CORE)
		end)

		t:it("declares the expected metadata", function()
			local _, meta = readToc()
			expect.equal(meta.Version, "0.2.0")
			expect.equal(meta.SavedVariables, "DawnwardChroniclesDB, DawnwardChroniclesSimDB")
			expect.equal(meta.OptionalDeps, "totalRP3")
		end)
	end)

	t:describe("addon load (L2, mocked client)", function()
		t:it("loads every file and answers /dawnward after login", function()
			local mock, env = boot()
			expect.truthy(mock.Slash("status"):find("Still loading"))
			login(mock)
			local output = mock.Slash("set name Aelin")
			expect.truthy(output:find("Set name"), output)
			local db = env.DawnwardChroniclesDB
			expect.equal(db.schemaVersion, 2)
			expect.equal(db.characters["Testchar-TestRealm"].fields.name.value, "Aelin")
			expect.truthy(mock.Slash("status"):find("WoW Classic Era"))
		end)

		t:it("escapes pipes in chat output", function()
			local mock = boot()
			login(mock)
			mock.Slash("history add a||b")
			for _, line in ipairs(mock.chat) do
				local stripped = line:gsub("^|cffe6c35cDawnward:|r ", "")
				expect.falsy(stripped:gsub("||", ""):find("|"), "unescaped pipe in: " .. line)
			end
		end)

		t:it("keeps newer saved data untouched and refuses writes", function()
			local saved = { schemaVersion = 99, characters = { ["Testchar-TestRealm"] = { future = true } } }
			local mock, env = boot({ savedVariables = { DawnwardChroniclesDB = saved } })
			login(mock)
			expect.truthy(env.DawnwardChroniclesDB == saved, "the saved table must not be replaced")
			expect.truthy(table.concat(mock.chat, "\n"):find("left untouched"))
			expect.truthy(mock.Slash("set name X"):find("read%-only"))
			expect.deepEqual(saved, { schemaVersion = 99, characters = { ["Testchar-TestRealm"] = { future = true } } })
		end)

		t:it("keeps simulation data in its own saved variable", function()
			local mock, env = boot()
			login(mock)
			mock.Slash("set name Real")
			mock.Slash("sim on")
			mock.Slash("set name Simulated")
			expect.equal(env.DawnwardChroniclesDB.characters["Testchar-TestRealm"].fields.name.value, "Real")
			expect.equal(env.DawnwardChroniclesSimDB.characters["Testchar-TestRealm"].fields.name.value, "Simulated")
		end)

		t:it("exports to the copy window and imports through it", function()
			local mock, env, ns = boot()
			login(mock)
			mock.Slash("set name Exported")
			mock.Slash("export backup")
			local frame = ns.CopyBox.GetFrame()
			expect.truthy(frame and frame:IsShown())
			local text = frame.editBox:GetText()
			expect.equal(text:sub(1, 8), "!DWC1!B!")

			mock.Slash("set name Changed")
			mock.Slash("import")
			frame.editBox:SetText(text)
			frame.primary:GetScript("OnClick")(frame.primary)
			expect.truthy(frame.status:GetText():find("Ready to import"))
			expect.truthy(frame.secondary:IsShown())
			frame.secondary:GetScript("OnClick")(frame.secondary)
			expect.falsy(frame:IsShown())
			expect.equal(env.DawnwardChroniclesDB.characters["Testchar-TestRealm"].fields.name.value, "Exported")
		end)

		t:it("drops a checked import when the pasted text is edited", function()
			local mock, _, ns = boot()
			login(mock)
			mock.Slash("set name A")
			mock.Slash("export backup")
			local frame = ns.CopyBox.GetFrame()
			local text = frame.editBox:GetText()
			mock.Slash("import")
			frame.editBox:SetText(text)
			frame.primary:GetScript("OnClick")(frame.primary)
			frame.editBox:GetScript("OnTextChanged")(frame.editBox, true)
			expect.falsy(frame.secondary:IsShown())
			expect.truthy(mock.Slash("import confirm"):find("Nothing to import"))
		end)

		t:it("reports TRP3 read-only status without touching it", function()
			local fake = Fake.new({ profileName = "Adventuring" })
			local mock = boot({ extra = { AddOn_TotalRP3 = fake.env.AddOn_TotalRP3 } })
			mock.env.C_AddOns.IsAddOnLoaded = fake.env.C_AddOns.IsAddOnLoaded
			local meta = mock.env.C_AddOns.GetAddOnMetadata
			mock.env.C_AddOns.GetAddOnMetadata = function(name, field)
				return fake.env.C_AddOns.GetAddOnMetadata(name, field) or meta(name, field)
			end
			login(mock)
			local before = fake.snapshot()
			local output = mock.Slash("trp3")
			expect.truthy(output:find("3.4.1"), output)
			expect.truthy(output:find("Adventuring"), output)
			expect.equal(#fake.setterCalls, 0)
			expect.deepEqual(fake.snapshot(), before)
		end)

		t:it("labels a Forever interface as provisional", function()
			local mock = boot({ interface = 16001, project = 2 })
			login(mock)
			expect.truthy(mock.Slash("status"):find("provisional"))
		end)
	end)
end
