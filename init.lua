-- TODO: State indicators (see canvas doc)
-- TODO: Kill-ring history (C-2 C-y)

local obj = {};

--
-- Metadata
--

obj.name = 'EWOM Spoon'
obj.version = '0.1'
obj.author = 'zk-phi'
obj.license = 'MIT'
obj.homepage = 'https://github.com/zk-phi/dotfiles'

--
-- Hooks
--

function obj.addHook (hook, fn)
  hook[#hook + 1] = fn
end

function obj.runHooks (hook, arg)
  for i = 1, #hook do
    hook[i](arg)
  end
end

--
-- afterFocusChangeHook
--

obj.afterFocusChangeHook = {}

-- We need to bind allocated watcher globally unless otherwise it will be garbage-collected.
-- https://github.com/Hammerspoon/hammerspoon/issues/681#issuecomment-178420569
obj._watchers = {}
obj._watchers[#obj._watchers + 1] = hs.application.watcher.new(
  function (app, event)
    if event == hs.application.watcher.activated then
      obj.runHooks(obj.afterFocusChangeHook, app)
    end
  end
):start()

--
-- afterInputMethodChangeHook
--

obj.afterInputMethodChangeHook = {}

obj._watchers[#obj._watchers + 1] = hs.keycodes.inputSourceChanged(
  function ()
    obj.runHooks(obj.afterInputMethodChangeHook, hs.keycodes.currentMethod())
  end
)

--
-- sendKey
--

obj.beforeSendHook = {}

-- hs.hotkey can be fired with synthetic keyboard event too,
-- which easily leads to infinite recursion. so implement we hotkeys by our own.
-- https://github.com/Hammerspoon/hammerspoon/issues/1230

local SYNTHETIC_EVENT_SIGNATURE = 55555

local function sendSyntheticEvent (evt, delay)
  evt:setProperty(
    hs.eventtap.event.properties.eventSourceUserData,
    SYNTHETIC_EVENT_SIGNATURE
  )
  obj.runHooks(obj.beforeSendHook, evt)
  if delay and delay > 0 then
    hs.timer.delayed.new(delay, function () evt:post() end):start()
  else
    evt:post()
  end
end

local function eventIsSynthetic (evt)
  local val = evt:getProperty(hs.eventtap.event.properties.eventSourceUserData)
  return val == SYNTHETIC_EVENT_SIGNATURE
end

-- Like fs.eventtap.keyStroke but faster
-- https://github.com/Hammerspoon/hammerspoon/issues/1082
function obj.sendKey (mod, char)
  sendSyntheticEvent(hs.eventtap.event.newKeyEvent(mod, char, true))
  sendSyntheticEvent(hs.eventtap.event.newKeyEvent(mod, char, false))
end

--
-- Keymap lookup
--

obj.globalMap = {}
obj.overlayMap = nil

local MODFLAGS =
  hs.eventtap.event.rawFlagMasks.alternate |
  hs.eventtap.event.rawFlagMasks.command |
  hs.eventtap.event.rawFlagMasks.control |
  hs.eventtap.event.rawFlagMasks.shift |
  hs.eventtap.event.rawFlagMasks.deviceRightAlternate |
  hs.eventtap.event.rawFlagMasks.deviceRightCommand |
  hs.eventtap.event.rawFlagMasks.deviceRightControl |
  hs.eventtap.event.rawFlagMasks.deviceRightShift

function obj.defineKey (map, mods, char, fn, repeatable)
  local e = hs.eventtap.event.newKeyEvent(mods, char, true)
  local flags = e:rawFlags() & MODFLAGS
  local code = e:getKeyCode()
  if not map[flags] then
    map[flags] = {}
  end
  map[flags][code] = { fn, repeatable }
end

function obj.globalSetKey (mods, char, fn, repeatable)
  obj.defineKey(obj.globalMap, mods, char, fn, repeatable)
end

local function maybeDisableOverlayMap ()
  if obj.overlayMap then
    obj.overlayMap = nil
    hs.alert('Prefix cleared')
  end
end

function obj.enableOverlayMap (map)
  maybeDisableOverlayMap()
  obj.overlayMap = map
end

local function lookupKey (map, evt)
  local codeMap = map and map[evt:rawFlags() & MODFLAGS]
  return codeMap and codeMap[evt:getKeyCode()]
end

local function lookupKeyDwim (evt)
  if obj.overlayMap then
    local entry = lookupKey(obj.overlayMap, evt)
    if (not entry) or (not obj.overlayMap.keep) then
      maybeDisableOverlayMap()
    end
    return entry or obj.overlayMap.default
  end
  return lookupKey(obj.globalMap, evt) or obj.globalMap.default
end

obj.addHook(obj.afterFocusChangeHook, maybeDisableOverlayMap)

--
-- The Core
--

-- enabled

obj.keybindsDisabledHook = {}
obj.keybindsEnabledHook = {}
obj.enabled = true

function obj.disableKeyBindings ()
  if obj.enabled then
    obj.enabled = false
    obj.runHooks(obj.keybindsDisabledHook)
  end
end

function obj.enableKeyBindings ()
  if not obj.enabled then
    obj.enabled = true
    obj.runHooks(obj.keybindsEnabledHook)
  end
end

-- filters

obj.applicationFilterValue = false
obj.inputMethodFilterValue = false

local function updateEnabledState ()
  if obj.applicationFilterValue or obj.inputMethodFilterValue then
    obj.disableKeyBindings()
  else
    obj.enableKeyBindings()
  end
end

function obj.setApplicationFilter (fn)
  local wrappedFn = function (app)
    obj.applicationFilterValue = fn(app)
    updateEnabledState()
  end
  wrappedFn(hs.application.frontmostApplication():title())
  obj.addHook(obj.afterFocusChangeHook, wrappedFn)
end

function obj.setInputMethodFilter (fn)
  local wrappedFn = function (method)
    obj.inputMethodFilterValue = fn(method)
    updateEnabledState()
  end
  wrappedFn(hs.keycodes.currentMethod())
  obj.addHook(obj.afterInputMethodChangeHook, wrappedFn)
end

-- digit argument

local nextDigitArgument = 0

function obj.setDigitArgument (val)
  nextDigitArgument = val
end

local function maybeClearDigitArgument ()
  if nextDigitArgument > 0 then
    nextDigitArgument = 0
    hs.alert('Argument cleared')
  end
end

obj.addHook(obj.afterFocusChangeHook, maybeClearDigitArgument)

-- the event loop

obj.lastCommand = nil
obj.lastEvent = nil

obj._watchers[#obj._watchers + 1] = hs.eventtap.new(
  {
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.leftMouseUp,
    hs.eventtap.event.types.rightMouseDown,
    hs.eventtap.event.types.rightMouseUp
  },
  function (evt)
    if not obj.enabled then
      return false
    end
    -- Skip synthetic events to avoid infinite loop
    if eventIsSynthetic(evt) then
      return false
    end
    -- Mouse event -> skip looking up hotkey table
    if not (evt:getType() == hs.eventtap.event.types.keyDown) then
      obj.runHooks(obj.beforeSendHook, evt)
      obj.lastCommand = nil
      obj.lastEvent = evt
      return false
    end
    local entry = lookupKeyDwim(evt)
    -- No hotkey entry found -> passthrough the event (unless explicitly ignored)
    if not entry then
      obj.runHooks(obj.beforeSendHook, evt)
      obj.lastCommand = nil
      obj.lastEvent = evt
      return false
    end
    local repeated = evt:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat)
    if repeated == 0 or entry[2] then
      local arg = nextDigitArgument
      nextDigitArgument = 0
      entry[1](arg, evt)
      obj.lastCommand = entry[1]
      obj.lastEvent = evt
    end
    return true
  end
):start()

