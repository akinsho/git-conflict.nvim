local M = {}

local color = require('git-conflict.colors')
local utils = require('git-conflict.utils')

local fn = vim.fn
local api = vim.api
local fmt = string.format
local map = vim.keymap.set
local job = utils.job
-----------------------------------------------------------------------------//
-- REFERENCES:
-----------------------------------------------------------------------------//
-- Detecting the state of a git repository based on files in the .git directory.
-- https://stackoverflow.com/questions/49774200/how-to-tell-if-my-git-repo-is-in-a-conflict
-- git diff commands to git a list of conflicted files
-- https://stackoverflow.com/questions/3065650/whats-the-simplest-way-to-list-conflicted-files-in-git
-- how to show a full path for files in a git diff command
-- https://stackoverflow.com/questions/10459374/making-git-diff-stat-show-full-file-path
-- Advanced merging
-- https://git-scm.com/book/en/v2/Git-Tools-Advanced-Merging

-----------------------------------------------------------------------------//
-- Types
-----------------------------------------------------------------------------//

---@alias ConflictSide "'ours'"|"'theirs'"|"'both'"|"'base'"|"'none'"

--- @class ConflictHighlights
--- @field current string
--- @field incoming string
--- @field ancestor string?

---@class RangeMark
---@field label integer
---@field content string

--- @class PositionMarks
--- @field current RangeMark
--- @field incoming RangeMark
--- @field ancestor RangeMark

--- @class Range
--- @field range_start integer
--- @field range_end integer
--- @field content_start integer
--- @field content_end integer

--- @class ConflictPosition
--- @field incoming Range
--- @field middle Range
--- @field current Range
--- @field marks PositionMarks

--- @class ConflictBufferCache
--- @field lines table<integer, boolean> map of conflicted line numbers
--- @field positions ConflictPosition[]
--- @field tick integer
--- @field bufnr integer

--- @class GitConflictMappings
--- @field ours string
--- @field theirs string
--- @field none string
--- @field both string
--- @field next string
--- @field prev string

--- @class GitConflictConfig
--- @field default_mappings GitConflictMappings
--- @field default_commands boolean
--- @field disable_diagnostics boolean
--- @field list_opener string|function
--- @field highlights ConflictHighlights
--- @field debug boolean

--- @class GitConflictUserConfig
--- @field default_mappings? boolean|GitConflictMappings
--- @field default_commands? boolean
--- @field disable_diagnostics? boolean
--- @field list_opener? string|function
--- @field highlights? ConflictHighlights
--- @field debug? boolean

-----------------------------------------------------------------------------//
-- Constants
-----------------------------------------------------------------------------//
local SIDES = {
  OURS = 'ours',
  THEIRS = 'theirs',
  BOTH = 'both',
  BASE = 'base',
  NONE = 'none',
}

-- A mapping between the internal names and the display names
local name_map = {
  ours = 'current',
  theirs = 'incoming',
  base = 'ancestor',
  both = 'both',
  none = 'none',
}

local CURRENT_HL = 'GitConflictCurrent'
local INCOMING_HL = 'GitConflictIncoming'
local ANCESTOR_HL = 'GitConflictAncestor'
local CURRENT_LABEL_HL = 'GitConflictCurrentLabel'
local INCOMING_LABEL_HL = 'GitConflictIncomingLabel'
local ANCESTOR_LABEL_HL = 'GitConflictAncestorLabel'
local PRIORITY = vim.highlight.priorities.user
local NAMESPACE = api.nvim_create_namespace('git-conflict')
local AUGROUP_NAME = 'GitConflictCommands'

local sep = package.config:sub(1, 1)
local IS_WINDOWS = sep ~= '/'

local conflict_start = '^<<<<<<<'
local conflict_middle = '^======='
local conflict_end = '^>>>>>>>'
local conflict_ancestor = '^|||||||'

local DEFAULT_CURRENT_BG_COLOR = 4218238  -- #405d7e
local DEFAULT_INCOMING_BG_COLOR = 3229523 -- #314753
local DEFAULT_ANCESTOR_BG_COLOR = 6824314 -- #68217A
-----------------------------------------------------------------------------//

--- @type GitConflictMappings
local DEFAULT_MAPPINGS = {
  ours = 'co',
  theirs = 'ct',
  none = 'c0',
  both = 'cb',
  next = ']x',
  prev = '[x',
}

