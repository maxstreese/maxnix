-- My Neovim configuration, loaded by the generated init.lua
-- (../neovim.nix). Plain Lua against Neovim's own API: everything here is
-- in `:help`, and the plugins come from nixpkgs, so there is no plugin
-- manager and nothing is downloaded at run time.

-- Space as leader, and the picker keys below, are LazyVim's, which this
-- replaced: the fingers already know them.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.o.number = true
-- Searches ignore case until the pattern contains a capital.
vim.o.ignorecase = true
vim.o.smartcase = true
-- Undo history survives closing the file.
vim.o.undofile = true
-- Yank and paste go through the system clipboard.
vim.o.clipboard = "unnamedplus"

-- ── Highlighting ────────────────────────────────────────────────────────
-- Tree-sitter, for every file type that has a parser; the parsers and
-- queries are installed by ../neovim.nix. pcall, because a file type
-- without one makes start() raise, and those keep Neovim's regex syntax.
vim.api.nvim_create_autocmd("FileType", {
  callback = function(ev)
    pcall(vim.treesitter.start, ev.buf)
  end,
})

-- ── Finding things ──────────────────────────────────────────────────────
-- fzf-lua drives the fzf binary: files through fd, grep through ripgrep,
-- both honouring .gitignore.
local fzf = require("fzf-lua")
fzf.setup({})
vim.keymap.set("n", "<leader><space>", fzf.files, { desc = "Find files" })
vim.keymap.set("n", "<leader>/", fzf.live_grep, { desc = "Grep the project" })
vim.keymap.set("n", "<leader>,", fzf.buffers, { desc = "Open buffers" })
vim.keymap.set("n", "<leader>sr", fzf.resume, { desc = "Resume the last picker" })

-- ── Language servers ────────────────────────────────────────────────────
-- nvim-lspconfig only supplies each server's definition (command, file
-- types, root markers); starting and attaching is Neovim's own vim.lsp.
-- The servers themselves are on nvim's PATH from ../neovim.nix.
--
-- nixd formats by running a formatter; nixfmt is the one this repo's
-- treefmt uses, so a save here and `nix fmt` agree.
vim.lsp.config("nixd", {
  settings = { nixd = { formatting = { command = { "nixfmt" } } } },
})
-- Metals is the only language server Scala has. It formats with scalafmt,
-- and only in a project that carries a .scalafmt.conf.
vim.lsp.enable({ "nixd", "metals" })

-- Neovim shows diagnostics only as signs and underlines by default; this
-- writes the message at the end of the line as well.
vim.diagnostic.config({ virtual_text = true })

-- Completion from the language server, offered while typing. noselect, so
-- Enter stays a newline until an entry is picked with Ctrl-N/Ctrl-P.
vim.o.completeopt = "menuone,noselect,popup"

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
    -- Neovim's defaults cover the rest (K hover, grn rename, gra code
    -- action, grr references); go-to-definition is only on Ctrl-], so gd
    -- is added for it.
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = ev.buf, desc = "Go to definition" })
  end,
})

-- Format on save, through whichever attached server can format. Synchronous
-- on purpose: the write waits for the formatted text, up to three seconds,
-- after which the file is written as it is.
vim.api.nvim_create_autocmd("BufWritePre", {
  callback = function(ev)
    if #vim.lsp.get_clients({ bufnr = ev.buf, method = "textDocument/formatting" }) > 0 then
      vim.lsp.buf.format({ bufnr = ev.buf, timeout_ms = 3000 })
    end
  end,
})
