# git-conflict.nvim

https://user-images.githubusercontent.com/22454918/159362564-a66d8c23-f7dc-4d1d-8e88-c5c73a49047e.mov


A plugin to visualise and resolve conflicts in neovim.
This plugin was inspired by [conflict-marker.vim](https://github.com/rhysd/conflict-marker.vim)

## Status

This plugin is under active development, it should generally work but you're likely to
encounter some bugs during usage. The current commands and mappings are also subject to change.

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
  default_mappings = true, -- disable buffer local mapping created by this plugin
  disable_diagnostics = false, -- This will disable the diagnostics in a buffer whilst it is conflicted
  highlights = { -- They must have background color, otherwise the default color will be used
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

## Autocommands

When a conflict is detected by this plugin a `User` autocommand is fired
called `GitConflictDetected`. When this is resolved another command is
fired called `GitConflictResolved`.

Either of these can be used to run logic whilst dealing with conflicts
e.g.

```lua
vim.api.nvim_create_autocommand('User', {
  pattern = 'GitConflictDetected'
  callback = function()
    vim.notify('Conflict detected in '..vim.fn.expand('<afile>'))
    vim.keymap.set('n', 'cww', function()
      engage.conflict_buster()
    end)
  end
})

```

## Mappings

This plugin offers default buffer local mappings inside of conflicted files. This is primarily because applying these buffers only to relevant buffers
is not possible through global mappings. A user can however disable these by setting `default_mappings = false` anyway and create global mappings as shown below.
The default mappings are:

- <kbd>c</kbd><kbd>t</kbd> - choose theirs
- <kbd>c</kbd><kbd>b</kbd> - choose both
- <kbd>c</kbd><kbd>0</kbd> - choose none
- <kbd>]</kbd><kbd>x</kbd> - move to previous conflict
- <kbd>[</kbd><kbd>x</kbd> - move to next conflict

If you would rather not use these then disable default mappings an you can then map these yourself.

```lua
vim.keymap.set('n', 'co', '<Plug>(git-conflict-ours)')
vim.keymap.set('n', 'cb', '<Plug>(git-conflict-both)')
vim.keymap.set('n', 'c0', '<Plug>(git-conflict-none)')
vim.keymap.set('n', 'ct', '<Plug>(git-conflict-theirs)')
vim.keymap.set('n', '[x', '<Plug>(git-conflict-next-conflict)')
vim.keymap.set('n', ']x', '<Plug>(git-conflict-prev-conflict)')
```

## Issues

**Please read this** - This plugin is not intended to do anything other than provide fancy visuals and some mappings to handle conflict resolution
It will not be expanded to become a full git management plugin, there are a zillion plugins that do that already, this won't be one of those.

### Feature requests

Open source should be collaborative, if you have an idea for a feature you'd like to see added. Submit a PR rather than a feature request.
