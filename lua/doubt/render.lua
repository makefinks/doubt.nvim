-- Buffer decorations: extmarks, signs, and visible-buffer refresh.
local claims = require("doubt.claims")

local M = {}

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

	local lines = {}
	local current = ""
	for word in string.gmatch(text, "%S+") do
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

function M.clear_buffer_claims(ctx, bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ctx.ns, 0, -1)
end

-- Each claim paints its range and places a sign at the first line.
function M.render_claim(ctx, bufnr, claim)
	local meta = claims.meta(claim.kind)
	local config = ctx.config.get()
	local path = ctx.current_path(bufnr)
	local start_row, end_row = claim_rows(bufnr, claim)
	local start_col = clamp_col(bufnr, start_row, claim.start_col)
	local claim_hl = claim.freshness == "stale" and (meta.stale_hl or meta.hl) or meta.hl
	local inline_label_hl = meta.inline_label_hl
	local inline_text_hl = meta.inline_text_hl
	local focus_mode = ctx.focus_mode and ctx.focus_mode(path, claim) or "normal"
	if focus_mode == "dimmed" then
		claim_hl = claim.freshness == "stale" and (meta.dim_stale_hl or meta.dim_hl or claim_hl) or (meta.dim_hl or claim_hl)
		inline_label_hl = meta.dim_inline_label_hl or inline_label_hl
		inline_text_hl = meta.dim_inline_text_hl or inline_text_hl
	end
	local inline_label, inline_text = claims.inline_text(claim)
	local expanded = ctx.is_claim_expanded and ctx.is_claim_expanded(ctx.current_path(bufnr), claim)
	local body_lines = expanded
		and wrap_inline_text(inline_text, config.inline_notes.max_width)
		or { compact_inline_text(inline_text, config.inline_notes.max_width) }
	local right_padding = math.max(config.inline_notes.padding_right or 0, 0)
	local prefix = config.inline_notes.prefix or ""
	local label_width = display_width(inline_label)
	local content_width = 0
	for _, body_line in ipairs(body_lines) do
		content_width = math.max(content_width, label_width + 1 + display_width(body_line))
	end
	content_width = content_width + right_padding

	-- Render inline notes as a rectangular virtual block so wrapped rows align
	-- with the label and background bar instead of drifting by content width.
	local virt_lines = config.inline_notes.enabled and {
		{
			{
				prefix,
				"DoubtInlinePrefix",
			},
			{
				pad(content_width),
				"DoubtInlineBar",
			},
		},
		{
			{
				prefix,
				"DoubtInlinePrefix",
			},
			{
				inline_label,
				inline_label_hl,
			},
			{
				" " .. body_lines[1],
				inline_text_hl,
			},
		},
	} or nil

	if virt_lines then
		local first_row_width = label_width + 1 + display_width(body_lines[1])
		local first_row_padding = content_width - first_row_width
		if first_row_padding > 0 then
			table.insert(virt_lines[2], {
				pad(first_row_padding),
				"DoubtInlineBar",
			})
		end
	end

	if expanded then
		for idx = 2, #body_lines do
			local row_width = label_width + 1 + display_width(body_lines[idx])
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
				{
					" " .. body_lines[idx],
					inline_text_hl,
				},
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
		virt_lines = virt_lines,
		virt_lines_above = config.inline_notes.enabled,
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
		return
	end

	M.render_file_sign(ctx, bufnr)
	for _, claim in ipairs(file_state.claims or {}) do
		M.render_claim(ctx, bufnr, claim)
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
