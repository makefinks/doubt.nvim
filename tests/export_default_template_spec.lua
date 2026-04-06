local t = dofile("tests/helpers/bootstrap.lua")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
vim.fn.mkdir(vim.fs.dirname(temp_state), "p")

local doubt = require("doubt")
local claims = require("doubt.claims")
local state = require("doubt.state")

local function write_file(path, lines)
	vim.fn.writefile(lines, path)
end

doubt.setup({
	export = {
		default_template = "review",
		register = "b",
		templates = {
			raw = "{{xml}}",
			review = "Review wrapper\n\n{{xml}}",
		},
	},
	keymaps = false,
	state_path = temp_state,
})

state.set_active_session("default-template-review")

local temp_dir = vim.fn.tempname()
vim.fn.mkdir(temp_dir, "p")
local source_path = vim.fs.joinpath(temp_dir, "default-template-source.lua")
write_file(source_path, {
	"target()",
	"tail()",
})

local content = table.concat(vim.fn.readfile(source_path), "\n")

local file_state = state.ensure_file_entry(source_path)
table.insert(file_state.claims, {
	id = "1",
	kind = "question",
	start_line = 0,
	start_col = 0,
	end_line = 0,
	end_col = 8,
	note = "wrap me",
	freshness = "fresh",
	anchor = claims.build_content_anchor(content, 0, 0, 0, 8),
})
claims.sort_claims(file_state.claims)

local text = doubt.copy_export()

t.assert_match(text, "^Review wrapper", "copy export should use the configured default template")
t.assert_eq(text, vim.fn.getreg("b"), "copy export should still write the rendered text to the configured register")
