-- Public entrypoint that wires together config, state, rendering, and commands.
local claims = require("doubt.claims")
local context = require("doubt.app.context")
local session_ui = require("doubt.app.session_ui")
local commands = require("doubt.commands")
local config = require("doubt.config")
local export = require("doubt.export")
local healthcheck = require("doubt.healthcheck")
local input = require("doubt.input")
local keymaps = require("doubt.keymaps")
local panel = require("doubt.panel")
local render = require("doubt.render")
local state = require("doubt.state")

local M = {}

local ctx = context.new({
	config = config,
	panel = panel,
	render = render,
	state = state,
})

local clear_expanded_claim = ctx.clear_expanded_claim
local clear_focused_claim = ctx.clear_focused_claim
local set_focused_claim = ctx.set_focused_claim
local set_expanded_claim = ctx.set_expanded_claim
local clear_live_edit_timers = ctx.clear_live_edit_timers
local schedule_live_edit_refresh = ctx.schedule_live_edit_refresh
local stop_live_edit_timer = ctx.stop_live_edit_timer

local function prompt_session_name(opts, callback)
	session_ui.prompt_session_name(config, input, state, ctx, opts, callback)
end

local function with_active_session(callback)
	session_ui.with_active_session(state, prompt_session_name, M.start_session, callback)
end

local function confirm(message)
	return session_ui.confirm(message)
end

local function current_cursor_position()
	return session_ui.current_cursor_position()
end

local function add_claim(kind, opts)
	opts = opts or {}
	local path = ctx.current_path(opts.bufnr)
	if not path then
		ctx.notify("Current buffer has no file path", vim.log.levels.WARN)
		return
	end

	-- Claims are always stored in normalized form before any UI refresh happens.
	local file_state = state.ensure_file_entry(path)
	local start_line, start_col, end_line, end_col =
		claims.normalize_position_range(opts.start_line, opts.start_col, opts.end_line, opts.end_col)
	local normalized = claims.normalize_claim({
		id = tostring(vim.uv.hrtime()),
		kind = claims.normalize_claim_kind(kind),
		start_line = start_line,
		start_col = start_col,
		end_line = end_line,
		end_col = end_col,
		note = claims.normalize_note(opts.note),
		freshness = "fresh",
		anchor = claims.build_buffer_anchor(opts.bufnr, start_line, start_col, end_line, end_col),
	})
	table.insert(file_state.claims, normalized)
	claims.sort_claims(file_state.claims)

	state.save(config.get(), ctx.notify)
	ctx.refresh_ui(opts.bufnr)
end

local function resolve_note(kind, opts, callback)
	opts = opts or {}
	if opts.note ~= nil then
		callback(claims.normalize_note(opts.note))
		return
	end

	local input_config = config.get().input or {}
	local prompt = (claims.meta(kind) or {}).prompt or ((input_config.prompts or {})[kind])
	local line = opts.line
	local col = opts.col
	if line == nil or col == nil then
		line, col = current_cursor_position()
	end
	input.ask_note({
		border = input_config.border,
		col = col,
		default = opts.default,
		line = line,
		prompt = prompt,
		title = claims.normalize_claim_kind(kind),
		width = input_config.width,
	}, function(note, cancelled)
		if cancelled then
			return
		end

		callback(claims.normalize_note(note))
	end)
end

