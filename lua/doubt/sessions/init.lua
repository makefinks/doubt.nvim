local claims = require("doubt.claims")
local classify = require("doubt.sessions.classify")
local normalize = require("doubt.sessions.normalize")
local persistence = require("doubt.sessions.persistence")
local store = require("doubt.sessions.store")

local M = {}

function M.set_workspace(workspace_key)
	store.set_current_workspace(workspace_key)
	store.ensure_workspace_state(store.get_current_workspace())
end

function M.get()
	return store.workspace_state()
end

function M.active_session_name()
	return store.workspace_state().active_session
end

function M.has_active_session()
	return M.active_session_name() ~= nil
end

M.normalize_session_name = normalize.normalize_session_name
M.normalize_file_state = normalize.normalize_file_state
M.normalize_session_state = normalize.normalize_session_state

function M.current_files()
	local session_name = M.active_session_name()
	if not session_name then
		return {}
	end

	local session_state = store.workspace_state().sessions[session_name]
	return session_state and session_state.files or {}
end

function M.list_sessions()
	local session_names = vim.tbl_keys(store.workspace_state().sessions)
	table.sort(session_names)
	return session_names
end

function M.ensure_session(name)
	name = M.normalize_session_name(name)
	if not name then
		return nil
	end

	local current = store.workspace_state()
	local normalized_session = M.normalize_session_state(current.sessions[name])
	if not normalized_session then
		normalized_session = { files = {} }
	end

	current.sessions[name] = normalized_session
	return normalized_session
end

function M.set_active_session(name)
	name = M.normalize_session_name(name)
	if not name then
		return nil
	end

	M.ensure_session(name)
	store.workspace_state().active_session = name
	return name
end

function M.stop_session()
	store.workspace_state().active_session = nil
end

function M.delete_session(name)
	name = M.normalize_session_name(name)
	local current = store.workspace_state()
	if not name or not current.sessions[name] then
		return false
	end

	current.sessions[name] = nil
	if current.active_session == name then
		current.active_session = nil
	end

	return true
end

function M.rename_session(old_name, new_name)
	old_name = M.normalize_session_name(old_name)
	new_name = M.normalize_session_name(new_name)
	if not old_name or not new_name or old_name == new_name then
		return false
	end

	local current = store.workspace_state()
	local session_state = current.sessions[old_name]
	if not session_state or current.sessions[new_name] then
		return false
	end

	current.sessions[new_name] = session_state
	current.sessions[old_name] = nil
	if current.active_session == old_name then
		current.active_session = new_name
	end

	return true
end

function M.delete_claim(path, claim_id)
	if type(path) ~= "string" or type(claim_id) ~= "string" then
		return false
	end

	local session_name = M.active_session_name()
	if not session_name then
		return false
	end

	local session_state = store.workspace_state().sessions[session_name]
	local file_state = session_state and session_state.files[path]
	local claims_list = file_state and file_state.claims
	if not claims_list then
		return false
	end

	for idx, claim in ipairs(claims_list) do
		if claim.id == claim_id then
			table.remove(claims_list, idx)
			if vim.tbl_isempty(claims_list) then
				session_state.files[path] = nil
			end
			return true
		end
	end

	return false
end

function M.find_claim(path, claim_id)
	if type(path) ~= "string" or type(claim_id) ~= "string" then
		return nil
	end

	local session_name = M.active_session_name()
	if not session_name then
		return nil
	end

	local session_state = store.workspace_state().sessions[session_name]
	local file_state = session_state and session_state.files[path]
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

	local normalized_claim = claims.normalize_claim(vim.tbl_extend("force", vim.deepcopy(claim), updates, {
		id = claim.id,
	}))
	if not normalized_claim then
		return false
	end

	claim.kind = normalized_claim.kind
	claim.start_line = normalized_claim.start_line
	claim.start_col = normalized_claim.start_col
	claim.end_line = normalized_claim.end_line
	claim.end_col = normalized_claim.end_col
	claim.note = normalized_claim.note
	claim.freshness = normalized_claim.freshness
	claim.anchor = normalized_claim.anchor

	local file_state = M.ensure_file_entry(path)
	claims.sort_claims(file_state.claims)
	return true
end

function M.classify_file_claims(path, opts)
	if type(path) ~= "string" or path == "" then
		return { changed = false, claim_count = 0 }
	end

	opts = opts or {}
	local session_name = M.active_session_name()
	if not session_name then
		return { changed = false, claim_count = 0 }
	end

	local session_state = store.workspace_state().sessions[session_name]
	local file_state = session_state and session_state.files[path]
	if not file_state then
		return { changed = false, claim_count = 0 }
	end

	local content = type(opts.content) == "string" and opts.content or persistence.read_file_content(path)
	local changed = classify.classify_file_state(file_state, content)
	return {
		changed = changed,
		claim_count = #(file_state.claims or {}),
	}
end

function M.classify_all_claims()
	for _, session_state in pairs(store.workspace_state().sessions) do
		for path, file_state in pairs((session_state or {}).files or {}) do
			classify.classify_file_state(file_state, persistence.read_file_content(path))
		end
	end
end

function M.classify_current_session_claims()
	local session_name = M.active_session_name()
	if not session_name then
		return {
			changed_file_count = 0,
			claim_count = 0,
		}
	end

	local session_state = store.workspace_state().sessions[session_name]
	local changed_file_count = 0
	local claim_count = 0

	for path, file_state in pairs((session_state or {}).files or {}) do
		claim_count = claim_count + #((file_state or {}).claims or {})
		if classify.classify_file_state(file_state, persistence.read_file_content(path)) then
			changed_file_count = changed_file_count + 1
		end
	end

	return {
		changed_file_count = changed_file_count,
		claim_count = claim_count,
	}
end

function M.delete_file(path)
	if type(path) ~= "string" then
		return false
	end

	local session_name = M.active_session_name()
	if not session_name then
		return false
	end

	local session_state = store.workspace_state().sessions[session_name]
	if not session_state or not session_state.files[path] then
		return false
	end

	session_state.files[path] = nil
	return true
end

function M.ensure_file_entry(path)
	local session_name = M.active_session_name()
	if not session_name then
		return nil
	end

	local session_state = M.ensure_session(session_name)
	local normalized_file = M.normalize_file_state(session_state.files[path])
	if not normalized_file then
		normalized_file = { claims = {} }
	end

	session_state.files[path] = normalized_file
	return normalized_file
end

function M.load(config, normalize_path, notify, workspace_key)
	persistence.load(config, normalize_path, notify, workspace_key, M.classify_all_claims)
end

function M.save(config, notify)
	persistence.save(config, notify)
end

return M
