local t = dofile("tests/helpers/bootstrap.lua")

local claims = require("doubt.claims")
local export = require("doubt.export")

local files = {
	["lua/doubt/export.lua"] = {
		claims = {
			{
				id = "fresh",
				kind = "question",
				start_line = 0,
				start_col = 0,
				end_line = 0,
				end_col = 4,
				note = "fresh note",
				freshness = "fresh",
			},
			{
				id = "reanchored",
				kind = "reject",
				start_line = 2,
				start_col = 0,
				end_line = 2,
				end_col = 6,
				note = "moved but trusted",
				freshness = "reanchored",
			},
			{
				id = "stale",
				kind = "concern",
				start_line = 4,
				start_col = 0,
				end_line = 4,
				end_col = 7,
				note = "stale note",
				freshness = "stale",
			},
		},
	},
	["lua/doubt/init.lua"] = {
		claims = {
			{
				id = "unknown",
				kind = "question",
				start_line = 1,
				start_col = 0,
				end_line = 1,
				end_col = 5,
				note = "unknown freshness",
				freshness = "mystery",
			},
		},
	},
}

local trusted_files, stats = export.select_trusted_files(files)

t.assert_eq(stats.exportable_claim_count, 2, "trusted export should count fresh and reanchored claims only")
t.assert_eq(stats.exportable_file_count, 1, "trusted export should count only files left with trusted claims")
t.assert_eq(stats.skipped_stale_claims, 2, "trusted export should count stale and malformed freshness claims as skipped")
t.assert_eq(trusted_files["lua/doubt/init.lua"], nil, "trusted export should drop files left with zero trusted claims")
t.assert_eq(#trusted_files["lua/doubt/export.lua"].claims, 2, "trusted export should keep only trusted claims")
t.assert_eq(trusted_files["lua/doubt/export.lua"].claims[1].freshness, "fresh", "trusted export should preserve fresh claims")
t.assert_eq(trusted_files["lua/doubt/export.lua"].claims[2].freshness, "reanchored", "trusted export should preserve reanchored claims")

trusted_files["lua/doubt/export.lua"].claims[1].note = "changed"
t.assert_eq(files["lua/doubt/export.lua"].claims[1].note, "fresh note", "trusted export should deep-copy returned claims")

local raw_xml = export.build_session_xml("trust-review", files)
t.assert_match(raw_xml, 'note="stale note"', "raw xml should still include stale claims when callers pass the full file map")

package.loaded["doubt"] = nil
package.loaded["doubt.config"] = nil
package.loaded["doubt.export"] = nil
package.loaded["doubt.input"] = nil
package.loaded["doubt.keymaps"] = nil
package.loaded["doubt.panel"] = nil
package.loaded["doubt.render"] = nil
package.loaded["doubt.state"] = nil

local function write_file(path, lines)
	vim.fn.writefile(lines, path)
end

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
vim.fn.mkdir(vim.fs.dirname(temp_state), "p")

local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, "p")

local trusted_path = vim.fs.joinpath(temp_dir, "trusted.lua")
local stale_path = vim.fs.joinpath(temp_dir, "stale.lua")

write_file(trusted_path, {
	"trusted()",
	"tail()",
})
write_file(stale_path, {
	"stale()",
	"tail()",
})

local trusted_content = table.concat(vim.fn.readfile(trusted_path), "\n")
local stale_content = table.concat(vim.fn.readfile(stale_path), "\n")

local doubt = require("doubt")
local state = require("doubt.state")

doubt.setup({
	export = {
		register = "c",
	},
	keymaps = false,
	state_path = temp_state,
})

state.set_active_session("trust-review")

local mixed = state.ensure_file_entry(trusted_path)
table.insert(mixed.claims, {
	id = "1",
	kind = "question",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 9,
	note = "trusted note",
	freshness = "fresh",
	anchor = claims.build_content_anchor(trusted_content, 0, 0, 0, 9),
})

local stale_only = state.ensure_file_entry(stale_path)
table.insert(stale_only.claims, {
	id = "2",
	kind = "concern",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 7,
	note = "another stale note",
	freshness = "fresh",
	anchor = claims.build_content_anchor(stale_content, 0, 0, 0, 7),
})

write_file(stale_path, {
	"changed()",
	"tail()",
})

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level, opts)
	table.insert(notifications, {
		message = message,
		level = level,
		opts = opts,
	})
end

local copied = doubt.copy_export()
t.assert_match(copied, '^The reviewer has provided feedback for the code in the xml below%.', "default copy export should still use the wrapped handoff")
t.assert_match(copied, 'note="trusted note"', "default copy export should keep trusted claims")
t.assert_eq(copied:match('another stale note'), nil, "default copy export should omit stale claims after pre-export refresh")
t.assert_eq(copied:match('another stale note'), nil, "default copy export should omit files with only stale claims")
t.assert_eq(vim.fn.getreg("c"), copied, "default copy export should write the trusted handoff to the configured register")
	t.assert_eq(notifications[#notifications].message, "Copied doubt export to c (review, skipped 1 stale claim)", "default copy export should report stale claims found during pre-export refresh")
t.assert_eq(notifications[#notifications].level, vim.log.levels.INFO, "mixed trusted exports should notify at info level")

vim.fn.setreg("c", "keep me")
state.get().sessions["trust-review"].files = {
	[stale_path] = {
		claims = {
			{
				id = "3",
				kind = "question",
				start_line = 0,
				start_col = 0,
				end_line = 0,
				end_col = 7,
				note = "only stale",
				freshness = "fresh",
				anchor = claims.build_content_anchor(stale_content, 0, 0, 0, 7),
			},
		},
	},
}

local blocked = doubt.copy_export()
t.assert_eq(blocked, nil, "default copy export should refuse empty trusted exports")
t.assert_eq(vim.fn.getreg("c"), "keep me", "all-stale export should not overwrite the register")
t.assert_eq(notifications[#notifications].message, "No exportable claims remain; skipped 1 stale claim", "all-stale export should warn with the skipped stale count")
t.assert_eq(notifications[#notifications].level, vim.log.levels.WARN, "all-stale export should notify at warn level")

doubt.export_xml()

local bufnr = vim.api.nvim_get_current_buf()
local xml_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local xml = table.concat(xml_lines, "\n")
t.assert_match(xml, 'note="only stale"', "raw xml export should remain available for deliberate stale-claim inspection")

vim.notify = original_notify
