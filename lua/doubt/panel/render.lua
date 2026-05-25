local line_builder = require("doubt.panel.lines")
local state_mod = require("doubt.panel.state")

local M = {}

local PANEL_HIGHLIGHT_PRIORITY = 100
local MARKDOWN_HIGHLIGHT_PRIORITY = 200
local ACTIVE_BORDER_PRIORITY = 300

local MARKDOWN_DELIMITERS = {
	{ marker = "`", hl_group = "DoubtPanelMarkdownCode" },
	{ marker = "**", hl_group = "DoubtPanelMarkdownBold" },
	{ marker = "__", hl_group = "DoubtPanelMarkdownBold" },
	{ marker = "~~", hl_group = "DoubtPanelMarkdownStrike" },
	{ marker = "*", hl_group = "DoubtPanelMarkdownItalic" },
	{ marker = "_", hl_group = "DoubtPanelMarkdownItalic", word_boundary = true },
}

local function panel_text_width(ctx, winid)
	local config_width = ctx.config.get().panel.width
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return config_width
	end

	local width = vim.api.nvim_win_get_width(winid)
	local info = vim.fn.getwininfo(winid)[1]
	return math.max(width - ((info and info.textoff) or 0), 1)
end

local function is_word_char(char)
	return char ~= "" and char:match("[%w_]") ~= nil
end

local function valid_marker_boundary(text, marker, open_start, close_start, close_end, word_boundary)
	local content_start = open_start + #marker
	if close_start <= content_start then
		return false
	end

	if text:sub(content_start, content_start):match("%s") or text:sub(close_start - 1, close_start - 1):match("%s") then
		return false
	end

	if word_boundary then
		if is_word_char(text:sub(open_start - 1, open_start - 1)) or is_word_char(text:sub(close_end, close_end)) then
			return false
		end
	end

	return true
end

local function find_markdown_span(text, index)
	for _, delimiter in ipairs(MARKDOWN_DELIMITERS) do
		local marker = delimiter.marker
		if text:sub(index, index + #marker - 1) == marker then
			local content_start = index + #marker
			local close_start = text:find(marker, content_start, true)
			if close_start then
				local close_end = close_start + #marker
				if valid_marker_boundary(text, marker, index, close_start, close_end, delimiter.word_boundary) then
					return {
						open_start = index,
						content_start = content_start,
						close_start = close_start,
						close_end = close_end,
						hl_group = delimiter.hl_group,
					}
				end
			end
		end
	end

	return nil
end

local function conceal_range(bufnr, ns, row, start_col, end_col)
	vim.api.nvim_buf_set_extmark(bufnr, ns, row, start_col, {
		end_row = row,
		end_col = end_col,
		conceal = "",
		priority = MARKDOWN_HIGHLIGHT_PRIORITY,
	})
end

local function add_markdown_highlights(bufnr, ns, row, text)
	local index = 1
	while index <= #text do
		local span = find_markdown_span(text, index)
		if span then
			conceal_range(bufnr, ns, row, span.open_start - 1, span.content_start - 1)
			vim.api.nvim_buf_set_extmark(bufnr, ns, row, span.content_start - 1, {
				end_row = row,
				end_col = span.close_start - 1,
				hl_group = span.hl_group,
				priority = MARKDOWN_HIGHLIGHT_PRIORITY,
			})
			conceal_range(bufnr, ns, row, span.close_start - 1, span.close_end - 1)
			index = span.close_end
		else
			index = index + 1
		end
	end
end

function M.render(ctx)
	local panel_state = state_mod.panel_state
	if not panel_state.bufnr or not vim.api.nvim_buf_is_valid(panel_state.bufnr) then
		return
	end

	local panel_width = panel_text_width(ctx, panel_state.winid)
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
				priority = PANEL_HIGHLIGHT_PRIORITY,
			})
		end

		if item.markdown then
			add_markdown_highlights(panel_state.bufnr, ctx.ns, idx - 1, item.text)
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
				sign_text = "▌",
				sign_hl_group = line_item.active_border_hl or line_item.active_hl or "DoubtPanelActiveClaim",
				priority = ACTIVE_BORDER_PRIORITY,
			})
		end
	end
end

return M
