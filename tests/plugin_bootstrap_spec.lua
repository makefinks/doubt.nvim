local t = dofile("tests/helpers/bootstrap.lua")

vim.cmd.runtime("plugin/doubt.lua")

t.assert_eq(vim.fn.exists(":DoubtExport"), 2, "plugin bootstrap should register user commands")
t.assert_eq(vim.fn.exists(":DoubtConcern"), 2, "plugin bootstrap should register built-in concern commands")
t.assert_eq(vim.fn.exists(":DoubtClaimDelete"), 2, "plugin bootstrap should register claim edit commands")
t.assert_eq(vim.fn.exists(":DoubtClaimKind"), 2, "plugin bootstrap should register claim kind edit commands")
t.assert_eq(vim.fn.exists(":DoubtClaimNote"), 2, "plugin bootstrap should register claim note edit commands")
t.assert_eq(vim.fn.exists(":DoubtClaimToggle"), 2, "plugin bootstrap should register claim expansion toggle commands")
t.assert_eq(vim.fn.exists(":DoubtHealthcheck"), 2, "plugin bootstrap should register healthcheck command")

local export_map = vim.fn.maparg("<leader>De", "n", false, true)
t.assert_eq(export_map.desc, "Copy doubt export for agent handoff", "plugin bootstrap should install default keymaps")

local concern_map = vim.fn.maparg("<leader>Dc", "n", false, true)
t.assert_eq(concern_map.desc, "Flag concern on current line or selection", "plugin bootstrap should install the concern keymap")

local delete_claim_map = vim.fn.maparg("<leader>Dd", "n", false, true)
t.assert_eq(delete_claim_map.desc, "Delete doubt claim nearest to cursor", "plugin bootstrap should install the nearest-claim delete keymap")

local edit_kind_map = vim.fn.maparg("<leader>Dk", "n", false, true)
t.assert_eq(edit_kind_map.desc, "Change doubt claim kind nearest to cursor", "plugin bootstrap should install the nearest-claim kind keymap")

local edit_note_map = vim.fn.maparg("<leader>Dm", "n", false, true)
t.assert_eq(edit_note_map.desc, "Change doubt claim note nearest to cursor", "plugin bootstrap should install the nearest-claim note keymap")

local toggle_claim_map = vim.fn.maparg("<leader>Dt", "n", false, true)
t.assert_eq(toggle_claim_map.desc, "Toggle doubt claim note nearest to cursor", "plugin bootstrap should install the nearest-claim toggle keymap")

local clear_buffer_map = vim.fn.maparg("<leader>Db", "n", false, true)
t.assert_eq(clear_buffer_map.desc, "Clear doubt state for current buffer", "plugin bootstrap should keep a clear-buffer keymap")

local doubt = require("doubt")

doubt.setup({
	export = {
		default_template = "agent",
		templates = {
			raw = "{{xml}}",
			agent = "agent\n{{xml}}",
		},
	},
	keymaps = false,
})

t.assert_eq(vim.fn.maparg("<leader>De", "n"), "", "re-running setup should remove default keymaps when disabled")
t.assert_eq(vim.fn.maparg("<leader>Dc", "n"), "", "re-running setup should remove the concern keymap when disabled")
t.assert_eq(vim.fn.maparg("<leader>Dd", "n"), "", "re-running setup should remove the delete-claim keymap when disabled")
t.assert_eq(vim.fn.maparg("<leader>Dk", "n"), "", "re-running setup should remove the edit-kind keymap when disabled")
t.assert_eq(vim.fn.maparg("<leader>Dm", "n"), "", "re-running setup should remove the edit-note keymap when disabled")
t.assert_eq(vim.fn.maparg("<leader>Dt", "n"), "", "re-running setup should remove the toggle keymap when disabled")
t.assert_eq(vim.fn.maparg("<leader>Db", "n"), "", "re-running setup should remove the clear-buffer keymap when disabled")
t.assert_eq(vim.fn.getcompletion("DoubtExport ", "cmdline"), { "agent", "multi_agent", "raw", "review" }, "re-running setup should refresh command completion")
