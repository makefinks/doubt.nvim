local config = require("doubt.config")
local claims = require("doubt.claims")
local state = require("doubt.state")

local M = {}

local REQUIRED_COMMANDS = {
	"DoubtPanel",
	"DoubtRefresh",
	"DoubtExport",
	"DoubtExportXml",
}

local function pass_fail(ok)
	if ok then
		return "PASS"
	end

	return "FAIL"
end

local function check_config_merge(current_config)
	local base_width = (((current_config or {}).input or {}).width) or 50
	local overridden_width = base_width + 3
	local merged = vim.tbl_deep_extend("force", vim.deepcopy(current_config or {}), {
		input = {
			width = overridden_width,
		},
	})

	local preserved = {
		type(merged.export) == "table",
		type((merged.export or {}).templates) == "table",
		type(((merged.export or {}).templates or {}).raw) == "string",
		type(((merged.input or {}).prompts or {}).question) == "string",
		type((merged.claim_kinds or {}).question) == "table",
		((merged.input or {}).width) == overridden_width,
	}

	local ok = true
	for _, item in ipairs(preserved) do
		if not item then
			ok = false
			break
		end
	end

	return {
		ok = ok,
		name = "Config Merge Check",
		details = "Deep override preserves defaults while applying new values",
		how_to_fix = "Call require('doubt').setup() once with a table override; avoid replacing nested sections wholesale.",
	}
end

local function check_dependency()
	local ok, _ = pcall(require, "nui.input")
	return {
		ok = ok,
		name = "Dependency Check [nui.input]",
		details = "Required module from MunifTanjim/nui.nvim is loadable",
		how_to_fix = "Install MunifTanjim/nui.nvim and ensure it is on runtimepath before doubt.nvim setup.",
	}
end

local function check_command_sanity()
	local missing = {}
	for _, name in ipairs(REQUIRED_COMMANDS) do
		if vim.fn.exists(":" .. name) ~= 2 then
			table.insert(missing, name)
		end
	end

	local ok = vim.tbl_isempty(missing)
	local details = "Required :Doubt* commands are registered"
	if not ok then
		details = "Missing commands: " .. table.concat(missing, ", ")
	end

	return {
		ok = ok,
		name = "Command Registration Sanity",
		details = details,
		how_to_fix = "Re-run require('doubt').setup() and verify plugin/doubt.lua is loaded during startup.",
	}
end

local function has_non_negative_integer(value)
	return type(value) == "number" and value >= 0 and math.floor(value) == value
end

local function check_claim_shape(claim)
	if type(claim) ~= "table" then
		return false, "claim entry is not a table"
	end

	if type(claim.id) ~= "string" or claim.id == "" then
		return false, "claim has missing id"
	end

	if type(claim.kind) ~= "string" or not claims.has_claim_kind(claim.kind) then
		return false, "claim has unknown kind"
	end

	if not has_non_negative_integer(claim.start_line) or not has_non_negative_integer(claim.start_col) then
		return false, "claim start range is invalid"
	end

	if not has_non_negative_integer(claim.end_line) then
		return false, "claim end line is invalid"
	end

	if claim.end_line < claim.start_line then
		return false, "claim end line is before start line"
	end

	if claim.end_col ~= nil and not has_non_negative_integer(claim.end_col) then
		return false, "claim end column is invalid"
	end

	if type(claim.note) ~= "string" then
		return false, "claim note is invalid"
	end

	if claim.freshness ~= "fresh" and claim.freshness ~= "stale" and claim.freshness ~= "reanchored" then
		return false, "claim freshness is invalid"
	end

	local anchor = claim.anchor
	if type(anchor) ~= "table"
		or type(anchor.text) ~= "string"
		or type(anchor.before) ~= "string"
		or type(anchor.after) ~= "string"
	then
		return false, "claim anchor is invalid"
	end

	return true
end

