-- shared/shared.lua (CLEAN)
-- Shared helpers used across the gangs resource:
-- - glm helpers (distance/vec3/radians/sin/cos)
-- - money/time formatting
-- - zone lookup helpers (position -> zone, zone -> owning gang)
-- - ranks system migration + inheritance
-- - locale selection + placeholder substitution
-- - optional chat command suggestions
-- - tableLenght (legacy name kept for compatibility)

glm = glm or {}

-- ------------------------------------------------------------
-- glm helpers
-- ------------------------------------------------------------

---Distance between two vector3s (FiveM vectors support subtraction + length operator).
---@param a vector3
---@param b vector3
---@return number
function glm.distance(a, b)
  return #(a - b)
end

---Ensure a value is a vector3.
---@param x number|vector3
---@param y number|nil
---@param z number|nil
---@return vector3
function glm.vec3(x, y, z)
  if type(x) == "vector3" then
    return x
  end
  return vector3(x, y, z)
end

---Convert degrees to radians.
---@param degrees number
---@return number
function glm.radians(degrees)
  return degrees * (math.pi / 180)
end

glm.sin = math.sin
glm.cos = math.cos

-- ------------------------------------------------------------
-- Formatting helpers
-- ------------------------------------------------------------

---Format a number as dollars with commas (floor, no decimals).
---@param amount number|string
---@return string
function FormatMoney(amount)
  local n = tonumber(amount) or 0
  local sign = ""
  if n < 0 then
    sign = "-"
    n = -n
  end

  n = math.floor(n)
  local s = tostring(n)

  -- insert commas every 3 digits
  s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")

  return sign .. "$" .. s
end

---Format seconds to HH:MM:SS (floor, zero-padded).
---@param seconds number|string
---@return string
function FormatTime(seconds)
  local total = math.floor(tonumber(seconds) or 0)
  local hours = math.floor(total / 3600)
  local mins = math.floor((total % 3600) / 60)
  local secs = total % 60
  return string.format("%02d:%02d:%02d", hours, mins, secs)
end

-- ------------------------------------------------------------
-- Zones
-- ------------------------------------------------------------

---Get owning gang for the provided zone (by max loyalty in Zones cache).
---@param zone table { name: string }
---@return table|nil  -- gang object from Gangs
function GetGangAtZone(zone)
  if not zone or not zone.name then return nil end
  if type(Zones) ~= "table" then return nil end
  if type(Gangs) ~= "table" then return nil end

  local bestGangId = 0
  local bestLoyalty = 0
  local zoneName = zone.name

  for _, z in pairs(Zones) do
    if z and z.name == zoneName and type(z.loyalty) == "number" then
      if z.loyalty > bestLoyalty then
        bestLoyalty = z.loyalty
        bestGangId = z.gangId or 0
      end
    end
  end

  return Gangs[bestGangId]
end

---Return the zone config object at a given position (first matching zone).
---@param pos vector3
---@return table|nil -- zone config from Config.GangZones
function GetZoneAtPosition(pos)
  if type(Config) ~= "table" or type(Config.GangZones) ~= "table" then return nil end
  if not pos then return nil end

  for _, zone in pairs(Config.GangZones) do
    if GetIsZoneAtPosition(pos, zone) then
      return zone
    end
  end

  return nil
end

---Check if a position is inside a zone definition (axis-aligned rect parts).
---@param pos vector3
---@param zone table { parts?: table, zoneParts?: table }
---@return table|nil -- returns the zone if inside; nil otherwise
function GetIsZoneAtPosition(pos, zone)
  if not pos or not zone then return nil end

  local parts = zone.parts or zone.zoneParts
  if type(parts) ~= "table" then return nil end

  local x, y = pos.x, pos.y
  for _, p in ipairs(parts) do
    if p and x > p.x1 and x < p.x2 and y > p.y1 and y < p.y2 then
      return zone
    end
  end

  return nil
end

-- Normalize zone parts so x1<=x2 and y1<=y2 (prevents bad configs from breaking lookups)
if type(Config) == "table" and type(Config.GangZones) == "table" then
  for _, zone in pairs(Config.GangZones) do
    local parts = zone.parts or zone.zoneParts
    if type(parts) == "table" then
      for _, p in ipairs(parts) do
        if p then
          if p.x1 and p.x2 and p.x1 > p.x2 then
            p.x1, p.x2 = p.x2, p.x1
          end
          if p.y1 and p.y2 and p.y1 > p.y2 then
            p.y1, p.y2 = p.y2, p.y1
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------
-- Ranks system: legacy migration + inheritance
-- ------------------------------------------------------------

