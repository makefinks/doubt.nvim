local claims = require("doubt.claims")

local M = {}
local CLAIM_KIND_CELL_WIDTH = 8

local function count_claims(files)
	local total = 0
	for _, file_state in pairs(files) do
		total = total + #(file_state.claims or {})
	end

	return total
end

local function count_stale_claims(claim_list)
	local total = 0
	for _, claim in ipairs(claim_list or {}) do
		if claim.freshness == "stale" then
			total = total + 1
		end
	end

	return total
end

local function count_stale_files(files)
	local total = 0
	for _, file_state in pairs(files or {}) do
		total = total + count_stale_claims(file_state.claims)
	end

	return total
end

local function with_defaults(item)
	item.highlights = item.highlights or {}
	return item
end

local function add_highlight(item, start_col, end_col, hl_group)
	table.insert(item.highlights, {
		start_col = start_col,
		end_col = end_col,
		hl_group = hl_group,
	})
end

local function split_long_word(word, width)
	if width <= 0 then
		return { word }
	end

	if vim.fn.strdisplaywidth(word) <= width then
		return { word }
	end

	local pieces = {}
	local total_chars = vim.fn.strchars(word)
	local char_index = 0

	while char_index < total_chars do
		local chunk = ""
		local chunk_width = 0

		while char_index < total_chars do
			local ch = vim.fn.strcharpart(word, char_index, 1)
			local ch_width = vim.fn.strdisplaywidth(ch)

			if chunk ~= "" and chunk_width + ch_width > width then
				break
			end

			if chunk == "" and ch_width > width then
				chunk = ch
				char_index = char_index + 1
				break
			end

			chunk = chunk .. ch
			chunk_width = chunk_width + ch_width
			char_index = char_index + 1
		end

		table.insert(pieces, chunk)
	end

	return pieces
end

local function wrap_text(text, width)
	width = math.max(width or 1, 1)
	text = vim.trim((text or ""):gsub("[\r\n]+", " "))
	if text == "" then
		return { "" }
	end

	local words = {}
	for word in text:gmatch("%S+") do
		for _, piece in ipairs(split_long_word(word, width)) do
			table.insert(words, piece)
		end
	end

	local lines = {}
	local current = ""
	local current_width = 0

	for _, word in ipairs(words) do
		local word_width = vim.fn.strdisplaywidth(word)
		if current == "" then
			current = word
			current_width = word_width
		elseif current_width + 1 + word_width <= width then
			current = current .. " " .. word
			current_width = current_width + 1 + word_width
		else
			table.insert(lines, current)
			current = word
			current_width = word_width
		end
	end

	if current ~= "" then
		table.insert(lines, current)
	end

	return lines
end

