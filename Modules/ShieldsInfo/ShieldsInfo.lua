-- BattleInfoTool module ShieldsInfo: the remaining absorb of a unit, as the client reports it
-- (UnitGetTotalAbsorbs), shown as an overlay on the unit's own health bar -- the player, the
-- target, the party (classic and compact party/raid frames) and every accessible nameplate --
-- and as a curved segmented gold aura beside the character when the optional HUD is on.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- The absorb value the client returns is a secret in combat: it must never be compared,
-- added, formatted into a string of its own, stored in a table key or saved. It flows raw
-- into the native display calls only: StatusBar:SetValue, StatusBar:SetMinMaxValues and
-- FontString:SetFormattedText (or C_StringUtil.TruncateWhenZero). Health and absorbs are
-- never saved anywhere; the HUD's best-known maximum lives in a module variable for the
-- session only.
--
-- The curved aura texture is Shield Aura Forever's, used under its MIT licence
-- (LICENSE-ShieldAuraForever.txt in this folder; GitHub: ShieldAuraForever/ShieldAuraForever).

local _, BIT = ...
local M = BIT.Module("ShieldsInfo")

local MEDIA = "Interface\\AddOns\\BattleInfoTool\\Modules\\ShieldsInfo\\Textures"
local AURA = MEDIA .. "\\shield_aura.tga"
local AURA_MIRROR = MEDIA .. "\\shield_aura_mirrored.tga"
local UPDATE_INTERVAL = 0.2
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }

local DEFAULTS = {
  player = true,      -- the player frame
  target = true,      -- the target frame
  party = true,       -- classic party frames and compact party/raid frames
  nameplates = true,  -- every accessible nameplate
  hud = false,        -- the curved aura beside the character
  numbers = true,     -- the absorb number under the HUD aura
  scale = 1,
  mirror = false,     -- the aura bows right; mirrored for the left side
  preview = false,    -- show a fixed sample instead of live absorb
  locked = true,      -- false: the HUD can be dragged
  x = 95, y = 20,     -- the HUD's offset from the screen centre
}

local settings

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) or false
end

-- The client's answer, or nil when the API is missing, errors, or has nothing to say.
-- A secret value is a value: it is returned untouched.
local function readAbsorb(unit)
  if type(UnitGetTotalAbsorbs) ~= "function" then return nil end
  local ok, v = pcall(UnitGetTotalAbsorbs, unit)
  if not ok then return nil end
  return v
end

-- The client's answer(s), or nothing when the API is missing, errors, or has nothing to
-- say. The answers after the first are preserved too: GetCenter returns x and y together,
-- and the callers that read a single value are unaffected (Lua keeps the first).
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

