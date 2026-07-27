return {
  {
    "lervag/vimtex",
    lazy = false,
    init = function()
      -- Use Skim for forward/inverse SyncTeX navigation.
      vim.g.vimtex_view_method = "skim"
      vim.g.vimtex_view_skim_sync = 1
      vim.g.vimtex_view_skim_activate = 1

      -- The recovered manuscript contains Unicode and requires XeLaTeX.
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_compiler_latexmk_engines = {
        ["_"] = "-xelatex",
        xelatex = "-xelatex",
      }
      vim.g.vimtex_compiler_latexmk = {
        build_dir = "",
        callback = 1,
        continuous = 1,
        executable = "latexmk",
        hooks = {},
        options = {
          "-verbose",
          "-file-line-error",
          "-synctex=1",
          "-interaction=nonstopmode",
        },
      }
    end,
    ft = { "tex" },
  },
}
