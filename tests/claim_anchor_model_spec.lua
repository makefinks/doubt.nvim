local t = dofile("tests/helpers/bootstrap.lua")
local claims = require("doubt.claims")

local normalized = claims.normalize_claim({
	id = "claim-1",
	kind = "question",
	start_line = 2,
	start_col = 3,
	end_line = 2,
	end_col = 8,
	note = "why",
})

t.assert_eq(normalized.freshness, "stale", "claims should default to stale freshness until validated")
t.assert_eq(normalized.anchor, {
	text = "",
	before = "",
	after = "",
}, "claims should normalize missing anchor fields")

local reanchored = claims.normalize_claim({
	id = "claim-2",
	kind = "question",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 4,
	note = "ok",
	freshness = "reanchored",
	anchor = {
		text = "name",
		before = "local ",
		after = " = 1",
	},
})

t.assert_eq(reanchored.freshness, "reanchored", "explicit reanchored freshness should normalize cleanly")

local malformed_anchor = claims.normalize_claim({
	id = "claim-3",
	kind = "reject",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 5,
	note = "bad",
	anchor = {
		text = "value",
		before = 12,
	},
})

t.assert_eq(malformed_anchor.anchor, {
	text = "value",
	before = "",
	after = "",
}, "claims should normalize malformed anchor tables into a stable shape")

local legacy_kind = claims.normalize_claim({
	id = "claim-legacy-kind",
	kind = "contradicted",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 1,
	note = "legacy",
})

t.assert_eq(legacy_kind.kind, "question", "legacy claim kinds should no longer be remapped")

local legacy_status = claims.normalize_claim({
	id = "claim-legacy-status",
	status = "reject",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 1,
	note = "legacy",
})

t.assert_eq(legacy_status.kind, "question", "claims should no longer read legacy status fields")

local fresh_result = claims.validate_claim_anchor({
	id = "claim-4",
	kind = "question",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 8,
	note = "stable",
	anchor = {
		text = "target()",
		before = "alpha\n",
		after = "\nomega\n",
	},
}, "alpha\ntarget()\nomega\n")

t.assert_eq(fresh_result.freshness, "fresh", "unchanged saved anchors should validate as fresh")
t.assert_eq(fresh_result.saved_range_matches, true, "fresh validation should keep the saved range")
t.assert_eq(fresh_result.contextual_match_count, 1, "fresh validation should prove one unique contextual match")

local ambiguous_result = claims.validate_claim_anchor({
	id = "claim-5",
	kind = "question",
	start_line = 0,
	start_col = 11,
	end_line = 0,
	end_col = 19,
	note = "duplicate",
	anchor = {
		text = "target()",
		before = "if ok then ",
		after = " end",
	},
}, "if ok then target() end\nif ok then target() end\n")

t.assert_eq(ambiguous_result.freshness, "stale", "ambiguous matches should become stale")
t.assert_eq(ambiguous_result.exact_match_count, 2, "ambiguous validation should report multiple exact matches")

local moved_result = claims.validate_claim_anchor({
	id = "claim-6",
	kind = "question",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 8,
	note = "moved",
	anchor = {
		text = "target()",
		before = "alpha\n",
		after = "\nomega\n",
	},
}, "alpha\nchanged\nomega\nbeta\ntarget()\ngamma\n")

t.assert_eq(moved_result.freshness, "stale", "unique matches elsewhere should stay stale in phase 1")
t.assert_eq(moved_result.saved_range_matches, false, "phase 1 should not treat moved anchors as saved-range matches")
t.assert_eq(moved_result.exact_match_count, 1, "moved validation should still detect the surviving exact match")

local contextual_result = claims.validate_claim_anchor({
	id = "claim-7",
	kind = "question",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 8,
	note = "contextual",
	anchor = {
		text = "target()",
		before = "alpha\n",
		after = "\nomega\n",
	},
}, "noise\ntarget()\nalpha\ntarget()\nomega\n")

t.assert_eq(contextual_result.freshness, "stale", "validation should stay stale until classification decides to reanchor")
t.assert_eq(contextual_result.exact_match_count, 2, "contextual validation should still count all exact matches")
t.assert_eq(contextual_result.contextual_match_count, 1, "contextual validation should expose a unique contextual candidate")
t.assert_eq(contextual_result.match.start_line, 3, "contextual validation should surface the unique contextual match location")
