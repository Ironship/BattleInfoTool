-- BattleInfoTool module HunterRangeFinder: the hunter's approximate range in native markers.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
--
-- The hunter's range ladder in seven stacked chevrons, fully inside BattleInfoTool:
--   * the settings live in one BIT.Settings("HunterRangeFinder") store, built into the module's
--     tab (/bit hunter), instead of a standalone store with a window and slash commands of its own;
--   * the module starts a HUD only for a Hunter with the module switched on; any other class (or
--     a switched-off module) creates no frames, events or polling, and the tab explains that.
-- /bit hunterprobe prints what the client answers, for diagnostics.
-- Range ladder and melee/dead-zone checks adapted from the supplied Bands.lua.
--
-- R1 (BIT Minimal): the display is a compact native segment rail or bar plus a readable
-- approximate zone label, drawn through the shared BIT.Style primitives. The retired
-- supplied artwork files stay in place untouched for packaging reconciliation and are
-- never loaded, not even optionally.
--
-- The probes are approximate, never exact yards: item probes mark the 10/15/20/25/30/35
-- yd boundaries, and the seventh slot needs the 35 yd probe to come back false while Auto
-- Shot (75) is in range. When the 35 yd probe cannot say, the rail stays at six lit slots.
-- Wing Clip (2974) measures melee (never Raptor Strike), and Auto Shot's minimum range marks
-- the dead zone (5-8 yd) between melee and the first slot.

local _, BIT = ...

local M = BIT.Module("HunterRangeFinder")

local DEFAULTS = {
    x = 0.19970703125, y = -229.9999389648438, scale = 1, opacity = 1,
    -- Retired display dimensions, kept so saved values survive: only nondefault
    -- values still map onto the shared style (the legacy fallback below).
    chevronHeight = 1, chevronWidth = 1,
    locked = true,
    attachToPlate = true, plateOffset = -8,
    longRange = false,
    -- Retired display flags, kept so saved values survive: they never restore
    -- the old artwork. A stored animation flag maps onto reducedMotion = false.
    animateDeadzone = false, animateMelee = false,
    showDeadzoneIcon = true, showMeleeIcon = true,
    smallBottomChevron = true,
}

-- R1 Hunter requested visuals (verified native Blizzard assets, no custom TGA):
--   Dead Zone skull: Interface\TargetingFrame\UI-RaidTargetingIcon_8 (Classic
--     ChatFrameConstants.lua ICON_LIST[8]/ICON_TAG_LIST skull, Gethe 8165d4).
--   Melee mark: Interface\Icons\INV_Sword_04 (public Blizzard bag/inventory
--     sword icon, used as a static melee glyph; never a RaidTarget assignment).
local DEAD_ZONE_SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
-- One-time narrow shape migration version (own module key only).
local R1_SHAPE_MIGRATION_VERSION = 1

-- Requested module defaults via the frozen Core registry: round dots,
-- border8/thickness12/gap7/length10/scale1, inverted near-RED / far-GREEN
-- distance gradient (mid stays product yellow). Explicit global/per-module
-- RGB writes keep winning; legacy fallback holds no shape/colors so it
-- cannot override these.
if BIT.Style and BIT.Style.RegisterDefaults then
    BIT.Style.RegisterDefaults("HunterRangeFinder", {
        shape = "dots", thickness = 14, border = 2, gap = 4, length = 10, scale = 1,
        colors = {
            distanceNear = { 1, 0.25, 0.25, 1 },
            distanceFar = { 0.3, 1, 0.3, 1 },
        },
    })
end

-- Narrow one-direction migration: saved appearance Hunter.shape == "segments"
-- (the user screenshot state) becomes "dots" once, preserving every other
-- geometry/color/setting and the anchor. Records hunterR1ShapeMigrated = 1 in
-- the own module store; a later explicit "segments" choice is respected (no
-- recurring force). Pure: only SavedVariables tables, no frames/units/sound,
-- never crashes on unknown/malformed appearance, never creates unrelated
-- module settings, never rewrites .lua files (runs inside the addon on load).
local function migrateHunterShape()
    if type(BattleInfoToolDB) ~= "table" then return end
    local mods = BattleInfoToolDB.modules
    if type(mods) ~= "table" then return end
    local a = BattleInfoToolDB.appearance
    if type(a) ~= "table" then return end
    local mmods = a.modules
    if type(mmods) ~= "table" then return end
    local h = mmods["HunterRangeFinder"]
    if type(h) ~= "table" then return end
    if h.shape ~= "segments" then return end
    local own = mods["HunterRangeFinder"]
    if type(own) == "table" and own.hunterR1ShapeMigrated == R1_SHAPE_MIGRATION_VERSION then return end
    h.shape = "dots"
    if type(own) ~= "table" then
        own = {}
        mods["HunterRangeFinder"] = own
    end
    own.hunterR1ShapeMigrated = R1_SHAPE_MIGRATION_VERSION
end

-- From nearest to farthest. The item ids name Bands.lua's rungs; the first field is the band.
local ladder = {
    {"Y10", 17626, 10699, 17689},
    {"Y15", 4559},
    {"Y20", 10645, 1191, 4388},
    {"Y25", 13289},
    {"Y30", 7734, 17202, 835, 2091},
    {"Y35", 18904},
}

local meleeSpell = 2974

local settings

local function isSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) or false
end

local spellNames = {}
local function spellName(id)
    if not id then return nil end
    if spellNames[id] then return spellNames[id] end
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and type(info.name) == "string" then name = info.name end
        if ok and type(info) == "string" then name = info end
    end
    if not name and GetSpellInfo then
        local ok, info = pcall(GetSpellInfo, id)
        if ok then name = info end
    end
    -- A secret name is never cached, compared or printed.
    if type(name) == "string" and not isSecret(name) then spellNames[id] = name end
    return name
end

-- 0/1/false/true answered by the client; anything else (an error, a secret) is "cannot say".
local function normalize(value)
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
    return nil
end

----------------------------------------------------------------------------------------------
-- The range probes. Every call is guarded: errors and secret values mean "cannot say", never a
-- guess. Spells are asked by name first (the client answers for the ranked spell), then by id.
----------------------------------------------------------------------------------------------

