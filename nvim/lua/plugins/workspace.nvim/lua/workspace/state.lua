-- workspace/state.lua
-- Persistence: load/save workspaces.json and track the active workspace.

local M = {}
local cfg = {}
local data = { workspaces = {} }

function M.setup(opts)
  cfg = opts
end

function M.load()
  local f = io.open(cfg.data_file, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return end
  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == "table" then
    data.workspaces = decoded
  end
end

function M.save()
  vim.fn.mkdir(vim.fn.fnamemodify(cfg.data_file, ":h"), "p")
  local f = io.open(cfg.data_file, "w")
  if not f then return end
  f:write(vim.json.encode(data.workspaces))
  f:close()
end

function M.list()
  local names = {}
  for k in pairs(data.workspaces) do table.insert(names, k) end
  table.sort(names)
  return names
end

function M.get(name) return data.workspaces[name] end

-- Workspace selection belongs to the current Neovim tab. New tabs therefore
-- start without a workspace and use their own current directory.
function M.active()
  local active = vim.t.workspace_active
  if type(active) == "string" and data.workspaces[active] then return active end
end

function M.paths()
  local active = M.active()
  return active and data.workspaces[active] or nil
end

function M.set(name, paths)
  data.workspaces[name] = paths
  M.save()
end

function M.delete(name)
  data.workspaces[name] = nil
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local ok, active = pcall(vim.api.nvim_tabpage_get_var, tabpage, "workspace_active")
    if ok and active == name then
      pcall(vim.api.nvim_tabpage_del_var, tabpage, "workspace_active")
    end
  end
  M.save()
end

function M.set_active(name)
  if not data.workspaces[name] then return false end
  vim.t.workspace_active = name
  return true
end

function M.deactivate()
  vim.t.workspace_active = nil
end

function M.status()
  local active = M.active()
  if not active then return "" end
  local paths = data.workspaces[active] or {}
  return string.format(" %s(%d)", active, #paths)
end

return M
