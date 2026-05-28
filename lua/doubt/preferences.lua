local M = {}

local VALID_INLINE_NOTES_LAYOUTS = {
	block = true,
	inline = true,
}

local function normalize_inline_notes_layout(layout)
	if VALID_INLINE_NOTES_LAYOUTS[layout] then
		return layout
	end

	return nil
end

function M.load(config, notify)
	local fd = vim.uv.fs_open(config.preferences_path, "r", 438)
	if not fd then
		return {}
	end

	local stat = vim.uv.fs_fstat(fd)
	if not stat then
		vim.uv.fs_close(fd)
		return {}
	end

	local content = vim.uv.fs_read(fd, stat.size, 0)
	vim.uv.fs_close(fd)
	if not content or content == "" then
		return {}
	end

	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" then
		if notify then
			notify("Failed to decode doubt preferences; using defaults", vim.log.levels.WARN)
		end
		return {}
	end

	return {
		inline_notes_layout = normalize_inline_notes_layout(decoded.inline_notes_layout),
	}
end

function M.save(config, preferences, notify)
	local inline_notes_layout = normalize_inline_notes_layout((preferences or {}).inline_notes_layout)
	if not inline_notes_layout then
		return false
	end

	vim.fn.mkdir(vim.fs.dirname(config.preferences_path), "p")
	local ok, encoded = pcall(vim.json.encode, {
		inline_notes_layout = inline_notes_layout,
	})
	if not ok then
		if notify then
			notify("Failed to encode doubt preferences", vim.log.levels.ERROR)
		end
		return false
	end

	local fd = vim.uv.fs_open(config.preferences_path, "w", 420)
	if not fd then
		if notify then
			notify("Failed to save doubt preferences", vim.log.levels.ERROR)
		end
		return false
	end

	local written = vim.uv.fs_write(fd, encoded, -1)
	vim.uv.fs_close(fd)
	if not written then
		if notify then
			notify("Failed to save doubt preferences", vim.log.levels.ERROR)
		end
		return false
	end

	return true
end

return M
