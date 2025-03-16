# git-conflict.nvim

https://user-images.githubusercontent.com/22454918/159362564-a66d8c23-f7dc-4d1d-8e88-c5c73a49047e.mov

A plugin to visualise and resolve conflicts in neovim.
This plugin was inspired by [conflict-marker.vim](https://github.com/rhysd/conflict-marker.vim)

## Status

This plugin is under active development, it should generally work, but you're likely to
encounter some bugs during usage.

## Requirements

- `git`
- `nvim 0.10+`

## Installation

```lua
-- packer.nvim
use {'akinsho/git-conflict.nvim', tag = "*", config = function()
  require('git-conflict').setup()
end}

-- lazy.nvim
{'akinsho/git-conflict.nvim', version = "*", config = true}
```

I recommend using the {tag|version} field of your package manager, so your version of this plugin is only updated when a new tag is pushed as `main` itself might be **unstable**.

## Configuration

```lua
{
  default_mappings = true, -- disable buffer local mapping created by this plugin
  default_commands = true, -- disable commands created by this plugin
  disable_diagnostics = false, -- This will disable the diagnostics in a buffer whilst it is conflicted
  list_opener = 'copen', -- command or function to open the conflicts list
  highlights = { -- They must have background color, otherwise the default color will be used
    incoming = 'DiffAdd',
    current = 'DiffText',
  }
}
```

## Commands

- `GitConflictChooseOurs` — Select the current changes.
- `GitConflictChooseTheirs` — Select the incoming changes.
- `GitConflictChooseBoth` — Select both changes.
- `GitConflictChooseNone` — Select none of the changes.
- `GitConflictNextConflict` — Move to the next conflict.
- `GitConflictPrevConflict` — Move to the previous conflict.
- `GitConflictListQf` — Get all conflict to quickfix

### Listing conflicts

You can list conflicts in the quick fix list using the `GitConflictListQf` command

<img width="475" alt="Screen Shot 2022-03-27 at 12 03 43" src="https://user-images.githubusercontent.com/22454918/160278511-705a0361-a387-4fc1-8b20-bd799bf85b82.png">

quickfix displayed using [nvim-pqf](https://github.com/yorickpeterse/nvim-pqf)

## Autocommands

When a conflict is detected by this plugin a `User` autocommand is fired
called `GitConflictDetected`. When this is resolved another command is
fired called `GitConflictResolved`.

Either of these can be used to run logic whilst dealing with conflicts
e.g.

```lua
vim.api.nvim_create_autocmd('User', {
  pattern = 'GitConflictDetected',
  callback = function()
    vim.notify('Conflict detected in '..vim.fn.expand('<afile>'))
    vim.keymap.set('n', 'cww', function()
      engage.conflict_buster()
      create_buffer_local_mappings()
    end)
  end
})

```

## Mappings

This plugin offers default buffer local mappings inside conflicted files. This is primarily because applying these mappings only to relevant buffers
is impossible through global mappings. A user can however disable these by setting `default_mappings = false` anyway and create global mappings as shown below.
The default mappings are:

- <kbd>c</kbd><kbd>o</kbd> — choose ours
- <kbd>c</kbd><kbd>t</kbd> — choose theirs
- <kbd>c</kbd><kbd>b</kbd> — choose both
- <kbd>c</kbd><kbd>0</kbd> — choose none
- <kbd>]</kbd><kbd>x</kbd> — move to previous conflict
- <kbd>[</kbd><kbd>x</kbd> — move to next conflict

If you would rather not use these then you can specify your own mappings.

```lua
require'git-conflict'.setup {
  default_mappings = {
    ours = 'o',
    theirs = 't',
    none = '0',
    both = 'b',
    next = 'n',
    prev = 'p',
  },
}
```

or alternatively, set `default_mappings = false` and apply the mappings yourself

<details><summary>example manual mappings</summary>

```lua
vim.keymap.set('n', 'co', '<Plug>(git-conflict-ours)')
vim.keymap.set('n', 'ct', '<Plug>(git-conflict-theirs)')
vim.keymap.set('n', 'cb', '<Plug>(git-conflict-both)')
vim.keymap.set('n', 'c0', '<Plug>(git-conflict-none)')
vim.keymap.set('n', '[x', '<Plug>(git-conflict-prev-conflict)')
vim.keymap.set('n', ']x', '<Plug>(git-conflict-next-conflict)')
```

</details>

## API

This plugin exposes an API to extract some of the data it collects for other
purposes.

<details><summary>conflict_count({bufnr})</summary>

```vimdoc
    Returns the amount of conflicts in a given buffer.
    

    Parameters:
	{bufnr} (number) Specify the buffer for which you want to know the
	                 amount of conflicts (default: current buffer).

    Return:
	number: The amount of conflicts.
```
</details>

## Issues

**Please read this** — This plugin is not intended to do anything other than provide fancy visuals, and some mappings to handle conflict resolution
It will not be expanded to become a full git management plugin, there are a zillion plugins that do that already, this won't be one of those.

### Feature requests

Open source should be collaborative, if you have an idea for a feature you'd like to see added. Submit a PR rather than a feature request.
