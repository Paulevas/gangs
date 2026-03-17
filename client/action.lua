-- client/actions_refactored.lua
-- Refactor of the decompiled “SHX…” chunk:
-- - No goto/labels
-- - Meaningful names
-- - Consolidated duplicated patterns
-- - 2-space indentation, readable flow
-- - Keeps the same public function names used elsewhere in the resource

-- ============================================================================
-- Aliases / external deps (expected to exist in your resource)
-- ============================================================================
local Menu = Menu
local L = Locale
local Config = Config

-- Optional externals referenced by the original code:
--   Framework (ShowNotification, IsPlayerDead, ActionsOnBlindfold, ActionsOnRestrain)
--   Inventory (OpenPlayerInventory)
--   Gang (leader, access["actions.perform"])
--   TargetEntity (entity, optionsOrNames, isAdd)
--   Intervals (table with .action/.entity timestamps)
--   ShapeTestCameraToRay (optional helper to raycast from camera)

-- ============================================================================
-- Native caches
-- ============================================================================
local Wait = Wait
local CreateThread = CreateThread
local SetTimeout = Citizen.SetTimeout

local PlayerPedId = PlayerPedId
local PlayerId = PlayerId
local GetGameTimer = GetGameTimer

local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local DoesEntityExist = DoesEntityExist
local IsEntityAVehicle = IsEntityAVehicle
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local NetworkGetEntityFromNetworkId = NetworkGetEntityFromNetworkId
local NetworkIsPlayerActive = NetworkIsPlayerActive
local NetworkGetPlayerIndexFromPed = NetworkGetPlayerIndexFromPed

local GetPlayerServerId = GetPlayerServerId
local GetPlayerFromServerId = GetPlayerFromServerId
local GetPlayerPed = GetPlayerPed

local GetVehiclePedIsIn = GetVehiclePedIsIn
local IsPedInAnyVehicle = IsPedInAnyVehicle
local GetPedInVehicleSeat = GetPedInVehicleSeat
local IsVehicleSeatFree = IsVehicleSeatFree
local GetEntityModel = GetEntityModel
local GetVehicleModelNumberOfSeats = GetVehicleModelNumberOfSeats

local AttachEntityToEntity = AttachEntityToEntity
local DetachEntity = DetachEntity
local GetPedBoneIndex = GetPedBoneIndex
local GetPedBoneCoords = GetPedBoneCoords
local SetEntityCollision = SetEntityCollision

local DisableControlAction = DisableControlAction
local DisplayRadar = DisplayRadar
local DrawSprite = DrawSprite
local HasStreamedTextureDictLoaded = HasStreamedTextureDictLoaded
local RequestStreamedTextureDict = RequestStreamedTextureDict

local RequestModel = RequestModel
local HasModelLoaded = HasModelLoaded
local CreateObject = CreateObject
local DeleteEntity = DeleteEntity

local RequestAnimDict = RequestAnimDict
local HasAnimDictLoaded = HasAnimDictLoaded
local IsEntityPlayingAnim = IsEntityPlayingAnim
local TaskPlayAnim = TaskPlayAnim
local TaskEnterVehicle = TaskEnterVehicle
local TaskLeaveVehicle = TaskLeaveVehicle
local ClearPedTasks = ClearPedTasks
local SetVehicleDoorOpen = SetVehicleDoorOpen
local SetVehicleDoorShut = SetVehicleDoorShut

local TriggerServerEvent = TriggerServerEvent
local RegisterNetEvent = RegisterNetEvent
local AddEventHandler = AddEventHandler
local TriggerEvent = TriggerEvent

local IsPedRagdoll = IsPedRagdoll
local IsPlayerDead = IsPlayerDead
local SetEnableHandcuffs = SetEnableHandcuffs
local SetCurrentPedWeapon = SetCurrentPedWeapon

-- ============================================================================
-- Small helpers
-- ============================================================================
local function notify(msg)
  if Framework and Framework.ShowNotification then
    Framework.ShowNotification(msg)
  end
end

local function isFrameworkDead()
  return Framework and Framework.IsPlayerDead and Framework.IsPlayerDead() or false
end

local function dist(a, b)
  if glm and glm.distance then return glm.distance(a, b) end
  return #(a - b)
end

local function ensureAnimDict(dict)
  if HasAnimDictLoaded(dict) then return true end
  RequestAnimDict(dict)
  local timeout = GetGameTimer() + 2000
  while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
    Wait(10)
  end
  return HasAnimDictLoaded(dict)
end

local function ensureModel(model)
  if HasModelLoaded(model) then return true end
  RequestModel(model)
  local timeout = GetGameTimer() + 2000
  while not HasModelLoaded(model) and GetGameTimer() < timeout do
    Wait(10)
  end
  return HasModelLoaded(model)
end

local function normalizeTarget(dataOrEntity)
  if type(dataOrEntity) == "number" then
    return { entity = dataOrEntity }
  end
  return dataOrEntity
end

local function getServerIdFromPed(ped)
  local playerIndex = NetworkGetPlayerIndexFromPed(ped)
  if playerIndex == nil or playerIndex == -1 then return nil end
  return GetPlayerServerId(playerIndex)
end

local function hasActionsAccess()
  if not Gang then return false end
  if Gang.leader then return true end
  return Gang.access and Gang.access["actions.perform"] and true or false
end

-- ============================================================================
-- Constants (models, offsets)
-- ============================================================================
local BAG_MODEL = 1463127915      -- paper bag prop
local CUFF_MODEL = 623548567     -- zip tie / cuffs prop

