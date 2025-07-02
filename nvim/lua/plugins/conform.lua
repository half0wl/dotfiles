-- confirm.lua
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        ["javascript"] = { "biome" },
        ["javascriptreact"] = { "biome" },
        ["typescript"] = { "biome" },
        ["typescriptreact"] = { "biome" },
        ["json"] = { "biome" },
        ["css"] = { "biome" },
      },
      formatters = {
        biome = {
          require_cwd = true,
          command = "biome",
          args = {
            "check",
            "--formatter-enabled=true",
            "--linter-enabled=false",
            "--organize-imports-enabled=true",
            "--write",
            "--stdin-file-path",
            "$FILENAME",
          },
        },
      },
    },
  },
}
