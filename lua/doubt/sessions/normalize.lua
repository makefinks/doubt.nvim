local claims = require("doubt.claims")
local store = require("doubt.sessions.store")

local M = {}

function M.normalize_session_name(name)
	if type(name) ~= "string" then
		return nil
	end

	name = vim.trim(name)
	if name == "" then
		return nil
	end

	return name
end

function M.normalize_file_state(file_state)
	if type(file_state) ~= "table" then
		return nil
	end

	local normalized_claims = {}
	for _, claim in ipairs(file_state.claims or {}) do
		local normalized = claims.normalize_claim(claim)
		if normalized then
			table.insert(normalized_claims, normalized)
		end
	end

	claims.sort_claims(normalized_claims)
	if vim.tbl_isempty(normalized_claims) then
		return nil
	end

	return { claims = normalized_claims }
end

function M.normalize_session_state(session_state)
	if type(session_state) ~= "table" then
		return nil
	end

	local files = {}
	for path, file_state in pairs(session_state.files or {}) do
		local normalized_file_state = M.normalize_file_state(file_state)
		if normalized_file_state then
			files[path] = normalized_file_state
		end
	end

	return { files = files }
end

function M.normalize_single_workspace_state(decoded, normalize_path)
	local loaded_state = store.empty_workspace_state()

	for name, session_state in pairs((decoded or {}).sessions or {}) do
		local normalized_name = M.normalize_session_name(name)
		if normalized_name then
			local normalized_session_state = { files = {} }
			for path, file_state in pairs((session_state or {}).files or {}) do
				local normalized_path = normalize_path(path)
				local normalized_file_state = M.normalize_file_state(file_state)
				if normalized_path and normalized_file_state then
					normalized_session_state.files[normalized_path] = normalized_file_state
				end
			end

			loaded_state.sessions[normalized_name] = normalized_session_state
		end
	end

	local active_session = M.normalize_session_name(decoded.active_session)
	if active_session and loaded_state.sessions[active_session] then
		loaded_state.active_session = active_session
	end

	return loaded_state
end

function M.normalize_loaded_state(decoded, normalize_path, workspace_key)
	local loaded_state = store.empty_global_state()

	if type((decoded or {}).workspaces) == "table" then
		for key, workspace_snapshot in pairs(decoded.workspaces) do
			local normalized_key = store.normalize_workspace_key(key)
			if normalized_key then
				loaded_state.workspaces[normalized_key] = M.normalize_single_workspace_state(workspace_snapshot, normalize_path)
			end
		end
	end

	local current = store.normalize_workspace_key(workspace_key)
	if not loaded_state.workspaces[current] then
		loaded_state.workspaces[current] = store.empty_workspace_state()
	end

	return loaded_state
end

return M