local function safeNormalize(value)
    local ok, result = pcall(normalize, value) -- instance secrets cannot be compared
    if ok then return result end
    return nil
end

local function spellInRange(id)
    if not id then return nil end
    local name = spellName(id)
    if name and IsSpellInRange then
        local ok, value = pcall(IsSpellInRange, name, "target")
        if ok then
            local result = safeNormalize(value)
            if result ~= nil then return result end
        end
    end
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, value = pcall(C_Spell.IsSpellInRange, id, "target")
        if ok then return safeNormalize(value) end
    end
    return nil
end

local function itemInRange(id)
    if C_Item and C_Item.IsItemInRange then
        local ok, value = pcall(C_Item.IsItemInRange, id, "target")
        if ok then return safeNormalize(value) end
    elseif IsItemInRange then
        local ok, value = pcall(IsItemInRange, id, "target")
        if ok then return safeNormalize(value) end
    end
    return nil
end

-- One rung: true when any item reaches, false only when an item answers false, nil when none can.
local function anyInRange(rung)
    local sawFalse = false
    for i = 2, #rung do
        local value = itemInRange(rung[i])
        if value == true then return true end
        if value == false then sawFalse = true end
    end
    if sawFalse then return false end
    return nil
end

-- Hawk Eye (or any +range effect) moves Auto Shot past 35 yd and only then the
-- seventh slot exists: without it the rail is six dots, with it seven. Proven from
-- data, never guessed: Auto Shot's own maxRange via GetSpellInfo(75). The manual
-- switch covers clients where the spellbook does not answer; detection, when it
-- answers past 35, wins and also ticks the switch so the tab shows the truth.
local detectedLongRange = false
local detectedAutoMax = nil
local function detectLongRange()
    detectedLongRange, detectedAutoMax = false, nil
    if type(GetSpellInfo) ~= "function" then return end
    local ok, name, rank, icon, castTime, minRange, maxRange = pcall(GetSpellInfo, 75)
    if not ok then return end
    if type(maxRange) == "number" and maxRange > 0 then
        detectedAutoMax = maxRange
        if maxRange > 35 then
            detectedLongRange = true
            if settings then settings.longRange = true end
        end
    end
end

local function effectiveSlots()
    if settings == nil then return 7 end
    if settings.longRange == true or detectedLongRange then return 7 end
    return 6
end
local function validTarget()
    local ok, valid = pcall(function()
        return UnitExists("target") and not UnitIsDeadOrGhost("target")
            and UnitCanAttack("player", "target") and true or false
    end)
    return ok and safeNormalize(valid) == true
end

-- "Y10".."Y35", "MAX" (the seventh slot), "MELEE", "DEAD" (the 5-8 yd dead zone),
-- "OOR" or nil (no valid target).
local function currentBand()
    if not validTarget() then return nil end
    local melee = spellInRange(meleeSpell)
    local auto
    if melee == nil then
        melee = itemInRange(16114)
        if melee == nil and CheckInteractDistance then
            local ok, value = pcall(CheckInteractDistance, "target", 2)
            if ok then melee = safeNormalize(value) end
        end
    elseif melee == true then
        auto = spellInRange(75)
        if auto ~= nil then melee = auto == false end
    end
    if melee == true then return "MELEE" end
    if auto == nil then auto = spellInRange(75) end
    local thirtyFive
    for i = 1, #ladder do
        local result = anyInRange(ladder[i])
        if i == #ladder then thirtyFive = result end
        if result == true then
            if auto == false and i <= 3 then return "DEAD" end
            return ladder[i][1]
        end
    end
    -- Past 35 yd: the 35 yd probe answering false proves it outright, unless Auto Shot
    -- is proven out of range. When the 35 yd probe cannot say (nil) but every shorter
    -- rung answers false, the target is past 30 yd: light the seventh slot whenever Auto
    -- Shot is not proven out of range either. On clients where the Auto Shot probe itself
    -- cannot say (nil), this is the only way the top band ever lights; a proven
    -- out-of-auto target still hides as OOR below, so a truly unreachable target is
    -- never shown all-green.
    local longMode = effectiveSlots() == 7
    if longMode then
        if thirtyFive == false and auto ~= false then return "MAX" end
        if thirtyFive ~= true and auto ~= false then
            local pastThirty = true
            for i = 1, #ladder - 1 do
                if anyInRange(ladder[i]) ~= false then pastThirty = false break end
            end
            if pastThirty then return "MAX" end
        end
    end
    if auto == true then return "Y35" end
    return "OOR"
end

----------------------------------------------------------------------------------------------
-- BIT Minimal R1: the native rail. Seven slots, nearest first, one per band rung;
-- the count semantics below are unchanged (Y10 lights one slot, MAX all seven).
-- Slot 3 is the 15-20 yd band in this ordering (the old top-to-bottom fifth
-- position); only it can read the 'bad' role for an extended Scatter Shot. The zone
-- label always names the approximate band; exact yards are never claimed.
----------------------------------------------------------------------------------------------

-- The live HUD is the scene frame itself (buildScene under UIParent); the driver is
-- the polling frame. Both stay nil while the module is off or the class is not Hunter.
local hud, driver

local band = nil
local targetSelectionChanged = true
local acquiringTarget, acquisitionTime, acquisitionBand, acquisitionSamples = false, 0, nil, 0
local preview = false
local elapsed = 0
local scatterRed, scatterExtendedObserved = false, false

local SLOT_COUNT = 7
local SAMPLE_BAND = "Y30" -- the settings sample: five of seven


local SCATTER_SLOT = 3 -- 15-20 yd in the new nearest-first ordering

-- Forward: the Scatter Shot probe below; renderScene only calls it, never reads a unit.
local scatterShotRange

local BAND_LABEL = {
    Y10 = "8-10 yd (approx.)", Y15 = "10-15 yd (approx.)", Y20 = "15-20 yd (approx.)",
    Y25 = "20-25 yd (approx.)", Y30 = "25-30 yd (approx.)", Y35 = "30-35 yd (approx.)",
    MAX = "35+ yd (approx.)", PREVIEW = "Preview (approx.)",
    MELEE = "MELEE", DEAD = "DEAD ZONE",
}

