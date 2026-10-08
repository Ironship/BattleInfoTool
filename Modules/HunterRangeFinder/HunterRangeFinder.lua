-- UsefulPlatesAndTooltips module HunterRangeFinder: the hunter's approximate range in native markers.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- The hunter's range ladder in seven stacked chevrons, fully inside UsefulPlatesAndTooltips:
--   * the settings live in one BIT.Settings("HunterRangeFinder") store, built into the module's
--     tab (/upt hunter), instead of a standalone store with a window and slash commands of its own;
--   * the module starts a HUD only for a Hunter with the module switched on; any other class (or
--     a switched-off module) creates no frames, events or polling, and the tab explains that.
-- /upt hunterprobe prints what the client answers, for diagnostics.
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
    if type(UsefulPlatesAndTooltipsDB) ~= "table" then return end
    local mods = UsefulPlatesAndTooltipsDB.modules
    if type(mods) ~= "table" then return end
    local a = UsefulPlatesAndTooltipsDB.appearance
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

-- Finite numbers only: NaN passes every </> comparison, so clamps alone cannot
-- catch a corrupted saved value before it reaches SetPoint/SetSize.
local function finiteNum(v, default)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return default end
    return v
end

local spellNames = {}
local function spellName(id)
    if not id then return nil end
    if spellNames[id] then return spellNames[id] end
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and not isSecret(info) and type(info) == "table" and type(info.name) == "string" then name = info.name end
        if ok and type(info) == "string" then name = info end
    end
    if not name and GetSpellInfo then
        local ok, info = pcall(GetSpellInfo, id)
        if ok then name = info end
    end
    -- A secret name is never cached, compared or printed.
    if type(name) == "string" and not isSecret(name) then spellNames[id] = name; return name end
    return nil
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
    if isSecret(value) then return nil end
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
    if not ok or isSecret(maxRange) then return end
    if type(maxRange) == "number" and maxRange > 0 then
        detectedAutoMax = maxRange
        -- A conclusive answer syncs the switch both ways (taking Hawk Eye
        -- respecs it back down); silence keeps a manual tick. The tab getter
        -- shows the detected truth either way.
        local long = maxRange > 35
        detectedLongRange = long
        if settings then settings.longRange = long end
    end
end

local function effectiveSlots()
    if settings == nil then return 6 end
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

-- Cheap guarded target check for driver visibility (no dead/attack probing).
local function hasTarget()
    if type(UnitExists) ~= "function" then return false end
    local ok, exists = pcall(UnitExists, "target")
    return ok and not isSecret(exists) and exists == true
end

-- "Y10".."Y35", "MAX" (the seventh slot), "MELEE", "DEAD" (the 5-8 yd dead zone),
-- "OOR" or nil (no valid target).
local function currentBand()
    if not validTarget() then return nil end
    local melee = spellInRange(meleeSpell)
    local auto
    if melee == nil then
        melee = itemInRange(16114)
    elseif melee == true then
        auto = spellInRange(75)
        if auto ~= nil then melee = auto == false end
    end
    if melee == true then return "MELEE" end
    if auto == nil then auto = spellInRange(75) end
    local thirtyFive
    local shorterFalse = true
    for i = 1, #ladder do
        local result = anyInRange(ladder[i])
        if i == #ladder then thirtyFive = result
        elseif result ~= false then shorterFalse = false end
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
        if thirtyFive ~= true and auto ~= false and shorterFalse then return "MAX" end
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
function M.OwnsNameplate(plate)
    return hud ~= nil and hud:IsShown() and hud:GetParent() == plate
end

local band = nil
-- Last rendered state: the poll skips a full relayout when nothing changed.
-- Style edits re-render directly through Subscribe/refreshAll, never the poll.
local lastRenderedBand, lastRenderedScatter, lastRenderedScatterRange = nil, nil, nil
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
-- Hoisted gradient stops: no per-slot tables on the render path.
local GLOSS_TOP = { r = 1, g = 1, b = 1, a = 0.55 }
local GLOSS_BOTTOM = { r = 1, g = 1, b = 1, a = 0 }

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
    -- The forbidden check itself can throw on a forbidden frame: probe everything.
    local okF, forbidden = pcall(function() return plate.IsForbidden and plate:IsForbidden() end)
    if not okF or forbidden or isSecret(forbidden) then return nil end
    return plate
