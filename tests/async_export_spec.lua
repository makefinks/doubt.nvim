local t = dofile("tests/helpers/bootstrap.lua")

describe("asynchronous export", function()
	it("keeps the command responsive and rejects snapshots after writes", function()
		local doubt = require("doubt")
		local claims = require("doubt.claims")
		local review_runs = require("doubt.review_runs")
		local state = require("doubt.state")
		local original_cwd = vim.fn.getcwd()
		local original_capture_tree_async = review_runs.capture_tree_async
		local original_notify = vim.notify
		local root = vim.fn.tempname()
		local path = vim.fs.joinpath(root, "feature.lua")
		local notifications = {}
		local capture_callback = nil
		local capture_count = 0

		vim.fn.mkdir(root, "p")
		vim.fn.writefile({ "return risky_value()" }, path)
		vim.system({ "git", "init", "-q", root }, { text = true }):wait()
		vim.cmd.cd(root)
		vim.fn.setreg("z", "")
		doubt.setup({
			export = { register = "z" },
			keymaps = false,
			state_path = vim.fs.joinpath(vim.fn.tempname(), "state.json"),
		})
		state.set_active_session("async-review")
		local content = table.concat(vim.fn.readfile(path), "\n")
		local file_state = state.ensure_file_entry(path)
		table.insert(file_state.claims, {
			id = "async-claim",
			kind = "concern",
			start_line = 0,
			start_col = 0,
			end_line = 0,
			end_col = #content,
			note = "Handle this failure",
			freshness = "fresh",
			anchor = claims.build_content_anchor(content, 0, 0, 0, #content),
		})

		review_runs.capture_tree_async = function(_, callback)
			capture_count = capture_count + 1
			capture_callback = callback
		end
		vim.notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end

		doubt.copy_export_async()
		t.assert_eq(type(capture_callback), "function", "the initial export should start its snapshot asynchronously")
		t.assert_eq(vim.fn.getreg("z"), "", "the register should remain unchanged while the snapshot is running")

		doubt.copy_export_async()
		t.assert_eq(capture_count, 1, "a second export should not start while the first snapshot is running")
		t.assert_eq(notifications[#notifications].message, "A doubt export is already being prepared", "concurrent exports should explain why they were ignored")

		vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })
		capture_callback("unused-tree")
		t.assert_eq(vim.fn.getreg("z"), "", "a snapshot spanning a buffer write should be discarded")
		t.assert_eq(notifications[#notifications].message, "Files changed while preparing the doubt export; run :DoubtExport again", "discarded snapshots should request a fresh export")

		doubt.copy_export_async()
		local tree_result = vim.system({ "git", "-C", root, "mktree" }, { stdin = "", text = true }):wait()
		capture_callback(vim.trim(tree_result.stdout))
		local exported = vim.fn.getreg("z")
		t.assert_match(exported, "## Doubt review run", "a completed background snapshot should finish the handoff")
		t.assert_match(notifications[#notifications].message, "Copied doubt export to z", "completion should report the copied export")

		review_runs.capture_tree_async = original_capture_tree_async
		vim.notify = original_notify
		vim.cmd.cd(original_cwd)
	end)

	it("completes the real Git snapshot through the interactive command", function()
		local doubt = require("doubt")
		local claims = require("doubt.claims")
		local state = require("doubt.state")
		local original_cwd = vim.fn.getcwd()
		local root = vim.fn.tempname()
		local path = vim.fs.joinpath(root, "actual.lua")

		vim.fn.mkdir(root, "p")
		vim.fn.writefile({ "return actual_value()" }, path)
		vim.system({ "git", "init", "-q", root }, { text = true }):wait()
		vim.cmd.cd(root)
		vim.fn.setreg("y", "")
		doubt.setup({
			export = { register = "y" },
			keymaps = false,
			state_path = vim.fs.joinpath(vim.fn.tempname(), "state.json"),
		})
		state.set_active_session("actual-async-review")
		local content = table.concat(vim.fn.readfile(path), "\n")
		local file_state = state.ensure_file_entry(path)
		table.insert(file_state.claims, {
			id = "actual-async-claim",
			kind = "concern",
			start_line = 0,
			start_col = 0,
			end_line = 0,
			end_col = #content,
			note = "Handle the actual failure",
			freshness = "fresh",
			anchor = claims.build_content_anchor(content, 0, 0, 0, #content),
		})

		vim.cmd("DoubtExport")
		t.assert_eq(vim.fn.getreg("y"), "", "the interactive command should return before the Git snapshot completes")
		local completed = vim.wait(5000, function()
			return vim.fn.getreg("y"):find("## Doubt review run", 1, true) ~= nil
		end)
		t.assert_eq(completed, true, "the real asynchronous Git snapshot should finish the export")

		vim.cmd.cd(original_cwd)
	end)
	it("does not block on asynchronous Git root discovery", function()
		local review_runs = require("doubt.review_runs")
		local original_system = vim.system
		local invoked = false
		local callback_called = false

		vim.system = function(_, _, callback)
			invoked = true
			t.assert_eq(type(callback), "function", "async snapshot setup should pass a process callback")
			return {}
		end

		review_runs.capture_tree_async({ workspace = vim.fn.getcwd() }, function()
			callback_called = true
		end)
		vim.system = original_system

		t.assert_eq(invoked, true, "async snapshot should start Git root discovery")
		t.assert_eq(callback_called, false, "async snapshot should wait for Git instead of completing inline")
	end)

	it("reports Git processes terminated by a signal", function()
		local review_runs = require("doubt.review_runs")
		local original_system = vim.system
		local callback_called = false
		local captured_tree = nil
		local captured_error = nil

		vim.system = function(_, _, callback)
			vim.schedule(function()
				callback({ code = 0, signal = 15, stdout = "", stderr = "" })
			end)
			return {}
		end

		review_runs.capture_tree_async({ workspace = vim.fn.getcwd() }, function(tree, err)
			callback_called = true
			captured_tree = tree
			captured_error = err
		end)
		local completed = vim.wait(1000, function()
			return callback_called
		end)
		vim.system = original_system

		t.assert_eq(completed, true, "signal termination should complete the async error callback")
		t.assert_eq(captured_tree, nil, "signal termination should not produce a tree")
		t.assert_eq(captured_error, "command terminated by signal 15", "signal termination should be reported explicitly")
	end)
end)
