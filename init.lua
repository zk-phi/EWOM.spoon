-- TODO: State indicators (see hs.canvas doc)
-- TODO: Kill-ring history (C-2 C-y / M-y)

local obj = {};

--
-- Metadata
--

obj.name = 'EWOM Spoon'
obj.version = '0.1.0'
obj.author = 'zk-phi'
obj.license = 'MIT'
obj.homepage = 'https://github.com/zk-phi/EWOM.spoon'

--
-- Mods
--

local C_ = { 'ctrl' }
local S_ = { 'shift' }
local M_ = { 'command' }
local C_S_ = { 'ctrl', 'shift' }
local M_S_ = { 'command', 'shift' }
local C_M_ = { 'ctrl', 'command' }
local C_M_S_ = { 'ctrl', 'command', 'shift' }

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

local function maybeDisableOverlayMap (silent)
  if obj.overlayMap then
    obj.overlayMap = nil
    if not silent then
      hs.alert('Prefix cleared')
    end
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
      maybeDisableOverlayMap(entry)
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
    hs.alert('Quit (press again to send "Esc")')
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
      sendSyntheticEvent(obj.kmacro[j], 0.05 * ((i - 1) * #obj.kmacro + j))
    end
  end
end

-- kmacro can be defined across applications, except for disabled ones
obj.addHook(obj.keybindsDisabledHook, obj.cmd.kmacroEndMacro)

-- Text-scale

obj.textScaleMap = { default = obj.cmd.ignore, keep = true }

local function maybeEnableTextScaleMap ()
  if not (obj.overlayMap == obj.textScaleMap) then
    obj.enableOverlayMap(obj.textScaleMap)
    hs.alert('+ (=), -, 0 for further adjustment')
  end
end

function obj.cmd.textScaleIncrease (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'command', 'shift' }, '=') -- Command +
  end
  maybeEnableTextScaleMap()
end

function obj.cmd.textScaleDecrease (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'command' }, '-') -- Command -
  end
  maybeEnableTextScaleMap()
end

function obj.cmd.textScaleReset (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'command' }, '0') -- Command 0
  end
  maybeEnableTextScaleMap()
end

obj.defineKey(obj.textScaleMap, {}, '0', obj.cmd.textScaleReset)
obj.defineKey(obj.textScaleMap, {}, '-', obj.cmd.textScaleDecrease)
obj.defineKey(obj.textScaleMap, {}, '=', obj.cmd.textScaleIncrease)
obj.defineKey(obj.textScaleMap, S_, '=', obj.cmd.textScaleIncrease)
obj.defineKey(obj.textScaleMap, C_, '0', obj.cmd.textScaleReset)
obj.defineKey(obj.textScaleMap, C_, '-', obj.cmd.textScaleDecrease)
obj.defineKey(obj.textScaleMap, C_, '=', obj.cmd.textScaleIncrease)
obj.defineKey(obj.textScaleMap, C_S_, '=', obj.cmd.textScaleIncrease)
obj.defineKey(obj.textScaleMap, M_, '0', obj.cmd.textScaleReset)
obj.defineKey(obj.textScaleMap, M_, '-', obj.cmd.textScaleDecrease)
obj.defineKey(obj.textScaleMap, M_, '=', obj.cmd.textScaleIncrease)
obj.defineKey(obj.textScaleMap, M_S_, '=', obj.cmd.textScaleIncrease)
obj.defineKey(obj.textScaleMap, C_M_, '0', obj.cmd.textScaleReset)
obj.defineKey(obj.textScaleMap, C_M_, '-', obj.cmd.textScaleDecrease)
obj.defineKey(obj.textScaleMap, C_M_, '=', obj.cmd.textScaleIncrease)
obj.defineKey(obj.textScaleMap, C_M_S_, '=', obj.cmd.textScaleIncrease)

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

function obj.cmd.scrollDown (arg)
  for i = 1, math.max(1, arg) do
    if obj.markActive then
      obj.sendKey({ 'shift' }, 'pageup')
    else
      obj.sendKey({}, 'pageup')
    end
  end
end

function obj.cmd.beginningOfBuffer ()
  if obj.markActive then
    obj.sendKey({ 'shift', 'command' }, 'up')
  else
    obj.sendKey({ 'command' }, 'up')
  end
end

function obj.cmd.endOfBuffer ()
  if obj.markActive then
    obj.sendKey({ 'shift', 'command' }, 'down')
  else
    obj.sendKey({ 'command' }, 'down')
  end
end

function obj.cmd.isearch ()
  maybeResetMark()
  obj.sendKey({ 'command' }, 'f')
end

-- Mark

function obj.cmd.markWord ()
  obj.sendKey({ 'shift', 'option' }, 'right')
  obj.sendKey({ 'shift', 'option' }, 'left')
  obj.cmd.setMarkCommand()
end

function obj.cmd.markWholeBuffer ()
  obj.sendKey({ 'command' }, 'a')
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
  obj.sendKey({ 'command' }, 'x')
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.killWord ()
  obj.sendKey({ 'option', 'shift' }, 'right')
  obj.sendKey({ 'command' }, 'x')
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.newline (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'return')
  end
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.defaultIndentNewline (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'return')
    obj.sendKey({}, 'tab')
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