end

local function hunterHealthBarOf(plate)
    local unitFrame = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
    local bar = unitFrame and (unitFrame.healthBar or (type(unitFrame.HealthBarsContainer) == "table"
        and unitFrame.HealthBarsContainer.healthBar)) or nil
    return type(bar) == "table" and bar or plate
end

-- Last anchor seat: SetParent/SetPoint only move on change, never every poll.
local reanchorKey, reanchorOffset = nil, nil

local function reanchorHunterHud()
    if not hud or not settings then return end
    local function screenFallback()
        if reanchorKey ~= "screen" then
            if hud:GetParent() ~= UIParent then hud:SetParent(UIParent) end
            hud:ClearAllPoints()
            hud:SetPoint("CENTER", UIParent, "CENTER", finiteNum(settings.x, DEFAULTS.x), finiteNum(settings.y, DEFAULTS.y))
            reanchorKey = "screen"
        end
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
    local offset = finiteNum(tonumber(settings.plateOffset), -8)
    if offset < -80 then offset = -80 elseif offset > 30 then offset = 30 end
    if reanchorKey ~= plate or reanchorOffset ~= offset then
        if hud:GetParent() ~= plate then hud:SetParent(plate) end
        hud:ClearAllPoints()
        hud:SetPoint("TOP", hunterHealthBarOf(plate), "BOTTOM", 0, -offset)
        reanchorKey, reanchorOffset = plate, offset
    end
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
                    pcall(gloss.SetGradient, gloss, "VERTICAL", GLOSS_TOP, GLOSS_BOTTOM)
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
    width = 500, -- the editor lives in the settings tab's right column (see the tab below)
}

-- Old visual values that still mean something, mapped onto the shared style and
-- only when they differ from the old defaults. Read-only: the module store is
-- never created or written here (no BIT.Settings), anchors and gameplay keys are
-- never style, and the retired display flags map to nothing visual.
local function hunterLegacy()
    local legacy = {}
    local mods = type(UsefulPlatesAndTooltipsDB) == "table" and UsefulPlatesAndTooltipsDB.modules
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
        if ok and not isSecret(info) and type(info) == "table" and not isSecret(info.maxRange) and type(info.maxRange) == "number"
            and info.maxRange > 0 then
            scatterMaxRange = info.maxRange
            return scatterMaxRange
        end
    end
    if GetSpellInfo then
        local ok, maximum = pcall(function()
            return select(6, GetSpellInfo(SCATTER_SHOT))
        end)
        if ok and not isSecret(maximum) and type(maximum) == "number" and maximum > 0 then
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
    if (cur == "Y20" or cur == "Y25") and anyInRange(ladder[2]) == false
        and scatterShotRange() == true then
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
        -- Hiding clears the drawn-band cache, so the next reading of the same band shows again.
        lastRenderedBand, lastRenderedScatter = nil, nil
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
            lastRenderedBand, lastRenderedScatter = nil, nil
            hud:Hide()
            return
        end
        acquiringTarget = false
    end
    band = measuredBand
    if band == nil or band == "OOR" then
        lastRenderedBand, lastRenderedScatter = nil, nil
        hud:Hide()
        return
    end
    local scatter = updateScatterFlag(band)
    reanchorHunterHud()
    local scatterRange = band == "Y25" and scatter and scatterShotRange() == true
    if band == lastRenderedBand and scatter == lastRenderedScatter
        and scatterRange == lastRenderedScatterRange then return end
    lastRenderedBand, lastRenderedScatter, lastRenderedScatterRange = band, scatter, scatterRange
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
    -- Forget the current anchor so an attached rail is re-seated by the attach setting, not left on the screen spot.
    reanchorKey, reanchorOffset = nil, nil
    if hud then
        position()
        reanchorHunterHud()
    end
end
M.ResetPosition = resetPosition

local function setPreview(value)
    preview = value and true or false
    if not hud then return end
    hud:EnableMouse(preview)
    -- Poll only while a target exists or the preview is being dragged.
    driver:SetShown(preview or hasTarget())
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
            driver:SetShown(preview or hasTarget())
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

