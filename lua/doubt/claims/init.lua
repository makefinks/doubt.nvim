local anchors = require("doubt.claims.anchors")
local format = require("doubt.claims.format")
local kinds = require("doubt.claims.kinds")
local normalize = require("doubt.claims.normalize")
local ranges = require("doubt.claims.ranges")
local search = require("doubt.claims.search")

local M = {}

M.configure = kinds.configure
M.list_claim_kinds = kinds.list_claim_kinds
M.has_claim_kind = kinds.has_claim_kind
M.meta = kinds.meta
M.default_note = kinds.default_note
M.normalize_claim_kind = kinds.normalize_claim_kind

M.normalize_line_range = ranges.normalize_line_range
M.normalize_position_range = ranges.normalize_position_range
M.current_range_from_command = ranges.current_range_from_command
M.current_span_from_command = ranges.current_span_from_command
M.current_visual_range = ranges.current_visual_range
M.current_visual_span = ranges.current_visual_span

M.normalize_note = normalize.normalize_note
M.normalize_claim = normalize.normalize_claim
M.sort_claims = normalize.sort_claims

M.build_buffer_anchor = anchors.build_buffer_anchor
M.build_content_anchor = anchors.build_content_anchor
M.validate_claim_anchor = anchors.validate_claim_anchor

M.freshness_marker = format.freshness_marker
M.claim_summary = format.claim_summary
M.inline_text = format.inline_text

M.find_nearest_claim = search.find_nearest_claim

return M
