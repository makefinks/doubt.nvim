local t = dofile("tests/helpers/bootstrap.lua")

local doubt = require("doubt")
local state = require("doubt.state")

local function write_file(path, lines)
	vim.fn.writefile(lines, path)
end

local function write_state(path, session_name, file_path)
	local workspace_key = vim.fs.normalize(vim.fn.getcwd())
	local payload = {
		workspaces = {
			[workspace_key] = {
				active_session = session_name,
				sessions = {
					[session_name] = {
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
										note = "recheck",
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

local function run_activation_case(method_name)
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")

	local session_name = method_name .. "-review"
	local source_path = vim.fs.joinpath(temp_dir, "sample.lua")
	local state_path = vim.fs.joinpath(temp_dir, "doubt-state.json")

	write_file(source_path, {
		"alpha",
		"target()",
		"omega",
	})
	write_state(state_path, session_name, source_path)

	doubt.setup({
		export = {
			register = "c",
		},
		state_path = state_path,
	})

	local loaded_claim = state.current_files()[source_path].claims[1]
	t.assert_eq(loaded_claim.freshness, "fresh", method_name .. " setup should classify unchanged anchors as fresh")

	write_file(source_path, {
		"alpha",
		"changed()",
		"omega",
	})

	doubt.stop_session()
	vim.fn.setreg("c", "keep me")

	if method_name == "resume" then
		doubt.resume_session({ name = session_name, quiet = true })
	else
		doubt.start_session({ name = session_name, quiet = true })
	end

	local reopened_claim = state.current_files()[source_path].claims[1]
	t.assert_eq(reopened_claim.freshness, "stale", method_name .. " should reclassify a changed claim before redraw")
	t.assert_eq(reopened_claim.start_line, 1, method_name .. " should keep stale claims at their saved location")

	local notifications = {}
	local original_notify = vim.notify
	vim.notify = function(message, level, opts)
		table.insert(notifications, {
			message = message,
			level = level,
			opts = opts,
		})
	end

	local copied = doubt.copy_export()
	vim.notify = original_notify

	t.assert_eq(copied, nil, method_name .. " should keep stale reopened claims out of default export")
	t.assert_eq(vim.fn.getreg("c"), "keep me", method_name .. " should not overwrite the export register when nothing trusted remains")
	t.assert_eq(notifications[#notifications].message, "No exportable claims remain; skipped 1 stale claim", method_name .. " should report the stale-skip guardrail")
end

local function run_export_recheck_case()
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")

	local session_name = "export-review"
	local source_path = vim.fs.joinpath(temp_dir, "sample.lua")
	local state_path = vim.fs.joinpath(temp_dir, "doubt-state.json")

	write_file(source_path, {
		"alpha",
		"target()",
		"omega",
	})
	write_state(state_path, session_name, source_path)

	doubt.setup({
		export = {
			register = "c",
		},
		state_path = state_path,
	})

	local loaded_claim = state.current_files()[source_path].claims[1]
	t.assert_eq(loaded_claim.freshness, "fresh", "setup should classify unchanged anchors as fresh before export")

	write_file(source_path, {
		"alpha",
		"changed()",
		"omega",
	})

	local notifications = {}
	local original_notify = vim.notify
	vim.notify = function(message, level, opts)
		table.insert(notifications, {
			message = message,
			level = level,
			opts = opts,
		})
	end

	vim.fn.setreg("c", "keep me")
	local copied = doubt.copy_export()
	vim.notify = original_notify

	local refreshed_claim = state.current_files()[source_path].claims[1]
	t.assert_eq(refreshed_claim.freshness, "stale", "export should reclassify changed files before trusting saved ranges")
	t.assert_eq(copied, nil, "export should block stale claims discovered during pre-export refresh")
	t.assert_eq(vim.fn.getreg("c"), "keep me", "export should not overwrite the register when refresh makes all claims stale")
	t.assert_eq(notifications[#notifications].message, "No exportable claims remain; skipped 1 stale claim", "export should report stale claims found during pre-export refresh")
end

run_activation_case("resume")
run_activation_case("start")
run_export_recheck_case()