local function prepareHunterSettings()
  local rawMods = type(UsefulPlatesAndTooltipsDB) == "table" and UsefulPlatesAndTooltipsDB.modules
  local rawHunter = type(rawMods) == "table" and rawMods["HunterRangeFinder"]
  local hadOldOffset = type(rawHunter) == "table" and type(rawHunter.plateOffset) == "number"
    and finiteNum(rawHunter.plateOffset, nil) ~= nil
    and rawHunter.plateScheme ~= 2
  settings = BIT.Settings("HunterRangeFinder", DEFAULTS)
  M.settings = settings
  if hadOldOffset then settings.plateOffset = -(tonumber(settings.plateOffset) or 0) end
  settings.plateScheme = 2
  settings.plateOffset = finiteNum(tonumber(settings.plateOffset), DEFAULTS.plateOffset)
  if settings.plateOffset < -80 then settings.plateOffset = -80
  elseif settings.plateOffset > 30 then settings.plateOffset = 30 end
  settings.scale = clamp(settings.scale, DEFAULTS.scale, 0.5, 3)
  settings.opacity = clamp(settings.opacity, DEFAULTS.opacity, 0.1, 1)
  settings.chevronHeight = clamp(settings.chevronHeight, DEFAULTS.chevronHeight, 0.5, 1.5)
  settings.chevronWidth = clamp(settings.chevronWidth, DEFAULTS.chevronWidth, 0.5, 1.5)
  settings.x = finiteNum(settings.x, DEFAULTS.x)
  settings.y = finiteNum(settings.y, DEFAULTS.y)
end
if BIT.RegisterWaker then BIT.RegisterWaker("HunterRangeFinder", prepareHunterSettings) end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("SPELLS_CHANGED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "SPELLS_CHANGED" then
        wipe(spellNames)
        scatterMaxRange, scatterExtendedObserved, scatterRed = nil, false, false
        detectLongRange()
        lastRenderedBand, lastRenderedScatter, lastRenderedScatterRange = nil, nil, nil
        return
    end
    if name ~= BIT.name then return end
    self:UnregisterEvent("ADDON_LOADED")
    -- Narrow one-time appearance migration runs before any gate, OFF-safe:
    -- no frames, units, timers or sounds here.
    pcall(migrateHunterShape)
    if not BIT.ShouldRun("HunterRangeFinder") then
        -- Switched off in /upt: no frames, no events, nothing polled.
        self:UnregisterEvent("SPELLS_CHANGED")
        return
    end
    prepareHunterSettings()
    detectLongRange()
    local _, class = UnitClass("player")
    if class == "HUNTER" then
        start()
    else
        -- The rail is a hunter's; any other class gets no display and no events.
        self:UnregisterEvent("SPELLS_CHANGED")
    end
end)

----------------------------------------------------------------------------------------------
-- The settings tab: a live preview on the left, tabbed settings on the right and the rail's
-- style presets in the strip above both, laid out like Modules/DoTInfo/Options.lua. The
-- preview draws the rail through the very same buildScene/renderScene as the live HUD, on a
-- mock enemy nameplate with its health bar underneath, and the TRY IT switch walks the mock
-- target through every band on demand. Retired chevron/animation keys stay in the store for
-- data preservation; only the two native icon flags have controls of their own.
----------------------------------------------------------------------------------------------

local WINDOW_WIDTH, WINDOW_HEIGHT = 840, 500
local PREVIEW_WIDTH = 290
local COL_HEIGHT = 440 -- both columns fit the window's viewport; only the Appearance tab scrolls
local ROW_HEIGHT = 26
local SETTINGS_LAYOUT = { label = 170, control = 200 }
local PREVIEW_LAYOUT = { label = 86, control = 146 }
local DISABLED_ALPHA = 0.35
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- The TRY IT switch: every band the rail can show, nearest first (the order the dots light).
local BAND_ORDER = { "Y10", "Y15", "Y20", "Y25", "Y30", "Y35", "MAX", "MELEE", "DEAD" }
local BAND_SWITCH_TEXT = {
    Y10 = "Y10  8-10 yd", Y15 = "Y15  10-15 yd", Y20 = "Y20  15-20 yd",
    Y25 = "Y25  20-25 yd", Y30 = "Y30  25-30 yd", Y35 = "Y35  30-35 yd",
    MAX = "MAX  35+ yd (seventh dot)", MELEE = "MELEE  Wing Clip's reach", DEAD = "DEAD  5-8 yd dead zone",
}
local previewBand = SAMPLE_BAND
local previewBar -- the mock health bar the preview rail is seated on

