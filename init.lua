local obj = {};

--
-- Metadata
--

obj.name = "EWOM Spoon"
obj.version = "0.1"
obj.author = "zk-phi"
obj.license = "MIT"
obj.homepage = "https://github.com/zk-phi/dotfiles"

--
-- Hooks
--

obj.preCommandHook = {}
obj.postCommandHook = {}
obj.afterChangeHook = {}

obj.beforeSendHook = {}
obj.afterSendHook = {}

obj.afterFocusChangeHook = {}

function obj:addHook (hook, fn)
  hook[#hook + 1] = fn
end

function obj:runHooks (hook, arg)
  for i = 1, #hook do
    hook[i](arg)
  end
end

-- Like fs.eventtap.keyStroke but faster
-- https://github.com/Hammerspoon/hammerspoon/issues/1082
function sendKey (mod, char)
  obj:runHooks(obj.beforeSendHook)
  hs.eventtap.event.newKeyEvent(mod, char, true):post()
  hs.eventtap.event.newKeyEvent(mod, char, false):post()
  obj:runHooks(obj.afterSendHook)
end

-- We need to bind allocated watcher unless otherwise it will be garbage-collected.
-- https://github.com/Hammerspoon/hammerspoon/issues/681#issuecomment-178420569
obj.watchers = {}
obj.watchers[#obj.watchers + 1] = hs.application.watcher.new(
  function (app, event)
    if event == hs.application.watcher.activated then
      obj:runHooks(obj.afterFocusChangeHook, app)
    end
  end
):start()

--
-- lastKeyDown
--

obj.lastKeyDown = nil

obj.watchers[#obj.watchers + 1] = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown },
  function (evt)
    obj.lastKeyDown = evt:getCharacters(true)
    return false
  end
):start()

--
-- Keymap internals
--

obj.globalMap = hs.hotkey.modal.new()

function obj:bindKey (map, mod, char, fn, repeated)
  map:bind(mod, char, fn, nil, repeated and fn or nil)
end

local function disableAllBindings ()
  obj.globalMap:exit()
end

local function enableAllBindings ()
  obj.globalMap:enter()
end

function obj:setFilter (filterFn)
  obj:addHook(
    obj.afterFocusChangeHook,
    function (app)
      if filterFn(app) then
        disableAllBindings()
      else
        enableAllBindings()
      end
    end
  )
end

--
-- Mark
--

obj.markActive = false

local function maybeResetMark ()
  if obj.markActive then
    hs.alert("Mark disabled")
    obj.markActive = false
  end
end

-- auto-disable mark on focus-out
obj:addHook(obj.afterFocusChangeHook, maybeResetMark)
-- auto-disable after change
obj:addHook(obj.afterChangeHook, maybeResetMark)

--
-- Digit arguments
--

obj.digitArgumentValue = 0
obj:addHook(
  obj.postCommandHook,
  function ()
    if obj.digitArgumentValue > 0 then
      hs.alert("Digit-argument cleared")
    end
    obj.digitArgumentValue = 0
  end
)

function obj:digitArgument ()
  local digit = tonumber(obj.lastKeyDown)
  obj.digitArgumentValue = obj.digitArgumentValue * 10 + digit
  hs.alert(obj.digitArgumentValue)
end

--
-- Commands
--

function obj:setMarkCommand ()
  obj:runHooks(obj.preCommandHook)
  hs.alert("Mark enabled")
  obj.markActive = true
  obj:runHooks(obj.postCommandHook)
end

function obj:keyboardQuit ()
  obj:runHooks(obj.preCommandHook)
  if obj.markActive then
    hs.alert("Mark disabled")
    obj.markActive = false
  end
  obj:runHooks(obj.postCommandHook)
end

function obj:backwardChar ()
  obj:runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'left')
    else
      sendKey({}, 'left')
    end
  end
  obj:runHooks(obj.postCommandHook)
end

function obj:forwardChar ()
  obj:runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'right')
    else
      sendKey({}, 'right')
    end
  end
  obj:runHooks(obj.postCommandHook)
end

function obj:previousLine ()
  obj:runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'up')
    else
      sendKey({}, 'up')
    end
  end
  obj:runHooks(obj.postCommandHook)
end

function obj:nextLine ()
  obj:runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift' }, 'down')
    else
      sendKey({}, 'down')
    end
  end
  obj:runHooks(obj.postCommandHook)
end

function obj:forwardWord ()
  obj:runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift', 'option' }, 'right')
    else
      sendKey({ 'option' }, 'right')
    end
  end
  obj:runHooks(obj.postCommandHook)
end

function obj:backwardWord ()
  obj:runHooks(obj.preCommandHook)
  for i = 1, math.max(1, obj.digitArgumentValue) do
    if obj.markActive then
      sendKey({ 'shift', 'option' }, 'left')
    else
      sendKey({ 'option' }, 'left')
    end
  end
  obj:runHooks(obj.postCommandHook)
end

return obj
