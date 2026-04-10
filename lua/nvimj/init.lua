local M = {}
M.repl_job_id = 0
M.repl_buf_nr = -1

local config = {
  command = "~/j9.7/bin/jconsole"
}

M.setup = function (user_opts)
  config = vim.tbl_deep_extend("force", config, user_opts or {})
end

M.open_repl = function()
  local current_win = vim.api.nvim_get_current_win()
  -- 1. Create a horizontal split at the bottom
  vim.cmd('botright split')
  -- 2. Resize it (e.g., 15 lines high)
  local buf = vim.api.nvim_create_buf(false, true)
  -- MAKE IT LISTED:
  vim.api.nvim_buf_set_option(buf, 'buflisted', true)
  -- Optional: Give it a name so it's easy to find in :ls
  vim.api.nvim_buf_set_name(buf, "REPL-Terminal")
  vim.api.nvim_win_set_buf(0, buf)

  vim.cmd('resize 10')
  -- 3. Open the terminal and capture the job_id
  M.repl_job_id = vim.fn.termopen(config.command)
  M.repl_buf_nr = buf

  -- Optional: Auto-scroll to bottom on output
  vim.cmd('setlocal scrollback=1000')
  vim.api.nvim_set_current_win(current_win)
end

M.send_to_repl = function()
  while M.repl_job_id == 0 or not vim.api.nvim_buf_is_valid(M.repl_buf_nr) do
    M.open_repl(config.command)
  end

  -- Get current line
  local line = vim.api.nvim_get_current_line()
  -- Send to terminal job (append \n to execute)
  vim.fn.chansend(M.repl_job_id, line .. "\n")
  local windows = vim.api.nvim_list_wins()
  for _, win in ipairs(windows) do
    if vim.api.nvim_win_get_buf(win) == M.repl_buf_nr then
      -- 2. Get the total number of lines in the REPL buffer
      local line_count = vim.api.nvim_buf_line_count(M.repl_buf_nr)
      -- 3. Set the cursor in THAT window to the last line
      -- The API uses (line, col) where line is 1-indexed
      vim.api.nvim_win_set_cursor(win, { line_count, 0 })
    end
  end
end

return M
