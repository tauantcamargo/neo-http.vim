local M = {}

local BUF_NAME = "http-response"
local _config = { split_width = 0.5 }
local _buf = nil  -- stored handle, avoids unreliable name-matching

function M.setup(opts)
  _config.split_width = math.max(0.1, math.min(0.9, opts.split_width or 0.5))
end

local function find_buf()
  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    return _buf
  end
  _buf = nil
  return nil
end

local function get_or_create_buf()
  local buf = find_buf()
  if buf then return buf end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, BUF_NAME)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile  = false
  _buf = buf
  return buf
end

local function find_win(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  return nil
end

local function open_split(buf)
  local existing = find_win(buf)
  if existing then return existing end

  local width = math.floor(vim.o.columns * _config.split_width)
  vim.cmd("botright " .. width .. "vsplit")
  local new_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(new_win, buf)

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, nowait = true })

  return new_win
end

local function detect_filetype(raw, is_json)
  if is_json then return "json" end
  local ct = raw:lower():match("content%-type:%s*([^\r\n;]+)")
  if ct then
    ct = ct:match("^%s*(.-)%s*$")
    if ct:find("text/html") then return "html" end
    if ct:find("application/xml") or ct:find("text/xml") then return "xml" end
  end
  return "text"
end

local function split_response(raw)
  local nl_start, nl_end = raw:find("\r?\n\r?\n")
  if not nl_start then
    return { status_line = raw:sub(1, 80), headers = {}, body = raw }
  end

  local header_section = raw:sub(1, nl_start)
  local body = raw:sub(nl_end + 1)  -- skip past entire CRLF CRLF sequence

  local header_lines = vim.split(header_section:gsub("\r", ""), "\n")
  local status_line = table.remove(header_lines, 1)

  while #header_lines > 0 and header_lines[#header_lines]:match("^%s*$") do
    table.remove(header_lines)
  end

  return { status_line = status_line, headers = header_lines, body = body }
end

local function write_buf(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.show_response(result, is_json)
  local buf = get_or_create_buf()
  local win = open_split(buf)

  local parsed = split_response(result.raw)
  local output = {}

  -- Request line at the top so the full resolved URL is always visible
  if result.request_line then
    table.insert(output, "→ " .. result.request_line)
    table.insert(output, string.rep("─", 40))
  end

  table.insert(output, string.format("%s  [%dms]", parsed.status_line, result.elapsed_ms))
  for _, h in ipairs(parsed.headers) do
    table.insert(output, h)
  end
  table.insert(output, string.rep("─", 40))
  for _, line in ipairs(vim.split(parsed.body, "\n")) do
    table.insert(output, line)
  end

  write_buf(buf, output)
  vim.bo[buf].filetype = detect_filetype(result.raw, is_json)
  vim.api.nvim_set_current_win(win)
end

function M.update_content(lines)
  local buf = find_buf()
  if not buf then
    vim.notify("[neo-http] No response buffer open", vim.log.levels.WARN)
    return
  end
  write_buf(buf, lines)
end

function M.get_buf()
  return find_buf()
end

return M
