local M = {}

function M.current()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then return nil end

  -- Workspace explorer entries are symlinks; show/copy the real file path.
  return vim.uv.fs_realpath(path) or vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

function M.copy()
  local path = M.current()
  if not path then
    vim.notify("Current buffer has no file path", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", path)
  vim.fn.setreg('"', path)
  vim.notify("Copied path: " .. path)
end

return M
