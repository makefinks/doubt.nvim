local M = {}

M.panel_state = {
	bufnr = nil,
	winid = nil,
	window_options = nil,
	return_bufnr = nil,
	help_bufnr = nil,
	help_winid = nil,
	help_ns = vim.api.nvim_create_namespace("doubt-panel-help"),
	lines = {},
	active_ns = vim.api.nvim_create_namespace("doubt-panel-active"),
}

function M.capture_window_options(winid)
	return {
		number = vim.wo[winid].number,
		relativenumber = vim.wo[winid].relativenumber,
		signcolumn = vim.wo[winid].signcolumn,
		foldcolumn = vim.wo[winid].foldcolumn,
		cursorline = vim.wo[winid].cursorline,
		winfixwidth = vim.wo[winid].winfixwidth,
	}
end

function M.restore_window_options(winid)
	local window_options = M.panel_state.window_options
	if not window_options or not winid or not vim.api.nvim_win_is_valid(winid) then
		return
	end

	for option, value in pairs(window_options) do
		vim.wo[winid][option] = value
	end

	M.panel_state.window_options = nil
end

return M
