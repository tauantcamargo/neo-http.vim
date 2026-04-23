local M = {}

local _jar_path = vim.fn.stdpath("cache") .. "/neo-http-cookies.txt"

function M.setup(opts)
  if opts and opts.cookie_jar_path then
    _jar_path = opts.cookie_jar_path
  end
end

function M.get_jar_path()
  return _jar_path
end

function M.clear()
  if vim.fn.filereadable(_jar_path) == 1 then
    vim.fn.delete(_jar_path)
  end
  vim.notify("[neo-http] Cookie jar cleared: " .. _jar_path, vim.log.levels.INFO)
end

function M.show()
  if vim.fn.filereadable(_jar_path) == 0 then
    vim.notify("[neo-http] Cookie jar is empty", vim.log.levels.INFO)
    return
  end
  vim.cmd("split " .. vim.fn.fnameescape(_jar_path))
end

return M
