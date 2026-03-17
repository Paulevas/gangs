-- ==============================================================
-- checkpoint.lua (server) - refactor, same behavior
-- ==============================================================

-- These were anonymous SHX tables; keep them module-local but with clear names.
local spawnedVehicleNetIdsByGangId = {} -- [gangId][model.color.plate] = netId (only if restrictSpawns)
local spawnInProgressByGangId = {}      -- [gangId][model.color.plate] = true/false (in-progress flag)

-- NOTE: two unused locals existed in decompile (SHX0_1={}, SHX1_1={}) and were later used heavily.
-- We preserve the same role using the two tables above.

-- ==============================================================
-- Helpers (global functions, per your rules)
-- ==============================================================

function NormalizeCheckpointType(checkpointType)
  if not checkpointType then return nil end
  local t = checkpointType:lower():strtrim()
  if t == "garage" or t == "storage" or t == "reserve" then
    return t
  end
  return nil
end

function GangFromRequest(sourceId, gangKey, requiredPerm)
  local gang = GetGangFromKey(gangKey)

  if gang then
    return gang, nil
  end

  if not sourceId then
    return nil, Locale.COMMAND_INVALID_GANG
  end

  local playerGang = ServerIdToGang and ServerIdToGang[sourceId] or nil
  if not playerGang then
    Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_GANG)
    return nil, Locale.COMMAND_INVALID_GANG
  end

  if playerGang.leader then
    return playerGang, nil
  end

  if playerGang.access and playerGang.access[requiredPerm] then
    return playerGang, nil
  end

  Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_GANG)
  return nil, Locale.COMMAND_INVALID_GANG
end

function CopyGangCheckpointPayload(gang)
  local payload = {}

  if gang.garage then
    payload.garage = { x = gang.garage.x, y = gang.garage.y, z = gang.garage.z }
  end

  if gang.storage then
    payload.storage = { x = gang.storage.x, y = gang.storage.y, z = gang.storage.z }
  end

  if gang.reserve then
    payload.reserve = { x = gang.reserve.x, y = gang.reserve.y, z = gang.reserve.z }
  end

  return payload
end

function ApplyCheckpointToGangCache(gangId, checkpoints)
  local gangCache = Gangs[gangId]
  if not gangCache then return end

  gangCache.garage = checkpoints.garage and vec3(checkpoints.garage.x, checkpoints.garage.y, checkpoints.garage.z) or nil
  gangCache.storage = checkpoints.storage and vec3(checkpoints.storage.x, checkpoints.storage.y, checkpoints.storage.z) or nil
  gangCache.reserve = checkpoints.reserve and vec3(checkpoints.reserve.x, checkpoints.reserve.y, checkpoints.reserve.z) or nil
end

function RefreshGangForOnlineMembers(gang)
  for _, member in ipairs(gang.members) do
    local memberServerId = PlayerIdToServerId and PlayerIdToServerId[member.identifier] or nil
    if memberServerId then
      SetPlayerGang(memberServerId)
    end
  end
end

function EnsureGangVehicleTables(gangId)
  if not spawnedVehicleNetIdsByGangId[gangId] then
    spawnedVehicleNetIdsByGangId[gangId] = {}
  end
  if not spawnInProgressByGangId[gangId] then
    spawnInProgressByGangId[gangId] = {}
  end
end

function VehicleKey(modelHash, colorIndex, plate)
  return tostring(modelHash) .. "." .. tostring(colorIndex) .. "." .. tostring(plate)
end

function VehicleKeyFromGangVehicle(v)
  return VehicleKey(v.model, v.color, v.plate)
end

function IsColorIndexValid(colorIndex)
  for _, colors in pairs(Config.VehicleColors) do
    for _, colorInfo in ipairs(colors) do
      if colorInfo.index == colorIndex then
        return true
      end
    end
  end
  return false
end

-- ==============================================================
-- Checkpoints
-- ==============================================================

