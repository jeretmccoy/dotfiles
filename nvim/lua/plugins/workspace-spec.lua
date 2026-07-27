local function safe_neo_tree_open(state)
  if not state or not state.tree then
    vim.notify("Neo-tree is still refreshing; try opening the file again", vim.log.levels.WARN)
    return
  end
  require("neo-tree.sources.filesystem.commands").open(state)
end

return {
  -- workspace.nvim (local, before publishing)
  {
    dir  = vim.fn.expand("~/.config/nvim/lua/plugins/workspace.nvim"),
    name = "workspace.nvim",
    lazy = false,
    dependencies = {
      "nvim-telescope/telescope.nvim",
      "nvim-neo-tree/neo-tree.nvim",
      "kdheepak/lazygit.nvim",
      "folke/which-key.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("workspace").setup({
        repos_root = "~/projects",
        -- <leader>pg is provided by the Telescope/Fugitive config so selecting a
        -- changed file opens the full side-by-side diff instead of LazyGit.
        keymaps = { git_pick = false },
      })
    end,
  },

  -- neo-tree (required by workspace.nvim explorer)
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    opts = {
      filesystem = {
        -- The workspace explorer has a synthetic symlink root. Never let :cd
        -- (for example from Git commands) replace it with the process cwd.
        bind_to_cwd = false,
        cwd_target = { sidebar = "none", current = "none" },
        -- Workspace files live below a synthetic multi-root. Explicit reveal
        -- handles navigation without letting Neo-tree follow real paths away.
        follow_current_file = { enabled = false },
        filtered_items = { visible = true }, -- show dotfiles and other hidden items
        window = {
          mappings = {
            ["<cr>"] = safe_neo_tree_open,
            ["<2-LeftMouse>"] = safe_neo_tree_open,
          },
        },
      },
    },
  },
}
