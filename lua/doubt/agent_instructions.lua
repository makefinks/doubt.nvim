local claims = require("doubt.claims")

local M = {}

local function bullet_list(items)
	return table.concat(vim.tbl_map(function(item)
		return "- " .. item
	end, items), "\n")
end

function M.render(config)
	config = config or {}
	local kinds = claims.list_claim_kinds()
	local register = ((config.export or {}).register or "+")

	return table.concat({
		"You are writing code-review findings for doubt.nvim.",
		"",
		"Review behavior:",
		bullet_list({
			"Review the current diff/change set first; do not produce broad, whole-codebase feedback unless it is directly relevant to changed behavior.",
			"Only create findings that are actionable and that the author would likely fix if they knew about them.",
			"Prefer no finding over speculative, vague, or low-confidence concerns.",
			"Prioritize correctness bugs, behavioral regressions, data loss, security issues, important performance problems, and missing tests for changed behavior.",
			"Ignore trivial style or nit comments unless they obscure meaning or violate explicit project rules.",
			"Anchor each finding to the smallest useful line range, usually 1-5 lines and rarely more than 10.",
			"Explain why the issue is a problem and name the scenario, input, or environment needed to trigger it.",
			"Keep notes concise, direct, and matter-of-fact. Do not praise, apologize, or add broad summaries.",
		}),
		"",
		"Write findings as doubt.nvim workspace claims under this repository:",
		"",
		".doubt/sessions/<session-name>/",
		"  session.json",
		"  claims/<repo-relative-source-path>.json",
		"",
		"Do not edit the plugin-managed Neovim state file. That file is for doubt.nvim local sessions only.",
		"Do not add .doubt/ to .gitignore automatically.",
		"",
		"Use one JSON file per reviewed source file. Preserve the source path under claims/ and append .json.",
		"Example: lua/doubt/init.lua -> .doubt/sessions/<session-name>/claims/lua/doubt/init.lua.json",
		"",
		"session.json:",
		"```json",
		vim.json.encode({
			schema_version = 1,
			name = "<session-name>",
		}),
		"```",
		"",
		"Per-file claim JSON:",
		"```json",
		vim.json.encode({
			schema_version = 1,
			file = "lua/doubt/init.lua",
			claims = {
				{
					id = "ai-001",
					kind = kinds[1] or "concern",
					start_line = 49,
					start_col = 1,
					end_line = 49,
					end_col = 20,
					note = "Explain the concrete issue and why it matters.",
				},
			},
		}),
		"```",
		"",
		"Coordinate rules:",
		bullet_list({
			"Use one-based line and column numbers. The first line is 1 and the first column is 1.",
			"Use repo-relative file paths in the file field.",
			"Required claim fields: kind, start_line, note.",
			"Recommended claim fields: id, start_col, end_line, end_col.",
			"Optional fields: freshness and anchor. You may omit them; doubt.nvim will compute and update anchors/freshness.",
		}),
		"",
		"Valid claim kinds:",
		bullet_list(kinds),
		"",
		"Use claim kinds this way:",
		bullet_list({
			"concern: likely issue that should be investigated or fixed.",
			"reject: code that should be removed or replaced because it is wrong or unsafe.",
			"question: precise question where the code is unclear and the uncertainty matters for review.",
		}),
		"",
		"After writing claims, tell the user which session name you wrote. The user can open it in doubt.nvim.",
		"Also include a concise findings summary: one bullet per claim, at most one sentence each.",
		"doubt.nvim users can copy these instructions with :DoubtAgentInstructionsCopy or the configured keymap. Current copy register: " .. register,
	}, "\n")
end

return M
