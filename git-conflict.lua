local M = {}

local api = vim.api

local color = require('git-conflict.colors')

local AUGROUP_NAME = 'GitConflictCommands'
local NAMESPACE = api.nvim_create_namespace('git-conflict')
local PRIORITY = vim.highlight.priorities.user
local CURRENT_LABEL_HL = 'GitConflictCurrentLabel'
local INCOMING_LABEL_HL = 'GitConflictIncomingLabel'

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
local function hl_range(bufnr, hl, range_start, range_end)
  api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_start, 0, {
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
local function draw_section_label(bufnr, hl_group, label, lnum)
  local remaining_space = api.nvim_win_get_width(0) - api.nvim_strwidth(label)
  api.nvim_buf_set_extmark(bufnr, NAMESPACE, lnum, 0, {
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

    draw_section_label(bufnr, CURRENT_LABEL_HL, current_label, current_start)
    hl_range(bufnr, config.highlights.current, current_start, current_end + 1)
    hl_range(bufnr, config.highlights.incoming, incoming_start, incoming_end)
    draw_section_label(bufnr, INCOMING_LABEL_HL, incoming_label, incoming_end)
  end
end

local function check_for_conflicts(lines)
  local positions = {}
  local has_conflict = false
  local position
  for index, line in ipairs(lines) do
    local lnum = index - 1
    if line:match(conflict_start) then
      position = { current = {}, incoming = {} }
      has_conflict = true
      position.current.range_start = lnum
    end
    if line:match(conflict_middle) then
      position.current.range_end = lnum - 1
      position.incoming.range_start = lnum + 1
    end
    if line:match(conflict_end) then
      position.incoming.range_end = lnum
      positions[#positions + 1] = position
      position = nil
    end
  end
  return has_conflict, positions
end

  local bufnr = api.nvim_get_current_buf()
  local cur_buf = api.nvim_buf_get_name(bufnr)
  if
    not visited_buffers[cur_buf]
    or (visited_buffers[cur_buf] and visited_buffers[cur_buf] ~= vim.b.changedtick)
  then
    visited_buffers[cur_buf] = vim.b.changedtick
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_conflict, positions = check_for_conflicts(lines)
    if has_conflict then
      highlight_conflicts(positions, config)
    end
  end
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
