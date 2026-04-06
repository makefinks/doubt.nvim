local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt.panel"] = nil

local panel = require("doubt.panel")

local ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-focus-existing-spec", { clear = true }),
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
			return {}
		end,
		get = function()
			return { sessions = {} }
		end,
	},
	api = {
		refresh = function() end,
		start_session = function() end,
		resume_session = function() end,
		stop_session = function() end,
		delete_session = function() end,
		rename_session = function() end,
		clear_focused_claim = function() end,
		focus_claim = function() end,
		delete_claim = function() end,
		delete_file = function() end,
	},
	ns = vim.api.nvim_create_namespace("doubt.panel.focus.existing.spec"),
}

local source_win = vim.api.nvim_get_current_win()

panel.open(ctx)
local panel_win = vim.api.nvim_get_current_win()

vim.api.nvim_set_current_win(source_win)
panel.open(ctx)

t.assert_eq(vim.api.nvim_get_current_win(), panel_win, "opening while the panel exists should focus it")
t.assert_eq(vim.api.nvim_win_is_valid(panel_win), true, "focusing an existing panel should keep the panel window alive")
