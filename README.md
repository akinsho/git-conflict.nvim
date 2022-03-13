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

## Commands

- `GitConflictChooseOurs` - Select the current changes
- `GitConflictChooseTheirs` - Select the incoming changes
- `GitConflictChooseBoth` - Select both changes

## Issues

**Please read this** - This plugin is not intended to do anything other than provide fancy visuals and some mappings to handle conflict resolution
It will not be expanded to become a full git management plugin, there are a zillion plugins that do that already, this won't be one of those.

### Feature requests

Open source should be collaborative, if you have an idea for a feature you'd like to see added. Submit a PR rather than a feature request.
