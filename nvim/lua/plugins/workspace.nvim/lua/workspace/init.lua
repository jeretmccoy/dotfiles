-- workspace/init.lua
-- Main entry point. Call require("workspace").setup(opts) from your config.

local M = {}

local state = require("workspace.state")
local ui    = require("workspace.ui")
local view  = require("workspace.view")
local git   = require("workspace.git")

-- ── Defaults ──────────────────────────────────────────────────────────────────

local defaults = {
  -- Root directory scanned when picking folders for a workspace.
  repos_root = "~/Desktop/repos",

  -- Where workspaces are persisted.
  data_file  = vim.fn.stdpath("data") .. "/workspaces.json",

  -- Set any key to "" or false to disable that mapping.
  keymaps = {
    new      = "<leader>wn",   -- new workspace
    switch   = "<leader>ws",   -- switch active workspace
    add      = "<leader>wa",   -- add folder(s)
    remove   = "<leader>wr",   -- remove folder(s)
    edit     = "<leader>we",   -- replace entire folder set
    delete   = "<leader>wd",   -- delete workspace
    clear    = "<leader>wc",   -- deactivate (keep workspaces)
    info     = "<leader>wi",   -- show active workspace info
    explorer = "<leader>e",    -- neo-tree (workspace-aware)
    grep     = "<leader>fg",   -- live_grep (workspace-aware)
    files    = "<leader>ff",   -- find_files (workspace-aware)
    git_pick = "<leader>pg",   -- lazygit repo picker
  },
}

-- ── Public API ─────────────────────────────────────────────────────────────────

function M.active()           return state.active()  end
function M.paths()            return state.paths()   end
function M.list()             return state.list()    end
function M.get(name)          return state.get(name) end
function M.save_ws(name, p)   state.set(name, p)     end
function M.delete(name)       state.delete(name)     end
function M.status()           return state.status()  end
function M.materialize_view() return view.materialize(state.paths() or {}, state.active()) end

function M.set_active(name)
  if state.set_active(name) then
    vim.notify("Workspace: " .. name, vim.log.levels.INFO)
    return true
  end
  vim.notify("Workspace not found: " .. name, vim.log.levels.WARN)
  return false
end

function M.deactivate()
  state.deactivate()
  vim.notify("Workspace cleared", vim.log.levels.INFO)
end

function M.info()
  if not state.active() then
    vim.notify("No active workspace", vim.log.levels.INFO)
    return
  end
  local paths = state.paths() or {}
  local lines = { "Workspace: " .. state.active() }
  for _, p in ipairs(paths) do
    table.insert(lines, "  " .. vim.fn.fnamemodify(p, ":~"))
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- ── Workspace management commands ──────────────────────────────────────────────

function M.new_workspace()
  local root = vim.fn.expand(M._config.repos_root)
  vim.ui.input({ prompt = "Workspace name: " }, function(name)
    if not name or name == "" then return end
    local dirs = ui.scan_dirs(root, 1)
    if #dirs == 0 then
      vim.notify("No folders found under " .. root, vim.log.levels.WARN)
      return
    end
    ui.multi_pick("New workspace '" .. name .. "' — pick folders", dirs, {}, function(selected)
      if #selected == 0 then
        vim.notify("Nothing selected — workspace not saved", vim.log.levels.WARN)
        return
      end
      state.set(name, selected)
      M.set_active(name)
    end)
  end)
end

