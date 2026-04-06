local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local temp_file = vim.fs.joinpath(vim.fn.tempname(), "sample.lua")

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
vim.fn.writefile({ "alpha = 1", "beta = alpha + 1", "return beta" }, temp_file)

local doubt = require("doubt")
local claims = require("doubt.claims")
local input = require("doubt.input")
local state = require("doubt.state")
local original_select = vim.ui.select
local original_ask_note = input.ask_note

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

local nearest = claims.find_nearest_claim({
	{ id = "wide", kind = "reject", start_line = 0, start_col = 0, end_line = 1, end_col = 8, note = "wide" },
	{ id = "tight", kind = "question", start_line = 0, start_col = 2, end_line = 0, end_col = 5, note = "tight" },
	{ id = "far", kind = "concern", start_line = 2, start_col = 0, end_line = 2, end_col = 6, note = "far" },
}, 0, 3)
t.assert_eq(nearest.id, "tight", "nearest claim should prefer the smallest overlapping span")

nearest = claims.find_nearest_claim({
	{ id = "upper", kind = "question", start_line = 0, start_col = 1, end_line = 0, end_col = 1, note = "upper" },
	{ id = "lower", kind = "reject", start_line = 2, start_col = 1, end_line = 2, end_col = 1, note = "lower" },
}, 1, 1)
t.assert_eq(nearest.id, "upper", "nearest claim should fall back to cursor distance and then stable order")

vim.cmd.edit(temp_file)
doubt.start_session({ name = "claim-editing", quiet = true })

local path = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
local file_state = state.ensure_file_entry(path)
table.insert(file_state.claims, {
	id = "wide",
	kind = "reject",
	start_line = 0,
	start_col = 0,
	end_line = 1,
	end_col = 8,
	note = "wide",
})
table.insert(file_state.claims, {
	id = "tight",
	kind = "question",
	start_line = 0,
	start_col = 2,
	end_line = 0,
	end_col = 5,
	note = "tight",
})
claims.sort_claims(file_state.claims)

vim.api.nvim_win_set_cursor(0, { 1, 3 })
vim.cmd("DoubtClaimKind concern")

local edited_claim = state.find_claim(path, "tight")
t.assert_eq(edited_claim.kind, "concern", "claim kind edit should update the nearest claim")

local picked_items
local picked_prompt
vim.ui.select = function(items, opts, callback)
	picked_items = vim.deepcopy(items)
	picked_prompt = opts and opts.prompt
	callback("reject")
end
doubt.edit_nearest_claim_kind()
edited_claim = state.find_claim(path, "tight")
t.assert_eq(picked_items, { "question", "reject" }, "claim kind picker should exclude the current claim kind")
t.assert_eq(picked_prompt, "Change claim kind", "claim kind picker should use a clear prompt")
t.assert_eq(edited_claim.kind, "reject", "claim kind picker should update the nearest claim with the selection")

vim.ui.select = original_select

vim.cmd("DoubtClaimNote rewritten note")
edited_claim = state.find_claim(path, "tight")
t.assert_eq(edited_claim.note, "rewritten note", "claim note edit should update the nearest claim")

local captured_note_opts
input.ask_note = function(opts, callback)
	captured_note_opts = vim.deepcopy(opts)
	callback("inline rewrite", false)
end

vim.cmd("DoubtClaimNote")
edited_claim = state.find_claim(path, "tight")
	t.assert_eq(edited_claim.note, "inline rewrite", "claim note inline editor should update the nearest claim")
	t.assert_eq(captured_note_opts.default, "rewritten note", "claim note editor should preload the existing note")
	t.assert_eq(captured_note_opts.line, 0, "claim note editor should anchor to the claim start line")
	t.assert_eq(captured_note_opts.col, 2, "claim note editor should anchor to the claim start column")

captured_note_opts = nil
	vim.api.nvim_win_set_cursor(0, { 2, 4 })
	doubt.claim_range("question")
	t.assert_eq(captured_note_opts.line, 1, "new claim note editor should anchor to the current cursor line")
	t.assert_eq(captured_note_opts.col, 0, "new claim note editor should anchor to the claim start column")

input.ask_note = original_ask_note

vim.api.nvim_win_set_cursor(0, { 1, 3 })
vim.cmd("DoubtClaimDelete")
t.assert_eq(state.find_claim(path, "tight"), nil, "claim delete should remove the nearest claim")
t.assert_eq(state.find_claim(path, "wide") ~= nil, true, "claim delete should keep other claims intact")
