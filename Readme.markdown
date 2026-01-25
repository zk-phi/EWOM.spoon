EWOM -- Emacs-Way of Operating Macintosh

enables Emacs keybinds and features globally on Macintosh.

![Macro example](./screencast.gif)

Lua alternative of EWOW https://github.com/zk-phi/ewow, but for Mac.

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

Sample `init.lua`:

``` lua
local EWOM = hs.loadSpoon("EWOM")

-- Make alert display smaller
hs.alert.defaultStyle.textSize = 16

-- Disable in some apps
EWOM.setApplicationFilter(
  function (app)
    return app == 'Emacs' or app == 'iTerm2'
  end
)

-- Disable when a specific input method is on
EWOM.setInputMethodFilter(
  function (method)
    return not method:find("SKK")
  end
)

-- Enable the default keybinds.
-- (See EWOM.spoon/init.lua for the full list of keybinds)
EWOM.registerDefaultKeymap()

-- You may also remap some keybinds as you want
-- EWOM equivalent of (global-set-key (kbd "C--") 'undo)
EWOM.globalSetKey({ 'ctrl' }, '-', EWOM.cmd.undo)
-- EWOM equivalent of (global-set-key (kbd "C-x a" 'mark-whole-buffer))
EWOM.defineKey(EWOM.cxMap, {}, 'a', EWOM.cmd.markWholeBuffer)
```

# Advantages

This spoon implements hotkey mechanism by its own, to break the limitations of Hammerspoon's `hs.hotkey`.

So that,

- EWOM takes precedence over the OS default keybinds
- EWOM can automagically avoid unexpected behaviors like infinite loops behind the scenes

with some non-trivial features ported:

- Keyboard macros
- Set-mark command
- Digit arguments

# Add-ons

- Keychord https://github.com/zk-phi/EWOMKeychord.spoon

# Extending EWOM
## Adding commands

Commands are just lua functions, so you may simply define functions and bind with `EWOM.globalSetKey`/`EWOM.defineKey`.

``` lua
function killLineBackward ()
  EWOM.sendKey({ 'command', 'shift' }, 'left')
  EWOM.sendKey({ 'command' }, 'x')
  EWOM.runHooks(EWOM.afterChangeHook)
end
EWOM.globalSetKey({ 'ctrl', 'command' }, 'k', killLineBackward)
```

Note that you should use `EWOM.sendKey` helper function to send inputs to the OS, so that `EWOM` can avoid undesired behaviors like infinite loops.

In addition, if your command edits a document, your command should call `EWOM.afterEditHook` after that. The hook will do common cleanups like disabling marks for you.

Command functions will receive two arguments: 1. digit argument (>= 0) and 2. keyboard event that triggered the command, that can be used on your demand.

## Hooks

EWOM has hook mechanism too (just like Emacs) that you may add your functions to extend the behavior of EWOM.

Following hooks are defined and handled by default.

- `EWOM.afterFocusChangeHook`
  - Hook called when the active window is switched
  - argument: new active app name (string)

- `EWOM.afterInputMethodChangeHook`
  - Hook called when the active input method is switched
  - argument: new input method name (string) or nil

- `EWOM.beforeSendHook`
  - Hook called when an input event is going to be sent from `EWOM` to the OS
  - argument: input event to be sent (`hs.eventtap.event`)

- `EWOM.keybindsDisabledHook`, `EWOM.keybindsEnabledHook`
  - Hook called when keybinds are disabled or enabled
    (via filters or functions `EWOM.disableKeyBindings`, `EWOM.enableKeyBindings`)

- `EWOM.preCommandHook`
  - Hook called when `EWOM` captures an input event, before invoking commands
  - argument: captured input event (`hs.eventtap.event`)

- `EWOM.afterChangeHook`
  - Hook called after a command that modify documents is executed

Note that hooks are just lists of functions, so you may create your own easily.

``` lua
mySpecialHook = {}
EWOM.addHook(mySpecialHook, mySpecialFunction)
EWOM.runHooks(mySpecialHook, mySpecialArgument)
```

## Keymaps

Keymaps are just lua tables, so you may create your own easily.

``` lua
-- EWOM equivalent of:
--   (global-set-key (kbd "C-h h") 'my-open-help)
--   (global-set-key (kbd "C-h d") 'my-open-dictionary)
myHelpMap = { default = EWOM.cmd.ignore }
EWOM.globalSetKey({ 'ctrl' }, 'h', function () EWOM.enableOverlayMap(myHelpMap) end)
EWOM.defineKey(myHelpMap, {}, 'h', myOpenHelp)
EWOM.defineKey(myHelpMap, {}, 'd', myOpenDictionary)
```

If `default = EWOM.cmd.ignore` is omitted, raw keyboard events are sent to the OS when no matching keybinds are found (this applies to `EWOM.globalMap` by default).

You may specify `keep = true` in addition, which works like `KEEP-PRED` argument to `set-temporary-map` function in Emacs.

## Other helper functions and variables
### Functions

- `EWOM.sendString(str, evt)`
  - Like `EWOM.sendKey`, but sends string `str` for keydown event `evt`, regardless of keyboard layout.

- `EWOM.usePasteboard(cb)`
  - Wait the pasteboard to be updated, and call `cb` with its content

- `EWOM.sendSyntheticEvent(event, delaySeconds)`
  - Mark event as synthetic and send to the OS.
  - Synthetic events will not trigger another hotkey, so you may use this function to avoid unexpected behaviors like infinite loops. This is the underlying function of `EWOM.sendKey`.

- `EWOM.enableOverlayMap(map)`
  - Enable temporary keymap `map`. This may be useful to implement keybinds like `C-x *`.

- `EWOM.disableKeyBindings()`, `EWOM.enableKeyBindings()`
  - Disable or enable all keybinds temporarily

### Variables

- `EWOM.enabled`
  - If keybinds are enabled or disabled

- `EWOM.lastEvent`
  - Last input event captured.

- `EWOM.lastCommand`
  - Last command function triggered for `EWOM.lastEvent`.
    This value may be `nil` if no keybinds are defined for the last input

- `EWOM.markActive`
  - If mark is active or not

- `EWOM.kmacroRecording`
  - If keybobard macro is recording or not
