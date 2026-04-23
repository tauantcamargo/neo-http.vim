local M = {}

local parser     = require("neo-http.parser")
local env        = require("neo-http.env")
local runner     = require("neo-http.runner")
local ui         = require("neo-http.ui")
local jq         = require("neo-http.jq")
local dynamic    = require("neo-http.dynamic")
local capture    = require("neo-http.capture")
local cookies    = require("neo-http.cookies")
local history    = require("neo-http.history")
local assert_mod = require("neo-http.assert")
local importer   = require("neo-http.importer")
local format_mod = require("neo-http.format")
local ws         = require("neo-http.websocket")

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

local function apply_env_vars(str, env_vars, unresolved)
  if not str then return nil end
  str = dynamic.resolve(str)
  return (str:gsub("{{([^}]+)}}", function(key)
    if env_vars[key] then
      return env_vars[key]
    end
    if unresolved and not key:match("^%$") and not unresolved[key] then
      unresolved[key] = true
      vim.notify(
        string.format("[neo-http] Unresolved variable: {{%s}}", key),
        vim.log.levels.WARN
      )
    end
    return "{{" .. key .. "}}"
  end))
end

local function apply_request_env_vars(req, env_vars)
  local unresolved = {}
  req.url = apply_env_vars(req.url, env_vars, unresolved)
  for i, h in ipairs(req.headers) do
    req.headers[i] = apply_env_vars(h, env_vars, unresolved)
  end
  req.body = apply_env_vars(req.body, env_vars, unresolved)
end

local jq_filter  -- forward declaration

local function run_request()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  local req, err = parser.parse_request_at_cursor(bufnr, cursor_line)
  if not req then
    vim.notify("[neo-http] " .. (err or "Unknown parse error"), vim.log.levels.WARN)
    return
  end

  local env_vars = env.get_vars()
  apply_request_env_vars(req, env_vars)

  vim.notify(string.format("[neo-http] %s %s", req.method, req.url), vim.log.levels.INFO)

  -- WebSocket requests open a persistent console instead of making an HTTP call
  if req.is_websocket then
    ws.connect(req.url, req.headers)
    return
  end

  local req_name = req.method .. " " .. req.url

  runner.execute(req, function(result)
    local is_json = is_json_response(result.raw)
    local body = extract_body(result.raw)

    _state.last_raw_body = body
    _state.last_is_json  = is_json

    -- @capture — extract values for request chaining
    if req.captures and #req.captures > 0 then
      capture.apply(req.captures, body)
    end

    -- @assert — evaluate pass/fail conditions
    if req.assertions and #req.assertions > 0 then
      local assert_results = assert_mod.run(req.assertions, result.raw, body)
      local assert_lines, all_pass = assert_mod.format(assert_results)
      result.assert_lines = assert_lines
      if not all_pass then
        vim.notify("[neo-http] Some assertions FAILED — see response buffer", vim.log.levels.WARN)
      else
        vim.notify("[neo-http] All assertions passed", vim.log.levels.INFO)
      end
    end

    local _, nl_end = result.raw:find("\r?\n\r?\n")
    if is_json and jq.has_jq() then
      local formatted = jq.format(body)
      if nl_end then
        result.raw = result.raw:sub(1, nl_end) .. formatted
      end
    else
      -- XML / HTML formatting
      local fmt = format_mod.detect_and_format(result.raw, body, is_json)
      if fmt.filetype ~= "text" and nl_end then
        result.raw = result.raw:sub(1, nl_end) .. fmt.content
      end
      result.override_ft = fmt.filetype
    end

    result.request_line = req.method .. " " .. req.url
    _state.last_result = result
    history.push(req_name, result, is_json)
    ui.show_response(result, is_json)

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
    vim.notify("[neo-http] No environment file found (.http-client.env.json)", vim.log.levels.WARN)
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

local function show_history()
  local names = history.list_names()
  if #names == 0 then
    vim.notify("[neo-http] No history yet — run a request first", vim.log.levels.WARN)
    return
  end

  vim.ui.select(names, { prompt = "Request history:" }, function(name)
    if not name then return end
    local entries = history.get(name)

    vim.ui.select(entries, {
      prompt = "Select response:",
      format_item = function(e)
        local status = e.result.raw:match("HTTP/%S+%s+(%d+)") or "???"
        return string.format("%s  %s  [%dms]",
          os.date("%H:%M:%S", e.timestamp), status, e.result.elapsed_ms)
      end,
    }, function(entry)
      if not entry then return end
      _state.last_result   = entry.result
      _state.last_is_json  = entry.is_json
      _state.last_raw_body = extract_body(entry.result.raw)
      ui.show_response(entry.result, entry.is_json)
    end)
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

local function import_collection()
  vim.ui.input({
    prompt = "Collection file (.json or .bru): ",
    completion = "file",
  }, function(source_path)
    if not source_path or source_path == "" then return end
    source_path = vim.fn.expand(source_path)

    local default_out = vim.fn.fnamemodify(source_path, ":t:r") .. ".http"
    vim.ui.input({
      prompt = "Save as (.http): ",
      default = default_out,
      completion = "file",
    }, function(output_path)
      if not output_path or output_path == "" then return end
      output_path = vim.fn.expand(output_path)

      local ok, result = importer.import(source_path, output_path)
      if ok then
        vim.notify("[neo-http] Imported → " .. result, vim.log.levels.INFO)
        vim.cmd("edit " .. vim.fn.fnameescape(output_path))
      else
        vim.notify("[neo-http] Import failed: " .. result, vim.log.levels.ERROR)
      end
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
  apply_request_env_vars(req, env_vars)

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
  cookies.setup(opts)
  history.setup(opts)

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

  -- Global keymap — import works from any buffer
  vim.keymap.set("n", "<leader>hi", import_collection, { desc = "Import collection" })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "http",
    callback = function(ev)
      local buf = ev.buf
      vim.keymap.set("n", "<leader>hr", run_request,        { buffer = buf, desc = "Run request" })
      vim.keymap.set("n", "<leader>hl", list_requests,      { buffer = buf, desc = "List requests" })
      vim.keymap.set("n", "<leader>he", select_environment, { buffer = buf, desc = "Select environment" })
      vim.keymap.set("n", "<leader>hj", jq_filter,          { buffer = buf, desc = "jq filter" })
      vim.keymap.set("n", "<leader>hc", copy_as_curl,       { buffer = buf, desc = "Copy as curl" })
      vim.keymap.set("n", "<leader>hH", show_history,       { buffer = buf, desc = "Response history" })
      vim.keymap.set("n", "<leader>hx", capture.clear,      { buffer = buf, desc = "Clear captured vars" })
      vim.keymap.set("n", "<leader>hC", cookies.clear,      { buffer = buf, desc = "Clear cookie jar" })
      vim.keymap.set("n", "<leader>hwm", ws.prompt_send,    { buffer = buf, desc = "WebSocket send message" })
      vim.keymap.set("n", "<leader>hwd", ws.disconnect,     { buffer = buf, desc = "WebSocket disconnect" })
    end,
  })
end

return M
