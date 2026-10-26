-- L1: verbatim biography sources and display helpers.
local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Interpretations")
	local Schema, Sources = ns.Schema, ns.Sources

	t:describe("Sources.Capture", function()
		t:it("stores text byte for byte, including tags, newlines, escapes and UTF-8", function()
			local c = Schema.NewCharacter(1)
			local text = "{h1:c}Aelin{/h1}\r\n{p}Born in caf\195\169 country.{/p}\n\n|cffff0000red|r || \0 tail  "
			local version, status = Sources.Capture(c, "trp3", text, { profile = "Aelin", junk = "x" }, 50)
			expect.equal(status, "stored")
			expect.equal(version.text, text)
			expect.equal(version.hash, Schema.SourceHash(text))
			expect.deepEqual(version.meta, { profile = "Aelin" })
			expect.equal(Sources.Current(c), version)
			-- And it survives normalisation unchanged.
			local reloaded = Schema.NormalizeCharacter(ns.Util.DeepCopy(c))
			expect.equal(Sources.Current(reloaded).text, text)
		end)

		t:it("stores nothing for identical text", function()
			local c = Schema.NewCharacter(1)
			local first = Sources.Capture(c, "paste", "Same text", nil, 1)
			local again, status = Sources.Capture(c, "trp3", "Same text", nil, 2)
			expect.equal(status, "unchanged")
			expect.equal(again, first)
			expect.equal(#Sources.Versions(c), 1)
			expect.equal(c.sources.nextId, 2)
		end)

		t:it("keeps three versions, dropping the oldest earlier one, never the current", function()
			local c = Schema.NewCharacter(1)
			for i = 1, 4 do
				Sources.Capture(c, "paste", "version " .. i, nil, i)
			end
			local texts = {}
			for _, v in ipairs(Sources.Versions(c)) do texts[#texts + 1] = v.text end
			expect.deepEqual(texts, { "version 2", "version 3", "version 4" })
			expect.equal(Sources.Current(c).text, "version 4")
			-- Even if the current pointer is the oldest, rotation keeps it.
			c.sources.current = c.sources.versions[1].id
			Sources.Capture(c, "paste", "version 5", nil, 5)
			c.sources.current = c.sources.versions[1].id
			expect.equal(Schema.RotateSources(c.sources, 1), 2)
			expect.equal(#c.sources.versions, 1)
			expect.equal(Sources.Current(c).text, "version 3")
		end)

		t:it("refuses text over 16 KB without truncating or storing anything", function()
			local c = Schema.NewCharacter(1)
			Sources.Capture(c, "paste", "kept", nil, 1)
			local ok = Sources.Capture(c, "paste", string.rep("x", Schema.FOUNDATION.bioBytes), nil, 2)
			expect.truthy(ok, "exactly the limit is allowed")
			local version, err = Sources.Capture(c, "paste", string.rep("y", Schema.FOUNDATION.bioBytes + 1), nil, 3)
			expect.falsy(version)
			expect.truthy(err:find("never shortened"))
			expect.equal(#Sources.Current(c).text, Schema.FOUNDATION.bioBytes)
			expect.equal(#Sources.Versions(c), 2)
		end)

		t:it("refuses unknown kinds and empty text", function()
			local c = Schema.NewCharacter(1)
			expect.falsy(Sources.Capture(c, "email", "x"))
			expect.falsy(Sources.Capture(c, "paste", ""))
			expect.falsy(Sources.Capture(c, "paste", nil))
			expect.equal(Sources.Current(c), nil)
		end)
	end)

	t:describe("Sources.StripTags", function()
		local cases = {
			{ "{h1}Title{/h1}Body", "Title\nBody" },
			{ "{h2:c}Centred{/h2}", "Centred\n" },
			{ "{p}One{/p}{p:c}Two{/p}{p:r}Three{/p}", "One\nTwo\nThree\n" },
			{ "{col:ff0000}red {col:00ff00}green{/col} red{/col}", "red green red" },
			{ "{img:Interface\\Icons\\X:64:64}after", "after" },
			{ "see {icon:inv_misc_book_09:16} here", "see  here" },
			{ "{link*https://example.com*Example}", "Example" },
			{ "{link*https://example.com*{icon:spell_holy:12} Holy}", " Holy" },
			{ "{twitter*handle*My feed}", "My feed" },
			{ "{unknown:tag}kept", "kept" },
			{ "a { b", "a { b" },
			{ "a } b {", "a } b {" },
			{ "use {braces} literally", "use  literally" }, -- known limit: looks like a tag
		}
		for i, case in ipairs(cases) do
			t:it("fixture " .. i .. ": " .. case[1], function()
				expect.equal(Sources.StripTags(case[1]), case[2])
			end)
		end

		t:it("never modifies the stored source", function()
			local c = Schema.NewCharacter(1)
			local text = "{h1}Title{/h1}{col:ff0000}x{/col}"
			Sources.Capture(c, "trp3", text)
			Sources.StripTags(Sources.Current(c).text)
			Sources.Sentences(Sources.Current(c).text)
			expect.equal(Sources.Current(c).text, text)
		end)
	end)

	t:describe("Sources.Paragraphs and Sentences", function()
		t:it("splits paragraphs on line breaks, dropping blank lines", function()
			expect.deepEqual(Sources.Paragraphs("One.\r\n\r\n  Two.  \nThree."), { "One.", "Two.", "Three." })
		end)

		-- Expected outputs are approximate by design; these pin the behaviour.
		local cases = {
			{ "Simple one. Simple two! Three?", { "Simple one.", "Simple two!", "Three?" } },
			{ "She prayed to St. Ilsa. Then left.", { "She prayed to St. Ilsa.", "Then left." } },
			{ "Mr. and Mrs. Hale came.", { "Mr. and Mrs. Hale came." } },
			{ "J. R. Hale wrote it. Done.", { "J. R. Hale wrote it.", "Done." } },
			{ "Wait... and then. Silence... Night fell.", { "Wait... and then.", "Silence...", "Night fell." } },
			{ "Hm\226\128\166 Later.", { "Hm\226\128\166", "Later." } },
			{ '"Run!" she said. "Now!" He ran.', { '"Run!" she said.', '"Now!"', "He ran." } },
			{ "Really?! Yes.", { "Really?!", "Yes." } },
			{ "\230\152\175\227\128\130\229\165\189\239\188\129\229\144\151\239\188\159", -- 是。好！吗？
				{ "\230\152\175\227\128\130", "\229\165\189\239\188\129", "\229\144\151\239\188\159" } },
			{ "No final punctuation", { "No final punctuation" } },
			{ "Version 3.5 shipped. Next.", { "Version 3.5 shipped.", "Next." } },
			-- Known limits:
			{ "lower case start. another one.", { "lower case start. another one." } },
			{ "The Capt. Hale spoke. Lord. Boy.", { "The Capt. Hale spoke.", "Lord.", "Boy." } },
			{ "Visit Ft. Ender.", { "Visit Ft. Ender." } },
			{ "He met Gen. Ilsa and Col. Brand.", { "He met Gen. Ilsa and Col. Brand." } },
			{ "Bring tools, i.e. Hammers. Go.", { "Bring tools, i.e. Hammers.", "Go." } },
		}
		for i, case in ipairs(cases) do
			t:it("fixture " .. i .. ": " .. case[1], function()
				expect.deepEqual(Sources.Sentences(case[1]), case[2])
			end)
		end

		t:it("handles empty and non-string input", function()
			expect.deepEqual(Sources.Sentences(""), {})
			expect.deepEqual(Sources.Sentences(nil), {})
			expect.deepEqual(Sources.Paragraphs(nil), {})
		end)
	end)
end
