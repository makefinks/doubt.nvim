-- Configuration and highlight setup for the plugin.
local M = {}

local DEFAULTS = {
		export = {
			default_template = "review",
			instructions = {
				question = "Explain the code and address the feedback without modifying the code.",
				concern = "Investigate the concern, explain whether it is valid, and revise the code if needed.",
				reject = "Remove or replace the code according to the feedback.",
			},
		register = "+",
				templates = {
					raw = "{{xml}}",
				review = table.concat({
					"The reviewer has provided feedback for the code in the xml below.",
					"Fetch every referenced file and line from the repository before performing claim specific actions.",
					"Also fetch any additional context from the codebase that may be relevant to the claim and your response.",
					"",
					"{{xml}}",
					"",
					"Format each claim as a separate section with a single horizontal divider line containing a centered CLAIM 1, CLAIM 2, and so on header.",
					"Under that, include labeled metadata lines for File and Claim Note using the exact file path, line range, kind, and claim note text from the xml.",
					"Also include the code context for each claim when the claim references fewer than 30 lines of code.",
					"Render code context as plain line-numbered code inside a fenced code block.",
					"Use a visible box-style top border above the code block and a matching bottom border below it, sized to the code block width.",
					"Use border lines only above and below the block, never at the left or right edge of each code line.",
					"Then provide the response for that claim directly below.",
				}, "\n"),
				multi_agent = table.concat({
					"You are coordinating a response to feedback the reviewer has provided.",
					"Fetch every referenced file and line from the repository before assigning claim specific work.",
					"Also fetch any additional context from the codebase that may be relevant to the claim and your response.",
					"Triage each claim, delegate explanation or revision work as needed, and return one consolidated response.",
					"You should act as a coordinator that delegates work and consolidates the individual responses from subagents into a final response for the user.",
					"",
					"{{xml}}",
					"",
					"In the final consolidated response, format each claim as a separate section with a single horizontal divider line containing a centered CLAIM 1, CLAIM 2, and so on header.",
					"Under that, include labeled metadata lines for File and Claim Note using the exact file path, line range, kind, and claim note text from the xml.",
					"In the final consolidated response, also include the code context for each claim when the claim references fewer than 30 lines of code.",
					"Render code context in the final consolidated response as plain line-numbered code inside a fenced code block.",
					"Use a visible box-style top border above the code block and a matching bottom border below it, sized to the code block width.",
					"Use border lines only above and below the block, never at the left or right edge of each code line.",
					"If you delegate work, require subagents to preserve the exact claim identifiers in their responses.",
					"Then provide the response for that claim directly below.",
				}, "\n"),
		},
	},
	input = {
		border = "rounded",
		prompts = {
			question = "Question note: ",
			concern = "Concern note: ",
			reject = "Reject note: ",
		},
		width = 50,
	},
	claim_kinds = {
		question = {
			command = "Question",
			default_note = "question",
			description = "Question current line or selection",
			label = "?",
			order = 10,
			styles = {
				inline_label = { fg = "#08141F", bg = "#7DD3FC", bold = true },
				inline_text = { fg = "#F5F5F5", bg = "#111827", italic = true },
				mark = { fg = "#9DDCFA", bg = "#173042", bold = true },
			},
		},
		concern = {
			command = "Concern",
			default_note = "concern",
			description = "Flag concern on current line or selection",
			label = "~",
			order = 15,
			styles = {
				inline_label = { fg = "#201600", bg = "#F6C453", bold = true },
				inline_text = { fg = "#F5F5F5", bg = "#111827", italic = true },
				mark = { fg = "#FFE08A", bg = "#4A3200", bold = true },
			},
		},
		reject = {
			command = "Reject",
			default_note = "reject",
			description = "Reject current line or selection",
			label = "!",
			order = 20,
			styles = {
				inline_label = { fg = "#FFF5F5", bg = "#FF3B30", bold = true },
				inline_text = { fg = "#F5F5F5", bg = "#111827", italic = true },
				mark = { fg = "#FFC2C2", bg = "#442526", bold = true },
			},
		},
	},
	inline_notes = {
		enabled = true,
		max_width = 60,
		prefix = "",
		padding_right = 2,
	},
	keymaps = {
		question = "<leader>Dq",
		concern = "<leader>Dc",
		reject = "<leader>Dr",
		claims = {},
		delete_claim = "<leader>Dd",
		edit_kind = "<leader>Dk",
		edit_note = "<leader>Dm",
		toggle_claim = "<leader>Dt",
		export = "<leader>De",
		clear_buffer = "<leader>Db",
		panel = "<leader>Dp",
		session_new = "<leader>Dn",
		session_resume = "<leader>Ds",
		stop_session = "<leader>Dx",
		refresh = "<leader>Df",
	},
	panel = {
		width = 56,
		side = "right",
	},
	state_path = vim.fs.joinpath(vim.fn.stdpath("state"), "doubt.nvim.json"),
	signs = {
		file = "?",
		question = "?",
		concern = "~",
		reject = "!",
	},
}

local config = vim.deepcopy(DEFAULTS)

local function muted_hex(color, factor)
	if type(color) ~= "string" or not color:match("^#%x%x%x%x%x%x$") then
		return color
	end

	local channels = {}
	for index = 2, 6, 2 do
		local channel = tonumber(color:sub(index, index + 1), 16)
		channel = math.floor(math.max(0, math.min(255, channel * factor)) + 0.5)
		table.insert(channels, string.format("%02X", channel))
	end

	return "#" .. table.concat(channels)
end

