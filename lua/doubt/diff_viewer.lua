local M = {}

local function builtin_viewer(payload)
	vim.cmd("tabnew")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(bufnr, string.format("doubt://%s/%s.diff", payload.run.run_id, payload.claim_id))
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].filetype = "diff"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, payload.patch_lines)
	vim.bo[bufnr].modifiable = false
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.keymap.set("n", "q", "<Cmd>tabclose<CR>", {
		buffer = bufnr,
		desc = "Close doubt claim diff",
		silent = true,
	})
	return true
end

local function append_hunk(pair, hunk)
	if #pair.before > 0 or #pair.after > 0 then
		table.insert(pair.before, "")
		table.insert(pair.after, "")
	end
	for index, line in ipairs(hunk.lines or {}) do
		if index > 1 then
			local marker = line:sub(1, 1)
			local content = line:sub(2)
			if marker == " " then
				table.insert(pair.before, content)
				table.insert(pair.after, content)
			elseif marker == "-" then
				table.insert(pair.before, content)
			elseif marker == "+" then
				table.insert(pair.after, content)
			end
		end
	end
end

local function build_file_pairs(matches)
	local by_path = {}
	local has_file_level_change = false
	for _, match in ipairs(matches or {}) do
		if not match.hunk then
			has_file_level_change = true
		else
			local path = match.file.new_path or match.file.old_path or match.file.path
			if type(path) == "string" and path ~= "" then
				local pair = by_path[path]
				if not pair then
					pair = { path = path, before = {}, after = {} }
					by_path[path] = pair
				end
				append_hunk(pair, match.hunk)
			end
		end
	end
	local pairs = vim.tbl_values(by_path)
	table.sort(pairs, function(left, right)
		return left.path < right.path
	end)
	return pairs, has_file_level_change
end

local function write_pair(root, pair)
	for _, side in ipairs({ "before", "after" }) do
		local path = vim.fs.joinpath(root, side, pair.path)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		local ok, result = pcall(vim.fn.writefile, pair[side], path)
		if not ok or result ~= 0 then
			return false
		end
	end
	return true
end

local function cleanup_directory(path)
	if path and path ~= "" then
		pcall(vim.fn.delete, path, "rf")
	end
end

local function cleanup_on_event(root, pattern)
	vim.api.nvim_create_autocmd("User", {
		pattern = pattern,
		once = true,
		callback = function()
			cleanup_directory(root)
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		callback = function()
			cleanup_directory(root)
		end,
	})
end

local function codediff_viewer(payload)
	if vim.fn.exists(":CodeDiff") ~= 2 then
		return false, "CodeDiff is not available"
	end
	if payload.has_file_level_change or vim.tbl_isempty(payload.files) then
		return false, "CodeDiff cannot represent this claim's non-textual changes"
	end

	local root = vim.fn.tempname()
	vim.fn.mkdir(vim.fs.joinpath(root, "before"), "p")
	vim.fn.mkdir(vim.fs.joinpath(root, "after"), "p")
	for _, pair in ipairs(payload.files) do
		if not write_pair(root, pair) then
			cleanup_directory(root)
			return false, "Unable to prepare files for CodeDiff"
		end
	end

	local ok, err = pcall(vim.cmd, string.format(
		"CodeDiff dir %s %s",
		vim.fn.fnameescape(vim.fs.joinpath(root, "before")),
		vim.fn.fnameescape(vim.fs.joinpath(root, "after"))
	))
	if not ok then
		cleanup_directory(root)
		return false, tostring(err)
	end

	cleanup_on_event(root, "CodeDiffClose")
	return true
end

local function run_git(root, args)
	local command = { "git", "-C", root }
	vim.list_extend(command, args)
	local result = vim.system(command, { text = true }):wait()
	if result.code ~= 0 then
		return nil, vim.trim(result.stderr or "")
	end
	return vim.trim(result.stdout or "")
end

