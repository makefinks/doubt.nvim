local M = {}

local function centered_size(width, height)
	local columns = vim.o.columns
	local lines = vim.o.lines
	return {
		col = math.max(math.floor((columns - width) / 2), 0),
		row = math.max(math.floor((lines - height) / 2 - 1), 0),
	}
end

local function clamp(value, min_value, max_value)
	return math.min(math.max(value, min_value), max_value)
end

local function note_editor_width(opts)
	local width = opts.width or 50
	local prompt = opts.prompt or opts.title or "note"
	local default_width = vim.fn.strdisplaywidth(opts.default or "")
	width = math.max(width, vim.fn.strdisplaywidth(prompt) + 6, default_width + 4)
	return clamp(width, 24, math.max(vim.o.columns - 4, 24))
end

local function close_window(winid)
	if winid and vim.api.nvim_win_is_valid(winid) then
		vim.api.nvim_win_close(winid, true)
	end
end

local function stop_insert_mode()
	pcall(vim.cmd, "stopinsert")
	vim.schedule(function()
		pcall(vim.cmd, "stopinsert")
	end)
end

local function relative_path(path, root)
	path = vim.fs.normalize(path)
	root = vim.fs.normalize(root or vim.fn.getcwd())

	local prefix = root .. "/"
	if path:sub(1, #prefix) == prefix then
		return path:sub(#prefix + 1)
	end

	return path
end

local function should_skip_file_path(path)
	local normalized = vim.fs.normalize(path)
	return normalized:match("/%.git/")
		or normalized:match("/%.deps/")
		or normalized:match("/node_modules/")
		or normalized:match("/%.DS_Store$")
end

local function git_files(root)
	if vim.fn.executable("git") ~= 1 then
		return nil
	end

	local git_root = vim.fs.root(root, ".git")
	if not git_root then
		return nil
	end

	local ok, process = pcall(vim.system, {
		"git",
		"-C",
		git_root,
		"ls-files",
		"--cached",
		"--others",
		"--exclude-standard",
		"-z",
	}, { text = false })
	if not ok then
		return nil
	end

	local result = process:wait()
	if result.code ~= 0 then
		return nil
	end

	local files = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
	for index, path in ipairs(files) do
		files[index] = vim.fs.normalize(path)
	end
	table.sort(files)
	return files
end

local function workspace_files(root)
	root = vim.fs.normalize(root or vim.fn.getcwd())
	local files = git_files(root)
	if files then
		return files
	end

	files = vim.fs.find(function(name, path)
		local full_path = vim.fs.joinpath(path, name)
		return not should_skip_file_path(full_path)
	end, {
		limit = math.huge,
		path = root,
		type = "file",
	})

	for index, path in ipairs(files) do
		files[index] = relative_path(path, root)
	end
	table.sort(files)
	return files
end

function M.ask_text(opts, callback)
	opts = opts or {}
	local ok, Input = pcall(require, "nui.input")
	if not ok then
		vim.notify("doubt.nvim requires MunifTanjim/nui.nvim for prompts", vim.log.levels.ERROR, {
			title = "doubt.nvim",
		})
		callback(nil, true)
		return
	end

	local submitted = false

	local input = Input({
		relative = "cursor",
		position = { row = 1, col = 0 },
		size = { width = opts.width or 50 },
		border = {
			style = opts.border or "rounded",
			text = {
				top = opts.prompt or opts.title or " doubt ",
				top_align = "right",
			},
		},
	}, {
		prompt = " > ",
		default_value = opts.default or "",
		on_submit = function(value)
			submitted = true
			stop_insert_mode()
			callback(vim.trim(value or ""), false)
		end,
		on_close = function()
			stop_insert_mode()
			if submitted then
				return
			end

			callback(nil, true)
		end,
	})

	input:map("i", "<Esc>", function()
		input:unmount()
	end, { noremap = true })

	input:map("n", "<Esc>", function()
		input:unmount()
	end, { noremap = true })

	input:map("n", "q", function()
		input:unmount()
	end, { noremap = true })

	input:mount()
	vim.schedule(function()
		if not submitted then
			vim.cmd("startinsert!")
		end
	end)
end

function M.ask_command_text(opts, callback)
	opts = opts or {}
	local cancel_value = "\003doubt-cancel-" .. tostring(vim.uv.hrtime())
	local prompt = opts.prompt or opts.title or ""
	local default = opts.default or ""

	pcall(vim.fn.inputsave)
	local ok, value = pcall(vim.fn.input, {
		prompt = prompt,
		default = default,
		cancelreturn = cancel_value,
	})
	pcall(vim.fn.inputrestore)

	if not ok or value == cancel_value then
		callback(nil, true)
		return
	end

	callback(vim.trim(value or ""), false)
end

function M.pick_file_reference(opts, callback)
	opts = opts or {}
	local files = opts.files or workspace_files(opts.root or opts.cwd or vim.fn.getcwd())
	if vim.tbl_isempty(files) then
		vim.notify("No files found to reference", vim.log.levels.INFO, { title = "doubt.nvim" })
		callback(nil)
		return
	end

	vim.ui.select(files, {
		kind = "file",
		prompt = opts.file_prompt or "Reference file",
	}, callback)
end

function M.ask_note(opts, callback)
	opts = opts or {}
	local anchor_line = math.max(tonumber(opts.line) or 0, 0)
	local anchor_col = math.max(tonumber(opts.col) or 0, 0)
	local width = note_editor_width(opts)
	local height = clamp(math.floor(tonumber(opts.height) or 3), 1, math.max(vim.o.lines - 4, 1))
	local wrap_at = tonumber(opts.wrap_at)
	if wrap_at == nil then
		wrap_at = width - 1
	end
	local bufnr = vim.api.nvim_create_buf(false, true)
	local winid = vim.api.nvim_open_win(bufnr, true, {
		relative = "win",
		win = opts.winid or vim.api.nvim_get_current_win(),
		bufpos = { anchor_line, anchor_col },
		row = 1,
		col = 1,
		style = "minimal",
		border = opts.border or "rounded",
		width = width,
		height = height,
		title = opts.prompt or opts.title or "Edit note",
		title_pos = "left",
	})

	local finished = false
	local default_value = opts.default or ""
	local picker_open = false

	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].filetype = "doubt-note"
	vim.bo[bufnr].omnifunc = ""
	vim.bo[bufnr].completefunc = ""
	vim.b[bufnr].completion = false
	if wrap_at > 0 then
		vim.bo[bufnr].textwidth = math.max(math.floor(wrap_at), 1)
		if not vim.bo[bufnr].formatoptions:find("t", 1, true) then
			vim.bo[bufnr].formatoptions = vim.bo[bufnr].formatoptions .. "t"
		end
	end
	vim.wo[winid].wrap = false
	vim.wo[winid].number = false
	vim.wo[winid].relativenumber = false
	vim.wo[winid].signcolumn = "no"
	vim.wo[winid].cursorline = false

	local default_lines = vim.split(default_value, "\n", { plain = true })
	if vim.tbl_isempty(default_lines) then
		default_lines = { "" }
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, default_lines)
	local last_line = default_lines[#default_lines] or ""
	vim.api.nvim_win_set_cursor(winid, { #default_lines, vim.fn.strchars(last_line) })

	local function finish(value, cancelled)
		if finished then
			return
		end
		finished = true
		stop_insert_mode()
		close_window(winid)
		callback(value, cancelled)
	end

	local function submit()
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		finish(vim.trim(table.concat(lines, "\n")), false)
	end

	local function cancel()
		finish(nil, true)
	end

	local function insert_text_at_cursor(text, position)
		if finished or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winid) then
			return
		end

		local cursor = position or vim.api.nvim_win_get_cursor(winid)
		local row = cursor[1] - 1
		local col = cursor[2]
		vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { text })
		vim.api.nvim_win_set_cursor(winid, { cursor[1], col + #text })
	end

	local function resume_note_insert()
		if finished or not vim.api.nvim_win_is_valid(winid) then
			return
		end

		vim.api.nvim_set_current_win(winid)
		vim.cmd("startinsert!")
	end

	local function pick_file_reference()
		local insert_position = vim.api.nvim_win_get_cursor(winid)
		picker_open = true
		M.pick_file_reference(opts, function(path)
			picker_open = false
			if path then
				insert_text_at_cursor("`@" .. path .. "` ", insert_position)
			end
			vim.schedule(resume_note_insert)
		end)
	end

	local function map(mode, lhs, rhs)
		vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, nowait = true, silent = true })
	end

	map("i", "<CR>", submit)
	map("n", "<CR>", submit)
	if opts.file_references ~= false then
		map("i", "@", pick_file_reference)
	end
	map("i", "<Esc>", cancel)
	map("n", "<Esc>", cancel)
	map("n", "q", cancel)

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = bufnr,
		callback = function()
			if picker_open then
				return
			end

			if not finished then
				cancel()
			end
		end,
	})

	vim.schedule(function()
		if not finished and winid and vim.api.nvim_win_is_valid(winid) then
			vim.cmd("startinsert!")
		end
	end)

	return {
		bufnr = bufnr,
		winid = winid,
		cancel = cancel,
		submit = submit,
	}
