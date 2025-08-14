return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = false,
      },
      inlay_hints = {
        enabled = false,
      },
      codelens = {
        enabled = true,
      },
      servers = {
        vtsls = {
          enabled = false,
        },
        eslint = {
          enabled = false,
        },
        glint = {
          enabled = false,
        },
        biome = {
          enabled = true,
        },
        tailwindcss = {
          enabled = true,
        },
        tsserver = {
          enabled = true,
        },
      },
    },
  },
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "typescript-language-server" })
      return opts
    end,
  },
}
