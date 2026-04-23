local M = {}

local _config = { backend = "curl" }

-- Timing fields appended to stdout after the response body.
-- Split on this sentinel when parsing the response.
local TIMING_SENTINEL = "\nNEOHTTP_TIMING\n"
local TIMING_FORMAT = TIMING_SENTINEL
  .. "dns:%{time_namelookup}"
  .. "\ntcp:%{time_connect}"
  .. "\nttfb:%{time_starttransfer}"
  .. "\ntotal:%{time_total}\n"

local function parse_timing(raw)
  local sep = raw:find("\nNEOHTTP_TIMING\n", 1, true)
  if not sep then return raw, {} end

  local response = raw:sub(1, sep - 1)
  local timing_str = raw:sub(sep + #"\nNEOHTTP_TIMING\n")
  local timing = {}
  for key, val in timing_str:gmatch("(%a+):([%d%.]+)") do
    timing[key] = math.floor(tonumber(val) * 1000)  -- convert to ms
  end
  return response, timing
end

local function percent_encode(str)
  return (str:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function encode_url(url)
  local base, query = url:match("^([^?]*)%?(.+)$")
  if not query then return url end

  local parts = {}
  for pair in (query .. "&"):gmatch("([^&]*)&") do
    local key, val = pair:match("^([^=]*)=(.*)$")
    if key then
      table.insert(parts, key .. "=" .. percent_encode(val))
    elseif pair ~= "" then
      table.insert(parts, percent_encode(pair))
    end
  end

  return base .. "?" .. table.concat(parts, "&")
end

function M.setup(opts)
  _config.backend = opts.backend or "curl"

  local backend_cmd = _config.backend == "httpie" and "http" or "curl"
  if vim.fn.executable(backend_cmd) == 0 then
    vim.notify(
      string.format(
        "[neo-http] Backend '%s' (%s) not found. Install it or set opts.backend.",
        _config.backend,
        backend_cmd
      ),
      vim.log.levels.WARN
    )
  end
end

local function is_multipart(headers)
  for _, h in ipairs(headers) do
    if h:lower():match("^content%-type:%s*multipart/form%-data") then
      return true
    end
  end
  return false
end

local function build_form_args(body)
  local args = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then
      local key, val = line:match("^([^=]+)=(.+)$")
      if key and val then
        key = key:match("^%s*(.-)%s*$")
        val = val:match("^%s*(.-)%s*$")
        local filepath = val:match("^file://(.+)$")
        if filepath then
          filepath = filepath:gsub("^~", os.getenv("HOME") or "~")
          table.insert(args, "--form")
          table.insert(args, key .. "=@" .. filepath)
        else
          table.insert(args, "--form")
          table.insert(args, key .. "=" .. val)
        end
      end
    end
  end
  return args
end

local function build_curl_command(req)
  local cmd = { "curl", "-s", "-i", "-X", req.method }

  if req.ssl_verify == false then
    table.insert(cmd, "-k")
  end

  if req.cookie_jar then
    local jar = require("neo-http.cookies").get_jar_path()
    table.insert(cmd, "--cookie")
    table.insert(cmd, jar)
    table.insert(cmd, "--cookie-jar")
    table.insert(cmd, jar)
  end

  local multipart = is_multipart(req.headers)

  for _, header in ipairs(req.headers) do
    -- curl sets Content-Type with boundary automatically for multipart
    if not (multipart and header:lower():match("^content%-type:%s*multipart")) then
      table.insert(cmd, "-H")
      table.insert(cmd, header)
    end
  end

  if req.body then
    if multipart then
      for _, arg in ipairs(build_form_args(req.body)) do
        table.insert(cmd, arg)
      end
    else
      table.insert(cmd, "-d")
      table.insert(cmd, req.body)
    end
  end

  table.insert(cmd, req.url)
  -- Append timing data after the response body
  table.insert(cmd, "--write-out")
  table.insert(cmd, TIMING_FORMAT)
  return cmd
end

local function build_httpie_command(req)
  local cmd = { "http", "--print=hb", req.method, req.url }

  for _, header in ipairs(req.headers) do
    table.insert(cmd, header)
  end

  if req.body then
    table.insert(cmd, "--ignore-stdin=false")
  end

  return cmd
end

function M.execute(req, callback)
  if req.url_encode then req.url = encode_url(req.url) end

  -- Transform GraphQL body into proper JSON payload
  if req.is_graphql and req.body then
    local gql = require("neo-http.graphql")
    req.body = gql.build_payload(req.body)
    local has_ct = false
    for _, h in ipairs(req.headers) do
      if h:lower():match("^content%-type:") then has_ct = true; break end
    end
    if not has_ct then
      table.insert(req.headers, "Content-Type: application/json")
    end
  end

  local cmd = _config.backend == "httpie"
    and build_httpie_command(req)
    or build_curl_command(req)

  local start_ms = vim.uv.now()
  local chunks = {}

  vim.system(cmd, {
    stdin = req.body,
    stdout = function(_, data)
      if data then table.insert(chunks, data) end
    end,
  }, function(result)
    local elapsed = vim.uv.now() - start_ms
    local raw_full = table.concat(chunks)
    local raw, timing = parse_timing(raw_full)

    vim.schedule(function()
      callback({
        raw        = raw,
        exit_code  = result.code,
        elapsed_ms = elapsed,
        timing     = timing,
      })
    end)
  end)
end

function M.to_curl_string(req)
  local url = req.url_encode and encode_url(req.url) or req.url
  local parts = { "curl -s -i" }
  if req.ssl_verify == false then
    table.insert(parts, "-k")
  end
  table.insert(parts, "-X " .. req.method)
  for _, h in ipairs(req.headers) do
    table.insert(parts, string.format("-H %q", h))
  end
  if req.body then
    table.insert(parts, string.format("-d %q", req.body))
  end
  table.insert(parts, string.format("%q", url))
  return table.concat(parts, " \\\n  ")
end

return M
