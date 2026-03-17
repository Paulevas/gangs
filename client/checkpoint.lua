-- ==============================================================
-- Gang Garage / Reserve / Checkpoints (refactor, same behavior)
-- ==============================================================

local spawnedVehicleNetIdsByKey = {} -- set by rcore_gangs:client:set_vehicles
local showcaseVehicleEntity = 0     -- preview vehicle handle used in menus

-- ==============================================================
-- Menus (same IDs / assets)
-- ==============================================================

Menu.CreateMenu("MENU_GARAGE", nil, Locale.MENU_GARAGE_SUBTITLE)
Menu.CreateMenu("MENU_RESERVE", nil, Locale.MENU_RESERVE_SUBTITLE)

Menu.CreateSubMenu("SUBMENU_CHECKPOINTS", "MENU_HOME")
Menu.CreateSubMenu("SUBMENU_CHECKPOINTS_MANAGE", "SUBMENU_CHECKPOINTS")

Menu.CreateSubMenu("SUBMENU_GARAGE_LIST", "MENU_GARAGE")
Menu.CreateSubMenu("SUBMENU_GARAGE_DRIVE", "MENU_GARAGE")
Menu.CreateSubMenu("SUBMENU_GARAGE_INSERT", "MENU_GARAGE")
Menu.CreateSubMenu("SUBMENU_GARAGE_REMOVE", "MENU_GARAGE")

Menu.CreateSubMenu("SUBMENU_RESERVE_TAKE", "MENU_RESERVE")
Menu.CreateSubMenu("SUBMENU_RESERVE_GIVE", "MENU_RESERVE")

for _, menuId in pairs({
  "MENU_GARAGE",
  "MENU_RESERVE",
  "SUBMENU_GARAGE_LIST",
  "SUBMENU_GARAGE_DRIVE",
  "SUBMENU_GARAGE_INSERT",
  "SUBMENU_GARAGE_REMOVE",
  "SUBMENU_RESERVE_TAKE",
  "SUBMENU_RESERVE_GIVE",
}) do
  Menu.SetSubTitleColor(menuId, "rgb(255, 255, 255)")
end

Menu.SetTitleBackground("MENU_GARAGE", "url(\"./images/shopui_title_auto_shop.png\") center / 22vw 12vh no-repeat")
Menu.SetTitleBackground("MENU_RESERVE", "url(\"./images/shopui_title_cash_bag.png\") center / 22vw 12vh no-repeat")
Menu.SetTitleBackground("SUBMENU_GARAGE_LIST", "url(\"./images/shopui_title_auto_shop.png\") center / 22vw 12vh no-repeat")
Menu.SetTitleBackground("SUBMENU_GARAGE_DRIVE", "url(\"./images/shopui_title_auto_shop.png\") center / 22vw 12vh no-repeat")
Menu.SetTitleBackground("SUBMENU_GARAGE_INSERT", "url(\"./images/shopui_title_auto_shop.png\") center / 22vw 12vh no-repeat")
Menu.SetTitleBackground("SUBMENU_GARAGE_REMOVE", "url(\"./images/shopui_title_auto_shop.png\") center / 22vw 12vh no-repeat")
Menu.SetTitleBackground("SUBMENU_RESERVE_TAKE", "url(\"./images/shopui_title_cash_bag.png\") center / 22vw 12vh no-repeat")
Menu.SetTitleBackground("SUBMENU_RESERVE_GIVE", "url(\"./images/shopui_title_cash_bag.png\") center / 22vw 12vh no-repeat")

-- ==============================================================
-- Config normalization (same output structure)
-- ==============================================================

for modelKey, value in pairs(Config.GarageVehicles) do
  local modelHash = modelKey

  if type(modelHash) == "string" then
    modelHash = GetHashKey(modelHash)
  end

  if type(value) == "table" then
    Config.GarageVehicles[modelHash] = {
      label = value.label,
      price = value.price
    }
  elseif type(value) == "number" then
    local displayName = GetDisplayNameFromVehicleModel(modelHash)
    local label = GetLabelText(displayName)
    Config.GarageVehicles[modelHash] = {
      label = label,
      price = value
    }
  end
end

