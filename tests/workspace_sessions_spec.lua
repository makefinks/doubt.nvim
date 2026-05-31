local t = dofile("tests/helpers/bootstrap.lua")

describe("workspace sessions", function()
	it("matches expected behavior", function()

package.loaded["doubt"] = nil
package.loaded["doubt.state"] = nil

local doubt = require("doubt")
local state = require("doubt.state")

local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root, "p")
local previous_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(temp_root))

local source_path = vim.fs.joinpath(temp_root, "lua", "doubt", "sample.lua")
vim.fn.mkdir(vim.fs.dirname(source_path), "p")
vim.fn.writefile({ "local value = 1", "return value" }, source_path)
local line_only_path = vim.fs.joinpath(temp_root, "lua", "doubt", "line_only.lua")
vim.fn.writefile({ "return true" }, line_only_path)
local loose_end_col_path = vim.fs.joinpath(temp_root, "lua", "doubt", "loose_end_col.lua")
vim.fn.writefile({
	"local session = load_session(name)",
	"\tif session_cache[name] then",
	"\t\treturn session_cache[name]",
	"\tend",
}, loose_end_col_path)

doubt.setup({
	keymaps = false,
	state_path = vim.fs.joinpath(temp_root, "state.json"),
})

doubt.start_workspace_session({ name = "ai-review", quiet = true })
t.assert_eq(state.active_session_name(), "ai-review", "workspace session should become active")
t.assert_eq(state.active_session_source(), "workspace", "active source should be workspace")

vim.cmd("edit " .. vim.fn.fnameescape(source_path))
local bufnr = vim.api.nvim_get_current_buf()
doubt.claim_range("concern", {
	bufnr = bufnr,
	line1 = 2,
	line2 = 2,
	note = "Changed return value needs review.",
})

local claim_file = vim.fs.joinpath(temp_root, ".doubt", "sessions", "ai-review", "claims", "lua", "doubt", "sample.lua.json")
local decoded = vim.json.decode(table.concat(vim.fn.readfile(claim_file), "\n"))
t.assert_eq(decoded.schema_version, 1, "workspace claim files should include schema version")
t.assert_eq(decoded.file, "lua/doubt/sample.lua", "workspace claim files should use repo-relative paths")
t.assert_eq(decoded.claims[1].start_line, 2, "workspace files should write one-based start lines")
t.assert_eq(decoded.claims[1].start_col, 1, "workspace files should write one-based start columns")
t.assert_eq(decoded.claims[1].kind, "concern", "workspace files should preserve claim kind")
t.assert_eq(decoded.claims[1].freshness, "fresh", "workspace files should persist freshness")
t.assert_eq(type(decoded.claims[1].anchor.text), "string", "workspace files should persist anchors")

vim.fn.writefile({ "local value = 1", "local other = true", "return value" }, source_path)
doubt.refresh()

local refreshed = vim.json.decode(table.concat(vim.fn.readfile(claim_file), "\n"))
t.assert_eq(refreshed.claims[1].start_line, 3, "refresh should write reanchored one-based lines back")
t.assert_eq(refreshed.claims[1].freshness, "reanchored", "refresh should write freshness updates back")

doubt.stop_session()
t.assert_eq(state.active_session_name(), nil, "stopping workspace session should leave no active session")

local manual_claim_file = vim.fs.joinpath(temp_root, ".doubt", "sessions", "manual-agent", "claims", "lua", "doubt", "line_only.lua.json")
vim.fn.mkdir(vim.fs.dirname(manual_claim_file), "p")
vim.fn.writefile({
	vim.json.encode({
		schema_version = 1,
		file = "lua/doubt/line_only.lua",
		claims = {
			{
				id = "agent-line-only",
				kind = "concern",
				start_line = 1,
				start_col = 1,
				end_line = 1,
				end_col = 1,
				note = "Line-only agent range should not become stale.",
			},
		},
	}),
}, manual_claim_file)
vim.fn.writefile({ vim.json.encode({ schema_version = 1, name = "manual-agent" }) }, vim.fs.joinpath(temp_root, ".doubt", "sessions", "manual-agent", "session.json"))

doubt.resume_workspace_session({ name = "manual-agent", quiet = true })
local manual_file_state = nil
for _, file_state in pairs(state.current_files()) do
	manual_file_state = file_state
end
local manual_claim = manual_file_state.claims[1]
t.assert_eq(manual_claim.freshness, "fresh", "line-only zero-width agent ranges should expand to a fresh line anchor")
t.assert_eq(manual_claim.anchor.text, "return true", "line-only zero-width agent ranges should anchor through EOL")

local loose_end_col_claim_file = vim.fs.joinpath(temp_root, ".doubt", "sessions", "loose-end-col", "claims", "lua", "doubt", "loose_end_col.lua.json")
vim.fn.mkdir(vim.fs.dirname(loose_end_col_claim_file), "p")
vim.fn.writefile({
	vim.json.encode({
		schema_version = 1,
		file = "lua/doubt/loose_end_col.lua",
		claims = {
			{
				id = "agent-loose-end-col",
				kind = "concern",
				start_line = 2,
				start_col = 2,
				end_line = 4,
				end_col = 31,
				note = "Agent range with loose end_col should not become stale.",
				freshness = "stale",
				anchor = { text = "", before = "", after = "" },
			},
		},
	}),
}, loose_end_col_claim_file)
vim.fn.writefile({ vim.json.encode({ schema_version = 1, name = "loose-end-col" }) }, vim.fs.joinpath(temp_root, ".doubt", "sessions", "loose-end-col", "session.json"))

doubt.resume_workspace_session({ name = "loose-end-col", quiet = true })
local loose_end_col_file_state = nil
for _, file_state in pairs(state.current_files()) do
	loose_end_col_file_state = file_state
end
local loose_end_col_claim = loose_end_col_file_state.claims[1]
t.assert_eq(loose_end_col_claim.freshness, "fresh", "agent ranges with loose end columns should rebuild fresh anchors")
t.assert_eq(loose_end_col_claim.end_col, nil, "loose end columns should expand to full end line")
t.assert_match(loose_end_col_claim.anchor.text, "session_cache%[name%]", "rebuilt anchor should include the intended range")

vim.cmd("cd " .. vim.fn.fnameescape(previous_cwd))
	end)
end)
