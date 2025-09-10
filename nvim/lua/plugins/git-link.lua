return {
  "juacker/git-link.nvim",
  keys = {
    {
      "<leader>gu",
      function()
        require("git-link.main").copy_line_url()
      end,
      desc = "Copy code link to clipboard",
      mode = { "n", "x" },
    },
    {
      "<leader>go",
      function()
        require("git-link.main").open_line_url()
      end,
      desc = "Open code link in browser",
      mode = { "n", "x" },
    },
  },
}
