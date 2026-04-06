local t = dofile("tests/helpers/bootstrap.lua")
local doubt = require("doubt")
local state = require("doubt.state")

local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, "p")

local function write_file(path, lines)
	vim.fn.writefile(lines, path)
end

local function write_state(path, file_path)
	local workspace_key = vim.fs.normalize(vim.fn.getcwd())
	local payload = {
		workspaces = {
			[workspace_key] = {
				active_session = "refresh-review",
				sessions = {
					["refresh-review"] = {
						files = {
							[file_path] = {
								claims = {
									{
										id = "claim-1",
										kind = "question",
										start_line = 1,
										start_col = 0,
										end_line = 1,
										end_col = 8,
										note = "check",
										freshness = "stale",
										anchor = {
											text = "target()",
											before = "alpha\n",
											after = "\nomega",
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}
	vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local source_path = vim.fs.joinpath(temp_dir, "sample.lua")
local state_path = vim.fs.joinpath(temp_dir, "doubt-state.json")

write_file(source_path, {
	"alpha",
	"target()",
	"omega",
})
write_state(state_path, source_path)

doubt.setup({
	state_path = state_path,
})

local loaded_claim = state.current_files()[source_path].claims[1]
t.assert_eq(loaded_claim.freshness, "fresh", "load should classify unchanged anchors as fresh")
t.assert_eq(loaded_claim.start_line, 1, "load classification should preserve saved ranges")

write_file(source_path, {
	"alpha",
	"changed()",
	"omega",
})

doubt.refresh()

local refreshed_claim = state.current_files()[source_path].claims[1]
t.assert_eq(refreshed_claim.freshness, "stale", "manual refresh should reclassify changed anchors as stale")
t.assert_eq(refreshed_claim.start_line, 1, "manual refresh should not move stale claims in phase 1")

local missing_state_path = vim.fs.joinpath(temp_dir, "missing-state.json")
local missing_source_path = vim.fs.joinpath(temp_dir, "missing.lua")
write_state(missing_state_path, missing_source_path)

doubt.setup({
	state_path = missing_state_path,
})

local missing_claim = state.current_files()[missing_source_path].claims[1]
t.assert_eq(missing_claim.freshness, "stale", "load should classify missing files as stale")
