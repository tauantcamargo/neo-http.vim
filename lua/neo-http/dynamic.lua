local M = {}

math.randomseed(os.time())

local function uuid4()
  local t = { "xxxxxxxx", "xxxx", "4xxx", "yxxx", "xxxxxxxxxxxx" }
  return table.concat(t, "-"):gsub("[xy]", function(c)
    local v = c == "x" and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format("%x", v)
  end)
end

local _builtins = {
  ["$timestamp"]    = function() return tostring(os.time()) end,
  ["$isoTimestamp"] = function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end,
  ["$randomInt"]    = function() return tostring(math.random(1, 1000)) end,
  ["$randomFloat"]  = function() return string.format("%.6f", math.random() * 1000) end,
  ["$uuid"]         = uuid4,
  ["$guid"]         = uuid4,
}

-- Resolve all {{$...}} placeholders in a string.
-- Returns the string unchanged if no dynamic vars are present.
function M.resolve(str)
  if not str or not str:find("{{%$") then return str end
  return (str:gsub("{{(%$[^}]+)}}", function(key)
    local fn = _builtins[key]
    if fn then return fn() end
    vim.notify(
      string.format("[neo-http] Unknown dynamic variable: {{%s}}", key),
      vim.log.levels.WARN
    )
    return "{{" .. key .. "}}"
  end))
end

return M
