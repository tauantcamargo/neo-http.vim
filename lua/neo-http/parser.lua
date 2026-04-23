local M = {}

local function find_blocks(lines)
  local blocks = {}
  local current_start = nil

  for i, line in ipairs(lines) do
    if line:match("^###") then
      if current_start then
        table.insert(blocks, { start = current_start, stop = i - 1 })
      end
      current_start = i
    end
  end

  if current_start then
    table.insert(blocks, { start = current_start, stop = #lines })
  end

  return blocks
end

local function parse_vars(lines, from, to)
  local vars = {}
  for i = from, to do
    local key, val = lines[i]:match("^@(%S+)%s*=%s*(.+)$")
    if key then
      vars[key] = val:match("^%s*(.-)%s*$")
    end
  end
  return vars
end

local function parse_directive_var(line)
  local key, val = line:match("^@(%S+)%s*=%s*(.+)$")
  if not key then return nil, nil end
  return key, val:match("^%s*(.-)%s*$")
end

local function resolve(str, vars)
  -- gsub returns (result, count) — capture only result to avoid multi-return
  -- expansion when used as a table.insert argument
  local result = str:gsub("{{([^}]+)}}", function(key)
    if vars[key] then
      return vars[key]
    else
      vim.notify(
        string.format("[neo-http] Unresolved variable: {{%s}}", key),
        vim.log.levels.WARN
      )
      return "{{" .. key .. "}}"
    end
  end)
  return result
end

local function resolve_silent(str, vars)
  return (str:gsub("{{([^}]+)}}", function(key)
    return vars[key] or ("{{" .. key .. "}}")
  end))
end

local function parse_block(lines, block_start, block_end, file_vars)
  local i = block_start + 1

  -- Skip optional name comment and blank lines
  while i <= block_end and (lines[i]:match("^%s*#") or lines[i]:match("^%s*$")) do
    i = i + 1
  end

  -- Collect request-scoped directives before the method line
  local req_var_end = i - 1
  local captures   = {}
  local assertions = {}
  while i <= block_end do
    local cap_name, cap_path = lines[i]:match("^@capture%s+(%S+)%s*=%s*(%S+)%s*$")
    local assert_expr        = lines[i]:match("^@assert%s+(.+)$")

    if cap_name then
      table.insert(captures, { name = cap_name, path = cap_path })
      i = i + 1
    elseif assert_expr then
      table.insert(assertions, { expr = assert_expr:match("^%s*(.-)%s*$") })
      i = i + 1
    elseif lines[i]:match("^@%S+%s*=") then
      req_var_end = i
      i = i + 1
    else
      break
    end
  end

  local req_vars = parse_vars(lines, block_start + 1, req_var_end)

  -- Skip blank lines between @var declarations and the METHOD URL line
  while i <= block_end and lines[i]:match("^%s*$") do
    i = i + 1
  end

  if i > block_end then return nil end

  local method, url = lines[i]:match("^(%u+)%s+(.-)%s*$")
  if not method then return nil end
  i = i + 1

  -- Join multi-line query param continuation lines
  while i <= block_end do
    local cont = lines[i]:match("^%s*([?&][^%s].*)$")
    if cont then
      url = url .. cont:match("^%s*(.-)%s*$")
      i = i + 1
    else
      break
    end
  end

  -- Parse headers and inline request directives until blank separator
  local headers = {}
  while i <= block_end and not lines[i]:match("^%s*$") do
    local key, val = parse_directive_var(lines[i])
    if key then
      req_vars[key] = val
    else
      local header = lines[i]:match("^(.+:.+)$")
      if header then
        table.insert(headers, header:match("^%s*(.-)%s*$"))
      end
    end
    i = i + 1
  end

  -- Skip blank line between headers and body
  if i <= block_end and lines[i]:match("^%s*$") then
    i = i + 1
  end

  local body_lines = {}
  while i <= block_end do
    table.insert(body_lines, lines[i])
    i = i + 1
  end
  local body       = #body_lines > 0 and table.concat(body_lines, "\n") or nil
  local is_graphql = body ~= nil and body:match("^%s*#%s*%[graphql%]") ~= nil

  local vars = vim.tbl_extend("force", file_vars, req_vars)

  url = resolve(url, vars)
  local resolved_headers = {}
  for _, h in ipairs(headers) do
    table.insert(resolved_headers, resolve(h, vars))
  end
  if body then body = resolve(body, vars) end

  -- @auth directive → inject Authorization header
  if vars["auth"] then
    local auth_header = require("neo-http.auth").resolve(resolve_silent(vars["auth"], vars))
    if auth_header then
      table.insert(resolved_headers, auth_header)
    end
  end

  return {
    method     = method,
    url        = url,
    headers    = resolved_headers,
    body       = body,
    vars       = vars,
    url_encode = vars["url_encode"] == "true",
    ssl_verify = vars["ssl_verify"] ~= "false",
    cookie_jar    = vars["cookie_jar"] == "true",
    captures      = captures,
    assertions    = assertions,
    is_graphql    = is_graphql,
    is_websocket  = method == "WS" or method == "WSS",
  }
end

function M.parse_request_at_cursor(bufnr, cursor_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = find_blocks(lines)

  if #blocks == 0 then
    return nil, "No requests found in file (missing ### separators)"
  end

  local file_vars = parse_vars(lines, 1, blocks[1].start - 1)

  local target = nil
  for _, b in ipairs(blocks) do
    if cursor_line >= b.start and cursor_line <= b.stop then
      target = b
      break
    end
  end

  -- Fallback: last block before cursor
  if not target then
    for _, b in ipairs(blocks) do
      if cursor_line >= b.start then target = b end
    end
  end

  if not target then
    return nil, "No request found at cursor position"
  end

  local req = parse_block(lines, target.start, target.stop, file_vars)
  if not req then
    return nil, "Could not parse request block — check METHOD URL line"
  end

  return req, nil
end

function M.list_requests(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = find_blocks(lines)
  local result = {}

  for _, b in ipairs(blocks) do
    local name = "Request at line " .. b.start
    local next = lines[b.start + 1]
    if next and next:match("^%s*#%s*(.+)") then
      name = next:match("^%s*#%s*(.+)")
    end
    table.insert(result, { name = name, line = b.start })
  end

  return result
end

return M
