-- server.lua

Gangs = {}
Zones = {}

PlayerIdToGang = {}
ServerIdToGang = {}

PlayerIdToServerId = {}
ServerIdToPlayerId = {}

local deathStateByServerId = {}
local rankIndexByGroup = {}

for groupName, groupCfg in pairs(Config.RanksGroups) do
  rankIndexByGroup[groupName] = {}
  for rankIndex, rankCfg in pairs(groupCfg.ranks) do
    rankIndexByGroup[groupName][rankCfg.label] = rankIndex
  end
end

function GetGangIdentifierByTag(tag)
  for _, gang in pairs(Gangs) do
    if gang.tag == tag then
      return gang.id
    end
  end
  return nil
end

function DoesPlayerRankExist(groupName, rankLabel)
  local group = rankIndexByGroup[groupName]
  if not group then
    return false
  end
  return group[rankLabel]
end

function GetPlayerGang(source)
  local playerIdentifier = ServerIdToPlayerId[source]

  for _, gang in pairs(Gangs) do
    if gang.identifier == playerIdentifier then
      local playerGang = {
        id = gang.id,
        identifier = gang.identifier,
        tag = gang.tag,
        name = gang.name,
        color = gang.color,
        group = gang.group,
        garage = gang.garage,
        storage = gang.storage,
        reserve = gang.reserve,
        balance = gang.balance,
        vehicles = gang.vehicles,
        members = gang.members
      }

      for _, rankCfg in ipairs(gang.ranks or {}) do
        if rankCfg.leader then
          playerGang.rank = rankCfg.label
          playerGang.leader = rankCfg.leader
          playerGang.access = rankCfg.access
          break
        end
      end

      for memberIndex, member in pairs(playerGang.members or {}) do
        local group = gang.group
        local labelToIndex = group and rankIndexByGroup[group]
        local rankIndex = labelToIndex and labelToIndex[member.rank] or nil
        playerGang.members[memberIndex].rankIndex = rankIndex
      end

      playerGang.ranks = gang.ranks
      return playerGang
    end

    for _, member in ipairs(gang.members or {}) do
      if member.identifier == playerIdentifier then
        local playerGang = {
          id = gang.id,
          identifier = gang.identifier,
          tag = gang.tag,
          name = gang.name,
          color = gang.color,
          group = gang.group,
          garage = gang.garage,
          storage = gang.storage,
          reserve = gang.reserve,
          balance = gang.balance,
          vehicles = gang.vehicles,
          members = gang.members
        }

        for _, rankCfg in ipairs(gang.ranks or {}) do
          if rankCfg.label == member.rank then
            playerGang.rank = rankCfg.label
            playerGang.leader = rankCfg.leader
            playerGang.access = rankCfg.access
            break
          end
        end

        playerGang.ranks = gang.ranks
        return playerGang
      end
    end
  end

  return nil
end

function SetPlayerGang(source)
  local serverId = source
  local playerIdentifier = Framework.GetPlayerId(serverId)
  local playerGang = GetPlayerGang(serverId)

  PlayerIdToGang[playerIdentifier] = playerGang
  ServerIdToGang[serverId] = playerGang

  if Config.OverrideGangs then
    Framework.SetPlayerGang(serverId, playerGang)
  end

  TriggerClientEvent("rcore_gangs:client:set_gang", serverId, playerGang)
end

