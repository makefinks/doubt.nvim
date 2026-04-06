local M = {}

local function line_byte_length(bufnr, line)
	local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
	return #text
end

local function clamp_col(bufnr, line, col)
	col = math.max(col or 0, 0)
	return math.min(col, line_byte_length(bufnr, line))
end

local function tuple_is_before(a_line, a_col, b_line, b_col)
	if a_line ~= b_line then
		return a_line < b_line
	end
	return a_col < b_col
end

local function char_end_col(bufnr, line, col)
	local max_col = line_byte_length(bufnr, line)
	col = math.min(math.max(col, 0), max_col)
	if col >= max_col then
		return max_col
	end

	local text = vim.api.nvim_buf_get_text(bufnr, line, col, line, col + 1, {})[1] or ""
	return col + math.max(#text, 1)
end

function M.normalize_line_range(start_line, end_line)
	start_line = math.max(start_line or 0, 0)
	end_line = math.max(end_line or start_line, 0)
	if end_line < start_line then
		start_line, end_line = end_line, start_line
	end

	return start_line, end_line
end

function M.normalize_position_range(start_line, start_col, end_line, end_col)
	start_line = math.max(start_line or 0, 0)
	end_line = math.max(end_line or start_line, 0)
	start_col = math.max(start_col or 0, 0)
	end_col = end_col == nil and nil or math.max(end_col, 0)

	if end_line < start_line then
		start_line, end_line = end_line, start_line
		start_col, end_col = end_col or 0, start_col
		return start_line, start_col, end_line, end_col
	end

	if end_line == start_line and end_col ~= nil and end_col < start_col then
		start_col, end_col = end_col, start_col
	end

	return start_line, start_col, end_line, end_col
end

function M.current_range_from_command(command_opts)
	local line1 = command_opts.line1 and (command_opts.line1 - 1) or nil
	local line2 = command_opts.line2 and (command_opts.line2 - 1) or nil
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
	return M.normalize_line_range(line1 or cursor_line, line2 or line1 or cursor_line)
end

function M.current_span_from_command(command_opts, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local start_line, end_line = M.current_range_from_command(command_opts)
	local start_col = 0
	local end_col = line_byte_length(bufnr, end_line)
	return M.normalize_position_range(start_line, start_col, end_line, end_col)
end

function M.current_visual_range(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local anchor = vim.fn.getpos("v")
	local cursor = vim.api.nvim_win_get_cursor(0)
	return M.normalize_line_range(anchor[2] - 1, cursor[1] - 1)
end

function M.current_visual_span(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local mode = vim.fn.mode()
	local anchor = vim.fn.getpos("v")
	local cursor = vim.fn.getpos(".")

	local anchor_line = math.max(anchor[2] - 1, 0)
	local anchor_col = math.max(anchor[3] - 1, 0)
	local cursor_line = math.max(cursor[2] - 1, 0)
	local cursor_col = math.max(cursor[3] - 1, 0)

	if mode == "V" or mode == "\22" then
		local start_line, end_line = M.normalize_line_range(anchor_line, cursor_line)
		return M.normalize_position_range(start_line, 0, end_line, line_byte_length(bufnr, end_line))
	end

	local start_line, start_col, end_line, end_col = anchor_line, anchor_col, cursor_line, cursor_col
	if tuple_is_before(end_line, end_col, start_line, start_col) then
		start_line, end_line = end_line, start_line
		start_col, end_col = end_col, start_col
	end

	start_col = clamp_col(bufnr, start_line, start_col)
	end_col = clamp_col(bufnr, end_line, end_col)
	end_col = char_end_col(bufnr, end_line, end_col)

	if start_line == end_line and end_col <= start_col then
		end_col = math.min(start_col + 1, line_byte_length(bufnr, end_line))
	end

	return M.normalize_position_range(start_line, start_col, end_line, end_col)
end

return M
