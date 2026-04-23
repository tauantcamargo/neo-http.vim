-- GraphQL body handling.
-- Detects the # [graphql] marker and builds the proper JSON payload.
local M = {}

function M.is_graphql(body)
  if not body then return false end
  return body:match("^%s*#%s*%[graphql%]") ~= nil
end

-- Convert a marked body into {"query":"...","variables":{...}}.
--
-- Input format:
--   # [graphql]
--   query { ... }
--   # [variables]      ← optional
--   { "key": "val" }
function M.build_payload(body)
  local rest = body:gsub("^%s*#%s*%[graphql%]%s*\n?", "")

  local query_part, variables_part = rest:match("^(.-)%s*#%s*%[variables%]%s*\n(.+)$")
  if not query_part then
    query_part     = rest
    variables_part = nil
  end

  query_part = query_part:match("^%s*(.-)%s*$")

  local payload = { query = query_part }

  if variables_part and variables_part:match("%S") then
    local ok, vars = pcall(vim.json.decode, variables_part)
    if ok then
      payload.variables = vars
    else
      vim.notify(
        "[neo-http] GraphQL # [variables] block is not valid JSON — sending without variables",
        vim.log.levels.WARN
      )
    end
  end

  return vim.json.encode(payload)
end

return M
