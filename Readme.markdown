WIP Lua (Hammerspoon) alternative of EWOW https://github.com/zk-phi/ewow for Mac.

Sample `init.lua`:

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
-- ↓ EWOM equivalent of (global-set-key (kbd "C--") 'undo)
EWOM.globalSetKey({ 'ctrl' }, '-', EWOM.cmd.undo)
```
