local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
vim.fn.mkdir(vim.fs.dirname(temp_state), "p")

local doubt = require("doubt")
local claims = require("doubt.claims")
local state = require("doubt.state")

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

state.set_active_session("review-xml")

local alpha = state.ensure_file_entry("lua/doubt/init.lua")
table.insert(alpha.claims, {
	id = "2",
	kind = "reject",
	start_line = 4,
	start_col = 0,
	end_line = 6,
	end_col = 3,
	note = "needs fix",
})
claims.sort_claims(alpha.claims)

local beta = state.ensure_file_entry("lua/doubt/state.lua")
table.insert(beta.claims, {
	id = "1",
	kind = "question",
	start_line = 0,
	start_col = 1,
	end_line = 0,
	end_col = 8,
	note = "verify persistence",
})
claims.sort_claims(beta.claims)

vim.cmd("DoubtExportXml")

local bufnr = vim.api.nvim_get_current_buf()
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local xml = table.concat(lines, "\n")

t.assert_eq(vim.bo[bufnr].buftype, "nofile", "export should open a scratch buffer")
t.assert_eq(vim.bo[bufnr].bufhidden, "wipe", "export buffer should wipe on hide")
t.assert_eq(vim.bo[bufnr].swapfile, false, "export buffer should disable swapfile")
t.assert_eq(vim.bo[bufnr].filetype, "xml", "export buffer should be tagged as xml")
t.assert_eq(vim.bo[bufnr].modifiable, false, "export buffer should become read-only after write")
t.assert_eq(vim.api.nvim_win_get_cursor(0), { 1, 0 }, "cursor should land on the first line")

t.assert_match(xml, '^<doubt session="review%-xml">', "export should use the active session name")
t.assert_match(xml, '<file path="lua/doubt/init.lua">', "export should include the first file")
t.assert_match(xml, '<file path="lua/doubt/state.lua">', "export should include the second file")
t.assert_match(xml, 'kind="reject"\n    start_line="5"\n    start_col="0"\n    end_line="7"\n    end_col="3"\n    note="needs fix"', "export should render file claims")
t.assert_match(xml, 'kind="question"\n    start_line="1"\n    start_col="1"\n    end_line="1"\n    end_col="8"\n    note="verify persistence"', "export should render active-session data")
