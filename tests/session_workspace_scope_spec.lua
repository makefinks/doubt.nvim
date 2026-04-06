local t = dofile("tests/helpers/bootstrap.lua")

local function load_state_module()
	package.loaded["doubt.state"] = nil
	return require("doubt.state")
end

local function load_doubt_module()
	package.loaded["doubt"] = nil
	package.loaded["doubt.state"] = nil
	return require("doubt"), require("doubt.state")
end

local function write_json(path, value)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile({ vim.json.encode(value) }, path)
end

local function read_json(path)
	local lines = vim.fn.readfile(path)
	return vim.json.decode(table.concat(lines, "\n"))
end

local function with_cwd(path, fn)
	local previous = vim.fn.getcwd()
	vim.cmd("cd " .. vim.fn.fnameescape(path))
	local ok, err = pcall(fn)
	vim.cmd("cd " .. vim.fn.fnameescape(previous))
	if not ok then
		error(err)
	end
end

local function sorted(list)
	local copy = vim.deepcopy(list)
	table.sort(copy)
	return copy
end

local function workspace_key(path)
	local key = nil
	with_cwd(path, function()
		key = vim.fs.normalize(vim.fn.getcwd())
	end)
	return key
end

local function test_workspace_scoped_listing_and_resume_guard()
	local root = vim.fn.tempname()
	local workspace_a = vim.fs.joinpath(root, "workspace-a")
	local workspace_b = vim.fs.joinpath(root, "workspace-b")
	vim.fn.mkdir(workspace_a, "p")
	vim.fn.mkdir(workspace_b, "p")

	local state_path = vim.fs.joinpath(root, "doubt-state.json")
	local workspace_key_a = workspace_key(workspace_a)
	local workspace_key_b = workspace_key(workspace_b)
	write_json(state_path, {
		workspaces = {
			[workspace_key_a] = {
				active_session = "shared-name",
				sessions = {
					["shared-name"] = {
						files = {
							[vim.fs.joinpath(workspace_a, "alpha.lua")] = {
								claims = {
									{
										id = "a-1",
										kind = "question",
										start_line = 0,
										start_col = 0,
										end_line = 0,
										end_col = 1,
										note = "a",
									},
								},
							},
						},
					},
				},
			},
			[workspace_key_b] = {
				active_session = nil,
				sessions = {
					["shared-name"] = { files = {} },
					["workspace-b-only"] = { files = {} },
				},
			},
		},
	})

	local notifications = {}
	local original_notify = vim.notify
	vim.notify = function(message)
		table.insert(notifications, message)
	end
	local doubt, state = load_doubt_module()

	with_cwd(workspace_a, function()
		doubt.setup({ keymaps = false, state_path = state_path })

		t.assert_eq(sorted(state.list_sessions()), { "shared-name" }, "only workspace A sessions should be listed")
		t.assert_eq(state.active_session_name(), "shared-name", "workspace A active session should be restored")

		doubt.stop_session()
		doubt.resume_session({ name = "workspace-b-only", quiet = true })
		t.assert_eq(state.active_session_name(), nil, "cross-workspace session names should be unknown")
		t.assert_eq(notifications[#notifications], "Unknown doubt session", "resume should report unknown session")
	end)

	vim.notify = original_notify
end

local function test_legacy_root_level_state_is_ignored_for_workspace_scope()
	local root = vim.fn.tempname()
	local workspace = vim.fs.joinpath(root, "workspace")
	vim.fn.mkdir(workspace, "p")

	local state_path = vim.fs.joinpath(root, "doubt-state.json")
	local workspace_key = workspace_key(workspace)
	write_json(state_path, {
		active_session = "legacy-session",
		sessions = {
			["legacy-session"] = {
				files = {},
			},
		},
	})

	local state = load_state_module()
	with_cwd(workspace, function()
		state.load({ state_path = state_path }, vim.fs.normalize, function() end, workspace_key)
		t.assert_eq(state.active_session_name(), nil, "legacy root-level active session should not be imported")
		t.assert_eq(sorted(state.list_sessions()), {}, "legacy root-level sessions should be ignored")

		state.save({ state_path = state_path }, function() end)
	end)

	local persisted = read_json(state_path)
	t.assert_eq(type(persisted.workspaces), "table", "save should persist workspace container")
	t.assert_eq(type(persisted.workspaces[workspace_key]), "table", "current workspace bucket should exist after load")
	t.assert_eq(
		((persisted.workspaces[workspace_key] or {}).sessions or {})["legacy-session"],
		nil,
		"current workspace should not contain legacy root-level sessions"
	)
end

local function test_session_mutations_only_touch_current_workspace_bucket()
	local root = vim.fn.tempname()
	local workspace_a = vim.fs.joinpath(root, "workspace-a")
	local workspace_b = vim.fs.joinpath(root, "workspace-b")
	vim.fn.mkdir(workspace_a, "p")
	vim.fn.mkdir(workspace_b, "p")

	local state_path = vim.fs.joinpath(root, "doubt-state.json")
	local workspace_key_a = vim.fs.normalize(workspace_a)
	local workspace_key_b = vim.fs.normalize(workspace_b)
	local original_workspace_b = {
		active_session = "stay",
		sessions = {
			stay = { files = {} },
			other = { files = {} },
		},
	}

	write_json(state_path, {
		workspaces = {
			[workspace_key_a] = {
				active_session = "alpha",
				sessions = {
					alpha = { files = {} },
					remove_me = { files = {} },
				},
			},
			[workspace_key_b] = original_workspace_b,
		},
	})

	local state = load_state_module()
	state.load({ state_path = state_path }, vim.fs.normalize, function() end, workspace_key_a)
	state.rename_session("alpha", "alpha-renamed")
	state.delete_session("remove_me")
	state.stop_session()
	state.save({ state_path = state_path }, function() end)

	local persisted = read_json(state_path)
	t.assert_eq(
		vim.deep_equal((persisted.workspaces or {})[workspace_key_b], original_workspace_b),
		true,
		"mutations in workspace A must not modify workspace B bucket"
	)
	t.assert_eq(
		type((((persisted.workspaces or {})[workspace_key_a] or {}).sessions or {})["alpha-renamed"]),
		"table",
		"rename should apply in current workspace"
	)
	t.assert_eq(
		(((persisted.workspaces or {})[workspace_key_a] or {}).sessions or {}).remove_me,
		nil,
		"delete should apply in current workspace"
	)
end

local function test_panel_shows_only_current_workspace_saved_sessions()
	local panel = require("doubt.panel")
	local lines = panel.build_lines({
		config = {
			get = function()
				return {
					signs = {
						file = "?",
					},
				}
			end,
		},
		state = {
			current_files = function()
				return {}
			end,
			active_session_name = function()
				return nil
			end,
			list_sessions = function()
				return { "local-one" }
			end,
			active_workspace_key = function()
				return "/workspace/a"
			end,
			get = function()
				return {
					sessions = {
						["local-one"] = { files = {} },
						["other-workspace"] = { files = {} },
					},
				}
			end,
		},
	}, 80)

	local saved_rows = {}
	local scoped_copy_seen = false
	for _, item in ipairs(lines) do
		if item.kind == "session" then
			table.insert(saved_rows, item.session_name)
		end
		if item.kind == "muted" and item.text == "Saved sessions below are scoped to this workspace." then
			scoped_copy_seen = true
		end
	end

	t.assert_eq(scoped_copy_seen, true, "panel should communicate workspace-scoped saved sessions")
	t.assert_eq(saved_rows, { "local-one" }, "panel should render only the scoped list_sessions entries")
end

test_workspace_scoped_listing_and_resume_guard()
test_legacy_root_level_state_is_ignored_for_workspace_scope()
test_session_mutations_only_touch_current_workspace_bucket()
test_panel_shows_only_current_workspace_saved_sessions()
