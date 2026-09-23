-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Options
vim.g.mapleader = ' '
vim.opt.clipboard = 'unnamedplus'
vim.opt.number = true
vim.opt.autoread = true

-- 'timeoutlen' is the wait for the NEXT key of a half-typed mapping -- it is
-- not input lag, and it is NOT what governs <Esc> latency (that's
-- 'ttimeoutlen', for terminal escape codes, already 50ms here).
--
-- The stock 1000ms is only load-bearing on a bare nvim. With which-key
-- installed, its trigger mapping fires on the prefix key and which-key takes
-- input over in its own getcharstr() loop, so a pending <leader>… sequence is
-- held open no matter how long you pause. Measured on this config by driving a
-- real pty: every value from 100ms to 1000ms behaved identically for both
-- <leader> sequences and gcc. Nothing here depends on the timeout, so go fast.
vim.opt.timeoutlen = 150

-- Unused remote-plugin providers. These only power :python3 / :ruby / :perl /
-- node *remote plugins* (nothing here uses them). Disabling skips the
-- interpreter probe at startup and stops :checkhealth reporting missing host
-- packages. LSP (pyright, bashls, ...) is a separate mechanism -- unaffected.
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- glsl_analyzer advertises filetypes nvim has never heard of (vert/frag/geom/
-- comp/tesc/tese), so shader files opened with *no* filetype at all: no LSP,
-- no highlighting, and after/syntax/glsl.vim never ran on them. Map the
-- extensions onto the real 'glsl' filetype instead.
vim.filetype.add({
  extension = {
    glsl = 'glsl', vert = 'glsl', frag = 'glsl',
    geom = 'glsl', comp = 'glsl', tesc = 'glsl', tese = 'glsl',
  },
})

-- OSC 52 clipboard for SSH sessions.
-- On a remote box there's no display server to reach, so the system clipboard
-- is unreachable the usual way ("clipboard: No provider"). OSC 52 is a terminal
-- escape sequence: nvim hands yanked text to the terminal emulator (kitty)
-- in-band over the existing tty, and kitty writes it to the desktop clipboard.
-- No X-forwarding, no clipboard daemon. Guarded so local machines keep their
-- native wl-clipboard provider (which, unlike OSC 52, also reads reliably).
if vim.env.SSH_TTY and vim.fn.has('nvim-0.10') == 1 then
  local osc52 = require('vim.ui.clipboard.osc52')
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
    paste = { ['+'] = osc52.paste('+'), ['*'] = osc52.paste('*') },
  }
end
vim.opt.hlsearch = false

-- Auto-reload files when changed on disk (events fallback)
local autoreload_group = vim.api.nvim_create_augroup('AutoReload', { clear = true })
-- CursorHoldI deliberately omitted: :checktime in insert mode can fire the
-- "file changed on disk" prompt mid-keystroke and eat what you were typing.
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
  group = autoreload_group,
  pattern = '*',
  callback = function()
    if vim.fn.mode() ~= 'c' then
      vim.cmd('checktime')
    end
  end,
})

