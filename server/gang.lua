-- server/gangs.lua (CLEAN)
-- Core gang management (create/delete/invite/join/leave/kick/rank/leader transfer)
-- Notes:
-- - Relies on globals populated elsewhere: Gangs, Zones, PlayerIdToGang, ServerIdToGang,
--   PlayerIdToServerId, ServerIdToPlayerId, SetPlayerGang, GetPlayerGang, RefreshRivalries,
--   GetRivalry, SQL, Framework, Locale.
-- - Keeps original behavior: leader is stored in `gangs.identifier` (player identifier).

local invitesByTargetSrc = {} -- [targetSrc] = gangId (expires)

-- ------------------------------------------------------------
-- Locale + notify helpers (handles Locale as function or table)
-- ------------------------------------------------------------

local function tr(key, vars)
  if type(Locale) == "function" then
    return Locale(key, vars)
  end

  if type(Locale) == "table" then
    local v = Locale[key]
    if type(v) == "function" then
      return v(vars)
    end
    return v or key
  end

  return key
end

local function notify(src, msgOrKey, vars)
  if not src then return end
  local msg = vars and tr(msgOrKey, vars) or (tr(msgOrKey) or msgOrKey)
  Framework.ShowNotification(src, msg)
end

local function trimLower(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return string.lower(s)
end

-- ------------------------------------------------------------
-- Resolve helpers
-- ------------------------------------------------------------

local function resolveOnlinePlayer(playerKey)
  -- Accepts serverId (number or numeric string) OR identifier (string)
  if playerKey == nil then return nil end

  if type(playerKey) == "string" then
    local n = tonumber(playerKey)
    if n then playerKey = n end
  end

  if type(playerKey) == "number" then
    local identifier = ServerIdToPlayerId[playerKey]
    if not identifier then return nil end
    return { src = playerKey, identifier = identifier }
  end

  if type(playerKey) == "string" then
    local src = PlayerIdToServerId[playerKey]
    if not src then return nil end
    return { src = src, identifier = playerKey }
  end

  return nil
end

local function findGangByKey(key)
  -- key can be:
  --  - gang id (number / numeric string)
  --  - tag / name (string) - case/space insensitive
  if key == nil then return nil end

  -- numeric
  if type(key) == "string" then
    local n = tonumber(key)
    if n then key = n end
  end

  if type(key) == "number" then
    return Gangs[key]
  end

  if type(key) ~= "string" then
    return nil
  end

  local wanted = trimLower(key)
  if not wanted or wanted == "" then return nil end

  -- Prefer in-memory first
  for _, gang in pairs(Gangs) do
    if trimLower(gang.tag) == wanted or trimLower(gang.name) == wanted then
      return gang
    end
  end

  -- Fallback: DB scan (matches original behavior)
  if SQL and SQL.GetGangs then
    local rows = SQL.GetGangs()
    if rows then
      for _, row in ipairs(rows) do
        if trimLower(row.tag) == wanted or trimLower(row.name) == wanted then
          return Gangs[row.id] -- only return if loaded in memory
        end
      end
    end
  end

  return nil
end

GetGangFromKey = findGangByKey

local function playerHasGang(identifier, src)
  if src and ServerIdToGang[src] then return true end
  if identifier and PlayerIdToGang[identifier] then return true end
  return false
end

local function hasGangPermission(gang, permKey)
  if not gang then return false end
  if gang.leader then return true end
  local access = gang.access
  if type(access) ~= "table" then return false end
  return access[permKey] == true
end

local function isValidGangColor(colorName)
  if type(colorName) ~= "string" then return false end
  local key = trimLower(colorName)
  if not key then return false end

  local ok1 = Config.ColorToMapColor and Config.ColorToMapColor[key] ~= nil
  local ok2 = Config.ColorToTextColor and Config.ColorToTextColor[key] ~= nil
  local ok3 = Config.GangMenuColors and Config.GangMenuColors[key] ~= nil
  return ok1 and ok2 and ok3
end

local function isValidRanksGroup(groupName)
  if type(groupName) ~= "string" then return false end
  local rg = Config.RanksGroups
  return type(rg) == "table" and rg[groupName] ~= nil
end

local function tagOrNameTaken(tag, name)
  local wantTag = trimLower(tag)
  local wantName = trimLower(name)
  for _, g in pairs(Gangs) do
    if wantTag and wantTag ~= "" and trimLower(g.tag) == wantTag then return true end
    if wantName and wantName ~= "" and trimLower(g.name) == wantName then return true end
  end
  return false
end

local function refreshGangMembers(gang)
  if not gang or not gang.id then return end
  if SQL and SQL.GetGangMembers then
    gang.members = SQL.GetGangMembers(gang.id) or {}
  end
end

local function syncGangToAllMembers(gang)
  if not gang or not gang.members then return end
  for _, m in ipairs(gang.members) do
    local memberSrc = PlayerIdToServerId[m.identifier]
    if memberSrc then
      SetPlayerGang(memberSrc)
    end
  end
end

-- ------------------------------------------------------------
-- Gang actions
-- ------------------------------------------------------------

function CreateGang(adminSrc, leaderKey, color, group, tag, name)
  if not leaderKey then
    notify(adminSrc, "COMMAND_MISSING_LEADER")
    return tr("COMMAND_MISSING_LEADER")
  end

  if not color then
    notify(adminSrc, "COMMAND_MISSING_COLOR")
    return tr("COMMAND_MISSING_COLOR")
  end

  if not group then
    notify(adminSrc, "COMMAND_MISSING_GROUP")
    return tr("COMMAND_MISSING_GROUP")
  end

  if not tag then
    notify(adminSrc, "COMMAND_MISSING_TAG")
    return tr("COMMAND_MISSING_TAG")
  end

  if not name then
    notify(adminSrc, "COMMAND_MISSING_NAME")
    return tr("COMMAND_MISSING_NAME")
  end

  local leader = resolveOnlinePlayer(leaderKey)
  if not leader then
    notify(adminSrc, "COMMAND_INVALID_LEADER1")
    return tr("COMMAND_INVALID_LEADER1")
  end

  if playerHasGang(leader.identifier, leader.src) then
    notify(adminSrc, "COMMAND_INVALID_LEADER2")
    return tr("COMMAND_INVALID_LEADER2")
  end

  if not isValidGangColor(color) then
    notify(adminSrc, "COMMAND_INVALID_COLOR")
    return tr("COMMAND_INVALID_COLOR")
  end

  if not isValidRanksGroup(group) then
    notify(adminSrc, "COMMAND_INVALID_GROUP")
    return tr("COMMAND_INVALID_GROUP")
  end

  if type(tag) ~= "string" or #tag > 10 then
    notify(adminSrc, "COMMAND_INVALID_TAG1")
    return tr("COMMAND_INVALID_TAG1")
  end

  if tagOrNameTaken(tag, nil) then
    notify(adminSrc, "COMMAND_INVALID_TAG2")
    return tr("COMMAND_INVALID_TAG2")
  end

  if type(name) ~= "string" or #name > 32 then
    notify(adminSrc, "COMMAND_INVALID_NAME1")
    return tr("COMMAND_INVALID_NAME1")
  end

  if tagOrNameTaken(nil, name) then
    notify(adminSrc, "COMMAND_INVALID_NAME2")
    return tr("COMMAND_INVALID_NAME2")
  end

  -- Build gang object
  local ranks = Config.RanksGroups[group].ranks
  local leaderRankLabel = ranks[#ranks].label

  if SQL and SQL.Execute then
    SQL.Execute("ANALYZE TABLE gangs")
  end

  local gangId
  if SQL and SQL.Scalar then
    gangId = SQL.Scalar("SELECT AUTO_INCREMENT FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gangs'")
  end
  if not gangId then
    -- fallback: pick max+1 (should not happen if DB present)
    local maxId = 0
    for id in pairs(Gangs) do
      if id > maxId then maxId = id end
    end
    gangId = maxId + 1
  end

  local gang = {
    id = gangId,
    identifier = leader.identifier,
    tag = tag,
    name = name,
    color = color,
    group = group,
    balance = 0,
    ranks = ranks,
    vehicles = {},
  }

  -- Persist
  if SQL and SQL.InsertGang then
    local memberJson = json.encode({ id = gangId, rank = leaderRankLabel, group = group })
    SQL.InsertGang(gang.identifier, gang.color, gang.group, gang.tag, gang.name, memberJson)
  end

  -- Cache + members
  Gangs[gang.id] = gang
  refreshGangMembers(gang)

  -- Framework-side gang creation (optional override mode)
  if Config.OverrideGangs then
    Framework.CreateGang(gang)
  end

  -- set leader gang on server/cache/client
  SetPlayerGang(leader.src)

  -- Notify
  if adminSrc then
    notify(adminSrc, "GANG_SUCCESS_CREATE", { gang = name })
    notify(leader.src, "GANG_SUCCESS_JOIN", { gang = name })
  end

  return nil
end

function DeleteGang(adminSrc, gangKey)
  local gang = findGangByKey(gangKey)
  if not gang then
    notify(adminSrc, "COMMAND_INVALID_GANG")
    return tr("COMMAND_INVALID_GANG")
  end

  if SQL and SQL.DeleteGang then
    SQL.DeleteGang(gang.id)
  end
  Gangs[gang.id] = nil

  -- Kick everyone out (online only)
  refreshGangMembers(gang)
  for _, m in ipairs(gang.members or {}) do
    local memberSrc = PlayerIdToServerId[m.identifier]
    if memberSrc then
      SetPlayerGang(memberSrc)
      notify(memberSrc, "GANG_SUCCESS_KICK", { gang = gang.name })
    end
  end

  -- Remove zones owned by this gang
  for k, z in pairs(Zones) do
    if z and z.gangId == gang.id then
      Zones[k] = nil
      local rivalry = GetRivalry and GetRivalry(z.name)
      if rivalry and (rivalry.attacker == gang.id or rivalry.defender == gang.id) then
        TriggerClientEvent("rcore_gangs:client:set_rivalry", -1, rivalry.zone, nil)
      end
    end
  end

  TriggerClientEvent("rcore_gangs:client:set_zones", -1, Zones)
  TriggerClientEvent("rcore_gangs:client:set_finished_rivalry", -1, gang.id, nil)

  if RefreshRivalries then
    RefreshRivalries()
  end

  if adminSrc then
    notify(adminSrc, "GANG_SUCCESS_DELETE", { gang = gang.name })
  end

  return nil
end

local function resolveMemberInGang(gang, memberKey)
  -- memberKey can be serverId, identifier, or (if offline) identifier
  if not gang or not gang.members then return nil end

  local online = resolveOnlinePlayer(memberKey)
  if online then
    return online
  end

  if type(memberKey) == "string" and memberKey ~= "" then
    for _, m in ipairs(gang.members) do
      if m.identifier == memberKey then
        return { src = nil, identifier = memberKey }
      end
    end
  end

  return nil
end

function AddMember(actorSrc, targetKey, gangKey)
  local gang = findGangByKey(gangKey)

  if not gang then
    -- if no explicit gang given, allow leader to operate on own gang (original behavior)
    if actorSrc then
      gang = ServerIdToGang[actorSrc]
    end
  end

  if not gang then
    notify(actorSrc, "COMMAND_INVALID_GANG")
    return tr("COMMAND_INVALID_GANG")
  end

  local target = resolveOnlinePlayer(targetKey)
  if not target then
    notify(actorSrc, "GANG_ERROR_PLAYER")
    return tr("GANG_ERROR_PLAYER")
  end

  refreshGangMembers(gang)

  local maxMembers = (Config.GangOptions and Config.GangOptions.maxMembers) or 0
  if maxMembers > 0 and #gang.members >= maxMembers then
    notify(actorSrc, "GANG_ERROR_LIMIT")
    return tr("GANG_ERROR_LIMIT")
  end

  local existing = PlayerIdToGang[target.identifier]
  if existing then
    if existing.id == gang.id then
      notify(actorSrc, "GANG_ERROR_MEMBER")
      return tr("GANG_ERROR_MEMBER")
    end
    notify(actorSrc, "GANG_ERROR_RIVAL")
    return tr("GANG_ERROR_RIVAL")
  end

  local joinRank = gang.ranks[1].label
  local payload = json.encode({ id = gang.id, rank = joinRank, group = gang.group })

  if SQL and SQL.SetPlayerGang then
    SQL.SetPlayerGang(target.identifier, payload)
  end

  refreshGangMembers(gang)
  syncGangToAllMembers(gang)
  if target.src then
    SetPlayerGang(target.src)
  end

  notify(actorSrc, "GANG_SUCCESS_ADD", { gang = gang.name })
  notify(target.src, "GANG_SUCCESS_JOIN", { gang = gang.name })

  return nil
end

function KickMember(actorSrc, targetKey, gangKey)
  local gang = findGangByKey(gangKey)
  if not gang then
    gang = ServerIdToGang[actorSrc]
  end
  if not gang then
    notify(actorSrc, "COMMAND_INVALID_GANG")
    return tr("COMMAND_INVALID_GANG")
  end

  -- permissions: leader OR access["members.kick"]
  local myGang = actorSrc and ServerIdToGang[actorSrc] or nil
  if not gangKey then
    if not hasGangPermission(myGang, "members.kick") then
      notify(actorSrc, "COMMAND_INVALID_GANG")
      return tr("COMMAND_INVALID_GANG")
    end
  end

  refreshGangMembers(gang)
  local target = resolveMemberInGang(gang, targetKey)
  if not target then
    notify(actorSrc, "GANG_ERROR_PLAYER")
    return tr("GANG_ERROR_PLAYER")
  end

  if SQL and SQL.SetPlayerGang then
    SQL.SetPlayerGang(target.identifier, nil)
  end

  refreshGangMembers(gang)
  syncGangToAllMembers(gang)
  if target.src then
    SetPlayerGang(target.src)
    notify(target.src, "GANG_SUCCESS_KICK", { gang = gang.name })
  end

  notify(actorSrc, "GANG_LEADER_KICK")
  return nil
end

function SetMemberRank(actorSrc, targetKey, rankKeyOrIndex, gangKey)
  local gang = findGangByKey(gangKey)
  if not gang then
    gang = ServerIdToGang[actorSrc]
  end
  if not gang then
    notify(actorSrc, "COMMAND_INVALID_GANG")
    return tr("COMMAND_INVALID_GANG")
  end

  -- permissions: leader OR access["members.rank"]
  local myGang = actorSrc and ServerIdToGang[actorSrc] or nil
  if not gangKey then
    if not hasGangPermission(myGang, "members.rank") then
      notify(actorSrc, "COMMAND_INVALID_GANG")
      return tr("COMMAND_INVALID_GANG")
    end
  end

  refreshGangMembers(gang)
  local target = resolveMemberInGang(gang, targetKey)
  if not target then
    notify(actorSrc, "GANG_ERROR_PLAYER")
    return tr("GANG_ERROR_PLAYER")
  end

  -- resolve rank index
  local rankIndex = nil
  if type(rankKeyOrIndex) == "string" then
    local n = tonumber(rankKeyOrIndex)
    if n then
      rankIndex = n
    else
      local wanted = trimLower(rankKeyOrIndex)
      for i, r in ipairs(gang.ranks or {}) do
        if trimLower(r.label) == wanted then
          rankIndex = i
          break
        end
      end
    end
  elseif type(rankKeyOrIndex) == "number" then
    rankIndex = rankKeyOrIndex
  end

  local rank = gang.ranks and gang.ranks[rankIndex or -1] or nil
  if not rank then
    notify(actorSrc, "GANG_ERROR_RANK")
    return tr("GANG_ERROR_RANK")
  end

  -- no-op if already same
  for _, m in ipairs(gang.members) do
    if m.identifier == target.identifier and m.rank == rank.label then
      return nil
    end
  end

  local payload = json.encode({ id = gang.id, rank = rank.label, group = gang.group })
  if SQL and SQL.SetPlayerGang then
    SQL.SetPlayerGang(target.identifier, payload)
  end

  refreshGangMembers(gang)
  syncGangToAllMembers(gang)
  if target.src then
    notify(target.src, "GANG_PLAYER_RANK", { rank = rank.label })
  end
  notify(actorSrc, "GANG_LEADER_RANK")
  return nil
end

function SetMemberLeader(actorSrc, targetKey, gangKey)
  local gang = findGangByKey(gangKey)
  if not gang then
    gang = ServerIdToGang[actorSrc]
  end
  if not gang then
    notify(actorSrc, "COMMAND_INVALID_GANG")
    return tr("COMMAND_INVALID_GANG")
  end

  -- only leader (original behavior)
  local myGang = actorSrc and ServerIdToGang[actorSrc] or nil
  if not gangKey then
    if not myGang or not myGang.leader then
      notify(actorSrc, "COMMAND_INVALID_GANG")
      return tr("COMMAND_INVALID_GANG")
    end
  end

  refreshGangMembers(gang)
  local target = resolveMemberInGang(gang, targetKey)
  if not target then
    notify(actorSrc, "GANG_ERROR_PLAYER")
    return tr("GANG_ERROR_PLAYER")
  end

  -- Update gangs table leader identifier
  if SQL and SQL.Execute then
    SQL.Execute("UPDATE gangs SET identifier = @identifier WHERE id = @id", {
      ["@id"] = gang.id,
      ["@identifier"] = target.identifier
    })
  end

  -- New leader gets top rank (last), old leader drops to lowest (first)
  local leaderRank = gang.ranks[#gang.ranks].label
  local memberRank = gang.ranks[1].label

  if SQL and SQL.SetPlayerGang then
    SQL.SetPlayerGang(target.identifier, json.encode({ id = gang.id, rank = leaderRank, group = gang.group }))
    SQL.SetPlayerGang(gang.identifier, json.encode({ id = gang.id, rank = memberRank, group = gang.group }))
  end

  gang.identifier = target.identifier
  refreshGangMembers(gang)
  syncGangToAllMembers(gang)

  if target.src then
    notify(target.src, "GANG_PLAYER_SHIP", { gang = gang.name })
  end
  notify(actorSrc, "GANG_LEADER_SHIP")
  return nil
end

function LeaveGang(actorSrc, targetKey, gangKey)
  local gang = findGangByKey(gangKey)
  if not gang then
    gang = ServerIdToGang[actorSrc]
  end
  if not gang then
    notify(actorSrc, "COMMAND_INVALID_GANG")
    return tr("COMMAND_INVALID_GANG")
  end

  -- default target is actor
  local target = resolveOnlinePlayer(targetKey or actorSrc)
  if not target then
    notify(actorSrc, "GANG_ERROR_PLAYER")
    return tr("GANG_ERROR_PLAYER")
  end

  if SQL and SQL.SetPlayerGang then
    SQL.SetPlayerGang(target.identifier, nil)
  end

  refreshGangMembers(gang)
  syncGangToAllMembers(gang)
  if target.src then
    SetPlayerGang(target.src)
  end

  notify(actorSrc, "GANG_SUCCESS_LEAVE", { gang = gang.name })
  return nil
end

function DisbandGang(actorSrc, targetKey, gangKey)
  local gang = findGangByKey(gangKey)
  if not gang then
    gang = ServerIdToGang[actorSrc]
  end
  if not gang then
    notify(actorSrc, "COMMAND_INVALID_GANG")
    return tr("COMMAND_INVALID_GANG")
  end

  -- must be leader if using own gang
  local myGang = actorSrc and ServerIdToGang[actorSrc] or nil
  if not gangKey then
    if not myGang or not myGang.leader then
      notify(actorSrc, "COMMAND_INVALID_GANG")
      return tr("COMMAND_INVALID_GANG")
    end
  end

  -- reuse delete
  DeleteGang(actorSrc, gang.id)
  notify(actorSrc, "GANG_SUCCESS_DISBAND", { gang = gang.name })
  return nil
end

function OpenPlayerManageMenu(src)
  if not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end
  TriggerClientEvent("rcore_gangs:client:set_gangs", src, Gangs)
end

-- ------------------------------------------------------------
-- Commands
-- ------------------------------------------------------------

RegisterCommand((Config.Commands and Config.Commands.MANAGEGANG) or "managegang", function(src)
  OpenPlayerManageMenu(src)
end)

RegisterCommand((Config.Commands and Config.Commands.CREATEGANG) or "creategang", function(src)
  OpenPlayerManageMenu(src)
end)

RegisterCommand((Config.Commands and Config.Commands.DELETEGANG) or "deletegang", function(src, args)
  if not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end

  local key = args and args[1] or nil
  if not key then
    notify(src, "COMMAND_MISSING_GANG")
    return
  end

  DeleteGang(src, key)
end)

RegisterCommand((Config.Commands and Config.Commands.ACCEPTGANG) or "acceptgang", function(src)
  local gangId = invitesByTargetSrc[src]
  if not gangId then
    notify(src, "GANG_ERROR_INVITE")
    return
  end

  local gang = Gangs[gangId]
  invitesByTargetSrc[src] = nil

  if not gang then
    notify(src, "COMMAND_INVALID_GANG")
    return
  end

  local identifier = ServerIdToPlayerId[src]
  if not identifier then return end

  local joinRank = gang.ranks[1].label
  if SQL and SQL.SetPlayerGang then
    SQL.SetPlayerGang(identifier, json.encode({ id = gang.id, rank = joinRank, group = gang.group }))
  end

  refreshGangMembers(gang)
  syncGangToAllMembers(gang)
  SetPlayerGang(src)

  notify(src, "GANG_SUCCESS_JOIN", { gang = gang.name })
end)

-- ------------------------------------------------------------
-- Net events (used by UI)
-- ------------------------------------------------------------

RegisterNetEvent("rcore_gangs:server:create_gang", function(leaderKey, color, group, tag, name)
  local src = source
  if not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end
  CreateGang(src, leaderKey, color, group, tag, name)
end)

RegisterNetEvent("rcore_gangs:server:delete_gang", function(gangKey)
  local src = source
  if not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end
  DeleteGang(src, gangKey)
end)

RegisterNetEvent("rcore_gangs:server:add_member", function(targetKey, gangKey)
  local src = source

  -- if gangKey provided, treat as staff action
  if gangKey and not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end

  -- else require leader
  if not gangKey then
    local myGang = ServerIdToGang[src]
    if not myGang or not myGang.leader then return end
  end

  AddMember(src, targetKey, gangKey)
end)

RegisterNetEvent("rcore_gangs:server:kick_member", function(targetKey, gangKey)
  local src = source

  if gangKey and not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end

  if not gangKey then
    local myGang = ServerIdToGang[src]
    if not hasGangPermission(myGang, "members.kick") then return end
  end

  KickMember(src, targetKey, gangKey)
end)

RegisterNetEvent("rcore_gangs:server:invite_member", function(targetSrc)
  local src = source
  if invitesByTargetSrc[targetSrc] then return end

  local myGang = ServerIdToGang[src]
  if not myGang then return end
  if not hasGangPermission(myGang, "members.invite") then return end

  refreshGangMembers(myGang)
  local maxMembers = (Config.GangOptions and Config.GangOptions.maxMembers) or 0
  if maxMembers > 0 and #myGang.members >= maxMembers then
    notify(src, "GANG_ERROR_LIMIT")
    return
  end

  local targetGang = ServerIdToGang[targetSrc]
  if targetGang then
    if targetGang.id == myGang.id then
      notify(src, "GANG_ERROR_MEMBER")
    else
      notify(src, "GANG_ERROR_RIVAL")
    end
    return
  end

  invitesByTargetSrc[targetSrc] = myGang.id
  SetTimeout(60000, function()
    invitesByTargetSrc[targetSrc] = nil
  end)

  notify(src, "GANG_LEADER_INVITE")
  notify(targetSrc, "GANG_SUCCESS_INVITE", { gang = myGang.name })
end)

RegisterNetEvent("rcore_gangs:server:set_rank", function(targetKey, rankKeyOrIndex, gangKey)
  local src = source

  if gangKey and not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end

  if not gangKey then
    local myGang = ServerIdToGang[src]
    if not hasGangPermission(myGang, "members.rank") then return end
  end

  SetMemberRank(src, targetKey, rankKeyOrIndex, gangKey)
end)

RegisterNetEvent("rcore_gangs:server:set_leader", function(targetKey, gangKey)
  local src = source

  if gangKey and not Framework.IsPlayerAllowed(src) then
    notify(src, "COMMAND_MISSING_PERMS")
    return
  end

  if not gangKey then
    local myGang = ServerIdToGang[src]
    if not myGang or not myGang.leader then return end
  end

  SetMemberLeader(src, targetKey, gangKey)
end)

RegisterNetEvent("rcore_gangs:server:leave", function()
  local src = source
  local myGang = ServerIdToGang[src]
  if not myGang then return end

  if myGang.leader then
    DisbandGang(src, nil, nil)
  else
    LeaveGang(src, nil, nil)
  end
end)

RegisterNetEvent("rcore_gangs:server:giveTerritoryUp", function()
  local src = source
  local myGang = GetPlayerGang(src)
  if not myGang then return end

  if not (myGang.leader or (myGang.access and myGang.access["rivalry.give_up_territory"])) then
    return
  end

  local ped = GetPlayerPed(src)
  local coords = GetEntityCoords(ped)
  local zone = GetZoneAtPosition(coords)
  if not zone or not zone.name then return end

  if SQL and SQL.DeleteZone then
    SQL.DeleteZone(myGang.id, zone.name)
  end

  -- Reload zones (matches original "rebuild from DB" approach)
  Zones = {}
  if SQL and SQL.GetZones then
    local rows = SQL.GetZones()
    if rows then
      for _, z in ipairs(rows) do
        Zones[("%s.%s"):format(z.name, z.gangId)] = z
      end
    end
  end

  TriggerClientEvent("rcore_gangs:client:set_zones", -1, Zones)
end)

-- ------------------------------------------------------------
-- Exports
-- ------------------------------------------------------------

exports("CreateGang", function(leaderKey, color, group, tag, name)
  return CreateGang(nil, leaderKey, color, group, tag, name)
end)

exports("DeleteGang", function(gangKey)
  return DeleteGang(nil, gangKey)
end)

exports("AddMember", function(targetKey, gangKey)
  return AddMember(nil, targetKey, gangKey)
end)

exports("KickMember", function(targetKey, gangKey)
  return KickMember(nil, targetKey, gangKey)
end)

exports("SetMemberRank", function(targetKey, rankKeyOrIndex, gangKey)
  return SetMemberRank(nil, targetKey, rankKeyOrIndex, gangKey)
end)

exports("SetMemberLeader", function(targetKey, gangKey)
  return SetMemberLeader(nil, targetKey, gangKey)
end)

exports("LeaveGang", function(targetKey, gangKey)
  return LeaveGang(nil, targetKey, gangKey)
end)

exports("DisbandGang", function(targetKey, gangKey)
  return DisbandGang(nil, targetKey, gangKey)
end)