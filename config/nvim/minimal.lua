-- Plugin-free config for Raspberry Pi and Neovim older than 0.11.3.
vim.g.mapleader = ' '
vim.opt.number = true
vim.opt.hlsearch = false
vim.opt.autoread = true
vim.opt.shiftwidth = 4
vim.opt.foldlevelstart = 99
vim.opt.clipboard = 'unnamedplus'
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  if vim.fn.has('nvim-0.10') == 1 then
    local osc52 = require('vim.ui.clipboard.osc52')
    vim.g.clipboard = {
      name = 'OSC 52',
      copy = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
      paste = { ['+'] = osc52.paste('+'), ['*'] = osc52.paste('*') },
    }
  else
    -- Old distro Neovim can still COPY over SSH. It cannot query the terminal
    -- clipboard here: p uses the last local yank; paste external text using
    -- kitty's normal terminal paste shortcut.
    local last = { { '' }, 'v' }
    local function copy(lines, regtype)
      last = { lines, regtype }
      local text = table.concat(lines, '\n') .. (regtype == 'V' and '\n' or '')
      local encoded = vim.fn.system('base64', text):gsub('%s', '')
      vim.api.nvim_chan_send(2, '\027]52;c;' .. encoded .. '\007')
    end
    local function paste() return last end
    vim.g.clipboard = {
      name = 'OSC 52 copy (old Neovim)',
      copy = { ['+'] = copy, ['*'] = copy },
      paste = { ['+'] = paste, ['*'] = paste },
      cache_enabled = 0,
    }
  end
end
