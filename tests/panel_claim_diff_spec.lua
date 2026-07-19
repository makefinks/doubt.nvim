local t = dofile("tests/helpers/bootstrap.lua")

describe("panel claim diff", function()
	it("opens changes for the selected claim with D", function()
		local panel = require("doubt.panel")
		local config = require("doubt.config")
		local claims = require("doubt.claims")
		local selected = nil
		local path = vim.fs.joinpath(vim.fn.tempname(), "feature.lua")
		config.setup({ panel = { side = "right", width = 50 } })
		config.set_highlights()
		claims.configure(config.get().claim_kinds)

		local ctx = {
			augroup = vim.api.nvim_create_augroup("doubt-panel-claim-diff-spec", { clear = true }),
			config = config,
			ns = vim.api.nvim_create_namespace("doubt.panel.claim.diff.spec"),
			review_run_inspection = function()
				return {
					run = { run_id = "run-test" },
					statuses = {
						["claim-1"] = {
							addressed = true,
							outcome = "changed",
							summary = "Split the module and added focused tests.",
							reported_change_count = 2,
							verified_hunk_count = 3,
						},
						["claim-2"] = {
							addressed = true,
							outcome = "answered",
							summary = "The fallback is required for older Neovim versions.",
							reported_change_count = 0,
							verified_hunk_count = 0,
						},
						["claim-3"] = {
							addressed = true,
							outcome = "disagreed",
							summary = "The concern does not apply because callers require this fallback.",
							reported_change_count = 0,
							verified_hunk_count = 0,
						},
						["claim-4"] = {
							addressed = false,
							outcome = "needs_input",
							summary = "Which compatibility target should this support?",
							reported_change_count = 0,
							verified_hunk_count = 0,
						},
						["claim-5"] = {
							addressed = true,
							outcome = "changed",
							summary = "Adjusted one focused code path.",
							reported_change_count = 1,
							verified_hunk_count = 1,
						},
						["claim-6"] = {
							addressed = false,
							outcome = "changed",
							summary = "Updated the implementation, but its diff could not be matched.",
							reported_change_count = 1,
							verified_hunk_count = 0,
						},
						["claim-7"] = {
							addressed = true,
							outcome = "disagreed",
							summary = "The requested removal would break callers.",
							reported_change_count = 0,
							verified_hunk_count = 0,
						},
					},
					unattributed_count = 1,
					post_response_change_count = 2,
				}
			end,
			state = {
				active_session_name = function()
					return "review"
				end,
				active_session_source = function()
					return "local"
				end,
				current_files = function()
					return {
						[path] = {
							claims = {
								{
									id = "claim-1",
									kind = "concern",
									start_line = 2,
									start_col = 0,
									end_line = 2,
									end_col = 8,
									note = "Split this module",
									freshness = "stale",
								},
								{
									id = "claim-2",
									kind = "question",
									start_line = 4,
									start_col = 0,
									end_line = 4,
									end_col = 8,
									note = "Explain the fallback",
									freshness = "stale",
								},
								{
									id = "claim-3",
									kind = "concern",
									start_line = 6,
									start_col = 0,
									end_line = 6,
									end_col = 8,
									note = "This fallback may be unnecessary",
									freshness = "stale",
								},
								{
									id = "claim-4",
									kind = "question",
									start_line = 8,
									start_col = 0,
									end_line = 8,
									end_col = 8,
									note = "Clarify supported versions",
									freshness = "fresh",
								},
								{
									id = "claim-5",
									kind = "concern",
									start_line = 10,
									start_col = 0,
									end_line = 10,
									end_col = 8,
									note = "Adjust this path",
									freshness = "fresh",
								},
								{
									id = "claim-6",
									kind = "concern",
									start_line = 12,
									start_col = 0,
									end_line = 12,
									end_col = 8,
									note = "Update this implementation",
									freshness = "fresh",
								},
								{
									id = "claim-7",
									kind = "reject",
									start_line = 14,
									start_col = 0,
									end_line = 14,
									end_col = 8,
									note = "Remove this branch",
									freshness = "fresh",
								},
							},
						},
					}
				end,
				list_sessions = function()
					return {}
				end,
				list_workspace_sessions = function()
					return {}
				end,
				get = function()
					return { sessions = {} }
				end,
			},
			api = {
				open_claim_diff = function(opts)
					selected = opts
				end,
				clear_focused_claim = function() end,
				focus_claim = function() end,
				refresh = function() end,
				start_session = function() end,
				resume_session = function() end,
				stop_session = function() end,
				delete_claim = function() end,
				delete_file = function() end,
				delete_session = function() end,
			},
		}

		panel.open(ctx)
		local winid = vim.api.nvim_get_current_win()
		local bufnr = vim.api.nvim_get_current_buf()
		local rendered = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
		t.assert_match(rendered, "Agent response  %[%+3 code changes%]  %[D: view diff%]", "response header should show attributed changes and the diff action")
		t.assert_eq(rendered:match("%[diff 3%]"), nil, "claim metadata should not retain the old diff badge")
		t.assert_match(rendered, "Agent response  %[%+3 code changes%]  %[D: view diff%]\n%s+Split the module", "changed claims should separate the agent summary into a response block")
		t.assert_match(rendered, "focused tests", "changed claim summaries should retain their reasoning")
		t.assert_match(rendered, "Agent response\n%s+The fallback is required", "ordinary answers should not show an outcome badge")
		t.assert_match(rendered, "The fallback is required", "answered claims should show the agent reasoning")
		t.assert_match(rendered, "Agent response  %[concern not valid%]", "disagreed concerns should explain the resolution")
		t.assert_match(rendered, "Agent response\n%s+The requested removal", "other disagreed claim kinds should not show a badge")
		t.assert_match(rendered, "Agent response  %[needs input%]", "response header should badge requests for input")
		t.assert_match(rendered, "Agent response  %[%+1 code change%]  %[D: view diff%]", "singular changes should retain the diff action")
		t.assert_match(rendered, "Agent response  %[code changes unavailable%]", "unmatched changes should explain that their diff is unavailable")
		t.assert_eq(rendered:match("%[code changes unavailable%]%s+%[D: view diff%]"), nil, "unavailable changes should not offer a diff action")
		t.assert_eq(rendered:match("%[stale"), nil, "addressed claims should not retain stale badges or rollups")
		t.assert_eq(rendered:match("Stale%s+3"), nil, "addressed claims should not count as stale in the session summary")
		t.assert_match(rendered, "%[unattributed 1%]", "panel should warn about unattributed run changes")
		t.assert_match(rendered, "%[workspace edited after response%]", "panel should warn about later workspace edits")

		local claim_line = nil
		local response_header = nil
		local response_body = nil
		for index, item in ipairs(panel.build_lines(ctx, 50)) do
			if item.kind == "claim" and item.id == "claim-1" then
				if not claim_line then
					claim_line = index
				end
				if item.text:find("Agent response", 1, true) then
					response_header = item
				elseif item.text:find("Split the module", 1, true) then
					response_body = item
				end
			end
		end
		t.assert_eq(response_header.line_hl_group, "DoubtPanelAgentResponse", "agent response headings should have a distinct background")
		t.assert_eq(response_body.line_hl_group, "DoubtPanelAgentResponse", "agent response bodies should share the response background")
		local decision_highlight = nil
		for _, highlight in ipairs(response_header.highlights) do
			if highlight.hl_group == "DoubtPanelDiff" then
				local highlighted_text = response_header.text:sub(highlight.start_col + 1, highlight.end_col)
				if highlighted_text == "[+3 code changes]" then
					decision_highlight = highlighted_text
					break
				end
			end
		end
		t.assert_eq(decision_highlight, "[+3 code changes]", "the code-change badge should receive success styling")
		vim.api.nvim_win_set_cursor(winid, { claim_line, 0 })
		vim.api.nvim_buf_call(bufnr, function()
			vim.api.nvim_feedkeys(vim.keycode("D"), "xt", false)
		end)
		t.assert_eq(selected, { path = path, id = "claim-1" }, "D should dispatch the selected claim identity")

		if vim.api.nvim_win_is_valid(winid) then
			vim.api.nvim_win_close(winid, true)
		end
	end)
end)
