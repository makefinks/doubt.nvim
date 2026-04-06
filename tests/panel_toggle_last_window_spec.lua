local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt.panel"] = nil

local panel = require("doubt.panel")

local cleared = 0
local source_buf = vim.api.nvim_get_current_buf()

vim.bo[source_buf].buftype = ""
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "source buffer" })
vim.bo[source_buf].modified = false

local ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-toggle-last-window-spec", { clear = true }),
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
		clear_focused_claim = function()
			cleared = cleared + 1
		end,
		focus_claim = function() end,
		delete_claim = function() end,
		delete_file = function() end,
	},
	ns = vim.api.nvim_create_namespace("doubt.panel.toggle.last.window.spec"),
}

panel.open(ctx)
local panel_win = vim.api.nvim_get_current_win()
local panel_buf = vim.api.nvim_get_current_buf()

vim.cmd("wincmd p")
local other_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_close(other_win, true)
vim.api.nvim_set_current_win(panel_win)

panel.open(ctx)

t.assert_eq(#vim.api.nvim_tabpage_list_wins(0), 1, "toggling the last panel window should not try to close the final window")
t.assert_eq(vim.bo.buftype, "", "toggling the last panel window should leave a normal buffer behind")
t.assert_eq(vim.api.nvim_get_current_buf(), source_buf, "toggling the last panel window should restore the buffer that opened the panel")
t.assert_eq(vim.api.nvim_get_current_buf() ~= panel_buf, true, "toggling the last panel window should replace the panel buffer")
t.assert_eq(cleared > 0, true, "toggling the last panel window should clear focused claim state")
