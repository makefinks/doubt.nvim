local t = dofile("tests/helpers/bootstrap.lua")

local doubt = require("doubt")

doubt.setup({
	keymaps = {
		question = false,
		reject = false,
		export = "<leader>De",
		clear_buffer = false,
		panel = false,
		session_new = false,
		session_resume = false,
		stop_session = false,
		refresh = false,
	},
})

local normal_maps = vim.api.nvim_get_keymap("n")
local export_map = nil

for _, map in ipairs(normal_maps) do
	if map.lhs == "\\De" then
		export_map = map
		break
	end
end

t.assert_eq(export_map ~= nil, true, "export keymap should be registered")
t.assert_eq(export_map.desc, "Copy doubt export for agent handoff", "export keymap should describe the handoff action")
