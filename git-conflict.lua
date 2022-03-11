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

-- Buffers that have been previously checked for conflicts and the saved tick at the time we last
-- checked
local visited_buffers = {}

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

local function draw_section_label(bufnr, hl_group, label, lnum)
  local win_width = api.nvim_win_get_width(0)
  local remaining_space = win_width - #label
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
---@param config table
local function highlight_conflicts(positions, config)
  local bufnr = api.nvim_get_current_buf()
  api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  local current_start = positions.current.range_start
  local current_end = positions.current.range_end
  local incoming_start = positions.incoming.range_start
  local incoming_end = positions.incoming.range_end

  draw_section_label(bufnr, CURRENT_LABEL_HL, '>>>>>>>>> Current changes', current_start)
  hl_range(bufnr, config.highlights.current, current_start, current_end + 1)
  hl_range(bufnr, config.highlights.incoming, incoming_start, incoming_end)
  draw_section_label(bufnr, INCOMING_LABEL_HL, 'Incoming changes <<<<<<<<', incoming_end)
end

local function check_for_conflicts(bufnr)
  local positions = { current = {}, incoming = {} }
  local has_conflict = false
  for index, line in ipairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local lnum = index - 1
    if line:match(conflict_start) then
      has_conflict = true
      positions.current.range_start = lnum
    end
    if line:match(conflict_middle) then
      positions.current.range_end = lnum - 1
      positions.incoming.range_start = lnum + 1
    end
    if line:match(conflict_end) then
      positions.incoming.range_end = lnum
    end
  end
  return has_conflict, positions
end

local function attach(config)
  local bufnr = api.nvim_get_current_buf()
  local cur_buf = api.nvim_buf_get_name(bufnr)
  if
    not visited_buffers[cur_buf]
    or (visited_buffers[cur_buf] and visited_buffers[cur_buf] ~= vim.b.changedtick)
  then
    visited_buffers[cur_buf] = vim.b.changedtick
    local has_conflict, positions = check_for_conflicts(bufnr)
    if has_conflict then
      highlight_conflicts(positions, config)
    end
  end
end

function M.setup()
  local config = {
    highlights = {
      current = 'DiffAdd',
      incoming = 'DiffText',
    },
  }
  set_label_highlights(config.highlights.current, config.highlights.incoming)

  local id = api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
  api.nvim_create_autocmd('BufEnter', {
    group = id,
    pattern = '*',
    callback = function()
      attach(config)
    end,
  })
end

return M
