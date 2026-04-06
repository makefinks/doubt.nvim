local t = dofile("tests/helpers/bootstrap.lua")

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
