# git-conflict.nvim

<img width="656" alt="Screen Shot 2022-03-13 at 00 17 39" src="https://user-images.githubusercontent.com/22454918/158039595-63c2922c-0e49-4baa-99bd-3d722ca90a4b.png">

A plugin to visualise and resolve conflicts in neovim.

## Status

This plugin is a work in progress, and not yet ready for stable use.

## Installation

```lua
use {'akinsho/git-conflict.nvim', config = function()
  require('git-conflict').setup
end}
```

## Configuration

```lua
{
  disable_diagnostics = false, -- This will disable the diagnostics in a buffer whilst it is conflicted
  highlights = {
    incoming = 'DiffText',
    current = 'DiffAdd',
  }
}
```