local function buildLegacyRankAccess(hasExtended)
  if hasExtended then
    return {
      ["actions.perform"] = true,
      ["garage.use"] = true,
      ["reserve.use"] = true,
      ["reserve.edit"] = true,
      ["storage.use"] = true,
      ["members.invite"] = true,
      ["protection.collect"] = true,
      ["rivalry.begin"] = true,
      ["rivalry.claim"] = true,
    }
  end

  return {
    ["actions.perform"] = true,
    ["garage.use"] = true,
    ["reserve.use"] = true,
    ["storage.use"] = true,
  }
end

-- If server is still using old `Config.GangRanks`, migrate into a single default group.
if type(Config) == "table" and type(Config.GangRanks) == "table" then
  if type(Config.RanksGroups) ~= "table" then
    Config.RanksGroups = {}
  end

  -- If no groups exist, create one group from the old ranks list.
  if next(Config.RanksGroups) == nil then
    Config.RanksGroups.default = { ranks = {} }

    for _, r in ipairs(Config.GangRanks) do
      local access = buildLegacyRankAccess(r and r.access)
      table.insert(Config.RanksGroups.default.ranks, {
        label = r.label,
        leader = r.superaccess,
        access = access,
      })
    end

    print("^1[GANGS] AUTOMATICALLY SWITCHED TO OLD RANK SYSTEM -> REMOVE `Config.GangRanks` AND UPDATE YOUR CONFIG^7")
  end
end

local function applyRankInheritance(ranks)
  if type(ranks) ~= "table" then return end

  -- Ensure higher ranks inherit permissions from lower ranks (if missing).
  for i = 1, #ranks do
    local from = ranks[i] and ranks[i].access
    if type(from) == "table" then
      for j = i + 1, #ranks do
        local to = ranks[j] and ranks[j].access
        if type(to) == "table" then
          for k, v in pairs(from) do
            if to[k] == nil then
              to[k] = v
            end
          end
        end
      end
    end
  end
end

if type(Config) == "table" and Config.RanksInheritance and type(Config.RanksGroups) == "table" then
  for _, group in pairs(Config.RanksGroups) do
    if type(group) == "table" and type(group.ranks) == "table" then
      applyRankInheritance(group.ranks)
    end
  end
end

-- ------------------------------------------------------------
-- Locale selection + placeholder substitution
-- ------------------------------------------------------------

local function installLocaleMeta(localeTable)
  return setmetatable(localeTable, {
    __index = function(_, key)
      return ("'%s' translation not found."):format(tostring(key))
    end,
    __call = function(self, key, vars)
      local tpl = self[key]
      if type(tpl) ~= "string" then
        return ("'%s' translation not found."):format(tostring(key))
      end

      return tpl:gsub("{(.-)}", function(k)
        if type(vars) == "table" and vars[k] ~= nil then
          return tostring(vars[k])
        end
        return k
      end)
    end
  })
end

do
  local selected = nil

  if type(Config) == "table" and Config.Locale and type(Locale) == "table" then
    selected = Locale[Config.Locale]
      or Locale[string.lower(Config.Locale)]
      or Locale[string.upper(Config.Locale)]
  end

  if type(selected) == "table" then
    Locale = installLocaleMeta(selected)
  else
    Locale = installLocaleMeta({})
    if type(Config) == "table" and Config.Locale then
      print("^1[GANGS] Selected locale has not been found^7")
    end
  end
end

-- ------------------------------------------------------------
-- Chat command suggestions
-- ------------------------------------------------------------

if type(Config) == "table" and type(Config.CommandSuggestion) == "table" then
  for commandKey, data in pairs(Config.CommandSuggestion) do
    local cmdName = Config.Commands and Config.Commands[commandKey]
    if cmdName and type(data) == "table" then
      TriggerEvent("chat:addSuggestion", "/" .. cmdName, data.description, data.parameters)
    end
  end
end

-- ------------------------------------------------------------
-- Legacy helper (name kept as-is for compatibility)
-- ------------------------------------------------------------

function tableLenght(t)
  if type(t) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(t) do
    n += 1
  end
  return n
end