function InsertCheckpoint(sourceId, checkpointType, coords, gangKey)
  local gang, gangErr = GangFromRequest(sourceId, gangKey, "checkpoint.edit")
  if not gang then
    if not sourceId then return gangErr end
    return gangErr
  end

  if not (Config.GangOptions.garage or Config.GangOptions.storage or Config.GangOptions.reserve) then
    return nil
  end

  if not checkpointType then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_CHECKPOINT) end
    return Locale.COMMAND_MISSING_CHECKPOINT
  end

  local normalized = NormalizeCheckpointType(checkpointType)
  if not normalized then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_CHECKPOINT) end
    return Locale.COMMAND_INVALID_CHECKPOINT
  end

  if not coords then
    local ped = GetPlayerPed(sourceId)
    coords = GetEntityCoords(ped)
  end

  local newCheckpoints = CopyGangCheckpointPayload(gang)

  local existing = gang[normalized] or vec3(0.0, 0.0, 0.0)
  local dist = glm.distance(coords, existing)

  if dist <= 5.0 then
    if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_CLOSE) end
    return Locale.CHECKPOINT_ERROR_CLOSE
  end

  newCheckpoints[normalized] = { x = coords.x, y = coords.y, z = coords.z }

  SQL.SetGangCheckpoints(gang.id, json.encode(newCheckpoints))
  ApplyCheckpointToGangCache(gang.id, newCheckpoints)
  RefreshGangForOnlineMembers(gang)

  if sourceId then
    Framework.ShowNotification(sourceId, Locale.CHECKPOINT_SUCCESS_PLACE)
  end

  return nil
end

function RemoveCheckpoint(sourceId, checkpointType, gangKeyOrFlag)
  local gang, gangErr = GangFromRequest(sourceId, gangKeyOrFlag, "checkpoint.edit")
  if not gang then
    if not sourceId then return gangErr end
    return gangErr
  end

  if not (Config.GangOptions.garage or Config.GangOptions.storage or Config.GangOptions.reserve) then
    return nil
  end

  if not checkpointType then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_CHECKPOINT) end
    return Locale.COMMAND_MISSING_CHECKPOINT
  end

  local normalized = NormalizeCheckpointType(checkpointType)
  if not normalized then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_CHECKPOINT) end
    return Locale.COMMAND_INVALID_CHECKPOINT
  end

  local newCheckpoints = CopyGangCheckpointPayload(gang)

  if normalized == "garage" then
    local forceRemove = gangKeyOrFlag == true
    if forceRemove then
      if #gang.vehicles == 0 then
        newCheckpoints.garage = nil
      else
        if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_GARAGE) end
        return Locale.CHECKPOINT_ERROR_GARAGE
      end
    else
      local ped = GetPlayerPed(sourceId)
      local coords = GetEntityCoords(ped)
      local dist = glm.distance(coords, gang.garage)

      if dist < 5.0 then
        if #gang.vehicles == 0 then
          newCheckpoints.garage = nil
        else
          if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_GARAGE) end
          return Locale.CHECKPOINT_ERROR_GARAGE
        end
      else
        if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_AWAY) end
        return Locale.CHECKPOINT_ERROR_AWAY
      end
    end
  end

  if normalized == "storage" then
    local forceRemove = gangKeyOrFlag == true
    if forceRemove then
      if Inventory.IsStorageEmpty(gang.tag) then
        newCheckpoints.storage = nil
      else
        if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_STORAGE) end
        return Locale.CHECKPOINT_ERROR_STORAGE
      end
    else
      local ped = GetPlayerPed(sourceId)
      local coords = GetEntityCoords(ped)
      local dist = glm.distance(coords, gang.storage)

      if dist < 5.0 then
        if Inventory.IsStorageEmpty(gang.tag) then
          newCheckpoints.storage = nil
        else
          if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_STORAGE) end
          return Locale.CHECKPOINT_ERROR_STORAGE
        end
      else
        if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_AWAY) end
        return Locale.CHECKPOINT_ERROR_AWAY
      end
    end
  end

  if normalized == "reserve" then
    local forceRemove = gangKeyOrFlag == true
    if forceRemove then
      if gang.balance == 0 then
        newCheckpoints.reserve = nil
      else
        if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_RESERVE) end
        return Locale.CHECKPOINT_ERROR_RESERVE
      end
    else
      local ped = GetPlayerPed(sourceId)
      local coords = GetEntityCoords(ped)
      local dist = glm.distance(coords, gang.reserve)

      if dist < 5.0 then
        if gang.balance == 0 then
          newCheckpoints.reserve = nil
        else
          if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_RESERVE) end
          return Locale.CHECKPOINT_ERROR_RESERVE
        end
      else
        if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_ERROR_AWAY) end
        return Locale.CHECKPOINT_ERROR_AWAY
      end
    end
  end

  SQL.SetGangCheckpoints(gang.id, json.encode(newCheckpoints))
  ApplyCheckpointToGangCache(gang.id, newCheckpoints)
  RefreshGangForOnlineMembers(gang)

  if sourceId then
    Framework.ShowNotification(sourceId, Locale.CHECKPOINT_SUCCESS_REMOVE)
  end

  return nil
