-- protection.lua

local menu = Menu
local locale = Locale

local currentBusiness = nil
local businessMoneyByName = {}

menu.CreateMenu("MENU_BUSINESS")

IsCloseToAnyBusiness = false

function RenderBusiness()
  IsCloseToAnyBusiness = false

  local gang = Gang
  local zone = Zone

  if not gang or not zone then
    currentBusiness = nil
    return
  end

  if gang.name ~= zone.gangName then
    currentBusiness = nil
    return
  end

  if not gang.leader then
    if not gang.access or not gang.access["protection.collect"] then
      currentBusiness = nil
      return
    end
  end

  local now = GetGameTimer()
  local ped = PlayerPedId()
  local playerCoords = GetEntityCoords(ped)

  if currentBusiness then
    local distance = glm.distance(playerCoords, currentBusiness.checkpoint)

    if distance < 10.0 then
      IsCloseToAnyBusiness = true

      local bg = Config.GangMenuColors[gang.color].background
      DrawMarker(
        1,
        currentBusiness.checkpoint.x,
        currentBusiness.checkpoint.y,
        currentBusiness.checkpoint.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        1.2, 1.2, 1.2,
        bg[1], bg[2], bg[3], 128,
        false, false, 2, false, nil, nil, false
      )

      if distance < 1.0 then
        if menu.CurrentMenu() ~= "MENU_BUSINESS" then
          menu.OpenMenu("MENU_BUSINESS")
        end
      else
        if menu.CurrentMenu() == "MENU_BUSINESS" then
          menu.CloseMenu()
        end
      end
    else
      currentBusiness = nil
      Intervals.protection = now + 5000
    end

    return
  end

  for _, business in pairs(Config.Businesses) do
    if business.zone == zone.name then
      local distance = glm.distance(playerCoords, business.checkpoint)

      if distance < 10.0 then
        IsCloseToAnyBusiness = true
        currentBusiness = business

        menu.SetSubTitle("MENU_BUSINESS", business.label)
        menu.SetTitleBackground(
          "MENU_BUSINESS",
          'url("./images/' .. business.banner .. '.png") center / 22vw 12vh no-repeat'
        )

        break
      end
    end
  end

  if currentBusiness then
    Intervals.protection = now
  else
    Intervals.protection = now + 5000
  end
end

RegisterNetEvent("rcore_gangs:client:set_business_money")
AddEventHandler("rcore_gangs:client:set_business_money", function(businessName, money)
  businessMoneyByName[businessName] = money
end)

function BusinessMenu(currentMenu)
  local gang = Gang
  local zone = Zone

  if not currentBusiness then
    return
  end

  if currentMenu ~= "MENU_BUSINESS" then
    return
  end

  local money = businessMoneyByName[currentBusiness.name]
  if money then
    if menu.Button("PROTECTION", locale.PROTECTION_COLLECT_MONEY, FormatMoney(money), true) then
      TriggerServerEvent("rcore_gangs:server:collect_protection", currentBusiness.name)
    end
  else
    menu.Button("PROTECTION", locale.PROTECTION_MISSING_MONEY, nil, false)
  end
end