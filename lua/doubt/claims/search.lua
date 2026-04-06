local M = {}

local function tuple_is_before(a_line, a_col, b_line, b_col)
	if a_line ~= b_line then
		return a_line < b_line
	end
	return a_col < b_col
end

local function tuple_is_after(a_line, a_col, b_line, b_col)
	return tuple_is_before(b_line, b_col, a_line, a_col)
end

local function contains_position(claim, line, col)
	if tuple_is_before(line, col, claim.start_line, claim.start_col or 0) then
		return false
	end

	if claim.end_col == nil then
		return not tuple_is_after(line, col, claim.end_line, math.huge)
	end

	return not tuple_is_after(line, col, claim.end_line, claim.end_col)
end

local function distance_to_claim(claim, line, col)
	if contains_position(claim, line, col) then
		return 0, 0
	end

	if tuple_is_before(line, col, claim.start_line, claim.start_col or 0) then
		return claim.start_line - line, math.abs((claim.start_col or 0) - col)
	end

	return line - claim.end_line, math.abs((claim.end_col or claim.start_col or 0) - col)
end

local function span_size(claim)
	return claim.end_line - claim.start_line, (claim.end_col or claim.start_col or 0) - (claim.start_col or 0)
end

function M.find_nearest_claim(claim_list, line, col)
	local best_claim = nil
	local best_score = nil

	for index, claim in ipairs(claim_list or {}) do
		local contains = contains_position(claim, line, col)
		local line_distance, col_distance = distance_to_claim(claim, line, col)
		local line_span, col_span = span_size(claim)
		local score = {
			contains and 0 or 1,
			contains and line_span or line_distance,
			contains and col_span or col_distance,
			index,
		}

		if not best_score then
			best_claim = claim
			best_score = score
		else
			for idx = 1, #score do
				if score[idx] ~= best_score[idx] then
					if score[idx] < best_score[idx] then
						best_claim = claim
						best_score = score
					end
					break
				end
			end
		end
	end

	return best_claim
end

return M
