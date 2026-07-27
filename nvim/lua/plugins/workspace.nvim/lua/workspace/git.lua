-- workspace/git.lua
-- Git helpers: find repos under a root, get repo status, format a picker row.

local M = {}

-- Find all git repos under search_root up to max_depth levels deep.
function M.find_repos(search_root, max_depth)
  max_depth = max_depth or 6
  local repos = {}
  local seen  = {}

  -- Include the repo that contains search_root itself
  local top = vim.fn.systemlist({ "git", "-C", search_root, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and top[1] and top[1] ~= "" then
    seen[top[1]] = true
    table.insert(repos, top[1])
  end

  local cmd
  if vim.fn.executable("fd") == 1 then
    cmd = { "fd", "--hidden", "--no-ignore", "--type", "d", "--glob", ".git",
            "--max-depth", tostring(max_depth), search_root }
  else
    cmd = { "find", search_root, "-maxdepth", tostring(max_depth), "-type", "d", "-name", ".git" }
  end

  for _, line in ipairs(vim.fn.systemlist(cmd)) do
    if line ~= "" then
      local repo = vim.fn.fnamemodify(line:gsub("/+$", ""), ":h")
      if repo ~= "" and not seen[repo] then
        seen[repo] = true
        table.insert(repos, repo)
      end
    end
  end

  table.sort(repos)
  return repos
end

-- Return a table describing the git status of a single repo directory.
function M.repo_status(repo)
  local porcelain = vim.fn.systemlist({ "git", "-C", repo, "status", "--porcelain" })
  if vim.v.shell_error ~= 0 then
    return { git = false }
  end

  local branch_out = vim.fn.systemlist({ "git", "-C", repo, "branch", "--show-current" })
  local branch = (vim.v.shell_error == 0 and branch_out[1] and branch_out[1] ~= "")
      and branch_out[1] or "HEAD"

  local unstaged, untracked = 0, 0
  for _, line in ipairs(porcelain) do
    if line:sub(1, 2) == "??" then
      untracked = untracked + 1
    elseif line:sub(2, 2) ~= " " then
      unstaged = unstaged + 1
    end
  end

  local ahead, behind = 0, 0
  local counts = vim.fn.systemlist({
    "git", "-C", repo, "rev-list", "--left-right", "--count", "@{upstream}...HEAD",
  })
  if vim.v.shell_error == 0 and counts[1] then
    local b, a = counts[1]:match("(%d+)%s+(%d+)")
    if b then
      behind = tonumber(b) or 0
      ahead  = tonumber(a) or 0
    end
  end

  return {
    git       = true,
    dirty     = #porcelain > 0,
    branch    = branch,
    unstaged  = unstaged,
    untracked = untracked,
    ahead     = ahead,
    behind    = behind,
  }
end

-- Build the display string + highlights table for a Telescope entry.
-- Format: ●/○  <branch>  <folder-name>  unstaged:N  untracked:N  ↑N  ↓N
function M.format_entry(path, s)
  -- Ensure the purple highlight group exists
  vim.api.nvim_set_hl(0, "WorkspaceBranch", { fg = "#c678dd", bold = true })

  if not s.git then
    return "  (not a git repo)  " .. vim.fn.fnamemodify(path, ":t"), {}
  end

  local circle = s.dirty and "●" or "○"
  local str    = circle .. " "
  local hl     = {}

  -- Branch name (highlighted)
  local b_start = #str
  str = str .. s.branch
  table.insert(hl, { { b_start, #str }, "WorkspaceBranch" })

  -- Repo folder name
  str = str .. "  " .. vim.fn.fnamemodify(path, ":t")

  -- Stats (only shown when > 0)
  local extras = {}
  if s.unstaged  > 0 then table.insert(extras, "unstaged:"  .. s.unstaged)  end
  if s.untracked > 0 then table.insert(extras, "untracked:" .. s.untracked) end
  if s.ahead     > 0 then table.insert(extras, "↑" .. s.ahead)              end
  if s.behind    > 0 then table.insert(extras, "↓" .. s.behind)             end
  if #extras > 0 then
    str = str .. "  " .. table.concat(extras, "  ")
  end

  return str, hl
end

return M
