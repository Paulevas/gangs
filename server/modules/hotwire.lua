-- server/hotwire.lua
-- Hotwire-related territory loyalty penalties + lightweight abuse limiting.
-- Integrates with:
--  - rcore_gangs:server:hotwire (called from client when entering a hotwire-needed vehicle)
--  - hud:server:GainStress (QB stress gain used as a "hotwire in progress" hint)
--  - qb-vehiclekeys:server:AcquireVehicleKeys (award keys after successful hotwire)
--  - rcore_hotwire:carHotwire (optional external hotwire resource hook)

local hotwireCountByIdentifier = {}      -- identifier -> count (decays after 1 hour)
local pendingHotwireNetBySrc = {}        -- src -> vehicleNetId (used to validate AcquireVehicleKeys)

local function canProcessHotwire(identifier)
  if not identifier then return false end

  local maxHotwires = Config.ZoneOptions.maximumHotwires
  local current = hotwireCountByIdentifier[identifier]
  if current and current > maxHotwires then
    return false
  end

  return true
end

local function registerHotwire(identifier)
  hotwireCountByIdentifier[identifier] = (hotwireCountByIdentifier[identifier] or 0) + 1

  -- Decrement after 1 hour (sliding window)
  SetTimeout(3600000, function()
    local c = hotwireCountByIdentifier[identifier]
    if c and c > 0 then
      hotwireCountByIdentifier[identifier] = c - 1
    end
  end)
end

local function applyHotwirePenalty(src, zone)
  if not zone then return end

  local rivalry = GetRivalry(zone.name)

  local multiplier = Config.DecreaseMultipliers.HOTWIRE
  if rivalry then
    multiplier = Config.DecreaseMultipliersRivalry.HOTWIRE
  end

  DecreaseLoyalty(src, zone, "HOTWIRE", 1.0, multiplier)
end

local function getZoneForPlayer(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  return GetZoneAtPosition(GetEntityCoords(ped))
end

-- Primary hook: client reports a vehicle that "needs hotwiring"
RegisterNetEvent("rcore_gangs:server:hotwire", function(vehicleNetId)
  local src = source
  local identifier = ServerIdToPlayerId[src]
  if not canProcessHotwire(identifier) then return end

  local veh = NetworkGetEntityFromNetworkId(vehicleNetId)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  if GetEntityType(veh) ~= 2 then return end -- 2 == vehicle

  local zone = getZoneForPlayer(src)
  if not zone then return end

  registerHotwire(identifier)
  applyHotwirePenalty(src, zone)
end)

-- QB stress gain event is used as a "hotwire started" indicator.
-- We store the player's current vehicle netId so we can validate key acquisition later.
RegisterNetEvent("hud:server:GainStress", function()
  local src = source
  local identifier = ServerIdToPlayerId[src]

  if identifier then
    local maxHotwires = Config.ZoneOptions.maximumHotwires
    local current = hotwireCountByIdentifier[identifier]
    if current and current > maxHotwires then
      pendingHotwireNetBySrc[src] = nil
      return
    end
  end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return end

  local veh = GetVehiclePedIsIn(ped, false)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end

  pendingHotwireNetBySrc[src] = NetworkGetNetworkIdFromEntity(veh)
end)

-- QB Vehicle Keys: when keys are acquired, validate that this is the same vehicle we tracked during hotwire.
RegisterNetEvent("qb-vehiclekeys:server:AcquireVehicleKeys", function(plate)
  local src = source
  local identifier = ServerIdToPlayerId[src]
  local pendingNetId = pendingHotwireNetBySrc[src]
  if not pendingNetId then return end

  if not canProcessHotwire(identifier) then
    pendingHotwireNetBySrc[src] = nil
    return
  end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then
    pendingHotwireNetBySrc[src] = nil
    return
  end

  local coords = GetEntityCoords(ped)
  local veh = GetVehiclePedIsIn(ped, false)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    pendingHotwireNetBySrc[src] = nil
    return
  end

  local currentNetId = NetworkGetNetworkIdFromEntity(veh)
  if currentNetId ~= pendingNetId then
    pendingHotwireNetBySrc[src] = nil
    return
  end

  local currentPlate = GetVehicleNumberPlateText(veh)
  if currentPlate ~= plate then
    pendingHotwireNetBySrc[src] = nil
    return
  end

  -- One-time use
  pendingHotwireNetBySrc[src] = nil

  local zone = GetZoneAtPosition(coords)
  if not zone then return end

  registerHotwire(identifier)
  applyHotwirePenalty(src, zone)
end)

-- Optional external hotwire resource hook (rcore_hotwire).
-- This event supplies a server id (not network id), so we just zone-check + penalize.
AddEventHandler("rcore_hotwire:carHotwire", function(src)
  local identifier = ServerIdToPlayerId[src]
  if not canProcessHotwire(identifier) then return end

  local zone = getZoneForPlayer(src)
  if not zone then return end

  registerHotwire(identifier)
  applyHotwirePenalty(src, zone)
end)