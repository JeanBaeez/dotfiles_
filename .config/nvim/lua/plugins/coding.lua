return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "bash", "c", "css", "dockerfile", "go", "gomod", "gosum", "gowork",
        "hcl", "html", "javascript", "json", "lua", "markdown", "markdown_inline",
        "python", "query", "regex", "rust", "scss",
        "sql", "terraform", "toml", "tsx", "typescript", "vim", "vimdoc", "yaml",
      },
    },
  },
  { "lewis6991/gitsigns.nvim", opts = {} },
}
