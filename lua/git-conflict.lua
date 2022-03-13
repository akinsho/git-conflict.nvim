local M = {}

local api = vim.api

local color = require('git-conflict.colors')

-----------------------------------------------------------------------------//
-- Types
-----------------------------------------------------------------------------//

---@alias ConflictSide "'ours'"|"'theirs'"|"'both'"

--- @class ConflictHighlights
--- @field current string
--- @field incoming string

--- @class ConflictPosition
--- @field incoming table
--- @field middle table
--- @field current table

--- @class ConflictBufferCache
--- @field lines table<number, boolean> map of conflicted line numbers
--- @field positions ConflictPosition[]
--- @field tick number

-----------------------------------------------------------------------------//
-- Constants
-----------------------------------------------------------------------------//
local SIDES = {
  ours = 'ours',
  theirs = 'theirs',
  both = 'both',
}
local CURRENT_LABEL_HL = 'GitConflictCurrentLabel'
local INCOMING_LABEL_HL = 'GitConflictIncomingLabel'
local NAMESPACE = api.nvim_create_namespace('git-conflict')
local PRIORITY = vim.highlight.priorities.user

local conflict_start = '^<<<<<<<'
local conflict_middle = '^======='
local conflict_end = '^>>>>>>>'
-----------------------------------------------------------------------------//

local config = {
  disable_diagnostics = false,
  highlights = {
    current = 'DiffText',
    incoming = 'DiffAdd',
  },
}

-- Buffers that have been previously checked for conflicts and the saved tick at the time we last
-- checked
--- @type table<string, ConflictBufferCache>
local visited_buffers = setmetatable({}, {
  __index = function(t, k)
    if type(k) == 'number' then
      return t[api.nvim_buf_get_name(k)]
    end
  end,
})

---Wrapper around `api.nvim_buf_get_lines` which defaults to the current buffer
---@param start number
---@param _end number
---@param buf number
---@return string[]
local function get_buf_lines(start, _end, buf)
  return api.nvim_buf_get_lines(buf or 0, start, _end, false)
end

---Get cursor row and column as (1, 0) based
---@param win_id number?
---@return number, number
local function get_cursor_pos(win_id)
  return unpack(api.nvim_win_get_cursor(win_id or 0))
end

---Add the positions to the buffer in our in memory buffer list
---positions are keyed by a list of range start and end for each mark
---@param buf number
---@param positions ConflictPosition[]
---@param conflicts table<string, boolean>
local function update_visited_buffers(buf, positions, conflicts)
  if not buf or not api.nvim_buf_is_valid(buf) then
    return
  end
  local buf_positions = {}
  local name = api.nvim_buf_get_name(buf)
  visited_buffers[name] = visited_buffers[name] or {}
  visited_buffers[name].tick = vim.b[buf].changedtick
  visited_buffers[name].positions = buf_positions
  visited_buffers[name].lines = conflicts
  for _, pos in ipairs(positions) do
    buf_positions[{ pos.current.range_start, pos.incoming.range_end }] = pos
  end
end

---Set an extmark for each section of the git conflict
---@param bufnr number
---@param hl string
---@param range_start number
---@param range_end number
---@return number extmark_id
local function hl_range(bufnr, hl, range_start, range_end)
  return api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_start, 0, {
    hl_group = hl,
    hl_eol = true,
    hl_mode = 'combine',
    end_row = range_end,
    priority = PRIORITY,
  })
end

---Add highlights and additional data to each section heading of the conflict marker
---These works by covering the underlying text with an extmark that contains the same information
---with some extra detail appended.
---TODO: ideally this could be done by using virtual text at the EOL and highlighting the
---background but this doesn't work and currently this is done by filling the rest of the line with
---empty space and overlaying the line content
---@param bufnr number
---@param hl_group string
---@param label string
---@param lnum number
---@return number extmark id
local function draw_section_label(bufnr, hl_group, label, lnum)
  local remaining_space = api.nvim_win_get_width(0) - api.nvim_strwidth(label)
  return api.nvim_buf_set_extmark(bufnr, NAMESPACE, lnum, 0, {
    hl_group = hl_group,
    virt_text = { { label .. string.rep(' ', remaining_space), hl_group } },
    virt_text_pos = 'overlay',
    priority = PRIORITY,
  })
