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
-- sendKey
--

obj.beforeSendHook = {}
obj.afterSendHook = {}

-- Like fs.eventtap.keyStroke but faster
-- https://github.com/Hammerspoon/hammerspoon/issues/1082
function obj.sendKey (mod, char)
  obj.runHooks(obj.beforeSendHook, { mod, char })
  hs.eventtap.event.newKeyEvent(mod, char, true):post()
  hs.eventtap.event.newKeyEvent(mod, char, false):post()
  obj.runHooks(obj.afterSendHook, { mod, char })
end

--
-- Keymap lookup
--

-- hs.hotkey can be fired with synthetic keyboard event too,
-- which easily leads to infinite recursion. so implement by our own
-- https://github.com/Hammerspoon/hammerspoon/issues/1230

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
  local code = e:getKeyCode()
  local flags = e:rawFlags() & MODFLAGS
  if not map[code] then
    map[code] = {}
  end
  map[code][flags] = { fn, repeatable }
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
  local flagsMap = map and map[evt:getKeyCode()]
  return flagsMap and flagsMap[evt:rawFlags() & MODFLAGS]
end

local function lookupKeyDwim (evt)
  local entry = lookupKey(obj.overlayMap, evt) or lookupKey(obj.globalMap, evt)
  maybeDisableOverlayMap(entry)
  return entry
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
  obj.enabled = false
  obj.runHooks(obj.keybindsDisabledHook)
end

function obj.enableKeyBindings ()
  obj.enabled = true
  obj.runHooks(obj.keybindsEnabledHook)
end

-- digit argument

local nextDigitArgument = 0

function obj.setDigitArgument (val)
  nextDigitArgument = val
end

local function maybeClearDigitArgument ()
  if nextDigitArgument > 0 then
    nextDigitArgument = 0
    hs.alert("Argument cleared")
  end
end

obj.addHook(obj.afterFocusChangeHook, maybeClearDigitArgument)

-- the event loop

obj.preCommandHook = {}
obj.postCommandHook = {}

obj._watchers[#obj._watchers + 1] = hs.eventtap.new(
  {hs.eventtap.event.types.keyDown},
  function (evt)
    if not obj.enabled then
      return false
    end
    -- skip synthetic events
    local source = evt:getProperty(hs.eventtap.event.properties.eventSourceUnixProcessID)
    if source > 0 then
      return false
    end
    local entry = lookupKeyDwim(evt)
    if not entry then
      return false
    end
    local repeated = evt:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat)
    if repeated == 0 or entry[2] then
      local arg = nextDigitArgument
      nextDigitArgument = 0
      obj.runHooks(obj.preCommandHook)
      entry[1](arg, evt:getCharacters(true))
      obj.runHooks(obj.postCommandHook)
    end
    return true
  end
):start()

--
-- Commands
--

obj.cmd = {}
obj.afterChangeHook = {}

-- Mark

obj.markActive = false

local function maybeResetMark ()
  if obj.markActive then
    hs.alert('Mark disabled')
    obj.markActive = false
  end
end

function obj.cmd.setMarkCommand ()
  hs.alert('Mark enabled')
  obj.markActive = true
end

obj.addHook(obj.afterFocusChangeHook, maybeResetMark)
obj.addHook(obj.afterChangeHook, maybeResetMark)

-- Digit arguments

function obj.cmd.digitArgument (arg, key)
  local digit = tonumber(key)
  local val = arg * 10 + digit
  obj.setDigitArgument(val)
  hs.alert(val)
end

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
  obj.afterSendHook,
  function (key)
    if obj.kmacroRecording then
      obj.kmacro[#obj.kmacro + 1] = key
    end
  end
)

function obj.cmd.kmacroStart ()
  obj.kmacroRecording = true
  obj.kmacro = {}
  hs.alert('Macro recording ...')
end

function obj.cmd.kmacroEnd ()
  if obj.kmacroRecording then
    obj.kmacroRecording = false
    hs.alert('Macro recorded')
  end
end

function obj.cmd.kmacroCall (arg)
  for i = 1, math.max(1, arg) do
    for j = 1, #obj.kmacro do
      obj.sendKey(obj.kmacro[j][1], obj.kmacro[j][2])
    end
  end
end

-- kmacro can be defined across applications, except for disabled ones
obj.addHook(obj.keybindsDisabledHook, obj.cmd.kmacroEnd)

-- Others

function obj.cmd.keyboardQuit (arg)
  if (not obj.markActive) and (not obj.overlayMap) and arg == 0 then
    -- nothing to clear => just send ESC
    obj.sendKey({}, 'esc')
  elseif obj.markActive then
    hs.alert('Mark disabled')
    obj.markActive = false
  end
  -- overlayMap and arg will be cleared automatically
end

function obj.cmd.selfInsertCommand (arg, key)
  for i = 1, math.max(1, arg) do
    obj.sendKey({}, key)
  end
  obj.runHooks(obj.afterChangeHook)
end

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

function obj.cmd.saveBuffer ()
  obj.sendKey({ 'cmd' }, 's')
end

return obj
