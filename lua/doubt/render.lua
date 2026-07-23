-- Buffer decorations: extmarks, signs, and visible-buffer refresh.
local claims = require("doubt.claims")

local M = {}
local find_markdown_span
local MARKDOWN_SPACE_SENTINEL = "\001doubt_md_space\001"

local MARKDOWN_DELIMITERS = {
	{ marker = "`", hl_group = "DoubtInlineMarkdownCode" },
	{ marker = "**", hl_group = "DoubtInlineMarkdownBold" },
	{ marker = "__", hl_group = "DoubtInlineMarkdownBold" },
	{ marker = "~~", hl_group = "DoubtInlineMarkdownStrike" },
	{ marker = "*", hl_group = "DoubtInlineMarkdownItalic" },
	{ marker = "_", hl_group = "DoubtInlineMarkdownItalic", word_boundary = true },
}

local function compact_inline_text(text, max_width)
	if not max_width or max_width <= 0 then
		return text
	end

	if vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end

	local total_chars = vim.fn.strchars(text)
	for keep = total_chars - 1, 0, -1 do
		local hidden_chars = total_chars - keep
		local compact = string.format("%s... %d more", vim.fn.strcharpart(text, 0, keep), hidden_chars)
		if vim.fn.strdisplaywidth(compact) <= max_width then
			return compact
		end
	end

	return string.format("... %d more", total_chars)
end

local function wrap_inline_text(text, max_width)
	if not max_width or max_width <= 0 then
		return { text }
	end

	local protected = {}
	local index = 1
	while index <= #text do
		local span = find_markdown_span(text, index)
		if span and span.open_start == index then
			local marked = text:sub(span.open_start, span.close_end - 1):gsub(" ", MARKDOWN_SPACE_SENTINEL)
			table.insert(protected, marked)
			index = span.close_end
		else
			table.insert(protected, text:sub(index, index))
			index = index + 1
		end
	end
	local protected_text = table.concat(protected)

	local lines = {}
	local current = ""
	for word in string.gmatch(protected_text, "%S+") do
		word = word:gsub(MARKDOWN_SPACE_SENTINEL, " ")
		local candidate = current == "" and word or (current .. " " .. word)
		if vim.fn.strdisplaywidth(candidate) <= max_width then
			current = candidate
		elseif current ~= "" then
			table.insert(lines, current)
			current = word
		else
			local start = 0
			while start < vim.fn.strchars(word) do
				local best = nil
				for stop = start + 1, vim.fn.strchars(word) do
					local chunk = vim.fn.strcharpart(word, start, stop - start)
					if vim.fn.strdisplaywidth(chunk) > max_width then
						break
					end
					best = chunk
				end
				best = best or vim.fn.strcharpart(word, start, 1)
				table.insert(lines, best)
				start = start + vim.fn.strchars(best)
			end
			current = ""
		end
	end

	if current ~= "" then
		table.insert(lines, current)
	end

	if vim.tbl_isempty(lines) then
		return { "" }
	end

	return lines
end

local function compact_inline_lines(text, max_width, max_lines)
	local wrapped = wrap_inline_text(text, max_width)
	if #wrapped <= max_lines then
		return wrapped
	end

	local total_chars = vim.fn.strchars(text)
	for keep = total_chars - 1, 0, -1 do
		local prefix = vim.fn.strcharpart(text, 0, keep):gsub("%s+$", "")
		local hidden_chars = total_chars - vim.fn.strchars(prefix)
		local marker = string.format("... %d more", hidden_chars):gsub(" ", MARKDOWN_SPACE_SENTINEL)
		local candidate = prefix == "" and marker or (prefix .. " " .. marker)
		local lines = wrap_inline_text(candidate, max_width)
		if #lines <= max_lines then
			return lines
		end
	end

	return { compact_inline_text(text, max_width) }
end

local function pad(width)
	return string.rep(" ", math.max(width, 1))
end

local function display_width(text)
	return vim.fn.strdisplaywidth(text or "")
end

local function line_byte_length(bufnr, line)
	local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
	return #text
end

local function is_word_char(char)
	return char ~= "" and char:match("[%w_]") ~= nil
end

local function valid_marker_boundary(text, marker, open_start, close_start, close_end, word_boundary)
	local content_start = open_start + #marker
	if close_start <= content_start then
		return false
	end

	if text:sub(content_start, content_start):match("%s") or text:sub(close_start - 1, close_start - 1):match("%s") then
		return false
	end

	if word_boundary then
		if is_word_char(text:sub(open_start - 1, open_start - 1)) or is_word_char(text:sub(close_end, close_end)) then
			return false
		end
	end

	return true
