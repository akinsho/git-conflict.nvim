local M = {}

local api = vim.api
local fn = vim.fn

local color = require('git-conflict.colors')

local SIDES = { ours = 'ours', theirs = 'theirs' }
local AUGROUP_NAME = 'GitConflictCommands'
local CURRENT_LABEL_HL = 'GitConflictCurrentLabel'
local INCOMING_LABEL_HL = 'GitConflictIncomingLabel'
local NAMESPACE = api.nvim_create_namespace('git-conflict')
local PRIORITY = vim.highlight.priorities.user

local conflict_start = '^<<<<<<<'
local conflict_middle = '^======='
local conflict_end = '^>>>>>>>'

local config = {
  highlights = {
    current = 'DiffAdd',
    incoming = 'DiffText',
  },
}

-- Buffers that have been previously checked for conflicts and the saved tick at the time we last
-- checked
local visited_buffers = {}

---Add the positions to the buffer in our in memory buffer list
---positions are keyed by a list of range start and end for each mark
---@param buf number
---@param positions table[]
local function update_visited_buffers(buf, positions)
  local buf_positions = {}
  visited_buffers[buf].positions = buf_positions
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

---Derive the colour of the section label highlights based on each sections highlights
---@param current string
---@param incoming string
local function set_label_highlights(current, incoming)
  local current_color = api.nvim_get_hl_by_name(current, true)
  local incoming_color = api.nvim_get_hl_by_name(incoming, true)
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

local function detect_conflicts(lines)
  local positions = {}
  local position, has_conflict, has_start, has_middle, has_end = nil, false, false, false, false
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
      has_end = true
      position.incoming.range_end = lnum
      position.incoming.content_end = lnum - 1
      positions[#positions + 1] = position
      has_conflict = has_start and has_middle and has_end

      position, has_start, has_middle, has_end = nil, false, false, false
    end
  end
  return has_conflict, positions
end

---Retrieves a conflict marker position by checking the visited buffers for a supported range
---each mark is keyed by it's starting and ending position so we loop through a buffers marks to
---see if the line number is withing a certain marks range
---@param bufnr number
---@return table?
local function get_current_position(bufnr)
  local match = visited_buffers[api.nvim_buf_get_name(bufnr)]
  if not match then
    return
  end
  local line = fn.line('.')
  for k, v in pairs(match.positions) do
    if type(k) == 'table' and k[1] <= line and k[2] >= line then
      return v
    end
  end
end

local function parse_buffer(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local has_conflict, positions = detect_conflicts(lines)
  if has_conflict then
    highlight_conflicts(positions, lines)
    update_visited_buffers(api.nvim_buf_get_name(bufnr), positions)
  end
end

local function attach()
  local bufnr = api.nvim_get_current_buf()
  local cur_buf = api.nvim_buf_get_name(bufnr)
  if
    not visited_buffers[cur_buf]
    or (visited_buffers[cur_buf] and visited_buffers[cur_buf].tick ~= vim.b.changedtick)
  then
    if not visited_buffers[cur_buf] then
      visited_buffers[cur_buf] = {}
    end
    visited_buffers[cur_buf].tick = vim.b.changedtick
    parse_buffer(bufnr)
  end
end

function M.choose(side)
  local position = get_current_position(api.nvim_get_current_buf())
  if not position then
    return
  end
  local pos_start, pos_end, content_start, content_end
  if side == SIDES.ours then
    pos_start = position.current.range_start - 1
    pos_start = pos_start < 0 and 0 or pos_start
    pos_end = position.middle.range_end + 1
    content_start = position.current.content_start
    content_end = position.current.content_end
  else
    pos_start = position.middle.range_start
    pos_end = position.incoming.range_end + 1
    content_start = position.incoming.content_start
    content_end = position.incoming.content_end
  end
  local lines = api.nvim_buf_get_lines(0, content_start, content_end + 1, false)
  api.nvim_buf_set_lines(0, pos_start, pos_end, false, lines)
  parse_buffer(0)
end

function M.clear()
  api.nvim_buf_clear_namespace(0, NAMESPACE, 0, -1)
end

function M.setup(user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})

  set_label_highlights(config.highlights.current, config.highlights.incoming)

  local id = api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
  api.nvim_create_autocmd('BufEnter', {
    group = id,
    pattern = '*',
    callback = attach,
  })
end

return M