local function add_session_summary(lines, session_name, files, active)
	local claim_count = count_claims(files)
	local stale_count = count_stale_files(files)
	local session_line = with_defaults({
		kind = "session",
		active = active,
		session_name = session_name,
		text = string.format("Session  %s", session_name),
	})
	add_highlight(session_line, 0, 7, "DoubtPanelMuted")
	add_highlight(session_line, 9, #session_line.text, active and "DoubtPanelSession" or "DoubtPanelFile")
	table.insert(lines, session_line)

	local summary_text = string.format("Files    %d    Claims    %d", vim.tbl_count(files), claim_count)
	if stale_count > 0 then
		summary_text = string.format("%s    Stale    %d", summary_text, stale_count)
	end

	local summary = with_defaults({
		kind = "summary",
		text = summary_text,
	})
	add_highlight(summary, 0, 5, "DoubtPanelMuted")
	add_highlight(summary, 9, 9 + #tostring(vim.tbl_count(files)), "DoubtPanelCount")
	add_highlight(summary, 14, 20, "DoubtPanelMuted")
	add_highlight(summary, #summary.text - #tostring(claim_count), #summary.text, "DoubtPanelCount")
	if stale_count > 0 then
		local stale_label_col = summary.text:find("Stale", 1, true)
		local stale_count_text = tostring(stale_count)
		local stale_count_col = summary.text:find(stale_count_text, stale_label_col and (stale_label_col + #"Stale") or 1, true)
		if stale_label_col then
			add_highlight(summary, stale_label_col - 1, stale_label_col - 1 + #"Stale", "DoubtPanelStale")
		end
		if stale_count_col then
			add_highlight(summary, stale_count_col - 1, stale_count_col - 1 + #stale_count_text, "DoubtPanelStale")
		end
	end
	table.insert(lines, summary)
end

local function build_file_line(config, path, file_state)
	local relative = vim.fn.fnamemodify(path, ":.")
	local count = #(file_state.claims or {})
	local stale_count = count_stale_claims(file_state.claims)
	local text = string.format("%s %s  [%d]", config.signs.file, relative, count)
	if stale_count > 0 then
		text = string.format("%s  [stale %d]", text, stale_count)
	end
	local item = with_defaults({
		kind = "file",
		path = path,
		text = text,
	})

	add_highlight(item, 0, 1, "DoubtFile")
	add_highlight(item, 2, 2 + #relative, "DoubtPanelFile")
	local count_token = string.format("[%d]", count)
	local count_col = text:find(count_token, 1, true)
	if count_col then
		add_highlight(item, count_col - 1, count_col - 1 + #count_token, "DoubtPanelCount")
	end
	if stale_count > 0 then
		local stale_token = string.format("[stale %d]", stale_count)
		local stale_col = text:find(stale_token, 1, true)
		if stale_col then
			add_highlight(item, stale_col - 1, stale_col - 1 + #stale_token, "DoubtPanelStale")
		end
	end
	return item
end

local function build_claim_lines(path, claim, panel_width)
	local start_col = (claim.start_col or 0) + 1
	local end_col = claim.end_col and tostring(claim.end_col) or "EOL"
	local line_label = string.format("L%d:C%d-L%d:C%s", claim.start_line + 1, start_col, claim.end_line + 1, end_col)

	local kind_label = string.upper(claim.kind)
	local kind_cell = string.format("%-" .. CLAIM_KIND_CELL_WIDTH .. "s", kind_label)
	local meta = claims.meta(claim.kind)
	local _, note = claims.inline_text(claim)
	local pw = panel_width or vim.o.columns
	local items = {}

	if pw >= 50 then
		local prefix = string.format("  %-16s  %s ", line_label, kind_cell)
		local kind_col = string.find(prefix, kind_cell, 1, true)
		local continuation_prefix = string.rep(" ", vim.fn.strdisplaywidth(prefix))
		local note_width = math.max(pw - vim.fn.strdisplaywidth(prefix), 1)
		local wrapped_note = wrap_text(note, note_width)

		for idx, note_line in ipairs(wrapped_note) do
			local text = (idx == 1 and prefix or continuation_prefix) .. note_line
			local item = with_defaults({
				kind = "claim",
				id = claim.id,
				active_hl = claim.freshness == "stale" and (meta.stale_hl or meta.hl) or meta.hl,
				path = path,
				line = claim.start_line + 1,
				col = claim.start_col or 0,
				text = text,
			})

			if idx == 1 then
				add_highlight(item, 2, 2 + #line_label, "DoubtPanelMuted")
				if kind_col then
					add_highlight(item, kind_col - 1, kind_col - 1 + #kind_cell, meta.hl)
				end
			end

			if claim.note == "" then
				add_highlight(item, vim.fn.strdisplaywidth(prefix), #text, "DoubtPanelMuted")
			end

			table.insert(items, item)
		end
	else
		table.insert(items, with_defaults({
			kind = "claim",
			id = claim.id,
			active_hl = claim.freshness == "stale" and (meta.stale_hl or meta.hl) or meta.hl,
			path = path,
			line = claim.start_line + 1,
			col = claim.start_col or 0,
			text = "  " .. line_label,
		}))
		add_highlight(items[#items], 2, 2 + #line_label, "DoubtPanelMuted")

		local meta_prefix = string.format("    %s ", kind_cell)
		local meta_kind_col = string.find(meta_prefix, kind_cell, 1, true)
		local meta_cont = string.rep(" ", vim.fn.strdisplaywidth(meta_prefix))
		local note_width = math.max(pw - vim.fn.strdisplaywidth(meta_prefix), 1)
		local wrapped_note = wrap_text(note, note_width)

		for idx, note_line in ipairs(wrapped_note) do
			local text = (idx == 1 and meta_prefix or meta_cont) .. note_line
			local item = with_defaults({
				kind = "claim",
				id = claim.id,
				active_hl = claim.freshness == "stale" and (meta.stale_hl or meta.hl) or meta.hl,
				path = path,
				line = claim.start_line + 1,
				col = claim.start_col or 0,
				text = text,
			})

			if idx == 1 and meta_kind_col then
				add_highlight(item, meta_kind_col - 1, meta_kind_col - 1 + #kind_cell, meta.hl)
			end

			if claim.note == "" then
				add_highlight(item, vim.fn.strdisplaywidth(meta_prefix), #text, "DoubtPanelMuted")
			else
				add_highlight(item, vim.fn.strdisplaywidth(meta_prefix), #text, meta.hl)
			end

			table.insert(items, item)
		end
	end

	return items
end

local function build_saved_session_line(config, session_name, session_state)
	local files = (session_state or {}).files or {}
	local file_count = vim.tbl_count(files)
	local claim_count = count_claims(files)
	local stale_count = count_stale_files(files)
	local text = string.format(
		"%s %s  [%d files, %d claims]",
		config.signs.file,
		session_name,
		file_count,
		claim_count
	)
	if stale_count > 0 then
		text = string.format("%s [stale %d]", text, stale_count)
	end
	local item = with_defaults({
		kind = "session",
		active = false,
		session_name = session_name,
		text = text,
	})

	add_highlight(item, 0, 1, "DoubtFile")
	add_highlight(item, 2, 2 + #session_name, "DoubtPanelFile")
	local claim_token = string.format("%d claims]", claim_count)
	local claim_col = text:find(claim_token, 1, true)
	if claim_col then
		add_highlight(item, claim_col - 1, claim_col - 1 + #claim_token, "DoubtPanelCount")
	end
	if stale_count > 0 then
		local stale_token = string.format("[stale %d]", stale_count)
		local stale_col = text:find(stale_token, 1, true)
		if stale_col then
			add_highlight(item, stale_col - 1, stale_col - 1 + #stale_token, "DoubtPanelStale")
		end
	end
	return item
end

function M.build_lines(ctx, panel_width)
	local config = ctx.config.get()
	local state = ctx.state
	local files = state.current_files()
	local session_name = state.active_session_name()
	local lines = {
		with_defaults({ kind = "title", text = "doubt.nvim" }),
	}

	if session_name then
		add_session_summary(lines, session_name, files, true)
		table.insert(lines, with_defaults({ kind = "muted", text = "" }))
		local help_hint = with_defaults({ kind = "muted", text = "press ? for help" })
		add_highlight(help_hint, 6, 7, "DoubtPanelKey")
		table.insert(lines, help_hint)
		table.insert(lines, with_defaults({ kind = "muted", text = "" }))

		if vim.tbl_isempty(files) then
			table.insert(lines, with_defaults({ kind = "muted", text = "No claims in this session yet." }))
			table.insert(lines, with_defaults({ kind = "muted", text = "Use :DoubtClaim {kind} or a kind-specific command to add one." }))
			return lines
		end

		table.insert(lines, with_defaults({ kind = "section", text = "Claims" }))
		local paths = vim.tbl_keys(files)
		table.sort(paths)
		for _, path in ipairs(paths) do
			local file_state = files[path]
			table.insert(lines, build_file_line(config, path, file_state))

			for _, claim in ipairs(file_state.claims or {}) do
				for _, item in ipairs(build_claim_lines(path, claim, panel_width)) do
					table.insert(lines, item)
				end
			end

			table.insert(lines, with_defaults({ kind = "muted", text = "" }))
		end

		return lines
	end

	local inactive = with_defaults({ kind = "muted", text = "Session  inactive" })
	add_highlight(inactive, 0, 7, "DoubtPanelMuted")
	add_highlight(inactive, 9, #inactive.text, "DoubtPanelCount")
	table.insert(lines, inactive)

	table.insert(lines, with_defaults({ kind = "muted", text = "" }))
	local help_hint = with_defaults({ kind = "muted", text = "press ? for help" })
	add_highlight(help_hint, 6, 7, "DoubtPanelKey")
	table.insert(lines, help_hint)
	table.insert(lines, with_defaults({ kind = "muted", text = "" }))
	table.insert(lines, with_defaults({ kind = "muted", text = "Saved sessions below are scoped to this workspace." }))
	table.insert(lines, with_defaults({ kind = "muted", text = "Claims are hidden until a session is active." }))

	local session_names = state.list_sessions()
	if vim.tbl_isempty(session_names) then
		table.insert(lines, with_defaults({ kind = "muted", text = "No saved sessions for this workspace yet." }))
		return lines
	end

	table.insert(lines, with_defaults({ kind = "section", text = "Saved Sessions" }))
	for _, name in ipairs(session_names) do
		table.insert(lines, build_saved_session_line(config, name, state.get().sessions[name]))
	end

	return lines
end

return M
