return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "bash", "c", "css", "dockerfile", "go", "html",
        "javascript", "json", "lua", "markdown", "markdown_inline",
        "python", "query", "regex", "rust", "scss",
        "sql", "toml", "tsx", "typescript", "vim", "vimdoc", "yaml",
      },
    },
  },
  { "lewis6991/gitsigns.nvim", opts = {} },
}