local function check_session_state_shape()
	local workspace_state = state.get()
	if type(workspace_state) ~= "table" then
		return {
			ok = false,
			name = "Session State Shape",
			details = "Workspace state is not a table",
			how_to_fix = "Re-run require('doubt').setup(); if it persists, remove or repair your state file and restart Neovim.",
		}
	end

	local sessions = workspace_state.sessions
	if type(sessions) ~= "table" then
		return {
			ok = false,
			name = "Session State Shape",
			details = "Workspace sessions bucket is missing or malformed",
			how_to_fix = "Re-run require('doubt').setup(); if it persists, remove or repair your state file and restart Neovim.",
		}
	end

	local active_session = workspace_state.active_session
	if active_session ~= nil and (type(active_session) ~= "string" or sessions[active_session] == nil) then
		return {
			ok = false,
			name = "Session State Shape",
			details = "Active session points to a missing or invalid session",
			how_to_fix = "Use :DoubtStopSession, then resume a valid session; if needed, repair state on disk.",
		}
	end

	local session_count = 0
	local file_count = 0
	local claim_count = 0

	for session_name, session_state in pairs(sessions) do
		session_count = session_count + 1
		if type(session_name) ~= "string" or vim.trim(session_name) == "" then
			return {
				ok = false,
				name = "Session State Shape",
				details = "Found a session with an invalid name",
				how_to_fix = "Rename invalid sessions via panel/command or repair the state file.",
			}
		end

		if type(session_state) ~= "table" or type(session_state.files) ~= "table" then
			return {
				ok = false,
				name = "Session State Shape",
				details = string.format("Session '%s' does not have a valid files table", session_name),
				how_to_fix = "Run :DoubtStopSession and re-open the session; if needed, repair persisted state.",
			}
		end

		for path, file_state in pairs(session_state.files) do
			file_count = file_count + 1
			if type(path) ~= "string" or path == "" then
				return {
					ok = false,
					name = "Session State Shape",
					details = string.format("Session '%s' has an invalid file path key", session_name),
					how_to_fix = "Remove malformed file entries from state or recreate the session.",
				}
			end

			if type(file_state) ~= "table" or type(file_state.claims) ~= "table" then
				return {
					ok = false,
					name = "Session State Shape",
					details = string.format("Session '%s' file '%s' has malformed claims data", session_name, path),
					how_to_fix = "Refresh/recreate claims for this file or repair persisted state.",
				}
			end

			for _, claim in ipairs(file_state.claims) do
				claim_count = claim_count + 1
				local valid, reason = check_claim_shape(claim)
				if not valid then
					return {
						ok = false,
						name = "Session State Shape",
						details = string.format("Invalid claim in session '%s' file '%s': %s", session_name, path, reason),
						how_to_fix = "Delete malformed claim entries or re-capture claims for this file.",
					}
				end
			end
		end
	end

	return {
		ok = true,
		name = "Session State Shape",
		details = string.format("Validated %d sessions, %d files, %d claims", session_count, file_count, claim_count),
		how_to_fix = "No action needed.",
	}
end

local function build_report_lines(result)
	local lines = {
		"Doubt Healthcheck Report",
		string.rep("=", 24),
		"",
		string.format("Overall: %s (%d/%d checks passing)", pass_fail(result.ok), result.pass_count, result.total_count),
		"",
		"Checks",
		"------",
	}

	local ordered = {
		result.checks.config_merge,
		result.checks.dependency_nui_input,
		result.checks.command_sanity,
		result.checks.session_state_shape,
	}

	for _, check in ipairs(ordered) do
		table.insert(lines, string.format("- %s: %s", check.name, pass_fail(check.ok)))
		table.insert(lines, "  Details: " .. check.details)
		if not check.ok then
			table.insert(lines, "  How to fix: " .. check.how_to_fix)
		end
		table.insert(lines, "")
	end

	return lines
end

local function render_report(lines)
	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()

	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	return bufnr
end

function M.run(opts)
	opts = opts or {}
	local current_config = config.get()
	local checks = {
		config_merge = check_config_merge(current_config),
		dependency_nui_input = check_dependency(),
		command_sanity = check_command_sanity(),
		session_state_shape = check_session_state_shape(),
	}

	local pass_count = 0
	for _, check in pairs(checks) do
		if check.ok then
			pass_count = pass_count + 1
		end
	end

	local result = {
		checks = checks,
		total_count = 4,
		pass_count = pass_count,
		ok = pass_count == 4,
	}

	result.bufnr = render_report(build_report_lines(result))

	if opts.notify then
		opts.notify(
			string.format("Doubt healthcheck: %s (%d/%d)", pass_fail(result.ok), result.pass_count, result.total_count),
			result.ok and vim.log.levels.INFO or vim.log.levels.WARN
		)
	end

	return result
end

return M