local function stale_mark_style(style)
	style = style or {}
	return {
		fg = muted_hex(style.fg, 0.7),
		bg = muted_hex(style.bg, 0.45),
		bold = false,
		italic = true,
	}
end

local function dim_style(style)
	style = style or {}
	return {
		fg = muted_hex(style.fg, 0.55),
		bg = muted_hex(style.bg, 0.45),
		bold = false,
		italic = style.italic,
	}
end

local function default_command_name(kind)
	local parts = vim.split(kind, "_", { plain = true, trimempty = true })
	for idx, part in ipairs(parts) do
		parts[idx] = part:gsub("^%l", string.upper)
	end
	return table.concat(parts, "")
end

local function normalize_kind_overrides(current)
	current.input = current.input or {}
	current.input.prompts = current.input.prompts or {}
	current.keymaps = current.keymaps or {}
	current.keymaps.claims = current.keymaps.claims or {}
	current.signs = current.signs or {}

	for kind, meta in pairs(current.claim_kinds or {}) do
		meta.command = meta.command or default_command_name(kind)
		meta.sign = current.signs[kind] or meta.sign or meta.label
		meta.prompt = current.input.prompts[kind] or meta.prompt or (meta.command and (meta.command .. " note: ")) or (kind .. ": ")
		if current.keymaps[kind] ~= nil and current.keymaps.claims[kind] == nil then
			current.keymaps.claims[kind] = current.keymaps[kind]
		end
	end

	return current
end

function M.setup(opts)
	config = normalize_kind_overrides(vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {}))
	return config
end

function M.get()
	return config
end

-- Keep plugin-owned highlight groups in one place so UI modules stay focused on rendering.
function M.set_highlights()
	-- Keep claim highlight colors in the same hue family as the inline labels,
	-- but softer so the buffer highlights stay faint.
	vim.api.nvim_set_hl(0, "DoubtFile", { fg = "#F8E7A1", bold = true })
	vim.api.nvim_set_hl(0, "DoubtInlinePrefix", { fg = "#7F8794" })
	vim.api.nvim_set_hl(0, "DoubtInlineBar", { bg = "#000000", fg = "#000000" })
	for kind, meta in pairs(config.claim_kinds or {}) do
		meta.styles = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS.claim_kinds.question.styles or {}), meta.styles or {})
		local claim_group = meta.hl or ("Doubt" .. meta.command)
		local stale_claim_group = meta.stale_hl or ("DoubtStale" .. meta.command)
		local dim_claim_group = meta.dim_hl or ("DoubtDim" .. meta.command)
		local dim_stale_claim_group = meta.dim_stale_hl or ("DoubtDimStale" .. meta.command)
		local inline_label_group = meta.inline_label_hl or ("DoubtInline" .. meta.command .. "Label")
		local inline_text_group = meta.inline_text_hl or ("DoubtInline" .. meta.command .. "Text")
		local dim_inline_label_group = meta.dim_inline_label_hl or ("DoubtInlineDim" .. meta.command .. "Label")
		local dim_inline_text_group = meta.dim_inline_text_hl or ("DoubtInlineDim" .. meta.command .. "Text")
		meta.hl = claim_group
		meta.stale_hl = stale_claim_group
		meta.dim_hl = dim_claim_group
		meta.dim_stale_hl = dim_stale_claim_group
		meta.inline_label_hl = inline_label_group
		meta.inline_text_hl = inline_text_group
		meta.dim_inline_label_hl = dim_inline_label_group
		meta.dim_inline_text_hl = dim_inline_text_group
		if meta.styles and meta.styles.mark then
			vim.api.nvim_set_hl(0, claim_group, meta.styles.mark)
			vim.api.nvim_set_hl(0, stale_claim_group, stale_mark_style(meta.styles.mark))
			vim.api.nvim_set_hl(0, dim_claim_group, dim_style(meta.styles.mark))
			vim.api.nvim_set_hl(0, dim_stale_claim_group, dim_style(stale_mark_style(meta.styles.mark)))
		end
		if meta.styles and meta.styles.inline_label then
			vim.api.nvim_set_hl(0, inline_label_group, meta.styles.inline_label)
			vim.api.nvim_set_hl(0, dim_inline_label_group, dim_style(meta.styles.inline_label))
		end
		if meta.styles and meta.styles.inline_text then
			vim.api.nvim_set_hl(0, inline_text_group, meta.styles.inline_text)
			vim.api.nvim_set_hl(0, dim_inline_text_group, dim_style(meta.styles.inline_text))
		end
		config.claim_kinds[kind] = meta
	end
	vim.api.nvim_set_hl(0, "DoubtPanelTitle", { fg = "#F8E7A1", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelSection", { fg = "#F5F5F5", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelFile", { fg = "#8EC5FC", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelSession", { fg = "#C6F6D5", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelCount", { fg = "#F8E7A1", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelKey", { fg = "#FDE68A", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelMuted", { fg = "#7F8794" })
	vim.api.nvim_set_hl(0, "DoubtPanelStale", { fg = "#D4A373", italic = true })
	vim.api.nvim_set_hl(0, "DoubtPanelActiveClaim", { bg = "#2A3441" })
	vim.api.nvim_set_hl(0, "DoubtPanelHelpNormal", { fg = "#D5DEE8" })
	vim.api.nvim_set_hl(0, "DoubtPanelHelpTitle", { fg = "#F8E7A1", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelHelpSection", { fg = "#8EC5FC", bold = true })
	vim.api.nvim_set_hl(0, "DoubtPanelHelpBorder", { fg = "#566476" })
	vim.api.nvim_set_hl(0, "DoubtPanelHelpText", { fg = "#A8B3C2" })
end

return M
