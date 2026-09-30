-- BattleInfoTool module ResourceDing: ported by tools/port.py from ResourceDing/Dots.lua at 540b462.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
-- Combo points as dots under the target's nameplate: a rogue or a cat druid sees at a glance
-- how many are built, where the eyes already are.
--
-- On WoW Forever the count is secret in a fight: an addon may not compare it or do sums with it.
-- A StatusBar may still show it, so each dot is a StatusBar of its own, from n - 1 to n: with the
-- count as its value it is empty below n and full at n or more, and the client, not this code,
-- does that comparison. Where the count is readable (out of combat, or from Blizzard's own combo
-- point display, see Core.lua) the plain number goes in instead; the bars show both alike.
--
-- Combo points belong to the target on the Classic game, so the dots sit on the target's plate.
-- They follow the plate, which the client hands to another unit when it is freed: a plate
-- going away is left at once.

local _, BIT = ...
-- Inside BattleInfoTool its own namespace; loaded on its own, the addon's table as before.
local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a white disc
local MAX_DOTS = 10
local DRUID_CAT_FORM = 1

local row -- the frame holding the dots
local dots = {}

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end

local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok then return nil end
  return v
end

-- A plain answer, or nil for none or a secret.
local function plain(fn, ...)
  local v = ask(fn, ...)
  if isSecret(v) then return nil end
  return v
end

local function targetPlate()
  local plate = plain(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "target")
  if type(plate) ~= "table" then return nil end
  if type(plate.IsForbidden) == "function" and plate:IsForbidden() then return nil end
  return plate
end

local function healthBarOf(plate)
  local unitFrame = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
  local bar = unitFrame and (unitFrame.healthBar or (type(unitFrame.HealthBarsContainer) == "table"
    and unitFrame.HealthBarsContainer.healthBar)) or nil
  return type(bar) == "table" and bar or plate
end

-- How many dots, and the count to show (plain, or the client's secret), or nil when the dots are
-- not for now: no resource, a druid out of Cat Form, no attackable target.
local function state()
  local resource, current, maximum = Addon.GetResourceState()
  if not resource then return nil end
  local _, class = UnitClass("player")
  if class == "DRUID" and resource.comboPoints and plain(GetShapeshiftFormID) ~= DRUID_CAT_FORM then return nil end
  if plain(UnitExists, "target") ~= true then return nil end
  if plain(UnitCanAttack, "player", "target") == false then return nil end
  if plain(UnitIsDeadOrGhost, "target") == true then return nil end
  local count = current
  if count == nil then
    -- the client keeps the number to itself: hand its own value to the bars
    count = ask(UnitPower, "player", resource.power)
    if count == nil and resource.comboPoints then count = ask(GetComboPoints, "player", "target") end
  end
  if count == nil then return nil end
  -- a maximum of 0 is a spec or form without this bar (a Retail Fire mage has no Arcane Charges)
  if type(maximum) ~= "number" or maximum <= 0 then return nil end
  return math.min(maximum, MAX_DOTS), count
end

local function makeDot(i)
  local dot = CreateFrame("StatusBar", nil, row)
  dot.border = dot:CreateTexture(nil, "BACKGROUND", nil, 0)
  dot.border:SetTexture(CIRCLE)
  dot.border:SetVertexColor(0, 0, 0, 0.9)
  dot.back = dot:CreateTexture(nil, "BACKGROUND", nil, 1)
  dot.back:SetTexture(CIRCLE)
  dot.back:SetVertexColor(0.15, 0.15, 0.15, 0.85)
  dot:SetStatusBarTexture(CIRCLE)
  dot:SetStatusBarColor(1, 0.25, 0.15, 1)
  dot:SetMinMaxValues(i - 1, i)
  dots[i] = dot
  return dot
end

local function layout(n)
  local db = Addon.db
  local size, gap = db.dotSize, math.max(2, math.floor(db.dotSize / 4))
  row:SetSize(n * size + (n - 1) * gap, size)
  for i = 1, MAX_DOTS do
    local dot = dots[i] or (i <= n and makeDot(i)) or nil
    if dot then
      dot:SetShown(i <= n)
      dot:SetSize(size, size)
      dot:ClearAllPoints()
      dot:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
      dot.border:ClearAllPoints()
      dot.border:SetPoint("TOPLEFT", dot, "TOPLEFT", -1, 1)
      dot.border:SetPoint("BOTTOMRIGHT", dot, "BOTTOMRIGHT", 1, -1)
      dot.back:SetAllPoints(dot)
    end
  end
end

local function hide()
  if not row then return end
  row:Hide()
  if row:GetParent() ~= UIParent then row:SetParent(UIParent) end
end

function Addon.RefreshDots()
  if not (row and Addon.db) then return end
  if not (Addon.db.enabled and Addon.db.dots) then return hide() end -- /rding off hides them too
  local n, count = state()
  local plate = n and targetPlate()
  if not plate then return hide() end
  row:SetParent(plate)
  row:ClearAllPoints()
  row:SetPoint("TOP", healthBarOf(plate), "BOTTOM", 0, -Addon.db.dotOffset)
  if row.shownFor ~= n or row.sizeFor ~= Addon.db.dotSize then
    layout(n)
    row.shownFor, row.sizeFor = n, Addon.db.dotSize
  end
  for i = 1, n do pcall(dots[i].SetValue, dots[i], count) end
  row:Show()
end

-- Called by Core.lua at ADDON_LOADED, once the settings are loaded: only then are events taken.
function Addon.StartDots()
  if row then return end
  row = CreateFrame("Frame", nil, UIParent)
  row:Hide()
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, event)
  end
  for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_COMBO_POINTS" }) do
    pcall(events.RegisterUnitEvent, events, event, "player")
  end
  -- Every one of them is a reason to look again. A plate freed for another unit is left here too:
  -- the target has no plate after it, and the dots go.
  events:SetScript("OnEvent", function() Addon.RefreshDots() end)
  Addon.RefreshDots()
end

Addon.starters = Addon.starters or {}
table.insert(Addon.starters, Addon.StartDots)

-- For the tests.
Addon._dotsRow = function() return row end
Addon._dots = dots
