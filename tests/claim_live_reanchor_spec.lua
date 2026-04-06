local t = dofile("tests/helpers/bootstrap.lua")
local claims = require("doubt.claims")
local state = require("doubt.state")

local unchanged_claim = {
	id = "claim-unchanged",
	kind = "question",
	start_line = 1,
	start_col = 0,
	end_line = 1,
	end_col = 8,
	note = "stable",
	anchor = {
		text = "target()",
		before = "alpha\n",
		after = "\nomega\n",
	},
}

local unchanged_content = "alpha\ntarget()\nomega\n"
local unchanged_result = claims.validate_claim_anchor(unchanged_claim, unchanged_content)

t.assert_eq(unchanged_result.freshness, "fresh", "unchanged anchors should stay fresh")
t.assert_eq(unchanged_result.saved_range_matches, true, "unchanged anchors should keep the saved range")

local moved_content = "alpha\nchanged\nomega\nbeta\ntarget()\ngamma\n"
local moved_result = claims.validate_claim_anchor(unchanged_claim, moved_content)

t.assert_eq(moved_result.freshness, "stale", "phase 1 matcher should still report moved claims as stale")
t.assert_eq(moved_result.exact_match_count, 1, "moved claim should expose one exact alternate match")

local rebuilt_anchor = claims.build_content_anchor(
	moved_content,
	moved_result.match.start_line,
	moved_result.match.start_col,
	moved_result.match.end_line,
	moved_result.match.end_col
)

t.assert_eq(rebuilt_anchor, {
	text = "target()",
	before = "alpha\nchanged\nomega\nbeta\n",
	after = "\ngamma\n",
}, "unique moved matches should rebuild anchor snapshots from content")

local ambiguous_result = claims.validate_claim_anchor({
	id = "claim-ambiguous",
	kind = "question",
	start_line = 0,
	start_col = 11,
	end_line = 0,
	end_col = 19,
	note = "duplicate",
	anchor = {
		text = "target()",
		before = "if ok then ",
		after = " end",
	},
}, "if ok then target() end\nif ok then target() end\n")

t.assert_eq(ambiguous_result.reason, "ambiguous", "ambiguous matches should remain ambiguous")
t.assert_eq(ambiguous_result.match, nil, "ambiguous matches should not expose a replacement range")

local missing_result = claims.validate_claim_anchor(unchanged_claim, "alpha\nchanged()\nomega\n")

t.assert_eq(missing_result.reason, "missing", "missing anchors should stay missing")
t.assert_eq(missing_result.match, nil, "missing anchors should not expose a replacement range")

local function reset_state(path, claim)
	local store = state.get()
	store.active_session = "live-review"
	store.sessions = {
		["live-review"] = {
			files = {
				[path] = {
					claims = {
						claims.normalize_claim(claim),
					},
				},
			},
		},
	}
	return store.sessions["live-review"].files[path].claims[1]
end

local live_path = "/tmp/live-reanchor.lua"

local fresh_claim = reset_state(live_path, unchanged_claim)
local fresh_summary = state.classify_file_claims(live_path, {
	content = unchanged_content,
})

t.assert_eq(fresh_claim.freshness, "fresh", "unchanged live claims should stay fresh")
t.assert_eq(fresh_claim.start_line, 1, "unchanged live claims should keep their saved line")
t.assert_eq(fresh_summary.changed, true, "fresh live classification should report the freshness update")

local moved_claim = reset_state(live_path, unchanged_claim)
local moved_summary = state.classify_file_claims(live_path, {
	content = moved_content,
})

t.assert_eq(moved_claim.freshness, "reanchored", "unique moved matches should become reanchored")
t.assert_eq(moved_claim.start_line, 4, "reanchored claims should move to the unique exact match")
t.assert_eq(moved_claim.anchor, rebuilt_anchor, "reanchored claims should rebuild stored anchors from live content")
t.assert_eq(moved_summary.changed, true, "reanchoring should report a claim change")

local contextual_moved_content = "noise\ntarget()\nalpha\ntarget()\nomega\n"
local contextual_moved_claim = reset_state(live_path, unchanged_claim)
local contextual_summary = state.classify_file_claims(live_path, {
	content = contextual_moved_content,
})

t.assert_eq(contextual_moved_claim.freshness, "reanchored", "unique contextual matches should become reanchored even when exact text is duplicated")
t.assert_eq(contextual_moved_claim.start_line, 3, "contextual reanchoring should prefer the unique contextual match")
t.assert_eq(contextual_moved_claim.anchor, claims.build_content_anchor(contextual_moved_content, 3, 0, 3, 8), "contextual reanchoring should rebuild anchors from the chosen contextual match")
t.assert_eq(contextual_summary.changed, true, "contextual reanchoring should report a claim change")

local ambiguous_claim = reset_state(live_path, {
	id = "claim-ambiguous-live",
	kind = "question",
	start_line = 0,
	start_col = 11,
	end_line = 0,
	end_col = 19,
	note = "duplicate",
	anchor = {
		text = "target()",
		before = "if ok then ",
		after = " end",
	},
})
state.classify_file_claims(live_path, {
	content = "if ok then target() end\nif ok then target() end\n",
})

t.assert_eq(ambiguous_claim.freshness, "stale", "ambiguous live matches should stay stale")
t.assert_eq(ambiguous_claim.start_line, 0, "ambiguous live matches should keep the saved range")

