local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
vim.fn.mkdir(vim.fs.dirname(temp_state), "p")

local doubt = require("doubt")
local claims = require("doubt.claims")
local state = require("doubt.state")

local function write_file(path, lines)
	vim.fn.writefile(lines, path)
end

doubt.setup({
	export = {
		register = "a",
	},
	state_path = temp_state,
})

state.set_active_session("copy-review")

local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, "p")
local source_path = vim.fs.joinpath(temp_dir, "copy-source.lua")
write_file(source_path, {
	"target()",
	"tail()",
})

local content = table.concat(vim.fn.readfile(source_path), "\n")

local file_state = state.ensure_file_entry(source_path)
table.insert(file_state.claims, {
	id = "1",
	kind = "question",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 8,
	note = "wrap for agent",
	freshness = "fresh",
	anchor = claims.build_content_anchor(content, 0, 0, 0, 8),
})
claims.sort_claims(file_state.claims)

local notifications = {}
local original_notify = vim.notify
local input = require("doubt.input")
local original_picker = input.ask_checklist
local original_select = vim.ui.select
vim.notify = function(message, level, opts)
	table.insert(notifications, {
		level = level,
		message = message,
		opts = opts,
	})
end

local copied = doubt.copy_export()

vim.notify = original_notify

t.assert_eq(copied, vim.fn.getreg("a"), "copy export should write to the configured register")
t.assert_match(copied, "^The reviewer has provided feedback for the code in the xml below%.", "copy export should use the review wrapper by default")
t.assert_eq(#notifications, 1, "copy export should emit one success notification")
t.assert_eq(notifications[1].message, "Copied doubt export to a (review)", "copy export should mention the register and template")
t.assert_eq(notifications[1].level, vim.log.levels.INFO, "copy export should use an info notification")
t.assert_eq(notifications[1].opts.title, "doubt.nvim", "copy export should use the plugin notify title")

local delegated_template = nil
local picker_prompt = nil
local original_copy_export = doubt.copy_export
doubt.copy_export = function(opts)
	delegated_template = opts and opts.template or nil
	return "delegated"
end

vim.ui.select = function(items, opts, callback)
	picker_prompt = opts.prompt
	callback("multi_agent")
end

doubt.copy_export_with_picker()

t.assert_eq(delegated_template, "multi_agent", "template picker should delegate through copy_export with the selected template")

doubt.copy_export = original_copy_export

local export_picker_map = vim.fn.maparg("<leader>DE", "n", false, true)
t.assert_eq(export_picker_map.desc, "Pick a doubt export template for agent handoff", "template picker keymap should be registered by default")

picker_prompt = nil
vim.ui.select = function(items, opts, callback)
	picker_prompt = opts.prompt
	callback("multi_agent")
end

doubt.copy_export_with_picker()

local picked = vim.fn.getreg("a")
t.assert_eq(picker_prompt, "Choose doubt export template", "template picker should use a helpful prompt")
t.assert_match(picked, "^You are coordinating a response to feedback the reviewer has provided%.", "template picker should export the selected template instead of the default")

input.ask_checklist = function(opts, callback)
	callback({ "question" }, false)
end

vim.cmd("DoubtExportFilter")

local filtered = vim.fn.getreg("a")
t.assert_match(filtered, '^<doubt session="copy%-review">', "filtered export should stay raw-only")
t.assert_eq(filtered:match('kind="reject"'), nil, "filtered export should respect the selected claim kinds")

vim.cmd("DoubtExport review")

local review = vim.fn.getreg("a")
t.assert_match(review, "^The reviewer has provided feedback for the code in the xml below%.", "review export should prepend the review instructions")
t.assert_match(review, "Fetch every referenced file and line from the repository before performing claim specific actions%.", "review export should include fetch guidance")
t.assert_match(review, "\n<doubt session=\"copy%-review\">", "review export should still include the xml payload")

vim.cmd("DoubtExport multi_agent")

local multi_agent = vim.fn.getreg("a")
t.assert_match(multi_agent, "^You are coordinating a response to feedback the reviewer has provided%.", "multi_agent export should prepend the coordinator instructions")
t.assert_match(multi_agent, "Triage each claim, delegate explanation or revision work as needed, and return one consolidated response%.", "multi_agent export should include the triage guidance")
t.assert_match(multi_agent, "\n<doubt session=\"copy%-review\">", "multi_agent export should still include the xml payload")

input.ask_checklist = original_picker
vim.ui.select = original_select
