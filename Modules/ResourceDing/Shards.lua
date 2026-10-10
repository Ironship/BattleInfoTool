-- UsefulPlatesAndTooltips module ResourceDing: ported by tools/port.py from ResourceDing/Shards.lua at 540b462.
-- Retail resource behavior is maintained here; review it before running tools/port.py.
-- Classic/Forever Soul Shards are bag items; Retail Soul Shards are player power.
--
-- One sound when the readable whole-shard count rises, and purple diamonds
-- under the target's nameplate. Loading, spending shards and switching targets
-- stay quiet. An unreadable Retail count clears the baseline and hides the row.

local _, BIT = ...
-- Inside UsefulPlatesAndTooltips its own namespace; loaded on its own, the addon's table as before.
local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT

local SOUL_SHARD = 6265
local DIAMOND = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" -- the purple raid diamond
local MAX_DIAMONDS = 10
local QUIET_AFTER_WORLD = 3 -- seconds to let the post-loading count settle

local count, lastMaximum, quietUntil = nil, nil, 0
local row, more
local diamonds = {}

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end

local function plain(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or isSecret(v) then return nil end
  return v
end

local function forWarlock()
  local _, class = UnitClass("player")
  return class == "WARLOCK"
end

local function shardCount()
  if not Addon.IsClassic() then
    local resource, current, maximum = Addon.GetResourceState()
    if not resource or current == nil or maximum <= 0 then return nil end
    -- Fractional progress is not another usable shard.
    return math.max(0, math.floor(math.min(current, maximum))), maximum
  end
  local n = plain(C_Item and C_Item.GetItemCount, SOUL_SHARD)
  if n == nil then n = plain(GetItemCount, SOUL_SHARD) end
  return type(n) == "number" and n or nil, nil
end

local function targetPlate()
  if plain(UnitExists, "target") ~= true then return nil end
  if plain(UnitCanAttack, "player", "target") == false then return nil end
  if plain(UnitIsDeadOrGhost, "target") == true then return nil end
  local plate = plain(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "target")
  if type(plate) ~= "table" then return nil end
  if type(plate.IsForbidden) == "function" and plate:IsForbidden() then return nil end
  return plate
end

local function healthBarOf(plate)
  if type(BIT.Plate) == "table" and type(BIT.Plate.HealthBar) == "function" then
    local bar = BIT.Plate.HealthBar(plate)
    return type(bar) == "table" and bar or plate
  end
  local unitFrame = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
  local container = unitFrame and type(unitFrame.HealthBarsContainer) == "table"
    and unitFrame.HealthBarsContainer or nil
  local bar = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar
    or (container and (container.healthBar or container.HealthBar))) or nil
  return type(bar) == "table" and bar or plate
end

local function hide()
  if not row then return end
  row:Hide()
  if row:GetParent() ~= UIParent then row:SetParent(UIParent) end
end

function Addon.RefreshShards()
  if not Addon.db then return end
  if not (Addon.db.enabled and Addon.db.shardDiamonds and forWarlock()) or not count or count <= 0 then return hide() end
  local plate = targetPlate()
  if not plate then return hide() end
  if not row then
    row = CreateFrame("Frame", nil, UIParent)
    more = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  end
  local size = tonumber(Addon.db.dotSize) or 14
  if size ~= size then size = 14 end
  if size < 8 then size = 8 elseif size > 24 then size = 24 end
  local shown = math.min(count, MAX_DIAMONDS)
  for i = 1, MAX_DIAMONDS do
    local d = diamonds[i]
    if i <= shown then
      if not d then
        d = row:CreateTexture(nil, "ARTWORK")
        d:SetTexture(DIAMOND)
        diamonds[i] = d
      end
      d:SetSize(size, size)
      d:ClearAllPoints()
      d:SetPoint("LEFT", row, "LEFT", (i - 1) * (size - 2), 0)
      d:Show()
    elseif d then
      d:Hide()
    end
  end
  more:SetText(count > MAX_DIAMONDS and ("+" .. (count - MAX_DIAMONDS)) or "")
  more:ClearAllPoints()
  more:SetPoint("LEFT", row, "LEFT", shown * (size - 2) + 4, 0)
  row:SetSize(shown * (size - 2) + 2, size)
  row:SetParent(plate)
  row:ClearAllPoints()
  local shardOffset = tonumber(Addon.db.shardOffset) or 2
  if shardOffset ~= shardOffset then shardOffset = 2 end
  if shardOffset < -80 then shardOffset = -80 elseif shardOffset > 30 then shardOffset = 30 end
  row:SetPoint("TOP", healthBarOf(plate), "BOTTOM", 0, -shardOffset)
  row:Show()
end

function Addon.CheckShards(silent)
  if not (Addon.db and forWarlock()) then return end
  local n, maximum = shardCount()
  if n == nil then
    -- An unreadable interval proves no gain and must not leave stale diamonds.
    count, lastMaximum = nil, nil
    Addon.RefreshShards()
    return
  end
  local before = count
  if lastMaximum ~= maximum then before = nil end
  count, lastMaximum = n, maximum
  local canSound = Addon.IsClassic() or not Addon.db.combatOnly or plain(UnitAffectingCombat, "player") == true
  if not silent and before and n > before and Addon.db.enabled and Addon.db.shards
      and canSound and GetTime() >= quietUntil then
    Addon.PlaySoundKey(Addon.db.sound)
  end
  Addon.RefreshShards()
end

function Addon.ResetShards()
  count, lastMaximum = nil, nil
  Addon.CheckShards(true)
end

local started = false
local function start()
  if started or not forWarlock() then return end
  started = true
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
    pcall(events.RegisterEvent, events, event)
  end
  if Addon.IsClassic() then
    pcall(events.RegisterEvent, events, "BAG_UPDATE")
    pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
  else
    for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }) do
      pcall(events.RegisterUnitEvent, events, event, "player")
    end
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
      quietUntil = GetTime() + QUIET_AFTER_WORLD
      Addon.ResetShards()
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED"
        or event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
      Addon.CheckShards()
    else
      Addon.RefreshShards()
    end
  end)
  quietUntil = GetTime() + QUIET_AFTER_WORLD
  Addon.CheckShards()
end

Addon.starters = Addon.starters or {}
table.insert(Addon.starters, start)

-- For the tests.
Addon._shardRow = function() return row end
Addon._diamonds = diamonds
Addon._shardMore = function() return more end
