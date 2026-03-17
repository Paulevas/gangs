-- server/protection.lua

local businessIdByKey = {}
local businessMoneyByKey = {}

function GetBusinessId(businessKey)
  return businessIdByKey[businessKey]
end

function GetBusinessMoney(businessKey)
  return businessMoneyByKey[businessKey]
end

function GetBusinessAtPosition(coords)
  for businessKey, businessCfg in pairs(Config.Businesses) do
    if businessIdByKey[businessKey] and businessMoneyByKey[businessKey] then
      if glm.distance(coords, businessCfg.checkpoint) < 20.0 then
        return businessCfg
      end
    end
  end

  return nil
end

function AddBusinessMoney(businessKey, amount)
  if businessIdByKey[businessKey] and businessMoneyByKey[businessKey] then
    businessIdByKey[businessKey] = businessIdByKey[businessKey]
    businessMoneyByKey[businessKey] = businessMoneyByKey[businessKey] + amount

    SQL.SetProtectionMoney(businessIdByKey[businessKey], businessMoneyByKey[businessKey])
    TriggerClientEvent("rcore_gangs:client:set_business_money", -1, businessKey, businessMoneyByKey[businessKey])
    return
  end

  SQL.Execute("ANALYZE TABLE protections")

  businessIdByKey[businessKey] = SQL.Scalar("SELECT AUTO_INCREMENT FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'protections'")
  businessMoneyByKey[businessKey] = amount

  SQL.InsertProtection(businessKey, amount)
  TriggerClientEvent("rcore_gangs:client:set_business_money", -1, businessKey, amount)
end

function RemoveBusinessMoney(businessKey, amount)
  if not (businessIdByKey[businessKey] and businessMoneyByKey[businessKey]) then
    return
  end

  if amount < businessMoneyByKey[businessKey] then
    businessIdByKey[businessKey] = businessIdByKey[businessKey]
    businessMoneyByKey[businessKey] = businessMoneyByKey[businessKey] - amount

    SQL.SetProtectionMoney(businessIdByKey[businessKey], businessMoneyByKey[businessKey])
    TriggerClientEvent("rcore_gangs:client:set_business_money", -1, businessKey, businessMoneyByKey[businessKey])
    return
  end

  SQL.DeleteProtection(businessIdByKey[businessKey])
  businessIdByKey[businessKey] = nil
  businessMoneyByKey[businessKey] = nil

  TriggerClientEvent("rcore_gangs:client:set_business_money", -1, businessKey, nil)
end

RegisterNetEvent("rcore_gangs:server:collect_protection")
AddEventHandler("rcore_gangs:server:collect_protection", function(businessKey)
  local serverId = source

  if not (businessIdByKey[businessKey] and businessMoneyByKey[businessKey]) then
    return
  end

  local playerGang = ServerIdToGang[serverId]
  local businessZoneName = Config.Businesses[businessKey].zone
  local businessZoneCfg = Config.GangZones[businessZoneName]
  local zoneOwnerGang = GetGangAtZone(businessZoneCfg)

  if not playerGang or not zoneOwnerGang then
    return
  end

  if not playerGang.leader then
    if not (playerGang.access and playerGang.access["protection.collect"]) then
      return
    end
  end

  if playerGang.id ~= zoneOwnerGang.id then
    return
  end

  local protectionId = businessIdByKey[businessKey]
  local moneyAmount = businessMoneyByKey[businessKey]

  businessIdByKey[businessKey] = nil
  businessMoneyByKey[businessKey] = nil

  local dirtyCfg = Config.OtherOptions
  if dirtyCfg and (dirtyCfg.dirtyMoney or dirtyCfg.dirtyMoneyItem) then
    Framework.AddPlayerDirtyMoney(serverId, moneyAmount)
  else
    Framework.AddPlayerMoney(serverId, moneyAmount)
  end

  SQL.DeleteProtection(protectionId)
  TriggerClientEvent("rcore_gangs:client:set_business_money", -1, businessKey, nil)

  Framework.ShowNotification(
    serverId,
    Locale("PROTECTION_RECEIVE_MONEY", {
      amount = FormatMoney(moneyAmount),
      business = Config.Businesses[businessKey].label
    })
  )
end)

RegisterNetEvent("rcore_gangs:server:player_loaded")
AddEventHandler("rcore_gangs:server:player_loaded", function(target)
  local targetServerId = target
  if not targetServerId then
    targetServerId = source
  end

  for businessKey, money in pairs(businessMoneyByKey) do
    Wait(100)
    TriggerClientEvent("rcore_gangs:client:set_business_money", targetServerId, businessKey, money)
  end
end)

AddEventHandler("rcore_gangs:server:database_ready", function()
  for _, row in ipairs(SQL.GetProtections()) do
    businessIdByKey[row.business] = row.id
    businessMoneyByKey[row.business] = row.money
  end

  Wait(1000)

  for businessKey, money in pairs(businessMoneyByKey) do
    Wait(100)
    TriggerClientEvent("rcore_gangs:client:set_business_money", -1, businessKey, money)
  end
end)

CreateThread(function()
  while true do
    Wait(60000)

    for businessKey, businessCfg in pairs(Config.Businesses) do
      Wait(1000)

      local zoneHasAnyOwner = false
      for _, zoneEntry in pairs(Zones) do
        if zoneEntry.name == businessCfg.zone then
          zoneHasAnyOwner = true
          break
        end
      end

      if zoneHasAnyOwner then
        local now = GetGameTimer()

        if not businessCfg.nextPayout then
          businessCfg.lastPayout = now
          businessCfg.nextPayout = now + (math.random(900, 2700) * 1000)
        end

        if now > businessCfg.nextPayout then
          local secondsSinceLast = math.floor((now - businessCfg.lastPayout) / 1000)
          businessCfg.lastPayout = now
          businessCfg.nextPayout = now + (math.random(900, 2700) * 1000)

          local hourlyIncome = businessCfg.hourlyIncome or businessCfg.hourlyRacket
          local payout = math.floor((secondsSinceLast / 3600) * hourlyIncome)

          AddBusinessMoney(businessKey, payout)
        end
      else
        businessCfg.lastPayout = nil
        businessCfg.nextPayout = nil

        local currentMoney = businessMoneyByKey[businessKey]
        RemoveBusinessMoney(businessKey, currentMoney)
      end
    end
  end
end, SessionNames.BUSINESSES_MONEY_MANAGEMENT)