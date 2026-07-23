local t = dofile("tests/helpers/bootstrap.lua")

describe("claim stale ui", function()
	it("matches expected behavior", function()

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

local expanded_claim_id = "stale-claim"
local inline_notes_layout = "block"
local render_ctx = {
	ns = vim.api.nvim_create_namespace("doubt.test.stale-ui"),
	config = require("doubt.config"),
	current_path = function()
		return path
	end,
	is_claim_expanded = function(_, claim)
		return claim.id == expanded_claim_id
	end,
	inline_notes_layout = function()
		return inline_notes_layout
	end,
}

render.clear_buffer_claims(render_ctx, bufnr)
render.render_claim(render_ctx, bufnr, file_state.claims[2])

local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, render_ctx.ns, 0, -1, { details = true })
local stale_range
local stale_sign
local function virt_line_text(line)
	local chunks = {}
	for _, chunk in ipairs(line or {}) do
		table.insert(chunks, chunk[1])
	end
	return table.concat(chunks, "")
end
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
local stale_inline_text = virt_line_text(stale_sign.virt_lines[2])
t.assert_match(stale_inline_text, "%[stale%]", "inline inspection should keep stale marker text readable in place")
t.assert_match(stale_inline_text, "stale note", "inline inspection should keep stale note text readable in place")

render_ctx.claim_review_status = function(id)
	if id == "stale-claim" then
		return {
			addressed = true,
			outcome = "changed",
			summary = "Updated the implementation.",
		}
	end
end
inline_notes_layout = "inline"
render.clear_buffer_claims(render_ctx, bufnr)
render.render_claim(render_ctx, bufnr, file_state.claims[2])

local addressed_sign
local addressed_stale_range
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, render_ctx.ns, 0, -1, { details = true })) do
	local details = mark[4] or {}
	if details.hl_group == "DoubtStaleQuestion" then
		addressed_stale_range = details
	end
	if details.sign_text and vim.startswith(details.sign_text, claims.meta("question").sign) then
		addressed_sign = details
	end
end
t.assert_eq(addressed_stale_range, nil, "addressed claims should not retain stale range styling")
t.assert_eq(addressed_sign.sign_hl_group, claims.meta("question").hl, "addressed claims should use their normal kind styling")
local addressed_top_text = virt_line_text(addressed_sign.virt_lines[1])
local addressed_inline_text = virt_line_text(addressed_sign.virt_lines[2])
t.assert_match(addressed_top_text, "changed $", "source annotations should place the lowercase agent decision at the top right")
t.assert_eq(addressed_inline_text:match("changed"), nil, "the top badge should not displace claim text")
t.assert_match(addressed_inline_text, "stale note", "the review badge should leave the note unchanged")
t.assert_eq(addressed_sign.virt_lines[1][#addressed_sign.virt_lines[1]][2], "DoubtInlineAddressed", "addressed outcomes should use a distinct badge style")
t.assert_eq(addressed_inline_text:match("%[stale%]"), nil, "addressed source annotations should suppress stale markers")
local addressed_response_text = ""
for _, line in ipairs(addressed_sign.virt_lines) do
	addressed_response_text = addressed_response_text .. "\n" .. virt_line_text(line)
end
t.assert_match(addressed_response_text, "Agent response", "expanded claims should show an agent response section")
t.assert_match(addressed_response_text, "Updated the implementation%.", "expanded claims should show the full agent response")
t.assert_eq(addressed_sign.virt_lines_above, true, "expanded responses should use wrapped virtual lines in end-of-line mode")

expanded_claim_id = nil
render_ctx.claim_review_status = function(id)
	if id == "stale-claim" then
		return {
			addressed = true,
			outcome = "answered",
			summary = "This response should remain hidden while collapsed.",
		}
	end
end
inline_notes_layout = "inline"
render.clear_buffer_claims(render_ctx, bufnr)
render.render_claim(render_ctx, bufnr, file_state.claims[2])

local collapsed_answered_sign
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, render_ctx.ns, 0, -1, { details = true })) do
	local details = mark[4] or {}
	if details.sign_text and vim.startswith(details.sign_text, claims.meta("question").sign) then
		collapsed_answered_sign = details
	end
end
local collapsed_answered_text = virt_line_text(collapsed_answered_sign.virt_text)
t.assert_match(collapsed_answered_text, "answered", "collapsed claims should retain their response outcome badge")
t.assert_eq(collapsed_answered_text:match("Agent response"), nil, "collapsed answered claims should hide the response preview")
t.assert_eq(collapsed_answered_text:match("remain hidden"), nil, "collapsed answered claims should hide response text")

render_ctx.claim_review_status = function(id)
	if id == "stale-claim" then
		return {
			addressed = false,
			outcome = "needs_input",
			summary = "Choose whether this behavior should remain configurable.",
		}
	end
end
inline_notes_layout = "block"
render.clear_buffer_claims(render_ctx, bufnr)
render.render_claim(render_ctx, bufnr, file_state.claims[2])

local needs_input_sign
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, render_ctx.ns, 0, -1, { details = true })) do
	local details = mark[4] or {}
	if details.sign_text and vim.startswith(details.sign_text, claims.meta("question").sign) then
		needs_input_sign = details
	end
end
local needs_input_text = ""
for _, line in ipairs(needs_input_sign.virt_lines) do
	needs_input_text = needs_input_text .. "\n" .. virt_line_text(line)
end
t.assert_match(needs_input_text, "needs input", "collapsed needs-input claims should show a warning badge")
t.assert_match(needs_input_text, "Agent response", "collapsed needs-input claims should show a response preview")
t.assert_match(needs_input_text, "Choose whether", "collapsed needs-input claims should include response text")
t.assert_eq(needs_input_sign.virt_lines[1][#needs_input_sign.virt_lines[1]][2], "DoubtInlineResponseWarning", "needs-input outcomes should use warning badge styling")

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
	end)
end)
