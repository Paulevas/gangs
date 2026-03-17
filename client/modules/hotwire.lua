-- hotwire.lua

AddEventHandler("gameEventTriggered", function(eventName, args)
  if eventName ~= "CEventNetworkPlayerEnteredVehicle" then
    return
  end

  local playerIdFromEvent = args[1]
  local vehicleEntity = args[2]

  if PlayerId() ~= playerIdFromEvent then
    return
  end

  if not DoesEntityExist(vehicleEntity) then
    return
  end

  if not IsVehicleNeedsToBeHotwired(vehicleEntity) then
    return
  end

  if not NetworkGetEntityIsNetworked(vehicleEntity) then
    return
  end

  local lockStatus = GetVehicleDoorLockStatus(vehicleEntity)
  if lockStatus ~= 1 and lockStatus ~= 7 then
    return
  end

  local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicleEntity)
  TriggerServerEvent("rcore_gangs:server:hotwire", vehicleNetId)
end)