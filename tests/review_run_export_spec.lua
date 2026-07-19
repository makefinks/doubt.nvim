local t = dofile("tests/helpers/bootstrap.lua")

describe("review run export", function()
	it("creates an agent-attribution checkpoint for trusted handoffs", function()
		local doubt = require("doubt")
		local claims = require("doubt.claims")
		local state = require("doubt.state")
		local original_cwd = vim.fn.getcwd()
		local root = vim.fn.tempname()
		vim.fn.mkdir(vim.fs.joinpath(root, "lua"), "p")
		vim.fn.writefile({ "return risky_value()" }, vim.fs.joinpath(root, "lua", "feature.lua"))
		vim.fn.writefile({ ".doubt/runs/" }, vim.fs.joinpath(root, ".gitignore"))
		vim.fn.mkdir(vim.fs.joinpath(root, ".doubt", "runs", "previous-run"), "p")
		vim.fn.writefile({ "ignored" }, vim.fs.joinpath(root, ".doubt", "runs", "previous-run", "run.json"))
		vim.system({ "git", "init", "-q", root }, { text = true }):wait()
		vim.cmd.cd(root)

		doubt.setup({
			export = { register = "z" },
			keymaps = false,
			state_path = vim.fs.joinpath(vim.fn.tempname(), "state.json"),
		})
		state.set_active_session("handoff")
		local path = vim.fs.joinpath(root, "lua", "feature.lua")
		local content = table.concat(vim.fn.readfile(path), "\n")
		local file_state = state.ensure_file_entry(path)
		table.insert(file_state.claims, {
			id = "claim-risk",
			kind = "concern",
			start_line = 0,
			start_col = 0,
			end_line = 0,
			end_col = #content,
			note = "Make this failure explicit",
			freshness = "fresh",
			anchor = claims.build_content_anchor(content, 0, 0, 0, #content),
		})

		local exported = doubt.copy_export()
		t.assert_match(exported, '<doubt session="handoff" run_id="run%-[^\"]+" manifest_path="%.doubt/runs/[^\"]+/results%.json">', "handoff XML should identify its review run")
		t.assert_match(exported, 'id="claim%-risk"', "handoff claims should expose stable IDs")
		t.assert_match(exported, "Doubt review run protocol:", "handoff should tell the agent how to report attribution")
		t.assert_match(exported, "Associate every intentional changed region with one or more claim IDs", "protocol should require semantic attribution")
		t.assert_match(exported, "Write the summary as a concise, direct response", "protocol should request reviewer-facing answers")
		t.assert_match(exported, "do not narrate investigation steps", "protocol should discourage process narration")
		t.assert_match(exported, "Summary must directly answer the question or feedback", "answered claims should receive direct responses")
		t.assert_match(exported, "Do not duplicate these results as a claim%-by%-claim final response", "protocol should keep the conversational response concise")
		t.assert_eq(exported:find("Repository root: " .. root, 1, true) ~= nil, true, "protocol should identify the exact repository root")

		local run_id = exported:match('run_id="([^"]+)"')
		local run_file = vim.fs.joinpath(root, ".doubt", "runs", run_id, "run.json")
		local absolute_pending_path = vim.fs.joinpath(root, ".doubt", "runs", run_id, "results.pending.json")
		local absolute_helper_path = vim.fs.joinpath(root, ".doubt", "runs", run_id, "complete")
		t.assert_eq(exported:find("pending results manifest to " .. absolute_pending_path, 1, true) ~= nil, true, "protocol should provide the absolute pending result path")
		t.assert_eq(exported:find(absolute_helper_path, 1, true) ~= nil, true, "protocol should provide the exact completion helper path")
		t.assert_match(exported, "Do not write results%.json directly", "protocol should make the completion helper authoritative")
		t.assert_eq(vim.uv.fs_stat(run_file) ~= nil, true, "export should persist its baseline metadata")
		t.assert_eq(vim.uv.fs_stat(absolute_helper_path) ~= nil, true, "export should generate the completion helper")
		local run = vim.json.decode(table.concat(vim.fn.readfile(run_file), "\n"))
		t.assert_eq(run.claims[1].file, "lua/feature.lua", "run metadata should use repository-relative paths")
		t.assert_eq(run.claims[1].id, "claim-risk", "run metadata should retain claim identity")
		t.assert_eq(run.baseline.type, "git-tree", "run should use an exact Git tree baseline")
		t.assert_match(run.baseline.ref, "^refs/doubt/runs/", "run should retain its baseline outside branch history")
		t.assert_match(run.pending_manifest_path, "results%.pending%.json$", "run metadata should record the pending manifest")
		t.assert_match(run.completion_helper_path, "complete$", "run metadata should record its completion helper")
		t.assert_eq(vim.uv.fs_stat(vim.fs.joinpath(root, ".doubt", "runs", "previous-run", "run.json")) ~= nil, true, "repeat exports should preserve earlier ignored runs")

		vim.cmd.cd(original_cwd)
	end)
end)