-- A usable number: a real finite one. The client can hand out NaN and infinities while
-- frames are being torn down or re-laid out; such geometry must never reach the saved
-- offsets (or SetPoint).
local function isFiniteNumber(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---------------------------------------------------------------------------------------------
-- Overlays on the Blizzard unit frames
---------------------------------------------------------------------------------------------

-- healthBar -> { bar = StatusBar, unit = unit, plate = bool, current = bool }
local overlays = setmetatable({}, { __mode = "k" })

local function hideOverlay(overlay)
  if overlay then overlay.bar:Hide() end
end

-- The unit's health bar the module may draw on, or nil.
local function usableBar(frame)
  if type(frame) ~= "table" then return nil end
  local ok = pcall(function()
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then error("forbidden") end
  end)
  if not ok then return nil end
  return frame
end

-- The overlay StatusBar on a health bar, created once and reused; nil when the bar is
-- protected or the client would not accept a child.
local function overlayFor(healthBar)
  if type(healthBar) ~= "table" then return nil end
  if not usableBar(healthBar) then return nil end
  local o = overlays[healthBar]
  if o then return o end
  local bar = CreateFrame("StatusBar", nil, healthBar)
  bar:SetAllPoints(healthBar)
  local orientation = ask(healthBar.GetOrientation, healthBar) or "HORIZONTAL"
  bar:SetOrientation(orientation)
  bar:SetReverseFill(orientation == "VERTICAL")
  bar:SetFrameLevel((healthBar:GetFrameLevel() or 0) + 1)
  bar:SetStatusBarTexture(AURA, "REPEAT", "REPEAT")
  bar:SetStatusBarColor(1, 1, 1, 0.55)
  bar:Hide()
  o = { bar = bar, unit = nil, plate = false, current = false }
  overlays[healthBar] = o
  return o
end

-- One unit's remaining absorb on one health bar. Raw values go to the native setters only;
-- a missing or unusable reading hides the overlay, never invents a value, and an overlay is
-- only ever created when there is a value to show.
local function updateBar(unit, healthBar, enabled)
  local o = type(healthBar) == "table" and overlays[healthBar] or nil
  if type(healthBar) ~= "table" or not enabled or unit == nil then
    hideOverlay(o)
    return
  end
  local absorb = readAbsorb(unit)
  if absorb == nil then hideOverlay(o) return end
  local secret = isSecret(absorb)
  if not secret and (type(absorb) ~= "number" or absorb <= 0) then hideOverlay(o) return end
  local maxHealth = ask(UnitHealthMax, unit)
  if maxHealth == nil then hideOverlay(o) return end
  if not o then
    o = overlayFor(healthBar)
    if not o then return end
  end
  local ok = pcall(function()
    o.bar:SetMinMaxValues(0, maxHealth)
    o.bar:SetValue(absorb)
    o.bar:Show()
  end)
  if not ok then hideOverlay(o) end
end

-- Without the modern path (PlayerFrame.Content...), the classic .healthbar.
local function playerBar()
  local pf = _G.PlayerFrame
  if type(pf) ~= "table" then return nil end
  if type(pf.PlayerFrameContent) == "table"
    and type(pf.PlayerFrameContent.PlayerFrameContentMain) == "table"
    and type(pf.PlayerFrameContent.PlayerFrameContentMain.HealthBar) == "table" then
    return pf.PlayerFrameContent.PlayerFrameContentMain.HealthBar
  end
  if type(pf.healthbar) == "table" then return pf.healthbar end
  return nil
end

-- The Forever target layout, then the classic .healthbar.
local function targetBar()
  local tf = _G.TargetFrame
  if type(tf) ~= "table" then return nil end
  if type(tf.TargetFrameContent) == "table"
    and type(tf.TargetFrameContent.TargetFrameContentMain) == "table"
    and type(tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer) == "table"
    and type(tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar) == "table" then
    return tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
  end
  if type(tf.healthbar) == "table" then return tf.healthbar end
  return nil
end

-- The classic party frames and the compact pool of the modern party frame: the same units,
-- whichever representation the player uses.
local function partyBars()
  local bars = {}
  for i = 1, 4 do
    local f = _G["PartyMemberFrame" .. i]
    if type(f) == "table" and type(f.healthBar) == "table" then
      bars[#bars + 1] = { unit = "party" .. i, bar = f.healthBar }
    end
  end
  local pf = _G.PartyFrame
  if type(pf) == "table" then
    local pool = pf.PartyMemberFramePool
    if type(pool) == "table" then
      local objects = type(pool.activeObjects) == "table" and pool.activeObjects or pool
      for _, f in ipairs(objects) do
        if type(f) == "table" and type(f.unit) == "string" and type(f.healthBar) == "table" then
          bars[#bars + 1] = { unit = f.unit, bar = f.healthBar }
        end
      end
    end
  end
  return bars
end

-- Every nameplate the client hands out, with its health bar; protected plates are skipped.
local function nameplateBars()
  local out = {}
  if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlates) ~= "function" then return out end
  local ok, list = pcall(C_NamePlate.GetNamePlates)
  if not ok or type(list) ~= "table" then return out end
  for _, plate in ipairs(list) do
    if usableBar(plate) then
      local uf = plate.UnitFrame
      if type(uf) == "table" and type(uf.unit) == "string" then
        local bar = uf.healthBar
        if type(bar) ~= "table" and type(uf.HealthBarsContainer) == "table" then
          bar = uf.HealthBarsContainer.healthBar
        end
        if type(bar) == "table" then
          out[#out + 1] = { unit = uf.unit, bar = bar, plate = plate }
        end
      end
    end
  end
  return out
end

local updateHUD -- defined below with the HUD, called by updateAll

local function updateAll()
  if not settings then return end
  updateBar("player", playerBar(), settings.player)
  updateBar("target", targetBar(), settings.target)
  for _, pb in ipairs(partyBars()) do
    updateBar(pb.unit, pb.bar, settings.party)
  end
  local seen = {}
  for _, np in ipairs(nameplateBars()) do
    seen[np.bar] = true
    updateBar(np.unit, np.bar, settings.nameplates)
    local o = overlays[np.bar]
    if o then o.plate = true end
  end
  -- plates the client has handed back (recycled or gone): their overlays leave at once
  for bar, o in pairs(overlays) do
    if o.plate and not seen[bar] then hideOverlay(o) end
  end
  updateHUD()
end
M.Update = updateAll

---------------------------------------------------------------------------------------------
-- The compact party/raid frames: Blizzard keeps a pool of them and updates each via the
-- compact unit frame functions. The hooks are attached when those functions exist (usually
-- at PLAYER_LOGIN, sometimes later) and always pcall-guarded; on an unexpected failure the
-- frame's overlay is cleared, never left stale.
---------------------------------------------------------------------------------------------

local hookedUpdateAll, hookedHealPrediction = false, false

local function compactUpdate(frame)
  local ok = pcall(function()
    if type(frame) ~= "table" then return end
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then return end
    if type(frame.unit) ~= "string" or type(frame.healthBar) ~= "table" then return end
    updateBar(frame.unit, frame.healthBar, settings ~= nil and settings.party or false)
  end)
  if not ok and type(frame) == "table" and type(frame.healthBar) == "table" then
    hideOverlay(overlays[frame.healthBar])
  end
end

local function attachCompactHooks()
  if not hookedUpdateAll and type(CompactUnitFrame_UpdateAll) == "function" and settings then
    local ok = pcall(function() hooksecurefunc("CompactUnitFrame_UpdateAll", compactUpdate) end)
    hookedUpdateAll = ok
  end
  if not hookedHealPrediction and type(CompactUnitFrame_UpdateHealPrediction) == "function" and settings then
    local ok = pcall(function() hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", compactUpdate) end)
    hookedHealPrediction = ok
  end
  return hookedUpdateAll, hookedHealPrediction
end

---------------------------------------------------------------------------------------------
-- The HUD: the curved segmented gold aura beside the character, with the remaining absorb
-- number under it. The aura drains with the value the client reports; the best-known maximum
-- is the session-only calibration below (never a secret, never saved).
---------------------------------------------------------------------------------------------

local hud, hudBar, hudText, hudBackdrop, hudLabel
local runtimeMax   -- plain-number calibrations only
local hudMaxNative -- the native bar already holds a maximum seeded from a raw reading
local hudHasData   -- a real value is on the bar

local function hudTexture()
  return settings ~= nil and settings.mirror and AURA_MIRROR or AURA
end

local function saveHudPosition()
  if not hud then return end
  -- All the client's answers are guarded: without readable geometry the saved position
  -- keeps its last value. The HUD's centre is normalised into the parent's units by the
  -- effective/parent scale ratio, so an offset saved at any effective UI scale re-applies
  -- to the same screen position (the next layout feeds exactly the saved offset back
  -- through SetPoint).
  local hx, hy = ask(hud.GetCenter, hud)
  local ux, uy = ask(UIParent.GetCenter, UIParent)
  local effective = ask(hud.GetEffectiveScale, hud)
  local parentScale = ask(UIParent.GetEffectiveScale, UIParent)
  if isFiniteNumber(hx) and isFiniteNumber(hy) and isFiniteNumber(ux)
      and isFiniteNumber(uy) and isFiniteNumber(effective) and isFiniteNumber(parentScale)
      and effective > 0 and parentScale > 0 then
    local scale = effective / parentScale
    settings.x = math.floor(hx * scale - ux + 0.5)
    settings.y = math.floor(hy * scale - uy + 0.5)
  end
end

local function applyHudLayout()
  if not hud then return end
  local scale = tonumber(settings.scale) or 1
  if scale < 0.5 then scale = 0.5 elseif scale > 2.5 then scale = 2.5 end
  hud:SetSize(64 * scale, 158 * scale)
  hudBar:SetSize(34 * scale, 132 * scale)
  hudBar:ClearAllPoints()
  hudBar:SetPoint("TOP", hud, "TOP", 0, -4 * scale)
  hudBar:SetStatusBarTexture(hudTexture())
  hudText:ClearAllPoints()
  hudText:SetPoint("TOP", hudBar, "BOTTOM", 0, 1 * scale)
  local font = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  hudText:SetFont(font, math.max(8, 13 * scale), "OUTLINE")
  hud:ClearAllPoints()
  -- Corrupt SavedVariables (a string, NaN, an infinity) must not reach SetPoint; a valid
  -- numeric offset, a numeric string included, is preserved as it is.
  local x, y = tonumber(settings.x), tonumber(settings.y)
  if not isFiniteNumber(x) then x = 95 end
  if not isFiniteNumber(y) then y = 20 end
  hud:SetPoint("CENTER", UIParent, "CENTER", x, y)
  hud:EnableMouse(settings.locked ~= true)
  hudBackdrop:SetShown(settings.locked ~= true)
  hudLabel:SetShown(settings.locked ~= true)
  hudText:SetShown(settings.numbers ~= false and hudHasData)
end

local function setHudNumber(v)
  if type(C_StringUtil) == "table" and type(C_StringUtil.TruncateWhenZero) == "function" then
    hudText:SetText(C_StringUtil.TruncateWhenZero(v))
  else
    hudText:SetFormattedText("%.0f", v)
  end
end

local function hudClearNow()
  hudBar:Hide()
  hudText:Hide()
  hud:Hide()
  hudHasData = false
end

updateHUD = function()
  if not hud then return end
  if settings.hud ~= true then hudClearNow() return end
  if settings.preview then
    pcall(function()
      hud:Show()
      -- never disturb a calibrated or seeded native maximum; a virgin bar gets the sample's own
      if runtimeMax ~= nil then
        hudBar:SetMinMaxValues(0, runtimeMax)
      elseif not hudMaxNative then
        hudBar:SetMinMaxValues(0, 100)
      end
      hudBar:SetValue(72)
      hudHasData = true
      hudBar:Show()
      hudText:SetShown(settings.numbers ~= false)
      if settings.numbers ~= false then setHudNumber(72) end
    end)
    return
  end
  local absorb = readAbsorb("player")
  if absorb == nil then hudClearNow() return end
  local ok = pcall(function()
    local secret = isSecret(absorb)
    if secret then
      -- a fresh combat reading may seed the native maximum with the raw value
      if runtimeMax == nil and not hudMaxNative then
        hudBar:SetMinMaxValues(0, absorb)
        hudMaxNative = true
      end
      hudBar:SetValue(absorb)
    elseif type(absorb) == "number" and absorb > 0 then
      -- ordinary values calibrate: a new or bigger shield becomes the full bar
      if not hudMaxNative and (runtimeMax == nil or absorb > runtimeMax) then
        runtimeMax = absorb
        hudBar:SetMinMaxValues(0, absorb)
      end
      hudBar:SetValue(absorb)
    else
      -- depleted: clear the calibration so the next fresh shield fills the bar again
      runtimeMax = nil
      hudMaxNative = false
      hudBar:SetMinMaxValues(0, 1)
      hudBar:SetValue(0)
    end
    hud:Show()
    hudBar:Show()
    hudHasData = true
    hudText:SetShown(settings.numbers ~= false)
    if settings.numbers ~= false then setHudNumber(absorb) end
  end)
  if not ok then hudClearNow() end
end

local function createHud()
  hud = CreateFrame("Frame", nil, UIParent)
  hud:SetMovable(true)
  hud:SetClampedToScreen(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetScript("OnDragStart", function(self)
    if settings and settings.locked ~= true then self:StartMoving() end
  end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if settings then saveHudPosition(); applyHudLayout() end
  end)
  hudBar = CreateFrame("StatusBar", nil, hud)
  hudBar:SetOrientation("VERTICAL")
  hudBar:SetReverseFill(false)
  hudBar:SetStatusBarTexture(AURA)
  hudBar:SetStatusBarColor(1, 1, 1, 1)
  hudText = hud:CreateFontString(nil, "OVERLAY")
  hudText:SetTextColor(1, 0.9, 0.2, 1)
  hudText:SetShadowOffset(1, -1)
  hudBackdrop = hud:CreateTexture(nil, "BACKGROUND")
  hudBackdrop:SetAllPoints()
  hudBackdrop:SetColorTexture(0.1, 0.1, 0.1, 0.45)
  hudBackdrop:Hide()
  hudLabel = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hudLabel:SetPoint("BOTTOM", hud, "TOP", 0, 3)
  hudLabel:SetText("Shields - drag to move")
  hudLabel:Hide()
  hud:Hide()
  applyHudLayout()
end

---------------------------------------------------------------------------------------------
-- The heartbeat: events make it responsive, the tick catches everything else (late frames,
-- roster changes, replaced frames, plates the events missed)
---------------------------------------------------------------------------------------------

local driver

local function onEvent(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    attachCompactHooks()
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    -- the client may still answer this unit's plate during the event: never leave a stale
    -- value on it, and do not let this event's own refresh put it back
    local cleared = false
    if type(C_NamePlate) == "table" and type(C_NamePlate.GetNamePlateForUnit) == "function" then
      local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, arg1)
      if ok and type(plate) == "table" and type(plate.UnitFrame) == "table" then
        local bar = plate.UnitFrame.healthBar
        if type(bar) ~= "table" and type(plate.UnitFrame.HealthBarsContainer) == "table" then
          bar = plate.UnitFrame.HealthBarsContainer.healthBar
        end
        local o = type(bar) == "table" and overlays[bar] or nil
        if o then hideOverlay(o); cleared = true end
      end
    end
    if cleared then return end
  end
  updateAll()
end

local function start()
  createHud()
  driver = CreateFrame("Frame")
  driver:RegisterEvent("PLAYER_LOGIN")
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  driver:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player", "target", unpack(PARTY_UNITS))
  driver:SetScript("OnEvent", onEvent)
  local since = 0
  driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < UPDATE_INTERVAL then return end
    since = 0
    attachCompactHooks()
    updateAll()
  end)
  driver:Show()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= BIT.name then return end
  self:UnregisterAllEvents()
  if not BIT.ShouldRun("ShieldsInfo") then return end
  settings = BIT.Settings("ShieldsInfo", DEFAULTS)
  M.settings = settings
  start()
end)

BIT.RegisterTab("ShieldsInfo", {
  title = "Shields",
  summary = "The remaining absorb of a shield on your frames and nameplates, and the curved HUD beside your character.",
  width = 640, height = 400,
  build = function(parent)
    local UI = BIT.UI
    local checks = {}
    M._checks = checks
    local rows = {}
    local function changed()
      for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
      applyHudLayout()
      updateAll()
    end
    local function set(key) return function(v) settings[key] = v; changed() end end
    local function get(key) return function() return settings[key] end end
    local y = -10
    local function add(row, height)
      row:SetPoint("TOPLEFT", 12, y)
      rows[#rows + 1] = row
      y = y - (height or 30)
    end
    local function toggle(name, label)
      local box = UI.Check(parent, label, get(name), set(name))
      checks[name] = box
      add(box)
    end
    toggle("player", "On your player frame")
    toggle("target", "On your target frame")
    toggle("party", "On party frames (classic and compact party/raid)")
    toggle("nameplates", "On nameplates")
    toggle("hud", "HUD: the curved aura beside your character")
    toggle("numbers", "HUD number")
    toggle("mirror", "Mirror the HUD curve to the left")
    toggle("preview", "HUD preview (a fixed sample)")
    checks.unlocked = UI.Check(parent, "HUD unlocked (drag it to move it)",
      function() return settings.locked ~= true end,
      function(v) settings.locked = not v; changed() end)
    add(checks.unlocked)
    checks.scale = UI.Slider(parent, "HUD scale", 0.5, 2.5, 0.05, get("scale"), set("scale"))
    add(checks.scale, 46)
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, y)
    hint:SetText("The HUD remembers where you drag it; it drains with the shield that remains.")
    changed()
  end,
})
BIT.tabWords.shields = "ShieldsInfo"

-- For the tests.
M._driver = function() return driver end
M._overlay = function(bar) return overlays[bar] end
M._overlayCount = function()
  local n = 0
  for _ in pairs(overlays) do n = n + 1 end
  return n
end
M._attachCompactHooks = attachCompactHooks
M._hooksAttached = function() return hookedUpdateAll, hookedHealPrediction end
M._applyLayout = applyHudLayout
M._hud = function() return hud end
M._hudBar = function() return hudBar end
M._hudText = function() return hudText end