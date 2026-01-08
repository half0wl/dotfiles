-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.mapleader = ","
vim.g.root_spec = { "cwd" }
vim.g.maplocalleader = "\\"
vim.opt.winbar = "%=%m %f"
vim.opt.colorcolumn = "79"
vim.g.snacks_animate = false
vim.opt.conceallevel = 0

-- Disable LSP file watching to prevent EMFILE errors
vim.lsp.set_log_level("off")
local ok, wf = pcall(require, "vim.lsp._watchfiles")
if ok then
  wf._watchfunc = function()
    return function() end
  end
end
