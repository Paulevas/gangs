-- rivalry.lua

local activeRivalriesByZoneName = {}
local finishedRivalriesByGangId = {}

function GetRivalry()
  local gang = Gang
  local zone = Zone

  if not gang or not zone then
    return nil
  end

  local rivalry = activeRivalriesByZoneName[zone.name]
  if not rivalry then
    return nil
  end

  local gangId = gang.id
  if rivalry.attacker ~= gangId and rivalry.defender ~= gangId then
    return nil
  end

  local secondsLeft = math.max(0, math.floor((rivalry.endsAt - GetNetworkTimeAccurate()) / 1000))
  rivalry.secondsLeft = secondsLeft

  return rivalry
end

function GetFinishedRivalry()
  local gang = Gang
  local zone = Zone

  if not gang or not zone then
    return nil
  end

  local gangFinished = finishedRivalriesByGangId[gang.id]
  if not gangFinished then
    return nil
  end

  return gangFinished[zone.name] or nil
end

RegisterNetEvent("rcore_gangs:client:set_rivalry")
AddEventHandler("rcore_gangs:client:set_rivalry", function(zoneName, rivalryData)
  activeRivalriesByZoneName[zoneName] = rivalryData
end)

RegisterNetEvent("rcore_gangs:client:set_finished_rivalry")
AddEventHandler("rcore_gangs:client:set_finished_rivalry", function(gangId, finishedData)
  finishedRivalriesByGangId[gangId] = finishedData
end)