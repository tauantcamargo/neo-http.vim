-- Converts Postman v2.1, Insomnia v4, and Bruno .bru collections into .http files.
local M = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil, "Cannot open file: " .. path end
  local content = f:read("*a")
  f:close()
  return content, nil
end

local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then return false, "Cannot write file: " .. path end
  f:write(content)
  f:close()
  return true, nil
end

-- ── Postman v2.1 ──────────────────────────────────────────────────────────────

local function postman_url(url_obj)
  if type(url_obj) == "string" then return url_obj end
  if type(url_obj) == "table" and url_obj.raw then return url_obj.raw end
  return ""
end

local function postman_headers(headers)
  local lines = {}
  for _, h in ipairs(headers or {}) do
    if not h.disabled then
      table.insert(lines, trim(h.key or "") .. ": " .. trim(h.value or ""))
    end
  end
  return lines
end

local function postman_body(body)
  if not body or body.mode == "none" then return nil, nil end
  if body.mode == "raw" then
    -- Detect content-type from options
    local ct = body.options and body.options.raw and body.options.raw.language
    return body.raw, ct == "json" and "application/json" or nil
  end
  if body.mode == "urlencoded" then
    local parts = {}
    for _, p in ipairs(body.urlencoded or {}) do
      if not p.disabled then
        table.insert(parts, trim(p.key or "") .. "=" .. trim(p.value or ""))
      end
    end
    return table.concat(parts, "&"), "application/x-www-form-urlencoded"
  end
  if body.mode == "formdata" then
    local parts = {}
    for _, p in ipairs(body.formdata or {}) do
      if not p.disabled then
        if p.type == "file" then
          table.insert(parts, trim(p.key or "") .. "=file://" .. trim(p.src or ""))
        else
          table.insert(parts, trim(p.key or "") .. "=" .. trim(p.value or ""))
        end
      end
    end
    return table.concat(parts, "\n"), "multipart/form-data"
  end
  return nil, nil
end

local function postman_item_to_blocks(item, out)
  if item.request then
    local req   = item.request
    local block = { "###" }
    if item.name and item.name ~= "" then
      table.insert(block, "# " .. item.name)
    end

    local url     = postman_url(req.url)
    local headers = postman_headers(req.header)
    local body_str, body_ct = postman_body(req.body)

    table.insert(block, (req.method or "GET") .. " " .. url)

    -- Inject Content-Type if body has one and headers don't already have it
    if body_ct then
      local has_ct = false
      for _, h in ipairs(headers) do
        if h:lower():match("^content%-type:") then has_ct = true; break end
      end
      if not has_ct then
        table.insert(headers, "Content-Type: " .. body_ct)
      end
    end

    for _, h in ipairs(headers) do
      table.insert(block, h)
    end

    if body_str and trim(body_str) ~= "" then
      table.insert(block, "")
      table.insert(block, body_str)
    end

    table.insert(out, table.concat(block, "\n"))
  elseif item.item then
    -- Folder — recurse
    if item.name and item.name ~= "" then
      table.insert(out, "\n###\n# ── " .. item.name .. " ──")
    end
    for _, child in ipairs(item.item) do
      postman_item_to_blocks(child, out)
    end
  end
end

function M.from_postman(json_str)
  local ok, col = pcall(vim.json.decode, json_str)
  if not ok then return nil, "Invalid JSON: " .. tostring(col) end
  if not col.info or not col.item then
    return nil, "Not a Postman v2.1 collection (missing info or item)"
  end

  local blocks = {}
  table.insert(blocks, "# " .. trim(col.info.name or "Imported Collection"))
  table.insert(blocks, "# Imported from Postman")
  table.insert(blocks, "")

  for _, item in ipairs(col.item) do
    postman_item_to_blocks(item, blocks)
  end

  return table.concat(blocks, "\n\n"), nil
end

-- ── Insomnia v4 ───────────────────────────────────────────────────────────────

local function insomnia_body(body)
  if not body then return nil end
  if body.mimeType == "application/x-www-form-urlencoded" then
    local parts = {}
    for _, p in ipairs(body.params or {}) do
      if not p.disabled then
        table.insert(parts, trim(p.name or "") .. "=" .. trim(p.value or ""))
      end
    end
    return table.concat(parts, "&")
  end
  return body.text
end

