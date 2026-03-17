-- murder.lua

AddEventHandler("gameEventTriggered", function(eventName, args)
  if eventName ~= "CEventNetworkEntityDamage" then
    return
  end

  local victimEntity = args[1]
  local attackerEntity = args[2]
  local damageFlag = args[6]
  local weaponHash = args[7]

  if damageFlag == 0 then
    return
  end

  if weaponHash == 133987706 or weaponHash == -1553120962 then
    return
  end

  if not IsEntityAPed(victimEntity) or not IsEntityAPed(attackerEntity) then
    return
  end

  if not NetworkGetEntityIsNetworked(victimEntity) or not NetworkGetEntityIsNetworked(attackerEntity) then
    return
  end

  if PlayerPedId() ~= attackerEntity then
    return
  end

  if GetPedType(victimEntity) == 28 then
    return
  end

  if IsPedAPlayer(victimEntity) then
    return
  end

  local victimNetId = NetworkGetNetworkIdFromEntity(victimEntity)
  TriggerServerEvent("rcore_gangs:server:murder", victimNetId)
end)