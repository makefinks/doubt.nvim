local claims = require("doubt.claims")

local M = {}

local deps = nil
local active = nil
local augroup = vim.api.nvim_create_augroup("doubt.nvim.inline-editor", { clear = true })

local function valid_buf(bufnr)
	return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(winid)
	return winid and vim.api.nvim_win_is_valid(winid)
end

local function source_window(bufnr, preferred)
	if valid_win(preferred) and vim.api.nvim_win_get_buf(preferred) == bufnr then
		return preferred
	end
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		if valid_win(winid) then
			return winid
		end
	end
	return nil
end

local function editor_note()
	if not active or not valid_buf(active.editor_bufnr) then
		return ""
	end
	return claims.normalize_note(table.concat(vim.api.nvim_buf_get_lines(active.editor_bufnr, 0, -1, false), "\n"))
end

local function body_width()
	local configured = tonumber((deps.config.get().inline_notes or {}).max_width) or 80
	local meta = claims.meta(active.claim.kind) or {}
	local prefix = (deps.config.get().inline_notes or {}).prefix or ""
	local available = math.max(vim.api.nvim_win_get_width(active.source_winid)
		- vim.fn.strdisplaywidth(prefix .. (meta.inline_label or ""))
		- 1, 1)
	local maximum = configured <= 0 and available or math.min(configured, available)
	local minimum = math.min(math.max(tonumber((deps.config.get().input or {}).inline_min_width) or 12, 1), maximum)
	local lines = vim.api.nvim_buf_get_lines(active.editor_bufnr, 0, -1, false)
	local cursor = valid_win(active.editor_winid)
		and vim.api.nvim_win_get_cursor(active.editor_winid)
		or { #lines, #(lines[#lines] or "") }
	local desired = minimum
	for index, line in ipairs(lines) do
		local at_line_end = cursor[2] >= math.max(#line - 1, 0)
		local cursor_cell = index == cursor[1] and at_line_end and 1 or 0
		desired = math.max(desired, vim.fn.strdisplaywidth(line) + cursor_cell)
	end
	return math.max(1, math.min(desired, maximum))
end

local function editor_row_count(width)
	local rows = 0
	local lines = vim.api.nvim_buf_get_lines(active.editor_bufnr, 0, -1, false)
	local cursor = valid_win(active.editor_winid)
		and vim.api.nvim_win_get_cursor(active.editor_winid)
		or { #lines, #(lines[#lines] or "") }
	for index, line in ipairs(lines) do
		local at_line_end = cursor[2] >= math.max(#line - 1, 0)
		local cursor_cell = index == cursor[1] and at_line_end and 1 or 0
		rows = rows + math.max(1, math.ceil((vim.fn.strdisplaywidth(line) + cursor_cell) / width))
	end
	return math.max(rows, 1)
end

local function editor_rows(width)
	local rows = editor_row_count(width)
	local max_height = math.max(tonumber((deps.config.get().input or {}).inline_max_height) or 6, 1)
	return math.min(rows, max_height)
end

local function edit_state(width, rows)
	return {
		body_width = width,
		bufnr = active.source_bufnr,
		claim = active.claim,
		draft = active.draft,
		rows = rows,
	}
end

local function window_config(width, rows)
	local meta = claims.meta(active.claim.kind) or {}
	local prefix = (deps.config.get().inline_notes or {}).prefix or ""
	local position = vim.fn.screenpos(active.source_winid, active.claim.start_line + 1, 1)
	local source_row = math.max(position.row or 1, rows + 2)
	local source_col = math.max(position.col or 1, 1)
	return {
		relative = "editor",
		anchor = "NW",
		row = source_row - rows - 2,
		col = source_col + vim.fn.strdisplaywidth(prefix .. (meta.inline_label or "")),
		width = width,
		height = rows,
		border = "none",
		style = "minimal",
		focusable = true,
		zindex = 60,
	}
end

local function show_full_note(width, rows, schedule)
	if not active or not valid_win(active.editor_winid) or editor_row_count(width) > rows then
		return
	end
	local winid = active.editor_winid
	local function restore_topline()
		if not active or active.editor_winid ~= winid or not valid_win(winid) then
			return
		end
		vim.api.nvim_win_call(winid, function()
			local view = vim.fn.winsaveview()
			view.topline = 1
			vim.fn.winrestview(view)
		end)
	end
	if schedule then
		vim.schedule(restore_topline)
	else
		restore_topline()
	end
end

local function refresh_layout()
	if not active or not valid_buf(active.editor_bufnr) or not valid_win(active.source_winid) then
		return
	end
	local width = body_width()
	local rows = editor_rows(width)
	active.body_width = width
	active.rows = rows
	deps.ctx.set_inline_edit(edit_state(width, rows))
	deps.ctx.refresh_ui(active.source_bufnr)
	if valid_win(active.editor_winid) then
		vim.api.nvim_win_set_config(active.editor_winid, window_config(width, rows))
		vim.api.nvim_win_set_width(active.editor_winid, width)
		vim.api.nvim_win_set_height(active.editor_winid, rows)
		show_full_note(width, rows, true)
	end
end

local function clear(restore_source)
	if not active then
		return nil
	end
	local closing = active
	active = nil
	vim.api.nvim_clear_autocmds({ group = augroup })
	deps.ctx.set_inline_edit(nil)
	if valid_win(closing.editor_winid) then
		pcall(vim.api.nvim_win_close, closing.editor_winid, true)
	end
	if valid_buf(closing.editor_bufnr) then
		pcall(vim.api.nvim_buf_delete, closing.editor_bufnr, { force = true })
	end
	if restore_source and valid_win(closing.source_winid) then
		pcall(vim.api.nvim_set_current_win, closing.source_winid)
		pcall(vim.api.nvim_win_set_cursor, closing.source_winid, closing.source_cursor)
	end
	pcall(vim.cmd, "stopinsert")
	return closing
end

function M.submit()
	if not active then
		return false
	end
	local note = editor_note()
	local discard = active.discard_empty and note == ""
	local closing = clear(true)
	if not discard and closing.on_submit then
		closing.on_submit(note)
	else
		deps.ctx.refresh_ui(closing.source_bufnr)
	end
	return true
end

function M.cancel()
	if not active then
		return false
	end
	local closing = clear(true)
	deps.ctx.refresh_ui(closing.source_bufnr)
	if closing.on_cancel then
		closing.on_cancel()
	end
	return true
end

local function set_mappings(bufnr)
	local opts = { buffer = bufnr, nowait = true, silent = true }
	for _, mode in ipairs({ "i", "n" }) do
		vim.keymap.set(mode, "<S-CR>", M.submit, vim.tbl_extend("force", opts, { desc = "Save doubt claim note" }))
	end
	vim.keymap.set("n", "ZZ", M.submit, vim.tbl_extend("force", opts, { desc = "Save doubt claim note" }))
	vim.keymap.set("n", "ZQ", M.cancel, vim.tbl_extend("force", opts, { desc = "Cancel doubt claim note edit" }))
	vim.keymap.set("n", "q", M.cancel, vim.tbl_extend("force", opts, { desc = "Cancel doubt claim note edit" }))
	vim.keymap.set("n", "<Esc>", M.cancel, vim.tbl_extend("force", opts, { desc = "Cancel doubt claim note edit" }))
	vim.keymap.set("i", "@", function()
		if not active or not deps.input then
			return
		end
		local editor_winid = active.editor_winid
		local position = vim.api.nvim_win_get_cursor(editor_winid)
		active.picker_open = true
		deps.input.pick_file_reference({}, function(path)
			if not active or active.editor_winid ~= editor_winid then
				return
			end
			active.picker_open = false
			if path then
				local row = position[1] - 1
				local text = "`@" .. path .. "` "
				vim.api.nvim_buf_set_text(active.editor_bufnr, row, position[2], row, position[2], { text })
				vim.api.nvim_win_set_cursor(editor_winid, { position[1], position[2] + #text })
			end
			vim.schedule(function()
				if active and valid_win(editor_winid) then
					vim.api.nvim_set_current_win(editor_winid)
					vim.cmd("startinsert!")
					refresh_layout()
				end
			end)
		end)
	end, vim.tbl_extend("force", opts, { desc = "Insert a file reference" }))
end

local function install_autocmds()
	vim.api.nvim_clear_autocmds({ group = augroup })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = active.editor_bufnr,
		callback = refresh_layout,
	})
	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		buffer = active.editor_bufnr,
		callback = function()
			if active and not active.picker_open then
				vim.schedule(M.cancel)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "BufUnload" }, {
		group = augroup,
		buffer = active.source_bufnr,
		callback = function()
			if active then
				vim.schedule(M.cancel)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinScrolled", {
		group = augroup,
		callback = function()
			if active then
				vim.schedule(refresh_layout)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			if not active then
				return
			end
			local closed = tonumber(args.match)
			if closed == active.editor_winid then
				vim.schedule(M.cancel)
				return
			end
			if closed == active.source_winid then
				vim.schedule(function()
					if not active then
						return
					end
					local replacement = source_window(active.source_bufnr)
					if not replacement then
						M.cancel()
						return
					end
					active.source_winid = replacement
					active.source_cursor = vim.api.nvim_win_get_cursor(replacement)
					refresh_layout()
				end)
			end
		end,
	})
end

function M.open(opts)
	opts = opts or {}
	if not deps or not valid_buf(opts.bufnr) or type(opts.claim) ~= "table" then
		return false
	end
	local winid = source_window(opts.bufnr, opts.winid)
	if not winid then
		return false
	end

	M.cancel()
	local editor_bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[editor_bufnr].buftype = "nofile"
	vim.bo[editor_bufnr].bufhidden = "wipe"
	vim.bo[editor_bufnr].swapfile = false
	vim.bo[editor_bufnr].filetype = "doubt-note"
	vim.b[editor_bufnr].doubt_inline_editor = true
	local lines = vim.split(opts.default or "", "\n", { plain = true })
	if vim.tbl_isempty(lines) then
		lines = { "" }
	end
	vim.api.nvim_buf_set_lines(editor_bufnr, 0, -1, false, lines)

	active = {
		claim = vim.deepcopy(opts.claim),
		discard_empty = opts.discard_empty == true,
		draft = opts.draft == true,
		editor_bufnr = editor_bufnr,
		editor_winid = nil,
		on_cancel = opts.on_cancel,
			on_submit = opts.on_submit,
			picker_open = false,
		source_bufnr = opts.bufnr,
		source_cursor = vim.api.nvim_win_get_cursor(winid),
		source_winid = winid,
	}

	local width = body_width()
	local rows = editor_rows(width)
	active.body_width = width
	active.rows = rows
	deps.ctx.set_inline_edit(edit_state(width, rows))
	deps.ctx.refresh_ui(opts.bufnr)
	active.editor_winid = vim.api.nvim_open_win(editor_bufnr, true, window_config(width, rows))
	local meta = claims.meta(active.claim.kind) or {}
	vim.wo[active.editor_winid].winhighlight = "Normal:" .. (meta.inline_text_hl or "Normal")
	vim.wo[active.editor_winid].number = false
	vim.wo[active.editor_winid].relativenumber = false
	vim.wo[active.editor_winid].signcolumn = "no"
	vim.wo[active.editor_winid].foldcolumn = "0"
	vim.wo[active.editor_winid].wrap = true
	vim.wo[active.editor_winid].linebreak = false
	vim.wo[active.editor_winid].scrolloff = 0
	vim.wo[active.editor_winid].sidescrolloff = 0
	local last_line = lines[#lines] or ""
	vim.api.nvim_win_set_cursor(active.editor_winid, { #lines, #last_line })
	show_full_note(width, rows, false)
	set_mappings(editor_bufnr)
	install_autocmds()
	vim.cmd("startinsert!")
	return true
end

function M.close()
	return M.cancel()
end

function M.refresh()
	if not active then
		return false
	end
	refresh_layout()
	return true
end

function M.setup(next_deps)
	if active then
		M.cancel()
	end
	deps = next_deps
	vim.api.nvim_clear_autocmds({ group = augroup })
end

function M.status()
	if not active then
		return { active = false }
	end
	return {
		active = true,
		body_width = active.body_width,
		bufnr = active.editor_bufnr,
		claim = vim.deepcopy(active.claim),
		draft = active.draft,
		rows = active.rows,
		source_bufnr = active.source_bufnr,
		source_winid = active.source_winid,
		winid = active.editor_winid,
	}
end

return M