local SLOT_ROLE = {
    "distanceNear", "distanceNear", "distanceMid", "distanceMid",
    "distanceMid", "distanceFar", "distanceFar",
}

local countByBand = {
    MELEE = 0, DEAD = 0, Y10 = 1, Y15 = 2,
    Y20 = 3, Y25 = 4, Y30 = 5,
    Y35 = 6, MAX = 7, PREVIEW = 7,
}

local function slotRole(i, scatter)
    if scatter and i == SCATTER_SLOT then return "bad" end
    return SLOT_ROLE[i]
end

local function zoneRole(band)
    if band == "Y10" or band == "Y15" then return "distanceNear" end
    if band == "Y20" or band == "Y25" or band == "Y30" then return "distanceMid" end
    if band == "Y35" or band == "MAX" or band == "PREVIEW" then return "distanceFar" end
    if band == "MELEE" then return "good" end
    if band == "DEAD" then return "bad" end
    return "text"
end

-- One retained scene: a frame owning a seven-slot rail (seven one-marker
-- containers, so every slot keeps its own semantic role), a two-marker bar for
-- the bar shape, the approximate zone label, and two native status icons
-- (Dead Zone skull + melee sword, both shown only for MELEE/DEAD, never a
-- RaidTarget assignment). Only native primitives are used.
-- Pure construction: no gameplay reads, no events, no timers, no sounds.
local GLOSS_WHITE = "Interface\\Buttons\\WHITE8X8"

-- Nameplate anchor (ResourceDing pattern): the rail rides above the target's
-- own plate, where the eyes already are, instead of a fixed screen spot.
-- Forbidden plates are never touched; without a plate the saved screen
-- position is the fallback, so the HUD never strands.
local function hunterTargetPlate()
    if type(UnitExists) ~= "function" then return nil end
    local ok, exists = pcall(UnitExists, "target")
    if not ok or exists ~= true then return nil end
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return nil end
    local okPlate, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    if not okPlate or type(plate) ~= "table" then return nil end
    if type(plate.IsForbidden) == "function" then
        local okF, forbidden = pcall(plate.IsForbidden, plate)
        if not okF or forbidden then return nil end
    end
    return plate
end

local function hunterHealthBarOf(plate)
    local unitFrame = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
    local bar = unitFrame and (unitFrame.healthBar or (type(unitFrame.HealthBarsContainer) == "table"
        and unitFrame.HealthBarsContainer.healthBar)) or nil
    return type(bar) == "table" and bar or plate
end

local function reanchorHunterHud()
    if not hud or not settings then return end
    local function screenFallback()
        if hud:GetParent() ~= UIParent then hud:SetParent(UIParent) end
        hud:ClearAllPoints()
        hud:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    end
    if preview or settings.attachToPlate ~= true then
        screenFallback()
        return
    end
    local plate = hunterTargetPlate()
    if not plate then
        screenFallback()
        return
    end
    local offset = tonumber(settings.plateOffset) or -8
    if offset < -80 then offset = -80 elseif offset > 30 then offset = 30 end
    if hud:GetParent() ~= plate then hud:SetParent(plate) end
    hud:ClearAllPoints()
    hud:SetPoint("TOP", hunterHealthBarOf(plate), "BOTTOM", 0, -offset)
end

-- Blizzard-style orb gloss (hunter-local): a specular highlight over each dot,
-- like the shine on Blizzard's own power orbs. A second texture per dot holder
-- reuses the holder's own circle mask, so it stays round with no square edges.
-- The gradient API is probed (older clients fall back to a flat faint shine).
-- Pure paint: no gameplay reads, never errors when APIs are missing.
local function paintHunterGloss(frame, style, active, bandName, close)
    local glossOn = style and style.shape == "dots" and not close
    local borderPx = 0
    if style then borderPx = math.max(0, (tonumber(style.border) or 0) * (tonumber(style.scale) or 1)) end
    local opacity = (style and tonumber(style.opacity)) or 1
    local slots = frame.slots or {}
    for i = 1, #slots do
        local slot = slots[i]
        local holder = slot and slot.markers and slot.markers[1]
        local gloss = holder and holder.hunterGloss
        local slotShown = false
        if type(slot) == "table" and type(slot.IsShown) == "function" then
            local ok, shown = pcall(slot.IsShown, slot)
            slotShown = ok and shown and true or false
        elseif type(slot) == "table" then
            slotShown = true
        end
        if not glossOn or not slotShown or type(holder) ~= "table" then
            if gloss and type(gloss.Hide) == "function" then pcall(gloss.Hide, gloss) end
        else
            if not gloss and type(holder.CreateTexture) == "function" then
                local ok, tex = pcall(holder.CreateTexture, holder, nil, "OVERLAY")
                if ok and tex then
                    holder.hunterGloss = tex
                    gloss = tex
                    local mask = holder.dotFillMask
                    if mask and type(tex.AddMaskTexture) == "function" then
                        pcall(tex.AddMaskTexture, tex, mask)
                    end
                end
            end
            if gloss then
                local lit = i <= (active or 0)
                local alpha = (lit and 0.5 or 0.14) * opacity
                if type(gloss.ClearAllPoints) == "function" then pcall(gloss.ClearAllPoints, gloss) end
                if type(gloss.SetPoint) == "function" then
                    pcall(gloss.SetPoint, gloss, "TOPLEFT", holder, "TOPLEFT", borderPx, -borderPx)
                    pcall(gloss.SetPoint, gloss, "BOTTOMRIGHT", holder, "BOTTOMRIGHT", -borderPx, borderPx)
                end
                if type(gloss.SetTexture) == "function" then pcall(gloss.SetTexture, gloss, GLOSS_WHITE) end
                if type(gloss.SetGradient) == "function" then
                    pcall(gloss.SetGradient, gloss, "VERTICAL",
                        { r = 1, g = 1, b = 1, a = 0.55 }, { r = 1, g = 1, b = 1, a = 0 })
                end
                if type(gloss.SetAlpha) == "function" then pcall(gloss.SetAlpha, gloss, alpha) end
                if type(gloss.Show) == "function" then pcall(gloss.Show, gloss) end
            end
        end
    end
end

