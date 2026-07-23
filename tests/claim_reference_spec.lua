local t = dofile("tests/helpers/bootstrap.lua")

describe("claim references", function()
	it("migrates legacy IDs and their inline tokens", function()
		local claims = require("doubt.claims")
		local files = {
			["legacy.lua"] = {
				claims = {
					{ id = "3.118e+15", kind = "question", note = "Original" },
					{ id = "claim-abcd1234", kind = "concern", note = "See `#3.118e+15`" },
				},
			},
		}
		claims.normalize_session_claim_ids(files)
		t.assert_eq(files["legacy.lua"].claims[1].id, "question-1", "legacy IDs should receive a session number")
		t.assert_eq(files["legacy.lua"].claims[2].id, "concern-2", "migration numbers should be session-wide")
		t.assert_eq(files["legacy.lua"].claims[2].note, "See `#question-1`", "migration should rewrite inline tokens")
	end)

	it("inserts multiple claim IDs into the note without exposing IDs in the picker", function()
		local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
		local temp_file = vim.fs.joinpath(vim.fn.tempname(), "claim-reference.lua")
		vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
		vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
		vim.fn.writefile({ "local first = 1", "local second = 2", "return first + second" }, temp_file)

		local doubt = require("doubt")
		local config = require("doubt.config")
		local export = require("doubt.export")
		local inline_editor = require("doubt.inline_editor")
		local state = require("doubt.state")
		doubt.setup({ keymaps = false, state_path = temp_state })
		vim.cmd.edit(temp_file)
		doubt.start_session({ name = "references", quiet = true })

		local bufnr = vim.api.nvim_get_current_buf()
		local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
		doubt.claim_range("concern", { bufnr = bufnr, line1 = 1, line2 = 1, note = "Original explanation" })
		doubt.claim_range("question", { bufnr = bufnr, line1 = 2, line2 = 2, note = "Another explanation" })
		local targets = state.current_files()[path].claims
		t.assert_eq(targets[1].id, "concern-1", "the first claim should use its kind and session number")
		t.assert_eq(targets[2].id, "question-2", "claim numbers should be unique across kinds")

		local original_select = vim.ui.select
		local picker_items
		local picker_opts
		local selection = 0
		vim.ui.select = function(items, opts, callback)
			selection = selection + 1
			picker_items = items
			picker_opts = opts
			callback(items[selection])
		end

		vim.api.nvim_win_set_cursor(0, { 3, 0 })
		doubt.claim_range("concern")
		local editor = inline_editor.status()
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A#", true, false, true), "xt", false)
		vim.wait(1000, function()
			return picker_items ~= nil and inline_editor.status().active
		end)
		t.assert_eq(picker_opts.kind, "doubt_claim", "# should open the claim reference picker")
		t.assert_eq(#picker_items, 2, "the picker should include other claims from the active session")
		t.assert_eq(picker_items[1].label:find(targets[1].id, 1, true), nil, "picker labels should hide internal IDs")
		t.assert_match(picker_items[1].label, "CONCERN%s+.*claim%-reference%.lua:1", "picker labels should lead with kind and location")

		vim.wait(1000, function()
			local status = inline_editor.status()
			return status.active and table.concat(vim.api.nvim_buf_get_lines(status.bufnr, 0, -1, false), "\n"):find(targets[1].id, 1, true) ~= nil
		end)
		editor = inline_editor.status()
		vim.api.nvim_set_current_win(editor.winid)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A#", true, false, true), "xt", false)
		vim.wait(1000, function()
			local status = inline_editor.status()
			return status.active and table.concat(vim.api.nvim_buf_get_lines(status.bufnr, 0, -1, false), "\n"):find(targets[2].id, 1, true) ~= nil
		end)

		inline_editor.submit()
		vim.ui.select = original_select
		local referenced = state.current_files()[path].claims[3]
		t.assert_eq(referenced.id, "concern-3", "new claims should continue the session-wide sequence")
		t.assert_eq(
			referenced.note,
			"`#" .. targets[1].id .. "` `#" .. targets[2].id .. "`",
			"each selection should insert a separate token directly into the note"
		)
		t.assert_eq(referenced.reference_claim_id, nil, "claim references should not create a separate schema field")

		local xml = export.build_session_xml("references", state.current_files(), config.get().export)
		t.assert_eq(xml:find('id="' .. targets[1].id .. '"', 1, true) ~= nil, true, "exports should identify reference targets")
		t.assert_eq(xml:find("`#" .. targets[1].id .. "` `#" .. targets[2].id .. "`", 1, true) ~= nil, true, "exports should keep inline reference tokens in the note")
		t.assert_eq(xml:find("reference_claim_id", 1, true), nil, "exports should not add a separate reference attribute")
	end)
end)
