local t = dofile("tests/helpers/bootstrap.lua")

package.loaded["doubt"] = nil
package.loaded["doubt.panel"] = nil
package.loaded["doubt.render"] = nil
package.loaded["doubt.state"] = nil
package.loaded["doubt.export"] = nil

local doubt = require("doubt")
local claims = require("doubt.claims")
local export = require("doubt.export")
local panel = require("doubt.panel")
local render = require("doubt.render")
local state = require("doubt.state")

local temp_root = vim.fn.tempname()
local temp_state = vim.fs.joinpath(temp_root, "benchmark-state.json")
local workspace = vim.fs.joinpath(temp_root, "workspace")
local render_file = vim.fs.joinpath(workspace, "render_target.lua")

local uv = vim.uv

local function mkdirp(path)
	vim.fn.mkdir(path, "p")
end

local function write_file(path, lines)
	mkdirp(vim.fs.dirname(path))
	vim.fn.writefile(lines, path)
end

local function build_source_lines(file_index, line_count)
	local lines = {}
	for line = 1, line_count do
		lines[line] = string.format("local file_%d_line_%d = %d", file_index, line, file_index + line)
	end
	return lines
end

local function build_note(file_index, claim_index)
	return string.format(
		"benchmark note %03d-%03d alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu",
		file_index,
		claim_index
	)
end

