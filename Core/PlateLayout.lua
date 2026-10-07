-- BattleInfoTool: one owner for the marks that share a nameplate.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- The live seat, for the hunter rail and for ResourceDing's dots and diamonds, is
-- SetPoint("TOP", healthBar, "BOTTOM", 0, -offset). Positive offset moves the widget down.
-- In that frame (positive y up, origin on the health bar's bottom edge) the widget's top is
-- at y = -offset and its body occupies [top - height, top]. The hunter preview anchors the
-- other way; clash math here follows the live seat, not that preview.
-- Range's check sits above the bar (BOTTOM to TOP) and is not part of this span.

local _, BIT = ...

local Plate = {}
BIT.Plate = Plate

-- Body heights of the live widgets. The hunter rail is the row of dots plus its icons;
-- the resource rows are one dot tall (ResourceDing's default dot size).
Plate.HUNTER_RAIL_HEIGHT = 16
Plate.DOT_ROW_HEIGHT = 14
Plate.SHARD_ROW_HEIGHT = 14
Plate.SHIELD_EDGE = 4

-- Bottom and top of a widget seated with the live formula, positive y up.
function Plate.Span(offset, height)
  local top = -(tonumber(offset) or 0)
  local h = tonumber(height) or 0
  if h < 0 then h = 0 end
  return top - h, top
end

-- True when the two bodies share any vertical space. Touching edges do not count.
function Plate.Clash(offsetA, heightA, offsetB, heightB)
  local a0, a1 = Plate.Span(offsetA, heightA)
  local b0, b1 = Plate.Span(offsetB, heightB)
  return a0 < b1 and b0 < a1
end

local function moduleSettings(name)
  if type(BIT.DB) ~= "function" then return nil end
  local saved = BIT.DB()
  local modules = type(saved) == "table" and saved.modules or nil
  local s = type(modules) == "table" and modules[name] or nil
  if type(s) ~= "table" then return nil end
  return s
end

-- Hunter rail offset, combo-dot offset, shard offset. Missing saved values are the defaults.
function Plate.ReadOffsets()
  local hunter = -8
  local hs = moduleSettings("HunterRangeFinder")
  if hs and type(hs.plateOffset) == "number" then hunter = hs.plateOffset end
  local dots, shards = 2, 2
  local rd = BattleInfoTool_ResourceDingDB
  if type(rd) == "table" then
    if type(rd.dotOffset) == "number" then dots = rd.dotOffset end
    if type(rd.shardOffset) == "number" then shards = rd.shardOffset end
  end
  return hunter, dots, shards
end

-- The hunter rail is actually on the plate: the module is running, the player is a hunter,
-- and the rail is attached. A non-hunter keeps the Range check even if this module is on.
function Plate.HunterOwnsNameplate()
  if type(BIT.IsRunning) ~= "function" or not BIT.IsRunning("HunterRangeFinder") then return false end
  local class
  if type(UnitClass) == "function" then
    class = select(2, UnitClass("player"))
  end
  if class ~= "HUNTER" then return false end
  local s = moduleSettings("HunterRangeFinder")
  if s and s.attachToPlate == false then return false end
  return true
end

-- DoTInfo has a marker's worth of damage on this unit. Shields use it to yield the fill.
function Plate.DotOnUnit(unit)
  if type(unit) ~= "string" then return false end
  if type(BIT.IsRunning) ~= "function" or not BIT.IsRunning("DoTInfo") then return false end
  local dot = BIT.modules and BIT.modules.DoTInfo
  if type(dot) ~= "table" or type(dot.HasMarker) ~= "function" then return false end
  local ok, on = pcall(dot.HasMarker, unit)
  return ok and on == true
end

-- A refresh is due when time left is still positive and inside the largest of one tick,
-- three seconds, and a quarter of the duration.
function Plate.RefreshDue(remaining, duration, interval)
  remaining = tonumber(remaining)
  if not remaining or remaining <= 0 then return false end
  duration = tonumber(duration) or 0
  interval = tonumber(interval) or 0
  if interval < 0 then interval = 0 end
  local portion = duration > 0 and duration * 0.25 or 0
  local window = math.max(interval, 3, portion)
  return remaining <= window
end

function Plate.ClashText()
  local hunter, dots, shards = Plate.ReadOffsets()
  local parts = {}
  if Plate.Clash(hunter, Plate.HUNTER_RAIL_HEIGHT, dots, Plate.DOT_ROW_HEIGHT) then
    parts[#parts + 1] = "Hunter rail overlaps combo dots."
  end
  if Plate.Clash(hunter, Plate.HUNTER_RAIL_HEIGHT, shards, Plate.SHARD_ROW_HEIGHT) then
    parts[#parts + 1] = "Hunter rail overlaps shard diamonds."
  end
  if Plate.Clash(dots, Plate.DOT_ROW_HEIGHT, shards, Plate.SHARD_ROW_HEIGHT) then
    parts[#parts + 1] = "Combo dots overlap shard diamonds."
  end
  if #parts == 0 then return "Nameplate lanes are clear." end
  return table.concat(parts, " ")
end