-- Bag prop: attach to head-ish bone
local BAG_BONE = 12844
-- Cuff prop: attach to hand-ish bone
local CUFF_BONE = 60309

-- Offsets: { x, y, z, rx, ry, rz }
local BAG_OFFSET = { 0.232, 0.0, 0.0, 0.0, -90.0, 0.0 }
local CUFF_OFFSET = { -0.022, 0.058, -0.004, 0.0, 0.0, -90.0 }

-- ============================================================================
-- Runtime state (replacing SHX* variables)
-- ============================================================================
local bagPropByServerId = {}     -- [serverId] = object entity (bag)
local cuffPropByServerId = {}    -- [serverId] = object entity (cuffs)
local escortedStateByServerId = {} -- [serverId] = boolean (escorted)

local vehicleRestrainedCache = {} -- [vehicleEntity] = restrained ped entity cached for TRANSPORT_OFF

local isBlindfolded = false
local isRestrained = false
local isTransported = false

local escortingTargetIndex = -1  -- when YOU escort someone: player index of the target
local escortedByIndex = -1       -- when YOU are escorted: player index of the escorter

local restrainCooldown = false

-- Dynamic per-target option caches used by TargetActions()
local targetOptionCache = {}     -- [pedEntity] = { [optionName]=optionTable }
local targetRegistered = {}      -- [pedEntity] = true/false

-- ============================================================================
-- ox_target / qb-target option factories
-- ============================================================================
local globalPlayerOptions = {}
local globalVehicleOptions = {}

-- Create a mapping of option names to option objects for quick lookup
local optionNameToObject = {}

local function makeClientOption(name, label, icon, onSelect, canInteract)
  local option = {
    type = "client",
    name = name,
    label = label,
    icon = icon,
    onSelect = onSelect,
    canInteract = canInteract,
    distance = 6.0
  }
  optionNameToObject[name] = option
  return option
end

-- ============================================================================
-- Public query helpers (kept same names as original)
-- ============================================================================
function IsPlayerBagged(serverId)
  local obj = bagPropByServerId[serverId]
  return obj ~= nil and DoesEntityExist(obj)
end

function IsPlayerRestrained(serverId)
  local obj = cuffPropByServerId[serverId]
  return obj ~= nil and DoesEntityExist(obj)
end

function IsPlayerEscorted(serverId)
  return escortedStateByServerId[serverId] == true
end

function IsPlayerRestrictedBySomeAction()
  return isBlindfolded or isRestrained or isTransported
end

function DoesPlayerHaveAccessToActions()
  return hasActionsAccess()
end

