-- shared/debug.lua (CLEAN)
-- Optional debug utilities + safe wrappers around common CFX functions.
-- Behaves like the decompiled version but without gotos/labels and with sane naming.

local debugSessions = {}

-- ------------------------------------------------------------
-- Session-based step recording (for "what step did we die on?")
-- ------------------------------------------------------------

---Start a debug session that can record steps (only if Config.ErrorDebug is true).
---@param sessionId string
function StartDebugSession(sessionId)
  if not (Config and Config.ErrorDebug) then return end
  debugSessions[sessionId] = {
    stepCount = 0,
    stepData = {},
  }
end

---Destroy a debug session.
---@param sessionId string
function DestoryDebugSession(sessionId) -- keep misspelling for compatibility
  if not (Config and Config.ErrorDebug) then return end
  debugSessions[sessionId] = nil
end

---Record a step into a session (useful before risky code).
---@param sessionId string
---@param stepName any
function DebugRecordStep(sessionId, stepName)
  if not (Config and Config.ErrorDebug) then return end
  local s = debugSessions[sessionId]
  if not s then return end

  s.stepCount += 1
  s.stepData[s.stepCount] = stepName
end

---Simple printf-style debug logger (only if Config.EnableDebug is true).
---@param fmt string
---@param ... any
function DebugLog(fmt, ...)
  if not (Config and Config.EnableDebug) then return end
  print(string.format(fmt, ...))
end