end

-- ==============================================================
-- Vehicles (garage list)
-- ==============================================================

function InsertVehicle(sourceId, vehicleModel, colorIndex, plate, gangKey, free)
  local gang, gangErr = GangFromRequest(sourceId, gangKey, "garage.edit")
  if not gang then
    if not sourceId then return gangErr end
    return gangErr
  end

  if not vehicleModel then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_VEHICLE) end
    return Locale.COMMAND_MISSING_VEHICLE
  end

  if not colorIndex then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_COLOR) end
    return Locale.COMMAND_MISSING_COLOR
  end

  if type(vehicleModel) == "string" then
    vehicleModel = GetHashKey(vehicleModel)
  end

  if not Config.GarageVehicles[vehicleModel] then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_VEHICLE) end
    return Locale.COMMAND_INVALID_VEHICLE
  end

  if not IsColorIndexValid(colorIndex) then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_COLOR) end
    return Locale.COMMAND_INVALID_COLOR
  end

  local price = 0
  if not free then
    local vehCfg = Config.GarageVehicles[vehicleModel]
    if type(vehCfg) == "table" then
      price = vehCfg.price
    end
  end

  if price > 0 then
    local money = Framework.GetPlayerMoney(sourceId)
    if price > money then
      if sourceId then Framework.ShowNotification(sourceId, Locale.CHECKPOINT_VEHICLE_MONEY) end
      return Locale.CHECKPOINT_VEHICLE_MONEY
    end
    Framework.RemovePlayerMoney(sourceId, price)
  end

  table.insert(gang.vehicles, { model = vehicleModel, color = colorIndex, plate = plate })

  SQL.SetGangVehicles(gang.id, json.encode(gang.vehicles))
  if Gangs[gang.id] then
    Gangs[gang.id].vehicles = gang.vehicles
  end

  RefreshGangForOnlineMembers(gang)

  if sourceId then
    Framework.ShowNotification(sourceId, Locale.CHECKPOINT_VEHICLE_INSERT)
  end

  return nil
end

function RemoveVehicle(sourceId, vehicleModel, colorIndex, gangKey)
  local gang, gangErr = GangFromRequest(sourceId, gangKey, "garage.edit")
  if not gang then
    if not sourceId then return gangErr end
    return gangErr
  end

  if not vehicleModel then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_VEHICLE) end
    return Locale.COMMAND_MISSING_VEHICLE
  end

  if not colorIndex then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_COLOR) end
    return Locale.COMMAND_MISSING_COLOR
  end

  if type(vehicleModel) == "string" then
    vehicleModel = GetHashKey(vehicleModel)
  end

  if not Config.GarageVehicles[vehicleModel] then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_VEHICLE) end
    return Locale.COMMAND_INVALID_VEHICLE
  end

  if not IsColorIndexValid(colorIndex) then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_COLOR) end
    return Locale.COMMAND_INVALID_COLOR
  end

  for i, v in ipairs(gang.vehicles) do
    if v.model == vehicleModel and v.color == colorIndex then
      table.remove(gang.vehicles, i)
      break
    end
  end

  SQL.SetGangVehicles(gang.id, json.encode(gang.vehicles))
  if Gangs[gang.id] then
    Gangs[gang.id].vehicles = gang.vehicles
  end

  RefreshGangForOnlineMembers(gang)

  if sourceId then
    Framework.ShowNotification(sourceId, Locale.CHECKPOINT_VEHICLE_REMOVE)
  end

  return nil
end

-- ==============================================================
-- Reserve balance
-- ==============================================================

function GiveBalance(sourceId, amount, gangKey)
  local gang, gangErr = GangFromRequest(sourceId, gangKey, "reserve.edit")
  if not gang then
    if not sourceId then return gangErr end
    return gangErr
  end

  if not amount then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_AMOUNT) end
    return Locale.COMMAND_MISSING_AMOUNT
  end

  if sourceId then
    local money = Framework.GetPlayerMoney(sourceId)
    if amount > money then
      Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_AMOUNT1)
      return Locale.COMMAND_INVALID_AMOUNT1
    end
    Framework.RemovePlayerMoney(sourceId, amount)
  end

  SQL.SetGangBalance(gang.id, gang.balance + amount)
  if Gangs[gang.id] then
    Gangs[gang.id].balance = Gangs[gang.id].balance + amount
  end

  RefreshGangForOnlineMembers(gang)

  if sourceId then
    Framework.ShowNotification(sourceId, Locale("CHECKPOINT_RESERVE_GIVE", { amount = FormatMoney(amount) }))
  end

  return nil
