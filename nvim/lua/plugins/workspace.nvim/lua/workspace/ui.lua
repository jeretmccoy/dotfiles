-- workspace/ui.lua
-- Telescope multi-select picker and directory scanner.

local M = {}

function M.scan_dirs(root, max_depth)
  max_depth = max_depth or 1
  local cmd
  if vim.fn.executable("fd") == 1 then
    cmd = { "fd", "--type", "d", "--max-depth", tostring(max_depth), ".", root }
  else
    cmd = { "find", root, "-maxdepth", tostring(max_depth), "-mindepth", "1", "-type", "d" }
  end
  local lines = vim.fn.systemlist(cmd)
  local dirs = {}
  for _, line in ipairs(lines) do
    local clean = line:gsub("/+$", "")
    if clean ~= "" and clean ~= root then
      table.insert(dirs, clean)
    end
  end
  table.sort(dirs)
  return dirs
end

-- Telescope multi-select picker.
-- Tab toggles selection, Enter confirms. Calls cb({list of selected paths}).
function M.multi_pick(title, items, preselected, cb)
  local pickers     = require("telescope.pickers")
  local finders     = require("telescope.finders")
  local conf        = require("telescope.config").values
  local actions     = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local pre = {}
  for _, p in ipairs(preselected or {}) do pre[p] = true end

  pickers.new({}, {
    prompt_title = title .. "  (Tab=toggle  Enter=confirm)",
    finder = finders.new_table({
      results = items,
      entry_maker = function(p)
        return {
          value   = p,
          display = (pre[p] and "● " or "  ") .. vim.fn.fnamemodify(p, ":~"),
          ordinal = p,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local picker   = action_state.get_current_picker(prompt_bufnr)
        local multi    = picker:get_multi_selection()
        local selected = {}
        if #multi > 0 then
          for _, s in ipairs(multi) do table.insert(selected, s.value) end
        else
          local sel = action_state.get_selected_entry()
          if sel then table.insert(selected, sel.value) end
        end
        actions.close(prompt_bufnr)
        cb(selected)
      end)
      return true
    end,
  }):find()
end

return M
