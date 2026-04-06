local t = dofile("tests/helpers/bootstrap.lua")
local config = require("doubt.config")
local export = require("doubt.export")

local export_config = config.setup({}).export

local xml = export.build_session_xml("review & verify <phase>", {
	["zeta.lua"] = {
		claims = {
			{
				kind = "reject",
				start_line = 9,
				start_col = 1,
				end_line = 11,
				end_col = 5,
				note = 'wrong > invariant & "proof"',
			},
		},
	},
	["alpha/<beta>.lua"] = {
		claims = {
			{
				kind = "question",
				start_line = 0,
				start_col = 2,
				end_line = 0,
				end_col = 8,
				note = "needs <source> & context",
			},
			{
				kind = "reject",
				start_line = 4,
				start_col = 0,
				end_line = 5,
				end_col = 12,
				note = "line \"breaks\" here",
			},
		},
	},
}, export_config)

t.assert_eq(export.build_session_xml(nil, {}), nil, "missing session names should return nil")
t.assert_eq(
	export.build_session_xml("empty", {}),
	'<doubt session="empty"></doubt>',
	"empty sessions should still emit a root node"
)
t.assert_match(xml, '^<doubt session="review &amp; verify &lt;phase&gt;">', "root node should escape session name")
t.assert_match(
	xml,
	'<instructions>\n    <instruction kind="question">Explain the code and address the feedback without modifying the code%.</instruction>\n    <instruction kind="reject">Remove or replace the code according to the feedback%.</instruction>\n  </instructions>\n  <file path="alpha/&lt;beta&gt;%.lua">',
	"xml should inject one deduplicated instruction block before file nodes"
)
t.assert_eq(select(2, xml:gsub('kind="reject">Remove or replace the code according to the feedback%.</instruction>', "")), 1, "xml should not repeat duplicate kind instructions")
t.assert_match(xml, '<file path="alpha/&lt;beta&gt;.lua">\n  <claim\n    kind="question"', "files should be sorted lexicographically")
t.assert_match(xml, 'kind="question"\n    start_line="1"\n    start_col="2"\n    end_line="1"\n    end_col="8"\n    note="needs &lt;source&gt; &amp; context"', "claims should convert lines and escape notes")
t.assert_match(xml, 'kind="reject"\n    start_line="5"\n    start_col="0"\n    end_line="6"\n    end_col="12"\n    note="line &quot;breaks&quot; here"', "claims should keep order inside a file")
t.assert_match(xml, '<file path="zeta.lua">\n  <claim\n    kind="reject"\n    start_line="10"\n    start_col="1"\n    end_line="12"\n    end_col="5"\n    note="wrong &gt; invariant &amp; &quot;proof&quot;"\n  />', "later files should also render claims")
t.assert_eq(
	export.build_session_xml("review & verify <phase>", {
		["alpha.lua"] = {
			claims = {
				{
					kind = "question",
					start_line = 0,
					start_col = 0,
					end_line = 0,
					end_col = 0,
					note = "hi",
				},
			},
		},
	}, export_config):match('kind="question">([^<]+)</instruction>'),
	"Explain the code and address the feedback without modifying the code.",
	"question should default to explanation-only guidance"
)
t.assert_eq(
	export.build_session_xml("review & verify <phase>", {
		["alpha.lua"] = {
			claims = {
				{
					kind = "reject",
					start_line = 0,
					start_col = 0,
					end_line = 0,
					end_col = 0,
					note = "hi",
				},
			},
		},
	}, export_config):match('kind="reject">([^<]+)</instruction>'),
	"Remove or replace the code according to the feedback.",
	"reject should default to revise-or-remove guidance"
)
t.assert_match(xml, '</doubt>$', "xml should close the root node")