end

function TakeBalance(sourceId, amount, gangKey)
  local gang, gangErr = GangFromRequest(sourceId, gangKey, "reserve.edit")
  if not gang then
    if not sourceId then return gangErr end
    return gangErr
  end

  if not amount then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_MISSING_AMOUNT) end
    return Locale.COMMAND_MISSING_AMOUNT
  end

  if amount > gang.balance then
    if sourceId then Framework.ShowNotification(sourceId, Locale.COMMAND_INVALID_AMOUNT2) end
    return Locale.COMMAND_INVALID_AMOUNT2
  end

  if sourceId then
    Framework.AddPlayerMoney(sourceId, amount)
  end

  SQL.SetGangBalance(gang.id, gang.balance - amount)
  if Gangs[gang.id] then
    Gangs[gang.id].balance = Gangs[gang.id].balance - amount
  end

  RefreshGangForOnlineMembers(gang)

  if sourceId then
    Framework.ShowNotification(sourceId, Locale("CHECKPOINT_RESERVE_TAKE", { amount = FormatMoney(amount) }))
  end

  return nil
end

-- ==============================================================
-- Commands (names unchanged)
-- ==============================================================

RegisterCommand((Config.Commands and Config.Commands.PLACEPOINT) or "placepoint", function(source, args)
  if not Framework.IsPlayerAllowed(source) then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_PERMS)
    return
  end

  local gangKey = tonumber(args[1]) or args[1]
  local checkpointType = args[2]

  if not gangKey then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_GANG)
    return
  end

  if not checkpointType then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_CHECKPOINT)
    return
  end

  InsertCheckpoint(source, checkpointType, nil, gangKey)
end)

RegisterCommand((Config.Commands and Config.Commands.REMOVEPOINT) or "removepoint", function(source, args)
  if not Framework.IsPlayerAllowed(source) then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_PERMS)
    return
  end

  local gangKey = tonumber(args[1]) or args[1]
  local checkpointType = args[2]

  if not gangKey then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_GANG)
    return
  end

  if not checkpointType then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_CHECKPOINT)
    return
  end

  RemoveCheckpoint(source, checkpointType, gangKey)
end)

RegisterCommand((Config.Commands and Config.Commands.ADDVEHICLE) or "addvehicle", function(source, args)
  if not Framework.IsPlayerAllowed(source) then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_PERMS)
    return
  end

  local gangKey = tonumber(args[1]) or args[1]
  local vehicleModel = tonumber(args[2]) or args[2]
  local colorIndex = tonumber(args[3]) or args[3]
  local plate = args[4]

  if not gangKey then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_GANG)
    return
  end
  if not vehicleModel then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_VEHICLE)
    return
  end
  if not colorIndex then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_COLOR)
    return
  end
  if not plate then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_PLATE)
    return
  end

  InsertVehicle(source, vehicleModel, colorIndex, plate, gangKey)
end)

RegisterCommand((Config.Commands and Config.Commands.DELVEHICLE) or "delvehicle", function(source, args)
  if not Framework.IsPlayerAllowed(source) then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_PERMS)
    return
  end

  local gangKey = tonumber(args[1]) or args[1]
  local vehicleModel = tonumber(args[2]) or args[2]
  local colorIndex = tonumber(args[3]) or args[3]

  if not gangKey then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_GANG)
    return
  end
  if not vehicleModel then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_VEHICLE)
    return
  end
  if not colorIndex then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_COLOR)
    return
  end

  RemoveVehicle(source, vehicleModel, colorIndex, gangKey)
end)

-- ==============================================================
-- Net events (names unchanged, handlers anonymous)
-- ==============================================================

RegisterNetEvent("rcore_gangs:server:insert_checkpoint")
AddEventHandler("rcore_gangs:server:insert_checkpoint", function(checkpointType, gangKeyOrPermFlag)
  local src = source
  if gangKeyOrPermFlag then
    if not Framework.IsPlayerAllowed(src) then
      Framework.ShowNotification(src, Locale.COMMAND_MISSING_PERMS)
      return
    end
  end
  InsertCheckpoint(src, checkpointType, nil, gangKeyOrPermFlag)
end)

