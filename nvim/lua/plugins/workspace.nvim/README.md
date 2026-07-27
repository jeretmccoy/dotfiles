# workspace.nvim

A Neovim plugin for managing named workspaces — each workspace is a curated set of folders from a large repository directory. Scopes Telescope grep/find, LazyGit repo picker, and Neo-tree explorer to only the folders you care about.

## Features

- **Named workspaces** — create multiple workspaces (e.g. `backend`, `frontend`, `sprint-42`), each with their own folder set
- **Telescope-aware** — `live_grep` and `find_files` search only workspace folders when a workspace is active
- **LazyGit repo picker** — shows only workspace repos, with `●/○` dirty indicator, branch name in purple, `unstaged:N`, `untracked:N`, `↑N`, `↓N`
- **Neo-tree explorer** — materialises a symlink view so all workspace folders appear as top-level nodes
- **Persisted** — workspaces are saved to JSON and survive restarts
- **which-key** — registers group hints automatically if which-key is installed

## Requirements

- Neovim ≥ 0.10
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) (for `<leader>e`)
- [lazygit.nvim](https://github.com/kdheepak/lazygit.nvim) (for `<leader>pg`)
- `fd` or `find` on PATH

## Installation

### lazy.nvim

```lua
{
  "jeret-mccoy/workspace.nvim",   -- replace with your GitHub username
  lazy = false,
  config = function()
    require("workspace").setup({
      repos_root = "~/Desktop/repos",   -- where folders are scanned from
    })
  end,
},
```

### Local (before publishing)

```lua
{
  dir  = vim.fn.expand("~/workspace.nvim"),
  name = "workspace.nvim",
  lazy = false,
  config = function()
    require("workspace").setup({
      repos_root = "~/Desktop/repos",
    })
  end,
},
```

## Configuration

```lua
require("workspace").setup({
  -- Directory scanned when adding folders to a workspace
  repos_root = "~/Desktop/repos",

  -- Where workspaces are persisted (default: stdpath("data")/workspaces.json)
  data_file = vim.fn.stdpath("data") .. "/workspaces.json",

  -- Override any keymap or set to "" / false to disable
  keymaps = {
    new      = "<leader>wn",   -- create new workspace
    switch   = "<leader>ws",   -- activate a workspace
    add      = "<leader>wa",   -- add folder(s) to active workspace
    remove   = "<leader>wr",   -- remove folder(s) from active workspace
    edit     = "<leader>we",   -- replace entire folder set
    delete   = "<leader>wd",   -- delete a workspace
    clear    = "<leader>wc",   -- deactivate (keep workspaces)
    info     = "<leader>wi",   -- show active workspace info
    explorer = "<leader>e",    -- Neo-tree (workspace-aware)
    grep     = "<leader>fg",   -- live_grep (workspace-aware)
    files    = "<leader>ff",   -- find_files (workspace-aware)
    git_pick = "<leader>pg",   -- LazyGit repo picker
  },
})
```

## Keymaps

| Key | Action |
|-----|--------|
| `<leader>wn` | **New** workspace — prompt for name, multi-select folders (Tab toggles, Enter confirms) |
| `<leader>ws` | **Switch** active workspace |
| `<leader>wa` | **Add** folder(s) to active workspace |
| `<leader>wr` | **Remove** folder(s) from active workspace |
| `<leader>we` | **Edit** — replace entire folder set |
| `<leader>wd` | **Delete** a workspace |
| `<leader>wc` | **Clear** — deactivate without deleting |
| `<leader>wi` | **Info** — list folders in active workspace |
| `<leader>e`  | Explorer — shows workspace folders as top-level nodes in Neo-tree |
| `<leader>fg` | Live grep — scoped to workspace folders |
| `<leader>ff` | Find files — scoped to workspace folders |
| `<leader>pg` | LazyGit picker — shows workspace repos with git status |

## Commands

`:WorkspaceNew`, `:WorkspaceSwitch`, `:WorkspaceAdd`, `:WorkspaceRemove`, `:WorkspaceEdit`, `:WorkspaceDelete`, `:WorkspaceClear`, `:WorkspaceInfo`, `:LazyGitPick`

## LazyGit picker format

```
● main        my-api      unstaged:3  untracked:1  ↑2 ↓1
○ DEV-1714    mirth-channels  ↑1
○ main        clean-client
```

- `●` dirty, `○` clean
- Branch name in purple
- `unstaged:N` / `untracked:N` / `↑N` / `↓N` shown only when > 0
- Dirty repos sort to the top

## Statusline

Call `require("workspace").status()` from your statusline plugin to show the active workspace name and folder count (e.g. ` sprint-42(4)`).

### lualine example

```lua
lualine_c = {
  "filename",
  { function() return require("workspace").status() end, color = { fg = "#61afef", bold = true } },
},
```

## Plugin structure

```
workspace.nvim/
├── lua/workspace/
│   ├── init.lua    -- setup() + all commands + public API
│   ├── state.lua   -- JSON persistence + active workspace state
│   ├── ui.lua      -- Telescope multi-select picker + directory scanner
│   ├── view.lua    -- symlink view materialisation for Neo-tree
│   └── git.lua     -- repo discovery, git status, picker row formatter
└── plugin/
    └── workspace.lua  -- (empty — users call setup() explicitly)
```
