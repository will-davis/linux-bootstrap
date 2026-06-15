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
    'hrsh7th/nvim-cmp',
    event = 'CmdlineEnter',
    dependencies = {
      'hrsh7th/cmp-cmdline',
    },
    config = function()
      local cmp = require('cmp')
      cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = 'cmdline' },
        }),
      })
    end,
  },
})
vim.cmd('colorscheme wildcharm')