local function write_side(root, pairs, side)
	for _, pair in ipairs(pairs) do
		local path = vim.fs.joinpath(root, pair.path)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		local ok, result = pcall(vim.fn.writefile, pair[side], path)
		if not ok or result ~= 0 then
			return false
		end
	end
	return true
end

local function diffview_viewer(payload)
	if vim.fn.exists(":DiffviewOpen") ~= 2 then
		return false, "Diffview is not available"
	end
	if payload.has_file_level_change or vim.tbl_isempty(payload.files) then
		return false, "Diffview cannot represent this claim's non-textual changes"
	end

	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local _, init_error = run_git(root, { "init", "-q" })
	if init_error or not write_side(root, payload.files, "before") then
		cleanup_directory(root)
		return false, init_error or "Unable to prepare files for Diffview"
	end
	local _, add_error = run_git(root, { "add", "-A" })
	local _, commit_error = run_git(root, {
		"-c", "user.name=doubt.nvim",
		"-c", "user.email=doubt@nvim",
		"commit", "-q", "--allow-empty", "-m", "Before doubt claim",
	})
	local before_revision = run_git(root, { "rev-parse", "HEAD" })
	if add_error or commit_error or not before_revision or not write_side(root, payload.files, "after") then
		cleanup_directory(root)
		return false, add_error or commit_error or "Unable to prepare Diffview baseline"
	end
	local _, final_add_error = run_git(root, { "add", "-A" })
	local _, final_commit_error = run_git(root, {
		"-c", "user.name=doubt.nvim",
		"-c", "user.email=doubt@nvim",
		"commit", "-q", "--allow-empty", "-m", "After doubt claim",
	})
	local after_revision = run_git(root, { "rev-parse", "HEAD" })
	if final_add_error or final_commit_error or not after_revision then
		cleanup_directory(root)
		return false, final_add_error or final_commit_error or "Unable to prepare Diffview result"
	end

	local ok, err = pcall(vim.cmd, string.format(
		"DiffviewOpen -C%s %s..%s",
		vim.fn.fnameescape(root),
		before_revision,
		after_revision
	))
	if not ok then
		cleanup_directory(root)
		return false, tostring(err)
	end
	cleanup_on_event(root, "DiffviewViewClosed")
	return true
end

function M.open(opts)
	opts = opts or {}
	local result = opts.result
	if type(result) ~= "table" or type(result.status) ~= "table" then
		return false, "Invalid doubt claim diff"
	end
	local files, has_file_level_change = build_file_pairs(result.status.matches)
	local payload = {
		claim_id = opts.claim_id,
		files = files,
		has_file_level_change = has_file_level_change,
		patch_lines = result.lines,
		run = result.run,
		status = result.status,
	}
	local viewer = opts.viewer or "auto"
	if type(viewer) == "function" then
		local ok, opened = pcall(viewer, payload)
		if ok and opened ~= false then
			return true
		end
		local err = ok and "Custom diff viewer declined the payload" or tostring(opened)
		if opts.notify then
			opts.notify(err .. "; using the built-in diff viewer", vim.log.levels.WARN)
		end
		return builtin_viewer(payload)
	end
	if viewer == "auto" or viewer == "codediff" then
		local opened, err = codediff_viewer(payload)
		if opened then
			return true
		end
		if viewer == "codediff" and opts.notify then
			opts.notify(err .. "; using the built-in diff viewer", vim.log.levels.WARN)
		end
		if viewer == "codediff" then
			return builtin_viewer(payload)
		end
	end
	if viewer == "auto" or viewer == "diffview" then
		local opened, err = diffview_viewer(payload)
		if opened then
			return true
		end
		if viewer == "diffview" and opts.notify then
			opts.notify(err .. "; using the built-in diff viewer", vim.log.levels.WARN)
		end
	end
	return builtin_viewer(payload)
end

M.build_file_pairs = build_file_pairs

return M
