local lines = require("doubt.panel.lines")
local render = require("doubt.panel.render")
local window = require("doubt.panel.window")

local M = {}

M.build_lines = lines.build_lines
M.render = render.render
M.highlight_active_claim = render.highlight_active_claim
M.open = function(ctx)
	window.open(ctx, M)
end

return M
