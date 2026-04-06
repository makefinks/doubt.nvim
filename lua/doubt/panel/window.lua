local help = require("doubt.panel.help")
local navigation = require("doubt.panel.navigation")
local render = require("doubt.panel.render")
local state_mod = require("doubt.panel.state")

local M = {}

local function clear_panel_state(ctx)
	help.close_help()
	if ctx.api.clear_focused_claim then
		ctx.api.clear_focused_claim()
	end
	state_mod.panel_state.bufnr = nil
	state_mod.panel_state.winid = nil
	state_mod.panel_state.window_options = nil
	state_mod.panel_state.return_bufnr = nil
	state_mod.panel_state.lines = {}
end

function M.close_panel_window(ctx, winid)
	local panel_state = state_mod.panel_state
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		clear_panel_state(ctx)
		return
	end

	if #vim.api.nvim_tabpage_list_wins(0) == 1 then
		local return_bufnr = panel_state.return_bufnr
		state_mod.restore_window_options(winid)
		if return_bufnr and vim.api.nvim_buf_is_valid(return_bufnr) then
			vim.api.nvim_win_set_buf(winid, return_bufnr)
		else
			vim.api.nvim_win_set_buf(winid, vim.api.nvim_create_buf(true, false))
		end
		clear_panel_state(ctx)
		return
	end

	vim.api.nvim_win_close(winid, true)
end

function M.open(ctx, panel_api)
	local panel_state = state_mod.panel_state
	local existing = panel_state.winid and vim.api.nvim_win_is_valid(panel_state.winid) and panel_state.winid or nil
	if existing then
		if vim.api.nvim_get_current_win() ~= existing then
			vim.api.nvim_set_current_win(existing)
			return
		end

		M.close_panel_window(ctx, existing)
		return
	end

	local config = ctx.config.get()
	panel_state.return_bufnr = vim.api.nvim_get_current_buf()
	vim.cmd(config.panel.side == "left" and "topleft vnew" or "botright vnew")
	panel_state.winid = vim.api.nvim_get_current_win()
	panel_state.window_options = state_mod.capture_window_options(panel_state.winid)
	panel_state.bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(panel_state.winid, panel_state.bufnr)
	vim.api.nvim_win_set_width(panel_state.winid, config.panel.width)
	vim.wo[panel_state.winid].number = false
	vim.wo[panel_state.winid].relativenumber = false
	vim.wo[panel_state.winid].signcolumn = "no"
	vim.wo[panel_state.winid].foldcolumn = "0"
	vim.wo[panel_state.winid].cursorline = false
	vim.wo[panel_state.winid].winfixwidth = true

	vim.bo[panel_state.bufnr].buftype = "nofile"
	vim.bo[panel_state.bufnr].bufhidden = "wipe"
	vim.bo[panel_state.bufnr].swapfile = false
	vim.bo[panel_state.bufnr].filetype = "doubt-panel"

	vim.keymap.set("n", "q", function()
		if panel_state.help_winid and vim.api.nvim_win_is_valid(panel_state.help_winid) then
			help.close_help()
			return
		end
		if panel_state.winid and vim.api.nvim_win_is_valid(panel_state.winid) then
			vim.api.nvim_win_close(panel_state.winid, true)
		end
	end, { buffer = panel_state.bufnr, silent = true })

	vim.keymap.set("n", "<Esc>", help.close_help, {
		buffer = panel_state.bufnr,
		silent = true,
		desc = "Close doubt panel help",
	})

	vim.keymap.set("n", "?", help.open_help, {
		buffer = panel_state.bufnr,
		silent = true,
		desc = "Open doubt panel help",
	})

	vim.keymap.set("n", "r", navigation.close_help_then(function()
		ctx.api.refresh()
	end), { buffer = panel_state.bufnr, silent = true, desc = "Refresh doubt panel" })

	vim.keymap.set("n", "n", navigation.close_help_then(function()
		ctx.api.start_session()
	end), { buffer = panel_state.bufnr, silent = true, desc = "Start doubt session" })

	vim.keymap.set("n", "s", navigation.close_help_then(function()
		ctx.api.resume_session()
	end), { buffer = panel_state.bufnr, silent = true, desc = "Resume doubt session" })

	vim.keymap.set("n", "x", navigation.close_help_then(function()
		ctx.api.stop_session()
	end), { buffer = panel_state.bufnr, silent = true, desc = "Stop doubt session" })

	vim.keymap.set("n", "d", navigation.close_help_then(function()
		navigation.delete_line(ctx)
	end), { buffer = panel_state.bufnr, silent = true, desc = "Delete doubt item" })

	vim.keymap.set("n", "R", navigation.close_help_then(function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		local item = panel_state.lines[line]
		if not item or item.kind ~= "session" or not item.session_name then
			return
		end

		ctx.api.rename_session({
			name = item.session_name,
		})
	end), { buffer = panel_state.bufnr, silent = true, desc = "Rename doubt session" })

	vim.keymap.set("n", "<CR>", navigation.close_help_then(function()
		navigation.activate_line(ctx)
	end), { buffer = panel_state.bufnr, silent = true, desc = "Open doubt item" })

	vim.keymap.set("n", "<Tab>", navigation.close_help_then(function()
		navigation.cycle_claim(ctx, 1)
	end), { buffer = panel_state.bufnr, silent = true, desc = "Open next doubt claim" })

	vim.keymap.set("n", "<S-Tab>", navigation.close_help_then(function()
		navigation.cycle_claim(ctx, -1)
	end), { buffer = panel_state.bufnr, silent = true, desc = "Open previous doubt claim" })

	vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "WinEnter" }, {
		group = ctx.augroup,
		buffer = panel_state.bufnr,
		callback = function()
			navigation.sync_claim_focus(ctx)
			render.highlight_active_claim()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = ctx.augroup,
		buffer = panel_state.bufnr,
		callback = function()
			vim.schedule(help.close_help_if_panel_unfocused)
			if ctx.api.clear_focused_claim then
				ctx.api.clear_focused_claim()
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWinLeave", {
		group = ctx.augroup,
		buffer = panel_state.bufnr,
		callback = function()
			state_mod.restore_window_options(panel_state.winid)
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = ctx.augroup,
		buffer = panel_state.bufnr,
		once = true,
		callback = function()
			state_mod.restore_window_options(panel_state.winid)
			clear_panel_state(ctx)
		end,
	})

	local renderer = panel_api or render
	renderer.render(ctx)
	navigation.sync_claim_focus(ctx)
end

return M
