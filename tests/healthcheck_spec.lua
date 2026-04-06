local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
vim.fn.mkdir(vim.fs.dirname(temp_state), "p")

local doubt = require("doubt")

doubt.setup({
	keymaps = false,
	state_path = temp_state,
	input = {
		width = 64,
	},
})

local result = doubt.healthcheck()

t.assert_eq(type(result), "table", "healthcheck should return a structured result")
t.assert_eq(type(result.checks), "table", "healthcheck should expose startup checks")
t.assert_eq(type(result.checks.config_merge), "table", "healthcheck should include config merge check")
t.assert_eq(type(result.checks.dependency_nui_input), "table", "healthcheck should include dependency availability check")
t.assert_eq(type(result.checks.command_sanity), "table", "healthcheck should include command sanity check")
t.assert_eq(type(result.checks.session_state_shape), "table", "healthcheck should include session state shape check")

t.assert_eq(result.checks.config_merge.ok, true, "healthcheck should validate config merge behavior")

local bufnr = result.bufnr
t.assert_eq(type(bufnr), "number", "healthcheck should expose report buffer number")
t.assert_eq(vim.bo[bufnr].buftype, "nofile", "healthcheck report should use a scratch buffer")
t.assert_eq(vim.bo[bufnr].bufhidden, "wipe", "healthcheck report should wipe when hidden")
t.assert_eq(vim.bo[bufnr].swapfile, false, "healthcheck report should disable swapfile")
t.assert_eq(vim.bo[bufnr].modifiable, false, "healthcheck report should become read-only after write")

local report = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
t.assert_match(report, "Doubt Healthcheck Report", "healthcheck should render a report heading")
t.assert_match(report, "Config Merge Check: PASS", "healthcheck should include config merge status")
t.assert_match(report, "Dependency Check %[nui%.input%]: PASS", "healthcheck should include dependency status")
t.assert_match(report, "Command Registration Sanity: PASS", "healthcheck should include command sanity status")
t.assert_match(report, "Session State Shape: PASS", "healthcheck should include session state shape status")
t.assert_eq(report:match("How to fix") ~= nil, false, "healthcheck should hide remediation guidance when all checks pass")

package.loaded["nui.input"] = nil
package.preload["nui.input"] = nil

local failing = doubt.healthcheck()
local failing_report = table.concat(vim.api.nvim_buf_get_lines(failing.bufnr, 0, -1, false), "\n")
t.assert_match(failing_report, "Dependency Check %[nui%.input%]: FAIL", "healthcheck should show failing dependency status")
t.assert_match(failing_report, "How to fix", "healthcheck should include remediation guidance when a check fails")

package.preload["nui.input"] = function()
	return function()
		return {
			map = function() end,
			mount = function() end,
			unmount = function() end,
		}
	end
end
package.loaded["nui.input"] = nil

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

vim.cmd("DoubtHealthcheck")

local command_bufnr = vim.api.nvim_get_current_buf()
local command_report = table.concat(vim.api.nvim_buf_get_lines(command_bufnr, 0, -1, false), "\n")
t.assert_match(command_report, "Doubt Healthcheck Report", "command should open the healthcheck report buffer")
