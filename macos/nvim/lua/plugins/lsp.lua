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
          -- Override cmd to use local biome first
          cmd = function()
            local local_biome = vim.fn.getcwd() .. "/node_modules/.bin/biome"
            if vim.fn.filereadable(local_biome) == 1 then
              return { local_biome, "lsp-proxy" }
            end
            -- Fallback to bunx
            return { "bunx", "biome", "lsp-proxy" }
          end,
        },
        tailwindcss = {
          enabled = true,
        },
        tsserver = {
          enabled = true,
        },
      },
      setup = {
        -- Custom setup for biome to handle the cmd function
        biome = function(_, opts)
          local lspconfig = require("lspconfig")

          -- Resolve the cmd if it's a function
          if type(opts.cmd) == "function" then
            opts.cmd = opts.cmd()
          end

          lspconfig.biome.setup(opts)
          return true -- Prevent default setup
        end,
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "typescript-language-server" })
      return opts
    end,
  },
}
