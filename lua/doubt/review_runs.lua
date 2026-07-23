local claims = require("doubt.claims")

local M = {}

local SCHEMA_VERSION = 1
local RUNS_RELATIVE_DIR = vim.fs.joinpath(".doubt", "runs")
local MODULE_PATH = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local PLUGIN_ROOT = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(MODULE_PATH))))
local OUTCOMES = {
	answered = true,
	changed = true,
	disagreed = true,
	needs_input = true,
}

local function trim_output(value)
	return vim.trim(value or "")
end

local function run_command(command, opts)
	opts = opts or {}
	local result = vim.system(command, {
		cwd = opts.cwd,
		env = opts.env,
		text = true,
	}):wait()
	if result.code ~= 0 then
		return nil, trim_output(result.stderr) ~= "" and trim_output(result.stderr) or "command failed"
	end
	return trim_output(result.stdout)
end

local function git(root, args, opts)
	local command = { "git", "-C", root }
	vim.list_extend(command, args)
	opts = opts or {}
	opts.cwd = root
	return run_command(command, opts)
end

local function git_root(workspace)
	local root = git(workspace, { "rev-parse", "--show-toplevel" })
	if not root or root == "" then
		return nil
	end
	root = vim.fs.normalize(root)
	local requested = vim.fs.normalize(workspace)
	if vim.uv.fs_realpath(root) == vim.uv.fs_realpath(requested) then
		return requested
	end
	return root
end

local function path_inside(root, path)
	path = vim.fs.normalize(path or "")
	return path == root or vim.startswith(path, root .. "/")
end

