local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
vim.fn.mkdir(vim.fs.dirname(temp_state), "p")

package.loaded["doubt"] = nil
package.loaded["doubt.state"] = nil

local doubt = require("doubt")
local commands = require("doubt.commands")
local panel = require("doubt.panel")
local state = require("doubt.state")

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

state.set_active_session("active-session")
local active_file = state.ensure_file_entry("lua/doubt/init.lua")
table.insert(active_file.claims, {
	id = "active-claim",
	kind = "question",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 3,
	note = "active note",
})

state.set_active_session("saved-session")
local saved_file = state.ensure_file_entry("lua/doubt/state.lua")
table.insert(saved_file.claims, {
	id = "saved-claim",
	kind = "reject",
	start_line = 2,
	start_col = 0,
	end_line = 4,
	end_col = 0,
	note = "saved note",
})

state.set_active_session("active-session")

local renamed_saved = doubt.rename_session({
	name = "saved-session",
	new_name = "renamed-session",
})
t.assert_eq(renamed_saved, true, "renaming a known saved session should succeed")
t.assert_eq(state.get().sessions["saved-session"], nil, "rename should remove the old session key")
t.assert_eq(
	state.get().sessions["renamed-session"] ~= nil,
	true,
	"rename should create the replacement session key"
)
t.assert_eq(
	state.get().sessions["renamed-session"].files["lua/doubt/state.lua"].claims[1].id,
	"saved-claim",
	"rename should preserve saved session claims"
)
t.assert_eq(state.active_session_name(), "active-session", "renaming non-active session should keep active session unchanged")

local renamed_active = doubt.rename_session({
	name = "active-session",
	new_name = "active-renamed",
})
t.assert_eq(renamed_active, true, "renaming active session should succeed")
t.assert_eq(state.active_session_name(), "active-renamed", "renaming active session should update active_session")
t.assert_eq(state.get().sessions["active-session"], nil, "old active session key should be removed")
t.assert_eq(
	state.get().sessions["active-renamed"].files["lua/doubt/init.lua"].claims[1].id,
	"active-claim",
	"renaming active session should preserve file/claim state"
)

state.ensure_session("taken-session")

local before_unknown = vim.deepcopy(state.get())
t.assert_eq(
	doubt.rename_session({ name = "missing-session", new_name = "new-name" }),
	false,
	"renaming an unknown session should fail"
)
t.assert_eq(vim.deep_equal(state.get(), before_unknown), true, "unknown rename should not mutate state")

local before_duplicate = vim.deepcopy(state.get())
t.assert_eq(
	doubt.rename_session({ name = "renamed-session", new_name = "taken-session" }),
	false,
	"renaming into an existing session should fail"
)
t.assert_eq(vim.deep_equal(state.get(), before_duplicate), true, "duplicate rename should not mutate state")

local before_empty = vim.deepcopy(state.get())
t.assert_eq(
	doubt.rename_session({ name = "renamed-session", new_name = "" }),
	false,
	"renaming into an empty name should fail"
)
t.assert_eq(vim.deep_equal(state.get(), before_empty), true, "empty rename should not mutate state")

local command_calls = {}
commands.register({
	rename_session = function(opts)
		table.insert(command_calls, opts or {})
	end,
	list_export_templates = function()
		return { "raw" }
	end,
})

vim.cmd("DoubtSessionRename renamed-session via-command")
t.assert_eq(#command_calls, 1, "rename command should route through api.rename_session")
t.assert_eq(command_calls[1].name, "renamed-session", "rename command should pass first arg as old session name")
t.assert_eq(command_calls[1].new_name, "via-command", "rename command should pass second arg as new session name")

vim.cmd("DoubtSessionRename")
t.assert_eq(#command_calls, 2, "rename command without args should still route through api.rename_session")
t.assert_eq(command_calls[2].name, nil, "rename command without args should rely on prompt flow")
t.assert_eq(command_calls[2].new_name, nil, "rename command without args should rely on prompt flow")

package.loaded["doubt.panel"] = nil
panel = require("doubt.panel")

local panel_rename_calls = {}
local panel_refresh_calls = 0
local panel_ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-rename-spec", { clear = true }),
	config = {
		get = function()
			return {
				panel = {
					side = "right",
					width = 40,
				},
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
			return { "saved-one" }
		end,
		get = function()
			return {
				sessions = {
					["saved-one"] = {
						files = {},
					},
				},
			}
		end,
	},
	api = {
		rename_session = function(opts)
			table.insert(panel_rename_calls, opts or {})
		end,
		refresh = function()
			panel_refresh_calls = panel_refresh_calls + 1
		end,
		start_session = function() end,
		resume_session = function() end,
		stop_session = function() end,
		delete_session = function() end,
		clear_focused_claim = function() end,
		focus_claim = function() end,
		delete_claim = function() end,
		delete_file = function() end,
	},
	ns = vim.api.nvim_create_namespace("doubt.panel.rename.spec"),
}

panel.open(panel_ctx)
local panel_win = vim.api.nvim_get_current_win()
local panel_buf = vim.api.nvim_get_current_buf()
local panel_lines = panel.build_lines(panel_ctx, 40)
local session_line = nil
for idx, item in ipairs(panel_lines) do
	if item.kind == "session" and item.session_name == "saved-one" then
		session_line = idx
		break
	end
end

t.assert_eq(session_line ~= nil, true, "panel should render saved session row for rename key test")
vim.api.nvim_win_set_cursor(panel_win, { session_line, 0 })
vim.api.nvim_buf_call(panel_buf, function()
	vim.api.nvim_feedkeys(vim.keycode("R"), "xt", false)
end)

t.assert_eq(#panel_rename_calls, 1, "panel R should call rename_session on session rows")
t.assert_eq(panel_rename_calls[1].name, "saved-one", "panel R should pass selected session name")

local non_session_line = 1
vim.api.nvim_win_set_cursor(panel_win, { non_session_line, 0 })
vim.api.nvim_buf_call(panel_buf, function()
	vim.api.nvim_feedkeys(vim.keycode("R"), "xt", false)
	vim.api.nvim_feedkeys(vim.keycode("r"), "xt", false)
end)

t.assert_eq(#panel_rename_calls, 1, "panel R should do nothing on non-session rows")
t.assert_eq(panel_refresh_calls, 1, "panel lowercase r should remain mapped to refresh")

if vim.api.nvim_win_is_valid(panel_win) then
	vim.api.nvim_win_close(panel_win, true)
end
