local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local temp_file = vim.fs.joinpath(vim.fn.tempname(), "inline-render.lua")
local deleted_line_file = vim.fs.joinpath(vim.fn.tempname(), "deleted-lines.lua")

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
vim.fn.mkdir(vim.fs.dirname(deleted_line_file), "p")
vim.fn.writefile({ "local alpha = 1", "local beta = alpha + 1", "return beta" }, temp_file)
vim.fn.writefile({ "first = 1", "second = 2", "third = first + second" }, deleted_line_file)

local doubt = require("doubt")
local claims = require("doubt.claims")
local render = require("doubt.render")
local state = require("doubt.state")

doubt.setup({
	keymaps = false,
	state_path = temp_state,
	inline_notes = {
		enabled = true,
		max_width = 14,
		padding_right = 1,
		prefix = "",
	},
})

vim.cmd.edit(temp_file)
doubt.start_session({ name = "inline-render", quiet = true })

local bufnr = vim.api.nvim_get_current_buf()
local ns = vim.api.nvim_get_namespaces()["doubt.nvim"]
local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
local file_state = state.ensure_file_entry(path)

table.insert(file_state.claims, {
	id = "first",
	kind = "question",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 5,
	note = "alpha beta gamma delta",
})

table.insert(file_state.claims, {
	id = "second",
	kind = "reject",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 4,
	note = "omega sigma lambda kappa",
})

claims.sort_claims(file_state.claims)

local ctx = {
	ns = ns,
	config = require("doubt.config"),
	state = state,
	current_path = function(target_bufnr)
		return vim.fs.normalize(vim.api.nvim_buf_get_name(target_bufnr))
	end,
}

local function render_marks()
	render.refresh_buffer(ctx, bufnr)
	return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

local function current_marks()
	return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

local function mark_by_sign_text(marks, sign_text)
	for _, mark in ipairs(marks) do
		local details = mark[4] or {}
		if vim.trim(details.sign_text or "") == sign_text and details.virt_lines then
			return details
		end
	end
	return nil
end

local function mark_with_end_row(marks)
	for _, mark in ipairs(marks) do
		local details = mark[4] or {}
		if details.end_row ~= nil then
			return details
		end
	end
	return nil
end

local function virt_line_text(line)
	local chunks = {}
	for _, chunk in ipairs(line or {}) do
		table.insert(chunks, chunk[1])
	end
	return table.concat(chunks, "")
end

local function virt_line_width(line)
	return vim.fn.strdisplaywidth(virt_line_text(line))
end

local marks = render_marks()
local question_mark = mark_by_sign_text(marks, "?")
local reject_mark = mark_by_sign_text(marks, "!")

t.assert_eq(question_mark ~= nil, true, "render should create a virtual-line extmark for the question claim")
t.assert_eq(reject_mark ~= nil, true, "render should create a virtual-line extmark for the reject claim")
t.assert_match(virt_line_text(question_mark.virt_lines[2]), "%.%.%. 19 more", "compact inline notes should show the hidden character count")
t.assert_eq(question_mark.virt_lines_above, true, "compact claim notes should render above the claim")
t.assert_eq(reject_mark.virt_lines_above, true, "other compact claims should keep the default above-claim layout")
t.assert_eq(question_mark.virt_lines[1][2][2], "DoubtInlineBar", "compact question claims should frame the note with the shared bar row")
t.assert_eq(question_mark.virt_lines[2][2][2], "DoubtInlineQuestionLabel", "compact question claims should keep the colored label")
t.assert_eq(question_mark.virt_lines[2][3][2], "DoubtInlineQuestionText", "compact question claim text should stay on the dark body treatment")
t.assert_eq(reject_mark.virt_lines[1][2][2], "DoubtInlineBar", "compact reject claims should frame the note with the shared bar row")
t.assert_eq(reject_mark.virt_lines[2][2][2], "DoubtInlineRejectLabel", "compact reject claims should keep the colored label")
t.assert_eq(reject_mark.virt_lines[2][3][2], "DoubtInlineRejectText", "compact reject claim text should stay on the dark body treatment")

vim.api.nvim_win_set_cursor(0, { 1, 1 })
doubt.toggle_nearest_claim()

marks = current_marks()
question_mark = mark_by_sign_text(marks, "?")
reject_mark = mark_by_sign_text(marks, "!")

t.assert_eq(question_mark.virt_lines_above, true, "expanded current claim should stay above the first selected line")
t.assert_match(virt_line_text(question_mark.virt_lines[2]), "alpha beta", "expanded claim should include the full note content")
t.assert_eq(question_mark.virt_lines[1][2][2], "DoubtInlineBar", "expanded question claims should keep the shared bar row")
t.assert_eq(question_mark.virt_lines[2][2][2], "DoubtInlineQuestionLabel", "expanded question claims should keep the colored label")
t.assert_eq(question_mark.virt_lines[2][3][2], "DoubtInlineQuestionText", "expanded question claim body text should stay dark")
	t.assert_eq(question_mark.virt_lines[3][2][2], "DoubtInlineBar", "wrapped rows should keep the frame gutter under the label")
	t.assert_eq(question_mark.virt_lines[3][3][2], "DoubtInlineQuestionText", "wrapped rows should keep the same dark body text treatment")
	t.assert_eq(virt_line_width(question_mark.virt_lines[1]), virt_line_width(question_mark.virt_lines[2]), "expanded frame should match the first content row width")
	t.assert_eq(virt_line_width(question_mark.virt_lines[1]), virt_line_width(question_mark.virt_lines[3]), "expanded frame should match wrapped content row widths")
	t.assert_eq(virt_line_width(question_mark.virt_lines[1]), virt_line_width(question_mark.virt_lines[4]), "expanded frame should match the closing bar width")
	t.assert_eq(question_mark.virt_lines[4][2][2], "DoubtInlineBar", "expanded claims should close with the shared bar treatment")
	t.assert_eq(reject_mark.virt_lines_above, true, "non-expanded claims should stay compact")

doubt.toggle_nearest_claim()

marks = current_marks()
question_mark = mark_by_sign_text(marks, "?")

t.assert_eq(question_mark.virt_lines_above, true, "toggling the same claim again should collapse it")
t.assert_match(virt_line_text(question_mark.virt_lines[2]), "%.%.%. 19 more", "collapsed claim should return to the compact truncation text")

vim.cmd.edit(deleted_line_file)
doubt.start_session({ name = "deleted-line-refresh", quiet = true })

bufnr = vim.api.nvim_get_current_buf()
path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
file_state = state.ensure_file_entry(path)

table.insert(file_state.claims, {
	id = "deleted-range",
	kind = "reject",
	start_line = 0,
	start_col = 0,
	end_line = 2,
	end_col = 5,
	note = "deleted lines",
})

claims.sort_claims(file_state.claims)

vim.api.nvim_buf_set_lines(bufnr, 1, -1, false, {})
vim.bo[bufnr].modified = false

local ok, err = pcall(function()
	doubt.refresh()
end)

t.assert_eq(ok, true, "refresh should not fail when claim end_line extends past deleted lines")

local deleted_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
local deleted_mark = mark_with_end_row(deleted_marks)

t.assert_eq(deleted_mark ~= nil, true, "refresh should still render the deleted-line claim highlight")
t.assert_eq(deleted_mark.end_row, 0, "deleted-line claim highlight should clamp to the last surviving row")

if not ok then
	t.fail(err)
end