-- Plugins
require('lazy').setup({
  rocks = { enabled = false },
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    config = function()
      require('which-key').setup({
        plugins = {
          marks = true,
          registers = true,
          spelling = { enabled = true, suggestions = 20 },
          presets = {
            operators = true,
            motions = true,
            text_objects = true,
            windows = true,
            nav = true,
            z = true,
            g = true,
          },
        },
        win = { border = 'rounded' },
      })
    end,
  },
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },  -- the real fzf algo
    },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
	defaults = {
	  file_ignore_patterns = { '%.git/' },   -- never the .git object soup
	},
	pickers = {
	  find_files = { hidden = true },         -- fd --hidden  → shows .config etc.
	  -- find_files = { hidden = true, no_ignore = true },  -- add to also show gitignored
	  live_grep  = { additional_args = { '--hidden' } },    -- grep into dotfiles too
	},
      })
      pcall(telescope.load_extension, 'fzf')      -- no-op if the build isn't ready yet
    end,
    keys = {
      { '<leader>ff', '<cmd>Telescope find_files<cr>', desc = 'Find files' },
      { '<leader>fg', '<cmd>Telescope live_grep<cr>', desc = 'Live grep' },
      { '<leader>fb', '<cmd>Telescope buffers<cr>', desc = 'Buffers' },
      { '<leader>fh', '<cmd>Telescope help_tags<cr>', desc = 'Help tags' },
      { '<leader>fc', '<cmd>Telescope colorscheme enable_preview=true<cr>', desc = 'Colorschemes' },
      { '<leader>fa', '<cmd>Telescope find_files hidden=true no_ignore=true<cr>', desc = 'Find files (all + ignored)' },
    },
  },
  {
    'williamboman/mason.nvim',
    config = function() require('mason').setup() end,
  },
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim' },
    config = function()
      require('mason-lspconfig').setup({
        ensure_installed = { 'pyright', 'bashls', 'fish_lsp', 'lua_ls' },
      })
    end,
  },
  {
    'neovim/nvim-lspconfig',
    dependencies = { 'williamboman/mason-lspconfig.nvim' },
    config = function()
      vim.lsp.enable({ 'pyright', 'glsl_analyzer', 'fish_lsp', 'bashls', 'lua_ls' })

      -- bashls also handles zsh files since no dedicated Zsh LSP exists
      -- ('enabled' is not a vim.lsp.Config field -- enabling is what
      -- vim.lsp.enable() above does. It was a no-op; bashls only ever came up
      -- because mason-lspconfig auto-enables installed servers.)
      vim.lsp.config.bashls = {
        filetypes = { 'bash', 'sh', 'zsh' },
        settings = {
          bashIde = {
            globPattern = '*@(.sh|.inc|.bash|.command|.zsh)',
          },
        },
      }

      -- lua_ls (lua-language-server). Out of the box it knows nothing about
      -- Neovim, so editing this very file it would flag `vim` as an undefined
      -- global and offer no completion for the API. This is the recipe from
      -- nvim-lspconfig's lua_ls docs: declare the LuaJIT runtime, teach it how
      -- nvim resolves `require` (lua/?.lua), and hand it $VIMRUNTIME as a
      -- library so vim.* and every plugin on the rtp resolve.
      --
      -- The on_init guard bails out for projects that ship their own
      -- .luarc.json -- those declare their own runtime (a Love2D or Hammerspoon
      -- project isn't Neovim) and should win over this.
      vim.lsp.config.lua_ls = {
        on_init = function(client)
          if client.workspace_folders then
            local path = client.workspace_folders[1].name
            if path ~= vim.fn.stdpath('config')
              and (vim.uv.fs_stat(path .. '/.luarc.json')
                or vim.uv.fs_stat(path .. '/.luarc.jsonc'))
            then
              return
            end
          end
          -- The type() guard is not paranoia: nvim types settings.Lua as a
          -- broad union (string|number|table|...), so lua_ls can't prove it's a
          -- table and flags tbl_deep_extend. Narrowing it here silences that
          -- honestly, rather than with a ---@diagnostic disable comment.
          local lua = client.config.settings.Lua
          client.config.settings.Lua = vim.tbl_deep_extend('force', type(lua) == 'table' and lua or {}, {
            runtime = {
              version = 'LuaJIT',
              path = { 'lua/?.lua', 'lua/?/init.lua' },
            },
            workspace = {
              checkThirdParty = false,
              library = { vim.env.VIMRUNTIME },
            },
          })
        end,
        settings = { Lua = {} },
      }

      -- Nvim 0.11+ ships its own LSP maps: grn rename, gra code action,
      -- grr references, gri implementation, grt type-def, grx codelens,
      -- gO document symbols, <C-s> signature help (:h grr).
      --
      -- A global `gr` -> references map made `gr` BOTH a complete mapping and
      -- the prefix of all seven, so nvim had to sit out 'timeoutlen' (1000ms)
      -- after every `gr` before deciding which you meant. That one-second
      -- dead pause is the "hotkeys feel off" symptom. Dropped: use grr.
      --
      -- K is left alone on purpose too. Nvim installs a *buffer-local* K on
      -- LspAttach, but only if K is still unmapped (runtime/lua/vim/lsp.lua
      -- guards on maparg('K','n')). That one falls back to 'keywordprg'/:help
      -- in buffers with no client and deletes itself on detach. A global
      -- K -> vim.lsp.buf.hover suppressed all of that and left K inert
      -- wherever no server was attached.
      --
      -- The rest are buffer-local via LspAttach so they only exist where a
      -- server is actually running -- `gd` in a plain text buffer goes back to
      -- Vim's builtin "go to local declaration" instead of silently no-oping.
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('UserLspKeymaps', { clear = true }),
        callback = function(ev)
          local function map(lhs, fn, desc)
            vim.keymap.set('n', lhs, fn, { buffer = ev.buf, desc = desc })
          end
          map('gd', vim.lsp.buf.definition, 'LSP definition')
          map('<leader>rn', vim.lsp.buf.rename, 'LSP rename (same as grn)')
          map('<leader>ca', vim.lsp.buf.code_action, 'LSP code action (same as gra)')
        end,
      })

      -- Diagnostics render with or without a client, so this stays global.
      vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show error' })
    end,

  },
  {
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-cmdline',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
    },
    config = function()
      local cmp = require('cmp')
      cmp.setup({
        snippet = {
          expand = function(args)
            vim.snippet.expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item() else fallback() end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item() else fallback() end
          end, { 'i', 's' }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'buffer' },
          { name = 'path' },
        }),
      })
      cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = 'cmdline' },
        }),
      })
    end,
  },
  {
    'b0o/incline.nvim',
    event = 'VeryLazy',
    config = function()
      require('incline').setup()
    end,
  },
 {
    'yetone/avante.nvim',
    event = 'VeryLazy',
    version = false,
    build = 'make',
    opts = {
      provider = 'llamacpp',
      providers = {
        llamacpp = {
	  __inherited_from = 'openai',
          api_key_name = '',
          endpoint = 'http://127.0.0.1:8080/v1',
          model = 'Nvidia-Qwen3.6-27B-NVFP4.gguf',
        },
      },
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-tree/nvim-web-devicons',
      {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = { file_types = { 'markdown', 'Avante' } },
        ft = { 'markdown', 'Avante' },
      },
    },
  },
  {
    'akinsho/bufferline.nvim',
    version = "*",
    dependencies = 'nvim-tree/nvim-web-devicons',
  },
  {
    'diegok/live-autoread.nvim',
    event = 'BufReadPost',
    opts = {},
  },
})
vim.cmd('colorscheme wildcharm')
-- Override bufferline active-tab highlights: give the selected tab/buffer a dark
-- gray background instead of the colourscheme's pure black.
local c = { bg = '#303030' }  -- adjust to taste; anything in #222–#444 range works
for group, guifg in pairs({
  BufferLineTabSelected            = nil,
  BufferLineBufferSelected         = nil,
  BufferLineCloseButtonSelected    = nil,
  BufferLineSeparatorSelected      = c.bg,   -- blend the separator into the bg
}) do
  vim.api.nvim_set_hl(0, group, { bg = c.bg, fg = guifg })
