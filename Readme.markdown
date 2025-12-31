WIP Lua (Hammerspoon) alternative of EWOW https://github.com/zk-phi/ewow for Mac.

Sample `init.lua`:

``` lua
local EWOM = hs.loadSpoon("EWOM")

EWOM:addHook(
  EWOM.afterFocusChangeHook,
  function (app)
    if app == "Emacs" or app == "iTerm2" then
      EWOM:disableKeyBindings()
    else
      EWOM:enableKeyBindings()
    end
  end
)

EWOM:defineKey(EWOM.globalMap, {}, 'a', EWOM.selfInsertCommand)

EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '0', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '1', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '2', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '3', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '4', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '5', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '6', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '7', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '8', EWOM.digitArgument)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, '9', EWOM.digitArgument)

EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, 'x', EWOM.cx)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, 'space', EWOM.setMarkCommand)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, 'g', EWOM.keyboardQuit)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, 'f', EWOM.forwardChar, true)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, 'b', EWOM.backwardChar, true)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, 'n', EWOM.nextLine, true)
EWOM:defineKey(EWOM.globalMap, { 'ctrl' }, 'p', EWOM.previousLine, true)
EWOM:defineKey(EWOM.globalMap, { 'command', 'ctrl' }, 'f', EWOM.forwardWord, true)
EWOM:defineKey(EWOM.globalMap, { 'command', 'ctrl' }, 'b', EWOM.backwardWord, true)

EWOM:defineKey(EWOM.cxMap, { 'ctrl' }, '9', EWOM.kmacroStart)
EWOM:defineKey(EWOM.cxMap, { 'ctrl' }, '0', EWOM.kmacroEnd)
EWOM:defineKey(EWOM.cxMap, { 'ctrl' }, 'm', EWOM.kmacroCall)
EWOM:defineKey(EWOM.cxMap, { 'ctrl' }, 's', EWOM.saveBuffer)
```
