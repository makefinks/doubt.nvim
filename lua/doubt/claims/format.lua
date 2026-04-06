local kinds = require("doubt.claims.kinds")

local M = {}

local FRESHNESS_MARKERS = {
	stale = "[stale]",
	reanchored = "[reanchored]",
}

function M.freshness_marker(claim)
	return FRESHNESS_MARKERS[(claim or {}).freshness]
end

local function display_note(claim)
	local marker = M.freshness_marker(claim)
	local note = claim.note ~= "" and claim.note or kinds.default_note(claim.kind)
	if marker then
		return string.format("%s %s", marker, note)
	end

	return note
end

function M.claim_summary(claim)
	local meta = kinds.meta(claim.kind)
	local start_col = (claim.start_col or 0) + 1
	local end_col = claim.end_col and tostring(claim.end_col) or "EOL"
	return string.format(
		"%s L%d:C%d-L%d:C%s%s",
		meta.label,
		claim.start_line + 1,
		start_col,
		claim.end_line + 1,
		end_col,
		" " .. display_note(claim)
	)
end

function M.inline_text(claim)
	local meta = kinds.meta(claim.kind)
	return meta.inline_label, display_note(claim)
end

return M