local function buildScene(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.rail = rail
    local slots = {}
    for i = 1, SLOT_COUNT do
        slots[i] = BIT.Style.CreateMarkers(rail, 1)
    end
    frame.slots = slots
    local bar = BIT.Style.CreateMarkers(frame, 2)
    bar:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, 0)
    frame.bar = bar
    local zone = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    zone:SetPoint("TOPLEFT", rail, "BOTTOMLEFT", 0, -4)
    zone:SetJustifyH("LEFT")
    frame.zone = zone
    -- Native status icons: static textures, no unit/spell/game probes.
    local deadIcon = frame:CreateTexture(nil, "OVERLAY")
    deadIcon:SetTexture(DEAD_ZONE_SKULL)
    deadIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    deadIcon:SetSize(24, 24)
    if deadIcon.SetVertexColor then deadIcon:SetVertexColor(1, 1, 1, 1) end
    deadIcon:Hide()
    frame.deadIcon = deadIcon
    local meleeIcon = frame:CreateTexture(nil, "OVERLAY")
    meleeIcon:SetTexture(MELEE_ICON)
    meleeIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    meleeIcon:SetSize(24, 24)
    if meleeIcon.SetVertexColor then meleeIcon:SetVertexColor(1, 1, 1, 1) end
    meleeIcon:Hide()
    frame.meleeIcon = meleeIcon
    frame:SetSize(238, 64)
    return frame
end

-- Guarded icon alpha: opacity 0 must make icons transparent too. Prefers
-- SetAlpha, falls back to white vertex alpha; missing API never errors.
local function setIconAlpha(icon, alpha)
    if not icon then return end
    if type(icon.SetAlpha) == "function" then
        pcall(icon.SetAlpha, icon, alpha)
    end
    if type(icon.SetVertexColor) == "function" then
        pcall(icon.SetVertexColor, icon, 1, 1, 1, alpha)
    end
end

-- Pure render of a retained scene from a resolved style, a measured band and the
-- Scatter Shot flag. No unit, range, gear, class or GUID reads here, except the
-- narrow Y25 Scatter re-check callers already pass through updateScatterFlag;
-- callers pass plain values only. Frames are never rebuilt: the same slots are
-- re-anchored and re-painted, the bar re-filled, the label re-set, icons
-- shown/hidden. Static by design: no shake, no pulse, no animation state;
-- reducedMotion changes nothing.
local function renderScene(frame, style, bandName, scatter)
    if type(frame) ~= "table" then return end
    local show = bandName ~= nil and bandName ~= "OOR"
    if not show then
        frame:Hide()
        if frame.deadIcon then frame.deadIcon:Hide() end
        if frame.meleeIcon then frame.meleeIcon:Hide() end
        return
    end
    frame:Show()
    local active = countByBand[bandName] or 0
    if bandName == "Y25" and scatter and scatterShotRange() == true then
        -- Within the 20-25 yd item rung, keep the marked slot on top until Scatter
        -- Shot itself falls out of range (approximately 21 yd).
        active = SCATTER_SLOT
    end
    local close = bandName == "MELEE" or bandName == "DEAD"
    -- Icon visibility: ONLY MELEE/DEAD, honouring the saved toggles. Band
    -- transitions hide the stale icon; Y/MAX/PREVIEW hide both.
    local showDead = bandName == "DEAD" and settings ~= nil and settings.showDeadzoneIcon ~= false
        or (bandName == "DEAD" and settings == nil)
    local showMelee = bandName == "MELEE" and settings ~= nil and settings.showMeleeIcon ~= false
        or (bandName == "MELEE" and settings == nil)
    -- OFF/pure sample has no settings table yet: show the icon for the band.
    if settings == nil then
        showDead = bandName == "DEAD"
        showMelee = bandName == "MELEE"
    end
    local iconSize = math.max(16, 24 * (style.scale or 1))
    if frame.deadIcon then
        if showDead then
            frame.deadIcon:Show()
            frame.deadIcon:SetSize(iconSize, iconSize)
            frame.deadIcon:ClearAllPoints()
            frame.deadIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        else
            frame.deadIcon:Hide()
        end
        setIconAlpha(frame.deadIcon, style.opacity or 1)
    end
    if frame.meleeIcon then
        if showMelee then
            frame.meleeIcon:Show()
            frame.meleeIcon:SetSize(iconSize, iconSize)
            frame.meleeIcon:ClearAllPoints()
            frame.meleeIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        else
            frame.meleeIcon:Hide()
        end
        setIconAlpha(frame.meleeIcon, style.opacity or 1)
    end
    if style.shape == "bar" and not close then
        frame.rail:SetShown(false)
        for i = 1, SLOT_COUNT do frame.slots[i]:SetShown(false) end
        frame.bar:SetShown(true)
        BIT.Style.RenderMarkers(frame.bar, style, active, effectiveSlots(), zoneRole(bandName))
    else
        frame.bar:SetShown(false)
        if close then
            -- MELEE and the dead zone read as role-colored text + native icon;
            -- the rail parks dimmed, so the hidden slots never keep a stale
            -- lit state across transitions.
            for i = 1, SLOT_COUNT do
                local slot = frame.slots[i]
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", frame.rail, "TOPLEFT", 0, 0)
                BIT.Style.RenderMarkers(slot, style, 0, 1, slotRole(i, scatter))
            end
            frame.rail:SetShown(false)
        elseif style.shape == "dots" then
            -- Round dots: layout from REAL painted extents (holder outer =
            -- thick + 2*border, step = outer + gap), matching Core.RenderMarkers
            -- painted bounds, so thickness12/border8/gap7 cannot overlap.
            frame.rail:SetShown(true)
            local thick = math.max(1, style.thickness * style.scale)
            local gap = math.max(0, style.gap * style.scale)
            local borderPx = math.max(0, (style.border or 0) * style.scale)
            local outer = thick + 2 * borderPx
            local step = outer + gap
            local dotTotal = effectiveSlots()
            for i = 1, SLOT_COUNT do
                local slot = frame.slots[i]
                if i <= dotTotal then
                    slot:SetShown(true)
                    slot:ClearAllPoints()
                    slot:SetPoint("TOPLEFT", frame.rail, "TOPLEFT", (i - 1) * step, 0)
                    BIT.Style.RenderMarkers(slot, style, i <= active and 1 or 0, 1, slotRole(i, scatter))
                else
                    slot:SetShown(false)
                end
            end
            frame.rail:SetSize(dotTotal * step - gap, outer)
        else
            frame.rail:SetShown(true)
            local thick = math.max(1, style.thickness * style.scale)
            local gap = math.max(0, style.gap * style.scale)
            local len = math.max(1, style.length * style.scale)
            local step = len + gap
            local segTotal = effectiveSlots()
            for i = 1, SLOT_COUNT do
                local slot = frame.slots[i]
                if i <= segTotal then
                    slot:SetShown(true)
                    slot:ClearAllPoints()
                    slot:SetPoint("TOPLEFT", frame.rail, "TOPLEFT", (i - 1) * step, 0)
                    BIT.Style.RenderMarkers(slot, style, i <= active and 1 or 0, 1, slotRole(i, scatter))
                else
                    slot:SetShown(false)
                end
            end
            frame.rail:SetSize(segTotal * step - gap, thick)
        end
    end
    paintHunterGloss(frame, style, active, bandName, close)
    frame.zone:SetText(BAND_LABEL[bandName] or "")
    -- Role-colored label for the close bands (MELEE good, DEAD bad), plain
    -- text for distance bands so the rail gradient stays the signal.
    local labelRole = "text"
    if bandName == "MELEE" then labelRole = "good"
    elseif bandName == "DEAD" then labelRole = "bad" end
    BIT.Style.ApplyText(frame.zone, style, labelRole)
    -- Re-anchor the label beside the icon for close bands, below the rail otherwise.
    frame.zone:ClearAllPoints()
    if close and (showDead or showMelee) then
        frame.zone:SetPoint("LEFT", (showDead and frame.deadIcon or frame.meleeIcon), "RIGHT", 6, 0)
    else
        frame.zone:SetPoint("TOPLEFT", frame.rail, "BOTTOMLEFT", 0, -4)
    end
    -- Frame reserves painted extents + gap and font/caption/icon bounds at
    -- min/max geometry: rail painted size (or bar/icon) plus label space.
    local railW, railH = (frame.rail:GetWidth() or 0), (frame.rail:GetHeight() or 0)
    local width
    if close then
        width = iconSize + 6 + 120
    elseif style.shape == "bar" then
        width = math.max(1, style.length * style.scale)
    else
        width = railW
    end
    local baseH = railH
    if close then baseH = math.max(railH, iconSize) end
    frame:SetSize(width, baseH + 8 + (style.fontSize or 12))
