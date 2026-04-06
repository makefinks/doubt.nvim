local ranges = require("doubt.claims.ranges")

local M = {}

local ANCHOR_SNIPPET_BYTES = 32

local function normalize_anchor(anchor)
	anchor = type(anchor) == "table" and anchor or {}
	return {
		text = type(anchor.text) == "string" and anchor.text or "",
		before = type(anchor.before) == "string" and anchor.before or "",
		after = type(anchor.after) == "string" and anchor.after or "",
	}
end

local function split_content_lines(content)
	return vim.split(content or "", "\n", { plain = true, trimempty = false })
end

local function line_for_content(content, line)
	return split_content_lines(content)[line + 1]
end

local function offset_from_position(content, line, col)
	line = math.max(line or 0, 0)
	col = math.max(col or 0, 0)

	local lines = split_content_lines(content)
	if line >= #lines then
		return nil
	end

	local line_text = lines[line + 1] or ""
	if col > #line_text then
		return nil
	end

	local offset = 1
	for idx = 1, line do
		offset = offset + #(lines[idx] or "") + 1
	end

	return offset + col
end

local function position_from_offset(content, offset)
	offset = math.max(offset or 1, 1)
	local lines = split_content_lines(content)
	local remaining = offset - 1

	for idx, line_text in ipairs(lines) do
		if remaining <= #line_text then
			return idx - 1, remaining
		end

		remaining = remaining - #line_text
		if idx < #lines then
			if remaining == 0 then
				return idx - 1, #line_text
			end
			remaining = remaining - 1
		end
	end

	local last_line = math.max(#lines - 1, 0)
	return last_line, #(lines[last_line + 1] or "")
end

local function resolve_end_col(content, line, end_col)
	if end_col ~= nil then
		return end_col
	end

	local line_text = line_for_content(content, line)
	if line_text == nil then
		return nil
	end

	return #line_text
end

local function range_offsets_from_content(content, start_line, start_col, end_line, end_col)
	local resolved_end_col = resolve_end_col(content, end_line, end_col)
	if resolved_end_col == nil then
		return nil, nil
	end

	local start_offset = offset_from_position(content, start_line, start_col)
	local end_offset = offset_from_position(content, end_line, resolved_end_col)
	if not start_offset or not end_offset or end_offset < start_offset then
		return nil, nil
	end

	return start_offset, end_offset
end

local function text_for_range(content, start_line, start_col, end_line, end_col)
	local start_offset, end_offset =
		range_offsets_from_content(content, start_line, start_col, end_line, end_col)
	if not start_offset or not end_offset then
		return nil
	end

	return content:sub(start_offset, end_offset - 1)
end

function M.build_buffer_anchor(bufnr, start_line, start_col, end_line, end_col)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	start_line, start_col, end_line, end_col =
		ranges.normalize_position_range(start_line, start_col, end_line, end_col)

	local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	return M.build_content_anchor(content, start_line, start_col, end_line, end_col)
end

function M.build_content_anchor(content, start_line, start_col, end_line, end_col)
	start_line, start_col, end_line, end_col =
		ranges.normalize_position_range(start_line, start_col, end_line, end_col)

	local start_offset, end_offset = range_offsets_from_content(content, start_line, start_col, end_line, end_col)
	if not start_offset or not end_offset then
		return normalize_anchor(nil)
	end

	return {
		text = content:sub(start_offset, end_offset - 1),
		before = content:sub(math.max(1, start_offset - ANCHOR_SNIPPET_BYTES), start_offset - 1),
		after = content:sub(end_offset, end_offset + ANCHOR_SNIPPET_BYTES - 1),
	}
end

function M.validate_claim_anchor(claim, content)
	local normalized = require("doubt.claims.normalize").normalize_claim(claim)
	if not normalized or type(content) ~= "string" then
		return {
			freshness = "stale",
			saved_range_matches = false,
			exact_match_count = 0,
			contextual_match_count = 0,
			reason = "invalid",
		}
	end

	local anchor = normalized.anchor
	if anchor.text == "" then
		return {
			freshness = "stale",
			saved_range_matches = false,
			exact_match_count = 0,
			contextual_match_count = 0,
			reason = "missing_anchor",
		}
	end

	local saved_text = text_for_range(content, normalized.start_line, normalized.start_col, normalized.end_line, normalized.end_col)
	local saved_start_offset, saved_end_offset =
		range_offsets_from_content(content, normalized.start_line, normalized.start_col, normalized.end_line, normalized.end_col)

	local saved_before = saved_start_offset and content:sub(math.max(1, saved_start_offset - #anchor.before), saved_start_offset - 1)
		or nil
	local saved_after = saved_end_offset and content:sub(saved_end_offset, saved_end_offset + #anchor.after - 1) or nil
	local saved_range_matches = saved_text == anchor.text
		and saved_before == anchor.before
		and saved_after == anchor.after

	local exact_matches = {}
	local contextual_matches = {}
	local search_from = 1

	while true do
		local match_start, match_end = content:find(anchor.text, search_from, true)
		if not match_start then
			break
		end

		local candidate = {
			start_offset = match_start,
			end_offset = match_end + 1,
		}
		candidate.start_line, candidate.start_col = position_from_offset(content, candidate.start_offset)
		candidate.end_line, candidate.end_col = position_from_offset(content, candidate.end_offset)
		candidate.before = content:sub(math.max(1, match_start - #anchor.before), match_start - 1)
		candidate.after = content:sub(candidate.end_offset, candidate.end_offset + #anchor.after - 1)
		candidate.context_matches = candidate.before == anchor.before and candidate.after == anchor.after
		table.insert(exact_matches, candidate)
		if candidate.context_matches then
			table.insert(contextual_matches, candidate)
		end

		search_from = match_start + 1
	end

	if saved_range_matches and #contextual_matches == 1 then
		return {
			freshness = "fresh",
			saved_range_matches = true,
			exact_match_count = #exact_matches,
			contextual_match_count = #contextual_matches,
			match = contextual_matches[1],
			reason = "saved_range",
		}
	end

	if #contextual_matches == 1 then
		return {
			freshness = "stale",
			saved_range_matches = false,
			exact_match_count = #exact_matches,
			contextual_match_count = #contextual_matches,
			match = contextual_matches[1],
			reason = "contextual_match",
		}
	end

	if #exact_matches == 1 then
		return {
			freshness = "stale",
			saved_range_matches = false,
			exact_match_count = #exact_matches,
			contextual_match_count = #contextual_matches,
			match = exact_matches[1],
			reason = "moved_or_context_changed",
		}
	end

	return {
		freshness = "stale",
		saved_range_matches = false,
		exact_match_count = #exact_matches,
		contextual_match_count = #contextual_matches,
		reason = #exact_matches == 0 and "missing" or "ambiguous",
	}
end

function M.normalize_anchor(anchor)
	return normalize_anchor(anchor)
end

return M
