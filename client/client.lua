-- client.lua

Gang = nil
Zone = nil

Zones = {}
CachedPeds = {}
IteratedPeds = {}

Intervals = {
  setHud = 0,
  setZone = 0,
  action = 0,
  entity = 0,
  checkpoint = 0,
  protection = 0,
  target = 0,
  targetArea = 0,
  renderMenu = 0
}

Identifier = nil

local isPlayerLoaded = false
local deathCacheByPlayerId = {}

function SortGangPresenceByLoyalty(a, b)
  return a.loyalty > b.loyalty
end

function SetZones()
  local gangPresenceByZoneName = {}
  local topGangByZoneName = {}
  local topRivalByZoneName = {}
  local localGangLoyaltyByZoneName = {}

  DebugLog("^1SetZones()^7 First cycle")

  for _, zoneEntry in pairs(Zones) do
    Wait(0)

    local zoneName = zoneEntry.name
    local existingTop = topGangByZoneName[zoneName]

    if existingTop then
      if existingTop.loyalty < zoneEntry.loyalty then
        existingTop.loyalty = zoneEntry.loyalty
        existingTop.gangName = zoneEntry.gangName
        existingTop.gangColor = zoneEntry.gangColor
      end
    else
      topGangByZoneName[zoneName] = {
        loyalty = zoneEntry.loyalty,
        gangName = zoneEntry.gangName,
        gangColor = zoneEntry.gangColor
      }
    end

    if not topGangByZoneName[zoneName].totalLoyalty then
      topGangByZoneName[zoneName].totalLoyalty = 0
    end
    topGangByZoneName[zoneName].totalLoyalty = topGangByZoneName[zoneName].totalLoyalty + zoneEntry.loyalty

    if not gangPresenceByZoneName[zoneName] then
      gangPresenceByZoneName[zoneName] = {}
    end

    gangPresenceByZoneName[zoneName][#gangPresenceByZoneName[zoneName] + 1] = {
      name = zoneEntry.gangName,
      color = zoneEntry.gangColor,
      loyalty = zoneEntry.loyalty
    }
    table.sort(gangPresenceByZoneName[zoneName], SortGangPresenceByLoyalty)

    if Gang and Gang.id == zoneEntry.gangId then
      localGangLoyaltyByZoneName[zoneName] = zoneEntry.loyalty
    end
  end

  DebugLog("^1SetZones()^7 Second cycle")

  for _, zoneEntry in pairs(Zones) do
    Wait(0)

    local zoneName = zoneEntry.name
    local top = topGangByZoneName[zoneName]

    if top and top.gangName ~= zoneEntry.gangName then
      local existingRival = topRivalByZoneName[zoneName]
      if existingRival then
        if existingRival.loyalty < zoneEntry.loyalty then
          existingRival.loyalty = zoneEntry.loyalty
        end
      else
        topRivalByZoneName[zoneName] = {
          loyalty = zoneEntry.loyalty,
          gangName = zoneEntry.gangName,
          gangColor = zoneEntry.gangColor
        }
      end
    end
  end

  DebugLog("^1SetZones()^7 Third cycle")

  for zoneKey, zoneData in pairs(Config.GangZones) do
    local top = topGangByZoneName[zoneKey]

    if top then
      zoneData.gangName = top.gangName
      zoneData.gangColor = top.gangColor
      zoneData.totalLoyalty = top.totalLoyalty

      zoneData.gangOwnership = math.floor((top.loyalty / top.totalLoyalty) * 100 + 0.5)

      local rival = topRivalByZoneName[zoneKey]
      if rival then
        zoneData.rivalGangOwnership = math.floor((rival.loyalty / top.totalLoyalty) * 100 + 0.5)
      else
        zoneData.rivalGangOwnership = 0
      end

      local localLoyalty = localGangLoyaltyByZoneName[zoneKey]
      if localLoyalty then
        zoneData.localGangOwnership = math.floor((localLoyalty / top.totalLoyalty) * 100 + 0.5)
      else
        zoneData.localGangOwnership = 0
      end
    else
      zoneData.gangName = nil
      zoneData.gangColor = nil
      zoneData.totalLoyalty = nil
      zoneData.gangOwnership = nil
      zoneData.rivalGangOwnership = nil
      zoneData.localGangOwnership = nil
    end

    zoneData.gangPresence = gangPresenceByZoneName[zoneKey] or nil
  end
end

_IsPlayerDead = IsPlayerDead
function IsPlayerDead(playerId)
  local cached = deathCacheByPlayerId[playerId]
  if cached == nil then
    return _IsPlayerDead(playerId)
  end
  return cached
end