--
-- Commands
--

obj.cmd = {}
obj.afterChangeHook = {}

-- Basic commands

function obj.cmd.selfInsertCommand (arg, evt)
  for i = 1, math.max(1, arg) do
    sendSyntheticEvent(evt)
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.selfSendCommand (arg, evt)
  -- Like selfInsertCommand, but does not invoke afterChangeHook
  for i = 1, math.max(1, arg) do
    sendSyntheticEvent(evt)
  end
end

function obj.cmd.digitArgument (arg, evt)
  local digit = tonumber(evt:getCharacters(true))
  local val = arg * 10 + digit
  obj.setDigitArgument(val)
  hs.alert('C-' .. val)
end

function obj.cmd.keyboardQuit ()
  -- Disable mark (note that arg is consumed automatically)
  if obj.markActive then
    obj.markActive = false
  end
  -- Disable overlayMap
  if obj.overlayMap then
    maybeDisableOverlayMap()
  end
  -- Tap twice to send ESC
  if obj.lastCommand == obj.cmd.keyboardQuit then
    obj.sendKey({}, 'escape')
    hs.alert('Esc')
  else
    hs.alert('Quit')
  end
end

function obj.cmd.restricted (cmdName)
  return function ()
    hs.alert('"' .. cmdName .. '" is not bound by default')
  end