if Config.GangOptions.restrictColors then
  for colorKey in pairs(Config.GangMenuColors) do
    if Config.VehicleColors[colorKey] and Config.VehicleColorClasses[colorKey] then
      local labelList = {}
      for _, colorInfo in ipairs(Config.VehicleColors[colorKey]) do
        table.insert(labelList, colorInfo.label)
      end

      table.insert(Config.VehicleColors, labelList)

      local classLabel = string.gsub(colorKey, "^%l", string.upper)
      table.insert(Config.VehicleColorClasses, classLabel)

      Config.VehicleColorClasses[colorKey] = #Config.VehicleColorClasses
    end
  end

  for colorKey in pairs(Config.GangMenuColors) do
    if not Config.VehicleColors[colorKey] and not Config.VehicleColorClasses[colorKey] then
      if colorKey:find("dark") then
        local baseKey = colorKey:gsub("dark", "")
        Config.VehicleColors[colorKey] = Config.VehicleColors[baseKey]
        Config.VehicleColorClasses[colorKey] = Config.VehicleColorClasses[baseKey]
      end

      if colorKey:find("light") then
        local baseKey = colorKey:gsub("light", "")
        Config.VehicleColors[colorKey] = Config.VehicleColors[baseKey]
        Config.VehicleColorClasses[colorKey] = Config.VehicleColorClasses[baseKey]
      end
    end
  end
else
  for colorKey in pairs(Config.GangMenuColors) do
    if Config.VehicleColors[colorKey] and Config.VehicleColorClasses[colorKey] then
      local labelList = {}
      for _, colorInfo in ipairs(Config.VehicleColors[colorKey]) do
        table.insert(labelList, colorInfo.label)
      end

      table.insert(Config.VehicleColors, labelList)

      local classLabel = string.gsub(colorKey, "^%l", string.upper)
      table.insert(Config.VehicleColorClasses, classLabel)
    end
  end
end

-- ==============================================================
-- Helpers (global functions, as requested)
-- ==============================================================

function HasGangAccess(gangData, permissionKey)
  if not gangData then return false end
  if gangData.leader then return true end
  local access = gangData.access
  return access and access[permissionKey] == true
end

function CanInteractAtCheckpoint(playerId, ped)
  if not IsControlJustPressed(0, Config.KeyBinds.checkpoint) then return false end
  if IsPedRagdoll(ped) then return false end
  if IsPlayerDead(playerId) then return false end
  return true
end

function ParseGarageVehicleKey(value)
  local plate = string.match(value, ":(.*)")
  local dotIndex = value:find("%.")
  local underscoreIndex = value:find("_")
  if not dotIndex or not underscoreIndex then
    return nil, nil, plate
  end

  local modelHash = tonumber(value:sub(1, dotIndex - 1))
  local colorIndex = tonumber(value:sub(dotIndex + 1, underscoreIndex - 1))
  return modelHash, colorIndex, plate
end

-- ==============================================================
-- Preview vehicle
-- ==============================================================

function CreateShowcaseVehicle(modelHash, colorIndex, plateText)
  local vehicleEntity = 0

  if HasModelLoaded(modelHash) then
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    vehicleEntity = CreateVehicle(modelHash, coords, heading, false, false)

    if plateText then
      SetVehicleNumberPlateText(vehicleEntity, plateText)
    end

    SetEntityAlpha(vehicleEntity, 224, false)
    SetEntityCollision(vehicleEntity, false, false)
    FreezeEntityPosition(vehicleEntity, true)

    SetPedIntoVehicle(ped, vehicleEntity, -1)
    SetVehicleColours(vehicleEntity, colorIndex, colorIndex)

    SetVehicleEngineOn(vehicleEntity, true, true, false)
    SetVehicleDoorsLocked(vehicleEntity, 4)

    return vehicleEntity
  end

  RequestModel(modelHash)
  return vehicleEntity
end

-- ==============================================================
-- Checkpoint rendering / interaction
-- ==============================================================

IsPlayerCloseToCheckpoint = false

