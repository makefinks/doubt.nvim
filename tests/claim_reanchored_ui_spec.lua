local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt"] = nil

local doubt = require("doubt")
local claims = require("doubt.claims")
local panel = require("doubt.panel")
local state = require("doubt.state")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local temp_file = vim.fs.joinpath(vim.fn.tempname(), "reanchored-ui.lua")

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
vim.fn.writefile({ "alpha", "target()", "omega" }, temp_file)

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

vim.cmd.edit(temp_file)
doubt.start_session({ name = "reanchored-ui", quiet = true })

local bufnr = vim.api.nvim_get_current_buf()
local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
local file_state = state.ensure_file_entry(path)

table.insert(file_state.claims, claims.normalize_claim({
	id = "reanchored-claim",
	kind = "question",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 8,
	note = "moved note",
	freshness = "reanchored",
	anchor = {
		text = "target()",
		before = "alpha\n",
		after = "\nomega\n",
	},
}))

table.insert(file_state.claims, claims.normalize_claim({
	id = "fresh-claim",
	kind = "reject",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 5,
	note = "fresh note",
	freshness = "fresh",
	anchor = {
		text = "alpha",
		before = "",
		after = "\ntarget()\nomega\n",
	},
}))

claims.sort_claims(file_state.claims)

local inline_label, inline_text = claims.inline_text(file_state.claims[2])
t.assert_eq(inline_label, claims.meta("question").inline_label, "inline text should still use the canonical label")
t.assert_match(inline_text, "^%[reanchored%] moved note$", "reanchored inline text should include a compact marker")

local _, fresh_inline_text = claims.inline_text(file_state.claims[1])
t.assert_eq(fresh_inline_text, "fresh note", "fresh inline text should remain unchanged")

local lines = panel.build_lines({
	config = require("doubt.config"),
	state = state,
}, 60)

local reanchored_line
local reanchored_item
for _, item in ipairs(lines) do
	if item.kind == "claim" and item.id == "reanchored-claim" then
		reanchored_line = item.text
		reanchored_item = item
		break
	end
end

t.assert_eq(reanchored_line ~= nil, true, "panel lines should include the reanchored claim")
t.assert_match(reanchored_line, "%[reanchored%] moved note", "panel text should expose the same reanchored marker")
t.assert_eq(reanchored_item ~= nil, true, "panel lines should expose the reanchored claim item")

local kind_highlight
for _, highlight in ipairs(reanchored_item.highlights or {}) do
	if highlight.hl_group == claims.meta("question").hl then
		kind_highlight = highlight
		break
	end
end

t.assert_eq(kind_highlight ~= nil, true, "panel lines should highlight the claim kind column")
t.assert_eq(kind_highlight.end_col - kind_highlight.start_col, 8, "claim kind highlight should span the fixed-width kind column")

local summary_text = claims.claim_summary(file_state.claims[2])
t.assert_match(summary_text, "%[reanchored%] moved note", "shared claim summaries should expose reanchored state")

vim.bo[bufnr].modified = false