RegisterNetEvent("rcore_gangs:server:delete_checkpoint")
AddEventHandler("rcore_gangs:server:delete_checkpoint", function(checkpointType, gangKeyOrPermFlag)
  local src = source
  if gangKeyOrPermFlag then
    if not Framework.IsPlayerAllowed(src) then
      Framework.ShowNotification(src, Locale.COMMAND_MISSING_PERMS)
      return
    end
  end
  RemoveCheckpoint(src, checkpointType, gangKeyOrPermFlag)
end)

RegisterNetEvent("rcore_gangs:server:purchase_vehicle")
AddEventHandler("rcore_gangs:server:purchase_vehicle", function(vehicleModel, colorIndex, plate, gangKeyOrPermFlag)
  local src = source
  if gangKeyOrPermFlag then
    if not Framework.IsPlayerAllowed(src) then
      Framework.ShowNotification(src, Locale.COMMAND_MISSING_PERMS)
      return
    end
  end
  InsertVehicle(src, vehicleModel, colorIndex, plate, gangKeyOrPermFlag)
end)

RegisterNetEvent("rcore_gangs:server:remove_vehicle")
AddEventHandler("rcore_gangs:server:remove_vehicle", function(vehicleModel, colorIndex, gangKeyOrPermFlag)
  local src = source
  if gangKeyOrPermFlag then
    if not Framework.IsPlayerAllowed(src) then
      Framework.ShowNotification(src, Locale.COMMAND_MISSING_PERMS)
      return
    end
  end
  RemoveVehicle(src, vehicleModel, colorIndex, gangKeyOrPermFlag)
end)

RegisterNetEvent("rcore_gangs:server:give_balance")
AddEventHandler("rcore_gangs:server:give_balance", function(amount, gangKeyOrPermFlag)
  local src = source
  if gangKeyOrPermFlag then
    if not Framework.IsPlayerAllowed(src) then
      Framework.ShowNotification(src, Locale.COMMAND_MISSING_PERMS)
      return
    end
  end
  GiveBalance(src, amount, gangKeyOrPermFlag)
end)

RegisterNetEvent("rcore_gangs:server:take_balance")
AddEventHandler("rcore_gangs:server:take_balance", function(amount, gangKeyOrPermFlag)
  local src = source
  if gangKeyOrPermFlag then
    if not Framework.IsPlayerAllowed(src) then
      Framework.ShowNotification(src, Locale.COMMAND_MISSING_PERMS)
      return
    end
  end
  TakeBalance(src, amount, gangKeyOrPermFlag)
end)

-- ==============================================================
-- Vehicle spawn / return (kept behavior & key formats)
-- ==============================================================

RegisterNetEvent("rcore_gangs:server:drive_vehicle")
AddEventHandler("rcore_gangs:server:drive_vehicle", function(vehicleModel, colorIndex, plate)
  local src = source
  local gangRef = ServerIdToGang and ServerIdToGang[src] or nil
  if not gangRef then return end

  if not Config.GarageVehicles[vehicleModel] then return end

  local gang = Gangs[gangRef.id]
  if not gang then return end

  EnsureGangVehicleTables(gang.id)

  local key = VehicleKey(vehicleModel, colorIndex, plate)

  if spawnInProgressByGangId[gang.id][key] then
    Framework.ShowNotification(src, "Vehicle spawning in progress for this vehicle")
    return
  end
  spawnInProgressByGangId[gang.id][key] = true

  for _, v in ipairs(gang.vehicles) do
    if v.model == vehicleModel and v.color == colorIndex and v.plate == plate then
      -- Restrict spawn check (same logic)
      local existingNetId = spawnedVehicleNetIdsByGangId[gang.id][key]
      if existingNetId and Config.GangOptions.restrictSpawns then
        local entity = NetworkGetEntityFromNetworkId(existingNetId)
        if DoesEntityExist(entity) then
          spawnInProgressByGangId[gang.id][key] = false
          Framework.ShowNotification(src, Locale.CHECKPOINT_VEHICLE_USED)
          return
        else
          spawnedVehicleNetIdsByGangId[gang.id][key] = nil
        end
      end

      local ped = GetPlayerPed(src)
      local coords = GetEntityCoords(ped)
      local heading = GetEntityHeading(ped)

      local vehicle = CreateVehicle(vehicleModel, coords, heading, true, true)
      while not DoesEntityExist(vehicle) do
        Wait(0)
      end

      local resolvedPlate = v.plate
      if resolvedPlate then
        SetVehicleNumberPlateText(vehicle, resolvedPlate)
      else
        v.plate = GetVehicleNumberPlateText(vehicle)
        SQL.SetGangVehicles(gang.id, json.encode(gang.vehicles))
        if Gangs[gang.id] then
          Gangs[gang.id].vehicles = gang.vehicles
        end
        resolvedPlate = v.plate
      end

      SetPedIntoVehicle(ped, vehicle, -1)
      SetVehicleColours(vehicle, colorIndex, colorIndex)
      Framework.SetVehicleModifications(vehicle)

      if Config.GangOptions.restrictSpawns then
        spawnedVehicleNetIdsByGangId[gang.id][VehicleKey(vehicleModel, colorIndex, resolvedPlate)] = NetworkGetNetworkIdFromEntity(vehicle)
      end

      spawnInProgressByGangId[gang.id][VehicleKey(vehicleModel, colorIndex, resolvedPlate)] = false

      TriggerClientEvent("rcore_gangs:client:set_vehicle_keys", src, NetworkGetNetworkIdFromEntity(vehicle))

      for _, member in ipairs(gang.members) do
        local memberServerId = PlayerIdToServerId and PlayerIdToServerId[member.identifier] or nil
        if memberServerId then
          TriggerClientEvent("rcore_gangs:client:set_vehicles", memberServerId, spawnedVehicleNetIdsByGangId[gang.id])
        end
      end

      Framework.ShowNotification(src, Locale.CHECKPOINT_VEHICLE_TAKE)
      return
    end
  end
end)

