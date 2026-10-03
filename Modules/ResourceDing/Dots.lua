-- BattleInfoTool ResourceDing: originally ported from ResourceDing/Dots.lua at 540b462.
-- Frozen in BIT: edit this module directly; tools/port.py protects its local gameplay fixes.
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

-- The red -> green combo progression, drawn from the shared palette: red for a low bar,
-- amber halfway up, green for every circle at maximum. The settings preview paints the
-- same roles over fixed data, so DotStyleRoles below stays the applied set.
local ROLE_LOW = "bad"       -- red endpoint
local ROLE_MID = "resource"   -- amber midpoint
local ROLE_FULL = "good"      -- green at maximum
Addon.DotStyleRoles = { "text", ROLE_LOW, ROLE_MID, ROLE_FULL }

-- The palette with the addon's own style when it is there, else the shipped defaults.
-- Pure: no saved writes, no game reads, and silent on a broken style.
local FALLBACK_STYLE = {
  opacity = 1,
  colors = {
    bad = { 1.00, 0.25, 0.25, 1 },
    resource = { 1.00, 0.80, 0.20, 1 },
    good = { 0.30, 1.00, 0.30, 1 },
  },
}

local function roleColor(style, role)
  local colors = type(style) == "table" and style.colors or nil
  local c = type(colors) == "table" and colors[role] or nil
  if type(c) ~= "table" then c = FALLBACK_STYLE.colors[role] end
  return c
end

local function palette()
  if BIT and BIT.Style and type(BIT.Style.Resolve) == "function" then
    local ok, style = pcall(BIT.Style.Resolve, "ResourceDing")
    if ok and type(style) == "table" then return style end
  end
  return FALLBACK_STYLE
end

local function opacityOf(style)
  return (type(style) == "table" and type(style.opacity) == "number") and style.opacity or 1
end

-- Blend two palette colours by a plain 0..1 share. Only plain numbers in and out;
-- a secret count never reaches this helper (see RefreshDots).
local function blend(a, b, t)
  if t <= 0 then return { a[1], a[2], a[3], a[4] } end
  if t >= 1 then return { b[1], b[2], b[3], b[4] } end
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
    a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t }
end

-- The fill colour of circle i of n: red at the first, amber towards the last, and green
-- for every circle when the bar is full. i, n and full are plain values the caller
-- derived without touching a secret count. Shared with the fixed-data preview.
function Addon.DotColor(style, i, n, full)
  local alpha = opacityOf(style)
  if full then
    local c = roleColor(style, ROLE_FULL)
    return { c[1], c[2], c[3], c[4] * alpha }
  end
  local t = 0
  if n > 1 then t = (i - 1) / (n - 1) end
  local c = blend(roleColor(style, ROLE_LOW), roleColor(style, ROLE_MID), t)
  return { c[1], c[2], c[3], c[4] * alpha }
end

-- Fixed round chrome: a neutral dark disc plus a black 1px outline, independent of
-- the role palette. Alpha multiplies the shared style opacity exactly once here;
-- no frame alpha is set, so opacity 0.4 never double-applies via parent and fill.
local CHROME_BACK_RGB = { 0.15, 0.15, 0.15 }
local CHROME_BACK_ALPHA = 0.85
local CHROME_BORDER_RGB = { 0, 0, 0 }
local CHROME_BORDER_ALPHA = 0.9

-- Shared chrome geometry: anchors back/border once for BOTH the live HUD and the
-- fixed-data sample. Pure: no unit, target, audio or saved reads.
function Addon.LayoutCircleChrome(dot)
  if type(dot) ~= "table" then return end
  if dot.border ~= nil and type(dot.border.ClearAllPoints) == "function" then
    dot.border:ClearAllPoints()
  end
  if dot.border ~= nil and type(dot.border.SetPoint) == "function" then
    dot.border:SetPoint("TOPLEFT", dot, "TOPLEFT", -1, 1)
    dot.border:SetPoint("BOTTOMRIGHT", dot, "BOTTOMRIGHT", 1, -1)
  end
  if dot.back ~= nil and type(dot.back.ClearAllPoints) == "function" then
    dot.back:ClearAllPoints()
  end
  if dot.back ~= nil and type(dot.back.SetAllPoints) == "function" then
    dot.back:SetAllPoints(dot)
  end
