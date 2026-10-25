-- Static analysis config. WoW runs Lua 5.1, so the standard library is lua51.
-- WoW API globals are added per-directory as each layer starts using them
-- (Core/ must never need any).
std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
	".tooling/",
	"private/",
	"review/",
	"dist/",
}

-- The runner reads varargs/`arg` and may exit the process.
files["tests/run.lua"] = { read_globals = { "arg", "jit" } }
files["tests/spec/environment_spec.lua"] = { read_globals = { "jit" } }
