-- render.lua

local zoneAreaBlips = {}
local showZonesEnabled = true

local zoneHudData = {
  vehicle = {},
  gang = {},
  zone = {},
  street = {}
}

local zoneHudCache = {
  vehicle = {},
  gang = {},
  zone = {},
  street = {}
}

AddTextEntry("ZONE_HUD", "~a~~n~~a~~n~~a~~n~~a~")

RegisterCommand((Config.Commands and Config.Commands.SHOWZONES) or "showzones", function(source, args, rawCommand)
  showZonesEnabled = not showZonesEnabled
  RenderZones()
end)

function CreateZoneAreaBlip(zoneKey, x1, y1, x2, y2)
  local centerX = (x1 + x2) / 2
  local centerY = (y1 + y2) / 2
  local width = math.abs(x1 - x2)
  local height = math.abs(y1 - y2)

  local blip = AddBlipForArea(centerX, centerY, 0.0, width, height)

  local color = 0
  local alpha = 80

  if Config.GangZones[zoneKey] and Config.GangZones[zoneKey].gangName then
    color = Config.ColorToMapColor[Config.GangZones[zoneKey].gangColor]
    alpha = 130
  end

  SetBlipColour(blip, color)
  SetBlipAlpha(blip, alpha)
  SetBlipAsShortRange(blip, true)
  SetBlipDisplay(blip, 3)

  return blip
end

function RenderZones()
  local gang = Gang

  DebugLog("^1RenderZones()^7 Start of the function")

  local canRenderZones = showZonesEnabled and (gang ~= nil or (Config.ZoneOptions and Config.ZoneOptions.showZonesEveryone))
  if not canRenderZones then
    DebugLog("^1RenderZones()^7 Removing blips")

    for partKey, blipData in pairs(zoneAreaBlips) do
      RemoveBlip(blipData.handle)
      zoneAreaBlips[partKey] = nil
    end

    DebugLog("^1RenderZones()^7 done with blips")
    return
  end

  DebugLog("^1RenderZones()^7 Start with zone cycle")

  for zoneKey, zoneData in pairs(Config.GangZones) do
    Wait(0)

    local parts = zoneData.parts or zoneData.zoneParts
    if parts then
      for partIndex, part in ipairs(parts) do
        local partKey = zoneKey .. "_" .. partIndex
        local expectedColor = Config.ColorToMapColor[zoneData.gangColor]

        local cached = zoneAreaBlips[partKey]
        if cached and cached.color ~= expectedColor then
          RemoveBlip(cached.handle)
          cached = nil
          zoneAreaBlips[partKey] = nil
        end

        if not cached then
          cached = {
            handle = CreateZoneAreaBlip(zoneKey, part.x1, part.y1, part.x2, part.y2),
            color = expectedColor
          }
          zoneAreaBlips[partKey] = cached
        end

        local shouldFlash = false
        if gang then
          if zoneData.gangOwnership and zoneData.rivalGangOwnership and zoneData.localGangOwnership then
            if gang.name == zoneData.gangName then
              if zoneData.rivalGangOwnership > 0 then
                local minVal = math.min(zoneData.gangOwnership, zoneData.rivalGangOwnership)
                local maxVal = math.max(zoneData.gangOwnership, zoneData.rivalGangOwnership)
                shouldFlash = (minVal / maxVal) > 0.8
              end
            else
              local minVal = math.min(zoneData.gangOwnership, zoneData.localGangOwnership)
              local maxVal = math.max(zoneData.gangOwnership, zoneData.localGangOwnership)
              shouldFlash = (minVal / maxVal) > 0.8
            end
          end
        end

        if cached then
          SetBlipFlashes(cached.handle, shouldFlash)
        end
      end
    end
  end

  DebugLog("^1RenderZones()^7 Done! with zone cycle")
end

