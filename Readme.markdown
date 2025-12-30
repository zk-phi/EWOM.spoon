WIP Lua (Hammerspoon) alternative of EWOW https://github.com/zk-phi/ewow for Mac.

Sample `init.lua`:

``` lua
local EWOM = hs.loadSpoon("EWOM")

-- Disable when Emacs or iTerm2 is focused
EWOM:setFilter(
  function (app)
    return app == "Emacs" or app == "iTerm2"
  end
)

EWOM:bindKey(EWOM.globalMap, { 'ctrl' }, 'space', EWOM.setMarkCommand, true)
EWOM:bindKey(EWOM.globalMap, { 'ctrl' }, 'g', EWOM.keyboardQuit, true)
EWOM:bindKey(EWOM.globalMap, { 'ctrl' }, 'f', EWOM.forwardChar, true)
EWOM:bindKey(EWOM.globalMap, { 'ctrl' }, 'b', EWOM.backwardChar, true)
EWOM:bindKey(EWOM.globalMap, { 'ctrl' }, 'n', EWOM.nextLine, true)
EWOM:bindKey(EWOM.globalMap, { 'ctrl' }, 'p', EWOM.previousLine, true)
EWOM:bindKey(EWOM.globalMap, { 'command', 'ctrl' }, 'f', EWOM.forwardWord, true)
EWOM:bindKey(EWOM.globalMap, { 'command', 'ctrl' }, 'b', EWOM.backwardWord, true)
```
