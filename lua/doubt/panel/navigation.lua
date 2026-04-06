local help = require("doubt.panel.help")
local render = require("doubt.panel.render")
local state_mod = require("doubt.panel.state")

local M = {}

function M.activate_line(ctx)
	local panel_state = state_mod.panel_state
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local item = panel_state.lines[line]
	if not item then
		return
	end

	if item.session_name then
		ctx.api.resume_session({ name = item.session_name, quiet = true })
		return
	end

	if not item.path then
		return
	end

	local panel_win = panel_state.winid
	vim.cmd("wincmd p")
	vim.cmd.edit(vim.fn.fnameescape(item.path))
	if item.line then
		vim.api.nvim_win_set_cursor(0, { item.line, item.col or 0 })
		vim.cmd("normal! zz")
	end
	if panel_win and vim.api.nvim_win_is_valid(panel_win) then
		vim.api.nvim_set_current_win(panel_win)
	end
end

function M.sync_claim_focus(ctx)
	local panel_state = state_mod.panel_state
	local clear_focus = ctx.api and ctx.api.clear_focused_claim or nil
	local focus_claim = ctx.api and ctx.api.focus_claim or nil

	if not panel_state.winid or not vim.api.nvim_win_is_valid(panel_state.winid) then
		if clear_focus then
			clear_focus()
		end
		return
	end

	local item = panel_state.lines[vim.api.nvim_win_get_cursor(panel_state.winid)[1]]
	if item and item.kind == "claim" and item.id and item.path then
		if focus_claim then
			focus_claim({
				id = item.id,
				path = item.path,
				session_name = ctx.state.active_session_name(),
			})
		end
		return
	end

	if clear_focus then
		clear_focus()
	end
end

function M.cycle_claim(ctx, step)
	local panel_state = state_mod.panel_state
	if not panel_state.winid or not vim.api.nvim_win_is_valid(panel_state.winid) then
		return
	end

	local line_count = #panel_state.lines
	if line_count == 0 then
		return
	end

	local start_line = vim.api.nvim_win_get_cursor(panel_state.winid)[1]
	local current_item = panel_state.lines[start_line]
	local current_claim_id = current_item and current_item.kind == "claim" and current_item.id or nil
	for offset = 1, line_count do
		local line = ((start_line - 1 + (offset * step)) % line_count) + 1
		local item = panel_state.lines[line]
		if item and item.kind == "claim" and item.id and item.id ~= current_claim_id then
			while line > 1 do
				local previous_item = panel_state.lines[line - 1]
				if not previous_item or previous_item.kind ~= "claim" or previous_item.id ~= item.id then
					break
				end
				line = line - 1
			end

			vim.api.nvim_win_set_cursor(panel_state.winid, { line, 0 })
			render.highlight_active_claim()
			M.activate_line(ctx)
			return
		end
	end
end

function M.delete_line(ctx)
	local panel_state = state_mod.panel_state
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local item = panel_state.lines[line]
	if not item then
		return
	end

	if item.kind == "claim" and item.path and item.id then
		ctx.api.delete_claim({
			path = item.path,
			id = item.id,
		})
		return
	end

	if item.kind == "file" and item.path then
		ctx.api.delete_file({
			path = item.path,
		})
		return
	end

	if item.kind == "session" and item.session_name and not item.active then
		ctx.api.delete_session({ name = item.session_name })
	end
end

function M.close_help_then(fn)
	return function()
		help.close_help()
		fn()
	end
end

return M
