Emacs keybinds for Macintosh (including kmacro feature etc)

WIP Lua alternative of EWOW https://github.com/zk-phi/ewow, but for Mac.

# Installation

1. Install Hammerspoon and launch to complete the initial setup

``` terminal
$ brew install hammerspoon
```

2. Clone this repo into `~/.hammerspoon/Spoons/`

``` terminal
$ cd ~/.hammerspoon/Spoons/
$ git clone https://github.com/zk-phi/EWOM.spoon.git
```

3. Load and initialize EWOM in your `~/.hammerspoon/init.lua`

Sample:

``` lua
local EWOM = hs.loadSpoon("EWOM")

-- Disable in some apps
EWOM.setApplicationFilter(
  function (app)
    return app == 'Emacs' or app == 'iTerm2'
  end
)

-- Disable while input method is on
EWOM.setInputMethodFilter(
  function (method)
    return not (method == nil)
  end
)

-- See EWOM.spoon/init.lua for the full list of keybinds
EWOM.registerDefaultKeymap()

-- You may also remap some keybinds as you want
-- (global-set-key (kbd "C--") 'undo)
EWOM.globalSetKey({ 'ctrl' }, '-', EWOM.cmd.undo)
-- (global-set-key (kbd "C-x a" 'mark-whole-buffer))
EWOM.defineKey(EWOM.cxMap, {}, 'a', EWOM.cmd.markWholeBuffer)
```
