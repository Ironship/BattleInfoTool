-- UsefulPlatesAndTooltips module ShieldsInfo: the remaining absorb of a unit, as the client reports it
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
-- fixed numbers; no game reading ever reaches it. The /upt tab shows that look live on a
-- mock bar (preview on the left, tabbed settings on the right, as in DoTInfo and
-- SpellDamageInfo), so the fill, its opacity and the absorb colour can be picked while the
-- same painter runs on the live overlays.

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
local TEXTURE_DIR = "Interface\\AddOns\\UsefulPlatesAndTooltips\\Modules\\ShieldsInfo\\Textures\\"
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
  { id = "shield_aura_mirrored", label = "Mirrored aura",
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
  o = { bar = bar, unit = nil, plate = false, party = false, current = false, edge = false }
  overlays[healthBar] = o
  return o
end

-- A DoT marker already paints the fill. The shield then keeps a thin edge along the top
-- so both stay readable. With no DoT marker the overlay covers the bar, as before.
local function applyOverlayMode(o, edge)
  edge = edge and true or false
  if o.edge == edge then return end
  local bar = o.bar
  local healthBar = type(bar.GetParent) == "function" and bar:GetParent() or nil
  if type(healthBar) ~= "table" then return end
  bar:ClearAllPoints()
  if edge then
    bar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    bar:SetHeight(BIT.Plate and BIT.Plate.SHIELD_EDGE or 4)
  else
    bar:SetAllPoints(healthBar)
  end
  o.edge = edge
end

-- One unit's remaining absorb on one health bar. Raw values go to the native setters only;
-- a missing reading hides the overlay, never invents a value, and an overlay is
-- only ever created when there is a value to show. Presence is all Lua may learn:
-- type() cannot reveal a combat-secret value, so a secret absorb (or health pool)
-- flows on without one Lua comparison; only a proven-plain reading may be
-- compared, and a depleted plain shield hides like any missing one.
local function updateBar(unit, healthBar, enabled)
  local o = type(healthBar) == "table" and overlays[healthBar] or nil
  if type(healthBar) ~= "table" or not enabled or isSecret(unit) or type(unit) ~= "string" then
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
    local dotOn = BIT.Plate and type(BIT.Plate.DotOnUnit) == "function" and BIT.Plate.DotOnUnit(unit)
    applyOverlayMode(o, dotOn == true)
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
  if type(f) == "table" and not isSecret(f.unit) and type(f.unit) == "string" then
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
local compactFrames = setmetatable({}, { __mode = "k" })
local function compactGroup(frame)
  if type(frame) ~= "table" or isSecret(frame.unit) or type(frame.unit) ~= "string" then return false end
  if type(frame.IsForbidden) == "function" and frame:IsForbidden() then return false end
  if type(frame.IsVisible) == "function" and not frame:IsVisible() then return false end
  return frame.unit:match("^party%d+$") or frame.unit:match("^raid%d+$") or frame.unit:match("^arena%d+$")
end

local function compactBars(bars)
  -- Frames learned from Blizzard's hooks may belong to a nested raid pool or arena UI.
  for frame in pairs(compactFrames) do
    if compactGroup(frame) then collectMember(frame, bars) end
  end
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
    if not compactGroup(frame) then return end
    compactFrames[frame] = true
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

local function prepareShieldSettings()
  settings = BIT.Settings("ShieldsInfo", DEFAULTS)
  M.settings = settings
end
if BIT.RegisterWaker then BIT.RegisterWaker("ShieldsInfo", prepareShieldSettings) end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= BIT.name then return end
  self:UnregisterAllEvents()
  if not BIT.ShouldRun("ShieldsInfo") then return end
  prepareShieldSettings()
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
  -- covering the health bar, one frame level up so the fill draws over the bar's own,
  -- carrying the sample reading.
  scene.overlay = CreateFrame("StatusBar", nil, scene.bar)
  scene.overlay:SetAllPoints(scene.bar)
  scene.overlay:SetFrameLevel((scene.bar:GetFrameLevel() or 0) + 1)
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

---------------------------------------------------------------------------------------------
-- The /upt settings tab: a live preview on the left, tabbed settings on the right (the
-- DoTInfo/Options.lua layout). The preview's mock bars are painted by the very painter the
-- live overlays wear (styleOverlay -> paintShield) and fed only the module's own sample
-- numbers above -- no game reading reaches the preview, so it can never touch a combat
-- secret. The style presets sit in the tab's top strip, as in DoTInfo.
---------------------------------------------------------------------------------------------

local PREVIEW_WIDTH = 290
local ROW_HEIGHT = 26
local SETTINGS_LAYOUT = { label = 150, control = 190 }
local PREVIEW_LAYOUT = { label = 96, control = 128 }
local DISABLED_ALPHA = 0.35
-- 470 is Core/Settings.lua's MAX_CONTENT_HEIGHT: the tallest content the window shows without
-- its own page scroll, the same as Range's tab. Shorter (the 460 a review once settled on)
-- leaves the page a stub shorter than the window and the Effects tab still cannot fit its
-- editor -- that one scrolls inside its tab instead (addTab below).
local WINDOW_WIDTH, WINDOW_HEIGHT = 760, 470

-- The preview's own numbers (plain sample data, in % of SAMPLE_MAX) and the mock the frame
-- switch shows. The sample starts at SAMPLE_ABSORB; the sliders move health and absorb only,
-- and nothing here ever asks the game for a reading.
local preview = { frame = "player", health = 100, absorb = SAMPLE_ABSORB * 100 / SAMPLE_MAX }

-- The four mocks the frame switch offers, named and sized as the real frames read. x centres
-- the bar in the preview card; the cluster (name above, caption below) is seated on the card's
-- floor by buildLivePreview, so the mock reads like a unit frame standing in the world.
local FRAME_MOCKS = {
  { id = "player", label = "Player", caption = "Your player frame", name = "You",
    nameColor = { 1, 1, 1 }, barColor = { 0.12, 0.85, 0.12 }, width = 224, height = 18, x = 21 },
  { id = "target", label = "Target", caption = "Your target frame", name = "Murloc Raider",
    nameColor = { 1, 0.2, 0.15 }, barColor = { 0.12, 0.85, 0.12 }, width = 224, height = 18, x = 21 },
  { id = "party", label = "Party", caption = "A party frame", name = "Kaya",
    nameColor = { 0.65, 0.8, 1 }, barColor = { 0.12, 0.85, 0.12 }, width = 192, height = 15, x = 37 },
  { id = "nameplate", label = "Nameplate", caption = "An enemy nameplate", name = "Murloc Raider",
    nameColor = { 1, 0.13, 0.13 }, barColor = { 0.85, 0.1, 0.1 }, width = 214, height = 12, x = 26 },
}

local function findMock(id)
  for i = 1, #FRAME_MOCKS do
    if FRAME_MOCKS[i].id == id then return FRAME_MOCKS[i] end
  end
  return FRAME_MOCKS[1]
end

-- The absorb colours the Fill tab offers next to the native picker. The colour itself lives
-- in the shared appearance (role "absorb"), never in the module's saved settings.
local ABSORB_PRESETS = {
  { id = "blue", label = "Blue", rgb = { 0.45, 0.75, 1.0 } },
  { id = "cyan", label = "Cyan", rgb = { 0.35, 0.85, 0.95 } },
  { id = "white", label = "White", rgb = { 1, 1, 1 } },
  { id = "gold", label = "Gold", rgb = { 1, 0.82, 0.2 } },
  { id = "green", label = "Green", rgb = { 0.35, 1, 0.55 } },
  { id = "violet", label = "Violet", rgb = { 0.7, 0.5, 1 } },
}

local controls = {} -- every settings/preview row, refreshed after each change
local tabs, activeTab = {}, nil
local menu -- the shared dropdown list
local scene -- the live preview's mock frame
local refreshPreview -- built with the preview; repaints it from the settings and the style

local function setBackdrop(frame, shade, alpha)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(shade, shade, shade, alpha or 1)
  frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

local function refreshControls()
  for i = 1, #controls do
    local row = controls[i]
    if row.Refresh then row:Refresh() end
  end
end

local function changed()
  refreshControls()
  -- Sliders and color drags must not re-enumerate every frame each step: the
  -- overlays restyle in place and the 0.2s poll refreshes the numbers.
  pcall(restyleOverlays)
  if refreshPreview then refreshPreview() end
end

-- A look change: the live overlays and the preview repaint at once.
local function styleChanged()
  pcall(restyleOverlays)
  changed()
end

local function percentText(v) return math.floor((tonumber(v) or 0) + 0.5) .. "%" end

-- The preview's percentages stay inside the bar whatever the sliders hold.
local function clampPercent(v)
  if type(v) ~= "number" or v ~= v then return 0 end
  if v < 0 then return 0 end
  if v > 100 then return 100 end
  return v
end

---------------------------------------------------------------------------------------------
-- Controls: the DoTInfo/Options.lua rows (label left, control right, tooltips, graying)
---------------------------------------------------------------------------------------------

local function makeRow(parent, labelText, opts)
  opts = opts or {}
  local layout = opts.layout or SETTINGS_LAYOUT
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(layout.label + layout.control + 40, ROW_HEIGHT)
  row.layout = layout
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.label:SetPoint("LEFT", 6, 0)
  row.label:SetWidth(layout.label - 8)
  row.label:SetJustifyH("LEFT")
  row.label:SetText(labelText)
  row.enabledIf = opts.enabledIf
  if opts.tooltip then
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(labelText, 1, 1, 1)
      GameTooltip:AddLine(opts.tooltip, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  function row:ApplyEnabled(widget)
    local enabled = not self.enabledIf or self.enabledIf(settings or DEFAULTS)
    self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    widget:EnableMouse(enabled)
    if widget.EnableMouseWheel then widget:EnableMouseWheel(enabled) end
  end
  controls[#controls + 1] = row
  return row
end

local function checkbox(parent, key, labelText, opts)
  opts = opts or {}
  local row = makeRow(parent, labelText, opts)
  local box = CreateFrame("CheckButton", nil, row)
  box:SetSize(24, 24)
  box:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetScript("OnClick", function(self)
    settings[key] = self:GetChecked() and true or false
    changed()
  end)
  function row:Refresh()
    box:SetChecked(settings[key] and true or false)
    self:ApplyEnabled(box)
  end
  row.widget = box
  return row
end

-- get/set work on any value (settings or the preview's own numbers).
local function sliderRow(parent, labelText, min, max, step, get, set, opts)
  opts = opts or {}
  local row = makeRow(parent, labelText, opts)
  local slider = CreateFrame("Slider", nil, row)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(row.layout.control - 48, 18)
  slider:SetPoint("LEFT", row, "LEFT", row.layout.label + 2, 0)
  slider:SetMinMaxValues(min, max)
  slider:SetValueStep(step)
  pcall(function() slider:SetObeyStepOnDrag(true) end)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.3, 0.3, 0.32, 1)
  track:SetHeight(4)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb = slider:GetThumbTexture()
  if thumb and thumb.SetSize then thumb:SetSize(18, 24) end
  local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  local function show(v)
    if opts.display then
      valueText:SetText(opts.display(v))
    else
      valueText:SetText(percentText(v))
    end
  end
  local updating = false
  slider:SetScript("OnValueChanged", function(_, value)
    if updating then return end
    value = math.floor(value / step + 0.5) * step
    show(value)
    set(value)
  end)
  slider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue((self:GetValue() or 0) + delta * step)
  end)
  function row:Refresh()
    updating = true
    local value = get()
    slider:SetValue(value)
    show(value)
    updating = false
    self:ApplyEnabled(slider)
  end
  row.bar, row.widget = slider, slider
  return row
end

local function pushButton(parent, text, width, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

-- The width the text needs in the panel button's own font (GameFontNormal), measured on a hidden
-- string, so a label such as "Nameplate" is never cut off by its button.
local function labelWidth(parent, text)
  local probe = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  probe:SetText(text)
  local width = probe:GetStringWidth() or 0
  probe:Hide()
  return width
end

local function closeMenu()
  if menu then menu:Hide() end
end

-- Shared dropdown list under `owner`; entries may carry an rgb swatch (the DoTInfo menu).
local function openMenu(owner, list, current, pick)
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    setBackdrop(menu, 0.08, 0.98)
    menu.buttons = {}
    -- Close on a click anywhere else (the event may not exist on every client).
    pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function(self)
      if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
    end)
  end
  if menu:IsShown() and menu.owner == owner then return menu:Hide() end
  menu.owner = owner
  for i, entry in ipairs(list) do
    local button = menu.buttons[i]
    if not button then
      button = CreateFrame("Button", nil, menu)
      button:SetHeight(20)
      local highlight = button:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      highlight:SetColorTexture(1, 1, 1, 0.1)
      button.swatch = button:CreateTexture(nil, "ARTWORK")
      button.swatch:SetSize(12, 12)
      button.swatch:SetPoint("LEFT", 8, 0)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      button.text:SetJustifyH("LEFT")
      menu.buttons[i] = button
    end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * 20)
    button:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
    button.swatch:SetShown(entry.rgb ~= nil)
    if entry.rgb then button.swatch:SetColorTexture(entry.rgb[1], entry.rgb[2], entry.rgb[3], 1) end
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", entry.rgb and 26 or 8, 0)
    button.text:SetText(entry.id == current and ("|cffffd100" .. entry.label .. "|r") or entry.label)
    button:SetScript("OnClick", function()
      menu:Hide()
      pick(entry.id)
    end)
    button:Show()
  end
  for i = #list + 1, #menu.buttons do menu.buttons[i]:Hide() end
  menu:SetSize(owner:GetWidth(), #list * 20 + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  menu:Show()
end

---------------------------------------------------------------------------------------------
-- The absorb colour (the shared style's "absorb" role): a swatch with quick colours and the
-- native picker. Every write goes through BIT.Style, so the live overlays and the preview
-- repaint from the same resolved colour.
---------------------------------------------------------------------------------------------

local function resolvedStyle()
  if type(BIT.Style) == "table" and type(BIT.Style.Resolve) == "function" then
    local ok, s = pcall(BIT.Style.Resolve, "ShieldsInfo")
    if ok and type(s) == "table" then return s end
  end
  return nil
end

local function absorbColor()
  local s = resolvedStyle()
  local c = s and type(s.colors) == "table" and s.colors.absorb or nil
  if type(c) == "table" then return c end
  return { 0.45, 0.75, 1, 1 }
end

local function absorbColorPresetId()
  local c = absorbColor()
  for i = 1, #ABSORB_PRESETS do
    local p = ABSORB_PRESETS[i]
    if math.abs(p.rgb[1] - c[1]) < 0.02 and math.abs(p.rgb[2] - c[2]) < 0.02
      and math.abs(p.rgb[3] - c[3]) < 0.02 then
      return p.id
    end
  end
  return "custom"
end

local function absorbColorLabel()
  local id = absorbColorPresetId()
  for i = 1, #ABSORB_PRESETS do
    if ABSORB_PRESETS[i].id == id then return ABSORB_PRESETS[i].label end
  end
  return "Custom"
end

local function commitAbsorbColor(r, g, b, a)
  if type(BIT.Style) == "table" and type(BIT.Style.Set) == "function" then
    pcall(BIT.Style.Set, "ShieldsInfo", "colors", { absorb = { r, g, b, a or 1 } })
  end
  changed()
end

-- The native colour picker, with its drag callbacks suppressed while it opens. A client
-- without it keeps the preset colours above; nothing here can error out of a click.
local function openAbsorbPicker()
  local picker = ColorPickerFrame
  if not picker or type(picker.SetupColorPickerAndShow) ~= "function" then return end
  local c = absorbColor()
  local last = { c[1], c[2], c[3], c[4] or 1 }
  local initializing = true
  local function commit()
    if initializing then return end
    local r, g, b = picker:GetColorRGB()
    local a = last[4]
    pcall(function() a = picker:GetColorAlpha() end)
    if math.abs(r - last[1]) < 0.000001 and math.abs(g - last[2]) < 0.000001
      and math.abs(b - last[3]) < 0.000001 and math.abs(a - last[4]) < 0.000001 then return end
    last = { r, g, b, a }
    commitAbsorbColor(r, g, b, a)
  end
  pcall(function()
    picker:SetupColorPickerAndShow({
      r = c[1], g = c[2], b = c[3], opacity = last[4], hasOpacity = true,
      swatchFunc = commit, opacityFunc = commit,
    })
  end)
  initializing = false
end

-- The Fill tab's colour row: label left, swatch button right, like the other rows.
local function absorbColorRow(parent, labelText)
  local row = makeRow(parent, labelText, {
    tooltip = "The colour of the shield fill: the shared appearance's absorb colour. "
      .. "The Effects tab holds the full palette.",
  })
  local button = CreateFrame("Button", nil, row, "BackdropTemplate")
  button:SetSize(row.layout.control, 22)
  button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
  setBackdrop(button, 0.13)
  local swatch = button:CreateTexture(nil, "ARTWORK")
  swatch:SetSize(12, 12)
  swatch:SetPoint("LEFT", 8, 0)
  local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetJustifyH("LEFT")
  text:SetPoint("LEFT", 26, 0)
  text:SetPoint("RIGHT", -20, 0)
  local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -8, 0)
  arrow:SetText("v")
  button:SetScript("OnClick", function(self)
    local list = {}
    for i = 1, #ABSORB_PRESETS do
      local p = ABSORB_PRESETS[i]
      list[#list + 1] = { id = p.id, label = p.label, rgb = p.rgb }
    end
    list[#list + 1] = { id = "custom", label = "Custom colour..." }
    openMenu(self, list, absorbColorPresetId(), function(id)
      if id == "custom" then
        openAbsorbPicker()
        return
      end
      for i = 1, #ABSORB_PRESETS do
        local p = ABSORB_PRESETS[i]
        if p.id == id then
          commitAbsorbColor(p.rgb[1], p.rgb[2], p.rgb[3], absorbColor()[4])
        end
      end
    end)
  end)
  function row:Refresh()
    local c = absorbColor()
    swatch:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    text:SetText(absorbColorLabel())
    self:ApplyEnabled(button)
  end
  row.widget, row.swatch = button, swatch
  return row
end

---------------------------------------------------------------------------------------------
-- Presets and tabs
---------------------------------------------------------------------------------------------

-- The presets write only the fill art and its translucency (plain style numbers), never the
-- frame switches, so a preset cannot turn a frame off.
local function applyPreset(preset)
  for k, v in pairs(preset.values) do settings[k] = v end
  styleChanged()
end

local function selectTab(tab)
  closeMenu()
  activeTab = tab
  for _, other in ipairs(tabs) do
    local selected = other == tab
    other.content:SetShown(selected)
    other.button.text:SetTextColor(selected and 1 or 0.6, selected and 0.82 or 0.6, selected and 0 or 0.6)
    other.button.underline:SetShown(selected)
  end
end

-- A tab whose methods add rows top to bottom and remember the setting keys, for "Reset this
-- tab". A tab may add resetExtra for the style keys its rows write. Every tab's content is a
-- scroll frame (Modules/HunterRangeFinder/HunterRangeFinder.lua): the Effects tab hosts the
-- shared appearance editor, which is taller than the area, and a scroll each keeps the
-- overflow inside the tab -- clipped and reachable -- instead of spilling past the window.
local function addTab(name, area)
  local tab = { keys = {}, y = 0 }
  local content = CreateFrame("ScrollFrame", nil, area)
  content:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -40)
  content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 40)
  content:EnableMouseWheel(true)
  -- SetScrollChild owns the child's anchors (Core/Settings.lua): explicit geometry only.
  local inner = CreateFrame("Frame", nil, content)
  inner:SetWidth((area:GetWidth() or 400) - 16)
  content:SetScrollChild(inner)
  content:SetScript("OnMouseWheel", function(_, delta)
    local maxScroll = math.max(0, (inner:GetHeight() or 0) - (content:GetHeight() or 0))
    local at = (content:GetVerticalScroll() or 0) - delta * 24
    content:SetVerticalScroll(math.min(math.max(at, 0), maxScroll))
  end)
  content:SetScript("OnSizeChanged", function(_, width)
    if type(width) == "number" and width > 0 then inner:SetWidth(width) end
  end)
  tab.content, tab.inner = content, inner
  content:Hide()

  local button = CreateFrame("Button", nil, area)
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.text:SetText(name)
  button:SetSize(button.text:GetStringWidth() + 20, 26)
  button.text:SetPoint("CENTER")
  button.underline = button:CreateTexture(nil, "ARTWORK")
  button.underline:SetColorTexture(1, 0.82, 0, 1)
  button.underline:SetHeight(2)
  button.underline:SetPoint("BOTTOMLEFT", 6, 0)
  button.underline:SetPoint("BOTTOMRIGHT", -6, 0)
  local previous = tabs[#tabs]
  if previous then
    button:SetPoint("LEFT", previous.button, "RIGHT", 2, 0)
  else
    button:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
  end
  button:SetScript("OnClick", function() selectTab(tab) end)
  tab.button = button

  local function place(row, height, key)
    row:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -tab.y)
    tab.y = tab.y + (height or ROW_HEIGHT)
    if key then tab.keys[#tab.keys + 1] = key end
    return row
  end
  function tab:add(row, height, key) return place(row, height, key) end
  function tab:gap(n) self.y = self.y + (n or 8) end
  -- The scroll child grows to the rows just added; a tab that fits never scrolls.
  function tab:finish() self.inner:SetHeight(math.max(self.y + 12, 1)) end

  tabs[#tabs + 1] = tab
  return tab
end

-- "Reset this tab": the tab's own saved keys back to the defaults, plus the style keys its
-- rows write (resetExtra). The frame switches are only in the Frames tab, so resetting a
-- look can never turn a frame off.
local function resetTab(tab)
  if not tab then return end
  for i = 1, #tab.keys do
    local key = tab.keys[i]
    settings[key] = DEFAULTS[key]
  end
  if tab.resetExtra then pcall(tab.resetExtra) end
  styleChanged()
end

---------------------------------------------------------------------------------------------
-- The left column: the live preview (the DoTInfo preview pane). One mock health bar with the
-- shield overlay over it, repainted from the current settings and style; the numbers under
-- the sliders are this preview's own sample data and flow only into the native setters.
---------------------------------------------------------------------------------------------

local function buildLivePreview(pane)
  local SIDE = 12
  local CARD_WIDTH = PREVIEW_WIDTH - 2 * SIDE
  local RULE = { 0.28, 0.28, 0.3 }
  local SCENE_HEIGHT = 170
  local BAR_SEAT = 40 -- the bar's bottom edge, above the caption it hangs over the floor

  local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", pane, "TOPLEFT", SIDE, -12)
  title:SetText("Live preview")
  local titleRule = pane:CreateTexture(nil, "ARTWORK")
  titleRule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
  titleRule:SetHeight(1)
  titleRule:SetPoint("TOPLEFT", 8, -34)
  titleRule:SetPoint("TOPRIGHT", -8, -34)

  -- Section header: small gold caps and a hairline to the right margin (the Range and
  -- DoTInfo previews). Every block below is anchored to the one over it, never to a
  -- hard-coded y, so the column holds together at any pane height.
  local function header(text, anchor, gap)
    local label = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    label:SetText(text)
    label:SetTextColor(0.85, 0.7, 0.3)
    local rule = pane:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)
    return label
  end

  scene = CreateFrame("Frame", nil, pane, "BackdropTemplate")
  scene:SetSize(CARD_WIDTH, SCENE_HEIGHT)
  scene:SetPoint("TOP", pane, "TOP", 0, -44)
  setBackdrop(scene, 0.06)
  local ground = scene:CreateTexture(nil, "BACKGROUND")
  ground:SetPoint("TOPLEFT", 1, -1)
  ground:SetPoint("BOTTOMRIGHT", -1, 1)
  ground:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
  ground:SetTexCoord(0, 0.26, 0, 0.18) -- about 1:1 texels on the card
  ground:SetVertexColor(0.75, 0.8, 0.75)

  -- The mock health bar the overlay lies on, and the overlay itself: exactly as overlayFor
  -- builds it on a live bar (its own StatusBar covering the health bar, one frame level up so
  -- the fill draws over the bar's own), carrying the sample reading instead of a game one.
  scene.bar = CreateFrame("StatusBar", nil, scene)
  scene.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  scene.bar:SetMinMaxValues(0, SAMPLE_MAX)
  scene.bar:SetValue(SAMPLE_MAX)
  scene.name = scene:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  scene.caption = scene:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  scene.overlay = CreateFrame("StatusBar", nil, scene.bar)
  scene.overlay:SetAllPoints(scene.bar)
  scene.overlay:SetFrameLevel((scene.bar:GetFrameLevel() or 0) + 1)
  scene.overlay:SetMinMaxValues(0, SAMPLE_MAX)
  scene.overlay:SetValue(SAMPLE_ABSORB)

  -- The frame switch: which of the module's frames the mock stands for.
  local which = header("FRAME", scene, 12)
  local switch = CreateFrame("Frame", nil, pane)
  switch:SetSize(CARD_WIDTH, 24)
  switch:SetPoint("TOPLEFT", which, "BOTTOMLEFT", 0, -4)
  local switchButtons = {}
  local switchRow = {}
  -- Each button is as wide as its own name needs, with 9 px either side of the text; the four and
  -- their 3 px gaps stay within the card.
  local left = 0
  for i = 1, #FRAME_MOCKS do
    local m = FRAME_MOCKS[i]
    local b = pushButton(switch, m.label, 56, function()
      preview.frame = m.id
      changed()
    end)
    local width = math.max(56, math.ceil(labelWidth(switch, m.label)) + 18)
    b:SetWidth(width)
    b:SetPoint("TOPLEFT", switch, "TOPLEFT", left, 0)
    left = left + width + 3
    switchButtons[m.id] = b
  end
  M._frameButtons = switchButtons
  function switchRow:Refresh()
    for id, b in pairs(switchButtons) do
      b:SetAlpha(id == preview.frame and 1 or 0.55)
    end
  end
  controls[#controls + 1] = switchRow

  -- TRY IT: the preview's own numbers, in % of the sample bar. Plain sample percentages --
  -- the live overlays read the real absorb in combat, and no reading is taken here.
  local tryIt = header("TRY IT", switch, 12)
  local health = sliderRow(pane, "Bar health", 0, 100, 1,
    function() return preview.health end,
    function(value)
      preview.health = value
      refreshPreview()
    end,
    { layout = PREVIEW_LAYOUT,
      tooltip = "How full the mock health bar is, in % of its sample maximum." })
  health:SetPoint("TOPLEFT", tryIt, "BOTTOMLEFT", -6, -6)

  local absorb = sliderRow(pane, "Shield absorb", 0, 100, 1,
    function() return preview.absorb end,
    function(value)
      preview.absorb = value
      refreshPreview()
    end,
    { layout = PREVIEW_LAYOUT,
      tooltip = "How much of the bar the sample shield covers, in % of its sample maximum. "
        .. "The preview runs on this fixed sample number only." })
  absorb:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 0)
  M._previewRows = { health = health, absorb = absorb }

  local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", absorb, "BOTTOMLEFT", 6, -12)
  hint:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText("The preview paints a fixed sample with the same painter as the live overlays; "
    .. "no live absorb is read here.")
  local hintRule = pane:CreateTexture(nil, "ARTWORK")
  hintRule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
  hintRule:SetHeight(1)
  hintRule:SetPoint("BOTTOMLEFT", hint, "TOPLEFT", 0, 8)
  hintRule:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)

  -- One painter for the mock (styleOverlay, the live overlays' own) and the sample numbers:
  -- a settings change, a preset or a style write all land here at once.
  refreshPreview = function()
    if type(scene) ~= "table" then return end
    pcall(function()
      local m = findMock(preview.frame)
      scene.bar:SetSize(m.width, m.height)
      scene.bar:ClearAllPoints()
      scene.bar:SetPoint("BOTTOMLEFT", scene, "BOTTOMLEFT", m.x, BAR_SEAT)
      scene.bar:SetStatusBarColor(m.barColor[1], m.barColor[2], m.barColor[3], 1)
      scene.bar:SetMinMaxValues(0, SAMPLE_MAX)
      scene.bar:SetValue(SAMPLE_MAX * clampPercent(preview.health) / 100)
      scene.name:SetText(m.name)
      scene.name:SetTextColor(m.nameColor[1], m.nameColor[2], m.nameColor[3], 1)
      scene.name:ClearAllPoints()
      scene.name:SetPoint("BOTTOMLEFT", scene.bar, "TOPLEFT", 0, 4)
      scene.caption:SetText(m.caption)
      scene.caption:ClearAllPoints()
      scene.caption:SetPoint("TOPLEFT", scene.bar, "BOTTOMLEFT", 0, -6)
      scene.overlay:SetAllPoints(scene.bar)
      scene.overlay:SetFrameLevel((scene.bar:GetFrameLevel() or 0) + 1)
      scene.overlay:SetMinMaxValues(0, SAMPLE_MAX)
      scene.overlay:SetValue(SAMPLE_MAX * clampPercent(preview.absorb) / 100)
      styleOverlay(scene.overlay)
    end)
  end
end

---------------------------------------------------------------------------------------------
-- The right column: Frames, Fill and Effects, with "Reset this tab" under them.
---------------------------------------------------------------------------------------------

local function buildTabs(area)
  local checks = {}
  M._checks = checks

  -- Frames: the saved switches, exactly the four the runtime reads.
  local frames = addTab("Frames", area)
  local function toggle(key, labelText, tooltip)
    local row = checkbox(frames.inner, key, labelText, { tooltip = tooltip })
    frames:add(row, ROW_HEIGHT, key)
    local box = row.widget
    if box then
      function box:Refresh() self:SetChecked(settings[key] and true or false) end
      checks[key] = box
    end
    return row
  end
  toggle("player", "On your player frame",
    "The shield over your own health bar.")
  toggle("target", "On your target frame",
    "The shield over your target's health bar.")
  toggle("party", "On party frames (classic and compact party/raid)",
    "The shields over the classic party frames and the compact party/raid frames.")
  toggle("nameplates", "On nameplates",
    "The shields over every accessible nameplate.")

  -- Fill: the art, its translucency and the absorb colour.
  local fill = addTab("Fill", area)
  local fillBox = CreateFrame("Frame", nil, fill.inner)
  fillBox:SetSize(400, 78)
  fillBox.label = fillBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fillBox.label:SetPoint("TOPLEFT", 0, 0)
  fillBox.label:SetText("Fill style")
  local fillButtons = {}
  for i, entry in ipairs(FILL_TEXTURES) do
    local b = pushButton(fillBox, entry.label, 128, function()
      settings.fillTexture = entry.id
      styleChanged()
    end)
    b:SetPoint("TOPLEFT", ((i - 1) % 3) * 136, -18 - math.floor((i - 1) / 3) * 26)
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
  M._fillButtons = fillButtons
  fill:add(fillBox, 78, "fillTexture")

  -- The shield translucency: clamped to the range the overlay painter accepts.
  local alpha = sliderRow(fill.inner, "Fill opacity", ALPHA_MIN, ALPHA_MAX, 0.05,
    function() return clampAlpha(settings.overlayAlpha) end,
    function(v)
      settings.overlayAlpha = clampAlpha(v)
      styleChanged()
    end,
    { display = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
      tooltip = "How solid the shield fill is. 100% is solid; lower lets the health bar under it show through." })
  fill:add(alpha, ROW_HEIGHT, "overlayAlpha")
  M._alpha = alpha

  local color = absorbColorRow(fill.inner, "Absorb color")
  fill:add(color, ROW_HEIGHT)
  M._colorButton = color.widget
  -- The colour is a style write, so the tab's reset puts it back to no override.
  fill.resetExtra = function()
    if type(BIT.Style) == "table" and type(BIT.Style.RemoveColor) == "function" then
      pcall(BIT.Style.RemoveColor, "ShieldsInfo", "absorb")
    end
  end

  -- Effects: room for the future (glow, flash), with the shared appearance editor today.
  -- The editor is taller than the tab area: it lives in the tab's scroll child and the tab
  -- scrolls to it (addTab), so "Reset this tab" and the window's bottom stay in view.
  local effects = addTab("Effects", area)
  local note = effects.inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", effects.inner, "TOPLEFT", 0, 0)
  note:SetWidth(400)
  note:SetJustifyH("LEFT")
  note:SetText("Extra shield effects land here later. The shared appearance editor below "
    .. "paints the overlay's colour, opacity and text.")
  effects.y = effects.y + 34
  if type(BIT.UI) == "table" and type(BIT.UI.Appearance) == "function" then
    local caps = { roles = CAPABILITIES.roles, shapes = false, geometry = false, border = false,
      font = true, scale = false, opacity = true, width = 400 }
    local ok, editor = pcall(BIT.UI.Appearance, effects.inner, "ShieldsInfo", caps, changed)
    if ok and type(editor) == "table" then
      editor:SetPoint("TOPLEFT", effects.inner, "TOPLEFT", 0, -effects.y)
      effects.editor = editor
      local editorTop = effects.y
      editor.onLayout = function()
        effects.y = editorTop + (editor:GetHeight() or 0) + 8
        effects:finish()
        effects.content:SetVerticalScroll(0)
      end
      effects.y = editorTop + (editor:GetHeight() or 0) + 8
    end
  end
  effects.resetExtra = function()
    if type(BIT.Style) == "table" and type(BIT.Style.Reset) == "function" then
      pcall(BIT.Style.Reset, "ShieldsInfo")
    end
  end

  for _, tab in ipairs(tabs) do tab:finish() end
end

-- The tab's content: presets in the top strip (DoTInfo's title-bar row), the preview pane on
-- the left and the settings area on the right.
local function buildContent(parent)
  local anchor = CreateFrame("Frame", nil, parent)
  anchor:SetSize(1, 22)
  anchor:SetPoint("TOPRIGHT", -10, -8)
  local presetLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  local previous
  for i = #PRESETS, 1, -1 do
    local preset = PRESETS[i]
    local button = pushButton(parent, preset.label, 78, function() applyPreset(preset) end)
    if previous then
      button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
    else
      button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    end
    button:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(preset.label .. " preset", 1, 1, 1)
      GameTooltip:AddLine("Only the fill style and its opacity change; your frame switches stay.",
        nil, nil, nil, true)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    previous = button
  end
  presetLabel:SetPoint("RIGHT", previous, "LEFT", -8, 0)
  presetLabel:SetText("Presets")

  local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  pane:SetPoint("TOPLEFT", 10, -44)
  pane:SetPoint("BOTTOMLEFT", 10, 10)
  pane:SetWidth(PREVIEW_WIDTH)
  setBackdrop(pane, 0.09)

  local area = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  area:SetPoint("TOPLEFT", pane, "TOPRIGHT", 10, 0)
  area:SetPoint("BOTTOMRIGHT", -10, 10)
  setBackdrop(area, 0.09)

  local divider = area:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(0.28, 0.28, 0.3, 1)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", 8, -34)
  divider:SetPoint("TOPRIGHT", -8, -34)

  buildLivePreview(pane)
  buildTabs(area)

  local reset = pushButton(area, "Reset this tab", 120, function() resetTab(activeTab) end)
  reset:SetPoint("BOTTOMRIGHT", -10, 10)

  -- Style writes made elsewhere (the OFF-page editor, the shared scope) repaint the preview too.
  if type(BIT.Style) == "table" and type(BIT.Style.Subscribe) == "function" then
    pcall(BIT.Style.Subscribe, "ShieldsInfo", function() pcall(changed) end)
  end

  selectTab(tabs[1])
  changed()
end

BIT.RegisterTab("ShieldsInfo", {
  buildPreview = buildShieldsPreview,
  previewRender = renderShieldsPreview,
  capabilities = CAPABILITIES,
  title = "Shields",
  summary = "The remaining absorb of a shield on your frames and nameplates.",
  width = WINDOW_WIDTH, height = WINDOW_HEIGHT,
  build = function(parent)
    buildContent(parent)
  end,
})
BIT.tabWords.shields = "ShieldsInfo"

-- For the tests.
M._driver = function() return driver end
M._tabs = tabs
M._previewState = preview
M._refreshPreview = function() if refreshPreview then refreshPreview() end end
M._overlay = function(bar) return overlays[bar] end
M._overlayCount = function()
  local n = 0
  for _ in pairs(overlays) do n = n + 1 end
  return n
end
M._attachCompactHooks = attachCompactHooks
M._hooksAttached = function() return hookedUpdateAll, hookedHealPrediction end
