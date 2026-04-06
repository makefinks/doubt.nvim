local t = dofile("tests/helpers/bootstrap.lua")
local export = require("doubt.export")

local files = {
	["beta.lua"] = {
		claims = {
			{
				kind = "question",
				start_line = 0,
				start_col = 0,
				end_line = 0,
				end_col = 3,
				note = "first",
			},
			{
				kind = "reject",
				start_line = 2,
				start_col = 1,
				end_line = 2,
				end_col = 5,
				note = "second",
			},
		},
	},
	["alpha.lua"] = {
		claims = {
			{
				kind = "reject",
				start_line = 4,
				start_col = 0,
				end_line = 4,
				end_col = 4,
				note = "third",
			},
		},
	},
}

local text, err, template_name = export.build_export_text({
	export_config = {
		default_template = "summary",
		templates = {
			raw = "{{xml}}",
			summary = "session={{session}} alias={{session_name}} files={{file_count}} claims={{claim_count}}\n{{xml}}",
		},
	},
	files = files,
	session_name = "review-42",
})

t.assert_eq(err, nil, "custom templates should render without an error")
t.assert_eq(template_name, "summary", "the configured default template should be used")
t.assert_match(text, "^session=review%-42 alias=review%-42 files=2 claims=3\n<doubt session=\"review%-42\">", "template variables should expand to session and count metadata")
