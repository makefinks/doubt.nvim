local t = dofile("tests/helpers/bootstrap.lua")

describe("input", function()
	it("matches expected behavior", function()

package.loaded["doubt.input"] = nil
local mounted_input
package.preload["nui.input"] = function()
	return function(_, opts)
		local instance = {
			maps = {},
			mount = function() end,
			unmount = function(self)
				if opts.on_close then
					opts.on_close()
				end
			end,
		}

		function instance:map(mode, lhs, rhs)
			self.maps[mode .. lhs] = rhs
		end

		mounted_input = instance
		return instance
	end
end

local input = require("doubt.input")
local commands = {}
local original_cmd = vim.cmd

vim.cmd = function(command)
	table.insert(commands, command)
end

input.ask_text({}, function() end)
vim.wait(20, function()
	return #commands > 0
end)
t.assert_eq(commands[1], "startinsert!", "text prompt should enter insert mode when mounted")

commands = {}
input.ask_text({}, function() end)
mounted_input:unmount()
vim.wait(20, function()
	for _, command in ipairs(commands) do
		if command == "stopinsert" then
			return true
		end
	end
	return false
end)
local closed_insert = false
for _, command in ipairs(commands) do
	if command == "stopinsert" then
		closed_insert = true
		break
	end
end
t.assert_eq(closed_insert, true, "text prompt should leave insert mode when closed")

commands = {}
local note = input.ask_note({}, function() end)
note.cancel()
vim.wait(20, function()
	for _, command in ipairs(commands) do
		if command == "stopinsert" then
			return true
		end
	end
	return false
end)
closed_insert = false
for _, command in ipairs(commands) do
	if command == "stopinsert" then
		closed_insert = true
		break
	end
end
t.assert_eq(closed_insert, true, "note prompt should leave insert mode when closed")

vim.cmd = original_cmd
local original_select = vim.ui.select
local selected_items = nil
local selected_prompt = nil
local selected_kind = nil
local select_callback = nil
vim.ui.select = function(items, opts, callback)
	selected_items = items
	selected_prompt = opts.prompt
	selected_kind = opts.kind
	select_callback = callback
end

local reference_note = input.ask_note({
	default = "see ",
	files = { "lua/doubt/init.lua", "lua/doubt/input.lua" },
}, function() end)
vim.api.nvim_set_current_win(reference_note.winid)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A@", true, false, true), "xt", false)
vim.wait(20, function()
	return selected_items ~= nil
end)
vim.api.nvim_win_set_cursor(reference_note.winid, { 1, 0 })
select_callback(selected_items[2])

t.assert_eq(selected_prompt, "Reference file", "file reference picker should use a clear prompt")
t.assert_eq(selected_kind, "file", "file reference picker should identify its item kind")
t.assert_eq(selected_items, { "lua/doubt/init.lua", "lua/doubt/input.lua" }, "file picker should receive candidate paths")
t.assert_eq(
	vim.api.nvim_buf_get_lines(reference_note.bufnr, 0, -1, false)[1],
	"see `@lua/doubt/input.lua` ",
	"selected file path should be inserted as a plain @ reference"
)
reference_note.cancel()
vim.ui.select = original_select

local original_input = vim.fn.input
local original_inputsave = vim.fn.inputsave
local original_inputrestore = vim.fn.inputrestore
local command_prompt_calls = {}
local inputsave_calls = 0
local inputrestore_calls = 0

vim.fn.inputsave = function()
	inputsave_calls = inputsave_calls + 1
end
vim.fn.inputrestore = function()
	inputrestore_calls = inputrestore_calls + 1
end
vim.fn.input = function(opts)
	table.insert(command_prompt_calls, opts)
	return "  native session  "
end

local command_value = nil
local command_cancelled = nil
input.ask_command_text({
	default = "existing",
	prompt = "Start session: ",
}, function(value, cancelled)
	command_value = value
	command_cancelled = cancelled
end)

t.assert_eq(command_value, "native session", "command text prompt should trim submitted values")
t.assert_eq(command_cancelled, false, "command text prompt should report submitted values")
t.assert_eq(command_prompt_calls[1].prompt, "Start session: ", "command text prompt should pass prompt text")
t.assert_eq(command_prompt_calls[1].default, "existing", "command text prompt should pass default text")
t.assert_eq(inputsave_calls, 1, "command text prompt should save typeahead state")
t.assert_eq(inputrestore_calls, 1, "command text prompt should restore typeahead state")

vim.fn.input = function(opts)
	return opts.cancelreturn
end

command_value = "unchanged"
command_cancelled = false
input.ask_command_text({ prompt = "Start session: " }, function(value, cancelled)
	command_value = value
	command_cancelled = cancelled
end)

t.assert_eq(command_value, nil, "command text prompt should return nil on cancellation")
t.assert_eq(command_cancelled, true, "command text prompt should report cancellation")

vim.fn.input = original_input
vim.fn.inputsave = original_inputsave
vim.fn.inputrestore = original_inputrestore
vim.cmd = original_cmd
	end)
end)
