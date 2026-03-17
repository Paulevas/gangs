-- server/murder.lua

-- Tracks per-player murder/vendetta "rate limits" (per identifier) to prevent abuse.
local murderCountByIdentifier = {}
local vendettaCountByIdentifier = {}

RegisterNetEvent("rcore_gangs:server:murder", function(victimNetId)
  local src = source
  local identifier = ServerIdToPlayerId[src]
  if not identifier then return end

  local maxMurders = Config.ZoneOptions.maximumMurders
  local current = murderCountByIdentifier[identifier] or 0
  if current > maxMurders then
    return
  end

  local victimEntity = NetworkGetEntityFromNetworkId(victimNetId)
  local killerPed = GetPlayerPed(src)

  -- Entity type 1 == Ped. (Matches original behavior; it's a light sanity check.)
  if GetEntityType(victimEntity) ~= 1 then
    return
  end

  local coords = GetEntityCoords(killerPed)
  local zone = GetZoneAtPosition(coords)
  if not zone then return end

  murderCountByIdentifier[identifier] = current + 1

  -- Decrement the murder counter after 1 hour (sliding window style).
  SetTimeout(3600000, function()
    local c = murderCountByIdentifier[identifier]
    if c and c > 0 then
      murderCountByIdentifier[identifier] = c - 1
    end
  end)

  local rivalry = GetRivalry(zone.name)

  local multiplier = Config.DecreaseMultipliers.MURDER
  if rivalry then
    multiplier = Config.DecreaseMultipliersRivalry.MURDER
  end

  DecreaseLoyalty(src, zone, "MURDER", 1.0, multiplier)
end)

RegisterNetEvent("rcore_gangs:server:vendetta", function(attackerSrc, defenderSrc)
  local attackerIdentifier = ServerIdToPlayerId[attackerSrc]
  local defenderIdentifier = ServerIdToPlayerId[defenderSrc]
  if not attackerIdentifier or not defenderIdentifier then return end

  local attackerGang = ServerIdToGang[attackerSrc]
  local defenderGang = ServerIdToGang[defenderSrc]
  if not attackerGang or not defenderGang then return end

  if attackerGang.id == defenderGang.id then
    return
  end

  local maxVendettas = Config.ZoneOptions.maximumVendettas
  local defenderCount = vendettaCountByIdentifier[defenderIdentifier] or 0
  if defenderCount > maxVendettas then
    return
  end

  local attackerPed = GetPlayerPed(attackerSrc)
  local defenderPed = GetPlayerPed(defenderSrc)

  local attackerZone = GetZoneAtPosition(GetEntityCoords(attackerPed))
  local defenderZone = GetZoneAtPosition(GetEntityCoords(defenderPed))
  if not attackerZone or not defenderZone then return end

  if attackerZone.name ~= defenderZone.name then
    return
  end

  vendettaCountByIdentifier[defenderIdentifier] = defenderCount + 1

  SetTimeout(3600000, function()
    local c = vendettaCountByIdentifier[defenderIdentifier]
    if c and c > 0 then
      vendettaCountByIdentifier[defenderIdentifier] = c - 1
    end
  end)

  local rivalry = GetRivalry(attackerZone.name)

  local inc = Config.IncreaseMultipliers.VENDETTA
  local dec = Config.DecreaseMultipliers.VENDETTA
  if rivalry then
    inc = Config.IncreaseMultipliersRivalry.VENDETTA
    dec = Config.DecreaseMultipliersRivalry.VENDETTA
  end

  -- Defender gains loyalty, attacker loses loyalty (matches original flow)
  IncreaseLoyalty(defenderSrc, defenderZone, "VENDETTA", 1.0, inc)
  DecreaseLoyalty(attackerSrc, attackerZone, "VENDETTA", 1.0, dec)
end)

-- ESX death hook: mirrors the vendetta logic when killer is a player
RegisterNetEvent("esx:onPlayerDeath", function(data)
  local victimSrc = source
  if not data or not data.killedByPlayer then return end

  local killerSrc = data.killerServerId
  if not killerSrc then return end

  local victimIdentifier = ServerIdToPlayerId[victimSrc]
  local killerIdentifier = ServerIdToPlayerId[killerSrc]
  if not victimIdentifier or not killerIdentifier then return end

  local victimGang = ServerIdToGang[victimSrc]
  local killerGang = ServerIdToGang[killerSrc]
  if not victimGang or not killerGang then return end

  if victimGang.id == killerGang.id then
    return
  end

  local maxVendettas = Config.ZoneOptions.maximumVendettas
  local killerCount = vendettaCountByIdentifier[killerIdentifier] or 0
  if killerCount > maxVendettas then
    return
  end

  local victimPed = GetPlayerPed(victimSrc)
  local killerPed = GetPlayerPed(killerSrc)

  local victimZone = GetZoneAtPosition(GetEntityCoords(victimPed))
  local killerZone = GetZoneAtPosition(GetEntityCoords(killerPed))
  if not victimZone or not killerZone then return end

  if victimZone.name ~= killerZone.name then
    return
  end

  vendettaCountByIdentifier[killerIdentifier] = killerCount + 1

  SetTimeout(3600000, function()
    local c = vendettaCountByIdentifier[killerIdentifier]
    if c and c > 0 then
      vendettaCountByIdentifier[killerIdentifier] = c - 1
    end
  end)

  local rivalry = GetRivalry(victimZone.name)

  local inc = Config.IncreaseMultipliers.VENDETTA
  local dec = Config.DecreaseMultipliers.VENDETTA
  if rivalry then
    inc = Config.IncreaseMultipliersRivalry.VENDETTA
    dec = Config.DecreaseMultipliersRivalry.VENDETTA
  end

  IncreaseLoyalty(killerSrc, killerZone, "VENDETTA", 1.0, inc)
  DecreaseLoyalty(victimSrc, victimZone, "VENDETTA", 1.0, dec)
end)

-- qb-ambulancejob integration block:
-- ⚠️ The decompiled code tries to PATCH qb-ambulancejob/client/dead.lua at runtime by editing the file.
-- That is fragile + unsafe in production and will break on updates.
-- Keep it out unless you explicitly want file-patching behavior.
CreateThread(function()
  local state = GetResourceState("qb-ambulancejob")
  if state ~= "starting" and state ~= "started" then
    return
  end

  local contents = LoadResourceFile("qb-ambulancejob", "client/dead.lua")
  if not contents then return end

  -- If already integrated, do nothing.
  if contents:find("rcore_gangs", 1, true) then return end

  -- Try to insert vendetta trigger before qb-log CreateLog block (matches original intent).
  local startPos, endPos = contents:find("qb%-log:server:CreateLog.-\n")
  if not startPos or not endPos then return end

  local injection = "\t\t\t\tTriggerServerEvent('rcore_gangs:server:vendetta', GetPlayerServerId(playerid), GetPlayerServerId(killerId))\n"
  local patched = contents:sub(1, endPos) .. injection .. contents:sub(endPos + 1)

  SaveResourceFile("qb-ambulancejob", "client/dead.lua", patched, -1)
  print("^2[GANGS] DEATH INTEGRATED, PLEASE RESTART YOUR SERVER!^7")
end, SessionNames.QB_AMBULANCE_JOB_INTEGRATION)