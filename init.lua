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

obj.preCommandHook = {}
obj.postCommandHook = {}

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

-- We need to bind allocated watcher unless otherwise it will be garbage-collected.
-- https://github.com/Hammerspoon/hammerspoon/issues/681#issuecomment-178420569
obj.watchers = {}
obj.watchers[#obj.watchers + 1] = hs.application.watcher.new(
  function (app, event)
    if event == hs.application.watcher.activated then
      obj.runHooks(obj.afterFocusChangeHook, app)
    end
  end
):start()

--
-- sendKey
--

obj.lastSentKey = nil

obj.beforeSendHook = {}
obj.afterSendHook = {}

-- Like fs.eventtap.keyStroke but faster
-- https://github.com/Hammerspoon/hammerspoon/issues/1082
function sendKey (mod, char)
  obj.runHooks(obj.beforeSendHook)
  obj.lastSentKey = { mod, char }
  hs.eventtap.event.newKeyEvent(mod, char, true):post()
  hs.eventtap.event.newKeyEvent(mod, char, false):post()
  obj.runHooks(obj.afterSendHook)
end

--
-- Keymap internals
--

-- hs.hotkey can be fired with synthetic keyboard event too,
-- which easily leads to infinite recursion. so implement by our own
-- https://github.com/Hammerspoon/hammerspoon/issues/1230

obj.lastKeyDown = nil

obj.enabled = true

obj.globalMap = {}
obj.overlayMap = nil

obj.MODFLAGS =
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
  local flags = e:rawFlags() & obj.MODFLAGS
  if not map[code] then
    map[code] = {}
  end
  map[code][flags] = { fn, repeatable }
end

local function lookupKey (map, evt)
  local flagsMap = map and map[evt:getKeyCode()]
  return flagsMap and flagsMap[evt:rawFlags() & obj.MODFLAGS]
end

obj.watchers[#obj.watchers + 1] = hs.eventtap.new(
  {hs.eventtap.event.types.keyDown},
  function (evt)
    obj.lastKeyDown = evt:getCharacters(true)
    if not obj.enabled then
      return false
    end
    -- skip synthetic events
    local source = evt:getProperty(hs.eventtap.event.properties.eventSourceUnixProcessID)
    if source > 0 then
      return false
    end
    local entry = lookupKey(obj.overlayMap, evt) or lookupKey(obj.globalMap, evt)
    if not entry then
      return false
    end
    local repeated = evt:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat)
    if repeated == 0 or entry[2] then
      entry[1]()
    end
    return true
  end
):start()

function obj.maybeDisableOverlayMap ()
  if obj.overlayMap then
    obj.overlayMap = nil
    -- hs.alert('Prefix cleared')
  end
end

function obj.enableOverlayMap (map)
  obj.maybeDisableOverlayMap()
  obj.overlayMap = map
end

function obj.disableKeyBindings ()
  obj.enabled = false
end

function obj.enableKeyBindings ()
  obj.enabled = true
end

obj.addHook(obj.afterFocusChangeHook, obj.maybeDisableOverlayMap)
obj.addHook(obj.postCommandHook, obj.maybeDisableOverlayMap)

--
-- Commands
--

obj.cmd = {}
obj.afterChangeHook = {}

--
-- Mark
--

obj.markActive = false

local function maybeResetMark ()
  if obj.markActive then
    hs.alert('Mark disabled')
    obj.markActive = false
  end
end

obj.addHook(obj.afterFocusChangeHook, maybeResetMark)
obj.addHook(obj.afterChangeHook, maybeResetMark)

--
-- cx
--

obj.cxMap = hs.hotkey.modal.new()

function obj.cmd.cx ()
  hs.alert('C-x')
  obj.enableOverlayMap(obj.cxMap)
end

--
-- Digit arguments
--

obj.digitArgumentValue = 0

local function maybeClearDigitArgument ()
  if obj.digitArgumentValue > 0 then
    hs.alert('Digit-argument cleared')
  end
  obj.digitArgumentValue = 0
end

function obj.cmd.digitArgument ()
  local digit = tonumber(obj.lastKeyDown)
  obj.digitArgumentValue = obj.digitArgumentValue * 10 + digit
  hs.alert(obj.digitArgumentValue)
end

obj.addHook(obj.afterFocusChangeHook, maybeClearDigitArgument)
obj.addHook(obj.postCommandHook, maybeClearDigitArgument)

--
-- Keyboard macro
--

obj.kmacroRecording = false
obj.kmacro = {}

obj.addHook(
  obj.afterSendHook,
  function ()
    if obj.kmacroRecording then
      obj.kmacro[#obj.kmacro + 1] = obj.lastSentKey
    end
  end
)

function obj.cmd.kmacroStart ()
  obj.runHooks(obj.preCommandHook)
  obj.kmacroRecording = true
  obj.kmacro = {}
  hs.alert('Macro recording ...')
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.kmacroEnd ()
  obj.runHooks(obj.preCommandHook)
  obj.kmacroRecording = false
  hs.alert('Macro recorded')
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.kmacroCall ()
  obj.runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    for j = 1, #obj.kmacro do
      sendKey(obj.kmacro[j][1], obj.kmacro[j][2])
    end
  end
  obj.runHooks(obj.postCommandHook)
end

--
-- Commands
--

function obj.cmd.setMarkCommand ()
  obj.runHooks(obj.preCommandHook)
  hs.alert('Mark enabled')
  obj.markActive = true
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.keyboardQuit ()
  obj.runHooks(obj.preCommandHook)
  if (not obj.markActive) and (not obj.overlayMap) and obj.digitArgumentValue == 0 then
    -- nothing to clear => just send ESC
    sendKey({}, 'esc')
  elseif obj.markActive then
    hs.alert('Mark disabled')
    obj.markActive = false
  end
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.selfInsertCommand ()
  obj.runHooks(obj.preCommandHook)
  local ch = obj.lastKeyDown
  for i = 1, math.max(1, obj.digitArgumentValue) do
    sendKey({}, ch)
  end
  obj.runHooks(obj.afterChangeHook)
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.backwardChar ()
  obj.runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'left')
    else
      sendKey({}, 'left')
    end
  end
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.forwardChar ()
  obj.runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'right')
    else
      sendKey({}, 'right')
    end
  end
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.previousLine ()
  obj.runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'up')
    else
      sendKey({}, 'up')
    end
  end
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.nextLine ()
  obj.runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'down')
    else
      sendKey({}, 'down')
    end
  end
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.forwardWord ()
  obj.runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift', 'option' }, 'right')
    else
      sendKey({ 'option' }, 'right')
    end
  end
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.backwardWord ()
  obj.runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift', 'option' }, 'left')
    else
      sendKey({ 'option' }, 'left')
    end
  end
  obj.runHooks(obj.postCommandHook)
end

function obj.cmd.saveBuffer ()
  obj.runHooks(obj.preCommandHook)
  sendKey({ 'cmd' }, 's')
  obj.runHooks(obj.postCommandHook)
end

return obj
