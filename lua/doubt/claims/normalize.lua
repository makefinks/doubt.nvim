local anchors = require("doubt.claims.anchors")
local kinds = require("doubt.claims.kinds")
local ranges = require("doubt.claims.ranges")

local M = {}

local FRESHNESS_VALUES = {
	fresh = true,
	stale = true,
	reanchored = true,
}

local function normalize_freshness(freshness)
	if type(freshness) == "string" and FRESHNESS_VALUES[freshness] then
		return freshness
	end

	return "stale"
end

function M.normalize_note(note)
	return vim.trim(note or "")
end

function M.new_claim_id()
	local seed = string.format("%s:%s", vim.uv.hrtime(), math.random())
	return "claim-" .. vim.fn.sha256(seed):sub(1, 12)
end

local function ordered_session_claims(files)
	local ordered = {}
	local paths = vim.tbl_keys(files or {})
	table.sort(paths)
	for _, path in ipairs(paths) do
		for _, claim in ipairs((files[path] or {}).claims or {}) do
			table.insert(ordered, claim)
		end
	end
	return ordered
end

local function escape_pattern(value)
	return (value:gsub("([^%w])", "%%%1"))
end

function M.normalize_session_claim_ids(files)
	local ordered = ordered_session_claims(files)
	local used_numbers = {}
	local pending = {}
	local remapped = {}
	local next_number = 1

	for _, claim in ipairs(ordered) do
		local kind, number = tostring(claim.id or ""):match("^([%w_-]+)%-(%d+)$")
		number = tonumber(number)
		if kind == claim.kind and number and not used_numbers[number] then
			used_numbers[number] = true
			next_number = math.max(next_number, number + 1)
		else
			table.insert(pending, { claim = claim, preferred_number = number })
		end
	end

	for _, entry in ipairs(pending) do
		local number = entry.preferred_number
		if not number or used_numbers[number] then
			while used_numbers[next_number] do
				next_number = next_number + 1
			end
			number = next_number
			next_number = next_number + 1
		end
		used_numbers[number] = true
		local old_id = tostring(entry.claim.id or "")
		local new_id = string.format("%s-%d", entry.claim.kind, number)
		entry.claim.id = new_id
		if old_id ~= "" and old_id ~= new_id then
			remapped[old_id] = new_id
		end
	end

	if vim.tbl_isempty(remapped) then
		return false
	end
	for _, claim in ipairs(ordered) do
		for old_id, new_id in pairs(remapped) do
			claim.note = claim.note:gsub("`#" .. escape_pattern(old_id) .. "`", "`#" .. new_id .. "`")
		end
	end
	return true
end

function M.next_session_claim_id(files, kind)
	local max_number = 0
	for _, claim in ipairs(ordered_session_claims(files)) do
		max_number = math.max(max_number, tonumber(tostring(claim.id):match("%-(%d+)$")) or 0)
	end
	return string.format("%s-%d", kinds.normalize_claim_kind(kind), max_number + 1)
end

function M.normalize_claim(claim)
	if type(claim) ~= "table" then
		return nil
	end

	local kind = kinds.normalize_claim_kind(claim.kind)
	local start_line, start_col, end_line, end_col =
		ranges.normalize_position_range(claim.start_line, claim.start_col, claim.end_line, claim.end_col)

	return {
		id = tostring(claim.id or M.new_claim_id()),
		kind = kind,
		start_line = start_line,
		start_col = start_col,
		end_line = end_line,
		end_col = end_col,
		note = M.normalize_note(claim.note),
		freshness = normalize_freshness(claim.freshness),
		anchor = anchors.normalize_anchor(claim.anchor),
	}
end

function M.review_revision(claim)
	local normalized = M.normalize_claim(claim)
	if not normalized then
		return nil
	end
	return vim.fn.sha256(vim.json.encode({ normalized.kind, normalized.note }))
end

function M.sort_claims(claim_list)
	table.sort(claim_list, function(a, b)
		if a.start_line == b.start_line then
			if (a.start_col or 0) ~= (b.start_col or 0) then
				return (a.start_col or 0) < (b.start_col or 0)
			end
			return a.id < b.id
		end

		return a.start_line < b.start_line
	end)
end

return M
