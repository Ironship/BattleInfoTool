-- BattleInfoTool module ShieldsInfo: the remaining absorb of a unit, as the client reports it
-- (UnitGetTotalAbsorbs), shown as an overlay on the unit's own health bar -- the player, the
-- target, the party (classic and compact party/raid frames) and every accessible nameplate.
-- There is no floating HUD: the shield dots beside the character are retired, and the
-- legacy hud/numbers/scale/mirror/preview/locked/x/y keys in saved settings are ignored
-- (never read, never cleaned).
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- The absorb value the client returns is a secret in combat: it must never be compared,
-- added, formatted into a string of its own, stored in a table key or saved. Presence is
-- all Lua may learn (via type(), which cannot reveal a value); a reading that is present
-- flows raw into the native display calls only: StatusBar:SetMinMaxValues and
-- StatusBar:SetValue. Health and absorbs are never saved anywhere.
--
-- The overlay fill is the shared absorb colour (BIT.Style role "absorb") over a fill
-- texture the settings choose: the native Blizzard WHITE8X8 ("flat") or one of the
-- module's own textures. The settings sample paints the very same look from its own
-- fixed numbers; no game reading ever reaches it.

local _, BIT = ...
local M = BIT.Module("ShieldsInfo")

local WHITE = "Interface\\Buttons\\WHITE8X8" -- the native Blizzard fill (the shared style paints it)
local UPDATE_INTERVAL = 0.2
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
-- The units whose bars the module draws: player, target and the party slots. The unit
-- events are registered unfiltered (see start(): RegisterUnitEvent takes at most two unit
-- tokens and this set is six), so onEvent checks every event's unit against this set.
local WATCHED_UNITS = { player = true, target = true }
for _, unit in ipairs(PARTY_UNITS) do WATCHED_UNITS[unit] = true end

local DEFAULTS = {
  player = true,      -- the player frame
  target = true,      -- the target frame
  party = true,       -- classic party frames and compact party/raid frames
  nameplates = true,  -- every accessible nameplate
  overlayAlpha = 1.0, -- the absorb fill translucency (the slider clamps it to 0.2..1.0)
  fillTexture = "flat", -- the fill art the overlay wears (FILL_TEXTURES below)
}
-- Retired keys (hud, numbers, scale, mirror, preview, locked, x, y) are not
-- defaults anymore: BIT.Settings leaves saved values untouched, and this
-- module never reads them, so an old profile loads without a crash or a wipe.

