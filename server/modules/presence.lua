-- server/presence.lua

local PresenceState = {}

function UpdatePlayerPresence(serverId, zone)
  if not PresenceState[serverId] then
    PresenceState[serverId] = {}
  end

  local state = PresenceState[serverId]
  local zoneName = zone.name

  if state[zoneName] == nil then
    state[zoneName] = 0
  end

  if state.capturedZone ~= zoneName then
    state[zoneName] = state[zoneName] + 1
  end

  local presenceThreshold = (Config.ZoneOptions.presenceTime / 5)

  if not state.capturedZone then
    if state[zoneName] == presenceThreshold then
      state.capturedZone = zoneName

      local rivalry = GetRivalry(zoneName)

      local increaseMultiplier = Config.IncreaseMultipliers.PRESENCE
      if rivalry then
        increaseMultiplier = Config.IncreaseMultipliersRivalry.PRESENCE
      end

      IncreaseLoyalty(serverId, zone, "PRESENCE", 1.0, increaseMultiplier)
    end
    return
  end

  local totalPresenceTicks = 0
  for _, value in pairs(state) do
    if type(value) == "number" then
      totalPresenceTicks = totalPresenceTicks + value
    end
  end

  if totalPresenceTicks > presenceThreshold then
    PresenceState[serverId] = {}
  end
end

AddEventHandler("playerDropped", function()
  PresenceState[source] = nil
end)

CreateThread(function()
  while true do
    Wait(300000)

    for serverId in pairs(ServerIdToGang) do
      Wait(0)

      local ped = GetPlayerPed(serverId)
      local coords = GetEntityCoords(ped)
      local zone = GetZoneAtPosition(coords)
      local bucket = GetPlayerRoutingBucket(serverId)

      if zone and bucket == 0 then
        UpdatePlayerPresence(serverId, zone)
      end
    end
  end
end, SessionNames.SETTING_PLAYER_PRESENCE_POINT)