end

----------------------------------------------------------------------------------------------
-- The shared contract: capabilities and the read-only legacy fallback. Registered
-- below, before any runtime gate, so the settings own an editor and a static sample
-- for every class while the module is off.
----------------------------------------------------------------------------------------------

local CAPABILITIES = {
    roles = { "distanceNear", "distanceMid", "distanceFar", "good", "bad", "unknown", "muted", "text" },
    shapes = { "segments", "bar", "dots" },
    font = true, geometry = true, border = true, scale = true, opacity = true,
}

-- Old visual values that still mean something, mapped onto the shared style and
-- only when they differ from the old defaults. Read-only: the module store is
-- never created or written here (no BIT.Settings), anchors and gameplay keys are
-- never style, and the retired display flags map to nothing visual.
local function hunterLegacy()
    local legacy = {}
    local mods = type(BattleInfoToolDB) == "table" and BattleInfoToolDB.modules
    local s = type(mods) == "table" and mods[M.moduleName]
    if type(s) ~= "table" then return legacy end
    if type(s.scale) == "number" and s.scale ~= 1 then legacy.scale = s.scale end
    if type(s.opacity) == "number" and s.opacity ~= 1 then legacy.opacity = s.opacity end
    if type(s.chevronWidth) == "number" and s.chevronWidth ~= 1 then
        legacy.length = 14 * s.chevronWidth
    end
    if type(s.chevronHeight) == "number" and s.chevronHeight ~= 1 then
        legacy.thickness = 4 * s.chevronHeight
    end
    if s.animateDeadzone == true or s.animateMelee == true then
        legacy.reducedMotion = false
    end
    return legacy
end

-- Scatter Shot (19503): a learned spell with a base maximum of 15 yd leaves the 15-20 yd chevron
-- yellow. When its range reaches beyond 15 yd (talents, roughly 21 yd), the chevron turns red:
-- either the client says its maximum exceeds 15, or it is observed in range past the 15 yd rung.
local SCATTER_SHOT = 19503
local function scatterShotKnown()
    local known = false
    if IsPlayerSpell then
        local ok, value = pcall(IsPlayerSpell, SCATTER_SHOT)
        known = ok and safeNormalize(value) == true
    end
    if not known and IsSpellKnown then
        local ok, value = pcall(IsSpellKnown, SCATTER_SHOT)
        known = ok and safeNormalize(value) == true
    end
    return known
end

scatterShotRange = function()
    if not scatterShotKnown() then return nil end
    return spellInRange(SCATTER_SHOT)
end

local scatterMaxRange = nil
local function scatterShotMaximum()
    if scatterMaxRange then return scatterMaxRange end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, SCATTER_SHOT)
        if ok and type(info) == "table" and type(info.maxRange) == "number"
            and info.maxRange > 0 then
            scatterMaxRange = info.maxRange
            return scatterMaxRange
        end
    end
    if GetSpellInfo then
        local ok, maximum = pcall(function()
            return select(6, GetSpellInfo(SCATTER_SHOT))
        end)
        if ok and type(maximum) == "number" and maximum > 0 then
            scatterMaxRange = maximum
            return scatterMaxRange
        end
    end
    return nil
end

-- Measurement only: recompute whether the 15-20 yd slot reads the 'bad' role.
-- Live reach past the 15 yd item rung takes precedence over a base maxRange that
-- a talent may not update on this client. No frames are touched here.
local function updateScatterFlag(cur)
    if not scatterShotKnown() then
        scatterExtendedObserved, scatterRed = false, false
        return false
    end
    if (cur == "Y20" or cur == "Y25") and scatterShotRange() == true then
        scatterExtendedObserved = true
    end
    local maximum = scatterShotMaximum()
    scatterRed = scatterExtendedObserved or (maximum ~= nil and maximum > 15)
    return scatterRed and true or false