end

function obj.cmd.unsupported (cmdName)
  return function ()
    hs.alert('"' .. cmdName .. '" is unsupported')
  end
end

function obj.cmd.ignore ()
end

-- Mark

obj.markActive = false

local function maybeResetMark ()
  if obj.markActive then
    hs.alert('Mark disabled')
    obj.markActive = false
  end
end

function obj.cmd.setMarkCommand ()
  if not obj.markActive then
    hs.alert('Mark enabled')
    obj.markActive = true
  end
end

obj.addHook(obj.afterFocusChangeHook, maybeResetMark)
obj.addHook(obj.afterChangeHook, maybeResetMark)

-- C-x

obj.cxMap = hs.hotkey.modal.new()

function obj.cmd.cx (arg)
  obj.setDigitArgument(arg)
  obj.enableOverlayMap(obj.cxMap)
  hs.alert('C-x')
end

-- Keyboard macro

obj.kmacroRecording = false
obj.kmacro = {}

obj.addHook(
  obj.beforeSendHook,
  function (evt)
    if obj.kmacroRecording then
      obj.kmacro[#obj.kmacro + 1] = evt:copy()
    end
  end
)

function obj.cmd.kmacroStartMacro ()
  obj.kmacroRecording = true
  obj.kmacro = {}
  hs.alert('Macro recording ...')
end

function obj.cmd.kmacroEndMacro ()
  if obj.kmacroRecording then
    obj.kmacroRecording = false
    hs.alert('Macro recorded')
  end
end

function obj.cmd.kmacroEndAndCallMacro (arg)
  obj.cmd.kmacroEndMacro()
  for i = 1, math.max(1, arg) do
    for j = 1, #obj.kmacro do
      sendSyntheticEvent(obj.kmacro[j], 0.1 * ((i - 1) * #obj.kmacro + j))
    end
  end
end

-- kmacro can be defined across applications, except for disabled ones
obj.addHook(obj.keybindsDisabledHook, obj.cmd.kmacroEndMacro)

-- Cursor

function obj.cmd.backwardChar (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift' }, 'left')
    else
      obj.sendKey({}, 'left')
    end
  end
end

function obj.cmd.forwardChar (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift' }, 'right')
    else
      obj.sendKey({}, 'right')
    end
  end
end

function obj.cmd.previousLine (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift' }, 'up')
    else
      obj.sendKey({}, 'up')
    end
  end
end

function obj.cmd.nextLine (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift' }, 'down')
    else
      obj.sendKey({}, 'down')
    end
  end
end

function obj.cmd.forwardWord (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift', 'option' }, 'right')
    else
      obj.sendKey({ 'option' }, 'right')
    end
  end
end

function obj.cmd.backwardWord (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift', 'option' }, 'left')
    else
      obj.sendKey({ 'option' }, 'left')
    end
  end
end

function obj.cmd.beginningOfLine ()
  if obj.markActive then
    obj.sendKey({ 'command', 'shift' }, 'left')
  else
    obj.sendKey({ 'command' }, 'left')
  end
end

function obj.cmd.endOfLine ()
  if obj.markActive then
    obj.sendKey({ 'command', 'shift' }, 'right')
  else
    obj.sendKey({ 'command' }, 'right')
  end
end

function obj.cmd.scrollUp (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift' }, 'pagedown')
    else
      obj.sendKey({}, 'pagedown')
    end
  end
end

function obj.cmd.isearch ()
  maybeResetMark()
  obj.sendKey({ 'command' }, 'f')
end

-- Edit

function obj.cmd.indentForTab (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'tab')
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.deleteChar (arg)
  for i = 1, math.max(1, arg) do
    -- unfortunately ({ 'fn' }, 'delete') did not work
    -- https://github.com/Hammerspoon/hammerspoon/issues/1614
    obj.sendKey({}, 'forwarddelete')
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.deleteBackwardChar (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'delete')
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.killLine ()
  obj.sendKey({ 'command', 'shift' }, 'right')
  obj.sendKey({}, 'delete')
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.newline (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'return')
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.killRegion ()
  obj.sendKey({ 'command' }, 'x')
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.yank (arg)
  if arg > 1 then
    hs.alert('Kill-ring history is unsupported for now')
  else
    obj.sendKey({ 'command' }, 'v')
    obj.runHooks(obj.afterChangeHook)
  end
end

function obj.cmd.openLine (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'return')
    obj.sendKey({}, 'up')
    obj.sendKey({ 'command' }, 'right')
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.undo (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'command' }, 'z')
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.redo (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'command', 'shift' }, 'z')
  end
  obj.runHooks(obj.afterChangeHook)
end

-- Frames

function obj.cmd.suspendFrame ()
  obj.sendKey({ 'command' }, 'm')
end

-- Others

function obj.cmd.toggleInputMethod ()
  if hs.keycodes.currentMethod() == nil then
    -- kana key
    obj.sendKey({}, 0x68)
  else
    -- eisu key
    obj.sendKey({}, 0x66)
  end
end

function obj.cmd.saveBuffer ()
  obj.sendKey({ 'cmd' }, 's')
end

--
-- Keymap
--

function obj.registerDefaultKeymap ()
  -- Reference: `emacs -Q` then `M-x describe-keymap global-map`

  -- Plain
  obj.globalSetKey({}, '`', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '1', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '2', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '3', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '4', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '5', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '6', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '7', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '8', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '9', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '0', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '-', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '=', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'q', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'w', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'e', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'r', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 't', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'y', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'u', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'i', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'o', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'p', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '[', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, ']', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'a', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 's', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'd', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'f', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'g', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'h', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'j', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'k', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'l', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, ';', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '\'', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '\\', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'z', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'x', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'c', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'v', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'b', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'n', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'm', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, ',', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '.', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, '/', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'space', obj.cmd.selfInsertCommand)
  obj.globalSetKey({}, 'tab', obj.cmd.indentForTab)
  obj.globalSetKey({}, 'return', obj.cmd.newline)
  obj.globalSetKey({}, 'escape', obj.cmd.selfSendCommand)

  -- S-*
  obj.globalSetKey({ 'shift' }, '`', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '1', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '2', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '3', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '4', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '5', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '6', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '7', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '8', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '9', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '0', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '-', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '=', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'q', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'w', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'e', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'r', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 't', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'y', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'u', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'i', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'o', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'p', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '[', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, ']', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'a', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 's', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'd', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'f', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'g', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'h', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'j', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'k', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'l', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, ';', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '\'', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '\\', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'z', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'x', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'c', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'v', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'b', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'n', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'm', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, ',', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '.', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, '/', obj.cmd.selfInsertCommand)
  obj.globalSetKey({ 'shift' }, 'space', obj.cmd.ignore)
  obj.globalSetKey({ 'shift' }, 'tab', obj.cmd.ignore) -- maybe selfSendCommand is useful ?
  obj.globalSetKey({ 'shift' }, 'return', obj.cmd.ignore)
  obj.globalSetKey({ 'shift' }, 'escape', obj.cmd.ignore)

  -- C-*
  obj.globalSetKey({ 'ctrl' }, '`', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, '1', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '2', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '3', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '4', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '5', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '6', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '7', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '8', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '9', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '0', obj.cmd.digitArgument)
  obj.globalSetKey({ 'ctrl' }, '-', obj.cmd.unsupported("negativeArgument"))
  obj.globalSetKey({ 'ctrl' }, '=', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, 'q', obj.cmd.unsupported("quotedInsert"))
  obj.globalSetKey({ 'ctrl' }, 'w', obj.cmd.killRegion)
  obj.globalSetKey({ 'ctrl' }, 'e', obj.cmd.endOfLine)
  obj.globalSetKey({ 'ctrl' }, 'r', obj.cmd.unsupported("isearchBackward"))
  obj.globalSetKey({ 'ctrl' }, 't', obj.cmd.unsupported("transposeChars"))
  obj.globalSetKey({ 'ctrl' }, 'y', obj.cmd.yank)
  obj.globalSetKey({ 'ctrl' }, 'u', obj.cmd.unsupported("universalArgument"))
  obj.globalSetKey({ 'ctrl' }, 'i', obj.cmd.indentForTab, true)
  obj.globalSetKey({ 'ctrl' }, 'o', obj.cmd.openLine, true)
  obj.globalSetKey({ 'ctrl' }, 'p', obj.cmd.previousLine)
  obj.globalSetKey({ 'ctrl' }, '[', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, ']', obj.cmd.unsupported("abortRecursiveEdit"))
  obj.globalSetKey({ 'ctrl' }, 'a', obj.cmd.beginningOfLine)
  obj.globalSetKey({ 'ctrl' }, 's', obj.cmd.isearch)
  obj.globalSetKey({ 'ctrl' }, 'd', obj.cmd.deleteChar, true)
  obj.globalSetKey({ 'ctrl' }, 'f', obj.cmd.forwardChar, true)
  obj.globalSetKey({ 'ctrl' }, 'g', obj.cmd.keyboardQuit)
  obj.globalSetKey({ 'ctrl' }, 'h', obj.cmd.deleteBackwardChar, true)
  obj.globalSetKey({ 'ctrl' }, 'j', obj.cmd.newline, true)
  obj.globalSetKey({ 'ctrl' }, 'k', obj.cmd.killLine)
  obj.globalSetKey({ 'ctrl' }, 'l', obj.cmd.unsupported("recenterTopBottom"))
  obj.globalSetKey({ 'ctrl' }, ';', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, '\'', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, '\\', obj.cmd.toggleInputMethod)
  obj.globalSetKey({ 'ctrl' }, 'z', obj.cmd.suspendFrame)
  obj.globalSetKey({ 'ctrl' }, 'x', obj.cmd.cx)
  obj.globalSetKey({ 'ctrl' }, 'c', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, 'v', obj.cmd.scrollUp, true)
  obj.globalSetKey({ 'ctrl' }, 'b', obj.cmd.backwardChar, true)
  obj.globalSetKey({ 'ctrl' }, 'n', obj.cmd.nextLine, true)
  obj.globalSetKey({ 'ctrl' }, 'm', obj.cmd.newline)
  obj.globalSetKey({ 'ctrl' }, ',', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, '.', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, '/', obj.cmd.undo)
  obj.globalSetKey({ 'ctrl' }, 'space', obj.cmd.setMarkCommand)
  obj.globalSetKey({ 'ctrl' }, 'tab', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, 'return', obj.cmd.ignore)
  obj.globalSetKey({ 'ctrl' }, 'escape', obj.cmd.ignore)

  -- TODO: C-S-*
  obj.globalSetKey({ 'ctrl', 'shift' }, '2', obj.cmd.setMarkCommand)
  obj.globalSetKey({ 'ctrl', 'shift' }, '-', obj.cmd.undo)
  obj.globalSetKey({ 'ctrl', 'shift' }, '/', obj.cmd.redo)

  -- TODO: M-*

  -- TODO: M-S-*

  -- TODO: C-M-*
  obj.globalSetKey({ 'command', 'ctrl' }, 'f', obj.cmd.forwardWord, true)
  obj.globalSetKey({ 'command', 'ctrl' }, 'b', obj.cmd.backwardWord, true)

  -- TODO: C-M-S-*

  -- TODO: C-x *
  obj.defineKey(obj.cxMap, {}, 'e', obj.cmd.kmacroEndAndCallMacro)

  -- TODO: C-x S-*
  obj.defineKey(obj.cxMap, { 'shift' }, '9', obj.cmd.kmacroStartMacro)
  obj.defineKey(obj.cxMap, { 'shift' }, '0', obj.cmd.kmacroEndMacro)

  -- TODO: C-x C-*
  obj.defineKey(obj.cxMap, { 'ctrl' }, 's', obj.cmd.saveBuffer)

  -- TODO: C-x C-S-*

  -- TODO: C-x M-*

  -- TODO: C-x M-S-*

  -- TODO: C-x C-M-*

  -- TODO: C-x C-M-S-*
end

return obj
