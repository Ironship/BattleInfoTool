-- BattleInfoTool module ShieldsInfo: the remaining absorb of a unit, as the client reports it
-- (UnitGetTotalAbsorbs), shown as an overlay on the unit's own health bar -- the player, the
-- target, the party (classic and compact party/raid frames) and every accessible nameplate.
-- There is no floating HUD: the shield dots beside the character are retired, and the
-- legacy hud/numbers/scale/mirror/preview/locked/x/y keys in saved settings are ignored
-- (never read, never cleaned).
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
--
-- The absorb value the client returns is a secret in combat: it must never be compared,
-- added, formatted into a string of its own, stored in a table key or saved. Presence is
-- all Lua may learn (via type(), which cannot reveal a value); a reading that is present
-- flows raw into the native display calls only: StatusBar:SetMinMaxValues and
-- StatusBar:SetValue. Health and absorbs are never saved anywhere.
--
-- The overlay fill is the native Blizzard WHITE8X8 in the shared absorb colour
-- (BIT.Style role "absorb"); no custom art is painted on unit frames.

local _, BIT = ...
local M = BIT.Module("ShieldsInfo")

local WHITE = "Interface\\Buttons\\WHITE8X8" -- the native Blizzard fill (the shared style paints it)
local UPDATE_INTERVAL = 0.2
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }

local DEFAULTS = {
  player = true,      -- the player frame
  target = true,      -- the target frame
  party = true,       -- classic party frames and compact party/raid frames
  nameplates = true,  -- every accessible nameplate
  overlayAlpha = 1.0, -- the absorb fill translucency (the slider clamps it to 0.2..1.0)
}
-- Retired keys (hud, numbers, scale, mirror, preview, locked, x, y) are not
-- defaults anymore: BIT.Settings leaves saved values untouched, and this
-- module never reads them, so an old profile loads without a crash or a wipe.

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
-- say. The answers after the first are preserved too (Lua keeps the first).
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

---------------------------------------------------------------------------------------------
-- Overlays on the Blizzard unit frames
---------------------------------------------------------------------------------------------

-- healthBar -> { bar = StatusBar, unit = unit, plate = bool, party = bool, current = bool }
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

---------------------------------------------------------------------------------------------
-- The shared absorb look: the native Blizzard fill in the shared absorb
-- colour/opacity. Styling only: the bars' raw values and every saved setting
-- stay untouched, so a style write (even while the settings are closed) never
-- disturbs gameplay data. Secret-safe by construction: Resolve/Apply never
-- read the absorb.
---------------------------------------------------------------------------------------------
-- Paints one overlay bar in the shared absorb look. The shield translucency
-- multiplies on top of the shared style: only the absorb fill turns more
-- transparent, never the underlying unit bar and never any text. Styling only:
-- every value here is a style number, never the absorb.
local ALPHA_MIN, ALPHA_MAX = 0.2, 1.0

local function clampAlpha(v)
  if type(v) ~= "number" or v ~= v then return 1.0 end
  if v < ALPHA_MIN then return ALPHA_MIN end
  if v > ALPHA_MAX then return ALPHA_MAX end
  return v
end

local function overlayAlpha()
  return clampAlpha(settings ~= nil and settings.overlayAlpha or 1.0)
end

local function styleOverlay(bar)
  if type(BIT.Style) == "table" then
    local ok, style = pcall(BIT.Style.Resolve, "ShieldsInfo")
    if ok and type(style) == "table" then
      pcall(BIT.Style.ApplyBar, bar, style, "absorb")
      pcall(function()
        local colors = style.colors
        local c = type(colors) == "table" and (colors.absorb or colors.text) or nil
        if type(c) == "table" then
          local base = type(c[4]) == "number" and c[4] or 1
          local op = type(style.opacity) == "number" and style.opacity or 1
          bar:SetStatusBarColor(c[1], c[2], c[3], base * op * overlayAlpha())
        end
      end)
      return
    end
  end
  -- Degraded but visible: the native fill, never an error.
  pcall(function() bar:SetStatusBarTexture(WHITE) end)
end

-- Style writes restyle the live overlays even while the settings are closed. Fully
-- guarded: the subscriber registry calls back without pcall, so nothing here
-- may error into an unrelated settings write.
local function restyleOverlays()
  for _, o in pairs(overlays) do
    if type(o) == "table" and type(o.bar) == "table" then styleOverlay(o.bar) end
  end