-- The fill art the overlay may wear, in the order the settings offer it. "flat" is the
-- native Blizzard fill the shared style paints; the rest are plain textures (the stripes
-- tile, REPEAT, so their pattern keeps its size on a bar of any width). A saved id that
-- is not on this list reads as "flat": nothing here ever rejects a write with an error.
local TEXTURE_DIR = "Interface\\AddOns\\BattleInfoTool\\Modules\\ShieldsInfo\\Textures\\"
local FILL_TEXTURES = {
  { id = "flat", label = "Flat", hint = "The native Blizzard fill: just the shared absorb colour.",
    path = WHITE },
  { id = "smooth", label = "Health bar", hint = "The game's own health bar texture.",
    path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { id = "raid", label = "Raid bar", hint = "The raid frames' health bar texture.",
    path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { id = "stripes", label = "Stripes", hint = "Diagonal stripes that keep their size on any bar.",
    path = TEXTURE_DIR .. "Stripes.tga", tiled = true },
  { id = "shield_aura", label = "Shield aura", hint = "The module's own shield aura art.",
    path = TEXTURE_DIR .. "shield_aura.tga" },
  { id = "shield_aura_mirrored", label = "Shield aura (mirrored)",
    hint = "The shield aura art, mirrored.",
    path = TEXTURE_DIR .. "shield_aura_mirrored.tga" },
}

-- The style presets under the settings: they write only the fill art and its translucency
-- (plain style numbers), never the frame switches, so a preset cannot turn a frame off.
local PRESETS = {
  { label = "Minimal", values = { fillTexture = "flat", overlayAlpha = 0.35 } },
  { label = "Classic", values = { fillTexture = "smooth", overlayAlpha = 0.6 } },
  { label = "Juicy", values = { fillTexture = "shield_aura", overlayAlpha = 1.0 } },
}

local settings

-- A secret value is one the client marks with issecretvalue: every comparison or table
-- index on it raises. Asked inside a pcall (as in ResourceDing/Core.lua:179-184), so a
-- client whose own check raises reads as "not secret" here, never as an error out of a
-- handler.
local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, r = pcall(issecretvalue, v)
  return ok and r or false
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

-- Hide runs from the event handlers too, where the client refuses work on a protected
-- frame in combat: wrapped, so a refusal never takes a handler down (the tick hides the
-- overlay at the next pass anyway).
local function hideOverlay(overlay)
  if overlay then pcall(function() overlay.bar:Hide() end) end
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
-- The shared absorb look: the chosen fill texture in the shared absorb
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

-- The settings the look and the sample read: the live table while the module runs, the
-- saved one otherwise, so the OFF-page sample shows the player's own choices. Reading
-- only: a missing table falls back to the defaults above, nothing is ever written here.
local function currentSettings()
  if settings then return settings end
  if type(BIT.Settings) == "function" then
    local ok, s = pcall(BIT.Settings, "ShieldsInfo", DEFAULTS)
    if ok and type(s) == "table" then return s end
  end
  return DEFAULTS
end

local function overlayAlpha()
  return clampAlpha(currentSettings().overlayAlpha)
end

-- The chosen fill art (FILL_TEXTURES), or "flat" for anything unknown. A saved id the
-- client would refuse to compare (a secret can never be written there, but a comparison
-- that raises must still not escape a paint) reads as "flat" too.
local function chosenFill()
  local id = currentSettings().fillTexture
  if type(id) == "string" then
    local ok, entry = pcall(function()
      for i = 1, #FILL_TEXTURES do
        if FILL_TEXTURES[i].id == id then return FILL_TEXTURES[i] end
      end
    end)
    if ok and type(entry) == "table" then return entry end
  end
  return FILL_TEXTURES[1]
end

-- Paints one overlay bar in the shared absorb look. The shield translucency
-- multiplies on top of the shared style: only the absorb fill turns more
-- transparent, never the underlying unit bar and never any text. Styling only:
-- every value here is a style number, never the absorb. The live overlays and
-- the settings sample run this same painter, so the sample can only look like
-- the real thing.
local function paintShield(bar, style)
  local entry = chosenFill()
  pcall(function()
    bar:SetStatusBarTexture(entry.path)
    -- The tiling is the texture's own: a status bar's fill is one texture region,
    -- configured here so "stripes" repeats instead of stretching (REPEAT, as in
    -- DoTInfo/Core.lua:1342-1344).
    local tex = ask(bar.GetStatusBarTexture, bar)
    if tex ~= nil and (type(tex) == "table" or type(tex) == "userdata") then
      pcall(function()
        if entry.tiled then
          tex:SetTexture(entry.path, "REPEAT", "REPEAT")
          tex:SetHorizTile(true)
          tex:SetVertTile(true)
        else
          tex:SetHorizTile(false)
          tex:SetVertTile(false)
        end
      end)
    end
  end)
  pcall(function()
    local colors = style.colors
    local c = type(colors) == "table" and (colors.absorb or colors.text) or nil
    if type(c) == "table" then
      local base = type(c[4]) == "number" and c[4] or 1
      local op = type(style.opacity) == "number" and style.opacity or 1
      bar:SetStatusBarColor(c[1], c[2], c[3], base * op * overlayAlpha())
    end
  end)
end

local function styleOverlay(bar)
  if type(BIT.Style) == "table" then
    local ok, style = pcall(BIT.Style.Resolve, "ShieldsInfo")
    if ok and type(style) == "table" then
      pcall(BIT.Style.ApplyBar, bar, style, "absorb")
      paintShield(bar, style)
      return
    end
  end
  -- Degraded but visible: the chosen fill, never an error.
  pcall(function() bar:SetStatusBarTexture(chosenFill().path) end)
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
-- protected or the client would not accept a child. Creation runs from the event handlers
-- as well, where the client may refuse a child of a protected bar in combat: the whole
-- build is wrapped, and a failure caches nothing (the next tick retries after the fight).
local function overlayFor(healthBar)
  if type(healthBar) ~= "table" then return nil end
  if not usableBar(healthBar) then return nil end
  local o = overlays[healthBar]
  if o then return o end
  local ok, bar = pcall(function()
    local b = CreateFrame("StatusBar", nil, healthBar)
    b:SetAllPoints(healthBar)
    local orientation = ask(healthBar.GetOrientation, healthBar) or "HORIZONTAL"
    b:SetOrientation(orientation)
    b:SetReverseFill(orientation == "VERTICAL")
    b:SetFrameLevel((healthBar:GetFrameLevel() or 0) + 1)
    styleOverlay(b)
    b:Hide()
    return b
  end)
  if not ok or type(bar) ~= "table" then return nil end
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

-- The unit a unit event is about, safe to look up and drawn on by this module. A secret
-- unit token is neither a key nor a comparison (it would raise), so it is never watched.
local function isUnitWatched(unit)
  if type(unit) ~= "string" or isSecret(unit) then return false end
  return WATCHED_UNITS[unit] == true
end

local UNIT_EVENTS = { UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_HEALTH = true, UNIT_MAXHEALTH = true }

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
  elseif UNIT_EVENTS[event] and not isUnitWatched(arg1) then
    -- the unit events arrive unfiltered (see start()): one about a unit nobody draws on
    -- never wakes a refresh (arg1 is the event's own unit)
    return
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
  -- The unit events unfiltered: Frame:RegisterUnitEvent takes at most two unit tokens and
  -- the watched set is six (player, target, the four party slots). onEvent does the
  -- filtering by each event's own unit (arg1).
  driver:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
  driver:RegisterEvent("UNIT_HEALTH")
  driver:RegisterEvent("UNIT_MAXHEALTH")
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

-- BIT-only settings sample: a mock health bar with the shield overlay over it, fed the
-- module's own fixed numbers (SAMPLE_MAX/SAMPLE_ABSORB), independent of live bars. The
-- numbers are plain sample data and flow only into the native SetMinMaxValues/SetValue,
-- exactly like a live reading; no game API is read here and nothing is formatted into text.
local SAMPLE_MAX, SAMPLE_ABSORB = 10000, 6200

local function buildShieldsPreview(parent)
  local scene = CreateFrame("Frame", nil, parent)
  scene:SetSize(560, 120)
  scene.title = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  scene.title:SetPoint("TOPLEFT", 12, -4)
  scene.title:SetText("Shields sample (fixed data)")
  -- The mock health bar: a plain full bar the overlay lies on, like the live frames.
  scene.bar = CreateFrame("StatusBar", nil, scene)
  scene.bar:SetSize(180, 20)
  scene.bar:SetPoint("TOPLEFT", 12, -30)
  scene.bar:SetMinMaxValues(0, SAMPLE_MAX)
  scene.bar:SetValue(SAMPLE_MAX)
  -- The overlay, exactly as overlayFor builds it on a live bar: its own StatusBar
  -- covering the health bar, carrying the sample reading.
  scene.overlay = CreateFrame("StatusBar", nil, scene.bar)
  scene.overlay:SetAllPoints(scene.bar)
  scene.overlay:SetMinMaxValues(0, SAMPLE_MAX)
  scene.overlay:SetValue(SAMPLE_ABSORB)
  return scene
end

local function renderShieldsPreview(scene, style)
  if type(scene) ~= "table" then return end
  BIT.Style.ApplyText(scene.title, style, "text")
  BIT.Style.ApplyBar(scene.bar, style, "muted")
  paintShield(scene.overlay, style)
  -- Native-Y min/max reflow: title depth, bar height and scene height all
  -- derive from the shared font size; widths stay fixed because this sample
  -- has no scale capability. The window is never resized.
  local fontSize = style.fontSize or 12
  local barH = math.max(20, fontSize + 6)
  local barDepth = 4 + fontSize + 8
  scene.bar:ClearAllPoints()
  scene.bar:SetPoint("TOPLEFT", 12, -barDepth)
  scene.bar:SetSize(180, barH)
  scene:SetSize(560, barDepth + barH + 12)
end

-- The palette roles the editor shows: "absorb" paints the overlay, "muted" the mock
-- health bar under it and "text" the sample title -- every role the module's look uses
-- (the Range.lua:451 contract).
local CAPABILITIES = { roles = { "absorb", "muted", "text" }, shapes = false,
  geometry = false, border = false, font = true, scale = false, opacity = true }

BIT.RegisterTab("ShieldsInfo", {
  buildPreview = buildShieldsPreview,
  previewRender = renderShieldsPreview,
  capabilities = CAPABILITIES,
  title = "Shields",
  summary = "The remaining absorb of a shield on your frames and nameplates.",
  width = 640, height = 900,
  build = function(parent)
    local UI = BIT.UI
    local checks = {}
    M._checks = checks
    local rows = {}
    local scene, editor
    -- The sample repaints from the same settings and resolved style the live overlays use.
    local function refreshPreview()
      if type(scene) == "table" then
        pcall(renderShieldsPreview, scene, BIT.Style.Resolve("ShieldsInfo"))
      end
    end
    local function changed()
      for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
      updateAll()
      refreshPreview()
    end
    -- A look change: the live overlays and the sample both repaint at once.
    local function styleChanged()
      restyleOverlays()
      changed()
    end
    local function set(key) return function(v) settings[key] = v; changed() end end
    local function get(key) return function() return settings[key] end end
    local y = -10
    local function add(row, height)
      row:SetPoint("TOPLEFT", 12, y)
      rows[#rows + 1] = row
      y = y - (height or 30)
    end
    local function toggle(name, label, tooltip)
      local box = UI.Check(parent, label, get(name), set(name), tooltip)
      checks[name] = box
      add(box)
    end
    toggle("player", "On your player frame",
      "The shield over your own health bar.")
    toggle("target", "On your target frame",
      "The shield over your target's health bar.")
    toggle("party", "On party frames (classic and compact party/raid)",
      "The shields over the classic party frames and the compact party/raid frames.")
    toggle("nameplates", "On nameplates",
      "The shields over every accessible nameplate.")
    local function getAlpha() return clampAlpha(settings.overlayAlpha) end
    local function setAlpha(v)
      settings.overlayAlpha = clampAlpha(v)
      styleChanged()
    end
    local alpha = UI.Slider(parent, "Fill opacity", ALPHA_MIN, ALPHA_MAX, 0.05,
      getAlpha, setAlpha, "%%",
      "How solid the shield fill is. 100% is solid; lower lets the health bar under it show through.")
    M._alpha = alpha
    add(alpha, 46)

    -- The fill art: one button per texture with a swatch of it, the current one lit.
    local fillBox = CreateFrame("Frame", nil, parent)
    fillBox:SetSize(560, 72)
    fillBox.label = fillBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fillBox.label:SetPoint("TOPLEFT", 0, 0)
    fillBox.label:SetText("Fill style")
    local fillButtons = {}
    for i, entry in ipairs(FILL_TEXTURES) do
      local b = UI.Button(fillBox, entry.label, 178, function()
        settings.fillTexture = entry.id
        styleChanged()
      end)
      b:SetPoint("TOPLEFT", ((i - 1) % 3) * 184, -18 - math.floor((i - 1) / 3) * 26)
      local sw = b:CreateTexture(nil, "ARTWORK")
      sw:SetSize(12, 12)
      sw:SetPoint("LEFT", 6, 0)
      pcall(function()
        sw:SetTexture(entry.path, entry.tiled and "REPEAT" or nil, entry.tiled and "REPEAT" or nil)
        if entry.tiled then sw:SetHorizTile(true) sw:SetVertTile(true) end
      end)
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.label, 1, 1, 1)
        GameTooltip:AddLine(entry.hint, nil, nil, nil, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      fillButtons[entry.id] = b
    end
    function fillBox:Refresh()
      local id = settings.fillTexture
      if type(id) ~= "string" then id = "flat" end
      for key, b in pairs(fillButtons) do
        b:SetAlpha(key == id and 1 or 0.55)
      end
    end
    add(fillBox, 78)

    -- The presets: one click for a known look. Only the fill art and its translucency
    -- are written; the frame switches above stay exactly as the player left them.
    local presetBox = CreateFrame("Frame", nil, parent)
    presetBox:SetSize(560, 46)
    presetBox.label = presetBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    presetBox.label:SetPoint("TOPLEFT", 0, 0)
    presetBox.label:SetText("Presets")
    for i, preset in ipairs(PRESETS) do
      local b = UI.Button(presetBox, preset.label, 150, function()
        for k, v in pairs(preset.values) do settings[k] = v end
        styleChanged()
      end)
      b:SetPoint("TOPLEFT", (i - 1) * 156, -18)
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(preset.label, 1, 1, 1)
        GameTooltip:AddLine("Only the fill style and its opacity change; your frame switches stay.",
          nil, nil, nil, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    add(presetBox, 52)

    -- The shared editor, and the module's own sample under it: the same pair the OFF-page
    -- builds as buildPreview/previewRender (the HunterRangeFinder pattern). The editor's
    -- refresh callback repaints that same scene with the freshly resolved module style.
    editor = UI.Appearance(parent, "ShieldsInfo", CAPABILITIES, refreshPreview)
    editor:SetPoint("TOPLEFT", 12, y)
    rows[#rows + 1] = editor
    y = y - editor:GetHeight() - 12
    scene = buildShieldsPreview(parent)
    scene:SetPoint("TOPLEFT", editor, "BOTTOMLEFT", 0, -12)
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