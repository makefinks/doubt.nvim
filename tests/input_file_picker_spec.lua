local t = dofile("tests/helpers/bootstrap.lua")

local function open_file_picker(input, opts)
	local selected_items = nil
	local selected_opts = nil
	local select_callback = nil
	local original_select = vim.ui.select

	vim.ui.select = function(items, picker_opts, callback)
		selected_items = items
		selected_opts = picker_opts
		select_callback = callback
	end

	local note = input.ask_note(opts, function() end)
	vim.api.nvim_set_current_win(note.winid)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A@", true, false, true), "xt", false)
	vim.wait(1000, function()
		return selected_items ~= nil
	end)

	return {
		close = function()
			if select_callback then
				select_callback(nil)
			end
			note.cancel()
			vim.ui.select = original_select
		end,
		items = selected_items,
		opts = selected_opts,
	}
end

describe("input file picker", function()
	it("uses the Git project root and includes tracked and untracked files", function()
		package.loaded["doubt.input"] = nil
		local input = require("doubt.input")
		local root = vim.fn.tempname()
		local nested = vim.fs.joinpath(root, "nested")

		vim.fn.mkdir(nested, "p")
		vim.fn.writefile({ "ignored.lua" }, vim.fs.joinpath(root, ".gitignore"))
		vim.fn.writefile({ "tracked" }, vim.fs.joinpath(root, "tracked.lua"))
		vim.fn.writefile({ "untracked" }, vim.fs.joinpath(nested, "untracked.lua"))
		vim.fn.writefile({ "ignored" }, vim.fs.joinpath(root, "ignored.lua"))
		vim.fn.system({ "git", "-C", root, "init", "--quiet" })
		vim.fn.system({ "git", "-C", root, "add", "tracked.lua" })

		local picker = open_file_picker(input, { root = nested })

		t.assert_eq(picker.opts.kind, "file", "file references should identify the vim.ui.select item kind")
		t.assert_eq(
			picker.items,
			{ ".gitignore", "nested/untracked.lua", "tracked.lua" },
			"Git discovery should return repository-relative tracked and non-ignored untracked files"
		)

		picker.close()
		vim.fn.delete(root, "rf")
	end)

	it("does not cap native fallback discovery", function()
		package.loaded["doubt.input"] = nil
		local input = require("doubt.input")
		local original_find = vim.fs.find
		local original_root = vim.fs.root
		local find_opts = nil
		local discovered = {}

		for index = 1, 501 do
			table.insert(discovered, string.format("/workspace/file-%03d.lua", index))
		end

		vim.fs.root = function()
			return nil
		end
		vim.fs.find = function(_, opts)
			find_opts = opts
			return vim.deepcopy(discovered)
		end

		local picker = open_file_picker(input, { root = "/workspace" })

		t.assert_eq(#picker.items, 501, "fallback discovery should not silently omit files after 500 matches")
		t.assert_eq(find_opts.limit, math.huge, "fallback discovery should request every matching file")
		t.assert_eq(picker.items[1], "file-001.lua", "fallback paths should be relative to the workspace")

		picker.close()
		vim.fs.find = original_find
		vim.fs.root = original_root
	end)
end)
