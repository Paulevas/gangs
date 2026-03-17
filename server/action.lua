-- ==============================================================
-- actions.lua (server) - refactor, same behavior
-- ==============================================================

local baggedByPlayerId = {}    -- [targetPlayerId] = baggerPlayerId
local restrainedByPlayerId = {} -- [targetPlayerId] = restrainerPlayerId
local escortedByPlayerId = {}   -- [targetPlayerId] = escorterPlayerId

function GetInventoryItemCount(item)
  if not item then return 0 end
  return item.amount or item.count or 0
end

function ConsumeRequiredItemOrNotify(source, itemName, missingMessage)
  if not itemName then return true end

  local trimmed = itemName:strtrim()
  if trimmed:len() <= 0 then
    return true
  end

  local item = Inventory.GetPlayerItem(source, itemName)
  if GetInventoryItemCount(item) < 1 then
    Framework.ShowNotification(source, missingMessage)
    return false
  end

  Inventory.RemovePlayerItem(source, itemName, 1)
  return true
end

function GetPlayerIdFromServerId(serverId)
  return ServerIdToPlayerId and ServerIdToPlayerId[serverId] or nil
end

function GetServerIdFromPlayerId(playerId)
  return PlayerIdToServerId and PlayerIdToServerId[playerId] or nil
end

function IsPlayerBagged(serverId)
  local playerId = GetPlayerIdFromServerId(serverId)
  if playerId then
    return baggedByPlayerId[playerId]
  end

  return baggedByPlayerId[serverId]
end

function IsPlayerRestrained(serverId)
  local playerId = GetPlayerIdFromServerId(serverId)
  if playerId then
    return restrainedByPlayerId[playerId]
  end

  return restrainedByPlayerId[serverId]
end

function IsPlayerEscorted(serverId)
  local playerId = GetPlayerIdFromServerId(serverId)
  if playerId then
    return escortedByPlayerId[playerId]
  end

  return escortedByPlayerId[serverId]
end

function UnbagPlayer(actorServerId, targetServerId)
  if not IsPlayerBagged(targetServerId) then return end

  local targetPlayerId = GetPlayerIdFromServerId(targetServerId)
  if targetPlayerId then
    baggedByPlayerId[targetPlayerId] = nil
  else
    baggedByPlayerId[targetServerId] = nil
  end

  TriggerClientEvent("rcore_gangs:client:bag", -1, actorServerId, targetServerId, false)
end

function UnrestrainPlayer(actorServerId, targetServerId)
  if not IsPlayerRestrained(targetServerId) then return end

  local targetPlayerId = GetPlayerIdFromServerId(targetServerId)
  if targetPlayerId then
    restrainedByPlayerId[targetPlayerId] = nil
  else
    restrainedByPlayerId[targetServerId] = nil
  end

  TriggerClientEvent("rcore_gangs:client:restrain", -1, actorServerId, targetServerId, false)
end

function UnescortPlayer(actorServerId, targetServerId)
  local escorterPlayerId = IsPlayerEscorted(targetServerId)
  if not escorterPlayerId then return end

  local targetPlayerId = GetPlayerIdFromServerId(targetServerId) or targetServerId
  escortedByPlayerId[targetPlayerId] = nil

  TriggerClientEvent("rcore_gangs:client:escorted", -1, targetServerId, nil)

  local escorterServerId = GetServerIdFromPlayerId(escorterPlayerId)
  local targetServerIdResolved = GetServerIdFromPlayerId(targetPlayerId)

  TriggerClientEvent("rcore_gangs:client:escort", escorterServerId, targetServerIdResolved, false)
  TriggerClientEvent("rcore_gangs:client:escort_by", targetServerIdResolved, escorterServerId, false)
end

-- Exports (names unchanged)
exports("UnescortPlayer", UnescortPlayer)
exports("UnrestrainPlayer", UnrestrainPlayer)
exports("UnbagPlayer", UnbagPlayer)

-- ==============================================================
-- Command: free player
-- ==============================================================

local freePlayerCommand = (Config.Commands and Config.Commands.FREEPLAYER) or "freeplayer"

