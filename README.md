# git-conflict.nvim

<img width="477" alt="image" src="https://user-images.githubusercontent.com/22454918/158040417-44b18468-3fc1-4ed9-ab38-75dadea0346b.png">

A plugin to visualise and resolve conflicts in neovim.

## Status

This plugin is a work in progress, and not yet ready for stable use.

## Requirements

- `git`
- `nvim 0.7+` - it's easier to build plugins with some of the nightly APIs such as `keymap.set` or `nvim_create_autocmd`

## Installation

```lua
use {'akinsho/git-conflict.nvim', config = function()
  require('git-conflict').setup()
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

- `GitConflictChooseOurs` - Select the current changes.
- `GitConflictChooseTheirs` - Select the incoming changes.
- `GitConflictChooseBoth` - Select both changes.
- `GitConflictChooseNone` - Select both none of the changes.
- `GitConflictNextConflict` - Move to the next conflict.
- `GitConflictPrevConflict` - Move to the previous conflict.

## Issues

**Please read this** - This plugin is not intended to do anything other than provide fancy visuals and some mappings to handle conflict resolution
It will not be expanded to become a full git management plugin, there are a zillion plugins that do that already, this won't be one of those.

### Feature requests

Open source should be collaborative, if you have an idea for a feature you'd like to see added. Submit a PR rather than a feature request.
