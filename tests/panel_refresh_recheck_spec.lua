local t = dofile("tests/helpers/bootstrap.lua")

local panel = require("doubt.panel")

local original_render = panel.render
local refresh_count = 0
local render_count = 0

panel.render = function(_)
	render_count = render_count + 1
end

local ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-refresh-spec", { clear = true }),
	config = {
		get = function()
			return {
				panel = {
					side = "right",
					width = 30,
				},
			}
		end,
	},
	api = {
		refresh = function()
			refresh_count = refresh_count + 1
		end,
		start_session = function() end,
		resume_session = function() end,
		stop_session = function() end,
		delete_session = function() end,
	},
}

panel.open(ctx)

local winid = vim.api.nvim_get_current_win()
local bufnr = vim.api.nvim_get_current_buf()

t.assert_eq(render_count, 1, "opening the panel should render once")

vim.api.nvim_buf_call(bufnr, function()
	vim.api.nvim_feedkeys(vim.keycode("r"), "xt", false)
end)

t.assert_eq(refresh_count, 1, "panel refresh key should call ctx.api.refresh() exactly once")
t.assert_eq(render_count, 1, "panel refresh key should not call panel.render() directly")

if vim.api.nvim_win_is_valid(winid) then
	vim.api.nvim_win_close(winid, true)
end

panel.render = original_render
