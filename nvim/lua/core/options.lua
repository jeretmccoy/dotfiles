-- Leader key (space) — used for most plugin shortcuts
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Basic options
local o = vim.opt
o.number = true           -- line numbers
o.relativenumber = true   -- relative line numbers
o.mouse = "a"             -- enable mouse
o.showmode = false        -- lualine handles mode display
o.clipboard = "unnamedplus"
o.breakindent = true
o.undofile = true
o.ignorecase = true
o.smartcase = true
o.signcolumn = "yes"
o.updatetime = 250
o.timeoutlen = 300
o.splitright = true
o.splitbelow = true
o.termguicolors = true
o.expandtab = true
o.tabstop = 2
o.shiftwidth = 2
o.completeopt = "menu,menuone,noselect"

-- Keymaps
local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit" })
map("n", "<leader>bc", require("core.path").copy, { desc = "Copy full file path" })
-- Window navigation (Ctrl + hjkl)
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
-- Move lines up/down in visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move up" })
-- Better indenting (keeps selection)
map("v", "<", "<gv")
map("v", ">", ">gv")
