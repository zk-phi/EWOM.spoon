WIP Lua (Hammerspoon) alternative of EWOW https://github.com/zk-phi/ewow for Mac.

Sample `init.lua`:

``` lua
local EWOM = hs.loadSpoon("EWOM")

EWOM.setApplicationFilter(
  function (app)
    if app == 'Emacs' or app == 'iTerm2' then
      EWOM.disableKeyBindings()
    else
      EWOM.enableKeyBindings()
    end
  end
)

EWOM.setInputMethodFilter(
  function (method)
    if method == nil then
      EWOM.enableKeyBindings()
    else
      EWOM.disableKeyBindings()
    end
  end
)

EWOM.defineKey(EWOM.globalMap, {}, 'a', EWOM.cmd.selfInsertCommand)

EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '0', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '1', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '2', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '3', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '4', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '5', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '6', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '7', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '8', EWOM.cmd.digitArgument)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, '9', EWOM.cmd.digitArgument)

EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, 'x', EWOM.cmd.cx)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, 'space', EWOM.cmd.setMarkCommand)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, 'g', EWOM.cmd.keyboardQuit)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, 'f', EWOM.cmd.forwardChar, true)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, 'b', EWOM.cmd.backwardChar, true)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, 'n', EWOM.cmd.nextLine, true)
EWOM.defineKey(EWOM.globalMap, { 'ctrl' }, 'p', EWOM.cmd.previousLine, true)
EWOM.defineKey(EWOM.globalMap, { 'command', 'ctrl' }, 'f', EWOM.cmd.forwardWord, true)
EWOM.defineKey(EWOM.globalMap, { 'command', 'ctrl' }, 'b', EWOM.cmd.backwardWord, true)

EWOM.defineKey(EWOM.cxMap, { 'ctrl' }, '9', EWOM.cmd.kmacroStart)
EWOM.defineKey(EWOM.cxMap, { 'ctrl' }, '0', EWOM.cmd.kmacroEnd)
EWOM.defineKey(EWOM.cxMap, { 'ctrl' }, 'm', EWOM.cmd.kmacroCall)
EWOM.defineKey(EWOM.cxMap, { 'ctrl' }, 's', EWOM.cmd.saveBuffer)
```