RegisterNetEvent("rcore_gangs:client:advanced_notification")
AddEventHandler("rcore_gangs:client:advanced_notification", function(message, sender, subject, textureDict, iconType)
  Framework.ShowAdvancedNotification(message, sender, subject, textureDict, iconType)
end)

RegisterNetEvent("rcore_gangs:client:set_gang")
AddEventHandler("rcore_gangs:client:set_gang", function(gang)
  DebugLog("-------")
  DebugLog("^3(set_gang event):^7 gang: ^3%s^7 (exp tbl/nil)", gang)

  Gang = gang

  DebugLog("^3(set_gang event):^7 Variable Gang: ^3%s^7 (exp tbl/nil)", Gang)

  if not Gang then
    Menu.CloseMenu()
  end

  SetZones()
  RenderZones()
end)

function SetZone(name, zoneData)
  DebugLog("-------")
  DebugLog("^3(set_zone event):^7 Name: ^3%s^7 (exp string), Zone: ^3%s^7 (exp tbl)", name, zoneData)
  DebugLog("^3(set_zone event):^7 Variable Zones: ^3%s^7 (exp tbl)", Zones)

  if not Zones then
    Zones = {}
  end

  Zones[name] = zoneData

  DebugLog("====")

  SetZones()
  DebugLog("^1SetZones()^7 called successfully")

  RenderZones()
  DebugLog("^1RenderZones()^7 called successfully")
end

RegisterNetEvent("rcore_gangs:client:set_zone")
AddEventHandler("rcore_gangs:client:set_zone", function(name, zoneData)
  SetZone(name, zoneData)
end)

RegisterNetEvent("rcore_gangs:client:set_zones")
AddEventHandler("rcore_gangs:client:set_zones", function(zones)
  if zones then
    Zones = zones
    SetZones()
    RenderZones()
    return
  end

  error("The zones from 'rcore_gangs:client:set_zones' are nil!")
end)

RegisterNetEvent("rcore_gangs:client:set_zones_update")
AddEventHandler("rcore_gangs:client:set_zones_update", function(updatePayload)
  for _, entry in pairs(updatePayload) do
    SetZone(entry[1], entry[2])
  end
end)

RegisterNetEvent("rcore_gangs:client:set_death")
AddEventHandler("rcore_gangs:client:set_death", function(serverId, isDead)
  local playerId = GetPlayerFromServerId(serverId)
  deathCacheByPlayerId[playerId] = isDead
end)

RegisterNetEvent("rcore_gangs:client:set_deaths")
AddEventHandler("rcore_gangs:client:set_deaths", function(deaths)
  for serverId, isDead in pairs(deaths) do
    local playerId = GetPlayerFromServerId(serverId)
    deathCacheByPlayerId[playerId] = isDead
  end
end)

RegisterNetEvent("rcore_gangs:client:player_loaded")
AddEventHandler("rcore_gangs:client:player_loaded", function(identifier)
  Identifier = identifier
  isPlayerLoaded = true
end)

AddEventHandler("gameEventTriggered", function(eventName, args)
  if eventName ~= "CEventNetworkEntityDamage" then
    return
  end

  local victimEntity = args[1]
  local damageFlag = args[6]
  if damageFlag == 0 then
    return
  end

  if CachedPeds[victimEntity] then
    CachedPeds[victimEntity] = nil
    TargetDrugs(victimEntity, false, false)
  end
end)

AddEventHandler("rcore_gangs:client:disable_actions", function(disable)
  if disable then
    Intervals.target = math.huge
    Intervals.targetArea = math.huge

    for ped in pairs(CachedPeds) do
      CachedPeds[ped] = nil
      TargetDrugs(ped, false, false)
      TargetActions(ped, false)
    end

    return
  end

  local now = GetGameTimer()
  Intervals.target = now
  Intervals.targetArea = now
end)

function HandleIteratedPedsNewIndex(_, ped, distance)
  local alreadyCached = CachedPeds[ped]

  if alreadyCached then
    if distance == nil then
      CachedPeds[ped] = nil

      if IsPedAPlayer(ped) then
        if Gang then
          TargetActions(ped, false)
        end
      else
        TargetDrugs(ped, false, false)
      end
    end

    return
  end

  if distance then
    CachedPeds[ped] = distance

    if IsPedAPlayer(ped) then
      if Gang then
        TargetActions(ped, true)
      end
    else
      TargetDrugs(ped, true, false)
    end
  end
end

setmetatable(IteratedPeds, { __newindex = HandleIteratedPedsNewIndex })

