local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))

vim.opt.runtimepath:prepend(root)

package.preload["nui.input"] = package.preload["nui.input"] or function()
	return function()
		return {
			map = function() end,
			mount = function() end,
			unmount = function() end,
		}
	end
end

local M = {
	root = root,
}

function M.fail(message)
	vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, { err = true })
	vim.cmd("cquit 1")
end

function M.assert_eq(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		M.fail(message or string.format("Expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
	end
end

function M.assert_match(text, pattern, message)
	if type(text) ~= "string" or text:match(pattern) == nil then
		M.fail(message or string.format("Expected %s to match %s", vim.inspect(text), pattern))
	end
end

return M