RegisterCommand(freePlayerCommand, function(source, args)
  if not Framework.IsPlayerAllowed(source) then
    Framework.ShowNotification(source, Locale.COMMAND_MISSING_PERMS)
    return
  end

  local targetServerId = args and args[1] and tonumber(args[1]) or nil
  if not targetServerId then return end

  UnbagPlayer(source, targetServerId)
  UnrestrainPlayer(source, targetServerId)
  UnescortPlayer(source, targetServerId)
end)

-- ==============================================================
-- Server events (names unchanged)
-- ==============================================================

RegisterNetEvent("rcore_gangs:server:rob")
AddEventHandler("rcore_gangs:server:rob", function(targetServerId)
  Framework.ShowNotification(targetServerId, Locale.ACTIONS_TARGET_SEARCH)
end)

RegisterNetEvent("rcore_gangs:server:bag")
AddEventHandler("rcore_gangs:server:bag", function(targetServerId, enabled)
  local actorServerId = source

  local targetPlayerId = GetPlayerIdFromServerId(targetServerId)
  local actorPlayerId = GetPlayerIdFromServerId(actorServerId)
  if not targetPlayerId or not actorPlayerId then return end

  if enabled then
    if Config.GangOptions and Config.GangOptions.paperBag then
      if not ConsumeRequiredItemOrNotify(actorServerId, Config.GangOptions.paperBag, Locale.ACTIONS_MISSING_BAG) then
        return
      end
    end

    baggedByPlayerId[targetPlayerId] = actorPlayerId
  else
    baggedByPlayerId[targetPlayerId] = nil
  end

  TriggerClientEvent("rcore_gangs:client:bag", -1, actorServerId, targetServerId, enabled)
end)

RegisterNetEvent("rcore_gangs:server:restrain")
AddEventHandler("rcore_gangs:server:restrain", function(targetServerId, enabled)
  local actorServerId = source

  local actorCoords = GetEntityCoords(GetPlayerPed(actorServerId))
  local targetCoords = GetEntityCoords(GetPlayerPed(targetServerId))
  if #(actorCoords - targetCoords) >= 10.0 then
    return
  end

  local targetPlayerId = GetPlayerIdFromServerId(targetServerId)
  local actorPlayerId = GetPlayerIdFromServerId(actorServerId)
  if not targetPlayerId or not actorPlayerId then return end

  if enabled then
    if Config.GangOptions and Config.GangOptions.zipTie then
      if not ConsumeRequiredItemOrNotify(actorServerId, Config.GangOptions.zipTie, Locale.ACTIONS_MISSING_TIE) then
        return
      end
    end

    restrainedByPlayerId[targetPlayerId] = actorPlayerId
  else
    restrainedByPlayerId[targetPlayerId] = nil
  end

  TriggerClientEvent("rcore_gangs:client:restrain", -1, actorServerId, targetServerId, enabled)
end)

RegisterNetEvent("rcore_gangs:server:escort")
AddEventHandler("rcore_gangs:server:escort", function(targetServerId, enabled)
  local actorServerId = source

  local targetPlayerId = GetPlayerIdFromServerId(targetServerId)
  local actorPlayerId = GetPlayerIdFromServerId(actorServerId)
  if not targetPlayerId or not actorPlayerId then return end

  if enabled then
    escortedByPlayerId[targetPlayerId] = actorPlayerId
    TriggerClientEvent("rcore_gangs:client:escorted", -1, targetServerId, actorServerId)
  else
    escortedByPlayerId[targetPlayerId] = nil
    TriggerClientEvent("rcore_gangs:client:escorted", -1, targetServerId, nil)
  end

  TriggerClientEvent("rcore_gangs:client:escort", actorServerId, targetServerId, enabled)
  TriggerClientEvent("rcore_gangs:client:escort_by", targetServerId, actorServerId, enabled)
end)

