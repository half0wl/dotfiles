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
