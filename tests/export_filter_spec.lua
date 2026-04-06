local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
vim.fn.mkdir(vim.fs.dirname(temp_state), "p")

local doubt = require("doubt")
local claims = require("doubt.claims")
local input = require("doubt.input")
local state = require("doubt.state")

doubt.setup({
	export = {
		register = "b",
	},
	keymaps = false,
	state_path = temp_state,
})

state.set_active_session("filter-review")

local alpha = state.ensure_file_entry("lua/doubt/init.lua")
table.insert(alpha.claims, {
	id = "1",
	kind = "question",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 4,
	note = "verify init",
})
table.insert(alpha.claims, {
	id = "2",
	kind = "reject",
	start_line = 3,
	start_col = 0,
	end_line = 3,
	end_col = 6,
	note = "bad branch",
})
claims.sort_claims(alpha.claims)

local beta = state.ensure_file_entry("lua/doubt/state.lua")
table.insert(beta.claims, {
	id = "3",
	kind = "reject",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 5,
	note = "state issue",
})
claims.sort_claims(beta.claims)

local original_picker = input.ask_checklist
local original_notify = vim.notify

local function with_picker(impl, run)
	input.ask_checklist = impl
	local ok, err = pcall(run)
	input.ask_checklist = original_picker
	if not ok then
		error(err)
	end
end

with_picker(function(opts, callback)
	t.assert_eq(vim.tbl_map(function(item)
		return item.label
	end, opts.items), { "question (1)", "concern (0)", "reject (2)" }, "filtered export should list claim kinds in canonical order with counts")
	callback({ "question" }, false)
end, function()
	doubt.copy_filtered_export()
	local copied = vim.fn.getreg("b")
	t.assert_match(copied, '^<doubt session="filter%-review">', "filtered export should still produce raw xml")
	t.assert_match(
		copied,
		'<instruction kind="question">Explain the code and address the feedback without modifying the code%.</instruction>',
		"filtered export should include instructions for surviving claim kinds"
	)
	t.assert_eq(
		copied:match('<instruction kind="reject">'),
		nil,
		"filtered export should omit instructions for filtered-out claim kinds"
	)
	t.assert_match(copied, 'kind="question"', "filtered export should keep selected claim kinds")
	t.assert_eq(copied:match('kind="reject"'), nil, "filtered export should omit unselected claim kinds")
	t.assert_match(copied, '<file path="lua/doubt/init.lua">', "filtered export should keep files with matching claims")
	t.assert_eq(copied:match('<file path="lua/doubt/state.lua">'), nil, "filtered export should omit files left empty after filtering")
end)

local notifications = {}
vim.notify = function(message, level, opts)
	table.insert(notifications, {
		level = level,
		message = message,
		opts = opts,
	})
end

with_picker(function(opts, callback)
	callback({}, false)
end, function()
	doubt.copy_filtered_export()
	t.assert_eq(notifications[#notifications].message, "No claim types selected for filtered export", "empty filtered selection should notify and cancel")
	t.assert_eq(notifications[#notifications].level, vim.log.levels.INFO, "empty filtered selection should be informational")
end)

state.stop_session()
with_picker(function()
	error("picker should not open without an active session")
end, function()
	doubt.copy_filtered_export()
	t.assert_eq(notifications[#notifications].message, "No active doubt session", "filtered export should match existing no-session behavior")
	t.assert_eq(notifications[#notifications].level, vim.log.levels.INFO, "no-session filtered export should be informational")
end)

vim.notify = original_notify
input.ask_checklist = original_picker
