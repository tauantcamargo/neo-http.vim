local M = {}

local function base64(str)
  local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local result = {}
  str:gsub("..?.?", function(chunk)
    local b1, b2, b3 = chunk:byte(1), chunk:byte(2), chunk:byte(3)
    local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
    table.insert(result, alpha:sub(math.floor(n / 262144) + 1,     math.floor(n / 262144) + 1))
    table.insert(result, alpha:sub(math.floor(n / 4096) % 64 + 1,  math.floor(n / 4096) % 64 + 1))
    table.insert(result, b2 and alpha:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "=")
    table.insert(result, b3 and alpha:sub(n % 64 + 1, n % 64 + 1) or "=")
  end)
  return table.concat(result)
end

-- Resolve an @auth directive into an Authorization header string.
--
-- Supported:
--   basic user:pass  →  Authorization: Basic <base64(user:pass)>
--   bearer TOKEN     →  Authorization: Bearer TOKEN
function M.resolve(auth_val)
  if not auth_val then return nil end
  local scheme, rest = auth_val:match("^(%S+)%s+(.+)$")
  if not scheme then return nil end

  scheme = scheme:lower()
  if scheme == "basic" then
    return "Authorization: Basic " .. base64(rest)
  elseif scheme == "bearer" then
    return "Authorization: Bearer " .. rest
  end

  vim.notify(
    "[neo-http] @auth: unknown scheme '" .. scheme .. "' — use 'basic' or 'bearer'",
    vim.log.levels.WARN
  )
  return nil
end

return M