-- Rail style presets: shape, thickness, border, gap and length, written to this module's
-- appearance through the shared style store, so the Appearance tab and the live HUD follow at
-- once. Every gameplay setting is left alone.
local PRESETS = {
    { id = "minimal", label = "Minimal",
        values = { shape = "dots", thickness = 10, border = 0, gap = 6, length = 10 } },
    { id = "classic", label = "Classic",
        values = { shape = "segments", thickness = 8, border = 1, gap = 3, length = 14 } },
    { id = "juicy", label = "Juicy",
        values = { shape = "dots", thickness = 18, border = 3, gap = 2, length = 12 } },
}

local area -- the right-hand settings area the tabs live in
local sample -- the retained live-preview scene, built inside build()
local rows = {}
local tabs, activeTab = {}, nil

local function db() return settings end

local function refreshControls()
    for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
end

-- Seat the preview rail on the mock health bar with the saved plate offset: the same "-offset"
-- sign the live anchor uses, so a negative value (above) lifts the rail off the bar.
local function seatPreviewRail()
    if not sample or not previewBar then return end
    local offset = finiteNum(tonumber(settings and settings.plateOffset), DEFAULTS.plateOffset)
    if offset < -80 then offset = -80 elseif offset > 30 then offset = 30 end
    sample:ClearAllPoints()
    sample:SetPoint("TOP", previewBar, "BOTTOM", 0, -offset)
end

-- The retained preview, re-rendered from the resolved style and the TRY IT band. Pure:
-- fictitious data only, never a live probe.
local function renderPreview()
    if not sample then return end
    seatPreviewRail()
    renderScene(sample, BIT.Style.Resolve(M.moduleName, hunterLegacy), previewBand, false)
end

-- Style edits, preset clicks and settings changes all land here: the preview first, then the
-- live HUD from its cached band, then every row's own refresh.
local function refreshAll()
    renderPreview()
    if hud then
        local style = BIT.Style.Resolve(M.moduleName, hunterLegacy)
        local b = preview and "PREVIEW" or band
        if b and b ~= "OOR" then
            renderScene(hud, style, b, scatterRed)
        end
    end
    refreshControls()
end

local plateClashLine

local function refreshPlateClash()
    if plateClashLine and BIT.Plate and type(BIT.Plate.ClashText) == "function" then
        plateClashLine:SetText(BIT.Plate.ClashText())
    end
end

local function changed()
    if hud then reanchorHunterHud() end
    refreshAll()
    refreshPlateClash()
end

local function bandIndex(name)
    for i = 1, #BAND_ORDER do
        if BAND_ORDER[i] == name then return i end
    end
end

local function bandText(name) return BAND_SWITCH_TEXT[name] or name end

local function setPreviewBand(name)
    if not bandIndex(name) then return end
    previewBand = name
    renderPreview()
    refreshControls()
end

----------------------------------------------------------------------------------------------
-- Widgets (Modules/DoTInfo/Options.lua): one labelled row per setting, with a tooltip and
-- greyed-out dependents; every row refreshes itself after any change.
----------------------------------------------------------------------------------------------

