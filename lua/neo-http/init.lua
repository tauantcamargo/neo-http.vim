local M = {}

local parser  = require("neo-http.parser")
local env     = require("neo-http.env")
local runner  = require("neo-http.runner")
local ui      = require("neo-http.ui")
local jq      = require("neo-http.jq")
local dynamic = require("neo-http.dynamic")

local _state = {
  last_raw_body = nil,
  last_result   = nil,
  last_is_json  = false,
}

local function is_json_response(raw)
  return raw:lower():match("content%-type:%s*application/json") ~= nil
end

local function extract_body(raw)
  local _, nl_end = raw:find("\r?\n\r?\n")
  if nl_end then return raw:sub(nl_end + 1) end
  return raw
end

local function apply_env_vars(str, env_vars)
  if not str then return nil end
  str = dynamic.resolve(str)
  return (str:gsub("{{([^}]+)}}", function(key)
    return env_vars[key] or ("{{" .. key .. "}}")
  end))
end

local jq_filter  -- forward declaration so run_request callback can reference it

local function run_request()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  local req, err = parser.parse_request_at_cursor(bufnr, cursor_line)
  if not req then
    vim.notify("[neo-http] " .. (err or "Unknown parse error"), vim.log.levels.WARN)
    return
  end

  local env_vars = env.get_vars()
  req.url = apply_env_vars(req.url, env_vars)
  for i, h in ipairs(req.headers) do
    req.headers[i] = apply_env_vars(h, env_vars)
  end
  req.body = apply_env_vars(req.body, env_vars)

  vim.notify(string.format("[neo-http] %s %s", req.method, req.url), vim.log.levels.INFO)

  runner.execute(req, function(result)
    local is_json = is_json_response(result.raw)
    local body = extract_body(result.raw)

    _state.last_raw_body = body
    _state.last_is_json  = is_json

    if is_json and jq.has_jq() then
      local formatted = jq.format(body)
      local _, nl_end = result.raw:find("\r?\n\r?\n")
      if nl_end then
        result.raw = result.raw:sub(1, nl_end) .. formatted
      end
    end

    result.request_line = req.method .. " " .. req.url
    _state.last_result = result
    ui.show_response(result, is_json)

    -- Also bind <leader>hj on the response buffer so the user can
    -- filter from either side without switching back to the .http file
    local rbuf = ui.get_buf()
    if rbuf then
      vim.keymap.set("n", "<leader>hj", function() jq_filter() end,
        { buffer = rbuf, desc = "jq filter", nowait = true })
    end
  end)
end

local function list_requests()
  local bufnr = vim.api.nvim_get_current_buf()
  local requests = parser.list_requests(bufnr)

  if #requests == 0 then
    vim.notify("[neo-http] No requests found in file", vim.log.levels.WARN)
    return
  end

  vim.ui.select(requests, {
    prompt = "Select request to run:",
    format_item = function(item) return item.name end,
  }, function(selected)
    if not selected then return end
    vim.api.nvim_win_set_cursor(0, { selected.line, 0 })
    run_request()
  end)
end

local function select_environment()
  local envs = env.list_envs()

  if #envs == 0 then
    vim.notify(
      "[neo-http] No environment file found (.neo-http.env.json)",
      vim.log.levels.WARN
    )
    return
  end

  local active = env.get_active_env()

  vim.ui.select(envs, {
    prompt = "Select environment:",
    format_item = function(e)
      return e == active and (e .. "  ✓") or e
    end,
  }, function(selected)
    if not selected then return end
    env.set_active_env(selected)
    vim.notify("[neo-http] Active environment: " .. selected, vim.log.levels.INFO)
  end)
end

jq_filter = function()
  if not _state.last_raw_body then
    vim.notify("[neo-http] No response yet — run a request first (<leader>hr)", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "jq filter (empty = reset): " }, function(input)
    if input == nil then return end

    local expr = input:match("^%s*(.-)%s*$")
    if expr == "" then
      ui.show_response(_state.last_result, _state.last_is_json)
      return
    end

    jq.filter(_state.last_raw_body, expr, function(output, err)
      if err then
        vim.notify("[neo-http] jq error: " .. err, vim.log.levels.ERROR)
        return
      end
      local lines = vim.split(output or "", "\n")
      if lines[#lines] == "" then table.remove(lines) end
      ui.update_content(lines)
    end)
  end)
end

local function copy_as_curl()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  local req, err = parser.parse_request_at_cursor(bufnr, cursor_line)
  if not req then
    vim.notify("[neo-http] " .. (err or "Unknown parse error"), vim.log.levels.WARN)
    return
  end

  local env_vars = env.get_vars()
  req.url = apply_env_vars(req.url, env_vars)
  for i, h in ipairs(req.headers) do
    req.headers[i] = apply_env_vars(h, env_vars)
  end
  req.body = apply_env_vars(req.body, env_vars)

  local curl_str = runner.to_curl_string(req)
  vim.fn.setreg("+", curl_str)
  vim.notify("[neo-http] Copied curl command to clipboard", vim.log.levels.INFO)
end

function M.setup(opts)
  opts = opts or {}

  env.setup(opts)
  runner.setup(opts)
  ui.setup(opts)
  jq.setup(opts)

  -- Register treesitter parser config if nvim-treesitter is available
  pcall(function()
    require("nvim-treesitter.parsers").get_parser_configs().http = {
      install_info = {
        url    = "https://github.com/rest-nvim/tree-sitter-http",
        files  = { "src/parser.c" },
        branch = "main",
      },
      filetype = "http",
    }
  end)

  -- Buffer-local keymaps: override any global bindings (e.g. Gitsigns) inside .http files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "http",
    callback = function(ev)
      local buf = ev.buf
      vim.keymap.set("n", "<leader>hr", run_request,        { buffer = buf, desc = "Run request" })
      vim.keymap.set("n", "<leader>hl", list_requests,      { buffer = buf, desc = "List requests" })
      vim.keymap.set("n", "<leader>he", select_environment, { buffer = buf, desc = "Select environment" })
      vim.keymap.set("n", "<leader>hj", jq_filter,          { buffer = buf, desc = "jq filter" })
      vim.keymap.set("n", "<leader>hc", copy_as_curl,       { buffer = buf, desc = "Copy as curl" })
    end,
  })
end

return M
