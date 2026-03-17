-- server/rivalry.lua

local activeRivalriesByZone = {}
local finishedRivalriesByGangId = {}

function GetRivalry(zoneName)
  return activeRivalriesByZone[zoneName]
end

function AddRivalrySale(source, zoneName, gangId, amount)
  local rivalry = activeRivalriesByZone[zoneName]
  if not rivalry then
    return
  end

  rivalry.funds = rivalry.funds + amount

  if rivalry.attacker == gangId then
    SQL.AddRivalrySaleAttacker(source, zoneName, gangId, amount)
  end

  if rivalry.defender == gangId then
    SQL.AddRivalrySaleDefender(source, zoneName, gangId, amount)
  end

  TriggerClientEvent("rcore_gangs:client:set_rivalry", -1, zoneName, rivalry)
end

function RefreshRivalries()
  activeRivalriesByZone = table.wipe(activeRivalriesByZone)
  finishedRivalriesByGangId = table.wipe(finishedRivalriesByGangId)

  for _, rivalry in ipairs(SQL.GetRivalries()) do
    activeRivalriesByZone[rivalry.zone] = rivalry
    activeRivalriesByZone[rivalry.zone].endsAt = GetGameTimer() + (rivalry.secondsLeft * 1000)
  end

  for _, finished in pairs(SQL.GetFinishedRivalries()) do
    local gangId = finished.gang
    finishedRivalriesByGangId[gangId] = finishedRivalriesByGangId[gangId] or {}
    finishedRivalriesByGangId[gangId][finished.zone] = finished
  end
end

RegisterNetEvent("rcore_gangs:server:start_rivalry")
AddEventHandler("rcore_gangs:server:start_rivalry", function(zoneName)
  local serverId = source
  local playerGang = ServerIdToGang[serverId]
  if not playerGang then
    return
  end

  if not playerGang.leader then
    if not (playerGang.access and playerGang.access["rivalry.begin"]) then
      return
    end
  end

  local ped = GetPlayerPed(serverId)
  local coords = GetEntityCoords(ped)
  local zone = GetZoneAtPosition(coords)

  if not zone or zone.name ~= zoneName then
    return
  end

  local ownerGang = GetGangAtZone(zone)
  if not ownerGang then
    return
  end

  if activeRivalriesByZone[zoneName] then
    return
  end

  if ownerGang.id == playerGang.id then
    return
  end

  local money = Framework.GetPlayerMoney(serverId)
  local cost = Config.ZoneOptions.rivalryCost
  if money < cost then
    Framework.ShowNotification(serverId, Locale.RIVALRY_MISSING_MONEY)
    return
  end

  logToDiscord(
    serverId,
    formatRivalryLog(
      playerGang.name,
      ownerGang.name,
      Config.GangZones[zone.name].label
    )
  )

  SQL.Execute("ANALYZE TABLE rivalries")

  local rivalryId = SQL.Scalar("SELECT AUTO_INCREMENT FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'rivalries'")
  local durationSeconds = (Config.ZoneOptions.rivalryDuration * 60) * 60

  activeRivalriesByZone[zoneName] = {
    id = rivalryId,
    zone = zone.name,
    funds = cost,
    attacker = playerGang.id,
    defender = ownerGang.id,
    secondsLeft = durationSeconds,
    endsAt = GetGameTimer() + (durationSeconds * 1000)
  }

  Framework.RemovePlayerMoney(serverId, cost)
  SQL.InsertRivalry(zoneName, playerGang.id, ownerGang.id)

  TriggerClientEvent("rcore_gangs:client:set_rivalry", -1, zoneName, activeRivalriesByZone[zoneName])

  for _, member in ipairs(playerGang.members or {}) do
    local memberServerId = PlayerIdToServerId[member.identifier]
    if memberServerId then
      Framework.ShowAdvancedNotification(
        memberServerId,
        Locale.NOTIFICATION_RIVALRY_TITLE,
        zone.label,
        Locale.NOTIFICATION_RIVALRY_ATTACK
      )
    end
  end

  for _, member in ipairs(ownerGang.members or {}) do
    local memberServerId = PlayerIdToServerId[member.identifier]
    if memberServerId then
      Framework.ShowAdvancedNotification(
        memberServerId,
        Locale.NOTIFICATION_RIVALRY_TITLE,
        zone.label,
        Locale.NOTIFICATION_RIVALRY_DEFEND
      )
    end
  end
end)

RegisterNetEvent("rcore_gangs:server:finish_rivalry")
AddEventHandler("rcore_gangs:server:finish_rivalry", function(zoneName)
  local serverId = source
  local playerGang = ServerIdToGang[serverId]
  if not playerGang then
    return
  end

  if not playerGang.leader then
    if not (playerGang.access and playerGang.access["rivalry.claim"]) then
      return
    end
  end

  local ped = GetPlayerPed(serverId)
  local coords = GetEntityCoords(ped)
  local zone = GetZoneAtPosition(coords)

  if not zone or zone.name ~= zoneName then
    return
  end

  local finishedByZone = finishedRivalriesByGangId[playerGang.id]
  local finished = finishedByZone and finishedByZone[zoneName] or nil

  if not finished then
    return
  end

  if finished.gang ~= playerGang.id then
    return
  end

  finishedByZone[zoneName] = nil

  local dirtyCfg = Config.OtherOptions
  if dirtyCfg and (dirtyCfg.dirtyMoney or dirtyCfg.dirtyMoneyItem) then
    Framework.AddPlayerDirtyMoney(serverId, finished.funds)
  else
    Framework.AddPlayerMoney(serverId, finished.funds)
  end

  SQL.DeleteRivalry(finished.id, finished.zone, finished.gang)
  TriggerClientEvent("rcore_gangs:client:set_finished_rivalry", -1, finished.gang, finishedByZone)
end)

RegisterNetEvent("rcore_gangs:server:player_loaded")
AddEventHandler("rcore_gangs:server:player_loaded", function(target)
  local targetServerId = target
  if not targetServerId then
    targetServerId = source
  end

  for zoneName, rivalry in pairs(activeRivalriesByZone) do
    TriggerClientEvent("rcore_gangs:client:set_rivalry", targetServerId, zoneName, rivalry)
  end

  for gangId, zones in pairs(finishedRivalriesByGangId) do
    TriggerClientEvent("rcore_gangs:client:set_finished_rivalry", targetServerId, gangId, zones)
  end
end)

AddEventHandler("rcore_gangs:server:database_ready", function()
  RefreshRivalries()
  Wait(1000)

  for zoneName, rivalry in pairs(activeRivalriesByZone) do
    TriggerClientEvent("rcore_gangs:client:set_rivalry", -1, zoneName, rivalry)
  end

  for gangId, zones in pairs(finishedRivalriesByGangId) do
    TriggerClientEvent("rcore_gangs:client:set_finished_rivalry", -1, gangId, zones)
  end
end)

CreateThread(function()
  while true do
    Wait(1000)

    for zoneName, rivalry in pairs(activeRivalriesByZone) do
      Wait(0)

      if rivalry.endsAt < GetGameTimer() then
        RefreshRivalries()
        TriggerClientEvent("rcore_gangs:client:set_rivalry", -1, zoneName, nil)

        for gangId, zones in pairs(finishedRivalriesByGangId) do
          local finished = zones[rivalry.zone]
          if finished and finished.id == rivalry.id then
            TriggerClientEvent("rcore_gangs:client:set_finished_rivalry", -1, gangId, zones)
          end
        end
      end
    end
  end
end, SessionNames.RIVALRIES_STATUS)