local function setBackdrop(frame, shade, alpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(shade, shade, shade, alpha or 1)
    frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

local function pushButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function makeRow(parent, labelText, opts)
    opts = opts or {}
    local layout = opts.layout or SETTINGS_LAYOUT
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(layout.label + layout.control + 50, ROW_HEIGHT)
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
        local enabled = not self.enabledIf or self.enabledIf(db())
        self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
        widget:EnableMouse(enabled)
        if widget.EnableMouseWheel then widget:EnableMouseWheel(enabled) end
    end
    rows[#rows + 1] = row
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
        db()[key] = self:GetChecked() and true or false
        changed()
    end)
    function row:Refresh()
        local v = db()[key]
        if key == "longRange" then v = v or detectedLongRange end
        box:SetChecked(v and true or false)
        self:ApplyEnabled(box)
    end
    row.widget = box
    return row
end

-- get/set work on any value: a saved setting or the preview's own band index.
local function sliderRow(parent, labelText, min, max, step, get, set, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(row.layout.control - 44, 18)
    slider:SetPoint("LEFT", row, "LEFT", row.layout.label + 2, 0)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.3, 0.3, 0.32, 1)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(18, 24)
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    local suffix = opts.suffix or ""
    local function label(v)
        if opts.format then return opts.format(v) end
        return tostring(v) .. suffix
    end
    local updating = false
    slider:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(label(value))
        set(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
    function row:Refresh()
        updating = true
        local value = get()
        slider:SetValue(value)
        valueText:SetText(label(math.floor(value / step + 0.5) * step))
        updating = false
        self:ApplyEnabled(slider)
    end
    row.slider = slider
    return row
end

local function slider(parent, key, labelText, min, max, step, opts)
    opts = opts or {}
    return sliderRow(parent, labelText, min, max, step,
        function() return db()[key] end,
        function(value)
            db()[key] = value
            changed()
        end, opts)
end

local function actionRow(parent, labelText, buttonText, onClick, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local button = pushButton(row, type(buttonText) == "function" and buttonText() or buttonText, 110, onClick)
    button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    function row:Refresh()
        if type(buttonText) == "function" then button:SetText(buttonText()) end
        self:ApplyEnabled(button)
    end
    row.widget = button
    return row
end

-- A read-only row whose value text refreshes with the rest (what the client answered).
local function infoRow(parent, labelText, getValue, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    function row:Refresh()
        text:SetText(getValue())
        self:ApplyEnabled(self)
    end
    return row
end

----------------------------------------------------------------------------------------------
-- Tabs (Modules/DoTInfo/Options.lua): one content area per tab, each remembering its setting
-- keys so "Reset this tab" can put them back. Every tab scrolls: the shared appearance editor
-- is taller than the area, and a scroll each keeps the left preview still.
----------------------------------------------------------------------------------------------

local function selectTab(tab)
    activeTab = tab
    for _, other in ipairs(tabs) do
        local selected = other == tab
        other.content:SetShown(selected)
        other.button.text:SetTextColor(selected and 1 or 0.6, selected and 0.82 or 0.6, selected and 0 or 0.6)
        other.button.underline:SetShown(selected)
    end
end

local function addTab(name)
    local tab = { name = name, keys = {}, y = 0 }
    local content = CreateFrame("ScrollFrame", nil, area)
    content:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -40)
    content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 40)
    content:EnableMouseWheel(true)
    local inner = CreateFrame("Frame", nil, content)
    inner:SetWidth((area:GetWidth() or 500) - 16)
    content:SetScrollChild(inner)
    content:SetScript("OnMouseWheel", function(_, delta)
        local maxScroll = math.max(0, (inner:GetHeight() or 0) - (content:GetHeight() or 0))
        local at = (content:GetVerticalScroll() or 0) - delta * 24
        content:SetVerticalScroll(math.min(math.max(at, 0), maxScroll))
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

    local function place(row, key, height)
        row:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -tab.y)
        tab.y = tab.y + (height or ROW_HEIGHT)
        if key then tab.keys[#tab.keys + 1] = key end
        return row
    end
    function tab:checkbox(key, ...) return place(checkbox(self.inner, key, ...), key) end
    function tab:slider(key, ...) return place(slider(self.inner, key, ...), key) end
    function tab:action(...) return place(actionRow(self.inner, ...)) end
    function tab:info(...) return place(infoRow(self.inner, ...)) end
    function tab:custom(row, key, height) return place(row, key, height) end
    function tab:note(text)
        local line = self.inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        line:SetPoint("TOPLEFT", self.inner, "TOPLEFT", 0, -self.y)
        line:SetPoint("RIGHT", self.inner, "RIGHT", -4, 0)
        line:SetJustifyH("LEFT")
        line:SetText(text)
        place(line, nil, 46)
        return line
    end
    function tab:gap(height) self.y = self.y + (height or 8) end
    function tab:finish() self.inner:SetHeight(math.max(self.y + 12, 1)) end

    tabs[#tabs + 1] = tab
    return tab
end

local function resetTab(tab)
    if not tab then return end
    if tab.reset then
        tab.reset()
    else
        for _, key in ipairs(tab.keys) do db()[key] = DEFAULTS[key] end
    end
    changed()
end

local function applyPreset(preset)
    for key, value in pairs(preset.values) do
        if BIT.Style and BIT.Style.Set then
            BIT.Style.Set(M.moduleName, key, value)
        end
    end
    changed()
end

local function buildTabs(parent, isHunter)
    local hunterOnly = function() return isHunter end

    local display = addTab("Display")
    parent.lockButton = display:action("Position",
        function() return settings.locked and "Unlock and move" or "Lock position" end,
        function() setLocked(not settings.locked) end,
        { enabledIf = hunterOnly,
            tooltip = "Unlock, drag the rail to a screen spot of your own, then lock to save its position." })
    parent.resetPosition = display:action("Dragged position", "Reset position", function()
        resetPosition()
        refreshAll()
    end, { enabledIf = hunterOnly, tooltip = "Back to the requested centre offset." })
    parent.attach = display:checkbox("attachToPlate", "Attach to target nameplate",
        { enabledIf = hunterOnly,
            tooltip = "The rail rides above the target's nameplate, like the ResourceDing dots. "
                .. "Unchecked keeps the draggable screen position." })
    parent.plateOffset = display:slider("plateOffset", "Offset from the health bar (- = above)", -80, 30, 1,
        { enabledIf = function(s) return isHunter and s.attachToPlate ~= false end,
            tooltip = "How far the rail sits from the plate's health bar. The same seat as the combo dots: top of the row, -offset under the bar." })
    plateClashLine = display:note("Nameplate lanes")
    refreshPlateClash()
    display:gap()
    parent.deadIcon = display:checkbox("showDeadzoneIcon", "Show Dead Zone skull (native)",
        { tooltip = "Native Blizzard raid skull for the 5-8 yd dead zone. Unchecked hides it." })
    parent.meleeIcon = display:checkbox("showMeleeIcon", "Show Melee mark (native sword)",
        { tooltip = "Native Blizzard sword glyph for melee reach. Unchecked hides it." })
    display.reset = function()
        for _, key in ipairs(display.keys) do db()[key] = DEFAULTS[key] end
        setLocked(DEFAULTS.locked)
    end

    local range = addTab("Range")
    parent.longRange = range:checkbox("longRange", "Extended range past 35 yd (Hawk Eye)",
        { enabledIf = hunterOnly,
            tooltip = "Seven dots instead of six. Auto-detected from Auto Shot's reach when the spellbook "
                .. "answers; tick manually otherwise." })
    range:info("Auto Shot's reach reads", function()
        return detectedAutoMax and (tostring(detectedAutoMax) .. " yd") or "not answered by this client"
    end, { enabledIf = hunterOnly,
        tooltip = "Auto Shot's own maximum range, read from the spellbook. Past 35 yd the seventh dot exists." })
    range:gap()
    range:note("The bands are approximate item probes, never exact yards: 8-10, 10-15, 15-20, 20-25, "
        .. "25-30 and 30-35 yd. MELEE is Wing Clip's reach; the 5-8 yd dead zone sits between melee and the "
        .. "first dot. /upt hunterprobe prints what the client answers for the probes.")

    local appearance = addTab("Appearance")
    local editor = BIT.UI.Appearance(appearance.inner, M.moduleName, CAPABILITIES, refreshAll, hunterLegacy)
    editor:SetPoint("TOPLEFT", appearance.inner, "TOPLEFT", 0, 0)
    editor.onLayout = function()
        appearance.y = (editor:GetHeight() or 0) + 8
        appearance:finish()
        appearance.content:SetVerticalScroll(0)
    end
    appearance.y = (editor:GetHeight() or 0) + 8
    appearance.editor = editor
    appearance.reset = function()
        if BIT.Style and BIT.Style.Reset then BIT.Style.Reset(M.moduleName) end
    end
    parent.hunterEditor = editor

    for _, tab in ipairs(tabs) do tab:finish() end
end

----------------------------------------------------------------------------------------------
-- The live preview: a mock enemy nameplate under the real rail, plus the TRY IT band switch.
----------------------------------------------------------------------------------------------

local function buildLivePreview(pane)
    local SIDE = 12
    local CARD_WIDTH = PREVIEW_WIDTH - 2 * SIDE

    local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", SIDE, -12)
    title:SetText("Live preview")
    local titleRule = pane:CreateTexture(nil, "ARTWORK")
    titleRule:SetColorTexture(0.28, 0.28, 0.3, 1)
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT", 8, -34)
    titleRule:SetPoint("TOPRIGHT", -8, -34)

    -- The scene: a patch of dusky world behind the mock plate, so the rail reads in place.
    local scene = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    scene:SetSize(CARD_WIDTH, 228)
    scene:SetPoint("TOP", pane, "TOP", 0, -44)
    scene:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    scene:SetBackdropBorderColor(0, 0, 0, 1)
    local ground = scene:CreateTexture(nil, "BACKGROUND", nil, -8)
    ground:SetPoint("TOPLEFT", 1, -1)
    ground:SetPoint("BOTTOMRIGHT", -1, 1)
    ground:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    ground:SetTexCoord(0, 0.26, 0, 0.2)
    ground:SetVertexColor(0.75, 0.8, 0.75)
    local sky = scene:CreateTexture(nil, "BACKGROUND", nil, -7)
    sky:SetAllPoints(ground)
    sky:SetColorTexture(0.06, 0.09, 0.12, 0.5)
    local shade = scene:CreateTexture(nil, "BACKGROUND", nil, -6)
    shade:SetPoint("BOTTOMLEFT", ground, "BOTTOMLEFT")
    shade:SetPoint("BOTTOMRIGHT", ground, "BOTTOMRIGHT")
    shade:SetHeight(40)
    shade:SetColorTexture(0, 0, 0, 0.45)

    -- Mock enemy nameplate: a hostile name under a red health bar with the target's selection
    -- glow. The rail is seated above it and re-seated whenever the saved offset changes.
    local plate = CreateFrame("Frame", nil, scene)
    plate:SetSize(CARD_WIDTH - 24, 62)
    plate:SetPoint("BOTTOM", scene, "BOTTOM", 0, 14)
    local name = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 6, 2)
    name:SetText("Murloc Raider")
    name:SetTextColor(1, 0.13, 0.13)
    local level = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    level:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -6, 2)
    level:SetText("12")
    level:SetTextColor(1, 0.82, 0)
    local healthBar = CreateFrame("StatusBar", nil, plate)
    healthBar:SetSize(CARD_WIDTH - 48, 16)
    healthBar:SetPoint("BOTTOM", plate, "BOTTOM", 0, 22)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(72)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(0.85, 0.1, 0.1)
    local barBack = healthBar:CreateTexture(nil, "BACKGROUND")
    barBack:SetAllPoints()
    barBack:SetColorTexture(0.1, 0.02, 0.02, 1)
    local barGlow = healthBar:CreateTexture(nil, "OVERLAY")
    barGlow:SetPoint("TOPLEFT", healthBar, "TOPLEFT", -3, 2)
    barGlow:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 3, -2)
    barGlow:SetColorTexture(1, 0.82, 0, 0.18)
    local healthText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthText:SetPoint("LEFT", healthBar, "LEFT", 4, 0)
    healthText:SetText("72%")
    previewBar = healthBar

    -- The rail itself: the retained scene the HUD draws, re-rendered from the resolved style
    -- and the TRY IT band, seated above the mock bar exactly like the live anchor.
    sample = buildScene(scene)
    renderPreview()
    pane.hunterRail = sample

    -- Section header: small gold caps and a hairline to the right margin.
    local function header(text, anchor, gap)
        local label = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        label:SetText(text)
        label:SetTextColor(0.85, 0.7, 0.3)
        local rule = pane:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(0.28, 0.28, 0.3, 1)
        rule:SetHeight(1)
        rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
        rule:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)
        return label
    end

    -- TRY IT: the mock target's own band, never a saved setting.
    local tryIt = header("TRY IT", scene, 14)
    local bandRow = sliderRow(pane, "Target band", 1, #BAND_ORDER, 1,
        function() return bandIndex(previewBand) or 1 end,
        function(value) setPreviewBand(BAND_ORDER[value]) end,
        { layout = PREVIEW_LAYOUT,
            format = function(v) return bandText(BAND_ORDER[v] or "") end,
            tooltip = "Walks the mock target through every band the rail shows: Y10 to Y35, the 35+ yd "
                .. "seventh dot, MELEE and the dead zone." })
    bandRow:SetPoint("TOPLEFT", tryIt, "BOTTOMLEFT", -6, -6)
    pane.hunterBandRow = bandRow

    local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", bandRow, "BOTTOMLEFT", 6, -14)
    hint:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Drawn by the same code as the live HUD, on a mock enemy nameplate. Six dots by "
        .. "default; a seventh past 35 yd only with Hawk Eye.")