end

local function set_commands()
  vim.cmd([[
    command! GitConflictChooseOurs lua require('git-conflict').choose('ours')
    command! GitConflictChooseTheirs lua require('git-conflict').choose('theirs')
    command! GitConflictChooseBoth lua require('git-conflict').choose('both')
    command! GitConflictNextConflict lua require('git-conflict').find_next('ours')
    command! GitConflictPrevConflict lua require('git-conflict').find_prev('ours')
  ]])
end

---Derive the colour of the section label highlights based on each sections highlights
---@param highlights ConflictHighlights
local function set_highlights(highlights)
  local current_color = api.nvim_get_hl_by_name(highlights.current, true)
  local incoming_color = api.nvim_get_hl_by_name(highlights.incoming, true)
  local current_label_bg = color.shade_color(current_color.background, -10)
  local incoming_label_bg = color.shade_color(incoming_color.background, -10)
  api.nvim_set_hl(0, CURRENT_LABEL_HL, { background = current_label_bg, bold = true })
  api.nvim_set_hl(0, INCOMING_LABEL_HL, { background = incoming_label_bg, bold = true })
end

---Highlight each part of a git conflict i.e. the incoming changes vs the current/HEAD changes
---@param positions table
---@param lines string[]
local function highlight_conflicts(positions, lines)
  local bufnr = api.nvim_get_current_buf()
  api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)

  for _, position in ipairs(positions) do
    local current_start = position.current.range_start
    local current_end = position.current.range_end
    local incoming_start = position.incoming.range_start
    local incoming_end = position.incoming.range_end
    -- Add one since the index access in lines is 1 based
    local current_label = lines[current_start + 1] .. ' (Current changes)'
    local incoming_label = lines[incoming_end + 1] .. ' (Incoming changes)'

    local curr_label_id = draw_section_label(bufnr, CURRENT_LABEL_HL, current_label, current_start)
    local curr_id = hl_range(bufnr, config.highlights.current, current_start, current_end + 1)
    local inc_id = hl_range(bufnr, config.highlights.incoming, incoming_start, incoming_end)
    local inc_label_id = draw_section_label(bufnr, INCOMING_LABEL_HL, incoming_label, incoming_end)

    position.marks = {
      current = { label = curr_label_id, content = curr_id },
      incoming = { label = inc_label_id, content = inc_id },
    }
  end
end