end

-- Shared pure paint: chrome (back/border) plus fill plus full-green overlay, all at
-- the shared opacity. i, n and full are plain values; the count itself never
-- reaches this helper, only native SetValue calls the callers make.
function Addon.PaintCircleDot(dot, style, i, n, full)
  if type(dot) ~= "table" then return end
  local alpha = opacityOf(style)
  if dot.back ~= nil and type(dot.back.SetVertexColor) == "function" then
    dot.back:SetVertexColor(CHROME_BACK_RGB[1], CHROME_BACK_RGB[2], CHROME_BACK_RGB[3],
      CHROME_BACK_ALPHA * alpha)
  end
  if dot.border ~= nil and type(dot.border.SetVertexColor) == "function" then
    dot.border:SetVertexColor(CHROME_BORDER_RGB[1], CHROME_BORDER_RGB[2], CHROME_BORDER_RGB[3],
      CHROME_BORDER_ALPHA * alpha)
  end
  local c = Addon.DotColor(style, i, n, full)
  if type(dot.SetStatusBarColor) == "function" then
    dot:SetStatusBarColor(c[1], c[2], c[3], c[4])
  end
  if dot.overlay ~= nil and type(dot.overlay.SetStatusBarColor) == "function" then
    local g = Addon.DotColor(style, 1, 1, true)
    dot.overlay:SetStatusBarColor(g[1], g[2], g[3], g[4])
  end
end

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
  local container = unitFrame and type(unitFrame.HealthBarsContainer) == "table"
    and unitFrame.HealthBarsContainer or nil
  local bar = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar
    or (container and (container.healthBar or container.HealthBar))) or nil
  return type(bar) == "table" and bar or plate
end

