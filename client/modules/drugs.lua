-- drugs.lua

local menu = Menu
local locale = Locale

local copsOnline = 0
local isSellingDrugs = false

local sellableDrugsByName = {}
local saleMultipliersByZoneName = {}

local lastSaleAt = 0
local drugTargetOptionCache = {}
local activeDrugTargets = {}

local handProps = {
  CATEGORY_LOW = {
    model = GetHashKey("prop_weed_bottle"),
    pos = vec3(0.026, 0.018, 0.022),
    rot = vec3(40.0, -292.0, -200.0)
  },
  CATEGORY_MED = {
    model = GetHashKey("prop_syringe_01"),
    pos = vec3(0.012, 0.036, 0.048),
    rot = vec3(46.0, -144.0, 0.0)
  },
  CATEGORY_HIGH = {
    model = GetHashKey("prop_meth_bag_01"),
    pos = vec3(0.018, 0.006, 0.018),
    rot = vec3(-48.0, 24.0, 0.0)
  },
  CATEGORY_CASH = {
    model = GetHashKey("prop_anim_cash_note"),
    pos = vec3(0.002, 0.036, 0.048),
    rot = vec3(30.0, 20.0, 0.0)
  }
}

TargetEntity = nil

if Config.TargetOptions and Config.TargetOptions.enableDrugs then
  local qbState = GetResourceState("qb-target")
  if qbState == "starting" or qbState == "started" then
    TargetEntity = function(entity, options, enabled)
      if enabled then
        exports["qb-target"]:AddTargetEntity(entity, {
          options = options,
          distance = options and options.distance
        })
      else
        exports["qb-target"]:RemoveTargetEntity(entity)
      end
    end
  end

  local oxState = GetResourceState("ox_target")
  if oxState == "starting" or oxState == "started" then
    TargetEntity = function(entity, options, enabled)
      if enabled then
        exports.ox_target:addLocalEntity(entity, options)
      else
        exports.ox_target:removeLocalEntity(entity)
      end
    end
  end

  if not TargetEntity then
    Config.TargetOptions.enableDrugs = false
  end
end

menu.CreateMenu("MENU_DRUGS")
menu.SetSubTitleColor("MENU_DRUGS", "rgb(255, 255, 255)")
menu.SetTitleBackground("MENU_DRUGS", 'url("./images/shopui_title_streetdealer.png") center / 22vw 12vh no-repeat')

function LerpNumber(from, to, t)
  return from + (to - from) * t
end

function AngleDelta(fromDeg, toDeg)
  return ((toDeg - fromDeg + 540) % 360) - 180
end

function LerpAngle(fromDeg, toDeg, t)
  return fromDeg + (AngleDelta(fromDeg, toDeg) * t)
end

function GetGroundZAtCoord(pos)
  local _, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, true)
  return groundZ
end