end

function M.ask_checklist(opts, callback)
	opts = opts or {}
	local items = vim.deepcopy(opts.items or {})
	local state = {}
	for idx, item in ipairs(items) do
		state[idx] = item.selected == true
	end

	local title = opts.title or "select items"
	local hint = opts.hint or "<Space> toggle  <CR> confirm  q close"
	local width = math.max(opts.width or 50, #title + 4, #hint + 4)
	for _, item in ipairs(items) do
		width = math.max(width, #(item.label or "") + 8)
	end
	local height = math.max(#items + 2, 4)
	local position = centered_size(width, height)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local winid = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		style = "minimal",
		border = opts.border or "rounded",
		width = width,
		height = height,
		row = position.row,
		col = position.col,
		title = title,
		title_pos = "center",
	})

	local finished = false

	local function selected_values()
		local values = {}
		for idx, item in ipairs(items) do
			if state[idx] then
				table.insert(values, item.value)
			end
		end
		return values
	end

	local function close(values, cancelled)
		if finished then
			return
		end
		finished = true
		if winid and vim.api.nvim_win_is_valid(winid) then
			vim.api.nvim_win_close(winid, true)
		end
		callback(values, cancelled)
	end

	local function render()
		local lines = { hint }
		for idx, item in ipairs(items) do
			local mark = state[idx] and "[x]" or "[ ]"
			table.insert(lines, string.format("%s %s", mark, item.label or item.value or ""))
		end

		vim.bo[bufnr].modifiable = true
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.bo[bufnr].modifiable = false
		vim.bo[bufnr].buftype = "nofile"
		vim.bo[bufnr].bufhidden = "wipe"
		vim.bo[bufnr].swapfile = false
		vim.bo[bufnr].modifiable = false
		vim.wo[winid].cursorline = true
		vim.wo[winid].number = false
		vim.wo[winid].relativenumber = false
		vim.wo[winid].signcolumn = "no"
		vim.api.nvim_win_set_cursor(winid, { math.max(vim.api.nvim_win_get_cursor(winid)[1], 2), 0 })
	end

	local function toggle_current()
		local line = vim.api.nvim_win_get_cursor(winid)[1]
		if line < 2 then
			return
		end
		local idx = line - 1
		if not items[idx] then
			return
		end
		state[idx] = not state[idx]
		render()
		vim.api.nvim_win_set_cursor(winid, { line, 0 })
	end

	render()
	if #items > 0 then
		vim.api.nvim_win_set_cursor(winid, { 2, 0 })
	end

	local function map(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true, silent = true })
	end

	map("<Space>", toggle_current)
	map("x", toggle_current)
	map("<CR>", function()
		close(selected_values(), false)
	end)
	map("q", function()
		close(nil, true)
	end)
	map("<Esc>", function()
		close(nil, true)
	end)

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = bufnr,
		once = true,
		callback = function()
			if not finished then
				close(nil, true)
			end
		end,
	})
end

return M