function RenderCheckpoint()
  IsPlayerCloseToCheckpoint = false

  local gangData = Gang
  local _zone = Zone -- kept (matches original pattern)

  if not gangData then return end
  if not (gangData.garage or gangData.storage or gangData.reserve) then return end
  if showcaseVehicleEntity > 0 then return end

  local now = GetGameTimer()
  local playerId = PlayerId()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)

  if not gangData.reserve then
    Intervals.checkpoint = now + 1000
    return
  end

  local garageDist = 1000.0
  if gangData.garage then
    local d = glm.distance(coords, gangData.garage)
    if d then garageDist = d end
  end

  local storageDist = 1000.0
  if gangData.storage then
    local d = glm.distance(coords, gangData.storage)
    if d then storageDist = d end
  end

  local reserveDist = 1000.0
  if gangData.reserve then
    local d = glm.distance(coords, gangData.reserve)
    if d then reserveDist = d end
  end

  if garageDist < 8.0 then
    IsPlayerCloseToCheckpoint = true
  else
    if Menu.CurrentMenu() == "MENU_GARAGE" then
      Menu.CloseMenu()
    end
  end

  if storageDist < 8.0 then
    IsPlayerCloseToCheckpoint = true
  end

  if reserveDist < 8.0 then
    IsPlayerCloseToCheckpoint = true
  else
    if Menu.CurrentMenu() == "MENU_RESERVE" then
      Menu.CloseMenu()
    end
  end

  if not IsPlayerCloseToCheckpoint then
    Intervals.checkpoint = now + 1000

    local current = Menu.CurrentMenu()
    if current == "MENU_GARAGE" or current == "MENU_RESERVE" then
      Menu.CloseMenu()
    end

    return
  end

  Intervals.checkpoint = 0

  local markerRgb = Config.GangMenuColors[gangData.color].background

  -- Garage
  if garageDist < 5.0 and HasGangAccess(gangData, "garage.use") and gangData.garage then
    local p = gangData.garage
    Draw3dText(
      p.x, p.y, p.z + 0.05,
      Locale("CHECKPOINT_INTERACT_GARAGE", { color = Config.ColorToTextColor[gangData.color] })
    )
    DrawMarker(
      2,
      p.x, p.y, p.z - 0.15,
      0.0, 0.0, 0.0,
      0.0, 0.0, 0.0,
      0.4, 0.25, 0.25,
      markerRgb[1], markerRgb[2], markerRgb[3], 196,
      false, true, 2, nil, nil, false
    )

    if garageDist < 1.5 and CanInteractAtCheckpoint(playerId, ped) then
      Menu.OpenMenu("MENU_GARAGE")
    end
  end

  -- Storage
  if storageDist < 5.0 and HasGangAccess(gangData, "storage.use") and gangData.storage then
    local p = gangData.storage
    Draw3dText(
      p.x, p.y, p.z + 0.05,
      Locale("CHECKPOINT_INTERACT_STORAGE", { color = Config.ColorToTextColor[gangData.color] })
    )
    DrawMarker(
      2,
      p.x, p.y, p.z - 0.15,
      0.0, 0.0, 0.0,
      0.0, 0.0, 0.0,
      0.4, 0.25, 0.25,
      markerRgb[1], markerRgb[2], markerRgb[3], 196,
      false, true, 2, nil, nil, false
    )

    if storageDist < 1.5 and CanInteractAtCheckpoint(playerId, ped) then
      Inventory.OpenStorage(gangData.tag)
    end
  end

  -- Reserve
  if reserveDist < 5.0 and HasGangAccess(gangData, "reserve.use") and gangData.reserve then
    local p = gangData.reserve
    Draw3dText(
      p.x, p.y, p.z + 0.05,
      Locale("CHECKPOINT_INTERACT_RESERVE", { color = Config.ColorToTextColor[gangData.color] })
    )
    DrawMarker(
      2,
      p.x, p.y, p.z - 0.15,
      0.0, 0.0, 0.0,
      0.0, 0.0, 0.0,
      0.4, 0.25, 0.25,
      markerRgb[1], markerRgb[2], markerRgb[3], 196,
      false, true, 2, nil, nil, false
    )

    if reserveDist < 1.5 and CanInteractAtCheckpoint(playerId, ped) then
      Menu.OpenMenu("MENU_RESERVE")
    end
  end
end

-- Keep the exported/global name exactly
RenderCheckpoint = RenderCheckpoint

-- ==============================================================
-- Menu logic
-- ==============================================================

