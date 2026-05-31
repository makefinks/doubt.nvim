local t = dofile("tests/helpers/bootstrap.lua")

describe("session prompt", function()
	it("matches expected behavior", function()

package.loaded["doubt.app.session_ui"] = nil

local session_ui = require("doubt.app.session_ui")

local function test_session_prompt_uses_native_command_line_input()
	local command_prompt_opts = nil
	local ask_text_called = false
	local notified = nil
	local resolved_name = nil
	local resolved_cancelled = nil

	session_ui.prompt_session_name({
		get = function()
			return {
				input = {
					border = "single",
					width = 70,
				},
			}
		end,
	}, {
		ask_command_text = function(opts, callback)
			command_prompt_opts = opts
			callback("  review-pass  ", false)
		end,
		ask_text = function()
			ask_text_called = true
		end,
	}, {
		normalize_session_name = function(name)
			name = vim.trim(name or "")
			if name == "" then
				return nil
			end

			return name
		end,
	}, {
		notify = function(message)
			notified = message
		end,
	}, {
		default = "old-name",
		prompt = "Start session: ",
		title = "new doubt session",
	}, function(name, cancelled)
		resolved_name = name
		resolved_cancelled = cancelled
	end)

	t.assert_eq(ask_text_called, false, "session prompt should not use floating text input")
	t.assert_eq(command_prompt_opts.prompt, "Start session: ", "session prompt should pass prompt text")
	t.assert_eq(command_prompt_opts.default, "old-name", "session prompt should pass default text")
	t.assert_eq(resolved_name, "review-pass", "session prompt should normalize submitted name")
	t.assert_eq(resolved_cancelled, false, "session prompt should report submitted name")
	t.assert_eq(notified, nil, "valid session prompt should not notify")
end

local function test_empty_session_prompt_notifies_and_cancels()
	local notified = nil
	local resolved_name = "unchanged"
	local resolved_cancelled = false

	session_ui.prompt_session_name({
		get = function()
			return {}
		end,
	}, {
		ask_command_text = function(_, callback)
			callback("", false)
		end,
	}, {
		normalize_session_name = function(name)
			if vim.trim(name or "") == "" then
				return nil
			end

			return name
		end,
	}, {
		notify = function(message)
			notified = message
		end,
	}, {}, function(name, cancelled)
		resolved_name = name
		resolved_cancelled = cancelled
	end)

	t.assert_eq(notified, "Session name cannot be empty", "empty session prompt should notify")
	t.assert_eq(resolved_name, nil, "empty session prompt should return nil")
	t.assert_eq(resolved_cancelled, true, "empty session prompt should cancel")
end

test_session_prompt_uses_native_command_line_input()
test_empty_session_prompt_notifies_and_cancels()
	end)
end)