end

local function onStyleChanged()
  pcall(restyleOverlays)
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
  styleOverlay(bar)
  bar:Hide()
  o = { bar = bar, unit = nil, plate = false, party = false, current = false }
  overlays[healthBar] = o
  return o
end

-- One unit's remaining absorb on one health bar. Raw values go to the native setters only;
-- a missing reading hides the overlay, never invents a value, and an overlay is
-- only ever created when there is a value to show. Presence is all Lua may learn:
-- type() cannot reveal a combat-secret value, so a secret absorb (or health pool)
-- flows on without one Lua comparison; only a proven-plain reading may be
-- compared, and a depleted plain shield hides like any missing one.
local function updateBar(unit, healthBar, enabled)
  local o = type(healthBar) == "table" and overlays[healthBar] or nil
  if type(healthBar) ~= "table" or not enabled or unit == nil then
    hideOverlay(o)
    return
  end
  local absorb = readAbsorb(unit)
  if type(absorb) == "nil" then hideOverlay(o) return end
  local plain = nil
  if not isSecret(absorb) then plain = absorb end
  if plain ~= nil and (type(plain) ~= "number" or plain <= 0) then hideOverlay(o) return end
  local maxHealth = ask(UnitHealthMax, unit)
  if type(maxHealth) == "nil" then hideOverlay(o) return end
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

-- The real primary layout (PlayerFrame.Content...HealthBarsContainer.HealthBar; the primary
-- frame XML nests the bar inside HealthBarsContainer, and PlayerFrameContainer is only a
-- sibling layer), then the old direct child, then the classic .HealthBar (Era/beta
-- parentKey="HealthBar"), then the legacy small key, then the global the vanilla
-- client keeps instead of a frame field.
local function playerBar()
  local pf = _G.PlayerFrame
  if type(pf) == "table" then
  if type(pf.PlayerFrameContent) == "table"
    and type(pf.PlayerFrameContent.PlayerFrameContentMain) == "table"
    and type(pf.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer) == "table"
    and type(pf.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar) == "table" then
    return pf.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
  end
  if type(pf.PlayerFrameContent) == "table"
    and type(pf.PlayerFrameContent.PlayerFrameContentMain) == "table"
    and type(pf.PlayerFrameContent.PlayerFrameContentMain.HealthBar) == "table" then
    return pf.PlayerFrameContent.PlayerFrameContentMain.HealthBar
  end
  if type(pf.HealthBar) == "table" then return pf.HealthBar end
  if type(pf.healthbar) == "table" then return pf.healthbar end
  end
  if type(_G.PlayerFrameHealthBar) == "table" then return _G.PlayerFrameHealthBar end
  return nil
end

-- The Forever target layout, then the classic .HealthBar (Era parentKey="HealthBar"),
-- then the legacy small key, then the global the vanilla client (no parentKey) keeps
-- instead of a frame field.
local function targetBar()
  local tf = _G.TargetFrame
  if type(tf) == "table" then
  if type(tf.TargetFrameContent) == "table"
    and type(tf.TargetFrameContent.TargetFrameContentMain) == "table"
    and type(tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer) == "table"
    and type(tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar) == "table" then
    return tf.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
  end
  if type(tf.HealthBar) == "table" then return tf.HealthBar end
  if type(tf.healthbar) == "table" then return tf.healthbar end
  end
  if type(_G.TargetFrameHealthBar) == "table" then return _G.TargetFrameHealthBar end
  return nil
end

-- The health bar of one party frame, whichever casing the client uses: the real
-- classic frames (Classic/PartyFrameTemplates.xml parentKey="HealthBar" on era and
-- beta) and the era pool members carry .HealthBar, the compact frames .healthBar.
local function partyBar(frame)
  if type(frame) ~= "table" then return nil end
  local bar = frame.HealthBar
  if type(bar) ~= "table" then bar = frame.healthBar end
  if type(bar) == "table" then return bar end
  return nil
end

-- The members of an era FramePool live in poolFrames below (pairs over the
-- hash activeObjects, frames as keys or values); this EnumerateActive-first
-- ipairs variant is retired.
-- One frame's health bar whichever key the client used: compact frames carry the small
-- .healthBar, classic templates the big parentKey .HealthBar.
local function partyBarOf(f)
  if type(f) ~= "table" then return nil end
  if type(f.healthBar) == "table" then return f.healthBar end
  if type(f.HealthBar) == "table" then return f.HealthBar end
  return nil
