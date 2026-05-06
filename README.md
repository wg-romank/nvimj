# Setup

Set environment variable for eval

```bash
export REPL_COMMAND="~/j9.7/bin/jconsole"
```

Set suggested keymap
```lua
vim.keymap.set({"n", "x", "o"}, "r", require('nvimj').send_motion, { desc = 'Send to REPL', expr = true } )
```