function obj.cmd.killRingSave ()
  obj.sendKey({ 'command' }, 'c')
  maybeResetMark()
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

function obj.cmd.insertParentheses (arg)
  if arg > 0 then
    hs.alert('Wrapping sexps is unsupported')
  else
    obj.sendKey({}, '(')
    obj.sendKey({}, ')')
    obj.sendKey({}, 'left')
    obj.runHooks(obj.afterChangeHook)
  end
end

function obj.cmd.transposeChars (arg)
  obj.sendKey({ 'shift' }, 'left')
  obj.sendKey({ 'command' }, 'x')
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'right')
  end
  obj.sendKey({ 'command' }, 'v')
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.transposeWords (arg)
  obj.sendKey({ 'option' }, 'left')
  obj.sendKey({ 'option' }, 'left')
  obj.sendKey({ 'option' }, 'right')
  obj.sendKey({ 'option', 'shift' }, 'right')
  obj.sendKey({ 'command' }, 'x')
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'option' }, 'right')
  end
  obj.sendKey({ 'command' }, 'v')
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.transposeLines (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, 'up')
  end
  obj.sendKey({ 'command' }, 'left')
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'shift' }, 'down')
  end
  obj.sendKey({ 'command', 'shift' }, 'left')
  obj.sendKey({ 'command' }, 'x')
  obj.sendKey({}, 'down')
  obj.sendKey({ 'command' }, 'left')
  obj.sendKey({ 'command' }, 'v')
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.upcaseWord (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'option', 'shift' }, 'right')
  end
  obj.sendKey({ 'command' }, 'x')
  hs.pasteboard.callbackWhenChanged(
    function (success)
      local content = success and hs.pasteboard.getContents()
      if content then
        hs.eventtap.keyStrokes(content:upper())
      else
        obj.sendKey({ 'command' }, 'v')
        hs.alert('Operation failed')
      end
    end
  )
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.downcaseWord (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'option', 'shift' }, 'right')
  end
  obj.sendKey({ 'command' }, 'x')
  hs.pasteboard.callbackWhenChanged(
    function (success)
      local content = success and hs.pasteboard.getContents()
      if content then
        hs.eventtap.keyStrokes(content:lower())
      else
        obj.sendKey({ 'command' }, 'v')
        hs.alert('Operation failed')
      end
    end
  )
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.capitalizeWord (arg)
  for i = 1, math.max(1, arg) do
    obj.sendKey({ 'option', 'shift' }, 'right')
  end
  obj.sendKey({ 'command' }, 'x')
  hs.pasteboard.callbackWhenChanged(
    function (success)
      local content = success and hs.pasteboard.getContents()
      if content then
        hs.eventtap.keyStrokes(content:sub(1, 1):upper() .. content:sub(2):lower())
      else
        obj.sendKey({ 'command' }, 'v')
        hs.alert('Operation failed')
      end
    end
  )
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.downcaseRegion ()
  obj.sendKey({ 'command' }, 'x')
  hs.pasteboard.callbackWhenChanged(
    function (success)
      local content = success and hs.pasteboard.getContents()
      if content then
        hs.eventtap.keyStrokes(content:lower())
      else
        obj.sendKey({ 'command' }, 'v')
        hs.alert('Operation failed')
      end
    end
  )
  obj.runHooks(obj.afterChangeHook)
end

function obj.cmd.upcaseRegion ()
  obj.sendKey({ 'command' }, 'x')
  hs.pasteboard.callbackWhenChanged(
    function (success)
      local content = success and hs.pasteboard.getContents()
      if content then
        hs.eventtap.keyStrokes(content:upper())
      else
        obj.sendKey({ 'command' }, 'v')
        hs.alert('Operation failed')
      end
    end
  )
  obj.runHooks(obj.afterChangeHook)
end

-- Windows

function obj.cmd.tabNew ()
  obj.sendKey({ 'command' }, 't')
end

function obj.cmd.tabClose ()
  obj.sendKey({ 'command' }, 'w')
end

function obj.cmd.tabNext ()
  obj.sendKey({ 'ctrl' }, 'tab')
end

function obj.cmd.tabPrevious ()
  obj.sendKey({ 'ctrl', 'shift' }, 'tab')
end

-- Frames

function obj.cmd.suspendFrame ()
  obj.sendKey({ 'command' }, 'm')
end

-- Others

function obj.cmd.spotlight ()
  obj.sendKey({ 'command' }, 'space')
end

function obj.cmd.finder ()
  hs.application.open('Finder')
end

function obj.cmd.mail ()
  hs.application.open('Mail')
end

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

function obj.cmd.writeFile ()
  obj.sendKey({ 'cmd', 'shift' }, 's')
end

function obj.cmd.killApp ()
  obj.sendKey({ 'cmd' }, 'q')
end

function obj.cmd.repeatLastCommand (arg)
  if not obj.lastCommand then
    sendSyntheticEvent(obj.lastEvent:copy())
  else
    obj.lastCommand(arg, obj.lastEvent)
  end
end

--
-- Keymap
--

