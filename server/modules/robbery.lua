-- server/robbery.lua

function GetRobberyContext(serverId)
  local ped = GetPlayerPed(serverId)
  if not ped or ped == 0 then
    return nil, nil
  end

  local coords = GetEntityCoords(ped)
  local zone = GetZoneAtPosition(coords)

  return coords, zone
end

function GetRobberyDecreaseMultiplier(zone)
  local rivalry = GetRivalry(zone.name)
  if rivalry then
    return Config.DecreaseMultipliersRivalry.ROBBERY
  end

  return Config.DecreaseMultipliers.ROBBERY
end

function ProcessRobberyPenalty(serverId, loyaltyScale, businessLossDivisor)
  local coords, zone = GetRobberyContext(serverId)
  if not coords or not zone then
    return
  end

  local decreaseMultiplier = GetRobberyDecreaseMultiplier(zone)
  DecreaseLoyalty(serverId, zone, "ROBBERY", loyaltyScale, decreaseMultiplier)

  local business = GetBusinessAtPosition(coords)
  local businessKey = business and business.name or nil
  local businessMoney = GetBusinessMoney(businessKey)

  -- ⚠️ Guard: original logic assumes business.name exists and money is numeric.
  if business and type(businessMoney) == "number" and businessMoney > 0 then
    RemoveBusinessMoney(business.name, math.floor(businessMoney / businessLossDivisor))
  end
end

RegisterNetEvent("esx_holdup:robberyComplete")
AddEventHandler("esx_holdup:robberyComplete", function()
  ProcessRobberyPenalty(source, 0.5, 4)
end)

RegisterNetEvent("qb-storerobbery:server:setSafeStatus")
AddEventHandler("qb-storerobbery:server:setSafeStatus", function()
  ProcessRobberyPenalty(source, 1.0, 2)
end)

RegisterNetEvent("qb-storerobbery:server:setRegisterStatus")
AddEventHandler("qb-storerobbery:server:setRegisterStatus", function()
  ProcessRobberyPenalty(source, 0.5, 4)
end)