end

-- The poll: measure the band, confirm a fresh target, render the retained scene.
-- Static by design: repeated polls with unchanged answers render identically.
-- PLAYER_TARGET_CHANGED already identifies a new target; GUID values may be secret
-- inside instances and cannot be compared by addons (none is read here).
local function updateDisplay(_, dt)
    if not hud then return end
    if acquiringTarget then acquisitionTime = acquisitionTime + dt end
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    local targetChanged = targetSelectionChanged
    targetSelectionChanged = false
    if targetChanged and not preview then
        acquiringTarget, acquisitionTime = true, 0
        acquisitionBand, acquisitionSamples = nil, 0
        band = nil
        hud:Hide()
    end
    local measuredBand = preview and "PREVIEW" or currentBand()
    if acquiringTarget and not preview then
        -- Newly selected targets can briefly return stale spell/item ranges. Confirm the
        -- first reading on the next poll (about 0.1 seconds), so a previous target's stale
        -- answer can never show for the new one.
        if measuredBand == acquisitionBand and measuredBand ~= "OOR" then
            acquisitionSamples = acquisitionSamples + 1
        else
            acquisitionBand, acquisitionSamples = measuredBand, 1
        end
        if not measuredBand or measuredBand == "OOR"
            or acquisitionTime < 0.08 or acquisitionSamples < 2 then
            hud:Hide()
            return
        end
        acquiringTarget = false
    end
    band = measuredBand
    if band == nil or band == "OOR" then
        hud:Hide()
        return
    end
    local scatter = updateScatterFlag(band)
    reanchorHunterHud()
    renderScene(hud, BIT.Style.Resolve(M.moduleName, hunterLegacy), band, scatter)
end

-- The anchor: the ordinary saved offset from the screen centre. Frame scale and
-- alpha are owned by the resolved style now (geometry, marker and label alpha),
-- so the saved scale/opacity values survive as data and as the legacy fallback
-- without being applied twice.
local function position()
    if not hud then return end
    hud:ClearAllPoints()
    hud:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
end

-- Exact saved-position reset: restores the requested centre offset
-- (x=0.19970703125, y=-229.9999389648438) and re-anchors the live HUD.
-- Only the two coordinates change; scale/lock/appearance stay.
local function resetPosition()
    if not settings then return end
    settings.x, settings.y = DEFAULTS.x, DEFAULTS.y
    if hud then position() end
end
M.ResetPosition = resetPosition

local function setPreview(value)
    preview = value and true or false
    if not hud then return end
    hud:EnableMouse(preview)
    -- Poll only while a target exists or the preview is being dragged.
    driver:SetShown(preview or UnitExists("target") == true)
    if preview then
        renderScene(hud, BIT.Style.Resolve(M.moduleName, hunterLegacy), "PREVIEW", false)
        reanchorHunterHud()
        hud:Show()
    else
        band = nil
        hud:Hide()
    end
end

local tabRefresh

local function setLocked(locked)
    settings.locked = locked and true or false
    setPreview(not settings.locked)
    if tabRefresh then tabRefresh() end
end

local function start()
    hud = buildScene(UIParent)
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    hud:EnableMouse(false)
    hud:SetMovable(true)
    hud:RegisterForDrag("LeftButton")
    hud:Hide()
    hud:SetScript("OnDragStart", function(self)
        if preview then self:StartMoving() end
    end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- The client's answers are guarded: without real numbers nothing is saved, and the
        -- ordinary offset (not a scaled-in screen position) is what the next position() uses.
        -- Both axes are saved: at unequal effective scales x and y scale independently.
        -- The whole geometry read is probed, never assumed: a client without these
        -- methods (or without numbers) keeps its anchor instead of erroring.
        local ok, x, y, ux, uy, effective, parentScale = pcall(function()
            local cx, cy = self:GetCenter()
            local px, py = UIParent:GetCenter()
            return cx, cy, px, py, self:GetEffectiveScale(), UIParent:GetEffectiveScale()
        end)
        if ok and type(x) == "number" and type(y) == "number" and type(ux) == "number"
            and type(uy) == "number" and type(effective) == "number"
            and type(parentScale) == "number" and parentScale > 0 then
            local scale = effective / parentScale
            settings.x, settings.y = (x * scale) - ux, (y * scale) - uy
        end
        position()
    end)

    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", updateDisplay)
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            -- Hide the previous target immediately, before the next range poll.
            hud:Hide()
            targetSelectionChanged = true
            acquiringTarget, acquisitionTime = true, 0
            acquisitionBand, acquisitionSamples = nil, 0
            band = nil
            elapsed = 0.1
            driver:SetShown(preview or UnitExists("target") == true)
        elseif band and band ~= "OOR" and not preview then
            -- Plates recycle between units: re-seat the rail on the new plate.
            reanchorHunterHud()
        end
    end)

    position()
    setPreview(settings.locked == false)
    -- Live style subscription: appearance edits re-render the real HUD even
    -- while the settings tab is closed. Pure re-render of the retained scene
    -- from the cached band (no new unit/target reads beyond the Y25
    -- Scatter re-check the poll already performs).
    if BIT.Style and BIT.Style.Subscribe then
        pcall(BIT.Style.Subscribe, M.moduleName, function()
            if hud and band and band ~= "OOR" then
                local ok = pcall(renderScene, hud,
                    BIT.Style.Resolve(M.moduleName, hunterLegacy), band, scatterRed)
                if not ok then end
            elseif hud and preview then
                pcall(renderScene, hud,
                    BIT.Style.Resolve(M.moduleName, hunterLegacy), "PREVIEW", false)
            end
        end)
    end
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, 16114)
        for _, rung in ipairs(ladder) do
            for j = 2, #rung do pcall(C_Item.RequestLoadItemDataByID, rung[j]) end
        end
    end
end

-- Start: the module's own switch (the tab's Enable box), the class, and the settings
----------------------------------------------------------------------------------------------

