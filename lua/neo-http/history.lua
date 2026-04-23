-- In-memory ring buffer keyed by request name.
-- Nothing is persisted to disk.
local M = {}

local _config = { max_per_key = 20 }
local _store  = {}  -- { [name] = { {result, is_json, timestamp}, ... } }

function M.setup(opts)
  _config.max_per_key = (opts and opts.history_max) or 20
end

function M.push(name, result, is_json)
  name = name or "unnamed"
  if not _store[name] then _store[name] = {} end
  table.insert(_store[name], 1, {
    result    = result,
    is_json   = is_json,
    timestamp = os.time(),
  })
  if #_store[name] > _config.max_per_key then
    table.remove(_store[name])
  end
end

function M.get(name)
  return _store[name] or {}
end

function M.list_names()
  local names = {}
  for name in pairs(_store) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.clear()
  _store = {}
  vim.notify("[neo-http] Response history cleared", vim.log.levels.INFO)
end

return M
