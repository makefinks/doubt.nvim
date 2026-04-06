local normalize = require("doubt.sessions.normalize")
local store = require("doubt.sessions.store")

local M = {}

local function pretty_json(json)
	local parts = {}
	local indent = 0
	local in_string = false
	local escaping = false

	for index = 1, #json do
		local char = json:sub(index, index)

		if in_string then
			table.insert(parts, char)
			if escaping then
				escaping = false
			elseif char == "\\" then
				escaping = true
			elseif char == '"' then
				in_string = false
			end
		elseif char == '"' then
			in_string = true
			table.insert(parts, char)
		elseif char == "{" or char == "[" then
			indent = indent + 1
			table.insert(parts, char)
			table.insert(parts, "\n" .. string.rep("  ", indent))
		elseif char == "}" or char == "]" then
			indent = math.max(indent - 1, 0)
			table.insert(parts, "\n" .. string.rep("  ", indent) .. char)
		elseif char == "," then
			table.insert(parts, char)
			table.insert(parts, "\n" .. string.rep("  ", indent))
		elseif char == ":" then
			table.insert(parts, ": ")
		else
			table.insert(parts, char)
		end
	end

	return table.concat(parts)
end

function M.read_file_content(path)
	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return nil
	end

	local stat = vim.uv.fs_fstat(fd)
	if not stat then
		vim.uv.fs_close(fd)
		return nil
	end

	local content = vim.uv.fs_read(fd, stat.size, 0)
	vim.uv.fs_close(fd)
	return content
end

function M.load(config, normalize_path, notify, workspace_key, classify_all_claims)
	store.set_current_workspace(workspace_key)
	local fd = vim.uv.fs_open(config.state_path, "r", 438)
	if not fd then
		store.reset_runtime_state(store.get_current_workspace())
		return
	end

	local stat = vim.uv.fs_fstat(fd)
	if not stat then
		vim.uv.fs_close(fd)
		store.reset_runtime_state(store.get_current_workspace())
		return
	end

	local content = vim.uv.fs_read(fd, stat.size, 0)
	vim.uv.fs_close(fd)
	if not content or content == "" then
		store.reset_runtime_state(store.get_current_workspace())
		return
	end

	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" then
		notify("Failed to decode doubt state; starting fresh", vim.log.levels.WARN)
		store.reset_runtime_state(store.get_current_workspace())
		return
	end

	store.set_state(normalize.normalize_loaded_state(decoded, normalize_path, store.get_current_workspace()))
	store.ensure_workspace_state(store.get_current_workspace())
	classify_all_claims()
end

function M.save(config, notify)
	vim.fn.mkdir(vim.fs.dirname(config.state_path), "p")
	local ok, encoded = pcall(vim.json.encode, store.get_state())
	if not ok then
		notify("Failed to encode doubt state", vim.log.levels.ERROR)
		return
	end
	encoded = pretty_json(encoded)

	local fd = assert(vim.uv.fs_open(config.state_path, "w", 420))
	assert(vim.uv.fs_write(fd, encoded, -1))
	assert(vim.uv.fs_close(fd))
end

return M