local function clamp(value, default, lo, hi)
    if type(value) ~= "number" then return default end
    return math.max(lo, math.min(hi, value))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("SPELLS_CHANGED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "SPELLS_CHANGED" then
        wipe(spellNames)
        scatterMaxRange, scatterExtendedObserved, scatterRed = nil, false, false
        detectLongRange()
        return
    end
    if name ~= BIT.name then return end
    self:UnregisterEvent("ADDON_LOADED")
    -- Narrow one-time appearance migration runs before any gate, OFF-safe:
    -- no frames, units, timers or sounds here.
    pcall(migrateHunterShape)
    if not BIT.ShouldRun("HunterRangeFinder") then
        -- Switched off in /bit: no frames, no events, nothing polled.
        self:UnregisterEvent("SPELLS_CHANGED")
        return
    end
    -- 0.9.15 scheme migration (once): the 0.9.14 gap meant 0..40 above the bar,
    -- the rogue scheme means -80..30 with negative above. Negate once, but only a
    -- value that was actually saved under the old scheme (fresh stores keep -8).
    local rawMods = type(BattleInfoToolDB) == "table" and BattleInfoToolDB.modules
    local rawHunter = type(rawMods) == "table" and rawMods["HunterRangeFinder"]
    local hadOldOffset = type(rawHunter) == "table" and type(rawHunter.plateOffset) == "number"
        and rawHunter.plateScheme ~= 2
    settings = BIT.Settings("HunterRangeFinder", DEFAULTS)
    M.settings = settings
    if hadOldOffset then settings.plateOffset = -(settings.plateOffset) end
    settings.plateScheme = 2
    if type(settings.plateOffset) ~= "number" then settings.plateOffset = DEFAULTS.plateOffset
    elseif settings.plateOffset < -80 then settings.plateOffset = -80
    elseif settings.plateOffset > 30 then settings.plateOffset = 30 end
    detectLongRange()
    -- Values out of the sliders' bounds (or of the wrong type) fall back to the defaults.
    settings.scale = clamp(settings.scale, DEFAULTS.scale, 0.5, 3)
    settings.opacity = clamp(settings.opacity, DEFAULTS.opacity, 0.1, 1)
    settings.chevronHeight = clamp(settings.chevronHeight, DEFAULTS.chevronHeight, 0.5, 1.5)
    settings.chevronWidth = clamp(settings.chevronWidth, DEFAULTS.chevronWidth, 0.5, 1.5)
    if type(settings.x) ~= "number" then settings.x = DEFAULTS.x end
    if type(settings.y) ~= "number" then settings.y = DEFAULTS.y end
    local _, class = UnitClass("player")
    if class == "HUNTER" then
        start()
    else
        -- The rail is a hunter's; any other class gets no display and no events.
        self:UnregisterEvent("SPELLS_CHANGED")
    end
end)

----------------------------------------------------------------------------------------------
-- The settings tab
----------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------
-- The settings tab: the shared appearance editor plus a real static sample on ANY
-- class, even without a target. Native Dead Zone skull + melee sword toggles and
-- an exact position reset sit beside the lock control; retired chevron/animation
-- keys stay in the store for data preservation but no control writes them back
-- except the two icon flags, which genuinely show/hide the native icons.
----------------------------------------------------------------------------------------------

