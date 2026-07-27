-- Copy this file to ~/.config/nvim-local/dbee.lua and customize it.
-- Never commit the customized file if it contains credentials or private hosts.
return {
  {
    "kndndrj/nvim-dbee",
    dependencies = { "MunifTanjim/nui.nvim" },
    build = function() require("dbee").install() end,
    cmd = { "Dbee" },
    keys = {
      { "<leader>db", function() require("dbee").open() end, desc = "Dbee: toggle database explorer" },
    },
    opts = {
      sources = {
        require("dbee.sources").MemorySource:new({
          {
            id = "local-database",
            name = "Local database",
            type = "postgres",
            url = 'postgres://{{ env "DB_USER" }}:{{ env "DB_PASSWORD" }}@localhost:5432/database?sslmode=disable',
          },
        }, "local"),
      },
    },
  },
}