CreateThread(function()
  local ignoreModelMap = {}
  local ignoreList = Config.IgnorePedModelsForDrugSale

  if not ignoreList then
    print("Please update properly config.lua, you're missing variable 'Config.IgnorePedModelsForDrugSale'!")
    Config.IgnorePedModelsForDrugSale = {}
    ignoreList = Config.IgnorePedModelsForDrugSale
  end

  for _, model in pairs(ignoreList) do
    if type(model) == "string" then
      ignoreModelMap[GetHashKey(model)] = true
    else
      ignoreModelMap[model] = true
    end
  end

  Config.IgnorePedModelsForDrugSale = ignoreModelMap
end, "converting array into more dev friendly one")

CreateThread(function()
  while true do
    Wait(1000)

    if isPlayerLoaded then
      local ped = PlayerPedId()
      local coords = GetEntityCoords(ped)

      if Gang then
        if Zone then
          Zone = GetIsZoneAtPosition(coords, Zone)
        else
          Zone = GetZoneAtPosition(coords)
        end

        if Zone then
          if Zone ~= zone then
            TriggerEvent("rcore_gangs:client:zone_changed")
          end
        end
      end
    end
  end
end, "ZoneManagement")

CreateThread(function()
  while true do
    Wait(0)

    if not IsPlayerCloseToCheckpoint and not IsCloseToAnyBusiness then
      Wait(1000)
    end

    if isPlayerLoaded and Gang then
      RenderBusiness()
      RenderCheckpoint()
    end
  end
end, "BusinessCheckpointRendering")

CreateThread(function()
  while true do
    Wait(1000)

    if isPlayerLoaded then
      local enableDrugs = Config.TargetOptions and Config.TargetOptions.enableDrugs
      local enableActions = Config.TargetOptions and Config.TargetOptions.enableActions

      if enableDrugs or enableActions then
        local allowDrugTargeting = false
        if enableDrugs then
          allowDrugTargeting = TargetDrugsOptions()
        end

        for ped in pairs(CachedPeds) do
          if DoesEntityExist(ped) then
            if IsPedAPlayer(ped) then
              if Gang then
                TargetActions(ped, true)
              end
            elseif allowDrugTargeting then
              TargetDrugs(ped, true, true)
            end
          else
            CachedPeds[ped] = nil
            TargetDrugs(ped, false, false)
            TargetActions(ped, false)
          end
        end
      end
    end
  end
end, "TargetOptionsProcessing")

CreateThread(function()
  while true do
    Wait(5000)

    if isPlayerLoaded then
      local enableDrugs = Config.TargetOptions and Config.TargetOptions.enableDrugs
      local enableActions = Config.TargetOptions and Config.TargetOptions.enableActions

      if enableDrugs or enableActions then
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        local peds = GetGamePool("CPed")
        for _, ped in ipairs(peds) do
          if ped ~= playerPed then
            local pedCoords = GetEntityCoords(ped)
            local distance = glm.distance(playerCoords, pedCoords)

            local ignored = Config.IgnorePedModelsForDrugSale[GetEntityModel(ped)]
            if not ignored then
              if distance < 25.0 then
                IteratedPeds[ped] = distance
              else
                IteratedPeds[ped] = nil
              end
            end
          end
        end
      end
    end
  end
end, "PedAreaCaching")

CreateThread(function()
  while true do
    Wait(0)

    if not IsPlayerRestrictedBySomeAction() then
      Wait(1000)
    end

    if isPlayerLoaded then
      if Config.GangOptions and Config.GangOptions.kidnapping then
        Actions()
      end
    end
  end
end, "KidnappingActions")

CreateThread(function()
  while true do
    Wait(1000)

    if isPlayerLoaded then
      if Config.GangOptions and Config.GangOptions.kidnapping then
        ActionsEntities()
      end
    end
  end
end, "KidnappingActions entities")

CreateThread(function()
  while true do
    Wait(0)

    if not ShouldBeZoneRendered then
      Wait(500)
    end

    if isPlayerLoaded then
      if Config.ZoneOptions and Config.ZoneOptions.showHudInfo then
        local now = GetGameTimer()
        if now > Intervals.setHud then
          Intervals.setHud = now + 500
          SetZoneHud()
        end

        RenderZoneHud()
      end
    end
  end
end, "HUDRendering")

CreateThread(function()
  while true do
    Wait(0)

    local now = GetGameTimer()
    if now > Intervals.renderMenu then
      local currentMenu = Menu.CurrentMenu()
      if currentMenu then
        GangMenu(currentMenu)
        DrugMenu(currentMenu)
        BusinessMenu(currentMenu)
        CheckpointMenu(currentMenu)
        Menu.Display()
      else
        Intervals.renderMenu = now + 500
      end
    else
      Wait(33)
    end
  end
end)