local function build(parent)
    local UI = BIT.UI
    local _, class = UnitClass("player")
    local isHunter = class == "HUNTER"
    local y = -6
    if not isHunter then
        local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        note:SetPoint("TOPLEFT", 12, y)
        note:SetPoint("RIGHT", -12, 0)
        note:SetJustifyH("LEFT")
        note:SetText("The native range rail appears only on a Hunter. On another class this "
            .. "module keeps its settings here, ready for the hunter alt; the appearance "
            .. "editor and the sample below need no hunter and no target.")
        parent.hunterNote = note
        y = y - 44
    end

    local rows = {}
    local function changed()
        for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
    end
    -- Forward: the retained ON sample, filled below; refreshAll re-renders it
    -- plus the live HUD from the cached band (no new gameplay reads).
    local sample
    local function refreshAll()
        local style = BIT.Style.Resolve(M.moduleName, hunterLegacy)
        if sample then
            renderScene(sample, style, SAMPLE_BAND, false)
        end
        if hud then
            local b = preview and "PREVIEW" or band
            if b and b ~= "OOR" then
                renderScene(hud, style, b, scatterRed)
            end
        end
        changed()
    end

    if isHunter then
        parent.lockButton = UI.Button(parent, settings.locked and "Unlock and move" or "Lock position",
            180, function()
                setLocked(not settings.locked)
            end)
        parent.lockButton:SetPoint("TOPLEFT", 12, y)
        local status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("LEFT", parent.lockButton, "RIGHT", 10, 0)
        status:SetText("Unlock, drag the rail, then lock to save its position.")
        y = y - 34
        parent.resetPosition = UI.Button(parent, "Reset position", 180, function()
            resetPosition()
            refreshAll()
            if tabRefresh then tabRefresh() end
        end)
        parent.resetPosition:SetPoint("TOPLEFT", 12, y)
        local rst = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rst:SetPoint("LEFT", parent.resetPosition, "RIGHT", 10, 0)
        rst:SetText("Back to the requested centre offset.")
        y = y - 34
        parent.attach = UI.Check(parent, "Attach to target nameplate",
            function() return settings.attachToPlate ~= false end,
            function(v)
                settings.attachToPlate = v and true or false
                if hud and band and band ~= "OOR" then reanchorHunterHud() end
                if tabRefresh then tabRefresh() end
            end,
            "The rail rides above the target's nameplate, like the ResourceDing dots. Unchecked keeps the draggable screen position.")
        parent.attach:SetPoint("TOPLEFT", 12, y)
        y = y - 30
        rows[#rows + 1] = parent.attach
        parent.plateOffset = UI.Slider(parent, "Offset from the health bar (- = above)", -80, 30, 1,
            function() return settings.plateOffset or -8 end,
            function(v)
                if type(v) ~= "number" then v = DEFAULTS.plateOffset end
                if v < -80 then v = -80 elseif v > 30 then v = 30 end
                settings.plateOffset = v
                if hud and band and band ~= "OOR" then reanchorHunterHud() end
            end)
        parent.plateOffset:SetPoint("TOPLEFT", 12, y)
        y = y - 52
        rows[#rows + 1] = parent.plateOffset
        parent.longRange = UI.Check(parent, "Extended range past 35 yd (Hawk Eye)",
            function() return settings.longRange == true or detectedLongRange end,
            function(v)
                settings.longRange = v and true or false
                refreshAll()
                if tabRefresh then tabRefresh() end
            end,
            "Seven dots instead of six. Auto-detected from Auto Shot's reach when the spellbook answers; tick manually otherwise.")
        parent.longRange:SetPoint("TOPLEFT", 12, y)
        y = y - 30
        rows[#rows + 1] = parent.longRange
        parent.deadIcon = UI.Check(parent, "Show Dead Zone skull (native)",
            function() return settings.showDeadzoneIcon ~= false end,
            function(v)
                settings.showDeadzoneIcon = v and true or false
                refreshAll()
            end,
            "Native Blizzard raid skull for the 5-8 yd dead zone. Unchecked hides it.")
        parent.deadIcon:SetPoint("TOPLEFT", 12, y)
        y = y - 30
        rows[#rows + 1] = parent.deadIcon
        parent.meleeIcon = UI.Check(parent, "Show Melee mark (native sword)",
            function() return settings.showMeleeIcon ~= false end,
            function(v)
                settings.showMeleeIcon = v and true or false
                refreshAll()
            end,
            "Native Blizzard sword glyph for melee reach. Unchecked hides it.")
        parent.meleeIcon:SetPoint("TOPLEFT", 12, y)
        y = y - 30
        rows[#rows + 1] = parent.meleeIcon
    end

    -- The shared editor. Its own subscription refreshes the panel; the refresh
    -- callback below re-renders the module's retained sample (plus the live HUD
    -- when it exists) with the same style.
    local function refreshSample()
        refreshAll()
    end
    local editor = UI.Appearance(parent, M.moduleName, CAPABILITIES, refreshSample, hunterLegacy)
    editor:SetPoint("TOPLEFT", 12, y)
    rows[#rows + 1] = editor
    parent.hunterEditor = editor
    y = y - editor:GetHeight() - 12

    -- The retained static sample: built once, re-rendered on every style change,
    -- never unlocked or moved. Pure fictitious data, no gameplay reads.
    sample = buildScene(parent)
    sample:SetPoint("TOPLEFT", editor, "BOTTOMLEFT", 0, -12)
    parent.hunterSample = sample
    renderScene(sample, BIT.Style.Resolve(M.moduleName, hunterLegacy), SAMPLE_BAND, false)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, y - sample:GetHeight() - 12)
    hint:SetPoint("RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("The rail rides above the target's nameplate while a living hostile target is "
        .. "selected (or floats at its saved screen spot when plates are off). The bands are approximate probes: 8-10, 10-15, 15-20, 20-25, 25-30, 30-35, "
        .. "and beyond 35 yd to Auto Shot's maximum. /bit hunterprobe prints what the client "
        .. "answers for the probes.")

    tabRefresh = function()
        if parent.lockButton then
            parent.lockButton:SetText(settings.locked and "Unlock and move" or "Lock position")
        end
        changed()
    end
end

----------------------------------------------------------------------------------------------
-- The pure OFF-page seam: a static fictitious scene plus its pure renderer.
-- Registered above the runtime gate, so OFF settings own an editor and a sample
-- for every class with no frames, events or polling from the module itself.
----------------------------------------------------------------------------------------------

local function buildPreview(parent)
    return buildScene(parent)
end

local function previewRender(scene, style)
    if type(scene) ~= "table" then return end
    renderScene(scene, style, SAMPLE_BAND, false)
end

----------------------------------------------------------------------------------------------
BIT.RegisterTab("HunterRangeFinder", {
    title = "Hunter range",
    summary = "Seven native markers tell a hunter the approximate range, from 8-10 yd to past 35 yd.",
    width = 700, height = 980,
    capabilities = CAPABILITIES,
    legacy = hunterLegacy,
    buildPreview = buildPreview,
    previewRender = previewRender,
    build = function(parent) build(parent) end,
})
BIT.tabWords.hunter = "HunterRangeFinder"

----------------------------------------------------------------------------------------------
-- The probe: what the client answers, in one line. Secrets are named, never stringified.
-- The raw answers are read here (not the normalized ones), so the readout shows exactly what
-- the client returned: nil, true/false, an ordinary number, or "secret".
----------------------------------------------------------------------------------------------

local function rawSpellInRange(id)
    if not id then return nil end
    local name = spellName(id)
    if name and IsSpellInRange then
        local ok, value = pcall(IsSpellInRange, name, "target")
        if ok and value ~= nil then return value end
    end
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, value = pcall(C_Spell.IsSpellInRange, id, "target")
        if ok then return value end
    end
    return nil
end

local function rawItemInRange(id)
    if C_Item and C_Item.IsItemInRange then
        local ok, value = pcall(C_Item.IsItemInRange, id, "target")
        if ok then return value end
    elseif IsItemInRange then
        local ok, value = pcall(IsItemInRange, id, "target")
        if ok then return value end
    end
    return nil
end

local function probeValue(value)
    if value == nil then return "nil" end
    if isSecret(value) then return "secret" end
    if type(value) == "boolean" or type(value) == "number" then return tostring(value) end
    return "unknown"
end

function M.Probe()
    local message = "35 yd item 18904=" .. probeValue(rawItemInRange(18904))
        .. ", Auto Shot=" .. probeValue(rawSpellInRange(75))
        .. ", AutoMax=" .. tostring(detectedAutoMax or "unknown")
        .. ", Scatter Shot=" .. probeValue(rawSpellInRange(SCATTER_SHOT))
        .. ", band=" .. tostring(currentBand() or "none")
    BIT.Say(message)
    return message
end
BIT.RegisterCommand("hunterprobe", function() M.Probe() end)

----------------------------------------------------------------------------------------------
-- For the tests.
----------------------------------------------------------------------------------------------

function M.CurrentBand() return currentBand() end
M._hud = function() return hud end
M._driver = function() return driver end
M._loader = function() return loader end
M._settings = function() return settings end