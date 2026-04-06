local M = {}

function M.prompt_session_name(config, input, state, ctx, opts, callback)
	opts = opts or {}
	local input_config = config.get().input or {}
	input.ask_text({
		border = input_config.border,
		default = opts.default,
		prompt = opts.prompt or "Session name: ",
		title = opts.title or "session",
		width = input_config.width,
	}, function(name, cancelled)
		if cancelled then
			callback(nil, true)
			return
		end

		local normalized_name = state.normalize_session_name(name)
		if not normalized_name then
			ctx.notify("Session name cannot be empty", vim.log.levels.WARN)
			callback(nil, true)
			return
		end

		callback(normalized_name, false)
	end)
end

function M.ensure_active_session(state, prompt_session_name, start_session, callback)
	if state.has_active_session() then
		callback(state.active_session_name())
		return
	end

	prompt_session_name({
		prompt = "Start session: ",
		title = "new doubt session",
	}, function(session_name, cancelled)
		if cancelled then
			return
		end

		start_session({ name = session_name, quiet = true })
		callback(session_name)
	end)
end

function M.with_active_session(state, prompt_session_name, start_session, callback)
	M.ensure_active_session(state, prompt_session_name, start_session, function()
		callback()
	end)
end

function M.confirm(message)
	return vim.fn.confirm(message, "&Delete\n&Cancel", 2) == 1
end

function M.current_cursor_position()
	local cursor = vim.api.nvim_win_get_cursor(0)
	return math.max(cursor[1] - 1, 0), math.max(cursor[2], 0)
end

return M