function CheckpointMenu(menuId)
  local gangData = Gang
  local _zone = Zone -- kept

  if not gangData then return end

  local keepShowcaseVehicle = false

  -- Checkpoints category selector
  if menuId == "SUBMENU_CHECKPOINTS" then
    if Config.GangOptions.garage then
      if Menu.MenuButton("GARAGE", "SUBMENU_CHECKPOINTS_MANAGE", Locale.MENU_CHECKPOINT_GARAGE, true) then
        Menu.SetSubTitle("SUBMENU_CHECKPOINTS_MANAGE", Locale.MENU_CHECKPOINT_GARAGE)
      end
    end

    if Config.GangOptions.storage then
      if Menu.MenuButton("STORAGE", "SUBMENU_CHECKPOINTS_MANAGE", Locale.MENU_CHECKPOINT_STORAGE, true) then
        Menu.SetSubTitle("SUBMENU_CHECKPOINTS_MANAGE", Locale.MENU_CHECKPOINT_STORAGE)
      end
    end

    if Config.GangOptions.reserve then
      if Menu.MenuButton("RESERVE", "SUBMENU_CHECKPOINTS_MANAGE", Locale.MENU_CHECKPOINT_RESERVE, true) then
        Menu.SetSubTitle("SUBMENU_CHECKPOINTS_MANAGE", Locale.MENU_CHECKPOINT_RESERVE)
      end
    end
  end

  -- Checkpoint placement/removal
  if menuId == "SUBMENU_CHECKPOINTS_MANAGE" then
    local checkpointType = Menu.CurrentValue()

    if checkpointType == "GARAGE" then
      if gangData.garage then
        if Menu.Button("CHECKPOINT", Locale.MENU_CHECKPOINT_REMOVE, nil, true) then
          TriggerServerEvent("rcore_gangs:server:delete_checkpoint", checkpointType)
          Menu.CloseMenu()
        end
      else
        if Menu.Button("CHECKPOINT", Locale.MENU_CHECKPOINT_PLACE, nil, true) then
          TriggerServerEvent("rcore_gangs:server:insert_checkpoint", checkpointType)
          Menu.CloseMenu()
        end
      end
    end

    if checkpointType == "STORAGE" then
      if gangData.storage then
        if Menu.Button("CHECKPOINT", Locale.MENU_CHECKPOINT_REMOVE, nil, true) then
          TriggerServerEvent("rcore_gangs:server:delete_checkpoint", checkpointType)
          Menu.CloseMenu()
        end
      else
        if Menu.Button("CHECKPOINT", Locale.MENU_CHECKPOINT_PLACE, nil, true) then
          TriggerServerEvent("rcore_gangs:server:insert_checkpoint", checkpointType)
          Menu.CloseMenu()
        end
      end
    end

    if checkpointType == "RESERVE" then
      if gangData.reserve then
        if Menu.Button("CHECKPOINT", Locale.MENU_CHECKPOINT_REMOVE, nil, true) then
          TriggerServerEvent("rcore_gangs:server:delete_checkpoint", checkpointType)
          Menu.CloseMenu()
        end
      else
        if Menu.Button("CHECKPOINT", Locale.MENU_CHECKPOINT_PLACE, nil, true) then
          TriggerServerEvent("rcore_gangs:server:insert_checkpoint", checkpointType)
          Menu.CloseMenu()
        end
      end
    end
  end

  -- Garage main menu
  if menuId == "MENU_GARAGE" then
    local ped = PlayerPedId()

    -- Return vehicle (same conditional logic)
    if IsPedInAnyVehicle(ped) then
      local vehicle = GetVehiclePedIsIn(ped)
      local modelHash = GetEntityModel(vehicle)
      local primaryColor = GetVehicleColours(vehicle)
      local plate = GetVehicleNumberPlateText(vehicle)
      local restrictSpawns = Config.GangOptions.restrictSpawns

      local lookupKey = tostring(modelHash) .. "." .. tostring(primaryColor) .. "." .. tostring(plate)

      if restrictSpawns then
        local expectedNetId = spawnedVehicleNetIdsByKey[lookupKey]
        if expectedNetId then
          local netId = NetworkGetNetworkIdFromEntity(vehicle)
          if expectedNetId == netId then
            if Menu.Button("RETURN", Locale.MENU_GARAGE_RETURN, nil, true) then
              TriggerServerEvent("rcore_gangs:server:return_vehicle", modelHash, primaryColor, plate)
              Menu.CloseMenu()
            end
          end
        end
      else
        if gangData.vehicles then
          for _, v in ipairs(gangData.vehicles) do
            if v.model == modelHash and v.color == primaryColor then
              if Menu.Button("RETURN", Locale.MENU_GARAGE_RETURN, nil, true) then
                TriggerServerEvent("rcore_gangs:server:return_vehicle", modelHash, primaryColor, plate)
                Menu.CloseMenu()
              end
            end
          end
        end
      end
    end

    -- Insert/remove access
    if HasGangAccess(gangData, "garage.edit") then
      if Config.GarageOptions.enableInsert then
        if Menu.MenuButton("INSERT", "SUBMENU_GARAGE_LIST", Locale.MENU_GARAGE_INSERT1, true) then
          Menu.SetSubTitle("SUBMENU_GARAGE_LIST", Locale.MENU_GARAGE_CATALOG)
        end
      end

      if Config.GarageOptions.enableRemove then
        local canRemove = gangData.vehicles and (#gangData.vehicles > 0) or false
        if Menu.MenuButton("REMOVE", "SUBMENU_GARAGE_LIST", Locale.MENU_GARAGE_REMOVE1, canRemove) then
          Menu.SetSubTitle("SUBMENU_GARAGE_LIST", Locale.MENU_GARAGE_LIST)
        end
      end
    end

    -- Vehicles list
    if gangData.vehicles then
      local shown = 0

      for _, v in ipairs(gangData.vehicles) do
        local plateSuffix = v.plate and (":" .. v.plate) or ""
        local vehicleKey = tostring(v.model) .. "." .. tostring(v.color) .. "_0" .. plateSuffix

        local enabled = true
        if spawnedVehicleNetIdsByKey[vehicleKey] and Config.GangOptions.restrictSpawns then
          enabled = not NetworkDoesEntityExistWithNetworkId(spawnedVehicleNetIdsByKey[vehicleKey])
        end

        local vehCfg = Config.GarageVehicles[v.model]
        if vehCfg then
          shown = shown + 1
          if Menu.MenuButton(vehicleKey, "SUBMENU_GARAGE_DRIVE", vehCfg.label, enabled) then
            Menu.SetSubTitle("SUBMENU_GARAGE_DRIVE", vehCfg.label)
          end
        end
      end

      if shown == 0 then
        Menu.Button("EMPTY", Locale.MENU_GARAGE_EMPTY, nil, false)
      end
    end
  end

  -- Reserve menu
  if menuId == "MENU_RESERVE" then
    Menu.Button("BALANCE", Locale.MENU_RESERVE_BALANCE, FormatMoney(gangData.balance), true)

    local _, amountText = Menu.InputButton(
      "AMOUNT",
      Locale.MENU_RESERVE_AMOUNT,
      Locale.MENU_RESERVE_AMOUNT_TEXT,
      nil,
      10,
      true
    )

    local amount = tonumber(amountText)
    if amount and amount > 0 then
      if HasGangAccess(gangData, "reserve.edit") then
        if Menu.MenuButton(tostring(amount) .. ".TAKE", "SUBMENU_RESERVE_TAKE", Locale.MENU_RESERVE_TAKE, true) then
          Menu.SetSubTitle(
            "SUBMENU_RESERVE_TAKE",
            Locale("MENU_WARNING_TAKE", { amount = FormatMoney(amount) })
          )
        end
      end

      if Menu.MenuButton(tostring(amount) .. ".GIVE", "SUBMENU_RESERVE_GIVE", Locale.MENU_RESERVE_GIVE, true) then
        Menu.SetSubTitle(
          "SUBMENU_RESERVE_GIVE",
          Locale("MENU_WARNING_GIVE", { amount = FormatMoney(amount) })
        )
      end
    end
  end

  -- Garage list (insert/remove)
  if menuId == "SUBMENU_GARAGE_LIST" then
    local mode = Menu.CurrentValue()

    if mode == "INSERT" then
      for modelHash, vehCfg in pairs(Config.GarageVehicles) do
        if IsModelInCdimage(modelHash) then
          if Menu.MenuButton(modelHash, "SUBMENU_GARAGE_INSERT", vehCfg.label, true) then
            Menu.SetSubTitle("SUBMENU_GARAGE_INSERT", vehCfg.label)
          end
        end
      end
    end

    if mode == "REMOVE" and gangData.vehicles then
      for _, v in ipairs(gangData.vehicles) do
        if IsModelInCdimage(v.model) then
          local plateSuffix = v.plate and (":" .. v.plate) or ""
          local vehicleKey = tostring(v.model) .. "." .. tostring(v.color) .. "_0" .. plateSuffix

          local enabled = true
          if spawnedVehicleNetIdsByKey[vehicleKey] and Config.GangOptions.restrictSpawns then
            enabled = not NetworkDoesEntityExistWithNetworkId(spawnedVehicleNetIdsByKey[vehicleKey])
          end

          local vehCfg = Config.GarageVehicles[v.model]
          if vehCfg then
            if Menu.MenuButton(vehicleKey, "SUBMENU_GARAGE_REMOVE", vehCfg.label, enabled) then
              Menu.SetSubTitle("SUBMENU_GARAGE_REMOVE", vehCfg.label)
            end
          end
        end
      end
    end
  end

  -- Drive vehicle confirm
  if menuId == "SUBMENU_GARAGE_DRIVE" then
    keepShowcaseVehicle = true

    local value = Menu.CurrentValue()
    local modelHash, colorIndex, plate = ParseGarageVehicleKey(value)

    if DoesEntityExist(showcaseVehicleEntity) then
      DisableControlAction(0, 63, true)
      DisableControlAction(0, 64, true)
      DisableControlAction(0, 71, true)
      DisableControlAction(0, 72, true)
    else
      showcaseVehicleEntity = CreateShowcaseVehicle(modelHash, colorIndex, plate)
    end

    if Menu.Button("ACCEPT", Locale.MENU_GARAGE_DRIVE, nil, true) then
      if showcaseVehicleEntity > 0 then
        DeleteEntity(showcaseVehicleEntity)
      end
      showcaseVehicleEntity = 0

      TriggerServerEvent("rcore_gangs:server:drive_vehicle", modelHash, colorIndex, plate)
      Menu.CloseMenu()
    end

    if Menu.Button("REJECT", Locale.MENU_GARAGE_CANCEL, nil, true) then
      if showcaseVehicleEntity > 0 then
        DeleteEntity(showcaseVehicleEntity)
      end
      showcaseVehicleEntity = 0

      Menu.CloseMenu()
    end
  end

  -- Insert vehicle confirm
  if menuId == "SUBMENU_GARAGE_INSERT" then
    keepShowcaseVehicle = true

    local modelHash = Menu.CurrentValue()
    local vehCfg = Config.GarageVehicles[modelHash]
    local colorIndex = 0

    if Config.GangOptions.restrictColors then
      Menu.Button(
        "CLASS",
        Locale.MENU_GARAGE_CLASS,
        Config.VehicleColorClasses[Config.VehicleColorClasses[gangData.color]],
        nil,
        false
      )

      local _, selectedColorIndex = Menu.ComboButton(
        "COLOR",
        Locale.MENU_GARAGE_COLOR,
        Config.VehicleColors[Config.VehicleColorClasses[gangData.color]],
        nil,
        true
      )

      colorIndex = Config.VehicleColors[gangData.color:lower()][selectedColorIndex].index
    else
      local _, selectedClassIndex = Menu.ComboButton(
        "CLASS",
        Locale.MENU_GARAGE_CLASS,
        Config.VehicleColorClasses,
        nil,
        true
      )

      local _, selectedColorIndex = Menu.ComboButton(
        "COLOR",
        Locale.MENU_GARAGE_COLOR,
        Config.VehicleColors[selectedClassIndex],
        nil,
        true
      )

      local classKey = Config.VehicleColorClasses[selectedClassIndex]:lower()
      colorIndex = Config.VehicleColors[classKey][selectedColorIndex].index
    end

    if DoesEntityExist(showcaseVehicleEntity) then
      SetVehicleColours(showcaseVehicleEntity, colorIndex, colorIndex)
      DisableControlAction(0, 63, true)
      DisableControlAction(0, 64, true)
      DisableControlAction(0, 71, true)
      DisableControlAction(0, 72, true)
    else
      showcaseVehicleEntity = CreateShowcaseVehicle(modelHash, colorIndex)
    end

    if Menu.Button("ACCEPT", Locale.MENU_GARAGE_INSERT2, FormatMoney(vehCfg.price), true) then
      local plate = GetVehicleNumberPlateText(showcaseVehicleEntity)

      if showcaseVehicleEntity > 0 then
        DeleteEntity(showcaseVehicleEntity)
      end
      showcaseVehicleEntity = 0

      TriggerServerEvent("rcore_gangs:server:purchase_vehicle", modelHash, colorIndex, plate)
      Menu.CloseMenu()
    end

    if Menu.Button("REJECT", Locale.MENU_GARAGE_CANCEL, nil, true) then
      if showcaseVehicleEntity > 0 then
        DeleteEntity(showcaseVehicleEntity)
      end
      showcaseVehicleEntity = 0

      Menu.CloseMenu()
    end
  end

  -- Remove vehicle confirm
  if menuId == "SUBMENU_GARAGE_REMOVE" then
    keepShowcaseVehicle = true

    local value = Menu.CurrentValue()
    local modelHash, colorIndex, plate = ParseGarageVehicleKey(value)

    if DoesEntityExist(showcaseVehicleEntity) then
      DisableControlAction(0, 63, true)
      DisableControlAction(0, 64, true)
      DisableControlAction(0, 71, true)
      DisableControlAction(0, 72, true)
    else
      showcaseVehicleEntity = CreateShowcaseVehicle(modelHash, colorIndex, plate)
    end

    if Menu.Button("ACCEPT", Locale.MENU_GARAGE_REMOVE2, nil, true) then
      if showcaseVehicleEntity > 0 then
        DeleteEntity(showcaseVehicleEntity)
      end
      showcaseVehicleEntity = 0

      TriggerServerEvent("rcore_gangs:server:remove_vehicle", modelHash, colorIndex)
      Menu.CloseMenu()
    end

    if Menu.Button("REJECT", Locale.MENU_GARAGE_CANCEL, nil, true) then
      if showcaseVehicleEntity > 0 then
        DeleteEntity(showcaseVehicleEntity)
      end
      showcaseVehicleEntity = 0

      Menu.CloseMenu()
    end
  end

  -- Reserve: take
  if menuId == "SUBMENU_RESERVE_TAKE" then
    local value = Menu.CurrentValue()
    local dotIndex = value:find("%.")
    local amount = dotIndex and tonumber(value:sub(1, dotIndex - 1)) or nil

    if Menu.Button("ACCEPT", Locale.MENU_BUTTON_CONFIRM, nil, true) then
      TriggerServerEvent("rcore_gangs:server:take_balance", amount)
      Menu.CloseMenu()
    end

    if Menu.Button("REJECT", Locale.MENU_BUTTON_CANCEL, nil, true) then
      Menu.CloseMenu()
    end
  end

  -- Reserve: give
  if menuId == "SUBMENU_RESERVE_GIVE" then
    local value = Menu.CurrentValue()
    local dotIndex = value:find("%.")
    local amount = dotIndex and tonumber(value:sub(1, dotIndex - 1)) or nil

    if Menu.Button("ACCEPT", Locale.MENU_BUTTON_CONFIRM, nil, true) then
      TriggerServerEvent("rcore_gangs:server:give_balance", amount)
      Menu.CloseMenu()
    end

    if Menu.Button("REJECT", Locale.MENU_BUTTON_CANCEL, nil, true) then
      Menu.CloseMenu()
    end
  end

  -- Cleanup preview vehicle when leaving preview contexts
  if not keepShowcaseVehicle then
    if showcaseVehicleEntity > 0 then
      DeleteEntity(showcaseVehicleEntity)
    end
    showcaseVehicleEntity = 0
  end
end

-- Keep the exported/global name exactly
CheckpointMenu = CheckpointMenu

-- ==============================================================
-- Net events (names unchanged, handlers anonymous)
-- ==============================================================

RegisterNetEvent("rcore_gangs:client:set_vehicles")
AddEventHandler("rcore_gangs:client:set_vehicles", function(vehiclesByKey)
  spawnedVehicleNetIdsByKey = vehiclesByKey
end)

RegisterNetEvent("rcore_gangs:client:set_vehicle_keys")
AddEventHandler("rcore_gangs:client:set_vehicle_keys", function(vehicleNetId)
  Wait(1000)
  local vehicleEntity, extra = NetworkGetEntityFromNetworkId(vehicleNetId)
  Framework.SetVehicleKeys(vehicleEntity, extra)
end)