RegisterNetEvent("rcore_gangs:server:return_vehicle")
AddEventHandler("rcore_gangs:server:return_vehicle", function(vehicleModel, colorIndex, plate)
  local src = source
  local gangRef = ServerIdToGang and ServerIdToGang[src] or nil
  if not gangRef then return end

  if not Config.GarageVehicles[vehicleModel] then return end

  local gang = Gangs[gangRef.id]
  if not gang then return end

  EnsureGangVehicleTables(gang.id)

  local key = VehicleKey(vehicleModel, colorIndex, plate)

  for _, v in ipairs(gang.vehicles) do
    if v.model == vehicleModel and v.color == colorIndex and v.plate == plate then
      local existingNetId = spawnedVehicleNetIdsByGangId[gang.id][key]
      if existingNetId and Config.GangOptions.restrictSpawns then
        local entity = NetworkGetEntityFromNetworkId(existingNetId)
        if DoesEntityExist(entity) then
          DeleteEntity(entity)
        end
        spawnedVehicleNetIdsByGangId[gang.id][key] = nil
      end

      if not Config.GangOptions.restrictSpawns then
        local ped = GetPlayerPed(src)
        local veh = GetVehiclePedIsIn(ped)
        local model = GetEntityModel(veh)
        local color = GetVehicleColours(veh)
        if model == v.model and color == v.color and v.plate == plate then
          if DoesEntityExist(veh) then
            DeleteEntity(veh)
          end
        end
      end

      for _, member in ipairs(gang.members) do
        local memberServerId = PlayerIdToServerId and PlayerIdToServerId[member.identifier] or nil
        if memberServerId then
          TriggerClientEvent("rcore_gangs:client:set_vehicles", memberServerId, spawnedVehicleNetIdsByGangId[gang.id])
        end
      end

      Framework.ShowNotification(src, Locale.CHECKPOINT_VEHICLE_PARK)
      return
    end
  end
end)

-- ==============================================================
-- Exports (names unchanged)
-- ==============================================================

exports("AddCheckpoint", function(gangKey, checkpointType, coords)
  return InsertCheckpoint(nil, gangKey, checkpointType, coords)
end)

exports("RemoveCheckpoint", function(gangKey, checkpointType)
  return RemoveCheckpoint(nil, gangKey, checkpointType)
end)

exports("AddVehicle", function(gangKey, vehicleModel, colorIndex, plate)
  return InsertVehicle(nil, gangKey, vehicleModel, colorIndex, plate)
end)

exports("RemoveVehicle", function(gangKey, vehicleModel, colorIndex)
  return RemoveVehicle(nil, gangKey, vehicleModel, colorIndex)
end)

exports("AddBalance", function(gangKey, amount)
  return GiveBalance(nil, gangKey, amount)
end)

exports("RemoveBalance", function(gangKey, amount)
  return TakeBalance(nil, gangKey, amount)
end)

exports("GetBalance", function(gangId)
  local gang = Gangs[gangId]
  return gang and gang.balance or 0
end)