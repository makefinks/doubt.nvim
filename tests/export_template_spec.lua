local t = dofile("tests/helpers/bootstrap.lua")
local config = require("doubt.config")
local export = require("doubt.export")

local files = {
	["alpha.lua"] = {
		claims = {
			{
				kind = "question",
				start_line = 0,
				start_col = 0,
				end_line = 0,
				end_col = 4,
				note = "why",
			},
		},
	},
}

local expected_xml = export.build_session_xml("alpha", files)

local default_export = config.setup({}).export

t.assert_eq(
	export.list_template_names(default_export),
	{ "multi_agent", "raw", "review" },
	"default config should ship the built-in template pack"
)

t.assert_eq(default_export.default_template, "review", "review should stay the default template")

local review_text, review_err, review_template_name = export.build_export_text({
	export_config = default_export,
	files = files,
	session_name = "alpha",
	template = "review",
})

t.assert_eq(review_err, nil, "review template should render without an error")
t.assert_eq(review_template_name, "review", "review template should be returned")
t.assert_match(
	review_text,
	"^The reviewer has provided feedback for the code in the xml below%.",
	"review should prepend the built-in review instructions"
)
t.assert_match(
	review_text,
	"Fetch every referenced file and line from the repository before performing claim specific actions%.",
	"review should tell the downstream agent to fetch the referenced code first"
)
t.assert_match(
	review_text,
	'<instruction kind="question">Explain the code and address the feedback without modifying the code%.</instruction>',
	"review should include the instruction-aware xml payload"
)
t.assert_match(review_text, "\n<doubt session=\"alpha\">", "review should include the xml payload after the prompt")

local multi_agent_text, multi_agent_err, multi_agent_template_name = export.build_export_text({
	export_config = default_export,
	files = files,
	session_name = "alpha",
	template = "multi_agent",
})

t.assert_eq(multi_agent_err, nil, "multi_agent template should render without an error")
t.assert_eq(multi_agent_template_name, "multi_agent", "multi_agent template should be returned")
t.assert_match(
	multi_agent_text,
	"^You are coordinating a response to feedback the reviewer has provided%.",
	"multi_agent should prepend the coordinator instructions"
)
t.assert_match(
	multi_agent_text,
	"Triage each claim, delegate explanation or revision work as needed, and return one consolidated response%.",
	"multi_agent should include the triage guidance"
)
t.assert_match(
	multi_agent_text,
	'<instruction kind="question">Explain the code and address the feedback without modifying the code%.</instruction>',
	"multi_agent should include the same instruction-aware xml payload"
)
t.assert_match(multi_agent_text, "\n<doubt session=\"alpha\">", "multi_agent should include the xml payload after the prompt")

local text, err, template_name = export.build_export_text({
	export_config = {
		default_template = "raw",
		templates = {
			raw = "{{xml}}",
			review = "Review this.\n\n{{xml}}",
			multi_agent = "Coordinate this.\n\n{{xml}}",
			escalate = "Escalate this review.\n\n{{xml}}",
		},
	},
	files = files,
	session_name = "alpha",
	template = "escalate",
})

t.assert_eq(err, nil, "custom templates should still render without an error")
t.assert_eq(template_name, "escalate", "the selected custom template should be returned")
t.assert_match(text, "^Escalate this review%.", "custom templates should keep their custom prefix")
t.assert_eq(text, "Escalate this review.\n\n" .. expected_xml, "custom templates should still append the same xml payload")

local empty_text, empty_err, empty_template_name = export.build_export_text({
	export_config = default_export,
	files = {},
	session_name = "alpha",
	template = "raw",
})

t.assert_eq(empty_err, nil, "empty exports should still render without an error")
t.assert_eq(empty_template_name, "raw", "raw template should still be returned for empty exports")
t.assert_eq(empty_text, '<doubt session="alpha"></doubt>', "empty exports should not invent an instruction block")

local _, missing_err = export.build_export_text({
	export_config = {
		templates = {
			raw = "{{xml}}",
		},
	},
	files = files,
	session_name = "alpha",
	template = "missing",
})

t.assert_eq(missing_err, "Unknown doubt export template: missing", "unknown templates should fail clearly")
