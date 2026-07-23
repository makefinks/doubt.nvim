local t = dofile("tests/helpers/bootstrap.lua")

describe("claim editing", function()
	it("matches expected behavior", function()

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local temp_file = vim.fs.joinpath(vim.fn.tempname(), "sample.lua")

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
vim.fn.writefile({ "alpha = 1", "beta = alpha + 1", "return beta" }, temp_file)

local doubt = require("doubt")
local claims = require("doubt.claims")
local input = require("doubt.input")
local inline_editor = require("doubt.inline_editor")
local state = require("doubt.state")
local original_select = vim.ui.select
local original_ask_note = input.ask_note
local original_confirm = vim.fn.confirm

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

vim.cmd("DoubtClaimNote")
local editor = inline_editor.status()
t.assert_eq(editor.active, true, "claim note editing should open the inline editor")
t.assert_eq(editor.draft, false, "editing an existing claim should not create a draft")
t.assert_eq(editor.claim.id, "tight", "inline editor should target the nearest claim")
t.assert_eq(vim.api.nvim_buf_get_lines(editor.bufnr, 0, -1, false), { "rewritten note" }, "inline editor should preload the existing note")
local editor_border = vim.api.nvim_win_get_config(editor.winid).border
local borderless = editor_border == "none" or (type(editor_border) == "table" and vim.tbl_isempty(editor_border))
t.assert_eq(borderless, true, "inline editor should use a seamless borderless window")

vim.api.nvim_buf_set_lines(editor.bufnr, 0, -1, false, { "inline rewrite", "with context" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = editor.bufnr })
editor = inline_editor.status()
t.assert_eq(editor.rows, 2, "inline editor should grow with multiline content")
inline_editor.submit()
edited_claim = state.find_claim(path, "tight")
	t.assert_eq(edited_claim.note, "inline rewrite\nwith context", "saving the inline editor should update the nearest claim")
	t.assert_eq(inline_editor.status().active, false, "saving should close the inline editor")

vim.api.nvim_win_set_cursor(0, { 1, 3 })
doubt.edit_nearest_claim_note()
editor = inline_editor.status()
vim.api.nvim_buf_set_lines(editor.bufnr, 0, -1, false, { "discarded rewrite" })
inline_editor.cancel()
edited_claim = state.find_claim(path, "tight")
t.assert_eq(edited_claim.note, "inline rewrite\nwith context", "cancelling inline editing should preserve the stored note")

	vim.api.nvim_win_set_cursor(0, { 2, 4 })
	doubt.claim_range("question")
	editor = inline_editor.status()
	t.assert_eq(editor.active, true, "claim creation should open the inline editor")
	t.assert_eq(editor.draft, true, "claim creation should remain a draft until saved")
	t.assert_eq(editor.claim.start_line, 1, "new inline claim should anchor to the current cursor line")
	t.assert_eq(editor.claim.start_col, 0, "new inline claim should anchor to the claim start column")
	vim.api.nvim_buf_set_lines(editor.bufnr, 0, -1, false, { "new inline claim" })
	inline_editor.submit()
	local created_claim = nil
	file_state = state.current_files()[path]
	for _, candidate in ipairs(file_state.claims) do
		if candidate.note == "new inline claim" then
			created_claim = candidate
			break
		end
	end
	t.assert_eq(created_claim ~= nil, true, "saving a draft should create the claim")

	local claim_count = #file_state.claims
	vim.api.nvim_win_set_cursor(0, { 3, 2 })
	doubt.claim_range("concern")
	inline_editor.submit()
	t.assert_eq(#file_state.claims, claim_count, "an untouched empty draft should be discarded")

	local captured_note_opts
	input.ask_note = function(opts, callback)
		captured_note_opts = vim.deepcopy(opts)
		callback("popup rewrite", false)
	end
	doubt.setup({
		keymaps = false,
		state_path = temp_state,
		input = { mode = "popup" },
	})
	vim.api.nvim_win_set_cursor(0, { 1, 3 })
	doubt.edit_nearest_claim_note()
	edited_claim = claims.find_nearest_claim(state.current_files()[path].claims, 0, 3)
	local migrated_tight_id = edited_claim.id
	t.assert_eq(edited_claim.note, "popup rewrite", "popup mode should retain the previous note editor")
	t.assert_eq(captured_note_opts.default, "inline rewrite\nwith context", "popup fallback should preload the existing note")
	t.assert_eq(captured_note_opts.line, 0, "popup fallback should anchor to the claim start line")
	t.assert_eq(captured_note_opts.col, 2, "popup fallback should anchor to the claim start column")

input.ask_note = original_ask_note

vim.api.nvim_win_set_cursor(0, { 1, 3 })
local confirm_message
vim.fn.confirm = function(message)
	confirm_message = message
	return 2
end
vim.cmd("DoubtClaimDelete")
t.assert_eq(confirm_message, "Delete doubt claim?", "claim delete should ask for confirmation")
t.assert_eq(state.find_claim(path, migrated_tight_id) ~= nil, true, "claim delete should keep the claim when cancelled")

vim.fn.confirm = function()
	return 1
end
vim.cmd("DoubtClaimDelete")
t.assert_eq(state.find_claim(path, migrated_tight_id), nil, "claim delete should remove the nearest claim")
t.assert_eq(#state.current_files()[path].claims > 0, true, "claim delete should keep other claims intact")

doubt.undo_deleted_claim()
t.assert_eq(state.find_claim(path, migrated_tight_id) ~= nil, true, "undo delete should restore the most recently deleted claim")
vim.fn.confirm = original_confirm
	end)
end)
