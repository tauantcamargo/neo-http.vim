-- Session-scoped variable store populated by @capture directives.
-- Values here override all other variable tiers.
local M = {}

local _store = {}

function M.set(name, value)
  _store[name] = tostring(value)
end

function M.get_all()
  return vim.tbl_extend("force", {}, _store)
end

function M.clear()
  _store = {}
  vim.notify("[neo-http] Captured variables cleared", vim.log.levels.INFO)
end

-- Extract a value from a JSON string using a simple dot-path.
-- Path format: $.field  or  $.nested.field  or  $.items[0].name
-- Returns nil when path cannot be resolved or JSON is invalid.
function M.extract(json_str, path)
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok or data == nil then return nil end

  local trimmed = path:gsub("^%$%.?", "")
  if trimmed == "" then
    if type(data) ~= "table" then return tostring(data) end
    return vim.json.encode(data)
  end

  local current = data
  for segment in trimmed:gmatch("[^.]+") do
    if current == nil then return nil end
    local key, idx = segment:match("^([^%[]+)%[(%d+)%]$")
    if key then
      current = current[key]
      if type(current) ~= "table" then return nil end
      current = current[tonumber(idx) + 1]
    elseif type(current) == "table" then
      current = current[segment]
    else
      return nil
    end
  end

  if current == nil then return nil end
  if type(current) == "table" then return vim.json.encode(current) end
  return tostring(current)
end

-- Apply a list of capture specs to a response body.
-- Each spec: { name = "var_name", path = "$.token" }
function M.apply(captures, body)
  for _, cap in ipairs(captures) do
    local value = M.extract(body, cap.path)
    if value then
      M.set(cap.name, value)
      vim.notify(
        string.format("[neo-http] Captured %s = %s", cap.name, value),
        vim.log.levels.INFO
      )
    else
      vim.notify(
        string.format("[neo-http] @capture %s: path '%s' not found in response", cap.name, cap.path),
        vim.log.levels.WARN
      )
    end
  end
end

return M
