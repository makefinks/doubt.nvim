local t = dofile("tests/helpers/bootstrap.lua")

local temp_dir = vim.fn.tempname()
local temp_state = vim.fs.joinpath(temp_dir, "doubt-state.json")
local temp_preferences = vim.fs.joinpath(temp_dir, "doubt-preferences.json")

vim.fn.mkdir(temp_dir, "p")
vim.fn.writefile({ vim.json.encode({ inline_notes_layout = "inline" }) }, temp_preferences)

local doubt = require("doubt")

doubt.setup({
	keymaps = false,
	state_path = temp_state,
	preferences_path = temp_preferences,
})

local layout = doubt.toggle_inline_notes()
t.assert_eq(layout, "block", "setup should restore the persisted inline notes layout")

local saved_preferences = vim.json.decode(table.concat(vim.fn.readfile(temp_preferences), "\n"))
t.assert_eq(saved_preferences.inline_notes_layout, "block", "toggle should persist the new inline notes layout")

doubt.start_session({ name = "preferences", quiet = true })
local saved_state = vim.json.decode(table.concat(vim.fn.readfile(temp_state), "\n"))
t.assert_eq(saved_state.inline_notes_layout, nil, "preferences should not be written to session state root")
t.assert_eq(saved_state.preferences, nil, "preferences should not be written to session state root")

doubt.setup({
	keymaps = false,
	state_path = temp_state,
	preferences_path = temp_preferences,
})

layout = doubt.toggle_inline_notes()
t.assert_eq(layout, "inline", "setup should restore block layout from the separate preferences file")