---Print recorded steps for a given sessionId.
---@param sessionId string
function DisplayCurrentRecordSteps(sessionId)
  local s = debugSessions[sessionId]
  if not s then return end

  for _, stepName in ipairs(s.stepData) do
    print("^0Step name: ^1" .. tostring(stepName))
  end

  print("^5=====^0")
  local last = s.stepData[#s.stepData]
  print("^0Last step before the error: ^1" .. tostring(last))
end

-- ------------------------------------------------------------
-- Table serialization for logs (non-JSON, readable)
-- ------------------------------------------------------------

local function serializeKey(key)
  local t = type(key)
  if t == "number" or t == "boolean" then
    return ("[%s]"):format(tostring(key))
  end
  return ("['%s']"):format(tostring(key))
end

local function serializeValue(value)
  local t = type(value)
  if t == "string" then
    return ("'%s'"):format(tostring(value))
  end
  return tostring(value)
end

---Serializes a Lua table into a readable string (handles nested tables, no cycles protection like original).
---@param root table
---@param silent boolean|nil if true, don't print; just return string
---@return string
local function tableToString(root, silent)
  local stack = { root }
  local indexStack = { nil }
  local indent = 1

  local out = { "{\n" }

  while #stack > 0 do
    local tbl = stack[#stack]
    local lastKey = indexStack[#indexStack]

    -- iterate next key after lastKey
    local nextKey, nextVal = next(tbl, lastKey)
    if nextKey == nil then
      -- close this table
      stack[#stack] = nil
      indexStack[#indexStack] = nil
      indent -= 1

      out[#out + 1] = string.rep("\t", indent) .. "}"
      if #stack > 0 then
        out[#out + 1] = ",\n"
      else
        out[#out + 1] = "\n"
      end
    else
      indexStack[#indexStack] = nextKey

      local keyStr = serializeKey(nextKey)
      local prefix = string.rep("\t", indent) .. keyStr .. " = "

      if type(nextVal) == "table" then
        out[#out + 1] = prefix .. "{\n"
        -- descend
        stack[#stack + 1] = nextVal
        indexStack[#indexStack + 1] = nil
        indent += 1
      else
        out[#out + 1] = prefix .. serializeValue(nextVal)

        -- decide trailing comma by peeking if more keys exist
        local peekK = next(tbl, nextKey)
        if peekK == nil then
          out[#out + 1] = "\n"
        else
          out[#out + 1] = ",\n"
        end
      end
    end
  end

  local result = table.concat(out)
  if not silent then
    print(result)
  end
  return result
end

-- ------------------------------------------------------------
-- Pretty print helper (kept name: tprint)
-- ------------------------------------------------------------

---Recursively print a table with indentation.
---@param value any
---@param indent number|nil
function tprint(value, indent)
  indent = indent or 0

  if type(value) ~= "table" then
    print(value)
    return
  end

  for k, v in pairs(value) do
    local prefix = string.rep("  ", indent) .. tostring(k) .. ": "
    if type(v) == "table" then
      print(prefix)
      tprint(v, indent + 1)
    elseif type(v) == "boolean" then
      print(prefix .. tostring(v))
    else
      print(prefix .. tostring(v))
    end
  end
end

-- ------------------------------------------------------------
-- Safe wrappers (only enabled when Config.ErrorDebug is true)
-- These wrap global functions, run handlers in xpcall, then print
-- steps + arguments on failure.
-- ------------------------------------------------------------

if Config and Config.ErrorDebug then
  local _AddEventHandler = AddEventHandler
  local _RegisterCommand = RegisterCommand
  local _RegisterNetEvent = RegisterNetEvent
  local _RegisterNUICallback = RegisterNUICallback
  local _CreateThread = CreateThread

  local function dumpArgs(args)
    for i, v in pairs(args) do
      print("^0Argument key: ^1" .. tostring(i))
      print("^0Argument value type: ^1" .. type(v))
      print(" ")
      if type(v) == "table" then
        print("^0Argument value: ^1" .. tostring(v))
        tableToString(v, true) -- prints when silent=false; we want just return, so silent=true
        print(tableToString(v, true))
      else
        print("^0Argument value: ^1" .. tostring(v))
      end
      print("^5=====^0")
    end
  end

  local function safeInvoke(kind, name, sessionId, fn, ...)
    local args = { ... }
    local ok, err = xpcall(function()
      fn(table.unpack(args))
    end, debug.traceback)

    if ok then return end

    print("^5=========================^0")
    print(("^2Error in: ^1%s^0"):format(kind))
    print(("^2Event name: ^1%s^0"):format(tostring(name)))
    print("^5=========================^0")
    DisplayCurrentRecordSteps(sessionId or name)
    print("^5=========================^0")
    dumpArgs(args)
    print("^5=========================^0")
    print(err)
    print("^5=========================^0")
  end

  -- Wrap RegisterCommand(name, handler)
  RegisterCommand = function(commandName, handler)
    _RegisterCommand(commandName, function(src, args, raw)
      safeInvoke("RegisterCommand", commandName, commandName, handler, src, args, raw)
    end)
  end

  -- Wrap RegisterNetEvent(name, handler?) - supports usage with handler later via AddEventHandler too
  RegisterNetEvent = function(eventName, handler)
    if handler == nil then
      _RegisterNetEvent(eventName)
      return
    end

    _RegisterNetEvent(eventName, function(...)
      safeInvoke("RegisterNetEvent", eventName, eventName, handler, ...)
    end)
  end

  -- Wrap RegisterNUICallback(name, handler)
  RegisterNUICallback = function(callbackName, handler)
    _RegisterNUICallback(callbackName, function(...)
      safeInvoke("RegisterNUICallback", callbackName, callbackName, handler, ...)
    end)
  end

  -- Wrap CreateThread(fn, sessionName)
  CreateThread = function(fn, sessionName)
    _CreateThread(function()
      local ok, err = xpcall(fn, debug.traceback)
      if ok then return end

      print("=========================")
      print("^2Error in: ^1CreateThread^0")
      print("^1" .. tostring(sessionName or "non defined") .. "^0")
      print("=========================")
      DisplayCurrentRecordSteps(sessionName)
      print("^5=========================^0")
      print(err)
      print("=========================")
    end)
  end

  -- Wrap AddEventHandler(eventName, handler)
  AddEventHandler = function(eventName, handler)
    _AddEventHandler(eventName, function(...)
      safeInvoke("AddEventHandler", eventName, eventName, handler, ...)
    end)
  end

  -- expose serializer (handy in other files)
  _G.tableToString = tableToString
end