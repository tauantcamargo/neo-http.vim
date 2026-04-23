local M = {}

local _config = { jq_auto_format = true }
local _has_jq = false

function M.setup(opts)
  _config.jq_auto_format = opts.jq_auto_format ~= false
  _has_jq = vim.fn.executable("jq") == 1

  if not _has_jq then
    vim.notify(
      "[neo-http] jq not found — JSON auto-formatting disabled. Install jq to enable.",
      vim.log.levels.INFO
    )
  end
end

function M.has_jq()
  return _has_jq
end

function M.format(json_str)
  if not _has_jq or not _config.jq_auto_format then
    return json_str
  end

  local result = vim.system({ "jq", "." }, { stdin = json_str }):wait()
  if result.code == 0 and result.stdout and result.stdout ~= "" then
    return result.stdout
  end
  return json_str
end

function M.filter(json_str, filter_expr, callback)
  if not _has_jq then
    callback(nil, "jq is not installed")
    return
  end

  local expr = filter_expr:match("^%s*(.-)%s*$")

  if expr == "" then
    callback(M.format(json_str), nil)
    return
  end

  local result = vim.system({ "jq", expr }, { stdin = json_str }):wait()
  if result.code == 0 then
    callback(result.stdout, nil)
  else
    callback(nil, result.stderr or "jq error (exit " .. result.code .. ")")
  end
end

function M.interactive_filter(raw_body, update_fn)
  if not _has_jq then
    vim.notify("[neo-http] jq not installed — cannot filter", vim.log.levels.WARN)
    return
  end

  if not raw_body or raw_body == "" then
    vim.notify("[neo-http] No response body to filter", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "jq filter: ", default = "." }, function(input)
    if input == nil then return end

    M.filter(raw_body, input, function(output, err)
      if err then
        vim.notify("[neo-http] jq error: " .. err, vim.log.levels.ERROR)
        return
      end
      local lines = vim.split(output or "", "\n")
      if lines[#lines] == "" then table.remove(lines) end
      update_fn(lines)
    end)
  end)
end

return M
