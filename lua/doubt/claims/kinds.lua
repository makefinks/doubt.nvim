local M = {}

local DEFAULT_KIND_META = {
	question = {
		order = 10,
		command = "Question",
		description = "Question current line or selection",
		hl = "DoubtQuestion",
		inline_label = " QUESTION ",
		inline_label_hl = "DoubtInlineQuestionLabel",
		inline_text_hl = "DoubtInlineQuestionText",
		label = "?",
		sign = "question",
		default_note = "question",
	},
	concern = {
		order = 15,
		command = "Concern",
		description = "Flag concern on current line or selection",
		hl = "DoubtConcern",
		inline_label = " CONCERN ",
		inline_label_hl = "DoubtInlineConcernLabel",
		inline_text_hl = "DoubtInlineConcernText",
		label = "~",
		sign = "concern",
		default_note = "concern",
	},
	reject = {
		order = 20,
		command = "Reject",
		description = "Reject current line or selection",
		hl = "DoubtReject",
		inline_label = " REJECT ",
		inline_label_hl = "DoubtInlineRejectLabel",
		inline_text_hl = "DoubtInlineRejectText",
		label = "!",
		sign = "reject",
		default_note = "reject",
	},
}

local claim_kinds = { "question", "concern", "reject" }
local claim_meta = vim.deepcopy(DEFAULT_KIND_META)

local function default_inline_label(kind)
	return string.format(" %s ", string.upper(kind:gsub("_", " ")))
end

local function default_command_name(kind)
	local parts = vim.split(kind, "_", { plain = true, trimempty = true })
	for idx, part in ipairs(parts) do
		parts[idx] = part:gsub("^%l", string.upper)
	end
	return table.concat(parts, "")
end

local function build_kind_meta(kind, opts)
	opts = opts or {}
	local base = vim.deepcopy(DEFAULT_KIND_META[kind] or DEFAULT_KIND_META.question)
	local meta = vim.tbl_deep_extend("force", base, opts)
	meta.command = meta.command or default_command_name(kind)
	meta.description = meta.description or string.format("%s current line or selection", meta.command)
	meta.inline_label = meta.inline_label or default_inline_label(kind)
	meta.label = meta.label or DEFAULT_KIND_META.question.label
	meta.sign = meta.sign or kind
	meta.default_note = meta.default_note or kind
	return meta
end

local function is_claim_kind(kind)
	for _, value in ipairs(claim_kinds) do
		if value == kind then
			return true
		end
	end

	return false
end

function M.configure(kind_defs)
	local normalized = {}
	for kind, opts in pairs(kind_defs or DEFAULT_KIND_META) do
		if type(kind) == "string" and kind ~= "" and type(opts) == "table" then
			normalized[kind] = build_kind_meta(kind, opts)
		end
	end

	if vim.tbl_isempty(normalized) then
		normalized = vim.deepcopy(DEFAULT_KIND_META)
	end

	claim_meta = normalized
	claim_kinds = vim.tbl_keys(claim_meta)
	table.sort(claim_kinds, function(a, b)
		local a_order = (claim_meta[a] or {}).order or math.huge
		local b_order = (claim_meta[b] or {}).order or math.huge
		if a_order ~= b_order then
			return a_order < b_order
		end

		return a < b
	end)
end

function M.list_claim_kinds()
	return vim.deepcopy(claim_kinds)
end

function M.has_claim_kind(kind)
	return is_claim_kind(kind)
end

function M.meta(kind)
	return claim_meta[kind] or claim_meta.question
end

function M.default_note(kind)
	return (M.meta(kind) or {}).default_note or kind or "question"
end

function M.normalize_claim_kind(kind)
	if is_claim_kind(kind) then
		return kind
	end

	return "question"
end

M.configure()

return M
