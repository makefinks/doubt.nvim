local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt.panel"] = nil

local panel = require("doubt.panel")

local ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-fixed-width-spec", { clear = true }),
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
	ns = vim.api.nvim_create_namespace("doubt.panel.fixed.width.spec"),
}

panel.open(ctx)

local panel_win = vim.api.nvim_get_current_win()
local initial_width = vim.api.nvim_win_get_width(panel_win)

vim.cmd("topleft vnew")
local sidebar_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(sidebar_win, 20)
vim.api.nvim_win_close(sidebar_win, true)

t.assert_eq(vim.api.nvim_win_get_width(panel_win), initial_width, "panel should keep its configured width when another sidebar opens and closes")

if vim.api.nvim_win_is_valid(panel_win) then
	vim.api.nvim_win_close(panel_win, true)
end