end

vim.opt.shiftwidth = 4

-- foldmethod=syntax derives folds from the syntax file. 'foldlevel' controls
-- how deep folds start OPEN -- at 0 every file opened fully collapsed, which is
-- why j/k/G looked like they were leaping over whole blocks.
-- 'foldlevelstart' is the same idea applied per newly-opened buffer, so files
-- land flat while zc / zM / za still fold on demand (:h foldlevelstart).
-- Want everything collapsed on open again? Change 99 back to 0.
vim.opt.foldmethod = 'syntax'
vim.opt.foldlevelstart = 99

-- The TABs
vim.opt.termguicolors = true
require("bufferline").setup({
  options = {
    separator_style = "slant",
    hover = { enabled = true },
  },
   highlights = {
      buffer_selected   = { bg = '#303030' },
      numbers_selected  = { bg = '#303030' },
      close_button_selected = { bg = '#303030' },
      separator_selected       = { bg = '#303030' },
      indicator_selected       = { bg = '#303030' },
      modified_selected        = { bg = '#303030' },
      duplicate_selected       = { bg = '#303030' },
    },
})

-- WHY gt/gT "stopped working": nothing remapped them. gt/gT are Vim's TAB PAGE
-- commands (:tabnext / :tabprevious, :h gt). bufferline draws **buffers** in
-- the tabline, not tab pages -- so with the usual single tab page open, gt was
-- faithfully cycling a list of one and looked dead. It broke the day
-- bufferline was added, not on a system update.
--
-- Route them by what's actually there: real tab pages when more than one
-- exists, bufferline's buffers otherwise. Counts behave like Vim's: 3gt jumps
-- to the third entry.
local function cycle(dir)
  return function()
    local count = vim.v.count
    if vim.fn.tabpagenr('$') > 1 then
      if count > 0 then
        vim.cmd(count .. 'tabnext')
      else
        vim.cmd(dir > 0 and 'tabnext' or 'tabprevious')
      end
    elseif count > 0 then
      vim.cmd('BufferLineGoToBuffer ' .. count)
    else
      vim.cmd(dir > 0 and 'BufferLineCycleNext' or 'BufferLineCyclePrev')
    end
  end
end

vim.keymap.set('n', 'gt', cycle(1), { desc = 'Next tab page / buffer' })
vim.keymap.set('n', 'gT', cycle(-1), { desc = 'Prev tab page / buffer' })

-- ]b / [b exist since nvim 0.11 as plain :bnext / :bprevious, which follow
-- buffer *number* order. Point them at bufferline so they follow the order you
-- can see in the tabline (bufferline lets tabs be reordered).
vim.keymap.set('n', ']b', '<cmd>BufferLineCycleNext<cr>', { desc = 'Next buffer' })
vim.keymap.set('n', '[b', '<cmd>BufferLineCyclePrev<cr>', { desc = 'Prev buffer' })
vim.keymap.set('n', '<leader>bp', '<cmd>BufferLinePick<cr>', { desc = 'Pick buffer' })
vim.keymap.set('n', '<leader>bd', '<cmd>bdelete<cr>', { desc = 'Close buffer' })

-- RayGLow: push GLSL edits straight to the running renderer on :w (bypasses
-- mutagen's ~5-20s sync). Controls under <leader>m (n/p/r/s/<space>/u, and
-- x→scale). host honours $RAYGLOW_HOST, else the rpi5 IP from LOCAL-SETUP
-- (update if DHCP moves it).
require('rayglow').setup({
  ctl  = vim.fn.expand('~/Projects/rayglow/tools/rayglow_ctl.py'),
  host = vim.env.RAYGLOW_HOST or '192.168.2.113',
})
