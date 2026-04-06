local claims = require("doubt.claims")

local M = {}

local function claim_matches_state(claim, normalized)
	return claim.start_line == normalized.start_line
		and claim.start_col == normalized.start_col
		and claim.end_line == normalized.end_line
		and claim.end_col == normalized.end_col
		and claim.freshness == normalized.freshness
		and vim.deep_equal(claim.anchor, normalized.anchor)
end

local function classify_claim_update(claim, content)
	if type(content) ~= "string" then
		return claims.normalize_claim(vim.tbl_extend("force", vim.deepcopy(claim), {
			freshness = "stale",
		}))
	end

	local result = claims.validate_claim_anchor(claim, content)
	if result.freshness == "fresh" then
		return claims.normalize_claim(vim.tbl_extend("force", vim.deepcopy(claim), {
			freshness = "fresh",
		}))
	end

	if result.contextual_match_count == 1 and result.match then
		return claims.normalize_claim(vim.tbl_extend("force", vim.deepcopy(claim), {
			start_line = result.match.start_line,
			start_col = result.match.start_col,
			end_line = result.match.end_line,
			end_col = result.match.end_col,
			freshness = "reanchored",
			anchor = claims.build_content_anchor(
				content,
				result.match.start_line,
				result.match.start_col,
				result.match.end_line,
				result.match.end_col
			),
		}))
	end

	if result.exact_match_count == 1 and result.match then
		return claims.normalize_claim(vim.tbl_extend("force", vim.deepcopy(claim), {
			start_line = result.match.start_line,
			start_col = result.match.start_col,
			end_line = result.match.end_line,
			end_col = result.match.end_col,
			freshness = "reanchored",
			anchor = claims.build_content_anchor(
				content,
				result.match.start_line,
				result.match.start_col,
				result.match.end_line,
				result.match.end_col
			),
		}))
	end

	return claims.normalize_claim(vim.tbl_extend("force", vim.deepcopy(claim), {
		freshness = "stale",
	}))
end

function M.classify_file_state(file_state, content)
	local changed = false
	for _, claim in ipairs((file_state or {}).claims or {}) do
		local normalized = classify_claim_update(claim, content)
		if normalized and not claim_matches_state(claim, normalized) then
			claim.start_line = normalized.start_line
			claim.start_col = normalized.start_col
			claim.end_line = normalized.end_line
			claim.end_col = normalized.end_col
			claim.freshness = normalized.freshness
			claim.anchor = normalized.anchor
			changed = true
		end
	end

	claims.sort_claims((file_state or {}).claims or {})
	return changed
end

return M