function MoveEntityToCoordSmooth(entity, targetCoords, targetHeading, _unused)
  local startCoords = GetEntityCoords(entity)
  local startHeading = GetEntityHeading(entity)

  local travelMs = (#(startCoords - targetCoords) * 8 / 100) * 7000 + 500
  local travelStart = GetGameTimer()
  local reached = false

  if #(GetEntityCoords(entity) - targetCoords) > 0.7 then
    TaskGoStraightToCoord(entity, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, targetHeading, 0.0)

    while true do
      Wait(100)
      TaskGoStraightToCoord(entity, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, targetHeading, 0.0)

      if (GetGameTimer() - travelStart) > travelMs then
        reached = true
        break
      end
    end
  else
    reached = true
  end

  if not reached then
    Wait(33)
    return
  end

  SetEntityCollision(entity, false, true)
  FreezeEntityPosition(entity, true)

  startCoords = GetEntityCoords(entity)
  startHeading = GetEntityHeading(entity)
  travelStart = GetGameTimer()

  local lerpMs = 500

  while true do
    Wait(0)

    local t = (GetGameTimer() - travelStart) / lerpMs

    local lerpPos = vector3(
      LerpNumber(startCoords.x, targetCoords.x, t),
      LerpNumber(startCoords.y, targetCoords.y, t),
      LerpNumber(startCoords.z, targetCoords.z, t)
    )

    local lerpHeading = LerpAngle(startHeading, targetHeading, t)

    SetEntityCoords(entity, lerpPos.x, lerpPos.y, GetGroundZAtCoord(lerpPos), true, true, true)
    SetEntityHeading(entity, lerpHeading)

    if t >= 1.0 then
      break
    end
  end

  Wait(33)
  FreezeEntityPosition(entity, false)
  SetEntityCollision(entity, true, true)
end

function SortInventoryItemsByName(a, b)
  if not a then return false end
  if not b then return true end

  local aName = a.name or ""
  local bName = b.name or ""

  return string.lower(aName) < string.lower(bName)
end

function UpdateSellableDrugs()
  sellableDrugsByName = table.wipe(sellableDrugsByName)

  local items = Inventory.GetItems()
  if not items then
    print("^1[GANGS] Could not get inventory items^7")
    return
  end

  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)

  local zoneAtPosition = GetZoneAtPosition(coords)
  local rivalry = GetRivalry()

  table.sort(items, SortInventoryItemsByName)

  for _, item in ipairs(items) do
    item.amount = item.amount or item.count

    local basePrice =
      (Config.Drugs.CATEGORY_LOW and Config.Drugs.CATEGORY_LOW[item.name]) or
      (Config.Drugs.CATEGORY_MED and Config.Drugs.CATEGORY_MED[item.name]) or
      (Config.Drugs.CATEGORY_HIGH and Config.Drugs.CATEGORY_HIGH[item.name])

    item.price = basePrice

    local category = nil
    if Config.Drugs.CATEGORY_LOW and Config.Drugs.CATEGORY_LOW[item.name] then
      category = "CATEGORY_LOW"
    elseif Config.Drugs.CATEGORY_MED and Config.Drugs.CATEGORY_MED[item.name] then
      category = "CATEGORY_MED"
    elseif Config.Drugs.CATEGORY_HIGH and Config.Drugs.CATEGORY_HIGH[item.name] then
      category = "CATEGORY_HIGH"
    end
    item.category = category

    if item.price and item.category and item.amount and item.amount > 0 then
      local zoneMultiplier = 1.0
      if zoneAtPosition then
        local m = saleMultipliersByZoneName[zoneAtPosition.name]
        if m then
          zoneMultiplier = m
        end
      end

      local preferenceMultiplier = 0.3
      if zoneAtPosition and zoneAtPosition.drugPreference then
        local pref = zoneAtPosition.drugPreference[item.category]
        if pref then
          preferenceMultiplier = pref
        end
      end

      item.price = item.price * zoneMultiplier * preferenceMultiplier

      if rivalry then
        item.price = math.ceil(item.price / 2)
      else
        item.price = math.ceil(item.price)
      end

      sellableDrugsByName[item.name] = item
    end
  end
end

function FindClosestDrugCustomer()
  local playerPed = PlayerPedId()
  local playerCoords = GetEntityCoords(playerPed)

  local closestPed = 0
  local closestDist = 4294967295

  local peds = GetGamePool("CPed")
  for _, ped in ipairs(peds) do
    if NetworkGetEntityIsNetworked(ped) then
      if not IsEntityDead(ped) and not IsPedRagdoll(ped) and not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped) and not IsEntityAMissionEntity(ped) then
        local ignored = Config.IgnorePedModelsForDrugSale[GetEntityModel(ped)]
        if not ignored then
          local pedCoords = GetEntityCoords(ped)
          local dist = glm.distance(playerCoords, pedCoords)
          if dist < 5.0 and dist < closestDist then
            closestDist = dist
            closestPed = ped
          end
        end
      end
    end
  end

  if not DoesEntityExist(closestPed) then
    return 0, 0
  end

  if not IsPedHuman(closestPed) then
    return 0, 0
  end

  local netId = NetworkGetNetworkIdFromEntity(closestPed)
  return closestPed, netId
end

RegisterNetEvent("rcore_gangs:client:set_cops")
AddEventHandler("rcore_gangs:client:set_cops", function(count)
  CachedPeds = {}
  copsOnline = count
end)

