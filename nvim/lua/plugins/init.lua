-- Helper: find every .git repo under ~/projects
local function find_repos()
  local projects = vim.fn.expand("~/projects")
  local results, seen = {}, {}
  local handle = io.popen("find " .. projects .. " -maxdepth 3 -name .git -type d 2>/dev/null")
  if handle then
    for line in handle:lines() do
      local repo = vim.fn.fnamemodify(line, ":h")
      if not seen[repo] then
        seen[repo] = true
        table.insert(results, { name = vim.fn.fnamemodify(repo, ":~:."), path = repo })
      end
    end
    handle:close()
  end
  table.sort(results, function(a, b) return a.name < b.name end)
  return results, projects
end

-- Return only Git repositories belonging to the active workspace.
local function active_workspace_repos()
  local ok, workspace = pcall(require, "workspace")
  if not ok then return {} end

  local folders
  if workspace.active() then
    folders = workspace.paths() or {}
  else
    -- With no tab-local workspace, discover the repo containing the current
    -- directory plus child repos beneath it.
    local repos = require("workspace.git").find_repos(vim.fn.getcwd(), 3)
    folders = repos
  end

  local results, seen = {}, {}
  for _, folder in ipairs(folders) do
    local root = vim.trim(vim.fn.system({ "git", "-C", folder, "rev-parse", "--show-toplevel" }))
    if vim.v.shell_error == 0 and root ~= "" and not seen[root] then
      seen[root] = true
      table.insert(results, { name = vim.fn.fnamemodify(root, ":t"), path = root })
    end
  end
  table.sort(results, function(a, b) return a.name < b.name end)
  return results
end

-- Colored columns for the repo pickers (telescope entry_display).
local entry_display = require("telescope.pickers.entry_display")
local repo_displayer = entry_display.create({
  separator = "  ",
  items = {
    { width = 30 },                          -- repo name
    { width = 1 },                           -- dirty/clean icon
    { width = 24 },                          -- branch
    { remaining = true },                    -- counts + ahead/behind (single string)
  },
})

-- Helper: build a colored, one-line git status line for a repo.
-- Returns { display = function, ordinal = string }.
-- Shows: name  dirty/clean icon  branch  unstaged (+staged/+untracked)  ↑ahead↓behind
local function repo_status_line(r)
  local p = r.path
  local branch = vim.trim(vim.fn.system({ "git", "-C", p, "rev-parse", "--abbrev-ref", "HEAD" }))
  local st = vim.fn.system({ "git", "-C", p, "status", "--porcelain" })
  local staged, unstaged, untracked = 0, 0, 0
  for line in (st or ""):gmatch("[^\n]+") do
    local x, y = line:sub(1, 1), line:sub(2, 2)
    if x == "?" then untracked = untracked + 1
    else
      if x ~= " " then staged = staged + 1 end
      if y ~= " " then unstaged = unstaged + 1 end
    end
  end
  local dirty = (staged + unstaged + untracked) > 0
  local icon = dirty and "●" or "○"   -- ● = has changes, ○ = clean

  -- ahead/behind upstream
  local ab = vim.fn.system({ "git", "-C", p, "rev-list", "--left-right", "--count", "@{u}...HEAD" })
  local behind, ahead = ab:match("^(%d+)%s+(%d+)")

  -- Build the trailing segment as a single string.
  local tail = ""
  if dirty then
    tail = string.format("unstaged:%d", unstaged)
    if staged > 0 then tail = tail .. string.format("  staged:%d", staged) end
    if untracked > 0 then tail = tail .. string.format("  untracked:%d", untracked) end
  end
  if behind then
    if tail ~= "" then tail = tail .. "  " end
    tail = tail .. string.format("↑%s ↓%s", ahead or "0", behind)
  end

  return {
    display = function()
      return repo_displayer({
        { r.name, dirty and "TelescopeResultsFunction" or "TelescopeResultsNormal" },
        { icon, dirty and "TelescopeResultsDiffAdd" or "TelescopeResultsComment" },
        { branch, "TelescopeResultsIdentifier" },
        tail == "" and " " or tail,
      })
    end,
    ordinal = r.name,
  }