function IncreaseLoyalty(source, zone, actionKey, amount, multiplier)
  local playerGang = ServerIdToGang[source]
  if not playerGang then
    return
  end

  if not (Config.IncreaseMultipliers and Config.IncreaseMultipliers[actionKey]) then
    return
  end

  local oldOwner = GetGangAtZone(zone)

  local zoneWeights = { [zone.name] = 1.0 }
  for _, neighborName in ipairs(zone.neighbors or {}) do
    zoneWeights[neighborName] = 0.1
  end

  local updates = {}

  for zoneName, weight in pairs(zoneWeights) do
    Wait(0)

    local zoneKey = zoneName .. "." .. playerGang.id
    local existing = Zones[zoneKey]

    if zoneName == zone.name or existing then
      local inc = math.max(1, math.ceil(weight * amount * multiplier))

      if existing then
        existing.loyalty = existing.loyalty + inc
        SQL.SetZoneLoyalty(playerGang.id, zoneName, existing.loyalty)
        updates[#updates + 1] = { zoneKey, existing }
      else
        local newEntry = {
          name = zoneName,
          gangId = playerGang.id,
          gangName = playerGang.name,
          gangColor = playerGang.color,
          loyalty = inc
        }

        Zones[zoneKey] = newEntry
        SQL.InsertZone(playerGang.id, zoneName, inc)
        updates[#updates + 1] = { zoneKey, newEntry }
      end
    end
  end

  TriggerClientEvent("rcore_gangs:client:set_zones_update", -1, updates)
  Framework.ShowAdvancedNotification(source, Locale.NOTIFICATION_LOYALTY_TITLE, zone.label, Locale.NOTIFICATION_LOYALTY_INCREASED)

  local newOwner = GetGangAtZone(zone)

  if oldOwner and newOwner and oldOwner.id ~= newOwner.id then
    logToDiscord(
      source,
      formatTerritoryCaptureLog(
        oldOwner.name,
        newOwner.name,
        Config.GangZones[zone.name].label
      )
    )
  end

  if not newOwner or newOwner.id == playerGang.id then
    return
  end

  for _, member in ipairs(newOwner.members or {}) do
    local memberServerId = PlayerIdToServerId[member.identifier]
    if memberServerId then
      Framework.ShowAdvancedNotification(
        memberServerId,
        Locale.NOTIFICATION_LOYALTY_TITLE,
        zone.label,
        Locale["NOTIFICATION_LOYALTY_RIVAL_" .. actionKey]
      )
    end
  end
end

function DecreaseLoyalty(source, zone, actionKey, amount, multiplier)
  if multiplier == 0 then
    return
  end

  local playerGang = ServerIdToGang[source]
  if not playerGang then
    return
  end

  if not (Config.DecreaseMultipliers and Config.DecreaseMultipliers[actionKey]) then
    return
  end

  local ownerGang = GetGangAtZone(zone)
  if not ownerGang then
    return
  end

  local ownerKey = zone.name .. "." .. ownerGang.id
  local attackerKey = zone.name .. "." .. playerGang.id

  local ownerEntry = Zones[ownerKey]
  local attackerEntry = Zones[attackerKey]

  local dec = math.max(1, math.ceil(amount * multiplier))

  if attackerEntry then
    if dec < attackerEntry.loyalty then
      attackerEntry.loyalty = attackerEntry.loyalty - dec
      SQL.SetZoneLoyalty(playerGang.id, zone.name, attackerEntry.loyalty)

      TriggerClientEvent("rcore_gangs:client:set_zone", -1, attackerKey, attackerEntry)
    else
      Zones[attackerKey] = nil
      SQL.DeleteZone(playerGang.id, zone.name)

      TriggerClientEvent("rcore_gangs:client:set_zone", -1, attackerKey, nil)
    end

    Framework.ShowAdvancedNotification(
      source,
      Locale.NOTIFICATION_LOYALTY_TITLE,
      zone.label,
      Locale["NOTIFICATION_LOYALTY_DECREASED_" .. actionKey]
    )
  end

  if ownerGang.id == playerGang.id then
    return
  end

  if not (Config.DecreaseLoyaltyOfOwner and Config.DecreaseLoyaltyOfOwner[actionKey]) then
    return
  end

  if ownerEntry then
    if dec < ownerEntry.loyalty then
      ownerEntry.loyalty = ownerEntry.loyalty - dec
      SQL.SetZoneLoyalty(ownerGang.id, zone.name, ownerEntry.loyalty)

      TriggerClientEvent("rcore_gangs:client:set_zone", -1, ownerKey, ownerEntry)
    else
      Zones[ownerKey] = nil
      SQL.DeleteZone(ownerGang.id, zone.name)

      TriggerClientEvent("rcore_gangs:client:set_zone", -1, ownerKey, nil)
    end

    for _, member in ipairs(ownerGang.members or {}) do
      local memberServerId = PlayerIdToServerId[member.identifier]
      if memberServerId then
        Framework.ShowAdvancedNotification(
          memberServerId,
          Locale.NOTIFICATION_LOYALTY_TITLE,
          zone.label,
          Locale["NOTIFICATION_LOYALTY_RIVAL_" .. actionKey]
        )
      end
    end
  end
end

function SetLoyalty(gangId, zone, loyalty)
  if not zone then
    return
  end

  local targetGang = nil
  for _, gang in pairs(Gangs) do
    local expectedId = gangId
    if expectedId == nil then
      expectedId = -1
    end

    if gang.id == expectedId then
      targetGang = gang
    end
  end

  for _, gang in pairs(Gangs) do
    local zoneKey = zone.name .. "." .. gang.id
    local entry = Zones[zoneKey]

    if entry then
      if gangId == nil then
        targetGang = gang
      end

      SQL.DeleteZone(gang.id, zone.name)
      Zones[zoneKey] = nil
      break
    end
  end

  if loyalty <= 0 then
    if targetGang then
      TriggerClientEvent("rcore_gangs:client:set_zones", -1, Zones)
    end
    return
  end

  if not targetGang then
    return
  end

  SQL.InsertZone(targetGang.id, zone.name, loyalty)

  local zoneKey = zone.name .. "." .. targetGang.id
  Zones[zoneKey] = {
    name = zone.name,
    gangId = targetGang.id,
    gangName = targetGang.name,
    gangColor = targetGang.color,
    loyalty = loyalty
  }

  TriggerClientEvent("rcore_gangs:client:set_zone", -1, zoneKey, Zones[zoneKey])
end

function GetGangLoyaltyAtZone(gangId, zoneName)
  local rows = SQL.GetZoneLoyalty(gangId, zoneName)
  if rows and rows[1] then
    return rows[1].loyalty
  end
  return 0
end

exports("GetGangLoyaltyAtZone", GetGangLoyaltyAtZone)

AddEventHandler("rcore_gangs:server:player_loaded", function(serverId, playerIdentifier)
  if not serverId or not playerIdentifier then
    return
  end

  PlayerIdToServerId[playerIdentifier] = serverId
  ServerIdToPlayerId[serverId] = playerIdentifier

  local playerGang = GetPlayerGang(serverId)

  PlayerIdToGang[playerIdentifier] = playerGang
  ServerIdToGang[serverId] = playerGang

  if Config.OverrideGangs then
    Framework.SetPlayerGang(serverId, playerGang)
  end

  TriggerClientEvent("rcore_gangs:client:set_gang", serverId, playerGang)
  TriggerClientEvent("rcore_gangs:client:set_zones", serverId, Zones)
  TriggerClientEvent("rcore_gangs:client:set_deaths", serverId, deathStateByServerId)
  TriggerClientEvent("rcore_gangs:client:player_loaded", serverId, playerIdentifier)
end)

function CreatePlayerGangData(source)
  local serverId = source
  local playerIdentifier = Framework.GetPlayerId(serverId)

  while not playerIdentifier do
    Wait(5000)

    local stillConnected = false
    for _, sid in ipairs(GetPlayers()) do
      if tonumber(sid) == tonumber(serverId) then
        stillConnected = true
        break
      end
    end

    if not stillConnected then
      return
    end

    playerIdentifier = Framework.GetPlayerId(serverId)
  end

  TriggerEvent("rcore_gangs:server:player_loaded", serverId, playerIdentifier)
end

RegisterNetEvent("esx:onPlayerJoined", function(serverId)
  CreatePlayerGangData(serverId)
end)

AddEventHandler("QBCore:Server:PlayerLoaded", function(player)
  CreatePlayerGangData(player.PlayerData.source)
end)

AddEventHandler("playerJoining", function()
  CreatePlayerGangData(source)
end)

function WipePlayerGangData(source)
  local serverId = source
  local playerIdentifier = ServerIdToPlayerId[serverId]

  if not playerIdentifier or not serverId then
    return
  end

  TriggerEvent("rcore_gangs:client:player_left", serverId, playerIdentifier)
  TriggerClientEvent("rcore_gangs:client:player_left", -1, serverId, playerIdentifier)

  PlayerIdToServerId[playerIdentifier] = nil
  ServerIdToPlayerId[serverId] = nil

  PlayerIdToGang[playerIdentifier] = nil
  ServerIdToGang[serverId] = nil

  deathStateByServerId[serverId] = nil
end

AddEventHandler("playerDropped", function()
  WipePlayerGangData(source)
end)

AddEventHandler("esx:playerLogout", function(serverId)
  WipePlayerGangData(serverId)
end)

AddEventHandler("QBCore:Server:OnPlayerUnload", function(serverId)
  WipePlayerGangData(serverId)
end)

AddEventHandler("rcore_gangs:server:database_ready", function()
  for _, gang in ipairs(SQL.GetGangs()) do
    Gangs[gang.id] = gang
    Gangs[gang.id].members = SQL.GetGangMembers(gang.id)

    for index, member in pairs(Gangs[gang.id].members or {}) do
      if not DoesPlayerRankExist(member.group, member.rank) then
        SQL.SetPlayerGang(member.identifier, json.encode({
          id = gang.id,
          rank = Config.RanksGroups[member.group].ranks[1].label,
          group = member.group
        }))

        Gangs[gang.id].members[index] = {
          identifier = member.identifier,
          name = member.name,
          rank = Config.RanksGroups[member.group].ranks[1].label,
          group = member.group
        }
      end
    end

    if gang.group then
      gang.ranks = Config.RanksGroups[gang.group].ranks
    else
      if Config.GangRanks then
        gang.ranks = Config.GangRanks
      else
        for _, groupCfg in pairs(Config.RanksGroups) do
          if groupCfg.default then
            gang.group = groupCfg.name
            gang.ranks = groupCfg.ranks
            break
          end
        end
      end
    end

    if gang.vehicles then
      gang.vehicles = json.decode(gang.vehicles)
    else
      gang.vehicles = {}
    end

    if gang.checkpoints then
      gang.checkpoints = json.decode(gang.checkpoints)

      if gang.checkpoints.garage then
        gang.garage = vec3(gang.checkpoints.garage.x, gang.checkpoints.garage.y, gang.checkpoints.garage.z)
      end

      if gang.checkpoints.storage then
        gang.storage = vec3(gang.checkpoints.storage.x, gang.checkpoints.storage.y, gang.checkpoints.storage.z)
      end

      if gang.checkpoints.reserve then
        gang.reserve = vec3(gang.checkpoints.reserve.x, gang.checkpoints.reserve.y, gang.checkpoints.reserve.z)
      end

      gang.checkpoints = nil
    end
  end

  for _, zone in ipairs(SQL.GetZones()) do
    Zones[zone.name .. "." .. zone.gangId] = zone
  end
end)

AddEventHandler("rcore_gangs:server:framework_ready", function()
  if Config.OverrideGangs then
    for _, gang in pairs(Gangs) do
      Framework.CreateGang(gang)
    end
  end

  for _, serverIdStr in pairs(Framework.GetPlayers()) do
    Wait(0)

    local serverId = tonumber(serverIdStr)
    local playerIdentifier = Framework.GetPlayerId(serverId)

    if playerIdentifier and serverId then
      PlayerIdToServerId[playerIdentifier] = serverId
      ServerIdToPlayerId[serverId] = playerIdentifier

      local playerGang = GetPlayerGang(serverId)

      PlayerIdToGang[playerIdentifier] = playerGang
      ServerIdToGang[serverId] = playerGang

      if Config.OverrideGangs then
        Framework.SetPlayerGang(serverId, playerGang)
      end

      TriggerClientEvent("rcore_gangs:client:set_gang", serverId, playerGang)
      TriggerClientEvent("rcore_gangs:client:set_zones", serverId, Zones)

      for deadServerId, isDead in pairs(deathStateByServerId) do
        Wait(0)
        TriggerClientEvent("rcore_gangs:client:set_death", serverId, deadServerId, isDead)
      end

      TriggerClientEvent("rcore_gangs:client:player_loaded", serverId, playerIdentifier)
    end
  end
end)

CreateThread(function()
  AddEventHandler("QBCore:Player:SetPlayerData", function(playerData)
    local serverId = playerData.source

    local previous = deathStateByServerId[serverId]
    local current = (playerData.metadata and (playerData.metadata.isdead or playerData.metadata.inlaststand)) == true

    deathStateByServerId[serverId] = current

    if current ~= previous then
      TriggerClientEvent("rcore_gangs:client:set_death", -1, serverId, current)
    end
  end)

  while true do
    if not (Config.ZoneOptions and Config.ZoneOptions.hourlyDecay) then
      break
    end

    if not (Config.ZoneOptions.hourlyDecay > 0) then
      break
    end

    Wait(3600000)

    for zoneKey, zoneEntry in pairs(Zones) do
      Wait(0)

      local decay = math.max(1, math.floor((zoneEntry.loyalty * Config.ZoneOptions.hourlyDecay) / 100))

      if decay < zoneEntry.loyalty then
        zoneEntry.loyalty = zoneEntry.loyalty - decay
        SQL.SetZoneLoyalty(zoneEntry.gangId, zoneEntry.name, zoneEntry.loyalty)
      else
        Zones[zoneKey] = nil
        SQL.DeleteZone(zoneEntry.gangId, zoneEntry.name)
      end
    end

    TriggerClientEvent("rcore_gangs:client:set_zones", -1, Zones)
  end
end, SessionNames.ZONE_LOYALTY_MANAGEMENT)

Citizen.CreateThread(function()
  if not Config.IncreaseMultipliersRivalry then
    Config.IncreaseMultipliersRivalry = Config.IncreaseMultipliers
  end

  if not Config.DecreaseMultipliersRivalry then
    Config.DecreaseMultipliersRivalry = Config.DecreaseMultipliers
  end
end)