local function make_claim(file_lines, file_index, claim_index)
	local line_count = #file_lines
	local start_line = (claim_index - 1) % line_count
	local line_text = file_lines[start_line + 1]
	local start_col = 0
	local end_col = math.min(18, #line_text)
	local content = table.concat(file_lines, "\n")
	return claims.normalize_claim({
		id = string.format("%d-%d", file_index, claim_index),
		kind = claim_index % 3 == 0 and "reject" or (claim_index % 2 == 0 and "concern" or "question"),
		start_line = start_line,
		start_col = start_col,
		end_line = start_line,
		end_col = end_col,
		note = build_note(file_index, claim_index),
		freshness = "fresh",
		anchor = claims.build_content_anchor(content, start_line, start_col, start_line, end_col),
	})
end

local function build_dataset(file_count, claims_per_file, line_count)
	local files = {}
	for file_index = 1, file_count do
		local file_path = vim.fs.joinpath(workspace, string.format("bench_%02d.lua", file_index))
		local file_lines = build_source_lines(file_index, line_count)
		write_file(file_path, file_lines)
		local normalized_path = vim.fs.normalize(file_path)
		files[normalized_path] = { claims = {} }
		for claim_index = 1, claims_per_file do
			table.insert(files[normalized_path].claims, make_claim(file_lines, file_index, claim_index))
		end
		claims.sort_claims(files[normalized_path].claims)
	end
	return files
end

local function count_claims(files)
	local total = 0
	for _, file_state in pairs(files) do
		total = total + #((file_state or {}).claims or {})
	end
	return total
end

local function measure(label, opts)
	opts = opts or {}
	local warmup = opts.warmup or 3
	local iterations = opts.iterations or 12
	for _ = 1, warmup do
		opts.run()
	end

	collectgarbage("collect")
	local samples = {}
	local total = 0
	for index = 1, iterations do
		local started = uv.hrtime()
		opts.run()
		local elapsed_ms = (uv.hrtime() - started) / 1000000
		samples[index] = elapsed_ms
		total = total + elapsed_ms
	end

	table.sort(samples)
	local median = samples[math.ceil(#samples / 2)]
	return {
		label = label,
		iterations = iterations,
		avg_ms = total / iterations,
		median_ms = median,
		max_ms = samples[#samples],
		min_ms = samples[1],
	}
	end

local function format_result(result)
	return string.format(
		"%-34s avg=%7.2fms  median=%7.2fms  min=%7.2fms  max=%7.2fms  iters=%d",
		result.label,
		result.avg_ms,
		result.median_ms,
		result.min_ms,
		result.max_ms,
		result.iterations
	)
end

mkdirp(workspace)
	doubt.setup({
		keymaps = false,
		state_path = temp_state,
		inline_notes = {
			enabled = true,
			max_width = 28,
			padding_right = 2,
			prefix = "",
		},
		panel = {
			side = "right",
			width = 72,
		},
	})

vim.cmd.cd(workspace)
	doubt.start_session({ name = "performance-bench", quiet = true })

local benchmark_files = build_dataset(12, 24, 80)
	local current = state.get()
	current.sessions[state.active_session_name()].files = benchmark_files

write_file(render_file, build_source_lines(99, 120))
	vim.cmd.edit(render_file)
	local render_bufnr = vim.api.nvim_get_current_buf()
	local render_path = vim.fs.normalize(vim.api.nvim_buf_get_name(render_bufnr))
	benchmark_files[render_path] = benchmark_files[render_path] or { claims = {} }
	if vim.tbl_isempty(benchmark_files[render_path].claims) then
		local file_lines = vim.api.nvim_buf_get_lines(render_bufnr, 0, -1, false)
		for claim_index = 1, 36 do
			table.insert(benchmark_files[render_path].claims, make_claim(file_lines, 99, claim_index))
		end
		claims.sort_claims(benchmark_files[render_path].claims)
	end

	panel.open({
		augroup = vim.api.nvim_create_augroup("doubt-performance-bench", { clear = true }),
		config = require("doubt.config"),
		state = state,
		api = {
			refresh = function() end,
			start_session = function() end,
			resume_session = function() end,
			stop_session = function() end,
			delete_session = function() end,
			rename_session = function() end,
			clear_focused_claim = function() end,
			focus_claim = function() end,
			delete_claim = function() end,
			delete_file = function() end,
		},
		ns = vim.api.nvim_create_namespace("doubt-performance-bench"),
	})

	local ctx = {
		ns = vim.api.nvim_get_namespaces()["doubt.nvim"],
		config = require("doubt.config"),
		state = state,
		current_path = function(bufnr)
			return vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
		end,
		focus_mode = function()
			return "normal"
		end,
		is_claim_expanded = function(_, claim)
			return claim.id == "99-1"
		end,
	}

	local session_name = state.active_session_name()
	t.assert_eq(session_name ~= nil, true, "benchmark session should be active")
	t.assert_eq(count_claims(state.current_files()) > 0, true, "benchmark should populate synthetic claims")

	local results = {
		measure("panel.render", {
			iterations = 18,
			run = function()
				panel.render({
					ns = ctx.ns,
					config = ctx.config,
					state = state,
				})
			end,
		}),
		measure("refresh_ui legacy", {
			iterations = 12,
			run = function()
				render.refresh_buffer(ctx, render_bufnr)
				render.refresh_visible_buffers(ctx)
				panel.render({
					ns = ctx.ns,
					config = ctx.config,
					state = state,
				})
			end,
		}),
		measure("refresh_ui optimized", {
			iterations = 12,
			run = function()
				render.refresh_buffer(ctx, render_bufnr)
				render.refresh_visible_buffers(ctx, { skip_bufnr = render_bufnr })
				panel.render({
					ns = ctx.ns,
					config = ctx.config,
					state = state,
				})
			end,
		}),
		measure("render.refresh_buffer", {
			iterations = 18,
			run = function()
				render.refresh_buffer(ctx, render_bufnr)
			end,
		}),
		measure("state.classify_current_session_claims", {
			iterations = 10,
			run = function()
				state.classify_current_session_claims()
			end,
		}),
		measure("export.build_session_xml", {
			iterations = 35,
			run = function()
				export.build_session_xml(session_name, state.current_files())
			end,
		}),
		measure("panel.open + render", {
			iterations = 10,
			run = function()
				panel.open({
					augroup = vim.api.nvim_create_augroup("doubt-performance-bench-open", { clear = true }),
					config = require("doubt.config"),
					state = state,
					api = {
						refresh = function() end,
						start_session = function() end,
						resume_session = function() end,
						stop_session = function() end,
						delete_session = function() end,
						rename_session = function() end,
						clear_focused_claim = function() end,
						focus_claim = function() end,
						delete_claim = function() end,
						delete_file = function() end,
					},
					ns = vim.api.nvim_create_namespace("doubt-performance-bench-open"),
				})
				panel.open({
					augroup = vim.api.nvim_create_augroup("doubt-performance-bench-open", { clear = true }),
					config = require("doubt.config"),
					state = state,
					api = {
						refresh = function() end,
						start_session = function() end,
						resume_session = function() end,
						stop_session = function() end,
						delete_session = function() end,
						rename_session = function() end,
						clear_focused_claim = function() end,
						focus_claim = function() end,
						delete_claim = function() end,
						delete_file = function() end,
					},
					ns = vim.api.nvim_create_namespace("doubt-performance-bench-open"),
				})
			end,
		}),
	}

	table.sort(results, function(left, right)
		return left.avg_ms > right.avg_ms
	end)

	print(string.format("Performance benchmark (%d files, %d claims)", vim.tbl_count(state.current_files()), count_claims(state.current_files())))
	for _, result in ipairs(results) do
		print(format_result(result))
	end

vim.cmd("tabnew")
