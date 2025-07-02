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
          on_attach = function(client)
            client.server_capabilities.documentFormattingProvider = false
          end,
        },
        biome = {},
        tailwindcss = {},
      },
    },
  },
}
