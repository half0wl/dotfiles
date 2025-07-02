return {
  "snacks.nvim",
  opts = {
    indent = { enabled = true },
    input = { enabled = true },
    notifier = { enabled = true },
    scope = { enabled = true },
    scroll = { enabled = true },
    statuscolumn = { enabled = false }, -- we set this in options.lua
    toggle = { map = LazyVim.safe_keymap_set },
    words = { enabled = true },
    picker = {
      hidden = true,
      ignored = true,
      exclude = { ".direnv", ".turbo", "node_modules", ".next", "dist" },
      grep = {
        finder = "rg",
      },
    },
  },
}
