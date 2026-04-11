local M = {}
M.repl_job_id = 0
M.repl_buf_nr = -1

local config = {
  command = "~/j9.7/bin/jconsole"
}
local ns_id = vim.api.nvim_create_namespace('repl_marks')

M.setup = function (user_opts)
  config = vim.tbl_deep_extend("force", config, user_opts or {})

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = 0,     -- Current buffer
    callback = function()
      local line_idx = vim.api.nvim_win_get_cursor(0)[1] - 1
      local mark_id = line_idx + 1

      -- Delete the mark for this line if it exists
      -- This signals that the line is no longer "in sync" with the REPL
      pcall(vim.api.nvim_buf_del_extmark, 0, ns_id, mark_id)
    end
  })
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

local function apply_marks(line_idx)
  local mark_id = line_idx + 1

  vim.api.nvim_buf_set_extmark(0, ns_id, line_idx, 0, {
    id = mark_id,
    virt_text = { { " ✓ ", "DiagnosticOk" } }, -- Virtual text at end of line
    virt_text_pos = "eol", -- Position at End Of Line
    line_hl_group = "CursorLine", -- Optional: highlight the line
    sign_text = "»", -- Optional: put a sign in the gutter
    sign_hl_group = "String",
  })
end

local function scroll_terminal()
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

M.send_to_repl = function(type)
  print("here")
  while M.repl_job_id == 0 or not vim.api.nvim_buf_is_valid(M.repl_buf_nr) do
    M.open_repl()
  end

  local start_mark = vim.api.nvim_buf_get_mark(0, "[")
  local end_mark = vim.api.nvim_buf_get_mark(0, "]")

  local start_line = start_mark[1] - 1
  local end_line = end_mark[1]

  -- For 'char' motions (like 'iw'), we might want just the words.
  -- But for REPLs, 'line' is usually safer.
  local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
  local text = table.concat(lines, "\n") .. "\n"

  -- Send to terminal job (append \n to execute)
  vim.fn.chansend(M.repl_job_id, text)

  scroll_terminal()

  for i = start_line, end_line - 1 do
    apply_marks(i)
  end
end

M.send_motion = function()
  print("HERE")
    -- Set the operatorfunc to our Lua function
    -- Note: We use a global wrapper because operatorfunc traditionally 
    -- expects a string pointing to a globally accessible function.
  _G.repl_op_func = M.send_to_repl
  vim.go.operatorfunc = "v:lua.repl_op_func"

  -- Return the keys that trigger the operator
  return "g@"
end

return M