end

-- Close Neo-tree before opening the nested repo/file pickers. Workspace trees can
-- retain a stale Neo-tree window after a new diff tab is created; clicking that
-- stale window calls Neo-tree's open handler without a tree state.
local function focus_edit_window()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for i = #wins, 1, -1 do
    local win = wins[i]
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "neo-tree" and vim.api.nvim_win_is_valid(win) then
      if #vim.api.nvim_tabpage_list_wins(0) > 1 then
        pcall(vim.api.nvim_win_close, win, true)
      else
        vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
      end
    end
  end
end

local function close_file_or_diff_tab()
  local ok, is_pg_diff = pcall(vim.api.nvim_tabpage_get_var, 0, "pg_diff")
  if ok and is_pg_diff and #vim.api.nvim_list_tabpages() > 1 then
    vim.cmd("tabclose")
    return
  end
  vim.cmd("bdelete")
end

-- Open the current file against HEAD and keep unchanged sections unfolded.
-- New/untracked files get an empty HEAD pane instead of a Fugitive error.
local function open_full_git_diff()
  local working_win = vim.api.nvim_get_current_win()
  local working_buf = vim.api.nvim_get_current_buf()
  local buffer_path = vim.fn.expand("%:p")
  local file = vim.uv.fs_realpath(buffer_path) or vim.fs.normalize(buffer_path)
  local dir = vim.fn.fnamemodify(file, ":h")
  local root_result = vim.system(
    { "git", "-C", dir, "rev-parse", "--show-toplevel" },
    { text = true }
  ):wait()
  local root = root_result.code == 0 and vim.trim(root_result.stdout or "") or ""
  local relative = root ~= "" and vim.fs.relpath(root, file) or nil
  if not relative then
    vim.notify("Cannot diff file outside a Git repository", vim.log.levels.ERROR)
    return
  end

  -- Read the reference side ourselves. This avoids Fugitive treating a file
  -- opened through the workspace symlink as absent and showing a full-file diff.
  local head_result = vim.system(
    { "git", "-C", root, "show", "HEAD:" .. relative },
    { text = true }
  ):wait()
  local head_lines = { "" }
  local reference_label = "[HEAD: absent] " .. relative
  if head_result.code == 0 then
    head_lines = vim.split(head_result.stdout or "", "\n", { plain = true })
    if head_lines[#head_lines] == "" then table.remove(head_lines) end
    if #head_lines == 0 then head_lines = { "" } end
    reference_label = "[HEAD] " .. relative
  end

  vim.cmd("leftabove vnew")
  local reference_buf = vim.api.nvim_get_current_buf()
  vim.bo[reference_buf].buftype = "nofile"
  vim.bo[reference_buf].bufhidden = "wipe"
  vim.bo[reference_buf].swapfile = false
  vim.api.nvim_buf_set_name(reference_buf, reference_label .. " #" .. reference_buf)
  vim.api.nvim_buf_set_lines(reference_buf, 0, -1, false, head_lines)
  vim.b[reference_buf].pg_diff_reference = true
  vim.bo[reference_buf].modifiable = false
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(working_win)
  vim.cmd("diffthis")

  vim.schedule(function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.wo[win].diff then
        vim.wo[win].foldenable = false
        local buf = vim.api.nvim_win_get_buf(win)
        if buf ~= working_buf then vim.b[buf].pg_diff_reference = true end
      end
    end

    -- Fugitive normally focuses the read-only HEAD pane. Return to the working
    -- copy and explicitly leave it editable.
    if vim.api.nvim_win_is_valid(working_win) and vim.api.nvim_buf_is_valid(working_buf) then
      vim.api.nvim_set_current_win(working_win)
      vim.bo[working_buf].modifiable = true
      vim.bo[working_buf].readonly = false
    end
  end)
end

return {
  -- Color scheme (tokyonight — clean, modern)
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("tokyonight-night")
    end,
  },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = { theme = "tokyonight" },
      sections = {
        lualine_c = {
          {
            function() return require("core.path").current() or "[No Name]" end,
          },
        },
      },
    },
  },

  -- File tabs for every open buffer. Click a tab, or use Tab/Shift-Tab.
  {
    "akinsho/bufferline.nvim",
    version = "*",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        mode = "buffers",
        diagnostics = "nvim_lsp",
        always_show_bufferline = true,
        show_close_icon = false,
        custom_filter = function(bufnr)
          -- A pg diff is represented by one file tab; hide its read-only HEAD pane.
          return not vim.b[bufnr].pg_diff_reference
        end,
        offsets = {
          {
            filetype = "neo-tree",
            text = "File Explorer",
            highlight = "Directory",
            separator = true,
          },
        },
      },
    },
    keys = {
      { "<Tab>", "<cmd>BufferLineCycleNext<CR>", desc = "Next file tab" },
      { "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", desc = "Previous file tab" },
      { "<leader>bd", close_file_or_diff_tab, desc = "Close file or diff tab" },
    },
  },

  -- Fuzzy finder (like VSCode Ctrl-P / Cmd-P) + repo switcher
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
    keys = {
      -- <leader>ff and <leader>fg are owned by workspace.nvim so their searches
      -- stay scoped to the active workspace.
      { "<leader>fF", function() require("telescope.builtin").find_files({ cwd = vim.fn.expand("~/projects") }) end, desc = "Find files (all projects)" },
      { "<leader>fG", function() require("telescope.builtin").live_grep({ cwd = vim.fn.expand("~/projects") }) end, desc = "Live grep (all projects)" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", desc = "Document symbols" },
      { "<leader>fS", "<cmd>Telescope lsp_workspace_symbols<CR>", desc = "Workspace symbols" },
      -- Switch working directory to one of your git repos + open its tree.
      -- Shows branch + unstaged count for each repo in the picker.
      { "<leader>pr", function()
          local pickers = require("telescope.pickers")
          local finders = require("telescope.finders")
          local conf = require("telescope.config").values
          local actions = require("telescope.actions")
          local action_state = require("telescope.actions.state")
          local repos = find_repos()
          pickers.new({}, {
            prompt_title = "Switch project repo  (● dirty  ○ clean  unstaged:N)",
            finder = finders.new_table({
              results = repos,
              entry_maker = function(r)
                local s = repo_status_line(r)
                return { value = r, display = s.display, ordinal = s.ordinal }
              end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _)
              actions.select_default:replace(function()
                local sel = action_state.get_selected_entry().value
                actions.close(prompt_bufnr)
                require("neo-tree.command").execute({
                  action = "focus",
                  source = "filesystem",
                  position = "left",
                  dir = sel.path,
                })
              end)
              return true
            end,
          }):find()
      end, desc = "Switch project repo" },
      -- Pick a repo, then one of its changed files, and open the same full
      -- side-by-side Fugitive view used by <leader>gd.
      { "<leader>pg", function()
          focus_edit_window()
          local pickers = require("telescope.pickers")
          local finders = require("telescope.finders")
          local conf = require("telescope.config").values
          local actions = require("telescope.actions")
          local action_state = require("telescope.actions.state")
          local repos = active_workspace_repos()
          if #repos == 0 then
            vim.notify("No Git repositories in the active workspace or current folder", vim.log.levels.WARN)
            return
          end
          local workspace = require("workspace")
          local scope = workspace.active() and ("Workspace: " .. workspace.active()) or ("Folder: " .. vim.fn.getcwd())
          pickers.new({}, {
            prompt_title = scope .. " — Git changes  (● dirty  ○ clean  unstaged:N)",
            finder = finders.new_table({
              results = repos,
              entry_maker = function(r)
                local s = repo_status_line(r)
                return { value = r, display = s.display, ordinal = s.ordinal }
              end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _)
              actions.select_default:replace(function()
                local repo = action_state.get_selected_entry().value
                actions.close(prompt_bufnr)
                vim.schedule(function()
                  require("telescope.builtin").git_status({
                    cwd = repo.path,
                    prompt_title = "Changed files — select for side-by-side diff",
                    attach_mappings = function(status_bufnr, _)
                      actions.select_default:replace(function()
                        local entry = action_state.get_selected_entry()
                        actions.close(status_bufnr)
                        vim.schedule(function()
                          -- Keep the global cwd/workspace unchanged. Telescope may
                          -- return a repo-relative path, so make it absolute here.
                          local path = entry.path
                          if not vim.startswith(path, "/") then
                            path = vim.fs.joinpath(repo.path, path)
                          end

                          -- Open in a fresh tab so this also works when <leader>pg
                          -- was launched while Neo-tree had focus.
                          vim.cmd("tabedit " .. vim.fn.fnameescape(path))
                          vim.api.nvim_tabpage_set_var(0, "pg_diff", true)
                          open_full_git_diff()
                        end)
                      end)
                      return true
                    end,
                  })
                end)
              end)
              return true
            end,
          }):find()
      end, desc = "Git changes (pick repo, side-by-side diff)" },
      -- Git status dashboard: lists every repo with branch + dirty/clean +
      -- unstaged/staged/untracked counts + ahead/behind upstream.
      -- Pick one to open lazygit on it.
      { "<leader>pd", function()
          local pickers = require("telescope.pickers")
          local finders = require("telescope.finders")
          local conf = require("telescope.config").values
          local actions = require("telescope.actions")
          local action_state = require("telescope.actions.state")
          local repos = find_repos()
          local entries = {}
          for _, r in ipairs(repos) do
            local s = repo_status_line(r)
            table.insert(entries, {
              value = { repo = r.path },
              display = s.display,
              ordinal = s.ordinal,
            })
          end
          pickers.new({}, {
            prompt_title = "Repo git status  (● dirty  ○ clean  unstaged:N  ↑ahead ↓behind)",
            finder = finders.new_table({
              results = entries,
              entry_maker = function(e)
                return { value = e.value, display = e.display, ordinal = e.ordinal }
              end,
            }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, _)
              actions.select_default:replace(function()
                local sel = action_state.get_selected_entry().value
                actions.close(prompt_bufnr)
                vim.schedule(function()
                  vim.cmd("cd " .. vim.fn.fnameescape(sel.repo))
                  vim.cmd("LazyGit")
                end)
              end)
              return true
            end,
          }):find()
      end, desc = "Repo git dashboard" },
    },
  },

  -- Treesitter — parser installer (highlighting is built into Neovim 0.12+)
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup({})
      -- Enable core treesitter features for installed parsers
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TreesitterSetup", {}),
        callback = function(args)
          pcall(function()
            if pcall(vim.treesitter.parser.get_parser, args.buf) then
              vim.treesitter.start(args.buf) -- syntax highlighting (Neovim core)
              vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end
          end)
        end,
      })
    end,
  },

  -- Git signs in the gutter
  {
    "lewis6991/gitsigns.nvim",
    opts = {},
    keys = {
      { "]h", function() require("gitsigns").nav_hunk("next") end, desc = "Next git hunk" },
      { "[h", function() require("gitsigns").nav_hunk("prev") end, desc = "Prev git hunk" },
      { "<leader>hp", function() require("gitsigns").preview_hunk() end, desc = "Preview hunk" },
      { "<leader>hr", function() require("gitsigns").reset_hunk() end, desc = "Reset hunk" },
      { "<leader>gb", function() require("gitsigns").blame_line() end, desc = "Blame line" },
    },
  },

  -- Full Git commands and in-editor diffs (:Gdiffsplit).
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "Gdiffsplit", "Gvdiffsplit", "Gedit", "Gread", "Gwrite" },
    keys = {
      {
        "<leader>gd",
        open_full_git_diff,
        desc = "Git diff current file (full side by side)",
      },
    },
  },

  -- lazygit floating window (interactive git UI)
  {
    "kdheepak/lazygit.nvim",
    cmd = "LazyGit",
    keys = {
      { "<leader>gg", "<cmd>LazyGit<CR>", desc = "LazyGit" },
    },
  },

  -- Auto-pairs, surround, comments
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },
  { "kylechui/nvim-surround", version = "*", opts = {} },
  {
    "numToStr/Comment.nvim",
    opts = {},
    keys = {
      { "gcc", mode = "n", desc = "Toggle line comment" },
      { "gc", mode = { "n", "v" }, desc = "Toggle comment" },
    },
  },

  -- Indent guides
  { "lukas-reineke/indent-blankline.nvim", main = "ibl", opts = {} },

  -- Which-key — shows available keybindings (great for learning!)
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  -- Session manager: save/restore a multi-project workspace (open buffers,
  -- window layout, working dir) and resume it later.
  {
    "olimorris/persisted.nvim",
    lazy = false,
    opts = {
      save_dir = vim.fn.expand("~/.local/share/nvim/sessions"),
      autosave = true,            -- auto-save on exit
      should_autosave = function() return true end,
      autoload = false,           -- don't auto-load; pick via Telescope
      use_git_branch = true,      -- separate session per git branch
    },
    keys = {
      { "<leader>ss", "<cmd>Telescope persisted<CR>", desc = "Switch session" },
      { "<leader>sq", function() require("persisted").save(); vim.cmd("qa") end, desc = "Save session & quit" },
    },
    config = function(_, opts)
      require("persisted").setup(opts)
      -- Register the Telescope extension so <leader>ss works
      require("telescope").load_extension("persisted")
    end,
  },

  -- Auto-completion
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()
      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        completion = { completeopt = "menu,menuone,noinsert" },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_locally_jumpable() then luasnip.expand_or_jump()
            else fallback() end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.locally_jumpable(-1) then luasnip.jump(-1)
            else fallback() end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, { { name = "buffer" } }),
      })
    end,
  },

  -- LSP config + Mason (installs language servers automatically)
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      { "williamboman/mason.nvim", opts = {} },
      { "williamboman/mason-lspconfig.nvim", opts = { ensure_installed = { "lua_ls", "ts_ls", "pyright", "gopls", "rust_analyzer" } } },
      { "j-hui/fidget.nvim", opts = {} }, -- LSP progress notifications
    },
    config = function()
      -- Globally configure LSP keymaps on attach
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("LspKeymaps", {}),
        callback = function(ev)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = ev.buf, desc = "LSP: " .. desc })
          end
          map("gd", vim.lsp.buf.definition, "Go to definition")
          map("gD", vim.lsp.buf.declaration, "Go to declaration")
          map("gr", vim.lsp.buf.references, "References")
          map("gi", vim.lsp.buf.implementation, "Implementation")
          map("K", vim.lsp.buf.hover, "Hover doc")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>df", vim.diagnostic.open_float, "Line diagnostics")
          map("[d", vim.diagnostic.goto_prev, "Prev diagnostic")
          map("]d", vim.diagnostic.goto_next, "Next diagnostic")
        end,
      })

      -- Modern Neovim 0.11+ LSP API: vim.lsp.config + vim.lsp.enable
      vim.lsp.config("lua_ls", { settings = { Lua = { diagnostics = { globals = { "vim" } } } } })
      -- typescript-language-server no longer bundles TypeScript. Use the global
      -- tsserver installed by fnm so JavaScript-only repos get LSP support too.
      vim.lsp.config("ts_ls", { init_options = { tsserver = { path = "tsserver" } } })
      vim.lsp.config("pyright", {})
      vim.lsp.config("gopls", {})
      vim.lsp.config("rust_analyzer", {})
      vim.lsp.enable({ "lua_ls", "ts_ls", "pyright", "gopls", "rust_analyzer" })
    end,
  },
}
