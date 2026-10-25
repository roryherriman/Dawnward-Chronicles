local Loader = require("support.loader")

return function(t, expect)
	local ns = Loader.CoreUpTo("Privacy")
	local Util, Privacy = ns.Util, ns.Privacy

	t:describe("Util.DeepCopy", function()
		t:it("copies nested tables independently", function()
			local src = { a = { b = { 1, 2 } }, s = "x" }
			local copy = Util.DeepCopy(src)
			expect.deepEqual(copy, src)
			copy.a.b[1] = 99
			expect.equal(src.a.b[1], 1)
		end)

		t:it("preserves cycles without recursing forever", function()
			local src = {}
			src.self = src
			local copy = Util.DeepCopy(src)
			expect.truthy(copy.self == copy)
			expect.truthy(copy ~= src)
		end)
	end)

	t:describe("Util.TruncateUtf8", function()
		t:it("leaves short strings alone", function()
			expect.equal(Util.TruncateUtf8("abc", 5), "abc")
		end)

		t:it("never splits a multi-byte character", function()
			local s = "a\195\169b" -- "aéb": é is two bytes
			expect.equal(Util.TruncateUtf8(s, 2), "a")
			expect.equal(Util.TruncateUtf8(s, 3), "a\195\169")
			local three = "\226\130\172\226\130\172" -- two euro signs, 3 bytes each
			expect.equal(Util.TruncateUtf8(three, 5), "\226\130\172")
		end)
	end)

	t:describe("Util.CleanText", function()
		t:it("rejects non-strings", function()
			expect.equal(Util.CleanText(42, 10), nil)
		end)

		t:it("strips WoW escape sequences and stray pipes", function()
			expect.equal(Util.CleanText("|cffff0000Red|r text", 100), "Red text")
			expect.equal(Util.CleanText("|Hitem:19019|h[Thunderfury]|h", 100), "[Thunderfury]")
			expect.equal(Util.CleanText("icon|TInterface\\Icons\\X:0|t here", 100), "icon here")
			expect.equal(Util.CleanText("a || b | c", 100), "a  b  c")
		end)

		t:it("removes control characters and flattens single-line text", function()
			expect.equal(Util.CleanText("a\0b\7c\nd", 100), "abc d")
		end)

		t:it("keeps newlines in multi-line text and normalises CRLF", function()
			expect.equal(Util.CleanText("line1\r\nline2\rline3", 100, true), "line1\nline2\nline3")
		end)

		t:it("trims and truncates", function()
			expect.equal(Util.CleanText("   hello world   ", 5), "hello")
		end)
	end)

	t:describe("Util.NextWord", function()
		t:it("splits the first word from the rest", function()
			local word, rest = Util.NextWord("  family add  father Aldric Dawn ")
			expect.equal(word, "family")
			expect.equal(rest, "add  father Aldric Dawn ")
		end)

		t:it("handles empty input", function()
			local word, rest = Util.NextWord(nil)
			expect.equal(word, "")
			expect.equal(rest, "")
		end)
	end)

	t:describe("Privacy", function()
		t:it("defaults invalid levels to private, never public", function()
			expect.equal(Privacy.Normalize(nil), "private")
			expect.equal(Privacy.Normalize("PUBLIC"), "private")
			expect.equal(Privacy.Normalize("secret"), "secret")
		end)

		t:it("filters by allowed levels", function()
			expect.truthy(Privacy.Allows(Privacy.PUBLIC_ONLY, "public"))
			expect.falsy(Privacy.Allows(Privacy.PUBLIC_ONLY, "private"))
			expect.falsy(Privacy.Allows(Privacy.PUBLIC_ONLY, "bogus"))
		end)
	end)
end
