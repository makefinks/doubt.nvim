local t = dofile("tests/helpers/bootstrap.lua")
local export = require("doubt.export")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local temp_file = vim.fs.joinpath(vim.fn.tempname(), "sample.lua")

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
vim.fn.writefile({ "local value = 1", "return value" }, temp_file)

local doubt = require("doubt")
local state = require("doubt.state")
local original_select = vim.ui.select

	doubt.setup({
		export = {
			instructions = {
				blocker = "Treat blocker claims as required fixes before continuing.",
			},
		},
		claim_kinds = {
			question = {
				command = "Question",
			label = "?",
		},
		concern = {
			command = "Concern",
			label = "~",
		},
		reject = {
			command = "Reject",
			label = "!",
		},
		blocker = {
			command = "Blocker",
			default_note = "blocker",
			description = "Block current line or selection",
			label = "X",
			order = 30,
		},
	},
	input = {
		prompts = {
			blocker = "Blocker note: ",
		},
	},
	keymaps = {
		question = false,
		concern = false,
		reject = false,
		claims = {
			blocker = "<leader>Dz",
		},
		export = false,
		clear_buffer = false,
		panel = false,
		session_new = false,
		session_resume = false,
		stop_session = false,
		refresh = false,
	},
	state_path = temp_state,
	signs = {
		blocker = "X",
	},
})

t.assert_eq(vim.fn.exists(":DoubtClaim"), 2, "generic claim command should be registered")
t.assert_eq(vim.fn.exists(":DoubtBlocker"), 2, "custom claim command should be registered")
t.assert_eq(vim.fn.getcompletion("DoubtClaim b", "cmdline"), { "blocker" }, "generic claim command should complete configured kinds")
t.assert_eq(vim.fn.getcompletion("DoubtClaimKind b", "cmdline"), { "blocker" }, "claim kind edit command should complete configured kinds")

local blocker_map = vim.fn.maparg("<leader>Dz", "n", false, true)
t.assert_eq(blocker_map.desc, "Block current line or selection", "custom claim keymap should use configured description")

vim.cmd.edit(temp_file)
doubt.start_session({ name = "custom-kinds", quiet = true })
vim.cmd("DoubtBlocker needs benchmark")

local files = state.current_files()
local paths = vim.tbl_keys(files)
t.assert_eq(#paths, 1, "custom claim command should track the edited file")

local claims = files[paths[1]].claims
t.assert_eq(#claims, 1, "custom claim command should add a claim")
t.assert_eq(claims[1].kind, "blocker", "custom claim command should persist the configured kind")
t.assert_eq(claims[1].note, "needs benchmark", "custom claim command should keep the provided note")

local picked_items
vim.ui.select = function(items, _, callback)
	picked_items = vim.deepcopy(items)
	callback("question")
end

doubt.edit_nearest_claim_kind()
claims = files[paths[1]].claims
t.assert_eq(picked_items, { "question", "concern", "reject" }, "claim kind picker should exclude the current custom kind")
t.assert_eq(claims[1].kind, "question", "claim kind picker should support switching from a custom kind")

local blocker_xml = export.build_session_xml("custom-kinds", {
	[temp_file] = {
		claims = {
			{
				kind = "blocker",
				start_line = 0,
				start_col = 0,
				end_line = 0,
				end_col = 5,
				note = "needs benchmark",
			},
		},
	},
})

t.assert_match(
	blocker_xml,
	'<instruction kind="blocker">Treat blocker claims as required fixes before continuing%.</instruction>',
	"custom claim kinds should use configured export instructions"
)

vim.ui.select = original_select
