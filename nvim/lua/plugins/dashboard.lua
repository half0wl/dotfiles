return {
  "snacks.nvim",
  opts = {
    dashboard = {
      preset = {
        pick = function(cmd, opts)
          return LazyVim.pick(cmd, opts)()
        end,
        header = [[
                                  |\---/|
 https://ray.cat                  | ,_, |
 https://x.com/raychen             \_`_/-..----.
 https://github.com/half0wl    ___/ `   ' ,""+ \
                                (__...'   __\    |`.___.';
                                  (_,...'(_,.`__)/'.....+
 ]],
        -- stylua: ignore
        ---@type snacks.dashboard.Item[]
        keys = {
          { icon = " ", key = "f", desc = "grep files ...", action = ":lua Snacks.dashboard.pick('files')" },
          { icon = " ", key = "g", desc = "grep text  ...", action = ":lua Snacks.dashboard.pick('live_grep')" },
          { icon = " ", key = "c", desc = "open config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          { icon = " ", key = "q", desc = "quit", action = ":qa" },
          -- { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          -- { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          -- { icon = " ", key = "s", desc = "Restore Session", section = "session" },
          -- { icon = " ", key = "x", desc = "Lazy Extras", action = ":LazyExtras" },
          -- { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
        },
      },
      formats = {
        header = {
          align = "left",
        },
      },
      sections = {
        { section = "header" },
        { section = "keys", gap = 1 },
      },
    },
  },
}