--- @type GitConflictConfig
local config = {
  debug = false,
  default_mappings = DEFAULT_MAPPINGS,
  default_commands = true,
  disable_diagnostics = false,
  list_opener = 'copen',
  highlights = {
    current = 'DiffText',
    incoming = 'DiffAdd',
    ancestor = nil,
  },
}

--- @return table<string, ConflictBufferCache>
local function create_visited_buffers()
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) == 'number' then return t[api.nvim_buf_get_name(k)] end
    end,
  })
end

--- A list of buffers that have conflicts in them. This is derived from
--- git using the diff command, and updated at intervals
local visited_buffers = create_visited_buffers()

local state = {
  ---@type string?
  current_watcher_dir = nil,
}

-----------------------------------------------------------------------------//

---Get full path to the repository of the directory passed in
---@param dir any
---@param callback fun(data: string)
local function get_git_root(dir, callback)
  job({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, function(data) callback(data[1]) end)
end

--- Get a list of the conflicted files within the specified directory
--- NOTE: only conflicted files within the git repository of the directory passed in are returned
--- also we add a line prefix to the git command so that the full path is returned
--- e.g. --line-prefix=`git rev-parse --show-toplevel`
---@reference: https://stackoverflow.com/a/10874862
---@param dir string?
---@param callback fun(files: table<string, integer[]>, string)
local function get_conflicted_files(dir, callback)
  local cmd = { 'git', '-C', dir, 'diff', ('--line-prefix=%s%s'):format(dir, sep), '--name-only', '--diff-filter=U' }
  job(cmd, function(data)
    local files = {}
    for _, filename in ipairs(data) do
      if IS_WINDOWS then filename = filename:gsub('/', sep) end
      if #filename > 0 then files[filename] = files[filename] or {} end
    end
    callback(files, dir)
  end)
end

---Add the positions to the buffer in our in memory buffer list
---positions are keyed by a list of range start and end for each mark
---@param buf integer
---@param positions ConflictPosition[]
local function update_visited_buffers(buf, positions)
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  local name = api.nvim_buf_get_name(buf)
  -- If this buffer is not in the list
  if not visited_buffers[name] then return end
  visited_buffers[name].bufnr = buf
  visited_buffers[name].tick = vim.b[buf].changedtick
  visited_buffers[name].positions = positions
end

---Set an extmark for each section of the git conflict
---@param bufnr integer
---@param hl string
---@param range_start integer
---@param range_end integer
---@return integer? extmark_id
local function hl_range(bufnr, hl, range_start, range_end)
  if not range_start or not range_end then return end
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
---@param bufnr integer
---@param hl_group string
---@param label string
---@param lnum integer
---@return integer extmark id
local function draw_section_label(bufnr, hl_group, label, lnum)
  local remaining_space = api.nvim_win_get_width(0) - api.nvim_strwidth(label)
  return api.nvim_buf_set_extmark(bufnr, NAMESPACE, lnum, 0, {
    hl_group = hl_group,
    virt_text = { { label .. string.rep(' ', remaining_space), hl_group } },
    virt_text_pos = 'overlay',
    priority = PRIORITY,
  })
end

---Highlight each part of a git conflict i.e. the incoming changes vs the current/HEAD changes
---TODO: should extmarks be ephemeral? or is it less expensive to save them and only re-apply
---them when a buffer changes since otherwise we have to reparse the whole buffer constantly
---@param positions table
---@param lines string[]
local function highlight_conflicts(positions, lines)
  local bufnr = api.nvim_get_current_buf()
  M.clear(bufnr)

  for _, position in ipairs(positions) do
    local current_start = position.current.range_start
    local current_end = position.current.range_end
    local incoming_start = position.incoming.range_start
    local incoming_end = position.incoming.range_end
    -- Add one since the index access in lines is 1 based
    local current_label = lines[current_start + 1] .. ' (Current changes)'
    local incoming_label = lines[incoming_end + 1] .. ' (Incoming changes)'

    local curr_label_id = draw_section_label(bufnr, CURRENT_LABEL_HL, current_label, current_start)
    local curr_id = hl_range(bufnr, CURRENT_HL, current_start, current_end + 1)
    local inc_id = hl_range(bufnr, INCOMING_HL, incoming_start, incoming_end + 1)
    local inc_label_id = draw_section_label(bufnr, INCOMING_LABEL_HL, incoming_label, incoming_end)

    position.marks = {
      current = { label = curr_label_id, content = curr_id },
      incoming = { label = inc_label_id, content = inc_id },
      ancestor = {},
    }
    if not vim.tbl_isempty(position.ancestor) then
      local ancestor_start = position.ancestor.range_start
      local ancestor_end = position.ancestor.range_end
      local ancestor_label = lines[ancestor_start + 1] .. ' (Base changes)'
      local id = hl_range(bufnr, ANCESTOR_HL, ancestor_start + 1, ancestor_end + 1)
      local label_id = draw_section_label(bufnr, ANCESTOR_LABEL_HL, ancestor_label, ancestor_start)
      position.marks.ancestor = { label = label_id, content = id }
    end
  end
end

---Iterate through the buffer line by line checking there is a matching conflict marker
---when we find a starting mark we collect the position details and add it to a list of positions
---@param lines string[]
---@return boolean
---@return ConflictPosition[]
local function detect_conflicts(lines)
  local positions = {}
  local position, has_start, has_middle, has_ancestor = nil, false, false, false
  for index, line in ipairs(lines) do
    local lnum = index - 1
    if line:match(conflict_start) then
      has_start = true
      position = {
        current = { range_start = lnum, content_start = lnum + 1 },
        middle = {},
        incoming = {},
        ancestor = {},
      }
    end
    if has_start and line:match(conflict_ancestor) then
      has_ancestor = true
      position.ancestor.range_start = lnum
      position.ancestor.content_start = lnum + 1
      position.current.range_end = lnum - 1
      position.current.content_end = lnum - 1
    end
    if has_start and line:match(conflict_middle) then
      has_middle = true
      if has_ancestor then
        position.ancestor.content_end = lnum - 1
        position.ancestor.range_end = lnum - 1
      else
        position.current.range_end = lnum - 1
        position.current.content_end = lnum - 1
      end
      position.middle.range_start = lnum
      position.middle.range_end = lnum + 1
      position.incoming.range_start = lnum + 1
      position.incoming.content_start = lnum + 1
    end
    if has_start and has_middle and line:match(conflict_end) then
      position.incoming.range_end = lnum
      position.incoming.content_end = lnum - 1
      positions[#positions + 1] = position

      position, has_start, has_middle, has_ancestor = nil, false, false, false
    end
  end
  return #positions > 0, positions
end

---Helper function to find a conflict position based on a comparator function
---@param bufnr integer
---@param comparator fun(string, integer): boolean
---@param opts table?
---@return ConflictPosition?
local function find_position(bufnr, comparator, opts)
  local match = visited_buffers[bufnr]
  if not match then return end
  local line = utils.get_cursor_pos()
  line = line - 1 -- Convert to 0-based for position comparison

  if opts and opts.reverse then
    for i = #match.positions, 1, -1 do
      local position = match.positions[i]
      if comparator(line, position) then return position end
    end
    if opts.wrap and match.positions[#match.positions] then
      return match.positions[#match.positions]
    end
    return nil
  end

  for _, position in ipairs(match.positions) do
    if comparator(line, position) then return position end
  end

  if opts and opts.wrap and match.positions[1] then return match.positions[1] end
  return nil
end

---Retrieves a conflict marker position by checking the visited buffers for a supported range
---@param bufnr integer
---@return ConflictPosition?
local function get_current_position(bufnr)
  return find_position(
    bufnr,
    function(line, position)
      return position.current.range_start <= line and position.incoming.range_end >= line
    end
  )
end

---@param position ConflictPosition?
---@param side ConflictSide
local function set_cursor(position, side)
  if not position then return end
  local target = side == SIDES.OURS and position.current or position.incoming
  api.nvim_win_set_cursor(0, { target.range_start + 1, 0 })
end

---Get the conflict marker positions for a buffer if any and update the buffers state
---@param bufnr integer
---@param range_start integer
---@param range_end integer
local function parse_buffer(bufnr, range_start, range_end)
  local lines = utils.get_buf_lines(range_start or 0, range_end or -1, bufnr)
  local prev_conflicts = visited_buffers[bufnr].positions ~= nil
      and #visited_buffers[bufnr].positions > 0
  local has_conflict, positions = detect_conflicts(lines)

  update_visited_buffers(bufnr, positions)
  if has_conflict then
    highlight_conflicts(positions, lines)
  else
    M.clear(bufnr)
  end
  if prev_conflicts ~= has_conflict or not vim.b[bufnr].conflict_mappings_set then
    local pattern = has_conflict and 'GitConflictDetected' or 'GitConflictResolved'
    api.nvim_exec_autocmds('User', { pattern = pattern })
  end
end

--- Fetch the conflicted files for the current buffer file's repo
--- this is throttled by tracking when last we checked for conflicts
--- and if it is over this interval we check again otherwise we return.
--- When clearing only clear buffers that are in the same repository as the conflicted files
--- as the result (files) might contain only files from a buffer in
--- a different repository in which case extmarks could be cleared for unrelated projects
local function fetch_conflicts(buf)
  buf = (buf and api.nvim_buf_is_valid(buf)) and buf or api.nvim_get_current_buf()
  get_git_root(fn.fnamemodify(api.nvim_buf_get_name(buf), ':h'), function(git_root)
    get_conflicted_files(git_root, function(files, repo)
      for name, b in pairs(visited_buffers) do
        -- FIXME: this will not work for nested repositories
        if vim.startswith(name, repo) and not files[name] and b.bufnr then
          visited_buffers[name] = nil
          M.clear(b.bufnr)
        end
      end
      for path, _ in pairs(files) do
        visited_buffers[path] = visited_buffers[path] or {}
      end
    end)
  end)
end

---@type table<string, userdata>
local watchers = {}

local on_throttled_change = utils.throttle(1000, function(dir, err, change)
  if err then return utils.notify(fmt('Error watching %s(%s): %s', dir, err, change), 'error') end
  if config.debug then utils.notify(fmt('Watching %s - change: %s ', dir, change), 'info') end
  fetch_conflicts()
end)

--- Stop any watchers that aren't for the current project
---@param curr_dir string
local function stop_running_watchers(curr_dir)
  for prev_dir, watcher in pairs(watchers) do
    if watcher ~= watchers[curr_dir] then
      watcher:stop()
      watchers[prev_dir] = nil
    end
  end
end

--- Create a FS watcher for the current git directory or restart an existing one
---@param dir string
local function watch_gitdir(dir)
  -- Stop if there is already a watcher running
  if watchers[dir] then return end

  ---@type userdata
  watchers[dir] = vim.loop.new_fs_event()
  watchers[dir]:start(
    dir,
    { recursive = true },
    vim.schedule_wrap(function(...) on_throttled_change(dir, ...) end)
  )
  state.current_watcher_dir = dir
end

local throttled_watcher = utils.throttle(1000, watch_gitdir)

---Process a buffer if the changed tick has changed
---@param bufnr integer?
local function process(bufnr, range_start, range_end)
  bufnr = bufnr or api.nvim_get_current_buf()
  if visited_buffers[bufnr] and visited_buffers[bufnr].tick == vim.b[bufnr].changedtick then
    return
  end
  parse_buffer(bufnr, range_start, range_end)
end

-----------------------------------------------------------------------------//
-- Commands
-----------------------------------------------------------------------------//

local function set_commands()
  local command = api.nvim_create_user_command
  command('GitConflictRefresh', function() fetch_conflicts() end, { nargs = 0 })
  command('GitConflictListQf', function()
    M.conflicts_to_qf_items(function(items)
      if #items > 0 then
        fn.setqflist(items, 'r')
        if type(config.list_opener) == 'function' then
          config.list_opener()
        else
          vim.cmd(config.list_opener)
        end
      end
    end)
  end, { nargs = 0 })
  command('GitConflictChooseOurs', '<Plug>(git-conflict-ours)', { nargs = 0 })
  command('GitConflictChooseTheirs', '<Plug>(git-conflict-theirs)', { nargs = 0 })
  command('GitConflictChooseBoth', '<Plug>(git-conflict-both)', { nargs = 0 })
  command('GitConflictChooseBase', '<Plug>(git-conflict-base)', { nargs = 0 })
  command('GitConflictChooseNone', '<Plug>(git-conflict-none)', { nargs = 0 })
  command('GitConflictNextConflict', '<Plug>(git-conflict-next-conflict)', { nargs = 0 })
  command('GitConflictPrevConflict', '<Plug>(git-conflict-prev-conflict)', { nargs = 0 })
end

-----------------------------------------------------------------------------//
-- Mappings
-----------------------------------------------------------------------------//

local function set_plug_mappings()
  local function opts(desc) return { silent = true, desc = 'Git Conflict: ' .. desc } end

  map({ 'n', 'v' }, '<Plug>(git-conflict-ours)', function() M.choose('ours') end, opts('Choose Ours'))
  map({ 'n', 'v' }, '<Plug>(git-conflict-both)', function() M.choose('both') end, opts('Choose Both'))
  map({ 'n', 'v' }, '<Plug>(git-conflict-base)', function() M.choose('base') end, opts('Choose Base'))
  map({ 'n', 'v' }, '<Plug>(git-conflict-none)', function() M.choose('none') end, opts('Choose None'))
  map({ 'n', 'v' }, '<Plug>(git-conflict-theirs)', function() M.choose('theirs') end, opts('Choose Theirs'))
  map(
    'n',
    '<Plug>(git-conflict-next-conflict)',
    function() M.find_next('ours') end,
    opts('Next Conflict')
  )
  map(
    'n',
    '<Plug>(git-conflict-prev-conflict)',
    function() M.find_prev('ours') end,
    opts('Previous Conflict')
  )
end

local function setup_buffer_mappings(bufnr)
  local function opts(desc)
    return { silent = true, buffer = bufnr, desc = 'Git Conflict: ' .. desc }
  end

  map({ 'n', 'v' }, config.default_mappings.ours, '<Plug>(git-conflict-ours)', opts('Choose Ours'))
  map({ 'n', 'v' }, config.default_mappings.both, '<Plug>(git-conflict-both)', opts('Choose Both'))
  map({ 'n', 'v' }, config.default_mappings.none, '<Plug>(git-conflict-none)', opts('Choose None'))
  map({ 'n', 'v' }, config.default_mappings.theirs, '<Plug>(git-conflict-theirs)', opts('Choose Theirs'))
  map({ 'v', 'v' }, config.default_mappings.ours, '<Plug>(git-conflict-ours)', opts('Choose Ours'))
  -- map('V', config.default_mappings.ours, '<Plug>(git-conflict-ours)', opts('Choose Ours'))
  map(
    'n',
    config.default_mappings.prev,
    '<Plug>(git-conflict-prev-conflict)',
    opts('Previous Conflict')
  )
  map(
    'n',
    config.default_mappings.next,
    '<Plug>(git-conflict-next-conflict)',
    opts('Next Conflict')
  )
  vim.b[bufnr].conflict_mappings_set = true
end

---@param key string
---@param mode "'n'|'v'|'o'|'nv'|'nvo'"?
---@return boolean
local function is_mapped(key, mode) return fn.hasmapto(key, mode or 'n') > 0 end

local function clear_buffer_mappings(bufnr)
  if not bufnr or not vim.b[bufnr].conflict_mappings_set then return end
  for _, mapping in pairs(config.default_mappings) do
    if is_mapped(mapping) then api.nvim_buf_del_keymap(bufnr, 'n', mapping) end
  end
  vim.b[bufnr].conflict_mappings_set = false
end

-----------------------------------------------------------------------------//
-- Highlights
-----------------------------------------------------------------------------//

---Derive the colour of the section label highlights based on each sections highlights
---@param highlights ConflictHighlights
local function set_highlights(highlights)
  local current_color = utils.get_hl(highlights.current)
  local incoming_color = utils.get_hl(highlights.incoming)
  local ancestor_color = utils.get_hl(highlights.ancestor)
  local current_bg = current_color.background or DEFAULT_CURRENT_BG_COLOR
  local incoming_bg = incoming_color.background or DEFAULT_INCOMING_BG_COLOR
  local ancestor_bg = ancestor_color.background or DEFAULT_ANCESTOR_BG_COLOR
  local current_label_bg = color.shade_color(current_bg, 60)
  local incoming_label_bg = color.shade_color(incoming_bg, 60)
  local ancestor_label_bg = color.shade_color(ancestor_bg, 60)
  api.nvim_set_hl(0, CURRENT_HL, { background = current_bg, bold = true, default = true })
  api.nvim_set_hl(0, INCOMING_HL, { background = incoming_bg, bold = true, default = true })
  api.nvim_set_hl(0, ANCESTOR_HL, { background = ancestor_bg, bold = true, default = true })
  api.nvim_set_hl(0, CURRENT_LABEL_HL, { background = current_label_bg, default = true })
  api.nvim_set_hl(0, INCOMING_LABEL_HL, { background = incoming_label_bg, default = true })
  api.nvim_set_hl(0, ANCESTOR_LABEL_HL, { background = ancestor_label_bg, default = true })
end

---@param user_config GitConflictUserConfig
function M.setup(user_config)
  if fn.executable('git') <= 0 then
    return vim.schedule(
      function()
        utils.notify('You need to have git installed in order to use this plugin', 'error', true)
      end
    )
  end

  local _user_config = user_config or {}

  if _user_config.default_mappings == true then _user_config.default_mappings = DEFAULT_MAPPINGS end

  config = vim.tbl_deep_extend('force', config, _user_config)

  set_highlights(config.highlights)

  if config.default_commands then set_commands() end

  set_plug_mappings()

  api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
  api.nvim_create_autocmd('ColorScheme', {
    group = AUGROUP_NAME,
    callback = function() set_highlights(config.highlights) end,
  })

  api.nvim_create_autocmd({ 'VimEnter', 'BufRead', 'SessionLoadPost', 'DirChanged' }, {
    group = AUGROUP_NAME,
    callback = function(args)
      local gitroot = vim.fs.root(fn.getcwd(), ".git")
      if not gitroot then return end
      local gitdir = vim.fs.joinpath(gitroot, ".git")
      if not vim.loop.fs_stat(gitdir) or state.current_watcher_dir == fn.getcwd() then return end
      stop_running_watchers(gitdir)
      fetch_conflicts(args.buf)
      throttled_watcher(gitdir)
    end,
  })

  api.nvim_create_autocmd('VimLeavePre', {
    group = AUGROUP_NAME,
    callback = function()
      for key, watcher in pairs(watchers) do
        watcher:stop()
        watchers[key] = nil
      end
    end,
  })

  api.nvim_create_autocmd('User', {
    group = AUGROUP_NAME,
    pattern = 'GitConflictDetected',
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      if config.disable_diagnostics then vim.diagnostic.disable(bufnr) end
      if config.default_mappings then setup_buffer_mappings(bufnr) end
    end,
  })

  api.nvim_create_autocmd('User', {
    group = AUGROUP_NAME,
    pattern = 'GitConflictResolved',
    callback = function()
      local bufnr = api.nvim_get_current_buf()
      if config.disable_diagnostics then vim.diagnostic.enable(bufnr) end
      if config.default_mappings then clear_buffer_mappings(bufnr) end
    end,
  })

  api.nvim_set_decoration_provider(NAMESPACE, {
    on_buf = function(_, bufnr, _) return utils.is_valid_buf(bufnr) end,
    on_win = function(_, _, bufnr, _, _)
      if visited_buffers[bufnr] then process(bufnr) end
    end,
  })
end

--- Add additional metadata to a quickfix entry if we have already visited the buffer and have that
--- information
---@param item table<string, integer|string>
---@param items table<string, integer|string>[]
---@param visited_buf ConflictBufferCache
local function quickfix_items_from_positions(item, items, visited_buf)
  if vim.tbl_isempty(visited_buf.positions) then return end
  for _, pos in ipairs(visited_buf.positions) do
    for key, value in pairs(pos) do
      if
          vim.tbl_contains({ name_map.ours, name_map.theirs, name_map.base }, key)
          and not vim.tbl_isempty(value)
      then
        local lnum = value.range_start + 1
        local next_item = vim.deepcopy(item)
        next_item.text = fmt('%s change', key, lnum)
        next_item.lnum = lnum
        next_item.col = 0
        table.insert(items, next_item)
      end
    end
  end
end

--- Convert the conflicts detected via get conflicted files into a list of quickfix entries.
---@param callback fun(files: table<string, integer[]>)
function M.conflicts_to_qf_items(callback)
  local items = {}
  for filename, visited_buf in pairs(visited_buffers) do
    local item = {
      filename = filename,
      pattern = conflict_start,
      text = 'git conflict',
      type = 'E',
      valid = 1,
    }

    if visited_buf and next(visited_buf) then
      quickfix_items_from_positions(item, items, visited_buf)
    else
      table.insert(items, item)
    end
  end

  callback(items)
end

---@param bufnr integer?
function M.clear(bufnr)
  if bufnr and not api.nvim_buf_is_valid(bufnr) then return end
  bufnr = bufnr or 0
  api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
end

---@param side ConflictSide
function M.find_next(side)
  local pos = find_position(
    0,
    function(line, position) return line < position.current.range_start end,
    { wrap = true }
  )
  set_cursor(pos, side)
end

---@param side ConflictSide
function M.find_prev(side)
  local pos = find_position(
    0,
    function(line, position) return line > position.current.range_start end,
    { wrap = true, reverse = true }
  )
  set_cursor(pos, side)
end

---Select the changes to keep
---@param side ConflictSide
function M.choose(side)
  local bufnr = api.nvim_get_current_buf()
  if vim.fn.mode() == 'v' or vim.fn.mode() == 'V' or vim.fn.mode() == '' then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
    -- have to defer so that the < and > marks are set
    vim.defer_fn(function()
      local start = vim.api.nvim_buf_get_mark(0, '<')[1]
      local finish = vim.api.nvim_buf_get_mark(0, '>')[1]
      local position = find_position(bufnr, function(line, pos)
        local left = pos.current.range_start >= start - 1
        local right = pos.incoming.range_end <= finish + 1
        return left and right
      end)
      while position ~= nil do
        local lines = {}
        if vim.tbl_contains({ SIDES.OURS, SIDES.THEIRS, SIDES.BASE }, side) then
          local data = position[name_map[side]]
          lines = utils.get_buf_lines(data.content_start, data.content_end + 1)
        elseif side == SIDES.BOTH then
          local first =
              utils.get_buf_lines(position.current.content_start, position.current.content_end + 1)
          local second =
              utils.get_buf_lines(position.incoming.content_start, position.incoming.content_end + 1)
          lines = vim.list_extend(first, second)
        elseif side == SIDES.NONE then
          lines = {}
        else
          return
        end

        local pos_start = position.current.range_start < 0 and 0 or position.current.range_start
        local pos_end = position.incoming.range_end + 1

        api.nvim_buf_set_lines(0, pos_start, pos_end, false, lines)
        api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.incoming.label)
        api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.current.label)
        if position.marks.ancestor.label then
          api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.ancestor.label)
        end
        parse_buffer(bufnr)
        position = find_position(bufnr, function(line, pos)
          local left = pos.current.range_start >= start - 1
          local right = pos.incoming.range_end <= finish + 1
          return left and right
        end)
      end
    end, 50)
    return
  end
  local position = get_current_position(bufnr)
  if not position then return end
  local lines = {}
  if vim.tbl_contains({ SIDES.OURS, SIDES.THEIRS, SIDES.BASE }, side) then
    local data = position[name_map[side]]
    lines = utils.get_buf_lines(data.content_start, data.content_end + 1)
  elseif side == SIDES.BOTH then
    local first =
        utils.get_buf_lines(position.current.content_start, position.current.content_end + 1)
    local second =
        utils.get_buf_lines(position.incoming.content_start, position.incoming.content_end + 1)
    lines = vim.list_extend(first, second)
  elseif side == SIDES.NONE then
    lines = {}
  else
    return
  end

  local pos_start = position.current.range_start < 0 and 0 or position.current.range_start
  local pos_end = position.incoming.range_end + 1

  api.nvim_buf_set_lines(0, pos_start, pos_end, false, lines)
  api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.incoming.label)
  api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.current.label)
  if position.marks.ancestor.label then
    api.nvim_buf_del_extmark(0, NAMESPACE, position.marks.ancestor.label)
  end
  parse_buffer(bufnr)
end

function M.debug_watchers() vim.pretty_print({ watchers = watchers }) end

function M.conflict_count(bufnr)
  if bufnr and not api.nvim_buf_is_valid(bufnr) then return 0 end
  bufnr = bufnr or 0

  local name = api.nvim_buf_get_name(bufnr)
  if not visited_buffers[name] then return 0 end

  return #visited_buffers[name].positions
end

return M
