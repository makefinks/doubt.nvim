local M = {}

local DEFAULT_WORKSPACE_KEY = "__global__"

local state = {
	workspaces = {},
}

local current_workspace = nil

function M.normalize_workspace_key(workspace)
	if type(workspace) ~= "string" then
		return DEFAULT_WORKSPACE_KEY
	end

	workspace = vim.trim(workspace)
	if workspace == "" then
		return DEFAULT_WORKSPACE_KEY
	end

	return workspace
end

function M.empty_workspace_state()
	return {
		active_session = nil,
		sessions = {},
	}
end

function M.empty_global_state()
	return {
		workspaces = {},
	}
end

function M.get_state()
	return state
end

function M.set_state(next_state)
	state = next_state or M.empty_global_state()
	if type(state.workspaces) ~= "table" then
		state.workspaces = {}
	end
	return state
end

function M.get_current_workspace()
	return current_workspace
end

function M.set_current_workspace(workspace_key)
	current_workspace = M.normalize_workspace_key(workspace_key)
	return current_workspace
end

function M.ensure_workspace_state(workspace_key)
	workspace_key = M.normalize_workspace_key(workspace_key or current_workspace)

	if type(state.workspaces) ~= "table" then
		state.workspaces = {}
	end

	local workspace_state = state.workspaces[workspace_key]
	if type(workspace_state) ~= "table" then
		workspace_state = M.empty_workspace_state()
	end

	if type(workspace_state.sessions) ~= "table" then
		workspace_state.sessions = {}
	end

	workspace_state.active_session = require("doubt.sessions.normalize").normalize_session_name(workspace_state.active_session)
	state.workspaces[workspace_key] = workspace_state
	return workspace_state
end

function M.workspace_state()
	return M.ensure_workspace_state(current_workspace)
end

function M.reset_runtime_state(workspace_key)
	M.set_state(M.empty_global_state())
	M.set_current_workspace(workspace_key)
	M.ensure_workspace_state(current_workspace)
end

return M
