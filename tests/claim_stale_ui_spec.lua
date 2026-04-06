local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt"] = nil

local doubt = require("doubt")
local claims = require("doubt.claims")
local panel = require("doubt.panel")
local render = require("doubt.render")
local state = require("doubt.state")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local temp_file = vim.fs.joinpath(vim.fn.tempname(), "stale-ui.lua")

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
vim.fn.writefile({ "alpha", "target()", "omega" }, temp_file)

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

vim.cmd.edit(temp_file)
doubt.start_session({ name = "stale-ui", quiet = true })

local bufnr = vim.api.nvim_get_current_buf()
local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
local file_state = state.ensure_file_entry(path)

table.insert(file_state.claims, claims.normalize_claim({
	id = "stale-claim",
	kind = "question",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 8,
	note = "stale note",
	freshness = "stale",
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

t.assert_eq(claims.freshness_marker(file_state.claims[2]), "[stale]", "stale claims should expose a shared stale marker")

local inline_label, inline_text = claims.inline_text(file_state.claims[2])
t.assert_eq(inline_label, claims.meta("question").inline_label, "stale inline text should keep the canonical label")
t.assert_match(inline_text, "^%[stale%] stale note$", "stale inline text should include an explicit stale marker")

local _, fresh_inline_text = claims.inline_text(file_state.claims[1])
t.assert_eq(fresh_inline_text, "fresh note", "fresh inline text should remain unchanged")

local render_ctx = {
	ns = vim.api.nvim_create_namespace("doubt.test.stale-ui"),
	config = require("doubt.config"),
	current_path = function()
		return path
	end,
	is_claim_expanded = function(_, claim)
		return claim.id == "stale-claim"
	end,
}

render.clear_buffer_claims(render_ctx, bufnr)
render.render_claim(render_ctx, bufnr, file_state.claims[2])

local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, render_ctx.ns, 0, -1, { details = true })
local stale_range
local stale_sign
for _, mark in ipairs(extmarks) do
	local details = mark[4] or {}
	if details.hl_group == "DoubtStaleQuestion" then
		stale_range = details
	end
	if details.sign_text and vim.startswith(details.sign_text, claims.meta("question").sign) then
		stale_sign = details
	end
end

t.assert_eq(stale_range ~= nil, true, "stale claims should render with a stale-specific range highlight")
t.assert_eq(stale_sign ~= nil, true, "stale claims should still render their existing kind sign")
t.assert_eq(stale_sign.sign_hl_group, "DoubtStaleQuestion", "stale signs should use the muted stale highlight")
t.assert_eq(stale_sign.virt_lines ~= nil, true, "stale claims should still expose inline inspection text")
t.assert_match(stale_sign.virt_lines[2][3][1], "^ %[%a+%] stale note$", "inline inspection should keep stale note text readable in place")

local lines = panel.build_lines({
	config = require("doubt.config"),
	state = state,
}, 60)

local stale_claim_line
local file_line
local summary_line
for _, item in ipairs(lines) do
	if item.kind == "claim" and item.id == "stale-claim" then
		stale_claim_line = item
	elseif item.kind == "file" and item.path == path then
		file_line = item
	elseif item.kind == "summary" then
		summary_line = item
	end
end

t.assert_eq(stale_claim_line ~= nil, true, "panel lines should include the stale claim")
t.assert_match(stale_claim_line.text, "%[stale%] stale note", "panel claim rows should expose the stale marker")
t.assert_eq(stale_claim_line.id, "stale-claim", "stale panel rows should keep claim ids for deletion")
t.assert_eq(stale_claim_line.path, path, "stale panel rows should keep file paths for actions")
t.assert_eq(stale_claim_line.line, 2, "stale panel rows should keep jump-to-claim line metadata")
t.assert_eq(stale_claim_line.col, 0, "stale panel rows should keep jump-to-claim column metadata")

t.assert_eq(file_line ~= nil, true, "panel lines should include the stale claim's file row")
t.assert_match(file_line.text, "%[stale 1%]", "file rows should roll up stale claim counts")

t.assert_eq(summary_line ~= nil, true, "active sessions should include a summary row")
t.assert_match(summary_line.text, "Stale%s+1", "session summary should roll up stale claim counts")

vim.bo[bufnr].modified = false