-- How many dots, and the count to show (plain, or the client's secret), or nil when the dots are
-- not for now: no resource, a druid out of Cat Form, no attackable target.
local function state()
  local resource, current, maximum, rawCurrent = Addon.GetResourceState()
  if not resource then return nil end
  local _, class = UnitClass("player")
  if class == "DRUID" and resource.comboPoints and plain(GetShapeshiftFormID) ~= DRUID_CAT_FORM then return nil end
  if plain(UnitExists, "target") ~= true then return nil end
  if plain(UnitCanAttack, "player", "target") == false then return nil end
  if plain(UnitIsDeadOrGhost, "target") == true then return nil end
  local count = current
  if resource.comboPoints and Addon.IsClassic() and type(GetComboPoints) == "function" then
    -- Classic points belong to this target. Forward its raw value, including
    -- a secret, to native bars; neither UnitPower nor fading highlights prove
    -- the selected target owns the points they still show.
    count = rawCurrent
  elseif count == nil then
    -- Player-owned resources keep their existing native-value fallback.
    count = ask(UnitPower, "player", resource.power)
    if count == nil and resource.comboPoints then count = ask(GetComboPoints, "player", "target") end
  end
  if count == nil then return nil end
  -- a maximum of 0 is a spec or form without this bar (a Retail Fire mage has no Arcane Charges)
  if type(maximum) ~= "number" or maximum <= 0 then return nil end
  return math.min(maximum, MAX_DOTS), count
end

local function newCircle(parent)
  local dot = CreateFrame("StatusBar", nil, parent)
  dot.border = dot:CreateTexture(nil, "BACKGROUND", nil, 0)
  dot.border:SetTexture(CIRCLE)
  dot.border:SetVertexColor(0, 0, 0, 0.9)
  dot.back = dot:CreateTexture(nil, "BACKGROUND", nil, 1)
  dot.back:SetTexture(CIRCLE)
  dot.back:SetVertexColor(0.15, 0.15, 0.15, 0.85)
  dot:SetStatusBarTexture(CIRCLE)
  -- The secret-safe full-bar overlay: the same round mask in full green, one level above
  -- the dot's own fill. Its range spans the whole row and its value is the raw count, so
  -- the native client -- never this code -- shows it only at maximum, even when the count
  -- itself is a secret no Lua comparison may touch.
  local overlay = CreateFrame("StatusBar", nil, dot)
  overlay:SetStatusBarTexture(CIRCLE)
  if type(dot.GetFrameLevel) == "function" and type(overlay.SetFrameLevel) == "function" then
    overlay:SetFrameLevel(dot:GetFrameLevel() + 1)
  end
  overlay:SetAllPoints(dot)
  dot.overlay = overlay
  -- Corner clipping the client itself enforces: where it offers mask textures
  -- (UnitFrame/EvokerEbonMightBar pattern), the overlay fill is clipped to the same
  -- round asset, so the green full-bar mark stays a circle -- never a stretched oval
  -- or a partially rounded fill gap. One mask only, no union; every anchor is the
  -- plain full slot, and the count still reaches only the native SetValue below.
  -- Clients without the mask API keep the round asset as the fill, like the dots.
  local fill = type(overlay.GetStatusBarTexture) == "function" and overlay:GetStatusBarTexture() or nil
  if type(overlay.CreateMaskTexture) == "function" and type(fill) == "table"
      and type(fill.AddMaskTexture) == "function" then
    local mask = overlay:CreateMaskTexture()
    if type(mask) == "table" then
      if type(mask.SetTexture) == "function" then
        pcall(mask.SetTexture, mask, CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      end
      if type(mask.SetWrapMode) == "function" then
        pcall(mask.SetWrapMode, mask, "CLAMPTOBLACK", "ADDITIVE")
      end
      if type(mask.SetAllPoints) == "function" then mask:SetAllPoints(overlay) end
      fill:AddMaskTexture(mask)
      overlay.circleMask = mask
    end
  end
  Addon.LayoutCircleChrome(dot)
  return dot
end

local function makeDot(i)
  local dot = newCircle(row)
  dot:SetMinMaxValues(i - 1, i)
  dots[i] = dot
  return dot
end

-- One native combo circle for the fixed-data settings preview: the same chrome as a live
-- dot, fixed size, no events and no game reads. Colours come from renderResourceDingPreview.
function Addon.MakeCircleDot(parent, size)
  local dot = newCircle(parent)
  dot:SetSize(size, size)
  dot:ClearAllPoints()
  Addon.LayoutCircleChrome(dot)
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
      if dot.overlay then dot.overlay:SetShown(i <= n) end
      dot:SetSize(size, size)
      dot:ClearAllPoints()
      dot:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
      Addon.LayoutCircleChrome(dot)
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
  -- The count stays a native SetValue input, plain or secret alike: full is decided only
  -- for a plain readable count, and a secret never reaches a comparison, arithmetic or
  -- string. At a secret maximum the native overlay above paints the green instead.
  local style = palette()
  local full = false
  if not isSecret(count) and type(count) == "number" then full = count >= n end
  for i = 1, n do
    local dot = dots[i]
    if dot.overlay then
      dot.overlay:SetMinMaxValues(n - 1, n)
      pcall(dot.overlay.SetValue, dot.overlay, count)
    end
    Addon.PaintCircleDot(dot, style, i, n, full)
    pcall(dot.SetValue, dot, count)
  end
  row:Show()
end

-- Called by Core.lua at ADDON_LOADED, once the settings are loaded: only then are events taken.
function Addon.StartDots()
  if row then return end
  row = CreateFrame("Frame", nil, UIParent)
  row:Hide()
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, event)
  end
  for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_COMBO_POINTS" }) do
    pcall(events.RegisterUnitEvent, events, event, "player")
  end
  -- Every one of them is a reason to look again. A plate freed for another unit is left here too:
  -- the target has no plate after it, and the dots go.
  events:SetScript("OnEvent", function() Addon.RefreshDots() end)
  -- A shared-style change repaints the live circles at once, settings window open or
  -- not. The callback is silent: RefreshDots plays no sound and starts nothing.
  if BIT.Style and type(BIT.Style.Subscribe) == "function" then
    BIT.Style.Subscribe("ResourceDing", function() Addon.RefreshDots() end)
  end
  Addon.RefreshDots()
end

Addon.starters = Addon.starters or {}
table.insert(Addon.starters, Addon.StartDots)

-- For the tests.
Addon._dotsRow = function() return row end
Addon._dots = dots
