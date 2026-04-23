-- WebSocket support via websocat (https://github.com/vi/websocat).
-- Install: brew install websocat
-- One connection at a time (module-level state).
local M = {}

local _conn = nil  -- { job, buf, win }

local function has_websocat()
  return vim.fn.executable("websocat") == 1
end

local function get_or_create_buf()
  if _conn and vim.api.nvim_buf_is_valid(_conn.buf) then
    return _conn.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "neo-http://websocket")
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile  = false
  vim.keymap.set("n", "q", function() M.disconnect() end,
    { buffer = buf, silent = true, nowait = true, desc = "Disconnect WebSocket" })
  return buf
end

local function buf_append(buf, lines)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    local count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, count, count, false, lines)
    vim.bo[buf].modifiable = false
    -- Scroll to bottom in all windows showing this buffer
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
      end
    end
  end)
end

local function ts()
  return os.date("[%H:%M:%S]")
end

function M.connect(url, headers)
  if not has_websocat() then
    vim.notify("[neo-http] websocat not found — install: brew install websocat", vim.log.levels.ERROR)
    return
  end

  if _conn then
    vim.notify("[neo-http] Already connected — disconnect first (<leader>hwd)", vim.log.levels.WARN)
    return
  end

  local buf = get_or_create_buf()

  local width = math.floor(vim.o.columns * 0.4)
  vim.cmd("botright " .. width .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "── WebSocket: " .. url .. " ──",
    ts() .. " Connecting...",
  })
  vim.bo[buf].modifiable = false

  local cmd = { "websocat", "--no-close", "-", url }
  for _, h in ipairs(headers or {}) do
    table.insert(cmd, 2, "-H")
    table.insert(cmd, 3, h)
  end

  local job = vim.system(cmd, {
    stdin  = true,
    stdout = function(_, data)
      if not data or data == "" then return end
      local lines = {}
      for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
          table.insert(lines, ts() .. " ← " .. line)
        end
      end
      if #lines > 0 then buf_append(buf, lines) end
    end,
    stderr = function(_, data)
      if data and data ~= "" then
        buf_append(buf, { ts() .. " ERR: " .. vim.trim(data) })
      end
    end,
  }, function(result)
    buf_append(buf, { ts() .. " Disconnected (exit " .. result.code .. ")" })
    _conn = nil
  end)

  _conn = { job = job, buf = buf, win = win }
  buf_append(buf, { ts() .. " Connected" })
  vim.notify("[neo-http] WebSocket connected: " .. url, vim.log.levels.INFO)
end

function M.send(message)
  if not _conn then
    vim.notify("[neo-http] Not connected — run a WS request first", vim.log.levels.WARN)
    return
  end
  _conn.job:write(message .. "\n")
  buf_append(_conn.buf, { ts() .. " → " .. message })
end

function M.prompt_send()
  if not _conn then
    vim.notify("[neo-http] Not connected", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "Send: " }, function(msg)
    if msg and msg ~= "" then M.send(msg) end
  end)
end

function M.disconnect()
  if not _conn then
    vim.notify("[neo-http] No active WebSocket connection", vim.log.levels.INFO)
    return
  end
  _conn.job:kill(15)
  _conn = nil
  vim.notify("[neo-http] WebSocket disconnected", vim.log.levels.INFO)
end

function M.is_connected()
  return _conn ~= nil
end

return M
