-- workspace/view.lua
-- Materialises a temporary directory of symlinks, one per workspace folder.
-- Neo-tree opens this dir so every workspace folder appears as a top-level node.

local M = {}

local function workspace_view_dir()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return vim.fn.stdpath("data") .. "/workspace-view/tab-" .. tostring(tabpage)
end

local function entries(paths)
  local result, used = {}, {}
  for _, path in ipairs(paths) do
    local base = vim.fn.fnamemodify(path, ":t")
    local name = base
    local i = 1
    while used[name] do
      name = base .. "-" .. i
      i = i + 1
    end
    used[name] = true
    table.insert(result, { path = vim.fs.normalize(path), name = name })
  end
  return result
end

function M.materialize(paths, _label)
  local workspace_view = workspace_view_dir()
  vim.fn.delete(workspace_view, "rf")
  vim.fn.mkdir(workspace_view, "p")

  for _, entry in ipairs(entries(paths)) do
    local link = workspace_view .. "/" .. entry.name
    local ok, err = pcall(vim.uv.fs_symlink, entry.path, link, { dir = true })
    if not ok then
      vim.notify("[workspace.nvim] symlink failed for " .. entry.path .. ": " .. tostring(err), vim.log.levels.WARN)
    end
  end

  return workspace_view
end

-- Translate a real file path to its location in the symlink workspace view.
function M.virtual_path(path, paths)
  local normalized = vim.fs.normalize(path)
  local workspace_view = workspace_view_dir()
  for _, entry in ipairs(entries(paths)) do
    if normalized == entry.path then
      return workspace_view .. "/" .. entry.name
    end
    local prefix = entry.path .. "/"
    if normalized:sub(1, #prefix) == prefix then
      return workspace_view .. "/" .. entry.name .. "/" .. normalized:sub(#prefix + 1)
    end
  end
end

return M
