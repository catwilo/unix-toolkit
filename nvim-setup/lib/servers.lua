-- Single source of truth for LSP servers.
-- To add a language: add one entry here. cmd = binary in PATH.
-- The nvim config and setup.sh both read this table.
return {
  ts_ls = {
    cmd = "typescript-language-server",
    filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  },
  eslint = {
    cmd = "vscode-eslint-language-server",
    filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  },
  cssls = {
    cmd = "vscode-css-language-server",
    filetypes = { "css", "scss", "less" },
  },
  html = {
    cmd = "vscode-html-language-server",
    filetypes = { "html" },
  },
  jsonls = {
    cmd = "vscode-json-language-server",
    filetypes = { "json", "jsonc" },
  },
  lua_ls = {
    cmd = "lua-language-server",
    filetypes = { "lua" },
    settings = { Lua = { diagnostics = { globals = { "vim" } } } },
  },
}