---Iterate through the buffer line by line checking there is a matching conflict marker
---when we find a starting mark we collect the position details and add it to a list of positions
---@param lines string[]
---@return boolean
---@return ConflictPosition[]
---@return table<number, boolean>
local function detect_conflicts(lines)
  local positions = {}
  -- A mapping of line number to bool for lines that have conflicts on them
  -- allowing an O(1) check if a line is conflicted
  local line_map = {}
  local position, has_start, has_middle = nil, false, false
  for index, line in ipairs(lines) do
    local lnum = index - 1
    if line:match(conflict_start) then
      has_start = true
      position = {
        current = { range_start = lnum, content_start = lnum + 1 },
        middle = {},
        incoming = {},
      }
    end
    if has_start and line:match(conflict_middle) then
      has_middle = true
      position.middle.range_start = lnum
      position.middle.range_end = lnum + 1
      position.current.range_end = lnum - 1
      position.current.content_end = lnum - 1
      position.incoming.range_start = lnum + 1
      position.incoming.content_start = lnum + 1
    end
    if has_start and has_middle and line:match(conflict_end) then
      position.incoming.range_end = lnum
      position.incoming.content_end = lnum - 1
      positions[#positions + 1] = position
      line_map[index] = true

      position, has_start, has_middle = nil, false, false
    end
    if position then
      line_map[index] = true
    end
  end
  return #positions > 0, positions, line_map
end

---Helper function to find a conflict position based on a comparator function
---@param bufnr number
---@param comparator number
---@return ConflictPosition
local function find_position(bufnr, comparator)
  local match = visited_buffers[bufnr]
  if not match then
    return
  end
  local line = get_cursor_pos()
  for range, position in pairs(match.positions) do
    if type(range) == 'table' and comparator(line, range, position) then
      return position
    end
  end
end
---Retrieves a conflict marker position by checking the visited buffers for a supported range
---each mark is keyed by it's starting and ending position so we loop through a buffers marks to
---see if the line number is within a certain marks range
---@param bufnr number
---@return table?
local function get_current_position(bufnr)
  return find_position(bufnr, function(line, range, _)
    return range[1] <= line and range[2] >= line
  end)
end

---@param pos ConflictPosition
---@param side ConflictSide
local function set_cursor(pos, side)
  if pos then
    local target = side == SIDES.ours and pos.current
      or side == SIDES.theirs and pos.incoming
      or pos.middle
    api.nvim_win_set_cursor(0, { target.range_start + 1, 0 })
  end
end

---@param bufnr number
---@param has_conflict boolean
local function toggle_diagnostics(bufnr, has_conflict)
  if has_conflict then
    vim.diagnostic.disable(bufnr)
  else
    vim.diagnostic.enable(bufnr)
  end
end

---Get the conflict marker positions for a buffer if any and update the buffers state
---@param bufnr number
local function parse_buffer(bufnr, range_start, range_end)
  local lines = get_buf_lines(range_start or 0, range_end or -1, bufnr)
  local has_conflict, positions, line_conflicts = detect_conflicts(lines)
  update_visited_buffers(bufnr, positions, line_conflicts)
  if has_conflict then
    highlight_conflicts(positions, lines)
  end
  if config.disable_diagnostics then
    toggle_diagnostics(bufnr, has_conflict)
  end
end

---Process a buffer if the changed tick has changed
---@param bufnr number?
local function process(bufnr, range_start, range_end)
  bufnr = bufnr or api.nvim_get_current_buf()
  if visited_buffers[bufnr] and visited_buffers[bufnr].tick == vim.b[bufnr].changedtick then
    return
  end
  parse_buffer(bufnr, range_start, range_end)
end

function M.setup(user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})

  set_highlights(config.highlights)
  set_commands()

  api.nvim_set_decoration_provider(NAMESPACE, {
    -- TODO: find a way to throttle how often
    -- this is called. We want to be able to undo
    -- a conflict resolution and have the markers
    -- re-appear but the tradeoff is re-parsing the visible
    -- section of the file
    -- how do we know what the set of conflicted buffers are?
    -- can we depend on a list we know ahead of time? what if the user merges whilst
    -- in nvim?
    on_win = function(_, _, bufnr, topline, botline)
      process(bufnr, topline, botline)
    end,
  })
end

function M.clear()
  api.nvim_buf_clear_namespace(0, NAMESPACE, 0, -1)
end

---@param side ConflictSide
function M.find_next(side)
  local pos = find_position(0, function(line, range, _)
    return range[1] >= line and range[2] >= line
  end)
  set_cursor(pos, side)
end

---@param side ConflictSide
function M.find_prev(side)
  local pos = find_position(0, function(line, range, _)
    return range[1] <= line and range[2] <= line
  end)
  set_cursor(pos, side)
end

---Select the changes to keep
---@param side ConflictSide
function M.choose(side)
  local bufnr = api.nvim_get_current_buf()
  local position = get_current_position(bufnr)
  if not position then
    return
  end
  local lines = {}
  if side == SIDES.ours or side == SIDES.theirs then
    local data = side == SIDES.ours and position.current or position.incoming
    lines = get_buf_lines(data.content_start, data.content_end + 1)
  elseif side == SIDES.both then
    local first = get_buf_lines(position.current.content_start, position.current.content_end + 1)
    local second = get_buf_lines(position.incoming.content_start, position.incoming.content_end + 1)
    lines = vim.list_extend(first, second)
  else
    return
  end

  local pos_start = position.current.range_start < 0 and 0 or position.current.range_start
  local pos_end = position.incoming.range_end + 1

  api.nvim_buf_set_lines(0, pos_start, pos_end, false, lines)
  api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.incoming.label)
  api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.current.label)
  parse_buffer(bufnr)
end

return M
