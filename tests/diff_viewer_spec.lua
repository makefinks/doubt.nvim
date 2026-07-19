local t = dofile("tests/helpers/bootstrap.lua")

describe("diff viewer adapters", function()
	it("opens claim-only synthetic trees with CodeDiff", function()
		local diff_viewer = require("doubt.diff_viewer")
		pcall(vim.api.nvim_del_user_command, "CodeDiff")
		local command_args = nil
		vim.api.nvim_create_user_command("CodeDiff", function(opts)
			command_args = opts.fargs
		end, { nargs = "+" })

		local result = {
			run = { run_id = "run-test" },
			lines = { "claim patch" },
			status = {
				matches = {
					{
						file = { path = "lua/example.lua", new_path = "lua/example.lua" },
						hunk = {
							lines = {
								"@@ -1,2 +1,3 @@",
								" local value = load()",
								"-return value",
								"+if value == nil then",
								"+\treturn nil",
								"+end",
							},
						},
					},
				},
			},
		}
		local opened = diff_viewer.open({
			claim_id = "claim-1",
			result = result,
			viewer = "codediff",
		})
		t.assert_eq(opened, true, "CodeDiff adapter should accept textual claim hunks")
		t.assert_eq(command_args[1], "dir", "CodeDiff adapter should use directory comparison mode")
		local before_dir = command_args[2]
		local after_dir = command_args[3]
		local before = vim.fn.readfile(vim.fs.joinpath(before_dir, "lua", "example.lua"))
		local after = vim.fn.readfile(vim.fs.joinpath(after_dir, "lua", "example.lua"))
		t.assert_eq(before, { "local value = load()", "return value" }, "before tree should contain only attributed hunk lines")
		t.assert_eq(after, {
			"local value = load()",
			"if value == nil then",
			"\treturn nil",
			"end",
		}, "after tree should contain only attributed hunk lines")

		vim.api.nvim_exec_autocmds("User", { pattern = "CodeDiffClose" })
		t.assert_eq(vim.uv.fs_stat(vim.fs.dirname(before_dir)), nil, "closing CodeDiff should remove synthetic trees")
		vim.api.nvim_del_user_command("CodeDiff")
	end)

	it("exposes a viewer-neutral payload to custom adapters", function()
		local diff_viewer = require("doubt.diff_viewer")
		local received = nil
		local opened = diff_viewer.open({
			claim_id = "claim-custom",
			result = {
				run = { run_id = "run-custom" },
				lines = { "patch" },
				status = { matches = {} },
			},
			viewer = function(payload)
				received = payload
				return true
			end,
		})
		t.assert_eq(opened, true, "custom viewer should control opening")
		t.assert_eq(received.claim_id, "claim-custom", "custom viewer should receive claim identity")
		t.assert_eq(received.patch_lines, { "patch" }, "custom viewer should receive the canonical patch")
	end)

	it("opens claim-only synthetic commits with Diffview", function()
		local diff_viewer = require("doubt.diff_viewer")
		pcall(vim.api.nvim_del_user_command, "DiffviewOpen")
		local command_args = nil
		vim.api.nvim_create_user_command("DiffviewOpen", function(opts)
			command_args = opts.fargs
		end, { nargs = "+" })
		local opened = diff_viewer.open({
			claim_id = "claim-diffview",
			result = {
				run = { run_id = "run-diffview" },
				lines = { "patch" },
				status = {
					matches = {
						{
							file = { path = "feature.lua", new_path = "feature.lua" },
							hunk = { lines = { "@@ -1 +1 @@", "-old", "+new" } },
						},
					},
				},
			},
			viewer = "diffview",
		})
		t.assert_eq(opened, true, "Diffview adapter should accept textual claim hunks")
		t.assert_match(command_args[1], "^-C", "Diffview adapter should target its synthetic repository")
		t.assert_match(command_args[2], "^[0-9a-f]+%.%.[0-9a-f]+$", "Diffview adapter should compare synthetic before and after commits")
		local root = command_args[1]:sub(3)
		vim.api.nvim_exec_autocmds("User", { pattern = "DiffviewViewClosed" })
		t.assert_eq(vim.uv.fs_stat(root), nil, "closing Diffview should remove its synthetic repository")
		vim.api.nvim_del_user_command("DiffviewOpen")
	end)
end)
