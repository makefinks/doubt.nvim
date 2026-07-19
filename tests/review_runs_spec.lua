local t = dofile("tests/helpers/bootstrap.lua")

local function publish_results(review_runs, run, manifest)
	vim.fn.writefile({ vim.json.encode(manifest) }, run.absolute_pending_manifest_path)
	local completion, completion_error = review_runs.complete({
		workspace = run.root,
		run_id = run.run_id,
	})
	t.assert_eq(completion_error, nil, "valid pending results should complete the review run")
	t.assert_eq(type(completion.result.object), "string", "completion should retain an immutable result tree")
	return completion
end

describe("review runs", function()
	it("maps agent manifest entries to authoritative diff hunks", function()
		local review_runs = require("doubt.review_runs")
		local original_cwd = vim.fn.getcwd()
		local root = vim.fn.tempname()
		vim.fn.mkdir(vim.fs.joinpath(root, "lua"), "p")
		vim.fn.mkdir(vim.fs.joinpath(root, "tests"), "p")
		vim.fn.writefile({
			"local M = {}",
			"function M.load()",
			"\treturn read_state()",
			"end",
			"return M",
		}, vim.fs.joinpath(root, "lua", "session.lua"))
		vim.fn.writefile({ "#!/bin/sh", "true" }, vim.fs.joinpath(root, "run.sh"))

		vim.system({ "git", "init", "-q", root }, { text = true }):wait()
		vim.cmd.cd(root)

		local run, create_error = review_runs.create({
			workspace = root,
			session_name = "modularize-review",
			session_source = "local",
			files = {
				[vim.fs.joinpath(root, "lua", "session.lua")] = {
					claims = {
						{
							id = "claim-split",
							start_line = 1,
							end_line = 2,
						},
						{
							id = "claim-explain",
							start_line = 0,
							end_line = 0,
						},
						{
							id = "claim-disagree",
							start_line = 0,
							end_line = 0,
						},
						{
							id = "claim-needs-input",
							start_line = 0,
							end_line = 0,
						},
					},
				},
			},
		})
		t.assert_eq(create_error, nil, "review run should capture a Git baseline")
		t.assert_eq(type(run.baseline.object), "string", "review run should retain the baseline tree")
		local retained = vim.system({ "git", "-C", root, "show-ref", "--verify", run.baseline.ref }, { text = true }):wait()
		t.assert_eq(retained.code, 0, "review run should retain its baseline under a hidden Git ref")
		t.assert_match(run.manifest_path, "^%.doubt/runs/.+/results%.json$", "run should expose the agent manifest path")
		t.assert_eq(vim.uv.fs_stat(run.absolute_completion_helper_path) ~= nil, true, "review runs should include a completion helper")

		vim.fn.writefile({
			"local repository = require('session.repository')",
			"local M = {}",
			"function M.load()",
			"\treturn repository.read()",
			"end",
			"return M",
		}, vim.fs.joinpath(root, "lua", "session.lua"))
		vim.fn.mkdir(vim.fs.joinpath(root, "lua", "session"), "p")
		vim.fn.writefile({
			"local M = {}",
			"function M.read()",
			"\treturn read_state()",
			"end",
			"return M",
		}, vim.fs.joinpath(root, "lua", "session", "repository.lua"))
		vim.fn.writefile({ "describe('repository', function() end)" }, vim.fs.joinpath(root, "tests", "repository_spec.lua"))
		vim.uv.fs_chmod(vim.fs.joinpath(root, "run.sh"), 493)

		vim.fn.writefile({ vim.json.encode({
			schema_version = 1,
			run_id = run.run_id,
			claims = {
				{
					claim_id = "claim-split",
					outcome = "changed",
					changes = {},
				},
			},
		}) }, run.absolute_pending_manifest_path)
		local invalid_helper_result = vim.system({ run.absolute_completion_helper_path }, { cwd = root, text = true }):wait()
		t.assert_eq(invalid_helper_result.code ~= 0, true, "the generated helper should fail visibly for invalid pending results")
		t.assert_match(invalid_helper_result.stderr, "without a summary", "the helper should explain manifest validation failures")
		local invalid_completion, invalid_error = review_runs.complete({ workspace = root, run_id = run.run_id })
		t.assert_eq(invalid_completion, nil, "invalid pending results should not publish")
		t.assert_eq(invalid_error, "Agent results manifest contains a claim result without a summary", "every decision should require agent reasoning")
		t.assert_eq(vim.uv.fs_stat(run.absolute_manifest_path), nil, "failed completion should not publish results")
		vim.fn.writefile({ vim.json.encode({
			schema_version = 1,
			run_id = run.run_id,
			claims = {
				{
					claim_id = "claim-split",
					outcome = "changed",
					summary = "Claimed a code update without declaring its location.",
					changes = {},
				},
			},
		}) }, run.absolute_pending_manifest_path)
		local empty_change_completion, empty_change_error = review_runs.complete({ workspace = root, run_id = run.run_id })
		t.assert_eq(empty_change_completion, nil, "changed outcomes should declare at least one code change")
		t.assert_eq(
			empty_change_error,
			"Agent results manifest contains a changed outcome without code changes",
			"completion should reject contradictory changed results"
		)
		vim.fn.writefile({ vim.json.encode({
			schema_version = 1,
			run_id = run.run_id,
			claims = {
				{
					claim_id = "claim-split",
					outcome = "answered",
					summary = "Only one claim was included.",
					changes = {},
				},
			},
		}) }, run.absolute_pending_manifest_path)
		local incomplete_completion, incomplete_error = review_runs.complete({ workspace = root, run_id = run.run_id })
		t.assert_eq(incomplete_completion, nil, "completion should reject omitted exported claims")
		t.assert_eq(incomplete_error, "Agent results manifest is missing a result for an exported claim", "completion should require one result per claim")

		vim.fn.writefile({ vim.json.encode({
			schema_version = 1,
			run_id = run.run_id,
			claims = {
				{
					claim_id = "claim-split",
					outcome = "changed",
					summary = "Extracted repository access and added tests.",
					changes = {
						{
							path = "lua/session.lua",
							type = "modified",
							description = "Delegated storage access.",
							regions = { { old_start = 1, old_end = 5, new_start = 1, new_end = 6 } },
						},
						{
							path = "lua/session/repository.lua",
							type = "created",
							description = "Added repository module.",
						},
						{
							path = "tests/repository_spec.lua",
							type = "created",
							description = "Added repository tests.",
						},
						{
							path = "run.sh",
							type = "modified",
							description = "Made the helper executable.",
						},
					},
				},
				{
					claim_id = "claim-explain",
					outcome = "answered",
					summary = "Explained without changing code.",
					changes = {},
				},
				{
					claim_id = "claim-disagree",
					outcome = "disagreed",
					summary = "Kept the behavior because callers rely on it.",
					changes = {},
				},
				{
					claim_id = "claim-needs-input",
					outcome = "needs_input",
					summary = "A product decision is required before changing this.",
					changes = {},
				},
			},
		}) }, run.absolute_pending_manifest_path)
		local helper_result = vim.system({ run.absolute_completion_helper_path }, { cwd = root, text = true }):wait()
		t.assert_eq(helper_result.code, 0, "the generated completion helper should publish valid results: " .. (helper_result.stderr or ""))
		t.assert_eq(vim.uv.fs_stat(run.absolute_manifest_path) ~= nil, true, "completion helper should publish results.json: " .. (helper_result.stderr or ""))
		local completion = vim.json.decode(table.concat(vim.fn.readfile(run.absolute_completion_path), "\n"))
		t.assert_eq(completion.run_id, run.run_id, "completion metadata should match the run")
		local completion_ref_result = vim.system({ "git", "-C", root, "show-ref", "--verify", completion.result.ref }, { text = true }):wait()
		t.assert_eq(completion_ref_result.code, 0, "completion helper should retain the result tree under a hidden ref")
		local duplicate_completion, duplicate_error = review_runs.complete({ workspace = root, run_id = run.run_id })
		t.assert_eq(duplicate_completion, nil, "completed runs should be immutable")
		t.assert_eq(duplicate_error, "This doubt review run is already completed", "completion should refuse to reseal a published run")

		local inspection, inspect_error = review_runs.inspect({
			workspace = root,
			session_name = "modularize-review",
			session_source = "local",
		})
		t.assert_eq(inspect_error, nil, "valid agent results should be inspectable")
		t.assert_eq(inspection.statuses["claim-split"].verified_hunk_count, 4, "one claim should own text and file-level changes across files")
		t.assert_eq(inspection.statuses["claim-explain"].verified_hunk_count, 0, "answer-only claims should have no hunks")
		t.assert_eq(inspection.statuses["claim-split"].addressed, true, "changed claims should be addressed when their diff is verified")
		t.assert_eq(inspection.statuses["claim-explain"].addressed, true, "answered claims should be addressed without code changes")
		t.assert_eq(inspection.statuses["claim-disagree"].addressed, true, "disagreed claims should be addressed without code changes")
		t.assert_eq(inspection.statuses["claim-needs-input"].addressed, false, "claims needing input should remain unresolved")
		t.assert_eq(inspection.statuses["claim-split"].summary, "Extracted repository access and added tests.", "changed claims should retain the agent summary")
		t.assert_eq(inspection.unattributed_count, 0, "all declared changes should account for the current diff")

		local claim_diff, diff_error = review_runs.claim_diff({
			workspace = root,
			session_name = "modularize-review",
			session_source = "local",
			claim_id = "claim-split",
		})
		t.assert_eq(diff_error, nil, "claim diff should open when manifest changes match")
		local patch = table.concat(claim_diff.lines, "\n")
		t.assert_match(patch, "lua/session/repository%.lua", "claim diff should include a newly extracted module")
		t.assert_match(patch, "tests/repository_spec%.lua", "claim diff should include new tests")
		t.assert_match(patch, "new mode 100755", "claim diff should include a mode-only change")
		t.assert_match(patch, "Extracted repository access", "claim diff should include the agent summary")

		local no_diff, no_diff_error = review_runs.claim_diff({
			workspace = root,
			session_name = "modularize-review",
			session_source = "local",
			claim_id = "claim-explain",
		})
		t.assert_eq(no_diff, nil, "answer-only claims should not fabricate a diff")
		t.assert_eq(no_diff_error, "The agent reported no code changes for this claim", "answer-only result should be explicit")

		vim.fn.writefile({ "unrelated" }, vim.fs.joinpath(root, "notes.txt"))
		inspection = review_runs.inspect({
			workspace = root,
			session_name = "modularize-review",
			session_source = "local",
		})
		t.assert_eq(inspection.unattributed_count, 0, "later worktree changes should not alter the sealed review diff")
		t.assert_eq(inspection.post_response_change_count, 1, "later worktree changes should be reported separately")
		t.assert_eq(inspection.statuses["claim-split"].verified_hunk_count, 4, "later edits should not alter the recorded claim diff")

		local malicious_id = "run-99991231T235959Z-999999"
		local malicious_dir = vim.fs.joinpath(root, ".doubt", "runs", malicious_id)
		vim.fn.mkdir(malicious_dir, "p")
		vim.fn.writefile({ vim.json.encode({
			schema_version = 1,
			run_id = "../../outside",
			session = "modularize-review",
			source = "local",
			baseline = run.baseline,
		}) }, vim.fs.joinpath(malicious_dir, "run.json"))
		local latest = review_runs.latest({
			workspace = root,
			session_name = "modularize-review",
			session_source = "local",
		})
		t.assert_eq(latest.run_id, run.run_id, "run metadata must not redirect manifest reads outside its directory")

		local published = vim.json.decode(table.concat(vim.fn.readfile(run.absolute_manifest_path), "\n"))
		published.claims[1].summary = "Tampered after completion."
		vim.fn.writefile({ vim.json.encode(published) }, run.absolute_manifest_path)
		local tampered = review_runs.inspect({
			workspace = root,
			session_name = "modularize-review",
			session_source = "local",
		})
		t.assert_eq(tampered.manifest_error, "Published agent results do not match the sealed completion", "inspection should reject results changed after sealing")
		t.assert_eq(vim.tbl_isempty(tampered.statuses), true, "tampered results should not produce claim statuses")

		vim.cmd.cd(original_cwd)
	end)

	it("preserves prior claim results when later exports contain new claims", function()
		local review_runs = require("doubt.review_runs")
		local original_cwd = vim.fn.getcwd()
		local root = vim.fn.tempname()
		local path = vim.fs.joinpath(root, "feature.lua")
		vim.fn.mkdir(root, "p")
		vim.fn.writefile({ "return 1" }, path)
		vim.system({ "git", "init", "-q", root }, { text = true }):wait()
		vim.cmd.cd(root)

		local first_run = review_runs.create({
			workspace = root,
			session_name = "incremental-review",
			session_source = "local",
			files = {
				[path] = {
					claims = { { id = "claim-old", start_line = 0, end_line = 0 } },
				},
			},
		})
		vim.fn.writefile({ "return 2" }, path)
		publish_results(review_runs, first_run, {
			schema_version = 1,
			run_id = first_run.run_id,
			claims = {
				{
					claim_id = "claim-old",
					outcome = "changed",
					summary = "Updated the original implementation.",
					changes = {
						{
							path = "feature.lua",
							type = "modified",
							description = "Updated the return value.",
							regions = { { old_start = 1, old_end = 1, new_start = 1, new_end = 1 } },
						},
					},
				},
			},
		})

		vim.wait(1100)
		local second_run = review_runs.create({
			workspace = root,
			session_name = "incremental-review",
			session_source = "local",
			files = {
				[path] = {
					claims = { { id = "claim-new", start_line = 0, end_line = 0 } },
				},
			},
		})

		local awaiting = review_runs.inspect({
			workspace = root,
			session_name = "incremental-review",
			session_source = "local",
		})
		t.assert_eq(awaiting.run.run_id, second_run.run_id, "the panel header should still describe the newest run")
		t.assert_eq(awaiting.manifest_error, "No agent results manifest found", "the new claim should show that results are pending")
		t.assert_eq(awaiting.statuses["claim-old"].addressed, true, "a new-only export should preserve the prior claim result")
		t.assert_eq(awaiting.statuses["claim-new"], nil, "the newly exported claim should await its own result")

		local old_diff, old_diff_error = review_runs.claim_diff({
			workspace = root,
			session_name = "incremental-review",
			session_source = "local",
			claim_id = "claim-old",
		})
		t.assert_eq(old_diff_error, nil, "pending new results should not block an older claim diff")
		t.assert_eq(old_diff.run.run_id, first_run.run_id, "older claim diffs should use their originating baseline")

		vim.fn.writefile({ "return 3" }, path)
		publish_results(review_runs, second_run, {
			schema_version = 1,
			run_id = second_run.run_id,
			claims = {
				{
					claim_id = "claim-new",
					outcome = "changed",
					summary = "Applied the newly requested update.",
					changes = {
						{
							path = "feature.lua",
							type = "modified",
							description = "Updated the return value again.",
							regions = { { old_start = 1, old_end = 1, new_start = 1, new_end = 1 } },
						},
					},
				},
			},
		})

		local completed = review_runs.inspect({
			workspace = root,
			session_name = "incremental-review",
			session_source = "local",
		})
		t.assert_eq(completed.statuses["claim-old"].addressed, true, "the prior claim should remain addressed")
		t.assert_eq(completed.statuses["claim-new"].addressed, true, "the new claim should use the latest result")
		t.assert_eq(completed.statuses["claim-old"].run.run_id, first_run.run_id, "prior status should retain its run provenance")
		t.assert_eq(completed.statuses["claim-new"].run.run_id, second_run.run_id, "new status should retain its run provenance")

		vim.cmd.cd(original_cwd)
	end)

	it("keeps live-diff compatibility for runs created before completion helpers", function()
		local review_runs = require("doubt.review_runs")
		local original_cwd = vim.fn.getcwd()
		local root = vim.fn.tempname()
		local path = vim.fs.joinpath(root, "legacy.lua")
		vim.fn.mkdir(root, "p")
		vim.fn.writefile({ "return 1" }, path)
		vim.system({ "git", "init", "-q", root }, { text = true }):wait()
		vim.cmd.cd(root)

		local run = review_runs.create({
			workspace = root,
			session_name = "legacy-review",
			session_source = "local",
			files = {
				[path] = { claims = { { id = "legacy-claim", start_line = 0, end_line = 0 } } },
			},
		})
		local metadata_path = vim.fs.joinpath(root, ".doubt", "runs", run.run_id, "run.json")
		local metadata = vim.json.decode(table.concat(vim.fn.readfile(metadata_path), "\n"))
		metadata.pending_manifest_path = nil
		metadata.completion_path = nil
		metadata.completion_helper_path = nil
		vim.fn.writefile({ vim.json.encode(metadata) }, metadata_path)
		pcall(vim.uv.fs_unlink, run.absolute_completion_helper_path)

		vim.fn.writefile({ "return 2" }, path)
		vim.fn.writefile({ vim.json.encode({
			schema_version = 1,
			run_id = run.run_id,
			claims = {
				{
					claim_id = "legacy-claim",
					outcome = "changed",
					summary = "Confirmed the old value was incorrect and updated it.",
					changes = { { path = "legacy.lua", type = "modified", description = "Updated the value." } },
				},
			},
		}) }, run.absolute_manifest_path)

		local inspection = review_runs.inspect({
			workspace = root,
			session_name = "legacy-review",
			session_source = "local",
		})
		t.assert_eq(inspection.statuses["legacy-claim"].addressed, true, "legacy manifests should continue using their live worktree diff")
		t.assert_eq(inspection.post_response_change_count, 0, "legacy runs should not claim to have a sealed response tree")

		vim.cmd.cd(original_cwd)
	end)
end)
