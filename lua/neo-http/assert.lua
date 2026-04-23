-- Evaluates @assert directives against a completed response.
--
-- Supported syntax:
--   @assert status == 200
--   @assert status >= 200
--   @assert status < 300
--   @assert body.field == "value"
--   @assert body.field != null
--   @assert body.count > 0
local M = {}

local function get_status(raw)
  return tonumber(raw:match("HTTP/%S+%s+(%d+)") or "0")
end

local function get_body_value(body, path)
  local ok, data = pcall(vim.json.decode, body)
  if not ok then return nil end

  local current = data
  for segment in path:gmatch("[^.]+") do
    if type(current) ~= "table" then return nil end
    local key, idx = segment:match("^([^%[]+)%[(%d+)%]$")
    if key then
      current = current[key]
      if type(current) == "table" then
        current = current[tonumber(idx) + 1]
      else
        return nil
      end
    else
      current = current[segment]
    end
  end
  return current
end

local function eval_op(actual, op, expected_str)
  if expected_str == "null" then
    if op == "==" then return actual == nil
    elseif op == "!=" then return actual ~= nil
    end
    return false
  end

  local n = tonumber(expected_str)
  local expected = n or (expected_str:match('^"(.*)"$') or expected_str)

  if op == "==" then return actual == expected
  elseif op == "!=" then return actual ~= expected
  elseif op == ">"  then return type(actual) == "number" and actual >  (n or 0)
  elseif op == ">=" then return type(actual) == "number" and actual >= (n or 0)
  elseif op == "<"  then return type(actual) == "number" and actual <  (n or 0)
  elseif op == "<=" then return type(actual) == "number" and actual <= (n or 0)
  end
  return false
end

-- Run all assertion specs against raw response + body.
-- Returns a list of { pass=bool, msg=string }.
function M.run(assertions, raw, body)
  local results = {}
  local status  = get_status(raw)

  for _, a in ipairs(assertions or {}) do
    local target, op, expected_str = a.expr:match("^(%S+)%s+(%S+)%s+(.+)$")
    if not target then
      table.insert(results, { pass = false, msg = "Invalid assertion: " .. a.expr })
    else
      expected_str = expected_str:match("^%s*(.-)%s*$")
      local actual

      if target == "status" then
        actual = status
      elseif target:sub(1, 5) == "body." then
        actual = get_body_value(body, target:sub(6))
      else
        actual = get_body_value(body, target)
      end

      local pass = eval_op(actual, op, expected_str)
      table.insert(results, {
        pass = pass,
        msg  = string.format("%-40s → %s  (got: %s)",
          a.expr, pass and "PASS" or "FAIL", tostring(actual)),
      })
    end
  end

  return results
end

-- Format assertion results into display lines + all_pass bool.
function M.format(results)
  local lines    = {}
  local all_pass = true
  for _, r in ipairs(results) do
    if not r.pass then all_pass = false end
    table.insert(lines, (r.pass and "✓ " or "✗ ") .. r.msg)
  end
  return lines, all_pass
end

return M
