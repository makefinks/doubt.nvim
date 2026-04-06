local line_builder = require("doubt.panel.lines")
local state_mod = require("doubt.panel.state")

local M = {}

function M.render(ctx)
	local panel_state = state_mod.panel_state
	if not panel_state.bufnr or not vim.api.nvim_buf_is_valid(panel_state.bufnr) then
		return
	end

	local panel_width = panel_state.winid and vim.api.nvim_win_get_width(panel_state.winid) or ctx.config.get().panel.width
	panel_state.lines = line_builder.build_lines(ctx, panel_width)
	local text = vim.tbl_map(function(item)
		return item.text
	end, panel_state.lines)

	vim.bo[panel_state.bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(panel_state.bufnr, 0, -1, false, text)
	vim.bo[panel_state.bufnr].modifiable = false

	vim.api.nvim_buf_clear_namespace(panel_state.bufnr, ctx.ns, 0, -1)
	for idx, item in ipairs(panel_state.lines) do
		local base_hl = ({
			title = "DoubtPanelTitle",
			section = "DoubtPanelSection",
			muted = "DoubtPanelMuted",
		})[item.kind]

		if base_hl then
			vim.api.nvim_buf_set_extmark(panel_state.bufnr, ctx.ns, idx - 1, 0, {
				line_hl_group = base_hl,
			})
		end

		for _, highlight in ipairs(item.highlights or {}) do
			vim.api.nvim_buf_set_extmark(panel_state.bufnr, ctx.ns, idx - 1, highlight.start_col, {
				end_row = idx - 1,
				end_col = highlight.end_col,
				hl_group = highlight.hl_group,
			})
		end
	end

	M.highlight_active_claim()
end

function M.highlight_active_claim()
	local panel_state = state_mod.panel_state
	if not panel_state.bufnr or not vim.api.nvim_buf_is_valid(panel_state.bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(panel_state.bufnr, panel_state.active_ns, 0, -1)
	if not panel_state.winid or not vim.api.nvim_win_is_valid(panel_state.winid) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(panel_state.winid)
	local item = panel_state.lines[cursor[1]]
	if not item or item.kind ~= "claim" or not item.id then
		return
	end

	for idx, line_item in ipairs(panel_state.lines) do
		if line_item.kind == "claim" and line_item.id == item.id then
			vim.api.nvim_buf_set_extmark(panel_state.bufnr, panel_state.active_ns, idx - 1, 0, {
				line_hl_group = line_item.active_hl or "DoubtPanelActiveClaim",
			})
		end
	end
end

return M