local missing_claim = reset_state(live_path, unchanged_claim)
state.classify_file_claims(live_path, {
	content = "alpha\nchanged()\nomega\n",
})

t.assert_eq(missing_claim.freshness, "stale", "missing live matches should stay stale")
t.assert_eq(missing_claim.start_line, 1, "missing live matches should keep the saved range")

package.loaded["doubt"] = nil

local doubt = require("doubt")
local panel = require("doubt.panel")
local render = require("doubt.render")

local temp_state = vim.fs.joinpath(vim.fn.tempname(), "doubt-state.json")
local temp_file = vim.fs.joinpath(vim.fn.tempname(), "live-edit.lua")

vim.fn.mkdir(vim.fs.dirname(temp_state), "p")
vim.fn.mkdir(vim.fs.dirname(temp_file), "p")
vim.fn.writefile({ "alpha", "target()", "omega" }, temp_file)

local original_create_autocmd = vim.api.nvim_create_autocmd
local original_new_timer = vim.uv.new_timer
local original_schedule_wrap = vim.schedule_wrap

local registered_autocmds = {}
local created_timers = {}

vim.api.nvim_create_autocmd = function(events, opts)
	table.insert(registered_autocmds, {
		events = type(events) == "table" and vim.deepcopy(events) or { events },
		opts = opts,
	})
	return #registered_autocmds
end

vim.uv.new_timer = function()
	local timer = {
		start_calls = {},
		stop_calls = 0,
	}

	function timer:stop()
		self.stop_calls = self.stop_calls + 1
	end

	function timer:start(timeout, repeat_ms, callback)
		table.insert(self.start_calls, {
			timeout = timeout,
			repeat_ms = repeat_ms,
		})
		self.callback = callback
	end

	function timer:close()
		self.closed = true
	end

	function timer:fire()
		if self.callback then
			self.callback()
		end
	end

	table.insert(created_timers, timer)
	return timer
end

vim.schedule_wrap = function(callback)
	return callback
end

doubt.setup({
	keymaps = false,
	state_path = temp_state,
})

vim.api.nvim_create_autocmd = original_create_autocmd

local live_edit_autocmd
for _, entry in ipairs(registered_autocmds) do
	local events = entry.events or {}
	if vim.deep_equal(events, { "TextChanged", "TextChangedI" }) then
		live_edit_autocmd = entry
		break
	end
end

t.assert_eq(live_edit_autocmd ~= nil, true, "setup should register debounced live-edit autocmds")

local original_classify_file_claims = state.classify_file_claims
local original_save = state.save
local original_render_refresh_buffer = render.refresh_buffer
local original_render_refresh_visible_buffers = render.refresh_visible_buffers
local original_panel_render = panel.render

local classify_calls = {}
local save_calls = 0
local refresh_calls = 0
local bufnr

state.classify_file_claims = function(path, opts)
	table.insert(classify_calls, {
		path = path,
		content = opts and opts.content,
	})
	return {
		changed = true,
		claim_count = 1,
	}
end

state.save = function()
	save_calls = save_calls + 1
end

render.refresh_buffer = function(_, target_bufnr)
	refresh_calls = refresh_calls + 1
	t.assert_eq(target_bufnr, bufnr, "live edit refresh should target the edited buffer")
end

render.refresh_visible_buffers = function()
	refresh_calls = refresh_calls + 1
end

panel.render = function()
	refresh_calls = refresh_calls + 1
end

bufnr = vim.fn.bufadd(temp_file)
vim.fn.bufload(bufnr)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "alpha", "changed", "target()", "omega" })

live_edit_autocmd.opts.callback({ buf = bufnr })
live_edit_autocmd.opts.callback({ buf = bufnr })

t.assert_eq(created_timers[1] ~= nil, true, "live edits should allocate a debounce timer")
t.assert_eq(#created_timers, 1, "rapid edits in one buffer should reuse a single timer")
t.assert_eq(#created_timers[1].start_calls, 2, "each edit should reschedule the debounce timer")
t.assert_eq(created_timers[1].stop_calls >= 1, true, "rescheduling should stop the in-flight timer first")

created_timers[1]:fire()

t.assert_match(classify_calls[1].path, "live%-edit%.lua$", "live edit callback should classify the edited file only")
t.assert_match(classify_calls[1].content, "changed\ntarget%(%)", "live edit callback should classify using current buffer text")
t.assert_eq(save_calls, 1, "live edit callback should persist changed claims once")
t.assert_eq(refresh_calls, 3, "live edit callback should refresh the current buffer, visible buffers, and panel after changed claims")

state.classify_file_claims = function()
	return {
		changed = false,
		claim_count = 0,
	}
end

live_edit_autocmd.opts.callback({ buf = bufnr })
created_timers[1]:fire()

t.assert_eq(save_calls, 1, "no-op live edits should not save state")
t.assert_eq(refresh_calls, 3, "no-op live edits should not refresh the UI")

state.classify_file_claims = original_classify_file_claims
state.save = original_save
render.refresh_buffer = original_render_refresh_buffer
render.refresh_visible_buffers = original_render_refresh_visible_buffers
panel.render = original_panel_render
vim.uv.new_timer = original_new_timer
vim.schedule_wrap = original_schedule_wrap
vim.bo[bufnr].modified = false
