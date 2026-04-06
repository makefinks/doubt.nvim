local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt.panel"] = nil

local panel = require("doubt.panel")

local refresh_count = 0
local started = 0
local resumed = 0
local stopped = 0
local deleted = 0
local renamed = 0

local ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-help-spec", { clear = true }),
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
		refresh = function()
			refresh_count = refresh_count + 1
		end,
		start_session = function()
			started = started + 1
		end,
		resume_session = function()
			resumed = resumed + 1
		end,
		stop_session = function()
			stopped = stopped + 1
		end,
		delete_session = function()
			deleted = deleted + 1
		end,
		rename_session = function()
			renamed = renamed + 1
		end,
		clear_focused_claim = function() end,
		focus_claim = function() end,
		delete_claim = function() end,
		delete_file = function() end,
	},
	ns = vim.api.nvim_create_namespace("doubt.panel.help.spec"),
}

local function floating_window_count()
	local total = 0
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local cfg = vim.api.nvim_win_get_config(winid)
		if cfg.relative and cfg.relative ~= "" then
			total = total + 1
		end
	end
	return total
end

local function floating_windows()
	local wins = {}
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local cfg = vim.api.nvim_win_get_config(winid)
		if cfg.relative and cfg.relative ~= "" then
			table.insert(wins, winid)
		end
	end
	return wins
end

local function assert_no_help_open(message)
	t.assert_eq(floating_window_count(), 0, message)
end

local function assert_help_open(message)
	t.assert_eq(floating_window_count(), 1, message)
end

local function read_floating_text()
	local wins = floating_windows()
	if #wins == 0 then
		return ""
	end

	local bufnr = vim.api.nvim_win_get_buf(wins[1])
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	return table.concat(lines, "\n")
end

panel.open(ctx)
local panel_win = vim.api.nvim_get_current_win()
local panel_buf = vim.api.nvim_get_current_buf()

local lines = panel.build_lines(ctx, 60)
local saw_hint = false
for _, item in ipairs(lines) do
	if item.text == "press ? for help" then
		saw_hint = true
	end
	t.assert_eq(item.text ~= "Keybinds", true, "panel should not render the always-visible keybind section")
end
t.assert_eq(saw_hint, true, "panel should keep a compact 'press ? for help' hint")

assert_no_help_open("help should start closed")

vim.api.nvim_buf_call(panel_buf, function()
	vim.api.nvim_feedkeys(vim.keycode("?"), "xt", false)
end)
assert_help_open("pressing '?' should open centered help")

local help_text = read_floating_text()
t.assert_match(help_text, "Rename selected session", "help should describe panel rename action")
t.assert_match(help_text, "%[   R    %]", "help should show uppercase R keybind")

local open_windows = floating_windows()
vim.api.nvim_set_current_win(open_windows[1])
vim.api.nvim_feedkeys(vim.keycode("q"), "xt", false)
assert_no_help_open("help should close with q")

vim.api.nvim_set_current_win(panel_win)
vim.api.nvim_buf_call(panel_buf, function()
	vim.api.nvim_feedkeys(vim.keycode("?"), "xt", false)
end)
assert_help_open("help should reopen from panel '?' key")

vim.cmd("new")
vim.wait(100, function()
	return floating_window_count() == 0
end)
assert_no_help_open("help should auto-close when panel loses focus")
local scratch_win = vim.api.nvim_get_current_win()

vim.api.nvim_set_current_win(panel_win)
vim.api.nvim_buf_call(panel_buf, function()
	vim.api.nvim_feedkeys(vim.keycode("?"), "xt", false)
end)
assert_help_open("help should open again after focus change")

if vim.api.nvim_win_is_valid(scratch_win) then
	vim.api.nvim_win_close(scratch_win, true)
end

open_windows = floating_windows()
vim.api.nvim_set_current_win(open_windows[1])
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
assert_no_help_open("help should close with <Esc>")

vim.api.nvim_set_current_win(panel_win)
vim.api.nvim_buf_call(panel_buf, function()
	vim.api.nvim_feedkeys(vim.keycode("?"), "xt", false)
	vim.api.nvim_feedkeys(vim.keycode("r"), "xt", false)
end)

t.assert_eq(refresh_count, 1, "panel actions should still trigger while help is open")
assert_no_help_open("panel actions should auto-close help")

t.assert_eq(started, 0, "help flow should not start sessions unexpectedly")
t.assert_eq(resumed, 0, "help flow should not resume sessions unexpectedly")
t.assert_eq(stopped, 0, "help flow should not stop sessions unexpectedly")
t.assert_eq(deleted, 0, "help flow should not delete sessions unexpectedly")
t.assert_eq(renamed, 0, "help flow should not rename sessions unexpectedly")

if vim.api.nvim_win_is_valid(panel_win) then
	vim.api.nvim_win_close(panel_win, true)
end
