-- Formats XML and HTML response bodies using external tools when available.
-- Falls back to raw text if the required tool is not installed.
local M = {}

local function has_cmd(cmd)
  return vim.fn.executable(cmd) == 1
end

function M.format_xml(xml_str)
  if not has_cmd("xmllint") then return xml_str end
  local result = vim.system({ "xmllint", "--format", "-" }, { stdin = xml_str }):wait()
  if result.code == 0 and result.stdout and result.stdout ~= "" then
    return result.stdout
  end
  return xml_str
end

function M.format_html(html_str)
  if has_cmd("prettier") then
    local result = vim.system(
      { "prettier", "--parser", "html" },
      { stdin = html_str }
    ):wait()
    if result.code == 0 and result.stdout and result.stdout ~= "" then
      return result.stdout
    end
  end
  return html_str
end

-- Detect content-type and format accordingly.
-- Returns { content = string, filetype = string }
function M.detect_and_format(raw_response, body, is_json)
  if is_json then return { content = body, filetype = "json" } end

  local ct = raw_response:lower():match("content%-type:%s*([^\r\n;]+)")
  if ct then
    ct = ct:match("^%s*(.-)%s*$")
    if ct:find("application/xml") or ct:find("text/xml") then
      return { content = M.format_xml(body), filetype = "xml" }
    end
    if ct:find("text/html") then
      return { content = M.format_html(body), filetype = "html" }
    end
  end

  return { content = body, filetype = "text" }
end

return M
