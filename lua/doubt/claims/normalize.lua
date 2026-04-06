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

function M.normalize_claim(claim)
	if type(claim) ~= "table" then
		return nil
	end

	local kind = kinds.normalize_claim_kind(claim.kind)
	local start_line, start_col, end_line, end_col =
		ranges.normalize_position_range(claim.start_line, claim.start_col, claim.end_line, claim.end_col)

	return {
		id = tostring(claim.id or vim.uv.hrtime()),
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
