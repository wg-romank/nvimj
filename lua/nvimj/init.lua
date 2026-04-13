local M = {}
M.repl_job_id = 0
M.repl_buf_nr = -1

local config = {
  -- command = "~/j9.7/bin/jconsole"
  command = 'python'
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
  while M.repl_job_id == 0 or not vim.api.nvim_buf_is_valid(M.repl_buf_nr) do
    M.open_repl()
  end

  local type_map = {
    char = "v",       -- character-wise
    line = "V",       -- line-wise
    block = "\22"     -- block-wise (CTRL-V as a raw byte)
  }

  local mtype = type_map[type] or type

  local start_pos = vim.fn.getpos("'[")
  local end_pos = vim.fn.getpos("']")

  -- For 'char' motions (like 'iw'), we might want just the words.
  -- But for REPLs, 'line' is usually safer.
  local region = vim.fn.getregion(start_pos, end_pos, { type = mtype })
  local text = table.concat(region, "\n") .. "\n"

  -- Send to terminal job (append \n to execute)
  vim.fn.chansend(M.repl_job_id, text) -- on stdout set marks

  scroll_terminal()

  for i = start_pos[2] - 1, end_pos[2] - 1 do
    apply_marks(i)
  end
end

M.send_motion = function()
    -- Set the operatorfunc to our Lua function
    -- Note: We use a global wrapper because operatorfunc traditionally 
    -- expects a string pointing to a globally accessible function.
  _G.repl_op_func = M.send_to_repl
  vim.go.operatorfunc = "v:lua.repl_op_func"

  return "g@"
end

local curl = require("plenary.curl")

local function insert_at_cursor(text)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  row = row - 1 -- Convert to 0-indexed for API calls

  -- 1. Split the string by newlines
  -- 'true' as the last argument handles trailing newlines correctly
  local lines = vim.split(text, "\n", { plain = true })

  -- 2. Insert the lines
  -- nvim_buf_set_text(buffer, start_row, start_col, end_row, end_col, replacement_lines)
  vim.api.nvim_buf_set_text(buf, row, col, row, col, lines)

  -- 3. Calculate the NEW cursor position
  local new_row, new_col
  if #lines > 1 then
    -- If there were newlines, the new row is:
    -- original row + number of new lines (lines - 1)
    new_row = row + (#lines - 1)
    -- The new column is just the length of that last partial line
    new_col = #lines[#lines]
  else
    -- If it's a single line chunk, just shift the column right
    new_row = row
    new_col = col + #lines[1]
  end

  -- 4. Set the cursor (API uses 1-indexing for rows, 0-indexing for cols)
  vim.api.nvim_win_set_cursor(win, { new_row + 1, new_col })
end

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local timer = vim.loop.new_timer()
local frame = 1

local function start_spinner()
  timer:start(0, 100, vim.schedule_wrap(function()
    vim.api.nvim_echo({{ spinner_frames[frame] .. " Gemini is thinking...", "Normal" }}, false, {})
    frame = (frame % #spinner_frames) + 1
  end))
end

local function stop_spinner()
  timer:stop()
  vim.api.nvim_echo({{ "", "Normal" }}, false, {}) -- Clear the line
end

local partial_data = ""

local function greedy_parse_and_insert(chunk)
  -- 1. Accumulate chunks (in case a JSON object is split across two network packets)
  partial_data = partial_data .. chunk

  -- 2. Pattern to find the value of the "text" key in Gemini's JSON
  -- This looks for: "text": " followed by any characters until a non-escaped "
  -- The [^\"]+ handles the content inside the quotes
  local pattern = '"text"%s*:%s*"([^"]+)"'

  local last_match_end = 0
  local batch_text = "" -- Accumulate all text from this chunk here

  -- 1. Collect all matches in this chunk first
  for text_match, match_end in partial_data:gmatch(pattern .. "()") do
    local clean_text = text_match:gsub("\\n", "\n")
                                 :gsub("\\t", "\t")
                                 :gsub("\\\"", "\"")
    
    batch_text = batch_text .. clean_text
    last_match_end = match_end
  end

  -- 2. If we found any text, do ONE update for the whole batch
  if #batch_text > 0 then
    vim.schedule(function()
      insert_at_cursor(batch_text)
    end)
  end

  -- 4. Keep only the unprocessed "tail" of the string for the next chunk
  if last_match_end > 0 then
    partial_data = partial_data:sub(last_match_end)
  end
end

local function prepare_new_line()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local row, _ = unpack(vim.api.nvim_win_get_cursor(win))
  
  -- Get content of the current line
  local line_content = vim.api.nvim_get_current_line()
  
  if line_content:gsub("%s+", "") ~= "" then
    -- Line isn't empty, create a new one below
    vim.api.nvim_buf_set_lines(buf, row, row, false, { "" })
    vim.api.nvim_win_set_cursor(win, { row + 1, 0 })
  else
    -- Line is empty, just make sure we are at column 0
    vim.api.nvim_win_set_cursor(win, { row, 0 })
  end
end

M.ask_gemini = function()
  local api_key = os.getenv("GOOGLE_API_KEY")
  local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent"

  local prompt = vim.api.nvim_get_current_line()
  -- print("Prompt " .. prompt)

  prepare_new_line()
  start_spinner()

  curl.post(url, {
    raw = { "--no-buffer", "--compressed", "-N" }, -- Disable curl's internal buffering
    headers = {
      ["Content-Type"] = "application/json",
      ["x-goog-api-key"] = api_key,
    },
    body = vim.json.encode({
      contents = { {
        parts = { { text = prompt } }
      } }
    }),
    stream = function(err, data)
      if err then
        -- print("Error: " .. err)
        return
      end

      if data then
        -- 'data' is a single chunk/line of the response
        vim.schedule(function()
          -- Update your Neovim buffer here
          -- print("Received chunk: " .. data)
          -- insert_at_cursor(data)
          greedy_parse_and_insert(data)
        end)
      end
    end,
    callback = function(res)
      -- local decoded = vim.json.decode(res.body)
      -- The text response is nested in candidates -> content -> parts
      -- local text = decoded.candidates[1].content.parts[1].text

      vim.schedule(function()
        stop_spinner()
        -- insert_at_cursor(text)
      end)
    end,
  })
end

return M