end

find_markdown_span = function(text, index)
	for _, delimiter in ipairs(MARKDOWN_DELIMITERS) do
		local marker = delimiter.marker
		if text:sub(index, index + #marker - 1) == marker then
			local content_start = index + #marker
			local close_start = text:find(marker, content_start, true)
			if close_start then
				local close_end = close_start + #marker
				if valid_marker_boundary(text, marker, index, close_start, close_end, delimiter.word_boundary) then
					return {
						open_start = index,
						content_start = content_start,
						close_start = close_start,
						close_end = close_end,
						hl_group = delimiter.hl_group,
					}
				end
			end
		end
	end

	return nil
end

local function inline_markdown_chunks(text, base_hl)
	local chunks = {}
	local index = 1
	while index <= #text do
		local span = find_markdown_span(text, index)
		if span then
			if span.open_start > index then
				table.insert(chunks, { text:sub(index, span.open_start - 1), base_hl })
			end
			table.insert(chunks, { text:sub(span.content_start, span.close_start - 1), span.hl_group })
			index = span.close_end
		else
			local next_index = #text + 1
			for seek = index + 1, #text do
				if find_markdown_span(text, seek) then
					next_index = seek
					break
				end
			end
			table.insert(chunks, { text:sub(index, next_index - 1), base_hl })
			index = next_index
		end
	end

	if vim.tbl_isempty(chunks) then
		return { { text, base_hl } }
	end

	return chunks
end

local function prefixed_markdown_chunks(prefix, text, base_hl)
	local chunks = {}
	if prefix ~= "" then
		table.insert(chunks, { prefix, base_hl })
	end
	for _, chunk in ipairs(inline_markdown_chunks(text, base_hl)) do
		table.insert(chunks, chunk)
	end
	return chunks
end

local function chunks_width(chunks)
	local width = 0
	for _, chunk in ipairs(chunks or {}) do
		width = width + display_width(chunk[1])
	end
	return width
end

local function append_chunks(target, source)
	for _, chunk in ipairs(source or {}) do
		table.insert(target, chunk)
	end
	return target
end

local function clamp_row(bufnr, line)
	local last_row = math.max(vim.api.nvim_buf_line_count(bufnr) - 1, 0)
	line = math.max(line or 0, 0)
	return math.min(line, last_row)
end

local function claim_rows(bufnr, claim)
	local start_row = clamp_row(bufnr, claim.start_line)
	local end_row = clamp_row(bufnr, claim.end_line)
	if end_row < start_row then
		end_row = start_row
	end
	return start_row, end_row
end

local function clamp_col(bufnr, line, col)
	col = math.max(col or 0, 0)
	return math.min(col, line_byte_length(bufnr, line))
end

local function claim_end_col(bufnr, claim, end_row)
	if claim.end_col ~= nil then
		return clamp_col(bufnr, end_row, claim.end_col)
	end
	return line_byte_length(bufnr, end_row)
end

function M.render_inline_editor(ctx, bufnr, edit)
	local claim = edit.claim
	local meta = claims.meta(claim.kind)
	local config = ctx.config.get()
	local start_row, end_row = claim_rows(bufnr, claim)
	local start_col = clamp_col(bufnr, start_row, claim.start_col)
	local prefix = config.inline_notes.prefix or ""
	local inline_label = (claims.inline_text(claim))
	local label_width = display_width(inline_label)
	local body_width = math.max(edit.body_width or config.inline_notes.max_width or 1, 1)
	local editing_badge = " EDITING "
	local content_width = math.max(label_width + body_width + 2, display_width(editing_badge))
	local right_border_width = content_width - label_width - body_width - 1
	local rows = math.max(edit.rows or 1, 1)
	local virt_lines = {
		{
			{ prefix, "DoubtInlinePrefix" },
			{ pad(content_width - display_width(editing_badge)), "DoubtInlineEditingBar" },
			{ editing_badge, "DoubtInlineEditingBadge" },
		},
	}

	for row = 1, rows do
		table.insert(virt_lines, {
			{ prefix, "DoubtInlinePrefix" },
			{ row == 1 and inline_label or pad(label_width), row == 1 and meta.inline_label_hl or "DoubtInlineEditingBar" },
			{ " ", meta.inline_text_hl },
			{ pad(body_width), meta.inline_text_hl },
			{ pad(right_border_width), "DoubtInlineEditingBar" },
		})
	end
	table.insert(virt_lines, {
		{ prefix, "DoubtInlinePrefix" },
		{ pad(content_width), "DoubtInlineEditingBar" },
	})

	vim.api.nvim_buf_set_extmark(bufnr, ctx.ns, start_row, start_col, {
		end_row = end_row,
		end_col = claim_end_col(bufnr, claim, end_row),
		hl_group = meta.hl,
		hl_eol = true,
		priority = 120,
	})
	vim.api.nvim_buf_set_extmark(bufnr, ctx.ns, start_row, start_col, {
		sign_text = meta.sign or config.signs[claim.kind] or config.signs.file,
		sign_hl_group = meta.hl,
		priority = 150,
		virt_lines = virt_lines,
		virt_lines_above = true,
	})
end

function M.clear_buffer_claims(ctx, bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ctx.ns, 0, -1)
end

-- Each claim paints its range and places a sign at the first line.
function M.render_claim(ctx, bufnr, claim)
	local inline_edit = ctx.current_inline_edit and ctx.current_inline_edit() or nil
	if inline_edit and inline_edit.bufnr == bufnr and inline_edit.claim.id == claim.id then
		M.render_inline_editor(ctx, bufnr, inline_edit)
		return
	end

	local meta = claims.meta(claim.kind)
	local config = ctx.config.get()
	local path = ctx.current_path(bufnr)
	local start_row, end_row = claim_rows(bufnr, claim)
	local start_col = clamp_col(bufnr, start_row, claim.start_col)
	local review_status = ctx.claim_review_status and ctx.claim_review_status(claim.id) or nil
	local addressed = review_status and review_status.addressed == true
	local effective_stale = claim.freshness == "stale" and not addressed
	local claim_hl = effective_stale and (meta.stale_hl or meta.hl) or meta.hl
	local inline_label_hl = meta.inline_label_hl
	local inline_text_hl = meta.inline_text_hl
	local focus_mode = ctx.focus_mode and ctx.focus_mode(path, claim) or "normal"
	if focus_mode == "dimmed" then
		claim_hl = effective_stale and (meta.dim_stale_hl or meta.dim_hl or claim_hl) or (meta.dim_hl or claim_hl)
		inline_label_hl = meta.dim_inline_label_hl or inline_label_hl
		inline_text_hl = meta.dim_inline_text_hl or inline_text_hl
	end
	local inline_label, inline_text = claims.inline_text(claim, { hide_freshness = addressed })
	local review_badge = addressed
		and string.format(" %s ", (review_status.outcome or "addressed"):gsub("_", " "))
		or nil
	local expanded = ctx.is_claim_expanded and ctx.is_claim_expanded(ctx.current_path(bufnr), claim)
	local body_lines = expanded
		and wrap_inline_text(inline_text, config.inline_notes.max_width)
		or compact_inline_lines(inline_text, config.inline_notes.max_width, 2)
	local body_chunks = {}
	for idx, body_line in ipairs(body_lines) do
		body_chunks[idx] = prefixed_markdown_chunks(" ", body_line, inline_text_hl)
	end
	local right_padding = math.max(config.inline_notes.padding_right or 0, 0)
	local prefix = config.inline_notes.prefix or ""
	local inline_notes_layout = ctx.inline_notes_layout and ctx.inline_notes_layout() or "block"
	local render_block_notes = config.inline_notes.enabled and inline_notes_layout == "block"
	local inline_note = config.inline_notes.enabled
		and inline_notes_layout == "inline"
		and (expanded and inline_text or compact_inline_text(inline_text, config.inline_notes.max_width))
		or nil
	local label_width = display_width(inline_label)
	local heading_chunks = { { inline_label, inline_label_hl } }
	local content_width = 0
	for idx in ipairs(body_lines) do
		content_width = math.max(content_width, label_width + chunks_width(body_chunks[idx]))
	end
	content_width = math.max(content_width + right_padding, display_width(review_badge))
	local first_content_chunks = append_chunks({}, heading_chunks)
	append_chunks(first_content_chunks, body_chunks[1])
	local inline_chunks = nil
	if inline_note then
		inline_chunks = append_chunks({ { " ", "Normal" } }, heading_chunks)
		if review_badge then
			append_chunks(inline_chunks, {
				{ " ", "DoubtInlineBar" },
				{ review_badge, "DoubtInlineAddressed" },
			})
		end
		append_chunks(inline_chunks, prefixed_markdown_chunks(" ", inline_note, inline_text_hl))
	end
	local top_row = {
		{
			prefix,
			"DoubtInlinePrefix",
		},
	}
	if review_badge then
		local badge_padding = content_width - display_width(review_badge)
		if badge_padding > 0 then
			table.insert(top_row, { pad(badge_padding), "DoubtInlineBar" })
		end
		table.insert(top_row, { review_badge, "DoubtInlineAddressed" })
	else
		table.insert(top_row, { pad(content_width), "DoubtInlineBar" })
	end

	-- Render inline notes as a rectangular virtual block so wrapped rows align
	-- with the label and background bar instead of drifting by content width.
	local virt_lines = render_block_notes and {
		top_row,
		{
			{
				prefix,
				"DoubtInlinePrefix",
			},
		unpack(first_content_chunks),
	},
	} or nil

	if virt_lines then
		local first_row_width = label_width + chunks_width(body_chunks[1])
		local first_row_padding = content_width - first_row_width
		if first_row_padding > 0 then
			table.insert(virt_lines[2], {
				pad(first_row_padding),
				"DoubtInlineBar",
			})
		end
	end

	if virt_lines then
		for idx = 2, #body_lines do
			local row_width = label_width + chunks_width(body_chunks[idx])
			local row_padding = content_width - row_width
			local row = {
				{
					prefix,
					"DoubtInlinePrefix",
				},
				{
					pad(label_width),
					"DoubtInlineBar",
				},
				unpack(body_chunks[idx]),
			}
			if row_padding > 0 then
				table.insert(row, {
					pad(row_padding),
					"DoubtInlineBar",
				})
			end
			table.insert(virt_lines, {
				unpack(row),
			})
		end
	end

	if virt_lines then
		table.insert(virt_lines, {
			{
				prefix,
				"DoubtInlinePrefix",
			},
			{
				pad(content_width),
				"DoubtInlineBar",
			},
		})
	end

	vim.api.nvim_buf_set_extmark(bufnr, ctx.ns, start_row, start_col, {
		end_row = end_row,
		end_col = claim_end_col(bufnr, claim, end_row),
		hl_group = claim_hl,
		hl_eol = true,
		priority = 120,
	})

	vim.api.nvim_buf_set_extmark(bufnr, ctx.ns, start_row, start_col, {
		sign_text = meta.sign or config.signs[claim.kind] or config.signs.file,
		sign_hl_group = claim_hl,
		priority = 130,
		virt_text = inline_chunks,
		virt_text_pos = inline_note and "eol" or nil,
		virt_lines = virt_lines,
		virt_lines_above = render_block_notes,
	})
end

function M.render_file_sign(ctx, bufnr)
	local config = ctx.config.get()
	vim.api.nvim_buf_set_extmark(bufnr, ctx.ns, 0, 0, {
		sign_text = config.signs.file,
		sign_hl_group = "DoubtFile",
		priority = 110,
	})
end

-- Refresh one buffer from canonical state without assuming it is currently visible.
function M.refresh_buffer(ctx, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local path = ctx.current_path(bufnr)
	if not path then
		return
	end

	M.clear_buffer_claims(ctx, bufnr)

	local file_state = ctx.state.current_files()[path]
	if not file_state or vim.tbl_isempty(file_state.claims or {}) then
		local inline_edit = ctx.current_inline_edit and ctx.current_inline_edit() or nil
		if inline_edit and inline_edit.bufnr == bufnr and inline_edit.draft then
			M.render_inline_editor(ctx, bufnr, inline_edit)
		end
		return
	end

	M.render_file_sign(ctx, bufnr)
	for _, claim in ipairs(file_state.claims or {}) do
		M.render_claim(ctx, bufnr, claim)
	end

	local inline_edit = ctx.current_inline_edit and ctx.current_inline_edit() or nil
	if inline_edit and inline_edit.bufnr == bufnr and inline_edit.draft then
		M.render_inline_editor(ctx, bufnr, inline_edit)
	end
end

-- Repaint every displayed buffer after state changes.
function M.refresh_visible_buffers(ctx, opts)
	opts = opts or {}
	local seen = {}
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		local bufnr = vim.api.nvim_win_get_buf(winid)
		if bufnr ~= opts.skip_bufnr and not seen[bufnr] then
			seen[bufnr] = true
			M.refresh_buffer(ctx, bufnr)
		end
	end
end

return M
