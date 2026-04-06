local t = dofile("tests/helpers/bootstrap.lua")

local doubt = require("doubt")

doubt.setup({
	export = {
		default_template = "agent",
		templates = {
			raw = "{{xml}}",
			agent = "agent\n{{xml}}",
			claude = "claude\n{{xml}}",
		},
	},
	keymaps = false,
})

t.assert_eq(
	doubt.list_export_templates(),
	{ "agent", "claude", "multi_agent", "raw", "review" },
	"export templates should be listed in sorted order"
)

local all = vim.fn.getcompletion("DoubtExport ", "cmdline")
local filtered = vim.fn.getcompletion("DoubtExport cl", "cmdline")

t.assert_eq(all, { "agent", "claude", "multi_agent", "raw", "review" }, "export command should complete named templates")
t.assert_eq(filtered, { "claude" }, "export command completion should filter by prefix")
