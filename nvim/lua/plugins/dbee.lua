-- Database connections often contain private infrastructure details.
-- Keep the complete plugin specification in ~/.config/nvim-local/dbee.lua.
-- See dbee-local.example.lua in this repository.
local local_config = vim.fn.expand("~/.config/nvim-local/dbee.lua")
if vim.fn.filereadable(local_config) == 1 then
  local spec, err = loadfile(local_config)
  if not spec then
    vim.notify("Could not load private dbee config: " .. err, vim.log.levels.ERROR)
    return {}
  end
  return spec()
end

return {}
