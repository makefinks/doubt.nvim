local t = dofile("tests/helpers/bootstrap.lua")

describe("panel overview review status", function()
	it("counts addressed claims separately from unresolved stale claims", function()
		local lines = require("doubt.panel.lines")
		local config = require("doubt.config")
		config.setup({})

		local path = vim.fs.joinpath(vim.fn.tempname(), "review.lua")
		local sessions = {
			review = {
				files = {
					[path] = {
						claims = {
							{ id = "addressed", freshness = "stale" },
							{ id = "unresolved", freshness = "stale" },
						},
					},
				},
			},
		}
		local inspected = {}
		local ctx = {
			config = config,
			review_run_inspection_for = function(session_name, source)
				table.insert(inspected, source .. ":" .. session_name)
				return {
					statuses = {
						addressed = { addressed = true },
						unresolved = { addressed = false },
					},
				}
			end,
			state = {
				active_session_name = function()
					return nil
				end,
				current_files = function()
					return {}
				end,
				list_sessions = function()
					return { "review" }
				end,
				list_workspace_sessions = function()
					return {}
				end,
				get = function()
					return { sessions = sessions }
				end,
			},
		}

		local rendered = lines.build_lines(ctx, 80)
		local session_line
		for _, item in ipairs(rendered) do
			if item.kind == "session" and item.session_name == "review" then
				session_line = item
			end
		end

		t.assert_eq(inspected, { "local:review" }, "overview should inspect the saved session's review runs")
		t.assert_match(session_line.text, "%[addressed 1%]", "addressed claims should have their own rollup")
		t.assert_match(session_line.text, "%[stale 1%]", "only unresolved stale claims should remain in the rollup")
	end)
end)
