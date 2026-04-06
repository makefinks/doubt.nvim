local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt.panel"] = nil

local panel = require("doubt.panel")

vim.wo.number = true
vim.wo.relativenumber = false
vim.wo.signcolumn = "yes"
vim.wo.foldcolumn = "1"
vim.wo.cursorline = true
vim.wo.winfixwidth = false

local ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-window-options-spec", { clear = true }),
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
	ns = vim.api.nvim_create_namespace("doubt.panel.window.options.spec"),
}

panel.open(ctx)

local panel_win = vim.api.nvim_get_current_win()

t.assert_eq(vim.wo[panel_win].number, false, "panel should disable line numbers while open")
t.assert_eq(vim.wo[panel_win].winfixwidth, true, "panel should keep a fixed width while open")

vim.cmd("enew")

t.assert_eq(vim.wo[panel_win].number, true, "window should restore line numbers after replacing the panel buffer")
t.assert_eq(vim.wo[panel_win].relativenumber, false, "window should restore relative number setting after replacing the panel buffer")
t.assert_eq(vim.wo[panel_win].signcolumn, "yes", "window should restore signcolumn after replacing the panel buffer")
t.assert_eq(vim.wo[panel_win].foldcolumn, "1", "window should restore foldcolumn after replacing the panel buffer")
t.assert_eq(vim.wo[panel_win].cursorline, true, "window should restore cursorline after replacing the panel buffer")
t.assert_eq(vim.wo[panel_win].winfixwidth, false, "window should restore fixed-width setting after replacing the panel buffer")

if vim.api.nvim_win_is_valid(panel_win) then
	vim.api.nvim_win_close(panel_win, true)
end