local function resolve_nearest_claim(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local path = ctx.current_path(bufnr)
	if not path then
		ctx.notify("Current buffer has no file path", vim.log.levels.WARN)
		return nil
	end

	if not state.has_active_session() then
		ctx.notify("No active doubt session", vim.log.levels.INFO)
		return nil
	end

	local file_state = state.current_files()[path]
	local claim_list = file_state and file_state.claims or nil
	if not claim_list or vim.tbl_isempty(claim_list) then
		ctx.notify("No claims in the current file", vim.log.levels.INFO)
		return nil
	end

	local line, col = current_cursor_position()
	local claim = claims.find_nearest_claim(claim_list, line, col)
	if not claim then
		ctx.notify("No claim found near the cursor", vim.log.levels.INFO)
		return nil
	end

	return {
		bufnr = bufnr,
		claim = claim,
		path = path,
	}
end

local function claim_range(kind, opts)
	if not claims.has_claim_kind(kind) then
		ctx.notify("Unknown claim kind", vim.log.levels.WARN)
		return
	end

	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local start_line, start_col, end_line, end_col = claims.current_span_from_command(opts, bufnr)
	with_active_session(function()
		resolve_note(kind, vim.tbl_extend("force", opts, {
			col = start_col,
			line = start_line,
		}), function(note)
			add_claim(kind, {
				bufnr = bufnr,
				start_line = start_line,
				start_col = start_col,
				end_line = end_line,
				end_col = end_col,
				note = note,
			})
		end)
	end)
end

local function leave_visual_mode()
	local keys = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	vim.api.nvim_feedkeys(keys, "x", false)
end

local function claim_visual(kind, opts)
	if not claims.has_claim_kind(kind) then
		ctx.notify("Unknown claim kind", vim.log.levels.WARN)
		return
	end

	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local start_line, start_col, end_line, end_col = claims.current_visual_span(bufnr)
	leave_visual_mode()
	with_active_session(function()
		resolve_note(kind, vim.tbl_extend("force", opts, {
			col = start_col,
			line = start_line,
		}), function(note)
			add_claim(kind, {
				bufnr = bufnr,
				start_line = start_line,
				start_col = start_col,
				end_line = end_line,
				end_col = end_col,
				note = note,
			})
		end)
	end)
end

function M.claim_range(kind, opts)
	claim_range(kind, opts)
end

function M.claim_visual(kind, opts)
	claim_visual(kind, opts)
end

function M.question_range(opts)
	claim_range("question", opts)
end

function M.reject_range(opts)
	claim_range("reject", opts)
end

function M.question_visual(opts)
	claim_visual("question", opts)
end

function M.reject_visual(opts)
	claim_visual("reject", opts)
end

function M.clear_buffer()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = ctx.current_path(bufnr)
	if not path then
		ctx.notify("Current buffer has no file path", vim.log.levels.WARN)
		return
	end

	local files = state.current_files()
	files[path] = nil
	if ctx.expanded_claim and ctx.expanded_claim.path == path then
		clear_expanded_claim()
	end
	if ctx.focused_claim and ctx.focused_claim.path == path then
		clear_focused_claim()
	end
	state.save(config.get(), ctx.notify)
	render.clear_buffer_claims(ctx, bufnr)
	ctx.refresh_ui(bufnr)
end

function M.delete_claim(opts)
	opts = opts or {}

	if not state.delete_claim(opts.path, opts.id) then
		ctx.notify("Unable to delete claim", vim.log.levels.WARN)
		return
	end

	if ctx.expanded_claim and ctx.expanded_claim.path == opts.path and ctx.expanded_claim.id == opts.id then
		clear_expanded_claim()
	end
	if ctx.focused_claim and ctx.focused_claim.path == opts.path and ctx.focused_claim.id == opts.id then
		clear_focused_claim()
	end

	state.save(config.get(), ctx.notify)
	ctx.refresh_ui(opts.bufnr)
end

function M.delete_nearest_claim(opts)
	local target = resolve_nearest_claim(opts)
	if not target then
		return
	end

	M.delete_claim({
		bufnr = target.bufnr,
		id = target.claim.id,
		path = target.path,
	})
end

function M.edit_nearest_claim_kind(opts)
	opts = opts or {}
	local target = resolve_nearest_claim(opts)
	if not target then
		return
	end

	local function apply_kind(kind)
		if not claims.has_claim_kind(kind) then
			ctx.notify("Unknown claim kind", vim.log.levels.WARN)
			return
		end

		if not state.update_claim(target.path, target.claim.id, { kind = kind }) then
			ctx.notify("Unable to update claim", vim.log.levels.WARN)
			return
		end

		state.save(config.get(), ctx.notify)
		ctx.refresh_ui(target.bufnr)
	end

	if opts.kind then
		apply_kind(opts.kind)
		return
	end

	local available_kinds = {}
	for _, kind in ipairs(claims.list_claim_kinds()) do
		if kind ~= target.claim.kind then
			table.insert(available_kinds, kind)
		end
	end

	if vim.tbl_isempty(available_kinds) then
		ctx.notify("No other claim kinds available", vim.log.levels.INFO)
		return
	end

	vim.ui.select(available_kinds, {
		prompt = "Change claim kind",
	}, function(kind)
		if not kind then
			return
		end

		apply_kind(kind)
	end)
end

function M.edit_nearest_claim_note(opts)
	opts = opts or {}
	local target = resolve_nearest_claim(opts)
	if not target then
		return
	end

	local function apply_note(note)
		if not state.update_claim(target.path, target.claim.id, { note = note }) then
			ctx.notify("Unable to update claim", vim.log.levels.WARN)
			return
		end

		state.save(config.get(), ctx.notify)
		ctx.refresh_ui(target.bufnr)
	end

	if opts.note ~= nil then
		apply_note(claims.normalize_note(opts.note))
		return
	end

	local input_config = config.get().input or {}
	local prompt = (claims.meta(target.claim.kind) or {}).prompt or ((input_config.prompts or {})[target.claim.kind])
	input.ask_note({
		border = input_config.border,
		col = target.claim.start_col,
		default = target.claim.note,
		line = target.claim.start_line,
		prompt = prompt,
		title = claims.normalize_claim_kind(target.claim.kind),
		width = input_config.width,
		winid = vim.api.nvim_get_current_win(),
	}, function(note, cancelled)
		if cancelled then
			return
		end

		apply_note(claims.normalize_note(note))
	end)
end

function M.toggle_nearest_claim(opts)
	opts = opts or {}
	local target = resolve_nearest_claim(opts)
	if not target then
		return
	end

	if ctx.is_claim_expanded(target.path, target.claim) then
		clear_expanded_claim()
	else
		set_expanded_claim(target.path, target.claim.id)
	end

	ctx.refresh_ui(target.bufnr)
end

function M.delete_file(opts)
	opts = opts or {}

	if not state.delete_file(opts.path) then
		ctx.notify("Unable to delete file", vim.log.levels.WARN)
		return
	end

	if ctx.focused_claim and ctx.focused_claim.path == opts.path then
		clear_focused_claim()
	end

	state.save(config.get(), ctx.notify)
	ctx.refresh_ui()
end

function M.focus_claim(opts)
	opts = opts or {}
	local session_name = state.active_session_name()
	if not session_name or session_name ~= opts.session_name then
		return
	end

	local path = ctx.normalize_path(opts.path)
	if not path or type(opts.id) ~= "string" or opts.id == "" then
		return
	end

	local current = ctx.focused_claim
	if current and current.session_name == session_name and current.path == path and current.id == opts.id then
		return
	end

	set_focused_claim(session_name, path, opts.id)
	ctx.refresh_ui()
end

function M.clear_focused_claim()
	if not ctx.focused_claim then
		return
	end

	clear_focused_claim()
	ctx.refresh_ui()
end

function M.open_panel()
	panel.open(ctx)
end

local function refresh_active_session_claims()
	local result = state.classify_current_session_claims()
	if result.changed_file_count > 0 then
		state.save(config.get(), ctx.notify)
	end

	return result
end

function M.refresh()
	refresh_active_session_claims()
	ctx.refresh_ui()
end

local function build_export_payload(opts)
	opts = opts or {}
	local session_name = state.active_session_name()
	if not session_name then
		ctx.notify("No active doubt session", vim.log.levels.INFO)
		return nil
	end

	refresh_active_session_claims()

	local files = state.current_files()
	local export_files = files
	local export_stats = {
		exportable_claim_count = 0,
		exportable_file_count = 0,
		skipped_stale_claims = 0,
	}

	if opts.trusted_only then
		export_files, export_stats = export.select_trusted_files(files)
	else
		export_stats.exportable_claim_count = 0
		for _, file_state in pairs(export_files) do
			export_stats.exportable_claim_count = export_stats.exportable_claim_count + #((file_state or {}).claims or {})
		end
		export_stats.exportable_file_count = vim.tbl_count(export_files)
	end

	local xml = export.build_session_xml(session_name, export_files)
	if not xml then
		ctx.notify("Unable to export doubt session", vim.log.levels.WARN)
		return nil
	end

	local text, err, template_name = export.build_export_text({
		export_config = config.get().export,
		files = export_files,
		session_name = session_name,
		template = opts.template,
		xml = xml,
	})
	if not text then
		ctx.notify(err, vim.log.levels.WARN)
		return nil
	end

	return {
		export_stats = export_stats,
		exportable_claim_count = export_stats.exportable_claim_count,
		session_name = session_name,
		files = files,
		export_files = export_files,
		template_name = template_name,
		text = text,
		xml = xml,
	}
end

local function pluralize_claim(count)
	if count == 1 then
		return "claim"
	end

	return "claims"
end

local function count_claim_kinds(files)
	local counts = {}
	for _, file_state in pairs(files or {}) do
		for _, claim in ipairs((file_state or {}).claims or {}) do
			local kind = claims.normalize_claim_kind(claim.kind)
			counts[kind] = (counts[kind] or 0) + 1
		end
	end
	return counts
end

function M.copy_export(opts)
	opts = opts or {}
	local payload = build_export_payload(vim.tbl_extend("force", opts, {
		trusted_only = true,
	}))
	if not payload then
		return
	end

	local skipped = (payload.export_stats or {}).skipped_stale_claims or 0
	if payload.exportable_claim_count == 0 then
		ctx.notify(
			string.format("No exportable claims remain; skipped %d stale %s", skipped, pluralize_claim(skipped)),
			vim.log.levels.WARN
		)
		return
	end

	local export_config = config.get().export or {}
	local register = export_config.register or "+"
	vim.fn.setreg(register, payload.text)
	if skipped > 0 then
		ctx.notify(
			string.format(
				"Copied doubt export to %s (%s, skipped %d stale %s)",
				register,
				payload.template_name,
				skipped,
				pluralize_claim(skipped)
			)
		)
	else
		ctx.notify(string.format("Copied doubt export to %s (%s)", register, payload.template_name))
	end
	return payload.text
end

function M.copy_export_with_picker()
	local template_names = M.list_export_templates()
	if vim.tbl_isempty(template_names) then
		ctx.notify("No doubt export templates configured", vim.log.levels.WARN)
		return
	end

	vim.ui.select(template_names, {
		prompt = "Choose doubt export template",
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if not choice then
			return
		end

		M.copy_export({ template = choice })
	end)
end

function M.copy_filtered_export()
	local payload = build_export_payload({ template = "raw" })
	if not payload then
		return
	end

	local kinds = claims.list_claim_kinds()
	local counts = count_claim_kinds(payload.files)
	local items = {}
	for _, kind in ipairs(kinds) do
		table.insert(items, {
			label = string.format("%s (%d)", kind, counts[kind] or 0),
			value = kind,
		})
	end

	local input_config = config.get().input or {}
	input.ask_checklist({
		border = input_config.border,
		hint = "<Space> toggle  <CR> export  q cancel",
		items = items,
		title = "filtered export",
		width = math.max(input_config.width or 50, 34),
	}, function(selected_kinds, cancelled)
		if cancelled then
			return
		end

		if type(selected_kinds) ~= "table" or vim.tbl_isempty(selected_kinds) then
			ctx.notify("No claim types selected for filtered export", vim.log.levels.INFO)
			return
		end

		local filtered_files = export.filter_files_by_kind(payload.files, selected_kinds)
		local xml = export.build_session_xml(payload.session_name, filtered_files)
		local register = (config.get().export or {}).register or "+"
		vim.fn.setreg(register, xml)
		ctx.notify(string.format("Copied doubt export to %s (filtered raw)", register))
	end)
end

function M.list_export_templates()
	return export.list_template_names(config.get().export)
end

function M.export_xml()
	local payload = build_export_payload({ template = "raw" })
	if not payload then
		return
	end

	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()
	local lines = vim.split(payload.xml, "\n", { plain = true })

	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].filetype = "xml"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

function M.healthcheck()
	return healthcheck.run({
		notify = ctx.notify,
	})
end

function M.open_state_file()
	local current_config = config.get()
	state.save(current_config, ctx.notify)
	vim.cmd("edit " .. vim.fn.fnameescape(current_config.state_path))
end

function M.start_session(opts)
	opts = opts or {}

	local function activate(session_name)
		local already_exists = state.get().sessions[session_name] ~= nil
		state.set_active_session(session_name)
		refresh_active_session_claims()
		clear_expanded_claim()
		clear_focused_claim()
		state.save(config.get(), ctx.notify)
		ctx.refresh_ui()
		if not opts.quiet then
			local verb = already_exists and "Resumed" or "Started"
			ctx.notify(string.format("%s doubt session: %s", verb, session_name))
		end
	end

	if opts.name then
		local session_name = state.normalize_session_name(opts.name)
		if not session_name then
			ctx.notify("Session name cannot be empty", vim.log.levels.WARN)
			return
		end

		activate(session_name)
		return
	end

	prompt_session_name({
		prompt = "Start session: ",
		title = "new doubt session",
	}, function(session_name, cancelled)
		if cancelled then
			return
		end

		activate(session_name)
	end)
end

function M.resume_session(opts)
	opts = opts or {}

	local function activate(session_name)
		state.set_active_session(session_name)
		refresh_active_session_claims()
		clear_expanded_claim()
		clear_focused_claim()
		state.save(config.get(), ctx.notify)
		ctx.refresh_ui()
		if not opts.quiet then
			ctx.notify(string.format("Resumed doubt session: %s", session_name))
		end
	end

	if opts.name then
		local session_name = state.normalize_session_name(opts.name)
		if not session_name or not state.get().sessions[session_name] then
			ctx.notify("Unknown doubt session", vim.log.levels.WARN)
			return
		end

		activate(session_name)
		return
	end

	local session_names = state.list_sessions()
	if vim.tbl_isempty(session_names) then
		ctx.notify("No saved doubt sessions yet", vim.log.levels.INFO)
		return
	end

	vim.ui.select(session_names, {
		prompt = "Resume doubt session",
		format_item = function(item)
			if item == state.active_session_name() then
				return item .. " (active)"
			end

			return item
		end,
	}, function(choice)
		if not choice then
			return
		end

		activate(choice)
	end)
end

function M.stop_session()
	local session_name = state.active_session_name()
	if not session_name then
		ctx.notify("No active doubt session", vim.log.levels.INFO)
		return
	end

	state.stop_session()
	clear_expanded_claim()
	clear_focused_claim()
	state.save(config.get(), ctx.notify)
	ctx.refresh_ui()
	ctx.notify(string.format("Stopped doubt session: %s", session_name))
end

function M.delete_session(opts)
	opts = opts or {}

	local function destroy(session_name)
		local deleting_active = session_name == state.active_session_name()
		if not confirm(string.format("Delete doubt session '%s'?", session_name)) then
			return
		end

		if not state.delete_session(session_name) then
			ctx.notify("Unknown doubt session", vim.log.levels.WARN)
			return
		end

		if deleting_active then
			clear_expanded_claim()
			clear_focused_claim()
		end

		state.save(config.get(), ctx.notify)
		ctx.refresh_ui()
		ctx.notify(string.format("Deleted doubt session: %s", session_name))
	end

	if opts.name then
		local session_name = state.normalize_session_name(opts.name)
		if not session_name or not state.get().sessions[session_name] then
			ctx.notify("Unknown doubt session", vim.log.levels.WARN)
			return
		end

		destroy(session_name)
		return
	end

	local session_names = state.list_sessions()
	if vim.tbl_isempty(session_names) then
		ctx.notify("No saved doubt sessions yet", vim.log.levels.INFO)
		return
	end

	vim.ui.select(session_names, {
		prompt = "Delete doubt session",
		format_item = function(item)
			if item == state.active_session_name() then
				return item .. " (active)"
			end

			return item
		end,
	}, function(choice)
		if not choice then
			return
		end

		destroy(choice)
	end)
end

function M.rename_session(opts)
	opts = opts or {}

	local function rename(old_name, new_name)
		if not state.rename_session(old_name, new_name) then
			ctx.notify("Unable to rename doubt session", vim.log.levels.WARN)
			return false
		end

		clear_expanded_claim()
		clear_focused_claim()
		state.save(config.get(), ctx.notify)
		ctx.refresh_ui()
		ctx.notify(string.format("Renamed doubt session: %s → %s", old_name, new_name))
		return true
	end

	local old_name = state.normalize_session_name(opts.name)
	if not old_name then
		ctx.notify("Session name cannot be empty", vim.log.levels.WARN)
		return false
	end

	if not state.get().sessions[old_name] then
		ctx.notify("Unknown doubt session", vim.log.levels.WARN)
		return false
	end

	local provided_new_name = state.normalize_session_name(opts.new_name)
	if opts.new_name ~= nil then
		if not provided_new_name then
			ctx.notify("Session name cannot be empty", vim.log.levels.WARN)
			return false
		end

		if provided_new_name == old_name then
			ctx.notify("Session name is unchanged", vim.log.levels.WARN)
			return false
		end

		if state.get().sessions[provided_new_name] then
			ctx.notify("Session name already exists", vim.log.levels.WARN)
			return false
		end

		return rename(old_name, provided_new_name)
	end

	prompt_session_name({
		default = old_name,
		prompt = "Rename session to: ",
		title = "rename doubt session",
	}, function(new_name, cancelled)
		if cancelled then
			return
		end

		if new_name == old_name then
			ctx.notify("Session name is unchanged", vim.log.levels.WARN)
			return
		end

		if state.get().sessions[new_name] then
			ctx.notify("Session name already exists", vim.log.levels.WARN)
			return
		end

		rename(old_name, new_name)
	end)

	return true
end

function M.setup(opts)
	ctx.api = M
	clear_live_edit_timers()
	config.setup(opts)
	config.set_highlights()
	claims.configure(config.get().claim_kinds)
	local workspace = ctx.normalize_path(vim.fn.getcwd())
	state.load(config.get(), ctx.normalize_path, ctx.notify, workspace)
	vim.api.nvim_clear_autocmds({ group = ctx.augroup })

	-- Decorations are derived from state, so entering a window is enough to restore them.
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = ctx.augroup,
		callback = function(args)
			render.refresh_buffer(ctx, args.buf)
		end,
	})

	-- Keep panel wrapping and virtual text layout in sync with window size changes.
	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = ctx.augroup,
		callback = function()
			ctx.refresh_ui()
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = ctx.augroup,
		callback = function(args)
			schedule_live_edit_refresh(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = ctx.augroup,
		callback = function(args)
			stop_live_edit_timer(args.buf)
		end,
	})

	commands.register(M)
	keymaps.register(M, config.get().keymaps)
end

return M