end

local function build(parent)
    rows, tabs, activeTab = {}, {}, nil
    local _, class = UnitClass("player")
    local isHunter = class == "HUNTER"
    settings = settings or BIT.Settings(M.moduleName, DEFAULTS)

    -- Top strip: the rail's style presets on the right, the class note on the left.
    local anchor = CreateFrame("Frame", nil, parent)
    anchor:SetSize(1, 22)
    anchor:SetPoint("TOPRIGHT", -10, -8)
    local presetLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local previous
    parent.hunterPresets = {}
    for i = #PRESETS, 1, -1 do
        local preset = PRESETS[i]
        local button = pushButton(parent, preset.label, 72, function() applyPreset(preset) end)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        else
            button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        end
        previous = button
        parent.hunterPresets[i] = button
    end
    presetLabel:SetPoint("RIGHT", previous, "LEFT", -8, 0)
    presetLabel:SetText("Rail style")

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 12, -6)
    note:SetPoint("RIGHT", presetLabel, "LEFT", -12, 0)
    note:SetJustifyH("LEFT")
    note:SetText(isHunter
        and "The rail rides above the target's nameplate while a living hostile target is selected; "
            .. "unlock to drag it to a screen spot of your own."
        or "The native range rail appears only on a Hunter. On another class these settings wait for the "
            .. "hunter alt; the preview and the appearance editor need no hunter and no target.")
    parent.hunterNote = note

    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", 10, -46)
    pane:SetSize(PREVIEW_WIDTH, COL_HEIGHT)
    setBackdrop(pane, 0.09)
    parent.hunterPane = pane

    area = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    area:SetPoint("TOPLEFT", pane, "TOPRIGHT", 10, 0)
    area:SetSize(WINDOW_WIDTH - PREVIEW_WIDTH - 30, COL_HEIGHT)
    setBackdrop(area, 0.09)
    parent.hunterArea = area

    local divider = area:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.28, 0.28, 0.3, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -34)
    divider:SetPoint("TOPRIGHT", -8, -34)

    buildLivePreview(pane)
    parent.hunterSample = sample
    buildTabs(parent, isHunter)

    local reset = pushButton(area, "Reset this tab", 120, function() resetTab(activeTab) end)
    reset:SetPoint("BOTTOMRIGHT", -10, 10)
    parent.hunterResetTab = reset
    parent.hunterTabs = tabs

    tabRefresh = function()
        refreshControls()
    end
    selectTab(tabs[1])
    refreshAll()
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
    summary = "Six native dots tell a hunter the approximate range, 8-10 yd to 30-35 yd; a seventh past 35 yd with Hawk Eye.",
    width = WINDOW_WIDTH, height = WINDOW_HEIGHT,
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
        if ok and value ~= nil and not isSecret(value) then return value end
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
    if isSecret(value) then return "secret" end
    if value == nil then return "nil" end
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
-- The settings tab: the retained preview scene, the TRY IT band switch and the tab strip.
M._previewScene = function() return sample end
M._previewBand = function(name)
    if name == nil then return previewBand end
    setPreviewBand(name)
    return previewBand
end
M._activeTab = function() return activeTab and activeTab.name end
M._tabs = function() return tabs end
