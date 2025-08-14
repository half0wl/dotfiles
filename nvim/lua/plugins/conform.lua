-- confirm.lua
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        ["javascript"] = { "biome", "prettier" },
        ["javascriptreact"] = { "biome", "prettier" },
        ["typescript"] = { "biome", "prettier" },
        ["typescriptreact"] = { "biome", "prettier" },
        ["python"] = { "black", "isort" },
        ["json"] = { "biome", "prettier" },
        ["css"] = { "biome", "prettier" },
      },
      formatters = {
        biome = {
          require_cwd = true,
          command = "biome",
          args = {
            "check",
            "--write",
            "--formatter-enabled=true",
            "--assist-enabled=true",
            "--linter-enabled=false",
            "--stdin-file-path",
            "$FILENAME",
          },
        },
      },
    },
  },
}