function M.switch_workspace()
  local names = state.list()
  if #names == 0 then
    vim.notify("No workspaces defined. Use WorkspaceNew", vim.log.levels.WARN)
    return
  end
  vim.ui.select(names, {
    prompt = "Activate workspace",
    format_item = function(n)
      local p = state.get(n) or {}
      return string.format("%s  (%d folders)", n, #p)
    end,
  }, function(choice)
    if choice then M.set_active(choice) end
  end)
end

function M.add_to_workspace()
  local name = state.active()
  if not name then
    vim.notify("No active workspace. Switch first.", vim.log.levels.WARN)
    return
  end
  local dirs    = ui.scan_dirs(vim.fn.expand(M._config.repos_root), 1)
  local current = state.get(name) or {}
  local in_ws   = {}
  for _, p in ipairs(current) do in_ws[p] = true end
  local available = {}
  for _, d in ipairs(dirs) do
    if not in_ws[d] then table.insert(available, d) end
  end
  if #available == 0 then
    vim.notify("All folders already in '" .. name .. "'", vim.log.levels.INFO)
    return
  end
  ui.multi_pick("Add to '" .. name .. "'", available, {}, function(selected)
    if #selected == 0 then return end
    for _, p in ipairs(selected) do table.insert(current, p) end
    table.sort(current)
    state.set(name, current)
    vim.notify("Added " .. #selected .. " folder(s) to " .. name)
  end)
end

function M.remove_from_workspace()
  local name = state.active()
  if not name then
    vim.notify("No active workspace", vim.log.levels.WARN)
    return
  end
  local current = state.get(name) or {}
  if #current == 0 then
    vim.notify("Workspace is empty", vim.log.levels.INFO)
    return
  end
  ui.multi_pick("Remove from '" .. name .. "'", current, {}, function(selected)
    if #selected == 0 then return end
    local drop = {}
    for _, p in ipairs(selected) do drop[p] = true end
    local kept = {}
    for _, p in ipairs(current) do
      if not drop[p] then table.insert(kept, p) end
    end
    state.set(name, kept)
    vim.notify("Removed " .. #selected .. " folder(s) from " .. name)
  end)
end

function M.edit_workspace()
  local name = state.active()
  if not name then
    vim.notify("No active workspace", vim.log.levels.WARN)
    return
  end
  local root    = vim.fn.expand(M._config.repos_root)
  local dirs    = ui.scan_dirs(root, 1)
  local current = state.get(name) or {}
  local seen    = {}
  for _, d in ipairs(dirs) do seen[d] = true end
  for _, p in ipairs(current) do
    if not seen[p] then table.insert(dirs, p); seen[p] = true end
  end
  table.sort(dirs)
  ui.multi_pick("REPLACE workspace '" .. name .. "' — select final set", dirs, current, function(selected)
    if #selected == 0 then
      vim.notify("Nothing selected — keeping previous", vim.log.levels.WARN)
      return
    end
    state.set(name, selected)
    vim.notify("Updated workspace: " .. name)
  end)
end

function M.delete_workspace()
  local names = state.list()
  if #names == 0 then
    vim.notify("No workspaces to delete", vim.log.levels.WARN)
    return
  end
  vim.ui.select(names, { prompt = "Delete workspace" }, function(choice)
    if choice then
      state.delete(choice)
      vim.notify("Deleted: " .. choice)
    end
  end)
end

-- ── LazyGit repo picker ────────────────────────────────────────────────────────

local function open_lazygit_picker()
  local ws_paths = state.paths()
  local repos

  if ws_paths and #ws_paths > 0 then
    repos = vim.deepcopy(ws_paths)
    table.sort(repos)
  else
    repos = git.find_repos(vim.loop.cwd())
  end

  if #repos == 0 then
    vim.notify("[workspace.nvim] No git repos found", vim.log.levels.WARN)
    return
  end

  local function open(path)
    local ok, lg = pcall(require, "lazygit")
    if ok then lg.lazygit(path)
    else vim.notify("[workspace.nvim] lazygit.nvim not installed", vim.log.levels.ERROR)
    end
  end

  if #repos == 1 then open(repos[1]); return end

  local ok_p, pickers = pcall(require, "telescope.pickers")
  if not ok_p then
    -- Fallback to vim.ui.select
    vim.ui.select(repos, {
      prompt = "Select git repo",
      format_item = function(p) return vim.fn.fnamemodify(p, ":~") end,
    }, function(choice) if choice then open(choice) end end)
    return
  end

  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- Build entries with git status
  local entries = {}
  for _, repo in ipairs(repos) do
    table.insert(entries, { path = repo, status = git.repo_status(repo) })
  end
  -- Dirty repos first, then alphabetical
  table.sort(entries, function(a, b)
    if a.status.dirty ~= b.status.dirty then return a.status.dirty end
    return a.path < b.path
  end)

  pickers.new({}, {
    prompt_title = "Git repos" .. (state.active() and (" [" .. state.active() .. "]") or ""),
    finder = finders.new_table({
      results = entries,
      entry_maker = function(item)
        return {
          value   = item.path,
          ordinal = item.path,
          display = function(_)
            return git.format_entry(item.path, item.status)
          end,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel and sel.value then
          vim.schedule(function() open(sel.value) end)
        end
      end)
      return true
    end,
  }):find()
end

-- ── Keymaps ────────────────────────────────────────────────────────────────────

local function map(key, fn, desc)
  if not key or key == "" or key == false then return end
  vim.keymap.set("n", key, fn, { desc = desc })
end

local function open_workspace_explorer(reveal_file, focus)
  local paths = state.paths()
  if not paths or #paths == 0 then
    require("neo-tree.command").execute({
      action = focus == false and "show" or "focus",
      source = "filesystem",
      position = "left",
      dir = vim.fn.getcwd(),
      reveal_file = reveal_file,
    })
    return
  end

  local vdir = view.materialize(paths, state.active())
  local virtual_file = reveal_file and view.virtual_path(reveal_file, paths) or nil

  -- Session/tab changes can leave a visible Neo-tree buffer whose manager
  -- state has already been disposed. Recreate the filesystem source instead
  -- of focusing that stale buffer (which crashes on the next click/open).
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if ok then
    pcall(manager.dispose, "filesystem", vim.api.nvim_get_current_tabpage())
    pcall(manager.dispose_invalid_tabs)
  end

  vim.schedule(function()
    require("neo-tree.command").execute({
      action = focus == false and "show" or "focus",
      source = "filesystem",
      position = "left",
      dir = vdir,
      reveal_file = virtual_file,
    })
  end)
end

local function reveal_after_telescope_selection()
  vim.schedule(function()
    local file = vim.api.nvim_buf_get_name(0)
    if file ~= "" then open_workspace_explorer(file, false) end
  end)
end

local function setup_keymaps(km)
  map(km.new,      M.new_workspace,         "New workspace")
  map(km.switch,   M.switch_workspace,      "Switch workspace")
  map(km.add,      M.add_to_workspace,      "Add folder to workspace")
  map(km.remove,   M.remove_from_workspace, "Remove folder from workspace")
  map(km.edit,     M.edit_workspace,        "Edit (replace) workspace")
  map(km.delete,   M.delete_workspace,      "Delete workspace")
  map(km.clear,    M.deactivate,            "Clear active workspace")
  map(km.info,     M.info,                  "Workspace info")
  map(km.git_pick, open_lazygit_picker,     "Pick repo → LazyGit")

  map(km.grep, function()
    local actions = require("telescope.actions")
    require("telescope.builtin").live_grep({
      search_dirs = state.paths(),
      attach_mappings = function()
        actions.select_default:enhance({ post = reveal_after_telescope_selection })
        return true
      end,
    })
  end, "Find text (workspace-aware)")

  map(km.files, function()
    local actions = require("telescope.actions")
    require("telescope.builtin").find_files({
      search_dirs = state.paths(),
      hidden = true,
      attach_mappings = function()
        actions.select_default:enhance({ post = reveal_after_telescope_selection })
        return true
      end,
    })
  end, "Find files (workspace-aware)")

  map(km.explorer, function()
    open_workspace_explorer(nil, true)
  end, "Explorer (workspace-aware)")
end

-- ── Commands ───────────────────────────────────────────────────────────────────

local function setup_commands()
  local cmds = {
    WorkspaceNew    = M.new_workspace,
    WorkspaceSwitch = M.switch_workspace,
    WorkspaceAdd    = M.add_to_workspace,
    WorkspaceRemove = M.remove_from_workspace,
    WorkspaceEdit   = M.edit_workspace,
    WorkspaceDelete = M.delete_workspace,
    WorkspaceClear  = M.deactivate,
    WorkspaceInfo   = M.info,
    LazyGitPick     = open_lazygit_picker,
  }
  for name, fn in pairs(cmds) do
    vim.api.nvim_create_user_command(name, fn, {})
  end
end

-- ── which-key (optional) ───────────────────────────────────────────────────────

local function setup_which_key(km)
  local ok, wk = pcall(require, "which-key")
  if not ok then return end

  -- Derive the workspace group prefix from the "new" key (e.g. <leader>wn → <leader>w)
  local ws_prefix = km.new and km.new:sub(1, #km.new - 1) or "<leader>w"

  local items = { { ws_prefix, group = "Workspace" } }
  local function wk_add(key, desc)
    if key and key ~= "" and key ~= false then
      table.insert(items, { key, desc = desc })
    end
  end
  wk_add(km.new,      "New workspace")
  wk_add(km.switch,   "Switch workspace")
  wk_add(km.add,      "Add folder")
  wk_add(km.remove,   "Remove folder")
  wk_add(km.edit,     "Edit (replace) workspace")
  wk_add(km.delete,   "Delete workspace")
  wk_add(km.clear,    "Clear active workspace")
  wk_add(km.info,     "Workspace info")
  wk_add(km.git_pick, "Pick repo → LazyGit")
  wk_add(km.explorer, "Explorer")
  wk_add(km.grep,     "Find text")
  wk_add(km.files,    "Find files")
  wk.add(items)
end

-- ── setup() ────────────────────────────────────────────────────────────────────

function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", defaults, opts or {})
  M._config.repos_root = vim.fn.expand(M._config.repos_root)

  state.setup({ data_file = M._config.data_file })
  state.load()

  setup_keymaps(M._config.keymaps)
  setup_commands()
  setup_which_key(M._config.keymaps)
end

return M
