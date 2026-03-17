-- server/drugs.lua
-- Drug selling server logic:
--  - decides NPC outcome (accept/reject/report) based on seller recent volume
--  - calculates payout using zone multipliers + zone drug preference + rivalry rules
--  - awards (dirty) money, removes items, increases zone loyalty, updates rivalry sales
--  - keeps a lightweight "already interacted" lock by target netId
--  - tracks cops count and pushes to clients

local zoneSaleMultiplierByZone = {}        -- [zoneName] = multiplier
local zoneSaleCountByZone = {}             -- [zoneName] = recent sales count (30m decay)
local sellerRecentSalesByIdentifier = {}   -- [identifier] = recent sales count (30m decay)
local activeInteractionsByTargetNet = {}   -- [targetNetId] = sellerSrc (prevents double-interaction)
local policeOnDuty = {}                    -- [identifier or src] = true
local cachedPoliceCount = 0

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function isDirtyMoneyEnabled()
  local o = Config.OtherOptions or {}
  return o.dirtyMoney or o.dirtyMoneyItem
end

local function clampIndex(i, max)
  if i < 1 then return 1 end
  if i > max then return max end
  return i
end

local function randomFrom(list)
  if not list or #list == 0 then return nil end
  return list[math.random(1, #list)]
end

local function getDrugCategoryAndPrice(itemName)
  if not itemName then return nil, nil end

  local drugs = Config.Drugs or {}
  local low = drugs.CATEGORY_LOW or {}
  local med = drugs.CATEGORY_MED or {}
  local high = drugs.CATEGORY_HIGH or {}

  if low[itemName] ~= nil then
    return "CATEGORY_LOW", low[itemName]
  end

  if med[itemName] ~= nil then
    return "CATEGORY_MED", med[itemName]
  end

  if high[itemName] ~= nil then
    return "CATEGORY_HIGH", high[itemName]
  end

  return nil, nil
end

local function pickSaleOutcome(identifier)
  -- returns: "accept" | "reject" | "report"
  local roll = math.random(1, 100)

  local chances = Config.DrugSaleChances
  local level = sellerRecentSalesByIdentifier[identifier] or 1

  local acceptChance, rejectChance

  if type(chances) == "table" and #chances > 0 then
    local entry = chances[clampIndex(level, #chances)] or chances[#chances]
    -- expected: {accept, reject, report}
    acceptChance = tonumber(entry[1]) or 35
    rejectChance = tonumber(entry[2]) or 35
  else
    acceptChance = 35
    rejectChance = 35
  end

  if roll <= acceptChance then
    return "accept"
  end

  if roll <= (acceptChance + rejectChance) then
    return "reject"
  end

  return "report"
end

local function refreshSaleMultipliers()
  local zones = Config.GangZones or {}
  local configMultipliers = Config.DrugSaleMultipliers or {}

  for zoneName in pairs(zones) do
    local sold = zoneSaleCountByZone[zoneName]

    -- default multiplier
    local defaultEntry = configMultipliers[#configMultipliers]
    local defaultMultiplier = 1.0

    if defaultEntry then
      defaultMultiplier = tonumber(defaultEntry.multiply or defaultEntry.multiplier) or defaultMultiplier
    elseif configMultipliers[1] then
      defaultMultiplier = tonumber(configMultipliers[1].multiply or configMultipliers[1].multiplier) or defaultMultiplier
    end

    local multiplier = defaultMultiplier

    if sold then
      for _, entry in ipairs(configMultipliers) do
        local threshold = tonumber(entry.sold)
        local m = tonumber(entry.multiply or entry.multiplier)
        if threshold and m and sold <= threshold then
          multiplier = m
          break
        end
      end
    else
      -- if nothing sold recently, use the first tier if present
      local first = configMultipliers[1]
      if first then
        multiplier = tonumber(first.multiply or first.multiplier) or multiplier
      end
    end

    zoneSaleMultiplierByZone[zoneName] = multiplier
  end
end

local function bumpCounterWithDecay(tbl, key, amount, decayMs)
  if not key then return end
  tbl[key] = (tbl[key] or 0) + (amount or 1)

  SetTimeout(decayMs, function()
    local v = tbl[key]
    if v and v > 0 then
      tbl[key] = v - (amount or 1)
      if tbl[key] <= 0 then
        tbl[key] = nil
      end
    end
  end)
end

local function notifySaleMultipliersAll()
  refreshSaleMultipliers()
  TriggerClientEvent("rcore_gangs:client:set_sale_multipliers", -1, zoneSaleMultiplierByZone)
end

local function finalizeDrugSale(sellerSrc, itemName, basePrice, amount, category)
  -- validate required inputs
  if not sellerSrc or not itemName or not basePrice or not amount or not category then return end
  if amount <= 0 or basePrice <= 0 then return end

  local identifier = ServerIdToPlayerId[sellerSrc]
  if not identifier then return end

  local ped = GetPlayerPed(sellerSrc)
  if not ped or ped == 0 then return end

  local coords = GetEntityCoords(ped)
  local gang = ServerIdToGang[sellerSrc]
  local zone = GetZoneAtPosition(coords)
  local rivalry = zone and GetRivalry(zone.name) or nil

  local zoneMultiplier = 1.0
  if zone and zoneSaleMultiplierByZone[zone.name] then
    zoneMultiplier = zoneSaleMultiplierByZone[zone.name]
  end

  local preferenceMultiplier = 0.3
  if zone and zone.drugPreference and zone.drugPreference[category] then
    preferenceMultiplier = preferenceMultiplier -- keep default? no
    preferenceMultiplier = 1.0
  else
    preferenceMultiplier = 0.3
  end

  -- payout
  local payout = basePrice * zoneMultiplier * preferenceMultiplier * amount
  if rivalry then
    payout = math.ceil(payout / 2)
  else
    payout = math.ceil(payout)
  end

  -- inventory check
  local item = Inventory.GetPlayerItem(sellerSrc, itemName)
  if not item then return end
  local have = item.amount or item.count or 0
  if amount > have then return end

  -- counters (30 minutes decay)
  bumpCounterWithDecay(sellerRecentSalesByIdentifier, identifier, 1, 1800000)
  if zone then
    bumpCounterWithDecay(zoneSaleCountByZone, zone.name, 1, 1800000)
    notifySaleMultipliersAll()
  end

  -- money reward
  if isDirtyMoneyEnabled() then
    Framework.AddPlayerDirtyMoney(sellerSrc, payout)
  else
    Framework.AddPlayerMoney(sellerSrc, payout)
  end

  -- discord log
  if logToDiscord and formatDrugDiscordLog then
    local msg, title, fields1, fields2, fields3 = formatDrugDiscordLog(sellerSrc, itemName, amount, payout)
    logToDiscord(sellerSrc, msg, title, fields1, fields2, fields3)
  end

  -- remove items
  Inventory.RemovePlayerItem(sellerSrc, itemName, amount)

  -- loyalty + rivalry
  if gang and zone then
    local loyaltyMultiplier = (Config.IncreaseMultipliers or {}).DRUGS
    if rivalry then
      loyaltyMultiplier = (Config.IncreaseMultipliersRivalry or {}).DRUGS or loyaltyMultiplier
    end

    IncreaseLoyalty(sellerSrc, zone, "DRUGS", zoneMultiplier * preferenceMultiplier, loyaltyMultiplier)

    if rivalry then
      AddRivalrySale(rivalry.id, rivalry.zone, gang.id, payout)
    end
  end
end

local function dispatchIfNeeded(sellerSrc, itemName)
  if not Dispatch then return end
  Dispatch(sellerSrc, itemName)
end

local function sendDrugInteractionToAll(sellerSrc, targetNetId, outcome, category)
  TriggerClientEvent("rcore_gangs:client:drug_interaction", -1, sellerSrc, targetNetId, outcome, category)
end

local function sendDrugNotification(sellerSrc, targetNetId, text)
  TriggerClientEvent("rcore_gangs:client:drug_notification", sellerSrc, targetNetId, text)
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------

RegisterNetEvent("rcore_gangs:server:sell_drugs", function(targetNetId, itemName, amount)
  local src = source

  local category, basePrice = getDrugCategoryAndPrice(itemName)
  if not category or not basePrice then return end
  amount = tonumber(amount) or 0
  if amount <= 0 then return end

  -- already interacted with this ped netId
  if activeInteractionsByTargetNet[targetNetId] then
    sendDrugInteractionToAll(src, targetNetId, "reject", category)
    SetTimeout(2000, function()
      local msg = randomFrom(Config.InteractedMessages or {})
      if msg then sendDrugNotification(src, targetNetId, msg) end
    end)
    return
  end

  -- validate seller and target entities
  local sellerPed = GetPlayerPed(src)
  local targetPed = NetworkGetEntityFromNetworkId(targetNetId)
  if not sellerPed or sellerPed == 0 or not targetPed or targetPed == 0 then return end
  if GetEntityType(sellerPed) ~= 1 or GetEntityType(targetPed) ~= 1 then return end

  local dist = (GetEntityCoords(sellerPed) - GetEntityCoords(targetPed))
  if #(dist) >= 10.0 then return end

  activeInteractionsByTargetNet[targetNetId] = src

  local identifier = ServerIdToPlayerId[src]
  local outcome = pickSaleOutcome(identifier)

  if outcome == "accept" then
    sendDrugInteractionToAll(src, targetNetId, "accept", category)

    SetTimeout(7000, function()
      local msg = randomFrom(Config.AcceptMessages or {})
      if msg then sendDrugNotification(src, targetNetId, msg) end
    end)

    if (Config.DrugOptions or {}).saleAlwaysReport then
      SetTimeout(1000, function()
        dispatchIfNeeded(src, itemName)
      end)
    end

    SetTimeout(7000, function()
      finalizeDrugSale(src, itemName, basePrice, amount, category)
    end)

    return
  end

  if outcome == "reject" then
    sendDrugInteractionToAll(src, targetNetId, "reject", category)

    SetTimeout(2000, function()
      local msg = randomFrom(Config.RejectMessages or {})
      if msg then sendDrugNotification(src, targetNetId, msg) end
    end)

    if (Config.DrugOptions or {}).saleAlwaysReport then
      SetTimeout(1000, function()
        dispatchIfNeeded(src, itemName)
      end)
    end

    return
  end

  -- report
  sendDrugInteractionToAll(src, targetNetId, "report", category)

  SetTimeout(2000, function()
    local msg = randomFrom(Config.ReportMessages or {})
    if msg then sendDrugNotification(src, targetNetId, msg) end
  end)

  SetTimeout(1000, function()
    dispatchIfNeeded(src, itemName)
  end)
end)

RegisterNetEvent("rcore_gangs:server:player_loaded", function(targetSrc)
  local src = targetSrc or source
  TriggerClientEvent("rcore_gangs:client:set_sale_multipliers", src, zoneSaleMultiplierByZone)
end)

-- initial multiplier build
refreshSaleMultipliers()

-- ------------------------------------------------------------
-- Main server thread: integrations, police count sync, cleanup
-- ------------------------------------------------------------

CreateThread(function()
  -- qb-drugs cornerselling integration (optional)
  local qbDrugsState = GetResourceState("qb-drugs")
  if qbDrugsState == "starting" or qbDrugsState == "started" then
    local content = LoadResourceFile("qb-drugs", "server/cornerselling.lua")
    if content and not string.find(content, "rcore_gangs") then
      local s, e = string.find(content, "if%s-hasItem.amount%s->=%s-amount%s-then%s-\n")
      if s and e then
        local before = string.sub(content, 1, e)
        local insert = "\t\tTriggerEvent('rcore_gangs:server:increase_loyalty', src, 'DRUGS', 1.0)\n"
        local after = string.sub(content, e + 1)
        SaveResourceFile("qb-drugs", "server/cornerselling.lua", before .. insert .. after, -1)
        print("^2[GANGS] CORNERSELLING INTEGRATED, PLEASE RESTART YOUR SERVER!^7")
      end
    end
  end

  -- ESX job updates
  AddEventHandler("esx:setJob", function(playerId, job)
    if not playerId or not job or not job.name then return end

    local isPolice = (Config.PoliceJobs or {})[job.name] == true
    local wasPolice = policeOnDuty[playerId] == true

    if wasPolice and not isPolice then
      policeOnDuty[playerId] = nil
      cachedPoliceCount = math.max(0, cachedPoliceCount - 1)
      TriggerClientEvent("rcore_gangs:client:set_cops", -1, cachedPoliceCount)
    elseif (not wasPolice) and isPolice then
      policeOnDuty[playerId] = true
      cachedPoliceCount = cachedPoliceCount + 1
      TriggerClientEvent("rcore_gangs:client:set_cops", -1, cachedPoliceCount)
    end
  end)

  -- QB job updates (onduty aware)
  AddEventHandler("QBCore:Server:OnJobUpdate", function(src, job)
    if not src or not job or not job.name then return end

    local identifier = Framework.GetPlayerId(src)
    if not identifier then return end

    local isPoliceJob = (Config.PoliceJobs or {})[job.name] == true
    local onduty = job.onduty == true

    local key = identifier -- keep original behavior (identifier keyed)
    local wasPolice = policeOnDuty[key] == true
    local shouldBePolice = isPoliceJob and onduty

    if wasPolice and not shouldBePolice then
      policeOnDuty[key] = nil
      cachedPoliceCount = math.max(0, cachedPoliceCount - 1)
      TriggerClientEvent("rcore_gangs:client:set_cops", -1, cachedPoliceCount)
    elseif (not wasPolice) and shouldBePolice then
      policeOnDuty[key] = true
      cachedPoliceCount = cachedPoliceCount + 1
      TriggerClientEvent("rcore_gangs:client:set_cops", -1, cachedPoliceCount)
    end
  end)

  -- periodic police resync + stale interaction cleanup
  while true do
    Wait(300000) -- 5 minutes

    local frameworkCops = Framework.GetPoliceCount and Framework.GetPoliceCount() or cachedPoliceCount
    if frameworkCops ~= cachedPoliceCount then
      cachedPoliceCount = frameworkCops
      TriggerClientEvent("rcore_gangs:client:set_cops", -1, cachedPoliceCount)
    end

    for netId in pairs(activeInteractionsByTargetNet) do
      local ent = NetworkGetEntityFromNetworkId(netId)
      if not ent or ent == 0 or not DoesEntityExist(ent) then
        activeInteractionsByTargetNet[netId] = nil
      end
    end
  end
end, (SessionNames and SessionNames.MAIN_SERVER_THREAD) or nil)

-- drugs_creator integration (optional)
AddEventHandler("drugs_creator:soldToNPC", function(src)
  TriggerEvent("rcore_gangs:server:increase_loyalty", src, "DRUGS", 1.0)
end)

-- ensure police jobs config exists
Citizen.CreateThread(function()
  if not Config.PoliceJobs then
    Config.PoliceJobs = { police = true }
  end
end)