RegisterNetEvent("rcore_gangs:server:transport")
AddEventHandler("rcore_gangs:server:transport", function(targetServerId, transportType, transportState)
  local actorServerId = source

  local targetPlayerId = GetPlayerIdFromServerId(targetServerId)
  local actorPlayerId = GetPlayerIdFromServerId(actorServerId)
  if not targetPlayerId or not actorPlayerId then return end

  if transportState then
    escortedByPlayerId[targetPlayerId] = nil

    TriggerClientEvent("rcore_gangs:client:escorted", -1, targetServerId, nil)
    TriggerClientEvent("rcore_gangs:client:escort", actorServerId, targetServerId, not transportState)
    TriggerClientEvent("rcore_gangs:client:escort_by", targetServerId, actorServerId, not transportState)

    Wait(500)
    TriggerClientEvent("rcore_gangs:client:transport", -1, targetServerId, transportType, transportState)
  else
    TriggerClientEvent("rcore_gangs:client:transport", -1, targetServerId, transportType, transportState)

    Wait(500)

    escortedByPlayerId[targetPlayerId] = actorPlayerId
    TriggerClientEvent("rcore_gangs:client:escorted", -1, targetServerId, actorServerId)
    TriggerClientEvent("rcore_gangs:client:escort", actorServerId, targetServerId, not transportState)
    TriggerClientEvent("rcore_gangs:client:escort_by", targetServerId, actorServerId, not transportState)
  end
end)

function SyncActionsToPlayer(targetServerId)
  for targetPlayerId, actorPlayerId in pairs(baggedByPlayerId) do
    TriggerClientEvent(
      "rcore_gangs:client:bag",
      targetServerId,
      GetServerIdFromPlayerId(actorPlayerId),
      GetServerIdFromPlayerId(targetPlayerId),
      true
    )
  end

  for targetPlayerId, actorPlayerId in pairs(restrainedByPlayerId) do
    TriggerClientEvent(
      "rcore_gangs:client:restrain",
      targetServerId,
      GetServerIdFromPlayerId(actorPlayerId),
      GetServerIdFromPlayerId(targetPlayerId),
      true
    )
  end

  for targetPlayerId, actorPlayerId in pairs(escortedByPlayerId) do
    TriggerClientEvent(
      "rcore_gangs:client:escorted",
      targetServerId,
      GetServerIdFromPlayerId(targetPlayerId),
      GetServerIdFromPlayerId(actorPlayerId)
    )
  end
end

RegisterNetEvent("rcore_gangs:server:player_loaded")
AddEventHandler("rcore_gangs:server:player_loaded", function(targetServerId)
  local resolvedTarget = targetServerId or source
  SyncActionsToPlayer(resolvedTarget)
end)

AddEventHandler("rcore_gangs:client:player_left", function(_, leftPlayerId)
  baggedByPlayerId[leftPlayerId] = nil
  restrainedByPlayerId[leftPlayerId] = nil
  escortedByPlayerId[leftPlayerId] = nil

  for targetPlayerId, actorPlayerId in pairs(baggedByPlayerId) do
    if actorPlayerId == leftPlayerId then
      baggedByPlayerId[targetPlayerId] = nil
      break
    end
  end

  for targetPlayerId, actorPlayerId in pairs(restrainedByPlayerId) do
    if actorPlayerId == leftPlayerId then
      restrainedByPlayerId[targetPlayerId] = nil
      break
    end
  end

  for targetPlayerId, actorPlayerId in pairs(escortedByPlayerId) do
    if actorPlayerId == leftPlayerId then
      escortedByPlayerId[targetPlayerId] = nil
      break
    end
  end
end)

-- ==============================================================
-- ox_target integration patch (same logic)
-- ==============================================================

CreateThread(function()
  local state = GetResourceState("ox_target")
  if state ~= "starting" and state ~= "started" then
    return
  end

  local api = LoadResourceFile("ox_target", "client/api.lua")
  if not api then return end

  local hasPlayersBlock = api:find([[
return%s-{
%s-global%s-=%s-Players
%s-}]])
  if not hasPlayersBlock then return end

  local removeStart, removeEnd = api:find([[
if%s-_type%s-==%s-1%s-then.-end
%s-end
]])
  if removeStart and removeEnd then
    api = api:sub(1, removeStart - 1) .. api:sub(removeEnd + 1)
  end

  local pedsStart, pedsEnd = api:find("global%s-=%s-Peds")
  if not pedsStart or not pedsEnd then return end

  local prefix = api:sub(1, pedsStart - 1)
  local injected = [[
if IsPedAPlayer(entity) then
			global = Players
		else
			global = Peds
		end]]
  local suffix = api:sub(pedsEnd + 1)

  api = prefix .. injected .. suffix

  SaveResourceFile("ox_target", "client/api.lua", api, -1)
  print("^2[GANGS] TARGET INTEGRATED, PLEASE RESTART YOUR SERVER!^7")
end, SessionNames.OX_INTEGRATION)
