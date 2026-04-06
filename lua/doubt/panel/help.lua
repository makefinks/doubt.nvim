local state_mod = require("doubt.panel.state")

local M = {}

local function build_help_content()
	local function center_key(text, width)
		local total_padding = math.max(width - #text, 0)
		local left_padding = math.floor(total_padding / 2)
		local right_padding = total_padding - left_padding
		return string.rep(" ", left_padding) .. text .. string.rep(" ", right_padding), left_padding
	end

	local sections = {
		{
			title = "Navigate",
			bindings = {
				{ "<CR>", "Open selected item" },
				{ "<Tab>", "Open next claim" },
				{ "<S-Tab>", "Open previous claim" },
			},
		},
		{
			title = "Session",
			bindings = {
				{ "n", "Start session" },
				{ "s", "Resume session" },
				{ "x", "Stop active session" },
			},
		},
		{
			title = "Manage",
			bindings = {
				{ "d", "Delete selected item" },
				{ "R", "Rename selected session" },
				{ "r", "Refresh panel" },
				{ "?", "Open this help" },
				{ "q", "Close panel" },
			},
		},
	}

	local lines = {
		" doubt.nvim panel help ",
		"",
	}
	local highlights = {
		{ line = 0, start_col = 0, end_col = #lines[1], hl_group = "DoubtPanelHelpTitle" },
	}

	local key_cell_width = 8
	for _, section in ipairs(sections) do
		table.insert(lines, string.upper(section.title))
		table.insert(highlights, {
			line = #lines - 1,
			start_col = 0,
			end_col = #lines[#lines],
			hl_group = "DoubtPanelHelpSection",
		})

		for _, binding in ipairs(section.bindings) do
			local key = binding[1]
			local description = binding[2]
			local key_cell, key_left_padding = center_key(key, key_cell_width)
			local prefix = string.format("  [%s]  ", key_cell)
			local row = prefix .. description
			table.insert(lines, row)

			local row_index = #lines - 1
			local key_start = 3 + key_left_padding
			table.insert(highlights, {
				line = row_index,
				start_col = key_start,
				end_col = key_start + #key,
				hl_group = "DoubtPanelKey",
			})
			table.insert(highlights, {
				line = row_index,
				start_col = #prefix,
				end_col = #row,
				hl_group = "DoubtPanelHelpText",
			})
		end

		table.insert(lines, "")
	end

	table.insert(lines, string.rep("-", 38))
	table.insert(highlights, {
		line = #lines - 1,
		start_col = 0,
		end_col = #lines[#lines],
		hl_group = "DoubtPanelHelpBorder",
	})
	table.insert(lines, "q or <Esc> closes this help")
	table.insert(highlights, {
		line = #lines - 1,
		start_col = 0,
		end_col = #lines[#lines],
		hl_group = "DoubtPanelMuted",
	})

	return lines, highlights
end

function M.close_help()
	local panel_state = state_mod.panel_state
	if panel_state.help_winid and vim.api.nvim_win_is_valid(panel_state.help_winid) then
		vim.api.nvim_win_close(panel_state.help_winid, true)
	end

	panel_state.help_bufnr = nil
	panel_state.help_winid = nil
end

function M.close_help_if_panel_unfocused()
	local panel_state = state_mod.panel_state
	if not panel_state.help_winid or not vim.api.nvim_win_is_valid(panel_state.help_winid) then
		return
	end

	local current_win = vim.api.nvim_get_current_win()
	if current_win == panel_state.help_winid then
		return
	end

	if panel_state.winid and vim.api.nvim_win_is_valid(panel_state.winid) and current_win == panel_state.winid then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()
	if panel_state.bufnr and vim.api.nvim_buf_is_valid(panel_state.bufnr) and current_buf == panel_state.bufnr then
		return
	end

	M.close_help()
end

function M.open_help()
	local panel_state = state_mod.panel_state
	if not panel_state.bufnr or not vim.api.nvim_buf_is_valid(panel_state.bufnr) then
		return
	end

	M.close_help()

	local lines, highlights = build_help_content()

	local content_width = 0
	for _, line in ipairs(lines) do
		content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
	end

	local width = math.max(46, content_width + 4)
	width = math.min(width, math.max(vim.o.columns - 4, 20))
	local height = math.min(#lines + 2, math.max(vim.o.lines - 4, 6))
	local row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0)
	local col = math.max(math.floor((vim.o.columns - width) / 2), 0)

	panel_state.help_bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[panel_state.help_bufnr].buftype = "nofile"
	vim.bo[panel_state.help_bufnr].bufhidden = "wipe"
	vim.bo[panel_state.help_bufnr].swapfile = false
	vim.bo[panel_state.help_bufnr].filetype = "doubt-panel-help"

	vim.api.nvim_buf_set_lines(panel_state.help_bufnr, 0, -1, false, lines)
	vim.bo[panel_state.help_bufnr].modifiable = false
	vim.api.nvim_buf_clear_namespace(panel_state.help_bufnr, panel_state.help_ns, 0, -1)
	for _, highlight in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(panel_state.help_bufnr, panel_state.help_ns, highlight.line, highlight.start_col, {
			end_row = highlight.line,
			end_col = highlight.end_col,
			hl_group = highlight.hl_group,
		})
	end

	panel_state.help_winid = vim.api.nvim_open_win(panel_state.help_bufnr, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		border = "rounded",
		style = "minimal",
		zindex = 160,
	})
	vim.wo[panel_state.help_winid].cursorline = false
	vim.wo[panel_state.help_winid].wrap = false
	vim.wo[panel_state.help_winid].winhighlight = "NormalFloat:DoubtPanelHelpNormal,FloatBorder:DoubtPanelHelpBorder"

	vim.keymap.set("n", "q", M.close_help, { buffer = panel_state.help_bufnr, silent = true })
	vim.keymap.set("n", "<Esc>", M.close_help, { buffer = panel_state.help_bufnr, silent = true })
end

return M