function DrawZoneHudText(x, y, alpha, line1, line2, line3, line4)
  BeginTextCommandDisplayText("ZONE_HUD")

  local a = line1
  local b = line2 or a
  local c = line3 or b
  local d = line4 or c

  if not a or a == b or a == c or a == d then a = "" end
  if not b or b == c or b == d then b = "" end
  if not c or c == d then c = "" end
  if not d then d = "" end

  AddTextComponentSubstringPlayerName(a)
  AddTextComponentSubstringPlayerName(b)
  AddTextComponentSubstringPlayerName(c)
  AddTextComponentSubstringPlayerName(d)

  SetTextFont(1)
  SetTextWrap(0.0, 0.98)
  SetTextScale(0.65, 0.65)
  SetTextColour(240, 240, 240, alpha)
  SetTextDropShadow()
  SetTextJustification(2)

  EndTextCommandDisplayText(x, y)
end

ShouldBeZoneRendered = false

if Config.ZoneOptions and Config.ZoneOptions.showHudInfo then
  RegisterCommand("+showzonehudgang", function(source, args, rawCommand)
    ShouldBeZoneRendered = true
  end, false)

  RegisterCommand("-showzonehudgang", function(source, args, rawCommand)
    ShouldBeZoneRendered = false
  end, false)

  RegisterCommand((Config.ZoneOptions and Config.ZoneOptions.showHudInfoCommand) or "showzoneinfo", function(source, args, rawCommand)
    ShouldBeZoneRendered = true
    Wait(5000)
    ShouldBeZoneRendered = false
  end)

  RegisterKeyMapping("+showzonehudgang", "", "keyboard", Config.KeyBinds and Config.KeyBinds.zoneHudInfo)
end

function RenderZoneHud()
  HideHudComponentThisFrame(6)
  HideHudComponentThisFrame(7)
  HideHudComponentThisFrame(8)
  HideHudComponentThisFrame(9)

  if ShouldBeZoneRendered then
    DrawZoneHudText(
      0.5,
      0.82,
      255,
      zoneHudData.vehicle.name,
      zoneHudData.gang.name,
      zoneHudData.zone.name,
      zoneHudData.street.name
    )
  end
end

function SetZoneHud()
  local zone = Zone
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local vehicle = GetVehiclePedIsIn(ped, false)
  local now = GetGameTimer()

  if DoesEntityExist(vehicle) then
    local model = GetEntityModel(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(displayName)

    zoneHudData.vehicle.name = label .. ", " .. Config.VehicleClasses[vehicleClass]
  else
    zoneHudData.vehicle.name = ""
  end

  if zoneHudCache.vehicle.name ~= zoneHudData.vehicle.name then
    zoneHudCache.vehicle.name = zoneHudData.vehicle.name
    zoneHudCache.vehicle.time = now
  elseif not zoneHudCache.vehicle.time then
    zoneHudCache.vehicle.time = now
  end

  if zone and zone.gangName then
    zoneHudData.gang.name =
      Config.ColorToTextColor[zone.gangColor] ..
      zone.gangName ..
      "~s~ (" ..
      zone.gangOwnership ..
      "%)"

    zoneHudData.zone.name = zone.label

    if zoneHudCache.gang.name ~= zoneHudData.gang.name then
      zoneHudCache.gang.name = zoneHudData.gang.name
      zoneHudCache.gang.time = now
    elseif not zoneHudCache.gang.time then
      zoneHudCache.gang.time = now
    end

    if zoneHudCache.zone.name ~= zoneHudData.zone.name then
      zoneHudCache.zone.name = zoneHudData.zone.name
      zoneHudCache.zone.time = now
    elseif not zoneHudCache.zone.time then
      zoneHudCache.zone.time = now
    end
  elseif not zone then
    zoneHudData.gang.name = ""
    zoneHudData.zone.name = Config.ZoneNames[GetNameOfZone(coords.x, coords.y, coords.z)]

    if zoneHudCache.zone.name ~= zoneHudData.zone.name then
      zoneHudCache.zone.name = zoneHudData.zone.name
      zoneHudCache.zone.time = now
    elseif not zoneHudCache.zone.time then
      zoneHudCache.zone.time = now
    end
  end

  local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
  local streetName = GetStreetNameFromHashKey(streetHash)

  zoneHudData.street.name = streetName

  if zoneHudCache.street.name ~= zoneHudData.street.name then
    zoneHudCache.street.name = zoneHudData.street.name
    zoneHudCache.street.time = now
  elseif not zoneHudCache.street.time then
    zoneHudCache.street.time = now
  end
end