local function relative_path(root, path)
	path = vim.fs.normalize(path or "")
	if not path_inside(root, path) or path == root then
		return nil
	end
	return path:sub(#root + 2)
end

local function prefer_file_root_alias(root, files)
	local real_root = vim.uv.fs_realpath(root)
	if not real_root then
		return root
	end
	for path in pairs(files or {}) do
		local normalized = vim.fs.normalize(path)
		local real_path = vim.uv.fs_realpath(normalized)
		if real_path and vim.startswith(real_path, real_root .. "/") then
			local relative = real_path:sub(#real_root + 2)
			local candidate = normalized:sub(1, #normalized - #relative - 1)
			if vim.uv.fs_realpath(candidate) == real_root then
				return candidate
			end
		end
	end
	return root
end

local function read_json(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or vim.tbl_isempty(lines) then
		return nil
	end
	local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decoded_ok or type(decoded) ~= "table" then
		return nil
	end
	return decoded
end

local function write_json(path, value)
	local ok, encoded = pcall(vim.json.encode, value)
	if not ok then
		return false
	end
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	return pcall(vim.fn.writefile, { encoded }, path)
end

local function write_json_atomic(path, value)
	local temporary_path = path .. ".tmp"
	if not write_json(temporary_path, value) then
		return false
	end
	local renamed = vim.uv.fs_rename(temporary_path, path)
	if not renamed then
		pcall(vim.uv.fs_unlink, temporary_path)
		return false
	end
	return true
end

local function copy_index(root, target)
	local index_path = git(root, { "rev-parse", "--git-path", "index" })
	if not index_path or index_path == "" then
		return
	end
	if not index_path:match("^/") then
		index_path = vim.fs.joinpath(root, index_path)
	end
	if vim.uv.fs_stat(index_path) then
		vim.uv.fs_copyfile(index_path, target)
	end
end

local function capture_tree(root)
	local temporary_index = vim.fn.tempname()
	copy_index(root, temporary_index)
	local env = { GIT_INDEX_FILE = temporary_index }
	local _, add_error = git(root, { "add", "-A", "--", "." }, { env = env })
	if add_error then
		pcall(vim.uv.fs_unlink, temporary_index)
		return nil, add_error
	end
	-- Review metadata must never appear in the source diff, even when users do not ignore it.
	local _, remove_error = git(root, {
		"rm",
		"-r",
		"-q",
		"--cached",
		"--ignore-unmatch",
		"--",
		RUNS_RELATIVE_DIR,
	}, { env = env })
	if remove_error then
		pcall(vim.uv.fs_unlink, temporary_index)
		return nil, remove_error
	end
	local tree, tree_error = git(root, { "write-tree" }, { env = env })
	pcall(vim.uv.fs_unlink, temporary_index)
	if not tree or tree == "" then
		return nil, tree_error
	end
	return tree
end

local function run_dir(root, run_id)
	return vim.fs.joinpath(root, RUNS_RELATIVE_DIR, run_id)
end

local function run_path(root, run_id)
	return vim.fs.joinpath(run_dir(root, run_id), "run.json")
end

local function results_path(root, run_id)
	return vim.fs.joinpath(run_dir(root, run_id), "results.json")
end

local function pending_results_path(root, run_id)
	return vim.fs.joinpath(run_dir(root, run_id), "results.pending.json")
end

local function completion_path(root, run_id)
	return vim.fs.joinpath(run_dir(root, run_id), "completion.json")
end

local function completion_helper_path(root, run_id)
	return vim.fs.joinpath(run_dir(root, run_id), "complete")
end

local function diff_helper_path(root, run_id)
	return vim.fs.joinpath(run_dir(root, run_id), "diff")
end

local function attach_run_paths(run, root)
	run.root = root
	run.absolute_manifest_path = results_path(root, run.run_id)
	run.absolute_pending_manifest_path = pending_results_path(root, run.run_id)
	run.absolute_completion_path = completion_path(root, run.run_id)
	run.absolute_completion_helper_path = completion_helper_path(root, run.run_id)
	if run.diff_helper_path then
		run.absolute_diff_helper_path = diff_helper_path(root, run.run_id)
	end
	return run
end

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function write_helper(path, lua_command)
	local lines = {
		"#!/bin/sh",
		"exec nvim --headless -u NONE -c " .. shell_quote("lua " .. lua_command) .. " +qa",
	}
	local ok = pcall(vim.fn.writefile, lines, path)
	if not ok or not vim.uv.fs_chmod(path, 493) then
		return false
	end
	return true
end

local function module_command(command)
	return string.format(
		'package.path = %q .. "/lua/?.lua;" .. %q .. "/lua/?/init.lua;" .. package.path; %s',
		PLUGIN_ROOT,
		PLUGIN_ROOT,
		command
	)
end

local function write_completion_helper(run)
	local command = string.format(
		'local ok, err = require("doubt.review_runs").complete({ workspace = %q, run_id = %q }); if not ok then io.stderr:write((err or "Unable to complete doubt review run") .. "\\n"); vim.cmd("cquit 1") end',
		run.root,
		run.run_id
	)
	return write_helper(run.absolute_completion_helper_path, module_command(command))
end

local function write_diff_helper(run)
	local command = string.format(
		'local output, err = require("doubt.review_runs").diff({ workspace = %q, run_id = %q }); if output == nil then io.stderr:write((err or "Unable to calculate doubt review diff") .. "\\n"); vim.cmd("cquit 1") elseif output ~= "" then io.write(output .. "\\n") end',
		run.root,
		run.run_id
	)
	return write_helper(run.absolute_diff_helper_path, module_command(command))
end

local function new_run_id()
	return string.format("run-%s-%06d", os.date("!%Y%m%dT%H%M%SZ"), vim.uv.hrtime() % 1000000)
end

local function valid_run_id(run_id)
	return type(run_id) == "string" and run_id:match("^run%-%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%d%d%d%d%d%d$") ~= nil
end

local function valid_tree_object(root, object)
	if type(object) ~= "string" or #object < 40 or #object > 64 or not object:match("^[0-9a-f]+$") then
		return false
	end
	return git(root, { "cat-file", "-e", object .. "^{tree}" }) ~= nil
end

local function normalize_exported_claims(root, files)
	local exported = {}
	for path, file_state in pairs(files or {}) do
		local relative = relative_path(root, path)
		if not relative then
			return nil
		end
		for _, claim in ipairs((file_state or {}).claims or {}) do
			table.insert(exported, {
				id = claim.id,
				file = relative,
				revision = claims.review_revision(claim),
				start_line = (claim.start_line or 0) + 1,
				end_line = (claim.end_line or claim.start_line or 0) + 1,
			})
		end
	end
	table.sort(exported, function(left, right)
		if left.file ~= right.file then
			return left.file < right.file
		end
		if left.start_line ~= right.start_line then
			return left.start_line < right.start_line
		end
		return left.id < right.id
	end)
	return exported
end

function M.create(opts)
	opts = opts or {}
	local root = git_root(opts.workspace or vim.fn.getcwd())
	if not root then
		return nil, "Review-run diffs require a Git repository"
	end
	root = prefer_file_root_alias(root, opts.files)
	local exported_claims = normalize_exported_claims(root, opts.files)
	if not exported_claims or vim.tbl_isempty(exported_claims) then
		return nil, "Exported claims must be inside the Git workspace"
	end
	local run_id = new_run_id()
	local baseline_tree, tree_error = capture_tree(root)
	if not baseline_tree then
		return nil, "Unable to capture review baseline: " .. (tree_error or "unknown error")
	end
	local baseline_ref = "refs/doubt/runs/" .. run_id
	local _, ref_error = git(root, { "update-ref", baseline_ref, baseline_tree })
	if ref_error then
		return nil, "Unable to retain review baseline: " .. ref_error
	end
	local manifest_relative_path = vim.fs.joinpath(RUNS_RELATIVE_DIR, run_id, "results.json")
	local pending_manifest_relative_path = vim.fs.joinpath(RUNS_RELATIVE_DIR, run_id, "results.pending.json")
	local completion_relative_path = vim.fs.joinpath(RUNS_RELATIVE_DIR, run_id, "completion.json")
	local completion_helper_relative_path = vim.fs.joinpath(RUNS_RELATIVE_DIR, run_id, "complete")
	local diff_helper_relative_path = vim.fs.joinpath(RUNS_RELATIVE_DIR, run_id, "diff")
	local run = {
		schema_version = SCHEMA_VERSION,
		run_id = run_id,
		session = opts.session_name,
		source = opts.session_source or "local",
		created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		baseline = {
			type = "git-tree",
			object = baseline_tree,
			ref = baseline_ref,
		},
		claims = exported_claims,
		manifest_path = manifest_relative_path,
		pending_manifest_path = pending_manifest_relative_path,
		completion_path = completion_relative_path,
		completion_helper_path = completion_helper_relative_path,
		diff_helper_path = diff_helper_relative_path,
	}
	if not write_json(run_path(root, run_id), run) then
		git(root, { "update-ref", "-d", baseline_ref })
		return nil, "Unable to write review-run metadata"
	end
	attach_run_paths(run, root)
	if not write_completion_helper(run) then
		pcall(vim.uv.fs_unlink, run_path(root, run_id))
		git(root, { "update-ref", "-d", baseline_ref })
		return nil, "Unable to write review-run completion helper"
	end
	if not write_diff_helper(run) then
		pcall(vim.uv.fs_unlink, run.absolute_completion_helper_path)
		pcall(vim.uv.fs_unlink, run_path(root, run_id))
		git(root, { "update-ref", "-d", baseline_ref })
		return nil, "Unable to write review-run diff helper"
	end
	return run
end

local function matching_runs(root, session_name, session_source)
	local directory = vim.fs.joinpath(root, RUNS_RELATIVE_DIR)
	if not vim.uv.fs_stat(directory) then
		return {}
	end
	local matching = {}
	for name, kind in vim.fs.dir(directory) do
		if kind == "directory" and valid_run_id(name) then
			local run = read_json(run_path(root, name))
			if run
				and run.schema_version == SCHEMA_VERSION
				and run.run_id == name
				and run.session == session_name
				and run.source == (session_source or "local")
				and type(run.baseline) == "table"
				and run.baseline.type == "git-tree"
				and valid_tree_object(root, run.baseline.object)
			then
				attach_run_paths(run, root)
				table.insert(matching, run)
			end
		end
	end
	table.sort(matching, function(left, right)
		return left.run_id > right.run_id
	end)
	return matching
end

function M.latest(opts)
	opts = opts or {}
	local root = git_root(opts.workspace or vim.fn.getcwd())
	if not root then
		return nil
	end
	return matching_runs(root, opts.session_name, opts.session_source)[1]
end

local function valid_relative_path(path)
	return type(path) == "string"
		and path ~= ""
		and not path:match("^/")
		and not path:match("^%.%./")
		and not path:match("/%.%./")
end

local function normalize_region(region)
	if type(region) ~= "table" then
		return nil
	end
	local normalized = {}
	for _, key in ipairs({ "old_start", "old_end", "new_start", "new_end" }) do
		if region[key] ~= nil then
			local value = tonumber(region[key])
			if not value or value < 0 or value ~= math.floor(value) then
				return nil
			end
			normalized[key] = value
		end
	end
	if vim.tbl_isempty(normalized) then
		return nil
	end
	if normalized.old_start and normalized.old_end and normalized.old_end < normalized.old_start then
		return nil
	end
	if normalized.new_start and normalized.new_end and normalized.new_end < normalized.new_start then
		return nil
	end
	return normalized
end

local function load_manifest(run, path)
	local manifest = read_json(path or run.absolute_manifest_path)
	if not manifest then
		return nil, "No agent results manifest found"
	end
	if manifest.schema_version ~= SCHEMA_VERSION
		or manifest.run_id ~= run.run_id
		or type(manifest.claims) ~= "table"
		or not vim.islist(manifest.claims)
	then
		return nil, "Agent results manifest does not match the active review run"
	end

	local known_claims = {}
	for _, claim in ipairs(run.claims or {}) do
		known_claims[claim.id] = true
	end
	local normalized = { claims = {} }
	for _, result in ipairs(manifest.claims) do
		if type(result) ~= "table"
			or not known_claims[result.claim_id]
			or type(result.changes) ~= "table"
			or not vim.islist(result.changes)
		then
			return nil, "Agent results manifest contains an invalid claim result"
		end
		if normalized.claims[result.claim_id] then
			return nil, "Agent results manifest contains duplicate claim results"
		end
		local outcome = type(result.outcome) == "string" and result.outcome or "changed"
		if not OUTCOMES[outcome] then
			return nil, "Agent results manifest contains an invalid outcome"
		end
		if type(result.summary) ~= "string" or vim.trim(result.summary) == "" then
			return nil, "Agent results manifest contains a claim result without a summary"
		end
		local claim_result = {
			claim_id = result.claim_id,
			outcome = outcome,
			summary = vim.trim(result.summary),
			changes = {},
		}
		for _, change in ipairs(result.changes) do
			if type(change) ~= "table" or not valid_relative_path(change.path) then
				return nil, "Agent results manifest contains an invalid changed path"
			end
			if change.regions ~= nil and (type(change.regions) ~= "table" or not vim.islist(change.regions)) then
				return nil, "Agent results manifest contains an invalid change"
			end
			local normalized_change = {
				path = vim.fs.normalize(change.path),
				regions = {},
			}
			for _, region in ipairs(change.regions or {}) do
				local normalized_region = normalize_region(region)
				if not normalized_region then
					return nil, "Agent results manifest contains an invalid changed region"
				end
				table.insert(normalized_change.regions, normalized_region)
			end
			table.insert(claim_result.changes, normalized_change)
		end
		if outcome == "changed" and vim.tbl_isempty(claim_result.changes) then
			return nil, "Agent results manifest contains a changed outcome without code changes"
		end
		normalized.claims[result.claim_id] = claim_result
	end
	for claim_id in pairs(known_claims) do
		if not normalized.claims[claim_id] then
			return nil, "Agent results manifest is missing a result for an exported claim"
		end
	end
	return normalized
end

local function load_run_by_id(root, run_id)
	if not valid_run_id(run_id) then
		return nil
	end
	local run = read_json(run_path(root, run_id))
	if not run
		or run.schema_version ~= SCHEMA_VERSION
		or run.run_id ~= run_id
		or type(run.baseline) ~= "table"
		or run.baseline.type ~= "git-tree"
		or not valid_tree_object(root, run.baseline.object)
	then
		return nil
	end
	return attach_run_paths(run, root)
end

local function manifest_digest(path)
	local ok, lines = pcall(vim.fn.readfile, path, "b")
	if not ok then
		return nil
	end
	return vim.fn.sha256(table.concat(lines, "\n"))
end

local function completion_ref(run_id)
	return "refs/doubt/results/" .. run_id
end

local function load_completion(run)
	local completion = read_json(run.absolute_completion_path)
	local expected_ref = completion_ref(run.run_id)
	if not completion
		or completion.schema_version ~= SCHEMA_VERSION
		or completion.run_id ~= run.run_id
		or type(completion.result) ~= "table"
		or completion.result.type ~= "git-tree"
		or completion.result.ref ~= expected_ref
		or not valid_tree_object(run.root, completion.result.object)
		or type(completion.manifest_sha256) ~= "string"
	then
		return nil
	end
	local retained_object = git(run.root, { "rev-parse", expected_ref .. "^{tree}" })
	if retained_object ~= completion.result.object then
		return nil
	end
	return completion
end

function M.complete(opts)
	opts = opts or {}
	local root = git_root(opts.workspace or vim.fn.getcwd())
	if not root then
		return nil, "Review-run completion requires a Git repository"
	end
	local run = load_run_by_id(root, opts.run_id)
	if not run or not run.completion_helper_path then
		return nil, "Unable to find a completable doubt review run"
	end
	if vim.uv.fs_stat(run.absolute_manifest_path) then
		return nil, "This doubt review run is already completed"
	end
	local manifest, manifest_error = load_manifest(run, run.absolute_pending_manifest_path)
	if not manifest then
		return nil, manifest_error:gsub("agent results", "pending agent results")
	end
	local digest = manifest_digest(run.absolute_pending_manifest_path)
	if not digest then
		return nil, "Unable to read pending agent results manifest"
	end

	local completion = load_completion(run)
	if completion then
		if completion.manifest_sha256 ~= digest then
			return nil, "Pending agent results changed after the completion tree was sealed"
		end
	else
		local result_tree, tree_error = capture_tree(root)
		if not result_tree then
			return nil, "Unable to capture review completion tree: " .. (tree_error or "unknown error")
		end
		local result_ref = completion_ref(run.run_id)
		local _, ref_error = git(root, { "update-ref", result_ref, result_tree })
		if ref_error then
			return nil, "Unable to retain review completion tree: " .. ref_error
		end
		completion = {
			schema_version = SCHEMA_VERSION,
			run_id = run.run_id,
			completed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			manifest_sha256 = digest,
			result = {
				type = "git-tree",
				object = result_tree,
				ref = result_ref,
			},
		}
		if not write_json_atomic(run.absolute_completion_path, completion) then
			git(root, { "update-ref", "-d", result_ref })
			return nil, "Unable to write review completion metadata"
		end
	end

	if not vim.uv.fs_rename(run.absolute_pending_manifest_path, run.absolute_manifest_path) then
		return nil, "Unable to publish agent results manifest"
	end
	return completion
end

local function parse_range(start_text, count_text)
	local start = tonumber(start_text) or 0
	local count = count_text == "" and 1 or tonumber(count_text) or 0
	return start, count
end

local function parse_diff(diff)
	local files = {}
	local current_file = nil
	local current_hunk = nil
	for _, line in ipairs(vim.split(diff or "", "\n", { plain = true })) do
		if vim.startswith(line, "diff --git ") then
			local old_path, new_path = line:match("^diff %-%-git a/(.-) b/(.+)$")
			current_file = {
				header = { line },
				hunks = {},
				old_path = old_path,
				new_path = new_path,
			}
			current_hunk = nil
			table.insert(files, current_file)
		elseif current_file then
			local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
			if old_start then
				local parsed_old_start, parsed_old_count = parse_range(old_start, old_count)
				local parsed_new_start, parsed_new_count = parse_range(new_start, new_count)
				current_hunk = {
					lines = { line },
					old_start = parsed_old_start,
					old_count = parsed_old_count,
					new_start = parsed_new_start,
					new_count = parsed_new_count,
				}
				table.insert(current_file.hunks, current_hunk)
			elseif current_hunk then
				table.insert(current_hunk.lines, line)
			else
				table.insert(current_file.header, line)
				local old_path = line:match("^%-%-%- a/(.+)$")
				local new_path = line:match("^%+%+%+ b/(.+)$")
				local renamed_from = line:match("^rename from (.+)$")
				local renamed_to = line:match("^rename to (.+)$")
				if old_path then
					current_file.old_path = old_path
				elseif line == "--- /dev/null" then
					current_file.created = true
				elseif new_path then
					current_file.new_path = new_path
				elseif line == "+++ /dev/null" then
					current_file.deleted = true
				elseif renamed_from then
					current_file.old_path = renamed_from
				elseif renamed_to then
					current_file.new_path = renamed_to
				end
			end
		end
	end
	for _, file in ipairs(files) do
		file.path = file.new_path or file.old_path
	end
	return files
end

local function ranges_intersect(start_a, count_a, start_b, end_b)
	local end_a = count_a == 0 and start_a or (start_a + count_a - 1)
	return start_a <= end_b and start_b <= end_a
end

local function hunk_matches_change(hunk, change)
	if vim.tbl_isempty(change.regions) then
		return true
	end
	for _, region in ipairs(change.regions) do
		local old_match = region.old_start
			and ranges_intersect(hunk.old_start, hunk.old_count, region.old_start, region.old_end or region.old_start)
		local new_match = region.new_start
			and ranges_intersect(hunk.new_start, hunk.new_count, region.new_start, region.new_end or region.new_start)
		if old_match or new_match then
			return true
		end
	end
	return false
end

local function tree_diff_text(root, from_tree, to_tree)
	return git(root, {
		"diff",
		"--no-ext-diff",
		"--find-renames",
		"--unified=0",
		from_tree,
		to_tree,
		"--",
	})
end

local function tree_diff(root, from_tree, to_tree)
	local diff, diff_error = tree_diff_text(root, from_tree, to_tree)
	if diff == nil then
		return nil, diff_error
	end
	return parse_diff(diff)
end

function M.diff(opts)
	opts = opts or {}
	local root = git_root(opts.workspace or vim.fn.getcwd())
	if not root then
		return nil, "Review-run diffs require a Git repository"
	end
	local run = load_run_by_id(root, opts.run_id)
	if not run or not run.diff_helper_path then
		return nil, "Unable to find a diffable doubt review run"
	end
	local current_tree, tree_error = capture_tree(root)
	if not current_tree then
		return nil, "Unable to capture current review tree: " .. (tree_error or "unknown error")
	end
	local diff, diff_error = tree_diff_text(root, run.baseline.object, current_tree)
	if diff == nil then
		return nil, "Unable to calculate review-run diff: " .. (diff_error or "unknown error")
	end
	return diff
end

local function review_diff(run)
	if run.completion_helper_path then
		local completion = load_completion(run)
		if not completion then
			return nil, "Review results have not been sealed by the completion helper"
		end
		if manifest_digest(run.absolute_manifest_path) ~= completion.manifest_sha256 then
			return nil, "Published agent results do not match the sealed completion"
		end
		run.completion = completion
		return tree_diff(run.root, run.baseline.object, completion.result.object)
	end

	local current_tree, tree_error = capture_tree(run.root)
	if not current_tree then
		return nil, tree_error
	end
	return tree_diff(run.root, run.baseline.object, current_tree)
end

local function count_diff_units(files)
	local count = 0
	for _, file in ipairs(files or {}) do
		count = count + (vim.tbl_isempty(file.hunks) and 1 or #file.hunks)
	end
	return count
end

local function inspect_run(run, opts)
	opts = opts or {}
	local manifest, manifest_error = load_manifest(run)
	if not manifest then
		return {
			run = run,
			manifest_error = manifest_error,
			statuses = {},
			unattributed_count = 0,
		}
	end
	local diff_files, diff_error = review_diff(run)
	if not diff_files then
		if run.completion_helper_path then
			return {
				run = run,
				manifest_error = diff_error,
				statuses = {},
				unattributed_count = 0,
			}
		end
		return nil, "Unable to calculate review-run diff: " .. (diff_error or "unknown error")
	end

	local attributed = {}
	local statuses = {}
	local exported_claims = {}
	for _, claim in ipairs(run.claims or {}) do
		exported_claims[claim.id] = claim
	end
	for claim_id, result in pairs(manifest.claims) do
		local matches = {}
		for _, change in ipairs(result.changes) do
			for file_index, file in ipairs(diff_files) do
				if file.path == change.path or file.old_path == change.path or file.new_path == change.path then
					if vim.tbl_isempty(file.hunks) then
						local key = string.format("%d:0", file_index)
						attributed[key] = true
						matches[key] = { file = file }
					end
					for hunk_index, hunk in ipairs(file.hunks) do
						if hunk_matches_change(hunk, change) then
							local key = string.format("%d:%d", file_index, hunk_index)
							attributed[key] = true
							matches[key] = { file = file, hunk = hunk }
						end
					end
				end
			end
		end
		local ordered_matches = vim.tbl_values(matches)
		table.sort(ordered_matches, function(left, right)
			if left.file.path ~= right.file.path then
				return left.file.path < right.file.path
			end
			return (left.hunk and left.hunk.new_start or 0) < (right.hunk and right.hunk.new_start or 0)
		end)
		local verified_hunk_count = #ordered_matches
		statuses[claim_id] = {
			addressed = result.outcome == "answered"
				or result.outcome == "disagreed"
				or (result.outcome == "changed" and verified_hunk_count > 0),
			outcome = result.outcome,
			summary = result.summary,
			reported_change_count = #result.changes,
			verified_hunk_count = verified_hunk_count,
			matches = ordered_matches,
			claim_revision = (exported_claims[claim_id] or {}).revision,
			run = run,
		}
	end

	local unattributed_count = 0
	for file_index, file in ipairs(diff_files) do
		if vim.tbl_isempty(file.hunks) and not attributed[string.format("%d:0", file_index)] then
			unattributed_count = unattributed_count + 1
		end
		for hunk_index in ipairs(file.hunks) do
			if not attributed[string.format("%d:%d", file_index, hunk_index)] then
				unattributed_count = unattributed_count + 1
			end
		end
	end
	for _, status in pairs(statuses) do
		status.unattributed_count = unattributed_count
	end
	local post_response_change_count = 0
	if opts.include_drift and run.completion then
		local current_tree, tree_error = capture_tree(run.root)
		if not current_tree then
			return nil, "Unable to calculate post-response changes: " .. (tree_error or "unknown error")
		end
		local drift_files, drift_error = tree_diff(run.root, run.completion.result.object, current_tree)
		if not drift_files then
			return nil, "Unable to calculate post-response changes: " .. (drift_error or "unknown error")
		end
		post_response_change_count = count_diff_units(drift_files)
	end
	return {
		run = run,
		statuses = statuses,
		unattributed_count = unattributed_count,
		post_response_change_count = post_response_change_count,
	}
end

local function inspect(opts)
	opts = opts or {}
	local root = git_root(opts.workspace or vim.fn.getcwd())
	if not root then
		return nil, "No review run found for the active session"
	end
	local runs = matching_runs(root, opts.session_name, opts.session_source)
	if vim.tbl_isempty(runs) then
		return nil, "No review run found for the active session"
	end

	local latest_inspection, latest_error = inspect_run(runs[1], { include_drift = true })
	if not latest_inspection then
		return nil, latest_error
	end
	local statuses = {}
	local seen_claims = {}
	for index, run in ipairs(runs) do
		local needs_inspection = index == 1
		if not needs_inspection then
			for _, claim in ipairs(run.claims or {}) do
				if not seen_claims[claim.id] then
					needs_inspection = true
					break
				end
			end
		end

		local run_inspection = index == 1 and latest_inspection or nil
		if needs_inspection and not run_inspection then
			local run_error
			run_inspection, run_error = inspect_run(run)
			if not run_inspection then
				return nil, run_error
			end
		end
		for _, claim in ipairs(run.claims or {}) do
			if not seen_claims[claim.id] then
				if run_inspection and run_inspection.statuses[claim.id] then
					statuses[claim.id] = run_inspection.statuses[claim.id]
				end
				seen_claims[claim.id] = true
			end
		end
	end
	latest_inspection.statuses = statuses
	return latest_inspection
end

function M.inspect(opts)
	return inspect(opts)
end

local function render_claim_patch(run, claim_id, status)
	local lines = {
		string.format("# Review run: %s", run.run_id),
		string.format("# Claim: %s", claim_id),
	}
	if status.summary ~= "" then
		table.insert(lines, "# Agent: " .. status.summary)
	end
	table.insert(lines, "")

	local current_file = nil
	for _, match in ipairs(status.matches) do
		if current_file ~= match.file then
			current_file = match.file
			vim.list_extend(lines, current_file.header)
		end
		if match.hunk then
			vim.list_extend(lines, match.hunk.lines)
		end
	end
	return lines
end

local function tree_file_lines(root, tree, path)
	local result = vim.system({ "git", "-C", root, "show", tree .. ":" .. path }, { text = true }):wait()
	if result.code ~= 0 then
		return nil, vim.trim(result.stderr or "")
	end
	if result.stdout == "" then
		return {}
	end
	local lines = vim.split(result.stdout, "\n", { plain = true, trimempty = false })
	if result.stdout:sub(-1) == "\n" then
		table.remove(lines)
	end
	return lines
end

local function hunk_result_lines(hunk)
	local lines = {}
	for index, line in ipairs(hunk.lines or {}) do
		if index > 1 then
			local marker = line:sub(1, 1)
			if marker == " " or marker == "+" then
				table.insert(lines, line:sub(2))
			end
		end
	end
	return lines
end

local function apply_hunks(lines, hunks)
	local result = vim.deepcopy(lines)
	table.sort(hunks, function(left, right)
		return left.old_start > right.old_start
	end)
	for _, hunk in ipairs(hunks) do
		local start = hunk.old_count == 0 and hunk.old_start + 1 or hunk.old_start
		for _ = 1, hunk.old_count do
			table.remove(result, start)
		end
		local replacement = hunk_result_lines(hunk)
		for index = #replacement, 1, -1 do
			table.insert(result, start, replacement[index])
		end
	end
	return result
end

local function build_claim_file_pairs(run, matches)
	local by_path = {}
	local has_file_level_change = false
	for _, match in ipairs(matches or {}) do
		if not match.hunk then
			has_file_level_change = true
		else
			local path = match.file.new_path or match.file.old_path or match.file.path
			if type(path) == "string" and path ~= "" then
				local pair = by_path[path]
				if not pair then
					pair = {
						path = path,
						source_path = match.file.old_path or match.file.path,
						created = match.file.created,
						hunks = {},
					}
					by_path[path] = pair
				end
				table.insert(pair.hunks, match.hunk)
			end
		end
	end

	local pairs = vim.tbl_values(by_path)
	table.sort(pairs, function(left, right)
		return left.path < right.path
	end)
	for _, pair in ipairs(pairs) do
		local before, err = tree_file_lines(run.root, run.baseline.object, pair.source_path)
		if not before and pair.created then
			before = {}
		elseif not before then
			return nil, has_file_level_change, err
		end
		pair.before = before
		pair.after = apply_hunks(before, pair.hunks)
		pair.source_path = nil
		pair.created = nil
		pair.hunks = nil
	end
	return pairs, has_file_level_change
end

function M.claim_diff(opts)
	opts = opts or {}
	local result, err = inspect(opts)
	if not result then
		return nil, err
	end
	local status = result.statuses[opts.claim_id]
	if not status then
		if result.manifest_error then
			return nil, result.manifest_error
		end
		return nil, "The agent manifest has no result for this claim"
	end
	if status.verified_hunk_count == 0 then
		return nil, status.reported_change_count > 0
			and "No actual diff hunks match the agent manifest for this claim"
			or "The agent reported no code changes for this claim"
	end
	local run = status.run or result.run
	local files, has_file_level_change, files_error = build_claim_file_pairs(run, status.matches)
	if not files then
		return nil, "Unable to prepare full claim diff context: " .. (files_error or "unknown error")
	end
	return {
		files = files,
		has_file_level_change = has_file_level_change,
		lines = render_claim_patch(run, opts.claim_id, status),
		run = run,
		status = status,
		unattributed_count = status.unattributed_count or result.unattributed_count,
	}
end

function M.protocol_text(run)
	if not run then
		return ""
	end
	return table.concat({
		"## Doubt review run",
		"",
		string.format("- Run ID: `%s`", run.run_id),
		string.format("- Repository root: `%s`", run.root),
		"",
		"### Required workflow",
		"",
		"1. Address every exported claim; do not skip any.",
		"2. Finish all code changes before deriving regions or writing the manifest.",
		"3. Run the diff helper below and derive regions from its output.",
		string.format("4. Write the pending results manifest to `%s`.", run.absolute_pending_manifest_path),
		"5. Run this completion helper as the final step:",
		"",
		"```sh",
		shell_quote(run.absolute_completion_helper_path),
		"```",
		"",
		"The helper validates every claim, seals the completion tree, and publishes `results.json`. Do not write `results.json` directly or modify code after running the helper.",
		"",
		"### Manifest",
		"",
		"- Use `schema_version: 1`, this run ID, and a `claims` array.",
		"- Each claim requires `claim_id`, `outcome`, a non-empty `summary`, and `changes`.",
		"- Write `summary` as a concise, direct response with only the conclusion and necessary reasoning. Do not narrate investigation steps.",
		"- Each change requires a repo-relative `path`; `regions` is optional. Use an empty `changes` array when no code changed.",
		"- Associate every intentional changed region with one or more claim IDs.",
		"- Keep the final conversational response concise; do not repeat these claim-by-claim results.",
		"",
		"### Regions",
		"",
		"Derive one-based old/new ranges from the authoritative zero-context diff produced by:",
		"",
		"```sh",
		shell_quote(run.absolute_diff_helper_path),
		"```",
		"",
		"Copy ranges from each `@@ -old_start,old_count +new_start,new_count @@` header. Ends are inclusive: `end = start + count - 1`.",
		"When a side has count `0`, omit that side's range: omit old coordinates for an insertion and new coordinates for a deletion.",
		"",
		"### Outcomes",
		"",
		"- `changed`: agreed and modified code; summarize the reasoning and change.",
		"- `answered`: responded without code changes; directly answer the feedback.",
		"- `disagreed`: explain why the claim is incorrect.",
		"- `needs_input`: state what information is required and why.",
		"",
		"### Example manifest",
		"",
		"```json",
		"{",
		'  "schema_version": 1,',
		string.format('  "run_id": "%s",', run.run_id),
		'  "claims": [',
		"    {",
		'      "claim_id": "CLAIM_ID",',
		'      "outcome": "changed",',
		'      "summary": "Confirmed the issue and added boundary validation.",',
		'      "changes": [',
		"        {",
		'          "path": "lua/example.lua",',
		'          "regions": [',
		'            { "old_start": 10, "old_end": 12, "new_start": 10, "new_end": 16 }',
		"          ]",
		"        }",
		"      ]",
		"    }",
		"  ]",
		"}",
		"```",
	}, "\n")
end

return M