-- ============================================================================
-- Vehicle helper (kept same name as original)
-- ============================================================================
function GetRestrainedPlayerFromVehicle(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end

  local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
  -- seat indices: -1 (driver), 0..(seats-2)
  for seat = -1, (seats - 2) do
    if not IsVehicleSeatFree(vehicle, seat) then
      local ped = GetPedInVehicleSeat(vehicle, seat)
      if ped and ped ~= 0 then
        local sid = getServerIdFromPed(ped)
        if sid and IsPlayerRestrained(sid) then
          vehicleRestrainedCache[vehicle] = ped
          return ped
        end
      end
    end
  end

  return 0
end

local function areAnyVehicleSeatsFree(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
  local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
  for seat = -1, (seats - 2) do
    if IsVehicleSeatFree(vehicle, seat) then
      return true
    end
  end
  return false
end

-- ============================================================================
-- Core action executors (kept same names as original)
-- ============================================================================
function RobPlayer(targetPlayerIndex, targetPed)
  local myPed = PlayerPedId()
  local myPos = GetEntityCoords(myPed)
  local targetPos = GetEntityCoords(targetPed)

  if dist(myPos, targetPos) > 2.0 then
    notify(L.ACTIONS_TARGET_AWAY)
    return
  end

  if Inventory and Inventory.OpenPlayerInventory then
    Inventory.OpenPlayerInventory(targetPlayerIndex)
  end

  local serverId = GetPlayerServerId(targetPlayerIndex)
  TriggerServerEvent("rcore_gangs:server:rob", serverId)
end

function BagPlayer(targetPlayerIndex, targetPed, enabled)
  local myPed = PlayerPedId()
  local myPos = GetEntityCoords(myPed)
  local targetPos = GetEntityCoords(targetPed)

  if dist(myPos, targetPos) > 2.0 then
    notify(L.ACTIONS_TARGET_AWAY)
    return
  end

  TriggerServerEvent("rcore_gangs:server:bag", GetPlayerServerId(targetPlayerIndex), enabled == true)
end

function StartRestrainCooldown()
  restrainCooldown = true
  SetTimeout(1000, function()
    restrainCooldown = false
  end)
end

function RestrainPlayer(targetPlayerIndex, targetPed, enabled)
  if restrainCooldown then
    notify(L.ACTION_TARGET_RESTRAIN_COOLDOWN)
    return
  end

  local myPed = PlayerPedId()
  local myPos = GetEntityCoords(myPed)
  local myHeading = GetEntityHeading(myPed)

  local targetPos = GetEntityCoords(targetPed)
  local targetHeading = GetEntityHeading(targetPed)

  if dist(myPos, targetPos) > 2.0 then
    notify(L.ACTIONS_TARGET_AWAY)
    return
  end

  -- Facing check (ported from decompiled math)
  local diff = math.abs(((myHeading - targetHeading) % 360) - 180)
  local facingScore = 180 - diff
  if facingScore > 60.0 then
    notify(L.ACTIONS_TARGET_FACING)
    return
  end

  StartRestrainCooldown()
  TriggerServerEvent("rcore_gangs:server:restrain", GetPlayerServerId(targetPlayerIndex), enabled == true)
end

function EscortPlayer(targetPlayerIndex, targetPed, enabled)
  local myPed = PlayerPedId()
  local myPos = GetEntityCoords(myPed)
  local targetPos = GetEntityCoords(targetPed)

  if dist(myPos, targetPos) > 2.0 then
    notify(L.ACTIONS_TARGET_AWAY)
    return
  end

  TriggerServerEvent("rcore_gangs:server:escort", GetPlayerServerId(targetPlayerIndex), enabled == true)
end

local function findNearbyNetworkedVehicle(targetPos)
  -- Try raycast helper first (if your resource provides it)
  if ShapeTestCameraToRay then
    local hitEntity = ShapeTestCameraToRay(8, 2, nil)
    if hitEntity and hitEntity ~= 0 and DoesEntityExist(hitEntity) then
      if IsEntityAVehicle(hitEntity) and NetworkGetEntityIsNetworked(hitEntity) then
        return hitEntity
      end
    end
  end

  -- Fallback: nearest within 5m
  local pool = GetGamePool("CVehicle")
  local bestVeh, bestDist = 0, 999999.0
  for i = 1, #pool do
    local veh = pool[i]
    if veh and DoesEntityExist(veh) then
      local d = dist(targetPos, GetEntityCoords(veh))
      if d < 5.0 and d < bestDist and NetworkGetEntityIsNetworked(veh) then
        bestVeh, bestDist = veh, d
      end
    end
  end

  return bestVeh
end

function TransportPlayer(targetPlayerIndex, targetPed, enabled)
  local myPed = PlayerPedId()
  local myPos = GetEntityCoords(myPed)
  local targetPos = GetEntityCoords(targetPed)

  if dist(myPos, targetPos) > 5.0 then
    notify(L.ACTIONS_TARGET_AWAY)
    return
  end

  local serverId = GetPlayerServerId(targetPlayerIndex)

  if enabled then
    local veh = findNearbyNetworkedVehicle(targetPos)
    if not veh or veh == 0 then
      notify(L.ACTIONS_VEHICLE_AWAY)
      return
    end

    if not areAnyVehicleSeatsFree(veh) then
      notify(L.ACTIONS_VEHICLE_FULL)
      return
    end

    TriggerServerEvent("rcore_gangs:server:transport", serverId, NetworkGetNetworkIdFromEntity(veh), true)
    return
  end

  -- Disable transport: use the vehicle target is currently in
  local veh = GetVehiclePedIsIn(targetPed)
  if not veh or veh == 0 then
    notify(L.ACTIONS_VEHICLE_AWAY)
    return
  end

  TriggerServerEvent("rcore_gangs:server:transport", serverId, NetworkGetNetworkIdFromEntity(veh), false)
end

-- ============================================================================
-- Build global target options (ox_target/qb-target)
-- ============================================================================
do
  -- ESCORT ON
  table.insert(globalPlayerOptions, makeClientOption(
    "ESCORT_ON",
    L.MENU_ACTIONS_ESCORT_ON,
    Config.GangOptions.escortIcon,
    function(data)
      data = normalizeTarget(data)
      local ped = data.entity
      local playerIndex = NetworkGetPlayerIndexFromPed(ped)
      EscortPlayer(playerIndex, ped, true)
    end,
    function(ped)
      local sid = getServerIdFromPed(ped)
      if not sid then return false end
      if not IsPlayerRestrained(sid) then return false end
      if IsPlayerEscorted(sid) then return false end
      if not Gang then return false end
      if isFrameworkDead() then return false end
      return true
    end
  ))

  -- ESCORT OFF
  table.insert(globalPlayerOptions, makeClientOption(
    "ESCORT_OFF",
    L.MENU_ACTIONS_ESCORT_OFF,
    Config.GangOptions.escortIcon,
    function(data)
      data = normalizeTarget(data)
      local ped = data.entity
      local playerIndex = NetworkGetPlayerIndexFromPed(ped)
      EscortPlayer(playerIndex, ped, false)
    end,
    function(ped)
      local sid = getServerIdFromPed(ped)
      if not sid then return false end
      if not IsPlayerRestrained(sid) then return false end
      if not IsPlayerEscorted(sid) then return false end
      if not Gang then return false end
      if isFrameworkDead() then return false end
      return true
    end
  ))

  -- TRANSPORT ON
  table.insert(globalPlayerOptions, makeClientOption(
    "TRANSPORT_ON",
    L.MENU_ACTIONS_TRANSPORT_ON,
    Config.GangOptions.transportIcon,
    function(data)
      data = normalizeTarget(data)
      local ped = data.entity
      local playerIndex = NetworkGetPlayerIndexFromPed(ped)
      TransportPlayer(playerIndex, ped, true)
    end,
    function(ped)
      local sid = getServerIdFromPed(ped)
      if not sid then return false end
      if not IsPlayerRestrained(sid) then return false end
      if Gang and isFrameworkDead() then return false end
      return true
    end
  ))

  -- TRANSPORT OFF (vehicle option)
  table.insert(globalVehicleOptions, {
    type = "client",
    name = "TRANSPORT_OFF",
    label = L.MENU_ACTIONS_TRANSPORT_OFF,
    icon = Config.GangOptions.transportIcon,
    distance = 6.0,
    onSelect = function(data)
      data = normalizeTarget(data)
      local vehicle = data.entity
      local restrainedPed = vehicleRestrainedCache[vehicle] or GetRestrainedPlayerFromVehicle(vehicle)
      if restrainedPed and restrainedPed ~= 0 then
        vehicleRestrainedCache[vehicle] = nil
        local playerIndex = NetworkGetPlayerIndexFromPed(restrainedPed)
        TransportPlayer(playerIndex, restrainedPed, false)
      end
    end,
    canInteract = function(vehicle)
      return GetRestrainedPlayerFromVehicle(vehicle) ~= 0
    end
  })

  -- Kidnapping options (blindfold + restrain) appended if enabled
  if Config.GangOptions.kidnapping then
    table.insert(globalPlayerOptions, makeClientOption(
      "BLINDFOLD_ON",
      L.MENU_ACTIONS_BAG_ON,
      Config.GangOptions.blindfoldIcon,
      function(data)
        data = normalizeTarget(data)
        local ped = data.entity
        local playerIndex = NetworkGetPlayerIndexFromPed(ped)
        BagPlayer(playerIndex, ped, true)
      end,
      function(ped)
        local sid = getServerIdFromPed(ped)
        if not sid then return false end
        if IsPlayerBagged(sid) then return false end
        if not hasActionsAccess() then return false end
        if isFrameworkDead() then return false end
        return true
      end
    ))

    table.insert(globalPlayerOptions, makeClientOption(
      "BLINDFOLD_OFF",
      L.MENU_ACTIONS_BAG_OFF,
      Config.GangOptions.blindfoldIcon,
      function(data)
        data = normalizeTarget(data)
        local ped = data.entity
        local playerIndex = NetworkGetPlayerIndexFromPed(ped)
        BagPlayer(playerIndex, ped, false)
      end,
      function(ped)
        local sid = getServerIdFromPed(ped)
        if not sid then return false end
        if not IsPlayerBagged(sid) then return false end
        if not hasActionsAccess() then return false end
        if isFrameworkDead() then return false end
        return true
      end
    ))

    table.insert(globalPlayerOptions, makeClientOption(
      "RESTRAIN_ON",
      L.MENU_ACTIONS_TIE_ON,
      Config.GangOptions.restrainIcon,
      function(data)
        data = normalizeTarget(data)
        local ped = data.entity
        local playerIndex = NetworkGetPlayerIndexFromPed(ped)
        RestrainPlayer(playerIndex, ped, true)
      end,
      function(ped)
        local sid = getServerIdFromPed(ped)
        if not sid then return false end
        if IsPlayerRestrained(sid) then return false end
        if not hasActionsAccess() then return false end
        if isFrameworkDead() then return false end
        return true
      end
    ))

    table.insert(globalPlayerOptions, makeClientOption(
      "RESTRAIN_OFF",
      L.MENU_ACTIONS_TIE_OFF,
      Config.GangOptions.restrainIcon,
      function(data)
        data = normalizeTarget(data)
        local ped = data.entity
        local playerIndex = NetworkGetPlayerIndexFromPed(ped)
        RestrainPlayer(playerIndex, ped, false)
      end,
      function(ped)
        local sid = getServerIdFromPed(ped)
        if not sid then return false end
        if not IsPlayerRestrained(sid) then return false end
        if not hasActionsAccess() then return false end
        if isFrameworkDead() then return false end
        return true
      end
    ))
  end

  -- Robbing option appended if enabled
  if Config.GangOptions.robbing then
    table.insert(globalPlayerOptions, makeClientOption(
      "SEARCH",
      L.MENU_ACTIONS_ROB,
      Config.GangOptions.robIcon,
      function(data)
        data = normalizeTarget(data)
        local ped = data.entity
        local playerIndex = NetworkGetPlayerIndexFromPed(ped)
        RobPlayer(playerIndex, ped)
      end,
      function(ped)
        if not Gang then return false end
        if isFrameworkDead() then return false end

        local sid = getServerIdFromPed(ped)
        if not sid then return false end

        if not IsPlayerRestrained(sid) then return false end
        if IsPlayerEscorted(sid) then return false end
        if GetVehiclePedIsIn(ped) ~= 0 then return false end

        return true
      end
    ))
  end
end

-- ============================================================================
-- Register global target options
-- ============================================================================
CreateThread(function()
  if not Config.TargetOptions.enableActions then return end

  local oxState = GetResourceState("ox_target")
  if oxState == "starting" or oxState == "started" then
    exports.ox_target:addGlobalPlayer(globalPlayerOptions)
    exports.ox_target:addGlobalVehicle(globalVehicleOptions)
    return
  end

  local qbState = GetResourceState("qb-target")
  if qbState == "starting" or qbState == "started" then
    -- qb-target uses `action` instead of `onSelect`
    for _, opt in pairs(globalPlayerOptions) do
      opt.action = opt.onSelect
    end
    for _, opt in pairs(globalVehicleOptions) do
      opt.action = opt.onSelect
    end

    exports["qb-target"]:AddGlobalPlayer({ options = globalPlayerOptions })
    exports["qb-target"]:AddGlobalVehicle({ options = globalVehicleOptions })
  end
end)

CreateThread(function()
  -- Original behavior: if TargetEntity function doesn't exist, disable enableActions
  if not TargetEntity then
    Config.TargetOptions.enableActions = false
  end
end)

-- ============================================================================
-- Tick: local player restrictions/attachments (kept name: Actions)
-- ============================================================================
local DISABLE_WHEN_RESTRAINED = {
  24, 25, 68, 69, 70, 91, 92, 114, 140, 141, 142, 143,
  257, 263, 264, 331, 345, 346, 347,
  22, 21, 36, 44, 45, 47, 58, 23, 75, 63, 64, 71, 72, 288, 289
}

function Actions()
  local now = GetGameTimer()

  -- If nothing active, throttle like the original did
  if not isBlindfolded and not isRestrained and escortingTargetIndex == -1 and escortedByIndex == -1 and not isTransported then
    if Intervals then Intervals.action = now + 1000 end
    return
  end

  local myPed = PlayerPedId()

  -- Blindfolded: hide radar, draw overlay, close menu, and auto-unbag on death
  if isBlindfolded then
    DisableControlAction(0, 199, true) -- pause menu
    DisableControlAction(0, 200, true) -- pause menu
    if Menu and Menu.CloseMenu then Menu.CloseMenu() end

    if HasStreamedTextureDictLoaded("prop_ld_paper_bag") then
      DrawSprite("prop_ld_paper_bag", "prop_paper_bag_2", 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
    else
      RequestStreamedTextureDict("prop_ld_paper_bag")
    end

    if isFrameworkDead() then
      if Intervals then Intervals.action = now + 1000 end
      TriggerServerEvent("rcore_gangs:server:bag", GetPlayerServerId(PlayerId()), false)
    end
  end

  -- Restrained: heavy control disable + looping anim (sit/idle based on transport)
  if isRestrained then
    for i = 1, #DISABLE_WHEN_RESTRAINED do
      DisableControlAction(0, DISABLE_WHEN_RESTRAINED[i], true)
    end
    if Menu and Menu.CloseMenu then Menu.CloseMenu() end

    local animDict = "mp_arresting"
    local animName = isTransported and "sit" or "idle"
    if ensureAnimDict(animDict) and not IsEntityPlayingAnim(myPed, animDict, animName, 3) and not restrainCooldown then
      StartRestrainCooldown()
      TaskPlayAnim(myPed, animDict, animName, 8.0, 8.0, -1, 49, 0, false, false, false)
    end

    if isFrameworkDead() then
      if Intervals then Intervals.action = now + 1000 end
      TriggerServerEvent("rcore_gangs:server:restrain", GetPlayerServerId(PlayerId()), false)
    end
  end

  -- YOU are escorting someone (keep attachment stable + break on death)
  if escortingTargetIndex ~= -1 and NetworkIsPlayerActive(escortingTargetIndex) then
    local targetPed = GetPlayerPed(escortingTargetIndex)

    if ensureAnimDict("anim@heists@box_carry@") and not IsEntityPlayingAnim(myPed, "anim@heists@box_carry@", "idle", 3) then
      TaskPlayAnim(myPed, "anim@heists@box_carry@", "idle", 8.0, 8.0, -1, 49, 0, false, false, false)
    end

    if DoesEntityExist(targetPed) then
      -- Attach target to you (fixed: bone index belongs to the parent entity)
      AttachEntityToEntity(
        targetPed, myPed, GetPedBoneIndex(myPed, 28422),
        0.0, -0.3, -0.25, -15.0, 0.0, 180.0,
        true, false, true, true, 0, true
      )

      local targetDead = isFrameworkDead() == false and IsPlayerDead(escortingTargetIndex) or isFrameworkDead()
      if targetDead then
        if Intervals then Intervals.action = now + 1000 end
        TriggerServerEvent("rcore_gangs:server:escort", GetPlayerServerId(escortingTargetIndex), false)
        ClearPedTasks(myPed)
        DetachEntity(targetPed, true, false)
      end
    end
  else
    escortingTargetIndex = -1
  end

  -- YOU are being escorted (attach yourself to escorter, lock movement, break on death)
  if escortedByIndex ~= -1 and NetworkIsPlayerActive(escortedByIndex) then
    DisableControlAction(0, 32, true)
    DisableControlAction(0, 33, true)
    DisableControlAction(0, 34, true)
    DisableControlAction(0, 35, true)

    local escorterPed = GetPlayerPed(escortedByIndex)
    if DoesEntityExist(escorterPed) then
      AttachEntityToEntity(
        myPed, escorterPed, GetPedBoneIndex(escorterPed, 28422),
        0.0, -0.3, -0.25, -15.0, 0.0, 180.0,
        true, false, true, true, 0, true
      )
    end

    local dead = isFrameworkDead() or IsPlayerDead(PlayerId())
    if dead then
      if Intervals then Intervals.action = now + 1000 end
      ClearPedTasks(escorterPed)
      DetachEntity(myPed, true, false)
    end
  else
    escortedByIndex = -1
  end

  -- Transported state sanity: if not in vehicle, drop transport flag
  if isTransported then
    if not IsPedInAnyVehicle(myPed) or isFrameworkDead() then
      isTransported = false
    end
  end
end

-- ============================================================================
-- Tick: ensure remote props exist/attach (kept name: ActionsEntities)
-- ============================================================================
local function ensureAttachedProp(map, serverId, playerIndex, model, boneId, offset)
  local ped = GetPlayerPed(playerIndex)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return end

  local prop = map[serverId]
  if prop and DoesEntityExist(prop) then
    return
  end

  if not ensureModel(model) then return end

  local spawnPos = GetPedBoneCoords(ped, boneId, 0.0, 0.0, 0.0)
  local obj = CreateObject(model, spawnPos, false, false, false)

  map[serverId] = obj
  SetEntityCollision(obj, false, false)
  AttachEntityToEntity(
    obj, ped, GetPedBoneIndex(ped, boneId),
    offset[1], offset[2], offset[3],
    offset[4], offset[5], offset[6],
    true, false, false, true, 0, true
  )
end

local function cleanupProp(map, serverId)
  local obj = map[serverId]
  if obj and DoesEntityExist(obj) then
    DeleteEntity(obj)
  end
  map[serverId] = nil
end

function ActionsEntities()
  if Intervals then Intervals.entity = GetGameTimer() + 5000 end

  -- Reuse playerIndex cache for this tick
  local playerIndexCache = {}

  -- Cuffs
  for serverId, prop in pairs(cuffPropByServerId) do
    local playerIndex = playerIndexCache[serverId]
    if playerIndex == nil then
      playerIndex = GetPlayerFromServerId(serverId)
      playerIndexCache[serverId] = playerIndex
    end

    if not NetworkIsPlayerActive(playerIndex) then
      cleanupProp(cuffPropByServerId, serverId)
    else
      ensureAttachedProp(cuffPropByServerId, serverId, playerIndex, CUFF_MODEL, CUFF_BONE, CUFF_OFFSET)
    end
  end

  -- Bags
  for serverId, prop in pairs(bagPropByServerId) do
    local playerIndex = playerIndexCache[serverId]
    if playerIndex == nil then
      playerIndex = GetPlayerFromServerId(serverId)
      playerIndexCache[serverId] = playerIndex
    end

    if not NetworkIsPlayerActive(playerIndex) then
      cleanupProp(bagPropByServerId, serverId)
    else
      ensureAttachedProp(bagPropByServerId, serverId, playerIndex, BAG_MODEL, BAG_BONE, BAG_OFFSET)
    end
  end
end

-- ============================================================================
-- Dynamic “TargetActions” (kept name) - no goto/labels
-- NOTE: This remains compatible with your existing TargetEntity() API.
-- ============================================================================
function TargetActions(targetPed, shouldEnable)
  if not Config.TargetOptions.enableActions then return end
  if not Config.GangOptions.kidnapping then return end

  -- No access: remove any dynamic target registration we added
  if not hasActionsAccess() then
    if targetRegistered[targetPed] then
      targetRegistered[targetPed] = nil
      targetOptionCache[targetPed] = nil
      TargetEntity(targetPed, nil, false)
    end
    return
  end

  -- If target is ragdoll/dead, remove dynamic target options
  if IsPedRagdoll(targetPed) then
    if targetRegistered[targetPed] then
      targetRegistered[targetPed] = nil
      targetOptionCache[targetPed] = nil
      TargetEntity(targetPed, nil, false)
    end
    return
  end

  local playerIndex = NetworkGetPlayerIndexFromPed(targetPed)
  if playerIndex == -1 then
    if targetRegistered[targetPed] then
      targetRegistered[targetPed] = nil
      targetOptionCache[targetPed] = nil
      TargetEntity(targetPed, nil, false)
    end
    return
  end

  if IsPlayerDead(playerIndex) then
    if targetRegistered[targetPed] then
      targetRegistered[targetPed] = nil
      targetOptionCache[targetPed] = nil
      TargetEntity(targetPed, nil, false)
    end
    return
  end

  if not shouldEnable then
    targetRegistered[targetPed] = nil
    targetOptionCache[targetPed] = nil
    TargetEntity(targetPed, nil, false)
    return
  end

  local serverId = GetPlayerServerId(playerIndex)
  local inVehicle = IsPedInAnyVehicle(targetPed)
  local bagged = IsPlayerBagged(serverId)
  local restrained = IsPlayerRestrained(serverId)

  targetOptionCache[targetPed] = targetOptionCache[targetPed] or {}
  local toAdd = {}

  -- Build the minimal set you want dynamically. (Your global target options already exist;
  -- this is only for the “TargetEntity” path used in the decompiled file.)
  if restrained then
    -- restrained: allow SEARCH (if enabled), RESTRAIN_OFF, TRANSPORT_ON, ESCORT_ON
    if Config.GangOptions.robbing and not inVehicle and not IsPlayerEscorted(serverId) and not targetOptionCache[targetPed].SEARCH then
      table.insert(toAdd, "SEARCH")
      targetOptionCache[targetPed].SEARCH = true
    end
    if not targetOptionCache[targetPed].RESTRAIN_OFF then
      table.insert(toAdd, "RESTRAIN_OFF")
      targetOptionCache[targetPed].RESTRAIN_OFF = true
    end
    if not targetOptionCache[targetPed].TRANSPORT_ON then
      table.insert(toAdd, "TRANSPORT_ON")
      targetOptionCache[targetPed].TRANSPORT_ON = true
    end
    if not targetOptionCache[targetPed].ESCORT_ON then
      table.insert(toAdd, "ESCORT_ON")
      targetOptionCache[targetPed].ESCORT_ON = true
    end
  else
    -- not restrained: allow RESTRAIN_ON
    if not targetOptionCache[targetPed].RESTRAIN_ON then
      table.insert(toAdd, "RESTRAIN_ON")
      targetOptionCache[targetPed].RESTRAIN_ON = true
    end
  end

  if Config.GangOptions.kidnapping then
    if bagged then
      if not targetOptionCache[targetPed].BLINDFOLD_OFF then
        table.insert(toAdd, "BLINDFOLD_OFF")
        targetOptionCache[targetPed].BLINDFOLD_OFF = true
      end
    else
      if not targetOptionCache[targetPed].BLINDFOLD_ON then
        table.insert(toAdd, "BLINDFOLD_ON")
        targetOptionCache[targetPed].BLINDFOLD_ON = true
      end
    end
  end

  if #toAdd > 0 then
    targetRegistered[targetPed] = true
    -- Convert option names to actual option objects for ox_target
    local optionObjects = {}
    for _, optionName in ipairs(toAdd) do
      local optionObj = optionNameToObject[optionName]
      if optionObj then
        table.insert(optionObjects, optionObj)
      end
    end
    TargetEntity(targetPed, optionObjects, true)
  end
end

-- ============================================================================
-- Net events (bag / restrain / escort / transport / cleanup)
-- ============================================================================
RegisterNetEvent("rcore_gangs:client:bag")
AddEventHandler("rcore_gangs:client:bag", function(sourceServerId, targetServerId, enabled)
  local sourceIndex = GetPlayerFromServerId(sourceServerId)
  local targetIndex = GetPlayerFromServerId(targetServerId)

  if not NetworkIsPlayerActive(targetIndex) then
    cleanupProp(bagPropByServerId, targetServerId)
    return
  end

  local myPed = PlayerPedId()
  local targetPed = GetPlayerPed(targetIndex)
  local d = dist(GetEntityCoords(targetPed), GetEntityCoords(myPed))
  if d > 60.0 then
    cleanupProp(bagPropByServerId, targetServerId)
    return
  end

  -- Local player updates
  if targetIndex == PlayerId() then
    if enabled then
      if Intervals then Intervals.action = 0 end
      isBlindfolded = true
      notify(L.ACTIONS_TARGET_BAG_ON)
      if Framework and Framework.ActionsOnBlindfold then Framework.ActionsOnBlindfold(true) end
      TriggerEvent("rcore_gangs:client:disable_actions", true)
    else
      isBlindfolded = false
      notify(L.ACTIONS_TARGET_BAG_OFF)
      if Framework and Framework.ActionsOnBlindfold then Framework.ActionsOnBlindfold(false) end
      TriggerEvent("rcore_gangs:client:disable_actions", false)
    end
    DisplayRadar(not enabled)
  end

  -- Remote prop
  if enabled then
    ClearPedTasks(GetPlayerPed(sourceIndex))
    ClearPedTasks(targetPed)

    ensureAttachedProp(bagPropByServerId, targetServerId, targetIndex, BAG_MODEL, BAG_BONE, BAG_OFFSET)
  else
    ClearPedTasks(GetPlayerPed(sourceIndex))
    ClearPedTasks(targetPed)
    cleanupProp(bagPropByServerId, targetServerId)
  end
end)

RegisterNetEvent("rcore_gangs:client:restrain")
AddEventHandler("rcore_gangs:client:restrain", function(sourceServerId, targetServerId, enabled)
  local sourceIndex = GetPlayerFromServerId(sourceServerId)
  local targetIndex = GetPlayerFromServerId(targetServerId)

  if not NetworkIsPlayerActive(targetIndex) then
    cleanupProp(cuffPropByServerId, targetServerId)
    return
  end

  local myPed = PlayerPedId()
  local targetPed = GetPlayerPed(targetIndex)
  local d = dist(GetEntityCoords(targetPed), GetEntityCoords(myPed))
  if d > 60.0 then
    cleanupProp(cuffPropByServerId, targetServerId)
    return
  end

  -- Local player updates
  if targetIndex == PlayerId() then
    if enabled then
      if Intervals then Intervals.action = 0 end
      isRestrained = true
      notify(L.ACTIONS_TARGET_TIE_ON)
      if Framework and Framework.ActionsOnRestrain then Framework.ActionsOnRestrain(true) end
      TriggerEvent("rcore_gangs:client:disable_actions", true)
    else
      isRestrained = false
      notify(L.ACTIONS_TARGET_TIE_OFF)
      if Framework and Framework.ActionsOnRestrain then Framework.ActionsOnRestrain(false) end
      TriggerEvent("rcore_gangs:client:disable_actions", false)
    end

    SetEnableHandcuffs(targetPed, enabled == true)
    SetCurrentPedWeapon(targetPed, -1569615261, true)
  end

  -- Remote animation for source/target (kept but simplified; no goto)
  local sourcePed = GetPlayerPed(sourceIndex)
  if sourceServerId == GetPlayerServerId(PlayerId()) then
    if enabled then
      ClearPedTasks(sourcePed)
      ensureAnimDict("mp_arrest_paired")
      TaskPlayAnim(sourcePed, "mp_arrest_paired", "cop_p3_fwd", 8.0, 8.0, -1, 16, 0, false, false, false)
      Wait(math.ceil(GetAnimDuration("mp_arrest_paired", "cop_p3_fwd") * 1000))
      ClearPedTasks(sourcePed)
    else
      ClearPedTasks(sourcePed)
    end
  end

  if targetServerId == GetPlayerServerId(PlayerId()) then
    if enabled then
      ClearPedTasks(targetPed)
      ensureAnimDict("mp_arrest_paired")
      TaskPlayAnim(targetPed, "mp_arrest_paired", "crook_p3", 8.0, 8.0, -1, 16, 0, false, false, false)
      Wait(math.ceil(GetAnimDuration("mp_arrest_paired", "cop_p3_fwd") * 1000) + 1000)
      ensureAnimDict("mp_arresting")
      TaskPlayAnim(targetPed, "mp_arresting", "idle", 8.0, 8.0, -1, 49, 0, false, false, false)
    else
      ClearPedTasks(targetPed)
    end
  end

  -- Remote prop
  if enabled then
    ensureAttachedProp(cuffPropByServerId, targetServerId, targetIndex, CUFF_MODEL, CUFF_BONE, CUFF_OFFSET)
  else
    cleanupProp(cuffPropByServerId, targetServerId)
  end
end)

RegisterNetEvent("rcore_gangs:client:escorted")
AddEventHandler("rcore_gangs:client:escorted", function(targetServerId, enabled)
  escortedStateByServerId[targetServerId] = enabled == true
end)

RegisterNetEvent("rcore_gangs:client:escort")
AddEventHandler("rcore_gangs:client:escort", function(targetServerId, enabled)
  -- This event is used when YOU are escorting someone (target attaches to you)
  local myIndex = PlayerId()
  local targetIndex = GetPlayerFromServerId(targetServerId)

  local myPed = GetPlayerPed(myIndex)
  local targetPed = GetPlayerPed(targetIndex)

  if enabled then
    if Intervals then Intervals.action = 0 end
    ClearPedTasks(myPed)
    ensureAnimDict("anim@heists@box_carry@")
    TaskPlayAnim(myPed, "anim@heists@box_carry@", "idle", 8.0, 8.0, -1, 49, 0, false, false, false)

    escortingTargetIndex = targetIndex

    if DoesEntityExist(targetPed) then
      AttachEntityToEntity(
        targetPed, myPed, GetPedBoneIndex(myPed, 28422),
        0.0, -0.3, -0.25, -15.0, 0.0, 180.0,
        true, false, true, true, 0, true
      )
    end
  else
    if Intervals then Intervals.action = Intervals.action end
    escortingTargetIndex = -1
    ClearPedTasks(myPed)
    if DoesEntityExist(targetPed) then
      DetachEntity(targetPed, true, false)
    end
  end
end)

RegisterNetEvent("rcore_gangs:client:escort_by")
AddEventHandler("rcore_gangs:client:escort_by", function(escorterServerId, enabled)
  -- This event is used when YOU are being escorted (you attach to escorter)
  local escorterIndex = GetPlayerFromServerId(escorterServerId)
  local myPed = PlayerPedId()
  local escorterPed = GetPlayerPed(escorterIndex)

  if enabled then
    if Intervals then Intervals.action = 0 end
    escortedByIndex = escorterIndex
    notify(L.ACTIONS_TARGET_ESCORT_ON)

    if DoesEntityExist(escorterPed) then
      AttachEntityToEntity(
        myPed, escorterPed, GetPedBoneIndex(escorterPed, 28422),
        0.0, -0.3, -0.25, -15.0, 0.0, 180.0,
        true, false, true, true, 0, true
      )
    end
  else
    escortedByIndex = -1
    notify(L.ACTIONS_TARGET_ESCORT_ON) -- original had same key; keep if that’s intentional in your locale
    DetachEntity(myPed, true, false)
  end
end)

RegisterNetEvent("rcore_gangs:client:transport")
AddEventHandler("rcore_gangs:client:transport", function(targetServerId, vehicleNetId, enabled)
  local targetIndex = GetPlayerFromServerId(targetServerId)
  if not NetworkIsPlayerActive(targetIndex) then return end

  local myPed = PlayerPedId()
  local targetPed = GetPlayerPed(targetIndex)
  if dist(GetEntityCoords(targetPed), GetEntityCoords(myPed)) > 60.0 then return end

  local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

  -- Local state updates when the event applies to us
  if targetIndex == PlayerId() and targetPed == myPed then
    if enabled then
      if Intervals then Intervals.action = 0 end
      isTransported = true
      notify(L.ACTIONS_TARGET_TRANSPORT_ON)
    else
      isTransported = false
      notify(L.ACTIONS_TARGET_TRANSPORT_OFF)
    end
  end

  -- Seat selection: choose nearest free door-related seat (simplified)
  local seatOrder = { -1, 0, 1, 2 }

  if enabled then
    local chosenSeat = nil
    for i = 1, #seatOrder do
      local seat = seatOrder[i]
      if IsVehicleSeatFree(vehicle, seat) then
        chosenSeat = seat
        break
      end
    end

    if chosenSeat == nil then return end

    SetVehicleDoorOpen(vehicle, chosenSeat + 1, false, false)
    Wait(250)
    TaskEnterVehicle(targetPed, vehicle, -1, chosenSeat, 1.0, 16, 0)
    Wait(250)
    ensureAnimDict("mp_arresting")
    TaskPlayAnim(targetPed, "mp_arresting", "sit", 8.0, 8.0, -1, 49, 0, false, false, false)
    SetVehicleDoorShut(vehicle, chosenSeat + 1, false)
  else
    for i = 1, #seatOrder do
      local seat = seatOrder[i]
      if GetPedInVehicleSeat(vehicle, seat) == targetPed then
        SetVehicleDoorOpen(vehicle, seat + 1, false, false)
        Wait(250)
        TaskLeaveVehicle(targetPed, vehicle, 16)
        Wait(250)
        ensureAnimDict("mp_arresting")
        TaskPlayAnim(targetPed, "mp_arresting", "idle", 8.0, 8.0, -1, 49, 0, false, false, false)
        SetVehicleDoorShut(vehicle, seat + 1, false)
        break
      end
    end
  end
end)

RegisterNetEvent("rcore_gangs:client:player_left")
AddEventHandler("rcore_gangs:client:player_left", function(serverId)
  cleanupProp(bagPropByServerId, serverId)
  cleanupProp(cuffPropByServerId, serverId)
  escortedStateByServerId[serverId] = nil
end)
