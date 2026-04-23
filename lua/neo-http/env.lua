local M = {}

local _state = {
  active_env = "dev",
  env_file = ".neo-http.env.json",
}

function M.setup(opts)
  _state.active_env = opts.default_env or "dev"
  _state.env_file = opts.env_file or ".neo-http.env.json"
end

local function find_env_file()
  local path = vim.fn.findfile(_state.env_file, ".;")
  return path ~= "" and path or nil
end

local function load_env_file()
  local path = find_env_file()
  if not path then return nil end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then return nil end

  local ok2, data = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if not ok2 then
    vim.notify("[neo-http] Invalid JSON in " .. _state.env_file, vim.log.levels.ERROR)
    return nil
  end

  return data
end

local function resolve_shell_env(value)
  return value:gsub("{{%$env%s+([^}]+)}}", function(varname)
    local trimmed = varname:match("^%s*(.-)%s*$")
    local val = vim.fn.getenv(trimmed)
    if val == vim.NIL or val == "" then
      vim.notify(
        string.format("[neo-http] Shell env var not set: %s", trimmed),
        vim.log.levels.WARN
      )
      return "{{$env " .. trimmed .. "}}"
    end
    return val
  end)
end

function M.get_vars()
  local data = load_env_file()
  if not data then return {} end

  local env_vars = data[_state.active_env]
  if not env_vars then
    vim.notify(
      string.format("[neo-http] Environment '%s' not found in %s", _state.active_env, _state.env_file),
      vim.log.levels.WARN
    )
    return {}
  end

  local resolved = {}
  for k, v in pairs(env_vars) do
    resolved[k] = resolve_shell_env(tostring(v))
  end
  return resolved
end

function M.get_active_env()
  return _state.active_env
end

function M.set_active_env(name)
  _state.active_env = name
end

function M.list_envs()
  local data = load_env_file()
  if not data then return {} end
  local envs = {}
  for k in pairs(data) do
    table.insert(envs, k)
  end
  table.sort(envs)
  return envs
end

return M
