local claims = require("doubt.claims")

local M = {}

local SCHEMA_VERSION = 1
local workspace_root = nil
local active_session = nil
local session_cache = {}

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

local function normalize_session_name(name)
	if type(name) ~= "string" then
		return nil
	end

	name = vim.trim(name)
	if name == "" or name:find("/", 1, true) or name:find("\\", 1, true) then
		return nil
	end

	return name
end

local function root()
	return workspace_root or vim.fs.normalize(vim.fn.getcwd())
end

local function sessions_dir()
	return vim.fs.joinpath(root(), ".doubt", "sessions")
end

local function session_dir(name)
	return vim.fs.joinpath(sessions_dir(), name)
end

local function claims_dir(name)
	return vim.fs.joinpath(session_dir(name), "claims")
end

local function read_json(path)
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
	if not content or content == "" then
		return nil
	end

	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	return decoded
end

local function write_json(path, value)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local ok, encoded = pcall(vim.json.encode, value)
	if not ok then
		return false
	end

	local fd = vim.uv.fs_open(path, "w", 420)
	if not fd then
		return false
	end
	vim.uv.fs_write(fd, pretty_json(encoded), -1)
	vim.uv.fs_close(fd)
	return true
end

local function relpath(path)
	path = vim.fs.normalize(path or "")
	local base = root()
	if path == base then
		return nil
	end

	local prefix = base .. "/"
	if path:sub(1, #prefix) ~= prefix then
		return nil
	end
	return path:sub(#prefix + 1)
end

local function abs_path(relative)
	if type(relative) ~= "string" or relative == "" or relative:sub(1, 1) == "/" then
		return nil
	end

	return vim.fs.normalize(vim.fs.joinpath(root(), relative))
end

local function claim_file_path(name, path)
	local relative = relpath(path)
	if not relative then
		return nil
	end

	return vim.fs.joinpath(claims_dir(name), relative .. ".json")
end

local function to_internal_claim(raw, path)
	if type(raw) ~= "table" then
		return nil
	end

	local start_line = math.max((tonumber(raw.start_line) or 1) - 1, 0)
	local start_col = math.max((tonumber(raw.start_col) or 1) - 1, 0)
	local end_line = raw.end_line == nil and start_line or math.max((tonumber(raw.end_line) or 1) - 1, 0)
	local end_col = raw.end_col == nil and nil or math.max((tonumber(raw.end_col) or 1) - 1, 0)
	if end_line == start_line and end_col ~= nil and end_col <= start_col then
		end_col = nil
	end
	local claim = vim.deepcopy(raw)
	claim.start_line = start_line
	claim.start_col = start_col
	claim.end_line = end_line
	claim.end_col = end_col
	local normalized = claims.normalize_claim(claim)

	if normalized and normalized.anchor.text == "" and type(path) == "string" then
		local content = require("doubt.sessions.persistence").read_file_content(path)
		if type(content) == "string" then
			normalized.anchor = claims.build_content_anchor(
				content,
				normalized.start_line,
				normalized.start_col,
				normalized.end_line,
				normalized.end_col
			)
			if normalized.anchor.text == "" and normalized.end_col ~= nil then
				normalized.end_col = nil
				normalized.anchor = claims.build_content_anchor(
					content,
					normalized.start_line,
					normalized.start_col,
					normalized.end_line,
					normalized.end_col
				)
			end
			normalized.freshness = normalized.anchor.text ~= "" and "fresh" or normalized.freshness
		end
	end

	return normalized
end

local function to_external_claim(claim)
	return {
		id = claim.id,
		kind = claim.kind,
		start_line = (claim.start_line or 0) + 1,
		start_col = (claim.start_col or 0) + 1,
		end_line = (claim.end_line or claim.start_line or 0) + 1,
		end_col = claim.end_col and (claim.end_col + 1) or nil,
		note = claim.note,
		freshness = claim.freshness,
		anchor = claim.anchor,
	}
end

local function load_session(name)
	name = normalize_session_name(name)
	if not name then
		return nil
	end
	if not vim.uv.fs_stat(vim.fs.joinpath(session_dir(name), "session.json")) then
		return nil
	end

	if session_cache[name] then
		return session_cache[name]
	end

	local session = { files = {} }
	local dir = claims_dir(name)
	local function visit(path)
		local stat = vim.uv.fs_stat(path)
		if not stat then
			return
		end

		if stat.type == "directory" then
			for child in vim.fs.dir(path) do
				visit(vim.fs.joinpath(path, child))
			end
			return
		end

		if stat.type ~= "file" or not path:match("%.json$") then
			return
		end

		local decoded = read_json(path)
		local file_path = abs_path(decoded and decoded.file)
		if not file_path then
			return
		end

		local normalized_claims = {}
		for _, raw_claim in ipairs(decoded.claims or {}) do
			local normalized = to_internal_claim(raw_claim, file_path)
			if normalized then
				table.insert(normalized_claims, normalized)
			end
		end

		claims.sort_claims(normalized_claims)
		if not vim.tbl_isempty(normalized_claims) then
			session.files[file_path] = { claims = normalized_claims }
		end
	end

	visit(dir)
	session_cache[name] = session
	return session
end

local function save_file(name, path, file_state)
	local target = claim_file_path(name, path)
	if not target then
		return false
	end

	local relative = relpath(path)
	local external_claims = {}
	for _, claim in ipairs((file_state or {}).claims or {}) do
		table.insert(external_claims, to_external_claim(claim))
	end

	if vim.tbl_isempty(external_claims) then
		pcall(vim.uv.fs_unlink, target)
		return true
	end

	return write_json(target, {
		schema_version = SCHEMA_VERSION,
		file = relative,
		claims = external_claims,
	})
end

function M.set_workspace(path)
	workspace_root = vim.fs.normalize(path or vim.fn.getcwd())
	active_session = nil
	session_cache = {}
end

function M.active_session_name()
	return active_session
end

function M.list_sessions()
	local names = {}
	local dir = sessions_dir()
	local stat = vim.uv.fs_stat(dir)
	if not stat or stat.type ~= "directory" then
		return names
	end

	for name, kind in vim.fs.dir(dir) do
		if kind == "directory" and normalize_session_name(name) and vim.uv.fs_stat(vim.fs.joinpath(dir, name, "session.json")) then
			table.insert(names, name)
		end
	end

	table.sort(names)
	return names
end

function M.ensure_session(name)
	name = normalize_session_name(name)
	if not name then
		return nil
	end

	vim.fn.mkdir(claims_dir(name), "p")
	write_json(vim.fs.joinpath(session_dir(name), "session.json"), {
		schema_version = SCHEMA_VERSION,
		name = name,
	})
	return load_session(name)
end

function M.set_active_session(name)
	local session = M.ensure_session(name)
	if not session then
		return nil
	end

	active_session = normalize_session_name(name)
	return active_session
end

function M.stop_session()
	active_session = nil
end

function M.get_session(name)
	return load_session(name)
end

function M.current_files()
	if not active_session then
		return {}
	end

	return (load_session(active_session) or {}).files or {}
end

function M.ensure_file_entry(path)
	if not active_session or type(path) ~= "string" then
		return nil
	end

	local session = load_session(active_session) or M.ensure_session(active_session)
	if not session.files[path] then
		session.files[path] = { claims = {} }
	end
	return session.files[path]
end

function M.delete_claim(path, claim_id)
	local file_state = M.current_files()[path]
	local claim_list = file_state and file_state.claims
	if not claim_list then
		return false
	end

	for idx, claim in ipairs(claim_list) do
		if claim.id == claim_id then
			table.remove(claim_list, idx)
			if vim.tbl_isempty(claim_list) then
				save_file(active_session, path, { claims = {} })
				M.current_files()[path] = nil
			end
			return true
		end
	end

	return false
end

function M.find_claim(path, claim_id)
	local file_state = M.current_files()[path]
	for _, claim in ipairs((file_state or {}).claims or {}) do
		if claim.id == claim_id then
			return claim
		end
	end

	return nil
end

function M.update_claim(path, claim_id, updates)
	local claim = M.find_claim(path, claim_id)
	if not claim or type(updates) ~= "table" then
		return false
	end

	local normalized = claims.normalize_claim(vim.tbl_extend("force", vim.deepcopy(claim), updates, { id = claim.id }))
	if not normalized then
		return false
	end

	claim.kind = normalized.kind
	claim.start_line = normalized.start_line
	claim.start_col = normalized.start_col
	claim.end_line = normalized.end_line
	claim.end_col = normalized.end_col
	claim.note = normalized.note
	claim.freshness = normalized.freshness
	claim.anchor = normalized.anchor
	claims.sort_claims(M.ensure_file_entry(path).claims)
	return true
end

function M.delete_file(path)
	if not active_session or type(path) ~= "string" then
		return false
	end

	local files = M.current_files()
	if not files[path] then
		return false
	end

	save_file(active_session, path, { claims = {} })
	files[path] = nil
	return true
end

function M.save_current_session()
	if not active_session then
		return false
	end

	local session = load_session(active_session) or { files = {} }
	M.ensure_session(active_session)
	for path, file_state in pairs(session.files or {}) do
		save_file(active_session, path, file_state)
	end
	return true
end

function M.delete_session(name)
	name = normalize_session_name(name)
	if not name or not vim.uv.fs_stat(session_dir(name)) then
		return false
	end

	vim.fn.delete(session_dir(name), "rf")
	session_cache[name] = nil
	if active_session == name then
		active_session = nil
	end
	return true
end

function M.rename_session(old_name, new_name)
	old_name = normalize_session_name(old_name)
	new_name = normalize_session_name(new_name)
	if not old_name or not new_name or old_name == new_name or vim.uv.fs_stat(session_dir(new_name)) then
		return false
	end

	if vim.fn.rename(session_dir(old_name), session_dir(new_name)) ~= 0 then
		return false
	end

	session_cache[new_name] = session_cache[old_name]
	session_cache[old_name] = nil
	if active_session == old_name then
		active_session = new_name
	end
	M.ensure_session(new_name)
	return true
end

return M