end

-- One member frame into the bars list when it carries a unit and a health bar.
local function collectMember(f, bars)
  if type(f) == "table" and type(f.unit) == "string" then
    local bar = partyBarOf(f)
    if bar then bars[#bars + 1] = { unit = f.unit, bar = bar } end
  end
end

-- Every frame a pool reports: EnumerateActive when it exists (Era Pools.lua iterates
-- pairs over the hash activeObjects, frame -> dummy), otherwise the activeObjects
-- table itself -- an array of frames in fixtures, a hash of frame -> dummy on the
-- client -- so pairs, never ipairs, and frames may be keys or values.
local function poolFrames(pool, bars)
  if type(pool) ~= "table" then return end
  if type(pool.EnumerateActive) == "function" then
    local ok, iter, state, seed = pcall(function() return pool:EnumerateActive() end)
    if ok and type(iter) == "function" then
      local guard = 0
      for f in iter, state, seed do
        guard = guard + 1
        if guard > 400 then break end
        collectMember(f, bars)
      end
      return
    end
  end
  local objects = type(pool.activeObjects) == "table" and pool.activeObjects or pool
  for k, v in pairs(objects) do
    if type(v) == "table" and type(v.unit) == "string" then
      collectMember(v, bars)
    elseif type(k) == "table" and type(k.unit) == "string" then
      collectMember(k, bars)
    end
  end
end

-- The raid-style party view the classic tick used to miss: CompactPartyFrame's members
-- and CompactRaidFrameContainer's members (memberUnitFrames or EnumerateActive). The
-- compact hooks update the same frames between ticks; this is the plan B when a hook
-- never fired or a frame refreshed past them.
local function compactBars(bars)
  local cpf = _G.CompactPartyFrame
  if type(cpf) == "table" and type(cpf.memberUnitFrames) == "table" then
    for _, f in pairs(cpf.memberUnitFrames) do
      collectMember(f, bars)
    end
  end
  local crc = _G.CompactRaidFrameContainer
  if type(crc) == "table" then
    if type(crc.memberUnitFrames) == "table" then
      for _, f in pairs(crc.memberUnitFrames) do
        collectMember(f, bars)
      end
    else
      poolFrames(crc, bars)
    end
  end
end

-- The classic party frames, the compact pool of the modern party frame, and the
-- raid-style compact members: the same units, whichever representation the player
-- uses. A lone PartyMemberFrameNHealthBar global (the frame object itself gone)
-- still draws. One bar is listed once no matter how many owners report it.
local function partyBars()
  local bars = {}
  for i = 1, 4 do
    local name = "PartyMemberFrame" .. i
    local bar = partyBar(_G[name])
    if type(bar) ~= "table" then
      local g = _G[name .. "HealthBar"]
      if type(g) == "table" then bar = g end
    end
    if type(bar) == "table" then
      bars[#bars + 1] = { unit = "party" .. i, bar = bar }
    end
  end
  local pf = _G.PartyFrame
  if type(pf) == "table" then
    poolFrames(pf.PartyMemberFramePool, bars)
  end
  compactBars(bars)
  local seen, out = {}, {}
  for _, b in ipairs(bars) do
    if not seen[b.bar] then
      seen[b.bar] = true
      out[#out + 1] = b
    end
  end
  return out
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

local function updateAll()
  if not settings then return end
  local pBar, tBar = playerBar(), targetBar()
  updateBar("player", pBar, settings.player)
  updateBar("target", tBar, settings.target)
  if type(pBar) == "table" then local o = overlays[pBar]; if o then o.party = false end end
  if type(tBar) == "table" then local o = overlays[tBar]; if o then o.party = false end end
  local partySeen = {}
  for _, pb in ipairs(partyBars()) do
    partySeen[pb.bar] = true
    updateBar(pb.unit, pb.bar, settings.party)
    local o = overlays[pb.bar]
    if o then o.party = true; o.plate = false end
  end
  local seen = {}
  for _, np in ipairs(nameplateBars()) do
    seen[np.bar] = true
    updateBar(np.unit, np.bar, settings.nameplates)
    local o = overlays[np.bar]
    if o then o.plate = true; o.party = false end
  end
  -- plates the client has handed back (recycled or gone): their overlays leave at once
  for bar, o in pairs(overlays) do
    if o.plate and not seen[bar] then hideOverlay(o) end
  end
  -- party members gone from every enumeration (left the party/raid): their overlays
  -- leave one by one; player/target/nameplates are never marked party, so only
  -- departed party bars are touched and overlay objects are kept for reuse
  for bar, o in pairs(overlays) do
    if o.party and not partySeen[bar] then hideOverlay(o) end
  end
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
    if type(frame.unit) ~= "string" then return end
    local bar = partyBarOf(frame)
    if type(bar) ~= "table" then return end
    updateBar(frame.unit, bar, settings ~= nil and settings.party or false)
    local o = overlays[bar]
    if o then o.party = true; o.plate = false end
  end)
  if not ok and type(frame) == "table" then
    local bar = partyBarOf(frame)
    if bar then hideOverlay(overlays[bar]) end
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
  -- shared-style writes restyle the live overlays even while the settings are
  -- closed; the callback touches styling only, never values or settings
  if type(BIT.Style) == "table" and type(BIT.Style.Subscribe) == "function" then
    pcall(BIT.Style.Subscribe, "ShieldsInfo", onStyleChanged)
  end
  driver = CreateFrame("Frame")
  driver:RegisterEvent("PLAYER_LOGIN")
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  driver:RegisterEvent("GROUP_ROSTER_UPDATE")
  driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  driver:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player", "target", unpack(PARTY_UNITS))
  driver:RegisterUnitEvent("UNIT_HEALTH", "player", "target", unpack(PARTY_UNITS))
  driver:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "target", unpack(PARTY_UNITS))
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

-- BIT-only settings sample: a mock bar with a native shield fill and a fixed
-- absorb number, independent of live bars.
local function buildShieldsPreview(parent)
  local scene = CreateFrame("Frame", nil, parent)
  scene:SetSize(560, 120)
  scene.title = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  scene.title:SetPoint("TOPLEFT", 12, -4)
  scene.title:SetText("Shields sample (not your bars)")
  scene.bar = CreateFrame("Frame", nil, scene)
  scene.bar:SetSize(180, 20)
  scene.bar:SetPoint("TOPLEFT", 12, -30)
  scene.fill = CreateFrame("Frame", nil, scene.bar)
  scene.fill:SetSize(120, 20)
  scene.fill:SetPoint("LEFT", scene.bar, "LEFT", 0, 0)
  scene.number = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scene.number:SetPoint("TOPLEFT", 12, -56)
  scene.number:SetText("12400")
  scene.number:SetHeight(14)
  return scene
end

local function renderShieldsPreview(scene, style)
  BIT.Style.ApplyText(scene.title, style, "text")
  BIT.Style.ApplyText(scene.number, style, "text")
  -- Native-Y min/max reflow: title depth, bar height, number row and scene
  -- height all derive from the shared font size; widths stay fixed because
  -- this sample has no scale capability. The window is never resized.
  local fontSize = style.fontSize or 12
  local barH = math.max(20, fontSize + 6)
  local barDepth = 4 + fontSize + 8
  local numDepth = barDepth + barH + 4
  scene.bar:ClearAllPoints()
  scene.bar:SetPoint("TOPLEFT", 12, -barDepth)
  scene.bar:SetSize(180, barH)
  scene.fill:SetSize(120, barH)
  scene.number:ClearAllPoints()
  scene.number:SetPoint("TOPLEFT", 12, -numDepth)
  scene:SetSize(560, numDepth + fontSize + 16)
end

BIT.RegisterTab("ShieldsInfo", {
  buildPreview = buildShieldsPreview,
  previewRender = renderShieldsPreview,
  capabilities = { roles = { "text" }, shapes = false,
    geometry = false, border = false, font = true, scale = false, opacity = true },
  title = "Shields",
  summary = "The remaining absorb of a shield on your frames and nameplates.",
  width = 640, height = 400,
  build = function(parent)
    local UI = BIT.UI
    local checks = {}
    M._checks = checks
    local rows = {}
    local function changed()
      for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
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
    local function getAlpha() return clampAlpha(settings.overlayAlpha) end
    local function setAlpha(v)
      settings.overlayAlpha = clampAlpha(v)
      restyleOverlays()
      changed()
    end
    local alpha = UI.Slider(parent, "Shield bar opacity", ALPHA_MIN, ALPHA_MAX, 0.05,
      getAlpha, setAlpha, "%%")
    M._alpha = alpha
    add(alpha, 46)
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