RegisterNetEvent("rcore_gangs:client:set_sale_multipliers")
AddEventHandler("rcore_gangs:client:set_sale_multipliers", function(multipliers)
  saleMultipliersByZoneName = multipliers
end)

RegisterNetEvent("rcore_gangs:client:drug_interaction")
AddEventHandler("rcore_gangs:client:drug_interaction", function(sellerServerId, customerNetId, result, categoryKey)
  local sellerPlayerId = GetPlayerFromServerId(sellerServerId)
  if not NetworkIsPlayerActive(sellerPlayerId) then
    return
  end

  if not NetworkDoesEntityExistWithNetworkId(customerNetId) then
    return
  end

  local localPed = PlayerPedId()
  local customerPed = NetworkGetEntityFromNetworkId(customerNetId)

  local distanceToCustomer = glm.distance(GetEntityCoords(localPed), GetEntityCoords(customerPed))
  if distanceToCustomer > 60.0 then
    return
  end

  local sellerPed = GetPlayerPed(sellerPlayerId)
  local sellerCoords = GetEntityCoords(sellerPed)
  local sellerRot = GetEntityRotation(sellerPed)
  local sellerFront = GetOffsetFromEntityInWorldCoords(sellerPed, 0.0, 1.0, 0.0)

  ClearPedTasksImmediately(sellerPed)
  SetPedCombatMovement(sellerPed, 0)
  SetPedCombatAbility(sellerPed, 0)

  ClearPedTasksImmediately(customerPed)
  SetEntityAsMissionEntity(customerPed, true, true)
  SetBlockingOfNonTemporaryEvents(customerPed, true)

  FreezeEntityPosition(sellerPed, true)
  MoveEntityToCoordSmooth(customerPed, sellerFront, sellerRot.z - 180.0)
  ClearPedTasksImmediately(customerPed)
  FreezeEntityPosition(sellerPed, false)

  if result == "accept" then
    RequestAnimDict("anim@heists@ornate_bank@chat_manager")

    TaskPlayAnim(sellerPed, "anim@heists@ornate_bank@chat_manager", "nice_clothes", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    TaskPlayAnim(customerPed, "anim@heists@ornate_bank@chat_manager", "nice_clothes", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    Wait(0)

    if distanceToCustomer < 15.0 then
      PlayPedAmbientSpeechNative(customerPed, "GENERIC_HI", "SPEECH_PARAMS_STANDARD")
      SetTimeout(1500, function()
        PlayPedAmbientSpeechNative(customerPed, "GENERIC_HOWS_IT_GOING", "SPEECH_PARAMS_STANDARD")
      end)
    end

    while IsEntityPlayingAnim(customerPed, "anim@heists@ornate_bank@chat_manager", "nice_clothes", 3) do
      Wait(0)
    end

    RequestModel(handProps[categoryKey].model)
    RequestModel(handProps.CATEGORY_CASH.model)

    local sellerProp = CreateObject(
      handProps[categoryKey].model,
      GetPedBoneCoords(sellerPed, 28422, 0.0, 0.0, 0.0),
      false, false, false
    )

    local customerProp = CreateObject(
      handProps.CATEGORY_CASH.model,
      GetPedBoneCoords(customerPed, 28422, 0.0, 0.0, 0.0),
      false, false, false
    )

    AttachEntityToEntity(
      sellerProp,
      sellerPed,
      GetPedBoneIndex(sellerPed, 28422),
      handProps[categoryKey].pos,
      handProps[categoryKey].rot,
      true, false, false, true, 0, true
    )

    AttachEntityToEntity(
      customerProp,
      customerPed,
      GetPedBoneIndex(customerPed, 28422),
      handProps.CATEGORY_CASH.pos,
      handProps.CATEGORY_CASH.rot,
      true, false, false, true, 0, true
    )

    RequestAnimDict("mp_common")
    TaskPlayAnim(sellerPed, "mp_common", "givetake1_a", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    TaskPlayAnim(customerPed, "mp_common", "givetake1_a", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    Wait(0)

    while IsEntityPlayingAnim(customerPed, "mp_common", "givetake1_a", 3) do
      if GetEntityAnimCurrentTime(customerPed, "mp_common", "givetake1_a") >= 0.425 then
        break
      end
      Wait(0)
    end

    DetachEntity(sellerProp, false, false)
    DetachEntity(customerProp, false, false)

    AttachEntityToEntity(
      sellerProp,
      customerPed,
      GetPedBoneIndex(customerPed, 28422),
      handProps[categoryKey].pos,
      handProps[categoryKey].rot,
      true, false, false, true, 0, true
    )

    AttachEntityToEntity(
      customerProp,
      sellerPed,
      GetPedBoneIndex(sellerPed, 28422),
      handProps.CATEGORY_CASH.pos,
      handProps.CATEGORY_CASH.rot,
      true, false, false, true, 0, true
    )

    while IsEntityPlayingAnim(customerPed, "mp_common", "givetake1_a", 3) do
      Wait(0)
    end

    DeleteEntity(sellerProp)
    DeleteEntity(customerProp)

    if glm.distance(GetEntityCoords(localPed), GetEntityCoords(customerPed)) < 15.0 then
      PlayPedAmbientSpeechNative(customerPed, "GENERIC_THANKS", "SPEECH_PARAMS_STANDARD")
      SetTimeout(1500, function()
        PlayPedAmbientSpeechNative(customerPed, "GENERIC_BYE", "SPEECH_PARAMS_STANDARD")
      end)
    end

    Wait(2000)
    ClearPedTasks(sellerPed)
    ClearPedTasks(customerPed)
    TaskWanderStandard(customerPed, 10.0, 10)
  end

  if result == "reject" then
    RequestAnimDict("anim@heists@ornate_bank@chat_manager")

    TaskPlayAnim(sellerPed, "anim@heists@ornate_bank@chat_manager", "nice_clothes", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    TaskPlayAnim(customerPed, "anim@heists@ornate_bank@chat_manager", "disrupt", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    Wait(0)

    if distanceToCustomer < 15.0 then
      PlayPedAmbientSpeechNative(customerPed, "GENERIC_HI", "SPEECH_PARAMS_STANDARD")
      SetTimeout(1500, function()
        local lines = { "GENERIC_CURSE_HIGH", "GENERIC_INSULT_HIGH" }
        PlayPedAmbientSpeechNative(customerPed, lines[math.random(1, 2)], "SPEECH_PARAMS_STANDARD")
      end)
    end

    Wait(2000)
    ClearPedTasks(sellerPed)
    ClearPedTasks(customerPed)
    TaskWanderStandard(customerPed, 10.0, 10)
  end

  if result == "report" then
    RequestAnimDict("anim@heists@ornate_bank@chat_manager")

    TaskPlayAnim(sellerPed, "anim@heists@ornate_bank@chat_manager", "nice_clothes", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    TaskPlayAnim(customerPed, "anim@heists@ornate_bank@chat_manager", "disrupt", 8.0, 8.0, -1, 16, 0, 0, 0, 0)
    Wait(0)

    if distanceToCustomer < 15.0 then
      PlayPedAmbientSpeechNative(customerPed, "GENERIC_HI", "SPEECH_PARAMS_STANDARD")
      SetTimeout(1000, function()
        local lines = { "GENERIC_SHOCKED_HIGH", "GENERIC_FRIGHTENED_HIGH" }
        PlayPedAmbientSpeechNative(customerPed, lines[math.random(1, 2)], "SPEECH_PARAMS_STANDARD")
      end)
    end

    Wait(2000)
    ClearPedTasks(sellerPed)
    ClearPedTasks(customerPed)
    TaskReactAndFleePed(customerPed, sellerPed)
  end

  Wait(10000)
  SetEntityAsNoLongerNeeded(customerPed)
end)

RegisterNetEvent("rcore_gangs:client:drug_notification")
AddEventHandler("rcore_gangs:client:drug_notification", function(customerNetId, message)
  UpdateSellableDrugs()
  isSellingDrugs = false

  if tableLenght(sellableDrugsByName) == 0 then
    Framework.ShowNotification(locale.DRUGS_MISSING_DRUGS)
    menu.CloseMenu()
  end

  if not NetworkDoesEntityExistWithNetworkId(customerNetId) then
    return
  end

  local customerPed = NetworkGetEntityFromNetworkId(customerNetId)
  local headshot = RegisterPedheadshot(customerPed)

  while not IsPedheadshotReady(headshot) do
    Wait(0)
  end

  local txd = GetPedheadshotTxdString(headshot)
  Framework.ShowAdvancedNotification(locale.NOTIFICATION_DRUGS_TITLE, locale.NOTIFICATION_DRUGS_SUBJECT, message, txd, txd)
  UnregisterPedheadshot(headshot)
end)

AddEventHandler("rcore_gangs:client:zone_changed", function()
  local zone = Zone

  UpdateSellableDrugs()

  if GetRivalry() then
    menu.SetSubTitle("MENU_DRUGS", zone.label .. " (" .. locale.MENU_DRUGS_RIVALRY .. ")")
  else
    menu.SetSubTitle("MENU_DRUGS", zone.label)
  end
end)

if Config.DrugOptions and Config.DrugOptions.enableSales then
  RegisterCommand((Config.Commands and Config.Commands.SELLDRUGS) or "selldrugs", function(source, args, rawCommand)
    if Config.DrugOptions.enableGangOnly and not Gang then
      return
    end

    if copsOnline < (Config.DrugOptions.minimumCops or 0) then
      local current = menu.CurrentMenu()
      if current == "MENU_HOME" or current == "MENU_DRUGS" then
        menu.CloseMenu()
      end
      Framework.ShowNotification(locale.DRUGS_MISSING_COPS)
      return
    end

    UpdateSellableDrugs()

    if tableLenght(sellableDrugsByName) == 0 then
      local current = menu.CurrentMenu()
      if current == "MENU_HOME" or current == "MENU_DRUGS" then
        menu.CloseMenu()
      end
      Framework.ShowNotification(locale.DRUGS_MISSING_DRUGS)
      return
    end

    Intervals.renderMenu = GetGameTimer()

    if Zone then
      if GetRivalry() then
        menu.SetSubTitle("MENU_DRUGS", Zone.label .. " (" .. locale.MENU_DRUGS_RIVALRY .. ")")
      else
        menu.SetSubTitle("MENU_DRUGS", Zone.label)
      end
    else
      local ped = PlayerPedId()
      local coords = GetEntityCoords(ped)
      menu.SetSubTitle("MENU_DRUGS", Config.ZoneNames[GetNameOfZone(coords.x, coords.y, coords.z)])
    end

    menu.OpenMenu("MENU_DRUGS")
  end, false)
end

function TargetDrugs(entity, enable, forceRefresh)
  local gang = Gang
  local zone = Zone

  if not (Config.TargetOptions and Config.TargetOptions.enableDrugs) then
    return
  end

  if not (Config.DrugOptions and Config.DrugOptions.enableSales) then
    return
  end

  if Config.DrugOptions.enableGangOnly and not gang then
    return
  end

  if copsOnline < (Config.DrugOptions.minimumCops or 0) then
    if activeDrugTargets[entity] then
      activeDrugTargets[entity] = nil
      TargetEntity(entity, nil, false)
    end
    return
  end

  if not IsPedHuman(entity) or not NetworkGetEntityIsNetworked(entity) then
    if activeDrugTargets[entity] then
      activeDrugTargets[entity] = nil
      TargetEntity(entity, nil, false)
    end
    return
  end

  if IsPedRagdoll(entity) or IsEntityDead(entity) or IsPedInAnyVehicle(entity) or IsEntityAMissionEntity(entity) then
    if activeDrugTargets[entity] then
      activeDrugTargets[entity] = nil
      TargetEntity(entity, nil, false)
    end
    return
  end

  if enable then
    if forceRefresh then
      TargetEntity(entity, nil, false)
    end

    local options = nil

    for drugName, targetDef in pairs(drugTargetOptionCache) do
      local drugData = sellableDrugsByName[drugName]

      local onSell = function()
        if isSellingDrugs then
          Framework.ShowNotification(locale.ALREADY_SELLING_DRUGS)
          return
        end

        if GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then
          Framework.ShowNotification(locale.CANT_SELL_DRUGS_IN_CAR)
          return
        end

        isSellingDrugs = true

        local qty = Config.DrugOptions.saleQuantity
        if Config.DrugOptions.saleRandomQuantity then
          qty = math.random(1, qty)
        end

        local available = drugData and drugData.amount or 0
        if qty > available and available then
          qty = available
        end

        activeDrugTargets[entity] = nil
        TargetEntity(entity, nil, false)

        TriggerServerEvent(
          "rcore_gangs:server:sell_drugs",
          NetworkGetNetworkIdFromEntity(entity),
          drugName,
          qty
        )
      end

      if not options then
        options = {}
      end

      options[#options + 1] = {
        type = targetDef.type,
        icon = targetDef.icon,
        name = targetDef.name,
        label = targetDef.label,
        distance = targetDef.distance,
        action = onSell,
        onSelect = onSell
      }
    end

    if options then
      activeDrugTargets[entity] = entity
      TargetEntity(entity, options, true)
    end
  else
    activeDrugTargets[entity] = nil
    TargetEntity(entity, nil, false)
  end
end

function TargetDrugsOptions()
  UpdateSellableDrugs()

  local hasChanges = false
  local nextCache = {}

  for drugName, drugData in pairs(sellableDrugsByName) do
    local icon = nil

    if drugData.category == "CATEGORY_LOW" then
      icon = Config.DrugOptions.categoryLowIcon
    elseif drugData.category == "CATEGORY_MED" then
      icon = Config.DrugOptions.categoryMidIcon
    elseif drugData.category == "CATEGORY_HIGH" then
      icon = Config.DrugOptions.categoryHighIcon
    end

    local label = drugData.amount .. " - " .. drugData.label .. " (" .. FormatMoney(drugData.price) .. ")"

    local entry = {
      type = "client",
      icon = icon,
      name = drugName,
      label = label,
      distance = 6.0,
      drugPrice = drugData.price,
      drugAmount = drugData.amount
    }

    local existing = drugTargetOptionCache[drugName]
    if not existing then
      hasChanges = true
    else
      if existing.drugPrice ~= drugData.price then
        hasChanges = true
      end
      if existing.drugAmount ~= drugData.amount then
        hasChanges = true
      end
    end

    nextCache[drugName] = entry
    drugTargetOptionCache[drugName] = entry
  end

  for drugName in pairs(drugTargetOptionCache) do
    if not nextCache[drugName] then
      hasChanges = true
      drugTargetOptionCache[drugName] = nil
    end
  end

  return hasChanges
end

function DrugMenu(currentMenu)
  local gang = Gang
  local zone = Zone

  if not (Config.DrugOptions and Config.DrugOptions.enableSales) then
    return
  end

  if Config.DrugOptions.enableGangOnly and not gang then
    return
  end

  if copsOnline < (Config.DrugOptions.minimumCops or 0) then
    return
  end

  if currentMenu ~= "MENU_DRUGS" then
    return
  end

  if isSellingDrugs then
    menu.Button("DRUGS", locale.MENU_DRUGS_SELLING, nil, false)
    return
  end

  for drugName, drugData in pairs(sellableDrugsByName) do
    if menu.Button(drugName, "[" .. drugData.amount .. "]\t" .. drugData.label, FormatMoney(drugData.price), true) then
      local ped = PlayerPedId()

      if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) then
        menu.CloseMenu()
        break
      end

      local customerPed, customerNetId = FindClosestDrugCustomer()
      if DoesEntityExist(customerPed) and customerNetId ~= 0 then
        isSellingDrugs = true

        local qty = Config.DrugOptions.saleQuantity
        if Config.DrugOptions.saleRandomQuantity then
          qty = math.random(1, qty)
        end

        local available = drugData.amount or 0
        if qty > available and available then
          qty = available
        end

        TriggerServerEvent("rcore_gangs:server:sell_drugs", customerNetId, drugName, qty)
      else
        Framework.ShowNotification(locale.DRUGS_MISSING_CUSTOMER)
      end
    end
  end
end
