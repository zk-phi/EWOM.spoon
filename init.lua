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
-- Helper fns
--

-- Like fs.eventtap.keyStroke but faster
-- https://github.com/Hammerspoon/hammerspoon/issues/1082
function myStrokeKey (mod, char)
  hs.eventtap.event.newKeyEvent(mod, char, true):post()
  hs.eventtap.event.newKeyEvent(mod, char, false):post()
end

function obj:addHook (hook, fn)
  hook[#hook + 1] = fn
end

function obj:runHooks (hook, arg)
  for i = 1, #hook do
    hook[i](arg)
  end
end

--
-- afterFocusChangeHook
--

obj.watchers = {}
obj.afterFocusChangeHook = {}

-- We need to bind allocated watcher unless otherwise it will be garbage-collected.
-- https://github.com/Hammerspoon/hammerspoon/issues/681#issuecomment-178420569
obj.watchers[#obj.watchers + 1] = hs.application.watcher.new(
  function (app, event)
    if event == hs.application.watcher.activated then
      obj:runHooks(obj.afterFocusChangeHook, app)
    end
  end
):start()

--
-- globalMap
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

-- auto-disable mark on focus-out
obj:addHook(
  obj.afterFocusChangeHook,
  function ()
    if obj.markActive then
      hs.alert("Mark disabled")
    end
    obj.markActive = false
  end
)

--
-- commands
--

function obj:setMarkCommand ()
  hs.alert("Mark enabled")
  obj.markActive = true
end

function obj:keyboardQuit ()
  if obj.markActive then
    hs.alert("Mark disabled")
    obj.markActive = false
  end
end

function obj:backwardChar ()
  if obj.markActive then
    myStrokeKey({ 'shift' }, 'left')
  else
    myStrokeKey({}, 'left')
  end
end

function obj:forwardChar ()
  if obj.markActive then
    myStrokeKey({ 'shift' }, 'right')
  else
    myStrokeKey({}, 'right')
  end
end

function obj:previousLine ()
  if obj.markActive then
    myStrokeKey({ 'shift' }, 'up')
  else
    myStrokeKey({}, 'up')
  end
end

function obj:nextLine ()
  if obj.markActive then
    myStrokeKey({ 'shift' }, 'down')
  else
    myStrokeKey({}, 'down')
  end
end

function obj:forwardWord ()
  if obj.markActive then
    myStrokeKey({ 'shift', 'option' }, 'right')
  else
    myStrokeKey({ 'option' }, 'right')
  end
end

function obj:backwardWord ()
  if obj.markActive then
    myStrokeKey({ 'shift', 'option' }, 'left')
  else
    myStrokeKey({ 'option' }, 'left')
  end
end

return obj
