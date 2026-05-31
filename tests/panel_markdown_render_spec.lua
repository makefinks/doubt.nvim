local t = dofile("tests/helpers/bootstrap.lua")

describe("panel markdown render", function()
	it("matches expected behavior", function()

package.loaded["doubt"] = nil
package.loaded["doubt.panel"] = nil

local doubt = require("doubt")
local claims = require("doubt.claims")
local panel = require("doubt.panel")
local panel_state = require("doubt.panel.state").panel_state

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local path = vim.fs.normalize(vim.fs.joinpath(vim.fn.tempname(), "markdown-panel.lua"))

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(path), "p")

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

local note = "Use `c` **b** __s__ *i* _e_ plus filler words before ~~old assumptions~~."
local claim = claims.normalize_claim({
	id = "markdown-claim",
	kind = "concern",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 8,
	note = note,
	freshness = "fresh",
})

local ctx = {
	augroup = vim.api.nvim_create_augroup("doubt-panel-markdown-render-spec", { clear = true }),
	config = require("doubt.config"),
	state = {
		current_files = function()
			return {
				[path] = {
					claims = { claim },
				},
			}
		end,
		active_session_name = function()
			return "markdown-render"
		end,
		active_session_source = function()
			return "local"
		end,
		list_sessions = function()
			return {}
		end,
		get = function()
			return { sessions = {} }
		end,
	},
	api = {
		refresh = function() end,
		start_session = function() end,
		resume_session = function() end,
		stop_session = function() end,
		delete_session = function() end,
		rename_session = function() end,
		clear_focused_claim = function() end,
		focus_claim = function() end,
		delete_claim = function() end,
		delete_file = function() end,
	},
	ns = vim.api.nvim_create_namespace("doubt.panel.markdown.render.spec"),
}

panel.open(ctx)

local panel_win = vim.api.nvim_get_current_win()
local bufnr = vim.api.nvim_get_current_buf()
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local note_row
local note_end_row

for idx, line in ipairs(lines) do
	if line:find("`c`", 1, true) then
		note_row = idx - 1
	end
	if line:find("~~old assumptions~~", 1, true) then
		note_end_row = idx - 1
	end
end

t.assert_eq(note_row ~= nil, true, "panel should render the raw markdown note text in the buffer")
t.assert_eq(note_end_row ~= nil, true, "panel should keep markdown spans intact when wrapping notes")
t.assert_eq(vim.wo[panel_win].conceallevel, 2, "panel window should enable delimiter concealment")

local inline_label, inline_text = claims.inline_text(claim)
t.assert_eq(inline_label, claims.meta("concern").inline_label, "inline label should stay unchanged")
t.assert_eq(inline_text, note, "inline claim text should stay raw markdown")

local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ctx.ns, { note_row, 0 }, { note_end_row, #lines[note_end_row + 1] }, { details = true })
local highlight_counts = {}
local conceal_count = 0

for _, mark in ipairs(extmarks) do
	local details = mark[4]
	if details.hl_group then
		highlight_counts[details.hl_group] = (highlight_counts[details.hl_group] or 0) + 1
	end
	if details.conceal == "" then
		conceal_count = conceal_count + 1
	end
end

t.assert_eq(highlight_counts.DoubtPanelMarkdownCode, 1, "panel should highlight inline code spans")
t.assert_eq(highlight_counts.DoubtPanelMarkdownBold, 2, "panel should highlight ** and __ bold spans")
t.assert_eq(highlight_counts.DoubtPanelMarkdownItalic, 2, "panel should highlight * and _ italic spans")
t.assert_eq(highlight_counts.DoubtPanelMarkdownStrike, 1, "panel should keep wrapped ~~ spans together and highlight them")
t.assert_eq(conceal_count, 12, "panel should conceal paired markdown delimiters")

vim.api.nvim_win_set_cursor(panel_win, { note_row + 1, 0 })
panel.highlight_active_claim()

local active_marks = vim.api.nvim_buf_get_extmarks(bufnr, panel_state.active_ns, { note_row, 0 }, { note_row, -1 }, { details = true })
t.assert_eq(#active_marks > 0, true, "active claim should render a selected-row marker")
t.assert_eq(active_marks[1][4].line_hl_group, nil, "active claim should not apply a full-row highlight")
t.assert_eq(active_marks[1][4].sign_text, "▌ ", "active claim should use the sign column marker")
t.assert_eq(active_marks[1][4].priority, 300, "active claim sign should stay above other panel signs")

if vim.api.nvim_win_is_valid(panel_win) then
	vim.api.nvim_win_close(panel_win, true)
end
	end)
end)
