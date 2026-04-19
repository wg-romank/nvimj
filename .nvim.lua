-- -- Open REPL (e.g., <leader>rs for "Repl Start")
vim.keymap.set('n', '<leader>rs', function()
    require('nvimj').open_repl() 
end, { desc = "Start REPL in horizontal split" })

vim.keymap.set('n', '<leader>rl', function()
    require('nvimj').send_to_repl()
end, { desc = "Send current line to REPL", silent = false })

vim.keymap.set({'n', 'v'}, 'r', function()
    return require('nvimj').send_motion()
end, { desc = "Send selection to REPL", silent = false, expr = true })

vim.keymap.set({'n', 'v'}, '<leader>ge', function()
    return require('nvimj').ask_gemini()
end, { desc = "Send selection to Gemini", silent = false })

