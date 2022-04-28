-----------------------------------------------------------------------------//
-- Utils
-----------------------------------------------------------------------------//
local M = {}

local api = vim.api
local fn = vim.fn

function M.job(cmd, callback)
  fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      callback(data)
    end,
  })
end

---Only call the passed function once every timeout in ms
---@param timeout number
---@param func function
---@return function
function M.throttle(timeout, func)
  local timer = vim.loop.new_timer()
  local running = false
  return function(...)
    if not running then
      func(...)
      running = true
      timer:start(timeout, 0, function()
        running = false
      end)
    end
  end
end

---Wrapper around `api.nvim_buf_get_lines` which defaults to the current buffer
---@param start number
---@param _end number
---@param buf number?
---@return string[]
function M.get_buf_lines(start, _end, buf)
  return api.nvim_buf_get_lines(buf or 0, start, _end, false)
end

---Get cursor row and column as (1, 0) based
---@param win_id number?
---@return number, number
function M.get_cursor_pos(win_id)
  return unpack(api.nvim_win_get_cursor(win_id or 0))
end

---Check if the buffer is likely to have actionable conflict markers
---@param bufnr number?
---@return boolean
function M.is_valid_buf(bufnr)
  bufnr = bufnr or 0
  return #vim.bo[bufnr].buftype == 0 and vim.bo[bufnr].modifiable
end

---@param name string?
---@return table<string, boolean|number|string>
function M.get_hl(name)
  if not name then
    return {}
  end
  return api.nvim_get_hl_by_name(name, true)
end

return M