obj.cxMap = { default = obj.cmd.ignore }
obj.cxwMap = { default = obj.cmd.ignore }
obj.cxtMap = { default = obj.cmd.ignore }

function obj.cmd.cx (arg)
  obj.setDigitArgument(arg)
  obj.enableOverlayMap(obj.cxMap)
  hs.alert('C-x')
end

function obj.cmd.cxw (arg)
  obj.setDigitArgument(arg)
  obj.enableOverlayMap(obj.cxwMap)
  hs.alert('C-x w')
end

function obj.cmd.cxt (arg)
  obj.setDigitArgument(arg)
  obj.enableOverlayMap(obj.cxtMap)
  hs.alert('C-x t')
end

-- Reference: `emacs -Q` then `M-x describe-keymap global-map`

-- Unmodified keycodes: non-ASCII chars and Tab
-- https://www.hammerspoon.org/docs/hs.keycodes.html#map
-- Tab, Return, Delete, ForwardDelete,
-- F1-F20, Numpad, Escape, CapsLock,
-- Home, PageUp, PageDown, End, Left, Right, Down, Up

function obj.registerBaseKeymap ()
  -- Plain
  obj.globalSetKey({}, '`', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '1', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '2', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '3', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '4', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '5', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '6', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '7', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '8', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '9', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '0', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '-', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '=', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'q', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'w', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'e', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'r', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 't', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'y', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'u', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'i', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'o', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'p', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '[', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, ']', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'a', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 's', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'd', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'f', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'g', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'h', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'j', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'k', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'l', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, ';', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '\'', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '\\', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'z', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'x', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'c', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'v', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'b', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'n', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'm', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, ',', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '.', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, '/', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey({}, 'space', obj.cmd.selfInsertCommand, true)

  -- S-*
  obj.globalSetKey(S_, '`', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '1', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '2', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '3', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '4', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '5', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '6', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '7', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '8', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '9', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '0', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '-', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '=', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'q', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'w', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'e', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'r', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 't', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'y', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'u', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'i', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'o', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'p', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '[', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, ']', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'a', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 's', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'd', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'f', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'g', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'h', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'j', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'k', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'l', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, ';', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '\'', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '\\', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'z', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'x', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'c', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'v', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'b', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'n', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, 'm', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, ',', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '.', obj.cmd.selfInsertCommand, true)
  obj.globalSetKey(S_, '/', obj.cmd.selfInsertCommand, true)
end

function obj.registerDefaultKeymap ()
  obj.registerBaseKeymap()

  -- S-*
  obj.globalSetKey(S_, 'space', obj.cmd.ignore)

  -- C-*
  obj.globalSetKey(C_, '`', obj.cmd.ignore)
  obj.globalSetKey(C_, '1', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '2', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '3', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '4', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '5', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '6', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '7', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '8', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '9', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '0', obj.cmd.digitArgument)
  obj.globalSetKey(C_, '-', obj.cmd.unsupported('negativeArgument'))
  obj.globalSetKey(C_, '=', obj.cmd.ignore)
  obj.globalSetKey(C_, 'q', obj.cmd.unsupported('quotedInsert'))
  obj.globalSetKey(C_, 'w', obj.cmd.killRegion)
  obj.globalSetKey(C_, 'e', obj.cmd.endOfLine)
  obj.globalSetKey(C_, 'r', obj.cmd.unsupported('isearchBackward'))
  obj.globalSetKey(C_, 't', obj.cmd.transposeChars)
  obj.globalSetKey(C_, 'y', obj.cmd.yank)
  obj.globalSetKey(C_, 'u', obj.cmd.unsupported('universalArgument'))
  obj.globalSetKey(C_, 'i', obj.cmd.indentForTab, true)
  obj.globalSetKey(C_, 'o', obj.cmd.openLine, true)
  obj.globalSetKey(C_, 'p', obj.cmd.previousLine, true)
  obj.globalSetKey(C_, '[', obj.cmd.ignore)
  obj.globalSetKey(C_, ']', obj.cmd.unsupported('abortRecursiveEdit'))
  obj.globalSetKey(C_, 'a', obj.cmd.beginningOfLine)
  obj.globalSetKey(C_, 's', obj.cmd.isearch)
  obj.globalSetKey(C_, 'd', obj.cmd.deleteChar, true)
  obj.globalSetKey(C_, 'f', obj.cmd.forwardChar, true)
  obj.globalSetKey(C_, 'g', obj.cmd.keyboardQuit)
  obj.globalSetKey(C_, 'h', obj.cmd.deleteBackwardChar, true)
  obj.globalSetKey(C_, 'j', obj.cmd.newline, true)
  obj.globalSetKey(C_, 'k', obj.cmd.killLine)
  obj.globalSetKey(C_, 'l', obj.cmd.unsupported('recenterTopBottom'))
  obj.globalSetKey(C_, ';', obj.cmd.ignore)
  obj.globalSetKey(C_, '\'', obj.cmd.ignore)
  obj.globalSetKey(C_, '\\', obj.cmd.toggleInputMethod)
  obj.globalSetKey(C_, 'z', obj.cmd.suspendFrame)
  obj.globalSetKey(C_, 'x', obj.cmd.cx)
  obj.globalSetKey(C_, 'c', obj.cmd.ignore)
  obj.globalSetKey(C_, 'v', obj.cmd.scrollUp, true)
  obj.globalSetKey(C_, 'b', obj.cmd.backwardChar, true)
  obj.globalSetKey(C_, 'n', obj.cmd.nextLine, true)
  obj.globalSetKey(C_, 'm', obj.cmd.newline)
  obj.globalSetKey(C_, ',', obj.cmd.ignore)
  obj.globalSetKey(C_, '.', obj.cmd.ignore)
  obj.globalSetKey(C_, '/', obj.cmd.undo)
  obj.globalSetKey(C_, 'space', obj.cmd.setMarkCommand)

  -- C-S-*
  obj.globalSetKey(C_S_, '`', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '1', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '2', obj.cmd.setMarkCommand)
  obj.globalSetKey(C_S_, '3', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '4', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '5', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '6', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '7', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '8', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '9', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '0', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '-', obj.cmd.undo)
  obj.globalSetKey(C_S_, '=', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'q', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'w', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'e', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'r', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 't', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'y', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'u', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'i', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'o', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'p', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '[', obj.cmd.ignore)
  obj.globalSetKey(C_S_, ']', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'a', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 's', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'd', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'f', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'g', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'h', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'j', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'k', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'l', obj.cmd.ignore)
  obj.globalSetKey(C_S_, ';', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '\'', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '\\', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'z', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'x', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'c', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'v', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'b', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'n', obj.cmd.ignore)
  obj.globalSetKey(C_S_, 'm', obj.cmd.ignore)
  obj.globalSetKey(C_S_, ',', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '.', obj.cmd.ignore)
  obj.globalSetKey(C_S_, '/', obj.cmd.redo)
  obj.globalSetKey(C_S_, 'space', obj.cmd.ignore)

  -- M-*
  obj.globalSetKey(M_, '`', obj.cmd.unsupported('tmmMenubar')) -- CtrlF2 ?
  obj.globalSetKey(M_, '1', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '2', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '3', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '4', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '5', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '6', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '7', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '8', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '9', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '0', obj.cmd.digitArgument)
  obj.globalSetKey(M_, '-', obj.cmd.unsupported('negativeArgument'))
  obj.globalSetKey(M_, '=', obj.cmd.unsupported('countWordsRegion'))
  obj.globalSetKey(M_, 'q', obj.cmd.unsupported('fillParagraph'))
  obj.globalSetKey(M_, 'w', obj.cmd.killRingSave)
  obj.globalSetKey(M_, 'e', obj.cmd.unsupported('forwardSentence')) -- CtrlRight ?
  obj.globalSetKey(M_, 'r', obj.cmd.unsupported('moveToWindowLineTopBottom'))
  obj.globalSetKey(M_, 't', obj.cmd.transposeWords)
  obj.globalSetKey(M_, 'y', obj.cmd.unsupported('yankPop'))
  obj.globalSetKey(M_, 'u', obj.cmd.upcaseWord)
  obj.globalSetKey(M_, 'i', obj.cmd.indentForTab) -- tab-to-tab-stop
  obj.globalSetKey(M_, 'o', obj.cmd.ignore)
  obj.globalSetKey(M_, 'p', obj.cmd.ignore)
  obj.globalSetKey(M_, '[', obj.cmd.ignore)
  obj.globalSetKey(M_, ']', obj.cmd.ignore)
  obj.globalSetKey(M_, 'a', obj.cmd.unsupported('backwardSentence')) -- CtrlLeft ?
  obj.globalSetKey(M_, 's', obj.cmd.unsupported('M-s *'))
  obj.globalSetKey(M_, 'd', obj.cmd.killWord)
  obj.globalSetKey(M_, 'f', obj.cmd.forwardWord)
  obj.globalSetKey(M_, 'g', obj.cmd.unsupported('M-g *'))
  obj.globalSetKey(M_, 'h', obj.cmd.unsupported('markParagraph'))
  obj.globalSetKey(M_, 'j', obj.cmd.defaultIndentNewline)
  obj.globalSetKey(M_, 'k', obj.cmd.unsupported('killSentence')) -- CtrlRight-Delete ?
  obj.globalSetKey(M_, 'l', obj.cmd.downcaseWord)
  obj.globalSetKey(M_, ';', obj.cmd.unsupported('commentDwim'))
  obj.globalSetKey(M_, '\'', obj.cmd.unsupported('abbrevPrefixMark'))
  obj.globalSetKey(M_, '\\', obj.cmd.unsupported('deleteHorizontalSpace'))
  obj.globalSetKey(M_, 'z', obj.cmd.unsupported('zapToChar'))
  obj.globalSetKey(M_, 'x', obj.cmd.spotlight) -- execute-extended-command
  obj.globalSetKey(M_, 'c', obj.cmd.capitalizeWord)
  obj.globalSetKey(M_, 'v', obj.cmd.scrollDown)
  obj.globalSetKey(M_, 'b', obj.cmd.backwardWord)
  obj.globalSetKey(M_, 'n', obj.cmd.ignore)
  obj.globalSetKey(M_, 'm', obj.cmd.beginningOfLine) -- back-to-indentation
  obj.globalSetKey(M_, ',', obj.cmd.unsupported('xrefGoBack'))
  obj.globalSetKey(M_, '.', obj.cmd.unsupported('xrefFindDefinitions'))
  obj.globalSetKey(M_, '/', obj.cmd.unsupported('dabbrevExpand'))
  obj.globalSetKey(M_, 'space', obj.cmd.unsupported('cycleSpacing'))

  -- M-S-*
  obj.globalSetKey(M_S_, '`', obj.cmd.unsupported('notModified'))
  obj.globalSetKey(M_S_, '1', obj.cmd.spotlight) -- shell-command
  obj.globalSetKey(M_S_, '2', obj.cmd.markWord)
  obj.globalSetKey(M_S_, '3', obj.cmd.ignore)
  obj.globalSetKey(M_S_, '4', obj.cmd.unsupported('ispellWord'))
  obj.globalSetKey(M_S_, '5', obj.cmd.unsupported('queryReplace')) -- no de-facto shortcut ?
  obj.globalSetKey(M_S_, '6', obj.cmd.unsupported('deleteIndentation'))
  obj.globalSetKey(M_S_, '7', obj.cmd.spotlight) -- async-shell-command
  obj.globalSetKey(M_S_, '8', obj.cmd.ignore)
  obj.globalSetKey(M_S_, '9', obj.cmd.insertParentheses)
  obj.globalSetKey(M_S_, '0', obj.cmd.unsupported('movePastCloseAndReindent'))
  obj.globalSetKey(M_S_, '-', obj.cmd.ignore)
  obj.globalSetKey(M_S_, '=', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'q', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'w', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'e', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'r', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 't', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'y', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'u', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'i', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'o', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'p', obj.cmd.ignore)
  obj.globalSetKey(M_S_, '[', obj.cmd.unsupported('backwardParagraph')) -- OptUp ?
  obj.globalSetKey(M_S_, ']', obj.cmd.unsupported('forwardParagraph'))  -- OptDown ?
  obj.globalSetKey(M_S_, 'a', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 's', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'd', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'f', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'g', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'h', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'j', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'k', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'l', obj.cmd.ignore)
  obj.globalSetKey(M_S_, ';', obj.cmd.unsupported('evalExpression'))
  obj.globalSetKey(M_S_, '\'', obj.cmd.ignore)
  obj.globalSetKey(M_S_, '\\', obj.cmd.unsupported('shellCommandOnRegion'))
  obj.globalSetKey(M_S_, 'z', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'x', obj.cmd.unsupported('executeExtendedCommandForBuffer'))
  obj.globalSetKey(M_S_, 'c', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'v', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'b', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'n', obj.cmd.ignore)
  obj.globalSetKey(M_S_, 'm', obj.cmd.ignore)
  obj.globalSetKey(M_S_, ',', obj.cmd.beginningOfBuffer)
  obj.globalSetKey(M_S_, '.', obj.cmd.endOfBuffer)
  obj.globalSetKey(M_S_, '/', obj.cmd.unsupported('xrefFindReferences'))
  obj.globalSetKey(M_S_, 'space', obj.cmd.ignore)

  -- C-M-*
  obj.globalSetKey(C_M_, '`', obj.cmd.ignore)
  obj.globalSetKey(C_M_, '1', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '2', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '3', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '4', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '5', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '6', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '7', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '8', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '9', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '0', obj.cmd.digitArgument)
  obj.globalSetKey(C_M_, '-', obj.cmd.unsupported('negativeArgument'))
  obj.globalSetKey(C_M_, '=', obj.cmd.ignore)
  obj.globalSetKey(C_M_, 'q', obj.cmd.ignore)
  obj.globalSetKey(C_M_, 'w', obj.cmd.unsupported('appendNextKill'))
  obj.globalSetKey(C_M_, 'e', obj.cmd.unsupported('endOfDefun'))
  obj.globalSetKey(C_M_, 'r', obj.cmd.unsupported('isearchBackwardRegexp'))
  obj.globalSetKey(C_M_, 't', obj.cmd.unsupported('transposeSexps'))
  obj.globalSetKey(C_M_, 'y', obj.cmd.ignore)
  obj.globalSetKey(C_M_, 'u', obj.cmd.unsupported('backwardUpList'))
  obj.globalSetKey(C_M_, 'i', obj.cmd.unsupported('completeSymbol'))
  obj.globalSetKey(C_M_, 'o', obj.cmd.unsupported('splitLine'))
  obj.globalSetKey(C_M_, 'p', obj.cmd.unsupported('backwardList'))
  obj.globalSetKey(C_M_, '[', obj.cmd.ignore)
  obj.globalSetKey(C_M_, ']', obj.cmd.ignore)
  obj.globalSetKey(C_M_, 'a', obj.cmd.unsupported('beginningOfDefun'))
  obj.globalSetKey(C_M_, 's', obj.cmd.isearch) -- isearch-forward-regexp
  obj.globalSetKey(C_M_, 'd', obj.cmd.unsupported('downList'))
  obj.globalSetKey(C_M_, 'f', obj.cmd.unsupported('forwardSexp'))
  obj.globalSetKey(C_M_, 'g', obj.cmd.ignore)
  obj.globalSetKey(C_M_, 'h', obj.cmd.unsupported('markDefun'))
  obj.globalSetKey(C_M_, 'j', obj.cmd.defaultIndentNewline)
  obj.globalSetKey(C_M_, 'k', obj.cmd.unsupported('killSexp'))
  obj.globalSetKey(C_M_, 'l', obj.cmd.unsupported('repositionWindow'))
  obj.globalSetKey(C_M_, ';', obj.cmd.ignore)
  obj.globalSetKey(C_M_, '\'', obj.cmd.ignore)
  obj.globalSetKey(C_M_, '\\', obj.cmd.unsupported('indentRegion'))
  obj.globalSetKey(C_M_, 'z', obj.cmd.ignore)
  obj.globalSetKey(C_M_, 'x', obj.cmd.ignore)
  obj.globalSetKey(C_M_, 'c', obj.cmd.unsupported('exitRecursiveEdit'))
  obj.globalSetKey(C_M_, 'v', obj.cmd.unsupported('scrollOtherWindow'))
  obj.globalSetKey(C_M_, 'b', obj.cmd.unsupported('backwardSexp'))
  obj.globalSetKey(C_M_, 'n', obj.cmd.unsupported('forwardList'))
  obj.globalSetKey(C_M_, 'm', obj.cmd.ignore)
  obj.globalSetKey(C_M_, ',', obj.cmd.unsupported('xrefGoForward'))
  obj.globalSetKey(C_M_, '.', obj.cmd.unsupported('xrefFindApropos'))
  obj.globalSetKey(C_M_, '/', obj.cmd.unsupported('dabbrevCompletion'))
  obj.globalSetKey(C_M_, 'space', obj.cmd.unsupported('markSexp'))

  -- C-M-S-*
  obj.globalSetKey(C_M_S_, '`', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '1', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '2', obj.cmd.unsupported('markSexp'))
  obj.globalSetKey(C_M_S_, '3', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '4', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '5', obj.cmd.unsupported('queryReplaceRegexp'))
  obj.globalSetKey(C_M_S_, '6', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '7', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '8', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '9', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '0', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '-', obj.cmd.redo)
  obj.globalSetKey(C_M_S_, '=', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'q', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'w', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'e', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'r', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 't', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'y', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'u', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'i', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'o', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'p', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '[', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, ']', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'a', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 's', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'd', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'f', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'g', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'h', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'j', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'k', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'l', obj.cmd.unsupported('recenterOtherWindow'))
  obj.globalSetKey(C_M_S_, ';', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '\'', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '\\', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'z', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'x', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'c', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'v', obj.cmd.unsupported('scrollOtherWindowDown'))
  obj.globalSetKey(C_M_S_, 'b', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'n', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'm', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, ',', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '.', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, '/', obj.cmd.ignore)
  obj.globalSetKey(C_M_S_, 'space', obj.ignore)

  -- C-x * (ignore by default)
  obj.defineKey(obj.cxMap, {}, '`', obj.cmd.unsupported('nextError'))
  obj.defineKey(obj.cxMap, {}, '1', obj.cmd.unsupported('deleteOtherWindows'))
  obj.defineKey(obj.cxMap, {}, '2', obj.cmd.tabNew) -- split-window-below
  obj.defineKey(obj.cxMap, {}, '3', obj.cmd.tabNew) -- split-window-right
  obj.defineKey(obj.cxMap, {}, '4', obj.cmd.unsupported('C-x 4 *'))
  obj.defineKey(obj.cxMap, {}, '5', obj.cmd.unsupported('C-x 5 *'))
  obj.defineKey(obj.cxMap, {}, '6', obj.cmd.unsupported('2C'))
  obj.defineKey(obj.cxMap, {}, '8', obj.cmd.unsupported('C-x 8 *'))
  obj.defineKey(obj.cxMap, {}, '0', obj.cmd.restricted('tabClose')) -- delete-window
  obj.defineKey(obj.cxMap, {}, '-', obj.cmd.unsupported('shrinkWindowIfLargerThanBuffer'))
  obj.defineKey(obj.cxMap, {}, '=', obj.cmd.unsupported('whatCursorPosition'))
  obj.defineKey(obj.cxMap, {}, 'q', obj.cmd.unsupported('kbdMacroQuery'))
  obj.defineKey(obj.cxMap, {}, 'w', obj.cmd.cxw)
  obj.defineKey(obj.cxMap, {}, 'e', obj.cmd.kmacroEndAndCallMacro)
  obj.defineKey(obj.cxMap, {}, 'r', obj.cmd.unsupported('C-x r *'))
  obj.defineKey(obj.cxMap, {}, 't', obj.cmd.cxt)
  obj.defineKey(obj.cxMap, {}, 'u', obj.cmd.undo)
  obj.defineKey(obj.cxMap, {}, 'i', obj.cmd.unsupported('insertFile'))
  obj.defineKey(obj.cxMap, {}, 'o', obj.cmd.tabNext) -- other-window
  obj.defineKey(obj.cxMap, {}, 'p', obj.cmd.unsupported('project'))
  obj.defineKey(obj.cxMap, {}, '[', obj.cmd.unsupported('backwardPage'))
  obj.defineKey(obj.cxMap, {}, ']', obj.cmd.unsupported('forwardPage'))
  obj.defineKey(obj.cxMap, {}, 'a', obj.cmd.unsupported('abbrev'))
  obj.defineKey(obj.cxMap, {}, 's', obj.cmd.unsupported('saveSomeBuffers'))
  obj.defineKey(obj.cxMap, {}, 'd', obj.cmd.finder)
  obj.defineKey(obj.cxMap, {}, 'f', obj.cmd.unsupported('setFillColumn'))
  obj.defineKey(obj.cxMap, {}, 'h', obj.cmd.markWholeBuffer)
  obj.defineKey(obj.cxMap, {}, 'k', obj.cmd.tabClose) -- kill-buffer
  obj.defineKey(obj.cxMap, {}, 'l', obj.cmd.unsupported('countLinesPage'))
  obj.defineKey(obj.cxMap, {}, ';', obj.cmd.unsupported('commentSetColumn'))
  obj.defineKey(obj.cxMap, {}, '\'', obj.cmd.unsupported('expandAbbrev'))
  obj.defineKey(obj.cxMap, {}, '\\', obj.cmd.unsupported('activateTransientInputMethod'))
  obj.defineKey(obj.cxMap, {}, 'z', obj.cmd.repeatLastCommand)
  obj.defineKey(obj.cxMap, {}, 'x', obj.cmd.unsupported('C-x x *'))
  obj.defineKey(obj.cxMap, {}, 'v', obj.cmd.unsupported('vc'))
  obj.defineKey(obj.cxMap, {}, 'b', obj.cmd.unsupported('switchToBuffer'))
  obj.defineKey(obj.cxMap, {}, 'n', obj.cmd.unsupported('narrowing'))
  obj.defineKey(obj.cxMap, {}, 'm', obj.cmd.mail) -- compose-mail
  obj.defineKey(obj.cxMap, {}, '.', obj.cmd.unsupported('setFillPrefix'))
  obj.defineKey(obj.cxMap, {}, 'space', obj.cmd.unsupported('rectangleMarkMode'))

  -- C-x S-* (ignore by default)
  obj.defineKey(obj.cxMap, S_, '4', obj.cmd.unsupported('setSelectiveDisplay'))
  obj.defineKey(obj.cxMap, S_, '6', obj.cmd.unsupported('enlargeWindow'))
  obj.defineKey(obj.cxMap, S_, '8', obj.cmd.unsupported('calcDispatch'))
  obj.defineKey(obj.cxMap, S_, '9', obj.cmd.kmacroStartMacro)
  obj.defineKey(obj.cxMap, S_, '0', obj.cmd.kmacroEndMacro)
  obj.defineKey(obj.cxMap, S_, '=', obj.cmd.unsupported('balanceWindows'))
  obj.defineKey(obj.cxMap, S_, '[', obj.cmd.unsupported('shrinkWindowHorizontally'))
  obj.defineKey(obj.cxMap, S_, ']', obj.cmd.unsupported('enlargeWindowHorizontally'))
  obj.defineKey(obj.cxMap, S_, ',', obj.cmd.unsupported('scrollLeft'))
  obj.defineKey(obj.cxMap, S_, '.', obj.cmd.unsupported('scrollRight'))

  -- C-x C-* (ignore by default)
  obj.defineKey(obj.cxMap, C_, '0', obj.cmd.restricted('textScaleReset'))
  obj.defineKey(obj.cxMap, C_, '-', obj.cmd.restricted('textScaleDecrease'))
  obj.defineKey(obj.cxMap, C_, '=', obj.cmd.restricted('textScaleIncrease'))
  obj.defineKey(obj.cxMap, C_, 'q', obj.cmd.unsupported('readOnlyMode'))
  obj.defineKey(obj.cxMap, C_, 'w', obj.cmd.writeFile)
  obj.defineKey(obj.cxMap, C_, 'e', obj.cmd.unsupported('evalLastSexp'))
  obj.defineKey(obj.cxMap, C_, 'r', obj.cmd.spotlight) -- find-file-read-only
  obj.defineKey(obj.cxMap, C_, 't', obj.cmd.transposeLines)
  obj.defineKey(obj.cxMap, C_, 'u', obj.cmd.upcaseRegion)
  obj.defineKey(obj.cxMap, C_, 'o', obj.cmd.unsupported('deleteBlankLines'))
  obj.defineKey(obj.cxMap, C_, 'p', obj.cmd.unsupported('markPage'))
  obj.defineKey(obj.cxMap, C_, 's', obj.cmd.saveBuffer)
  obj.defineKey(obj.cxMap, C_, 'd', obj.cmd.spotlight) -- list-directory
  obj.defineKey(obj.cxMap, C_, 'f', obj.cmd.spotlight) -- find-file
  obj.defineKey(obj.cxMap, C_, 'j', obj.cmd.finder) -- dired-jump
  obj.defineKey(obj.cxMap, C_, 'k', obj.cmd.unsupported('C-x C-k *'))
  obj.defineKey(obj.cxMap, C_, 'l', obj.cmd.downcaseRegion)
  obj.defineKey(obj.cxMap, C_, ';', obj.cmd.unsupported('commentLine'))
  obj.defineKey(obj.cxMap, C_, 'z', obj.cmd.suspendFrame)
  obj.defineKey(obj.cxMap, C_, 'x', obj.cmd.unsupported('exchangePointAndMark'))
  obj.defineKey(obj.cxMap, C_, 'c', obj.cmd.restricted('killApp'))
  obj.defineKey(obj.cxMap, C_, 'v', obj.cmd.spotlight) -- find-alternate-file
  obj.defineKey(obj.cxMap, C_, 'b', obj.cmd.unsupported('listBuffers'))
  obj.defineKey(obj.cxMap, C_, 'n', obj.cmd.unsupported('setGoalColumn'))
  obj.defineKey(obj.cxMap, C_, 'space', obj.cmd.unsupported('popGlobalMark'))

  -- C-x C-S-* (ignore by default)
  obj.defineKey(obj.cxMap, C_S_, '2', obj.cmd.restricted('popGlobalMark'))
  obj.defineKey(obj.cxMap, C_S_, '=', obj.cmd.restricted('textScaleIncrease'))

  -- C-x M-* (ignore by default)

  -- C-x M-S-* (ignore by default)
  obj.defineKey(obj.cxMap, M_S_, ';', obj.cmd.unsupported('repeatComplexCommand'))

  -- C-x C-M-* (ignore by default)
  obj.defineKey(obj.cxMap, C_M_, '0', obj.cmd.restricted('textScaleReset'))
  obj.defineKey(obj.cxMap, C_M_, '-', obj.cmd.restricted('textScaleDecrease'))
  obj.defineKey(obj.cxMap, C_M_, '=', obj.cmd.restricted('textScaleIncrease'))

  -- C-x C-M-S-* (ignore by default)
  obj.defineKey(obj.cxMap, C_M_S_, '=', obj.cmd.restricted('textScaleIncrease'))

  -- C-x w * (ignore by default)
  obj.defineKey(obj.cxwMap, {}, '0', obj.cmd.restricted('tabClose')) -- delete-windows-on
  obj.defineKey(obj.cxwMap, {}, '2', obj.cmd.tabNew) -- split-root-window-below
  obj.defineKey(obj.cxwMap, {}, '3', obj.cmd.tabNew) -- split-root-window-right
  obj.defineKey(obj.cxwMap, {}, '-', obj.cmd.unsupported('fitWindowToBuffer'))
  obj.defineKey(obj.cxwMap, {}, 's', obj.cmd.unsupported('windowToggleSideWindows'))

  -- C-x t * (ignore by default)
  obj.defineKey(obj.cxtMap, {}, '0', obj.cmd.tabClose)
  obj.defineKey(obj.cxtMap, {}, '1', obj.cmd.unsupported('tabCloseOther'))
  obj.defineKey(obj.cxtMap, {}, '2', obj.cmd.tabNew)
  obj.defineKey(obj.cxtMap, {}, 'r', obj.cmd.unsupported('tabRename'))
  obj.defineKey(obj.cxtMap, {}, 't', obj.cmd.unsupported('C-x t t *'))
  obj.defineKey(obj.cxtMap, {}, 'u', obj.cmd.unsupported('tabUndo'))
  obj.defineKey(obj.cxtMap, {}, 'o', obj.cmd.tabNext)
  obj.defineKey(obj.cxtMap, {}, 'p', obj.cmd.unsupported('projectOtherTab'))
  obj.defineKey(obj.cxtMap, {}, 'd', obj.cmd.finder) -- dired-other-tab
  obj.defineKey(obj.cxtMap, {}, 'f', obj.cmd.spotlight) -- find-file-other-tab
  obj.defineKey(obj.cxtMap, {}, 'b', obj.cmd.unsupported('switchToBufferOtherTab'))
  obj.defineKey(obj.cxtMap, {}, 'n', obj.cmd.unsupported('tabDuplicate'))
  obj.defineKey(obj.cxtMap, {}, 'm', obj.cmd.unsupported('tabMove'))

  -- C-x t S-* (ignore by default)
  obj.defineKey(obj.cxtMap, S_, '6', obj.cmd.unsupported('tabDetach'))
  obj.defineKey(obj.cxtMap, S_, 'o', obj.cmd.tabPrevious)
  obj.defineKey(obj.cxtMap, S_, 'g', obj.cmd.unsupported('tabGroup'))
  obj.defineKey(obj.cxtMap, S_, 'n', obj.cmd.unsupported('tabNewTo'))
  obj.defineKey(obj.cxtMap, S_, 'm', obj.cmd.unsupported('tabMoveTo'))

  -- C-x t C-* (ignore by default)
  obj.defineKey(obj.cxtMap, C_, 'r', obj.cmd.spotlight) -- find-file-read-only-other-tab
  obj.defineKey(obj.cxtMap, C_, 'f', obj.cmd.spotlight) -- find-file-other-tab
end

return obj