function M.from_insomnia(json_str)
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then return nil, "Invalid JSON" end

  local resources = data.resources or data
  if type(resources) ~= "table" then
    return nil, "Not an Insomnia v4 export (missing resources)"
  end

  local folders  = {}
  local requests = {}
  for _, r in ipairs(resources) do
    if r._type == "request_group" then
      folders[r._id] = r
    elseif r._type == "request" then
      table.insert(requests, r)
    end
  end

  table.sort(requests, function(a, b)
    return (a.name or "") < (b.name or "")
  end)

  local blocks = {}
  table.insert(blocks, "# Imported from Insomnia")
  table.insert(blocks, "")

  for _, req in ipairs(requests) do
    local block  = { "###" }
    local folder = folders[req.parentId]
    local name   = trim(req.name or "")
    if folder then name = trim(folder.name or "") .. " / " .. name end
    if name ~= "" then table.insert(block, "# " .. name) end

    table.insert(block, (req.method or "GET") .. " " .. trim(req.url or ""))

    for _, h in ipairs(req.headers or {}) do
      if not h.disabled then
        table.insert(block, trim(h.name or "") .. ": " .. trim(h.value or ""))
      end
    end

    local body = insomnia_body(req.body)
    if body and trim(body) ~= "" then
      table.insert(block, "")
      table.insert(block, body)
    end

    table.insert(blocks, table.concat(block, "\n"))
  end

  return table.concat(blocks, "\n\n"), nil
end

-- ── Bruno .bru ────────────────────────────────────────────────────────────────

local function bru_block(content, tag)
  return content:match(tag .. "%s*{([^}]*)}")
end

local function bru_method_url(content)
  for _, m in ipairs({ "get", "post", "put", "delete", "patch", "head", "options" }) do
    local url = content:match("^" .. m .. "%s+(.-)%s*\n")
    if url then return m:upper(), trim(url) end
  end
  return nil, nil
end

function M.from_bruno(bru_str)
  local block = { "###" }

  local meta = bru_block(bru_str, "meta")
  if meta then
    local name = meta:match("name:%s*(.-)%s*,") or meta:match("name:%s*(.-)%s*\n")
    if name and trim(name) ~= "" then
      table.insert(block, "# " .. trim(name))
    end
  end

  local method, url = bru_method_url(bru_str)
  if not method then
    return nil, "Could not parse method/URL from .bru file"
  end
  table.insert(block, method .. " " .. url)

  local headers_block = bru_block(bru_str, "headers")
  if headers_block then
    for line in (headers_block .. "\n"):gmatch("([^\n]*)\n") do
      line = trim(line)
      if line ~= "" then table.insert(block, line) end
    end
  end

  local body_block = bru_block(bru_str, "body:json")
    or bru_block(bru_str, "body:text")
    or bru_block(bru_str, "body")
  if body_block and trim(body_block) ~= "" then
    table.insert(block, "")
    table.insert(block, trim(body_block))
  end

  local out = { "# Imported from Bruno", "", table.concat(block, "\n") }
  return table.concat(out, "\n"), nil
end

-- ── Format Detection ──────────────────────────────────────────────────────────

local function detect_format(path, content)
  if path:match("%.bru$") then return "bruno" end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then return nil, "File is not valid JSON or .bru" end

  if data.info and data.info.schema and data.info.schema:find("v2%.1") then
    return "postman"
  end
  if data.info and data.item then return "postman" end  -- schema-less Postman
  if data._type == "export" or data.resources then return "insomnia" end

  return nil, "Unknown collection format (expected Postman v2.1, Insomnia v4, or .bru)"
end

-- ── Public Entry Point ────────────────────────────────────────────────────────

-- Import source_path → write .http to output_path.
-- Returns true + output_path on success, false + error string on failure.
function M.import(source_path, output_path)
  local content, err = read_file(source_path)
  if not content then return false, err end

  local fmt, det_err = detect_format(source_path, content)
  if not fmt then return false, det_err end

  local result, conv_err
  if fmt == "postman" then
    result, conv_err = M.from_postman(content)
  elseif fmt == "insomnia" then
    result, conv_err = M.from_insomnia(content)
  elseif fmt == "bruno" then
    result, conv_err = M.from_bruno(content)
  end

  if not result then return false, conv_err end

  local ok, write_err = write_file(output_path, result)
  if not ok then return false, write_err end

  return true, output_path
end

return M
