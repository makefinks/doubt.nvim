local t = dofile("tests/helpers/bootstrap.lua")

describe("inline claim editor", function()
	it("renders and resizes an unsaved first claim", function()
		local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
		local temp_file = vim.fs.joinpath(vim.fn.tempname(), "inline-editor.lua")
		vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
		vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
		vim.fn.writefile({ "local value = 1", "return value" }, temp_file)

		local doubt = require("doubt")
		local inline_editor = require("doubt.inline_editor")
		local state = require("doubt.state")
		doubt.setup({
			keymaps = false,
			state_path = temp_state,
			input = { inline_max_height = 2 },
			inline_notes = { max_width = 20 },
		})
		vim.cmd.edit(temp_file)
		doubt.start_session({ name = "inline-editor", quiet = true })

		local source_bufnr = vim.api.nvim_get_current_buf()
		vim.cmd.vsplit()
		local path = vim.fs.normalize(vim.api.nvim_buf_get_name(source_bufnr))
		doubt.claim_range("question")
		local editor = inline_editor.status()
		t.assert_eq(editor.active, true, "claim creation should open an inline editor")
		t.assert_eq(state.current_files()[path], nil, "a draft should not create persisted file state")
		t.assert_eq(vim.api.nvim_win_get_config(editor.winid).row >= 0, true, "a first-line editor should remain on screen")
		t.assert_eq(editor.body_width, 12, "an empty inline editor should start at its compact minimum width")
		local save_mapping = vim.api.nvim_buf_call(editor.bufnr, function()
			return vim.fn.maparg("<S-CR>", "i", false, true)
		end)
		t.assert_eq(save_mapping.desc, "Save doubt claim note", "shift-enter should save from insert mode")
		local original_source_winid = editor.source_winid
		vim.api.nvim_win_close(original_source_winid, true)
		vim.wait(50, function()
			return inline_editor.status().source_winid ~= original_source_winid
		end)
		editor = inline_editor.status()
		t.assert_eq(editor.active, true, "closing a source split should keep editing in another window showing the buffer")
		t.assert_eq(vim.api.nvim_win_is_valid(editor.source_winid), true, "reattached inline editor should have a valid source window")

		local ns = vim.api.nvim_get_namespaces()["doubt.nvim"]
		local marks = vim.api.nvim_buf_get_extmarks(source_bufnr, ns, 0, -1, { details = true })
		local shell = nil
		for _, mark in ipairs(marks) do
			if (mark[4] or {}).virt_lines then
				shell = mark[4]
				break
			end
		end
		t.assert_eq(shell ~= nil, true, "an unsaved first claim should render its editing shell")
		t.assert_eq(#shell.virt_lines, 3, "a one-row editor should render a top, body, and bottom row")
		t.assert_eq(shell.virt_lines[1][#shell.virt_lines[1]][1], " EDITING ", "active claim should show an editing badge")
		t.assert_eq(shell.virt_lines[1][#shell.virt_lines[1]][2], "DoubtInlineEditingBadge", "editing badge should use its active style")
		t.assert_eq(shell.virt_lines[2][3][1], " ", "editing text should retain the normal gap after the claim label")
		t.assert_eq(shell.virt_lines[2][#shell.virt_lines[2]][2], "DoubtInlineEditingBar", "active claim should have a visible right border")
		t.assert_eq(shell.virt_lines[3][2][2], "DoubtInlineEditingBar", "active claim should have a visible bottom border")

		vim.api.nvim_win_set_cursor(editor.winid, { 1, 0 })
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A<CR>", true, false, true), "xt", false)
		vim.wait(50, function()
			return vim.api.nvim_buf_line_count(editor.bufnr) == 2
		end)
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = editor.bufnr })
		vim.wait(50)
		local top_line = vim.api.nvim_win_call(editor.winid, function()
			return vim.fn.line("w0")
		end)
		t.assert_eq(vim.api.nvim_win_get_height(editor.winid), 2, "entering a newline should resize the editor window")
		t.assert_eq(top_line, 1, "entering a newline should keep the existing note visible")

		local growing_text = string.rep("x", 14)
		vim.api.nvim_buf_set_lines(editor.bufnr, 0, -1, false, { growing_text })
		vim.api.nvim_win_set_cursor(editor.winid, { 1, #growing_text })
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = editor.bufnr })
		editor = inline_editor.status()
		t.assert_eq(editor.body_width, 15, "inline editor should grow with its text and insert cursor")
		t.assert_eq(vim.api.nvim_win_get_width(editor.winid), 15, "floating editor window should follow the growing content width")

		local edge_text = string.rep("x", 20)
		vim.api.nvim_buf_set_lines(editor.bufnr, 0, -1, false, { edge_text })
		vim.api.nvim_win_set_cursor(editor.winid, { 1, #edge_text })
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = editor.bufnr })
		editor = inline_editor.status()
		t.assert_eq(editor.rows, 2, "text at the right edge should reserve a wrapped row for the insert cursor")
		t.assert_eq(vim.api.nvim_win_get_height(editor.winid), 2, "right-edge typing should keep the text visible")

		vim.api.nvim_buf_set_lines(editor.bufnr, 0, -1, false, { "one", "two", "three" })
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = editor.bufnr })
		editor = inline_editor.status()
		t.assert_eq(editor.rows, 2, "inline editor height should stop at the configured maximum")
		marks = vim.api.nvim_buf_get_extmarks(source_bufnr, ns, 0, -1, { details = true })
		for _, mark in ipairs(marks) do
			if (mark[4] or {}).virt_lines then
				shell = mark[4]
				break
			end
		end
		t.assert_eq(#shell.virt_lines, 4, "the editing shell should track the visible editor height")

		inline_editor.cancel()
		t.assert_eq(state.current_files()[path], nil, "cancelling a first draft should leave no persisted claim")

		doubt.setup({
			keymaps = false,
			state_path = temp_state,
			inline_notes = { max_width = 0 },
		})
		doubt.claim_range("question")
		editor = inline_editor.status()
		t.assert_eq(editor.body_width > 1, true, "unlimited note width should use the available source window")

		local original_confirm = vim.fn.confirm
		vim.fn.confirm = function()
			return 1
		end
		doubt.delete_session({ name = "inline-editor" })
		vim.fn.confirm = original_confirm
		t.assert_eq(inline_editor.status().active, false, "deleting the active session should close its draft editor")
	end)
end)
