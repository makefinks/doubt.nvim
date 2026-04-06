local M = {}

local LIVE_EDIT_DEBOUNCE_MS = 120

function M.new(deps)
	local ctx = {
		ns = vim.api.nvim_create_namespace("doubt.nvim"),
		augroup = vim.api.nvim_create_augroup("doubt.nvim", { clear = true }),
		config = deps.config,
		state = deps.state,
		api = nil,
		expanded_claim = nil,
		focused_claim = nil,
		live_edit_timers = {},
	}

	function ctx.stop_live_edit_timer(bufnr)
		local timer = ctx.live_edit_timers[bufnr]
		if not timer then
			return
		end

		timer:stop()
		timer:close()
		ctx.live_edit_timers[bufnr] = nil
	end

	function ctx.clear_live_edit_timers()
		for bufnr in pairs(ctx.live_edit_timers) do
			ctx.stop_live_edit_timer(bufnr)
		end
	end

	function ctx.schedule_live_edit_refresh(bufnr)
		if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		local timer = ctx.live_edit_timers[bufnr]
		if not timer then
			timer = vim.uv.new_timer()
			ctx.live_edit_timers[bufnr] = timer
		end

		timer:stop()
		timer:start(LIVE_EDIT_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				ctx.stop_live_edit_timer(bufnr)
				return
			end

			local path = ctx.current_path(bufnr)
			if not path then
				return
			end

			local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
			local result = deps.state.classify_file_claims(path, {
				content = content,
			})
			if not result.changed then
				return
			end

			deps.state.save(deps.config.get(), ctx.notify)
			ctx.refresh_ui(bufnr)
		end))
	end

	function ctx.clear_expanded_claim()
		ctx.expanded_claim = nil
	end

	function ctx.clear_focused_claim()
		ctx.focused_claim = nil
	end

	function ctx.set_focused_claim(session_name, path, claim_id)
		ctx.focused_claim = {
			session_name = session_name,
			path = path,
			id = claim_id,
		}
	end

	function ctx.set_expanded_claim(path, claim_id)
		ctx.expanded_claim = {
			path = path,
			id = claim_id,
		}
	end

	function ctx.is_claim_expanded(path, claim)
		return ctx.expanded_claim ~= nil
			and ctx.expanded_claim.path == path
			and claim ~= nil
			and ctx.expanded_claim.id == claim.id
	end

	function ctx.focus_mode(path, claim)
		local focused = ctx.focused_claim
		if not focused or focused.session_name ~= deps.state.active_session_name() then
			return "normal"
		end

		if claim and focused.path == path and focused.id == claim.id then
			return "active"
		end

		return "dimmed"
	end

	function ctx.notify(msg, level)
		vim.notify(msg, level or vim.log.levels.INFO, { title = "doubt.nvim" })
	end

	function ctx.normalize_path(path)
		if not path or path == "" then
			return nil
		end

		return vim.fs.normalize(path)
	end

	function ctx.current_path(bufnr)
		bufnr = bufnr or vim.api.nvim_get_current_buf()
		return ctx.normalize_path(vim.api.nvim_buf_get_name(bufnr))
	end

	function ctx.refresh_ui(bufnr)
		if bufnr then
			deps.render.refresh_buffer(ctx, bufnr)
		end

		deps.render.refresh_visible_buffers(ctx, { skip_bufnr = bufnr })
		deps.panel.render(ctx)
	end

	return ctx
end

return M
