-- BattleInfoTool module HunterRangeFinder: the hunter's range in seven stacked chevrons.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- Adapted from the supplied local addon HunterRangeFinder v1.03, version 3.11.6
-- (C:/Users/Oleg/Downloads/HunterRangeFinder/HunterRangeFinder: HunterRangeFinder.lua,
-- README.txt, HunterRangeFinder.toc and its Textures). The folder keeps its literal name in
-- that provenance. Two things changed for living inside BattleInfoTool:
--   * the settings live in one BIT.Settings("HunterRangeFinder") store, built into the module's
--     tab (/bit hunter), instead of HunterRangeFinderDB and a window and slash commands of its own;
--   * the module starts a HUD only for a Hunter with the module switched on; any other class (or
--     a switched-off module) creates no frames, events or polling, and the tab explains that.
-- /bit hunterprobe prints what the client answers, for diagnostics.
-- Range ladder and melee/dead-zone checks adapted from the supplied Bands.lua.
--
-- The chevrons are approximate probes, never exact yards: item probes mark the 10/15/20/25/30/35
-- yd boundaries, and the top cyan band needs the 35 yd probe to come back false while Auto Shot
-- (75) is in range. When the 35 yd probe cannot say, the stack stays at six green chevrons.
-- Wing Clip (2974) measures melee (never Raptor Strike), and Auto Shot's minimum range marks the
-- dead zone (5-8 yd, the skull) between melee and the first chevron.

local _, BIT = ...

local M = BIT.Module("HunterRangeFinder")

local DEFAULTS = {
    x = -135, y = -34, scale = 1, opacity = 1,
    chevronHeight = 1, chevronWidth = 1,
    locked = true,
    -- The chevron transitions are there, but off is the default: a static icon suits more
    -- players than the shake and pulse (the original shipped animated; see HunterRangeFinder.lua).
    animateDeadzone = false, animateMelee = false,
    showDeadzoneIcon = true, showMeleeIcon = true,
    smallBottomChevron = true,
}

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

local function validTarget()
    local ok, valid = pcall(function()
        return UnitExists("target") and not UnitIsDeadOrGhost("target")
            and UnitCanAttack("player", "target") and true or false
    end)
    return ok and safeNormalize(valid) == true
end

-- "Y10".."Y35", "MAX" (cyan), "MELEE", "DEAD" (the 5-8 yd skull), "OOR" or nil (no valid target).
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
    -- Auto Shot alone cannot prove the target is past 35 yd. The 35 yd probe must explicitly
    -- answer false before the top chevron turns cyan; a missing answer keeps the six green ones.
    if auto == true and thirtyFive == false then return "MAX" end
    if auto == true then return "Y35" end -- probe unavailable: keep green
    return "OOR"
end

----------------------------------------------------------------------------------------------
-- The display: seven chevrons on one frame, the skull and the crossed swords on top of them.
----------------------------------------------------------------------------------------------

local hud, driver

-- Seven smaller chevrons occupy roughly the original display area. From bottom to top:
-- 8-10, 10-15, 15-20, 20-25, 25-30, 30-35, and 35 yd to Auto Shot's maximum range.
local CHEVRON_SPACING, CHEVRON_LIFT, CHEVRON_WIDTH = 18, 10, 68
local CHEVRON_HEIGHT = 38
local chevronNames = {"Cyan", "Green", "Amber", "Amber", "Amber", "Coral", "CoralShort"}
local path = "Interface\\AddOns\\" .. BIT.name .. "\\Modules\\" .. M.moduleName .. "\\Textures\\"

local states = {}
local band, lastCount, animationTime = nil, nil, 0
local targetSelectionChanged = true
local acquiringTarget, acquisitionTime, acquisitionBand, acquisitionSamples = false, 0, nil, 0
local iconProgress, chevronFade, oorProgress, shakeTime, exitOffset = 0, 0, 0, 0, -700
local skullAlpha, swordsAlpha = 0, 0
local preview = false
local elapsed = 0

local function drawChevron(i, xOffset, yOffset, groupAlpha)
    local state = states[i]
    local tex = hud.chevrons[i]
    tex:ClearAllPoints()
    tex:SetPoint("TOP", hud.frame, "TOP", xOffset, -state.y + yOffset)
    tex:SetAlpha(state.alpha * groupAlpha)
end

local function applyChevronHeight(value)
    local newSpacing = 18 * value
    local ratio = newSpacing / CHEVRON_SPACING
    CHEVRON_SPACING, CHEVRON_LIFT = newSpacing, 10 * value
    for i = 1, #hud.chevrons do
        local state = states[i]
        state.y = state.y * ratio
        state.fromY = state.fromY * ratio
        state.toY = state.toY * ratio
        hud.chevrons[i]:SetSize(CHEVRON_WIDTH, CHEVRON_HEIGHT * value)
    end
end

local function applyChevronWidth(value)
    CHEVRON_WIDTH = 68 * value
    for i = 1, #hud.chevrons do
        hud.chevrons[i]:SetWidth(CHEVRON_WIDTH)
    end
end

local function updateBottomChevron()
    if not hud then return end
    local bottom = hud.chevrons[#hud.chevrons]
    bottom:SetTexture(path .. (settings.smallBottomChevron and "CoralShort" or "Coral"))
end

local countByBand = {
    MELEE = 0, DEAD = 0, Y10 = 1, Y15 = 2,
    Y20 = 3, Y25 = 4, Y30 = 5,
    Y35 = 6, MAX = 7, PREVIEW = 7,
}

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

local function scatterShotRange()
    if not scatterShotKnown() then return nil end
    return spellInRange(SCATTER_SHOT)
end

local scatterColorKnown, scatterExtendedObserved, scatterMaxRange = nil, false, nil
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

local function updateScatterChevron(cur)
    if not hud then return end
    local known = scatterShotKnown()
    if not known then scatterExtendedObserved = false end
    -- Live reach past the 15 yd item rung takes precedence over a base maxRange that a talent
    -- may not update on this client.
    if known and (cur == "Y20" or cur == "Y25") and scatterShotRange() == true then
        scatterExtendedObserved = true
    end
    local maximum = known and scatterShotMaximum() or nil
    local red = known and (scatterExtendedObserved or (maximum ~= nil and maximum > 15)) or false
    if scatterColorKnown == red then return end
    scatterColorKnown = red
    hud.chevrons[5]:SetTexture(path .. (red and "Coral" or "Amber"))
end

local function chevronCount(cur)
    -- Within the 20-25 yd item rung, keep the red chevron on top until Scatter Shot itself
    -- falls out of range (approximately 21 yd).
    if cur == "Y25" and scatterShotRange() == true then return 3 end
    return countByBand[cur] or 7
end

local function setCount(count)
    if count == lastCount then return end
    local oldCount = lastCount or #hud.chevrons
    lastCount = count
    animationTime = 0
    local first = #hud.chevrons + 1 - count
    local oldFirst = #hud.chevrons + 1 - oldCount
    for i = 1, #hud.chevrons do
        local state = states[i]
        local slot = (i - 1) * CHEVRON_SPACING
        state.fromY, state.fromAlpha = state.y, state.alpha
        if i < first then
            state.toAlpha = 0
            -- An already hidden chevron stays still; only a departing one lifts.
            state.toY = i >= oldFirst and (slot - CHEVRON_LIFT) or state.y
        else
            state.toAlpha = 1
            state.toY = slot
            if i < oldFirst and state.alpha == 0 then
                -- The returning chevron descends into its original slot.
                state.y, state.fromY = slot - CHEVRON_LIFT, slot - CHEVRON_LIFT
            end
        end
    end
end

local function usesSpecialIcon(cur)
    return (cur == "DEAD" and settings.showDeadzoneIcon ~= false)
        or (cur == "MELEE" and settings.showMeleeIcon ~= false)
end

local ICON_TRANSITION, ANIMATION = 0.22, 0.16

local function updateDisplay(_, dt)
    if not hud then return end
    if acquiringTarget then acquisitionTime = acquisitionTime + dt end
    elapsed = elapsed + dt
    if elapsed >= 0.1 then
        elapsed = 0
        local priorBand = band
        -- PLAYER_TARGET_CHANGED already identifies a new target; GUID values may be secret
        -- inside instances and cannot be compared by addons (none is read here).
        local targetChanged = targetSelectionChanged
        targetSelectionChanged = false
        if targetChanged and not preview then
            acquiringTarget, acquisitionTime = true, 0
            acquisitionBand, acquisitionSamples = nil, 0
            band, lastCount = nil, nil
            oorProgress = 1
            iconProgress, chevronFade, skullAlpha, swordsAlpha = 0, 0, 0, 0
            -- Clear the previous target's stack before building this one's.
            for i = 1, #hud.chevrons do
                local state = states[i]
                local slot = (i - 1) * CHEVRON_SPACING
                state.y, state.fromY, state.toY = slot, slot, slot
                state.alpha, state.fromAlpha, state.toAlpha = 0, 0, 0
            end
            hud.frame:Hide()
        end
        local measuredBand = preview and "PREVIEW" or currentBand()
        updateScatterChevron(measuredBand)
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
                hud.frame:Hide()
                return
            end
            acquiringTarget = false
        end
        band = measuredBand
        local priorStatic = (priorBand == "DEAD" and settings.animateDeadzone == false)
            or (priorBand == "MELEE" and settings.animateMelee == false)
        if priorStatic and band ~= "DEAD" and band ~= "MELEE" then
            iconProgress, chevronFade = 0, 0
            skullAlpha, swordsAlpha = 0, 0
        end
        if band then
            if usesSpecialIcon(band) then
                -- Measure the distance to the left edge once, so the entire visible stack can
                -- slide fully off screen together. The client's answers are guarded: without
                -- them the stack simply stays below the icon (exitOffset keeps its last value).
                if iconProgress == 0 then
                    local centerX = hud.frame:GetCenter()
                    if type(centerX) == "number" then
                        local effective = hud.frame:GetEffectiveScale()
                        local parentScale = UIParent:GetEffectiveScale()
                        if type(effective) == "number" and type(parentScale) == "number"
                            and parentScale > 0 then
                            local scale = effective / parentScale
                            local parentLeft = UIParent:GetLeft()
                            exitOffset = -((centerX - (type(parentLeft) == "number" and parentLeft or 0))
                                / scale + 80)
                        end
                    end
                end
            elseif band ~= "OOR" then
                setCount(chevronCount(band))
            end
            local blankClose = (band == "DEAD" and settings.showDeadzoneIcon == false)
                or (band == "MELEE" and settings.showMeleeIcon == false)
            if blankClose then
                -- With the icon disabled, this range must remain empty.
                iconProgress, chevronFade = 0, 0
                skullAlpha, swordsAlpha = 0, 0
                animationTime = ANIMATION
                for i = 1, #hud.chevrons do
                    local state = states[i]
                    state.y, state.fromY = state.toY, state.toY
                    state.alpha, state.fromAlpha = 0, 0
                    hud.chevrons[i]:SetAlpha(0)
                end
                hud.skull:SetAlpha(0)
                hud.swords:SetAlpha(0)
                hud.frame:Hide()
            elseif band ~= "OOR" or oorProgress < 1 then
                hud.frame:Show()
            end
        else
            hud.frame:Hide()
            lastCount = nil
            iconProgress, chevronFade, oorProgress, skullAlpha, swordsAlpha = 0, 0, 0, 0, 0
            hud.skull:SetAlpha(0)
            hud.swords:SetAlpha(0)
        end
    end
    if not band then return end
    local staticDead = band == "DEAD" and usesSpecialIcon(band)
        and settings.animateDeadzone == false
    local staticMelee = band == "MELEE" and usesSpecialIcon(band)
        and settings.animateMelee == false
    local iconsSuppressed = (band == "DEAD" and settings.showDeadzoneIcon == false)
        or (band == "MELEE" and settings.showMeleeIcon == false)
    if staticDead or staticMelee then
        iconProgress, chevronFade = 1, 1
    elseif usesSpecialIcon(band) then
        iconProgress = math.min(1, iconProgress + dt / ICON_TRANSITION)
        chevronFade = math.min(1, chevronFade + dt / 0.07)
    else
        iconProgress = math.max(0, iconProgress - dt / 0.07)
        chevronFade = math.max(0, chevronFade - dt / 0.07)
    end
    if band == "OOR" then
        oorProgress = math.min(1, oorProgress + dt / ANIMATION)
    else
        oorProgress = math.max(0, oorProgress - dt / ANIMATION)
    end
    shakeTime = shakeTime + dt
    local slide = iconProgress * iconProgress * (3 - 2 * iconProgress)
    local xOffset = exitOffset * slide
    local rise = oorProgress * oorProgress * (3 - 2 * oorProgress)
    local iconFade = dt / 0.12
    if iconsSuppressed then
        skullAlpha, swordsAlpha = 0, 0
    elseif staticDead then
        skullAlpha, swordsAlpha = 1, 0
    elseif staticMelee then
        skullAlpha, swordsAlpha = 0, 1
    else
        skullAlpha = math.max(0, math.min(1,
            skullAlpha + (band == "DEAD" and iconFade or -iconFade)))
        swordsAlpha = math.max(0, math.min(1,
            swordsAlpha + (band == "MELEE" and iconFade or -iconFade)))
    end
    hud.skull:SetAlpha(skullAlpha)
    hud.skull:ClearAllPoints()
    local skullShake = staticDead and 0 or 1
    hud.skull:SetPoint("CENTER", hud.frame, "TOP",
        math.sin(shakeTime * 59) * 3 * skullAlpha * skullShake,
        -111 + math.sin(shakeTime * 83) * 2 * skullAlpha * skullShake)
    local pulse = staticMelee and 0.5 or (0.5 + 0.5 * math.sin(shakeTime * 9))
    hud.swords:SetSize(84 + 8 * pulse, 84 + 8 * pulse)
    hud.swords:SetAlpha(staticMelee and 1 or swordsAlpha * (0.72 + 0.28 * pulse))
    animationTime = math.min(animationTime + dt, ANIMATION)
    local t = animationTime / ANIMATION
    t = t * t * (3 - 2 * t) -- quick, soft landing
    for i = 1, #hud.chevrons do
        local state = states[i]
        state.y = state.fromY + (state.toY - state.fromY) * t
        state.alpha = state.fromAlpha + (state.toAlpha - state.fromAlpha) * t
        drawChevron(i, xOffset, 12 * rise, (1 - chevronFade) * (1 - rise))
    end
    if (band == "OOR" and oorProgress >= 1) or iconsSuppressed then
        hud.frame:Hide()
    end
end

local function position()
    if not hud then return end
    hud.frame:ClearAllPoints()
    hud.frame:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    hud.frame:SetScale(settings.scale)
    hud.frame:SetAlpha(settings.opacity)
end

local function setPreview(value)
    preview = value and true or false
    if not hud then return end
    hud.frame:EnableMouse(preview)
    -- Poll only while a target exists or the preview is being dragged.
    driver:SetShown(preview or UnitExists("target") == true)
    if preview then
        band = "PREVIEW"
        setCount(#hud.chevrons)
        hud.frame:Show()
    else
        band, lastCount = nil, nil
        hud.frame:Hide()
    end
end

local tabRefresh

local function setLocked(locked)
    settings.locked = locked and true or false
    setPreview(not settings.locked)
    if tabRefresh then tabRefresh() end
end

local function start()
    hud = {
        frame = CreateFrame("Frame", nil, UIParent),
        chevrons = {},
        skull = nil,
        swords = nil,
    }
    local frame = hud.frame
    frame:SetSize(76, 140)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    frame:SetScript("OnDragStart", function(self)
        if preview then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- The client's answers are guarded: without real numbers nothing is saved, and the
        -- ordinary offset (not a scaled-in screen position) is what the next position() uses.
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local effective = self:GetEffectiveScale()
        local parentScale = UIParent:GetEffectiveScale()
        if type(x) == "number" and type(y) == "number" and type(ux) == "number"
            and type(uy) == "number" and type(effective) == "number"
            and type(parentScale) == "number" and parentScale > 0 then
            local scale = effective / parentScale
            settings.x, settings.y = (x * scale) - ux, (y * scale) - uy
        end
        position()
    end)

    -- Each V has a roughly 16 px thick band at 38 px texture height; 18 px slots leave a
    -- slight gap at every point along the parallel edges.
    for i, name in ipairs(chevronNames) do
        local tex = frame:CreateTexture(nil, "ARTWORK", nil, i)
        tex:SetTexture(path .. name)
        tex:SetSize(CHEVRON_WIDTH, CHEVRON_HEIGHT)
        tex:SetPoint("TOP", frame, "TOP", 0, -((i - 1) * CHEVRON_SPACING))
        hud.chevrons[i] = tex
    end
    local skull = frame:CreateTexture(nil, "OVERLAY")
    skull:SetTexture(path .. "DeadzoneSkull")
    skull:SetSize(80, 80)
    skull:SetPoint("CENTER", frame, "TOP", 0, -111)
    skull:SetAlpha(0)
    hud.skull = skull
    local swords = frame:CreateTexture(nil, "OVERLAY")
    swords:SetTexture(path .. "CrossedSwords")
    swords:SetSize(88, 88)
    swords:SetPoint("CENTER", frame, "TOP", 0, -111)
    swords:SetAlpha(0)
    hud.swords = swords

    for i = 1, #hud.chevrons do
        states[i] = { y = (i - 1) * CHEVRON_SPACING, alpha = 1, fromY = 0,
            fromAlpha = 1, toY = 0, toAlpha = 1 }
    end

    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", updateDisplay)
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:SetScript("OnEvent", function(_, event)
        -- Hide the previous target immediately, before the next range poll.
        frame:Hide()
        targetSelectionChanged = true
        acquiringTarget, acquisitionTime = true, 0
        acquisitionBand, acquisitionSamples = nil, 0
        band = nil
        elapsed = 0.1
        driver:SetShown(preview or UnitExists("target") == true)
    end)

    applyChevronHeight(settings.chevronHeight)
    applyChevronWidth(settings.chevronWidth)
    updateBottomChevron()
    position()
    setPreview(settings.locked == false)
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, 16114)
        for _, rung in ipairs(ladder) do
            for j = 2, #rung do pcall(C_Item.RequestLoadItemDataByID, rung[j]) end
        end
    end
end

----------------------------------------------------------------------------------------------
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
        scatterMaxRange, scatterExtendedObserved = nil, false
        if hud then updateScatterChevron() end
        return
    end
    if name ~= BIT.name then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not BIT.ShouldRun("HunterRangeFinder") then
        -- Switched off in /bit: no frames, no events, nothing polled.
        self:UnregisterEvent("SPELLS_CHANGED")
        return
    end
    settings = BIT.Settings("HunterRangeFinder", DEFAULTS)
    M.settings = settings
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
        -- The chevrons are a hunter's; any other class gets no display and no events.
        self:UnregisterEvent("SPELLS_CHANGED")
    end
end)

----------------------------------------------------------------------------------------------
-- The settings tab
----------------------------------------------------------------------------------------------

local function build(parent)
    local UI = BIT.UI
    local _, class = UnitClass("player")
    if class ~= "HUNTER" then
        local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        note:SetPoint("TOPLEFT", 12, -10)
        note:SetPoint("RIGHT", -12, 0)
        note:SetJustifyH("LEFT")
        note:SetText("The seven range chevrons appear only on a Hunter. On another class this "
            .. "module keeps its settings here, ready for the hunter alt.")
        parent.hunterNote = note
        return
    end

    local rows = {}
    local function changed()
        for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
    end
    local function set(key, apply)
        return function(v)
            -- every slider here steps by 0.05; round the float the way the sliders show it.
            -- The switches pass true/false through untouched.
            if type(v) == "number" then v = math.floor(v * 20 + 0.5) / 20 end
            settings[key] = v
            if apply then apply() end
        end
    end
    local function get(key) return function() return settings[key] end end

    local y = -6
    local function add(row, height)
        row:SetPoint("TOPLEFT", 12, y)
        rows[#rows + 1] = row
        y = y - (height or 30)
        return row
    end

    parent.lockButton = UI.Button(parent, settings.locked and "Unlock and move" or "Lock position",
        180, function()
            setLocked(not settings.locked)
        end)
    parent.lockButton:SetPoint("TOPLEFT", 12, y)
    local status = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", parent.lockButton, "RIGHT", 10, 0)
    status:SetText("Unlock, drag the chevrons, then lock to save their position.")
    y = y - 34

    parent.sliders = {}
    parent.sliders.scale = UI.Slider(parent, "Size", 0.5, 3, 0.05, get("scale"), set("scale", position), "%.2fx")
    add(parent.sliders.scale, 46)
    parent.sliders.opacity = UI.Slider(parent, "Opacity", 0.1, 1, 0.05, get("opacity"), set("opacity", position), "%d%%")
    add(parent.sliders.opacity, 46)
    parent.sliders.height = UI.Slider(parent, "Chevron height", 0.5, 1.5, 0.05,
        get("chevronHeight"), set("chevronHeight", function() applyChevronHeight(settings.chevronHeight) end), "%d%%")
    add(parent.sliders.height, 46)
    parent.sliders.width = UI.Slider(parent, "Chevron width", 0.5, 1.5, 0.05,
        get("chevronWidth"), set("chevronWidth", function() applyChevronWidth(settings.chevronWidth) end), "%d%%")
    add(parent.sliders.width, 46)

    local x = 380
    parent.deadAnim = UI.Check(parent, "Dead zone animation", get("animateDeadzone"), set("animateDeadzone"))
    parent.deadAnim:SetPoint("TOPLEFT", x, y + 46)
    parent.meleeAnim = UI.Check(parent, "Melee animation", get("animateMelee"), set("animateMelee"))
    parent.meleeAnim:SetPoint("TOPLEFT", x, y + 46 - 30)
    parent.deadIcon = UI.Check(parent, "Show dead zone skull", get("showDeadzoneIcon"), set("showDeadzoneIcon"))
    parent.deadIcon:SetPoint("TOPLEFT", x, y + 46 - 60)
    parent.meleeIcon = UI.Check(parent, "Show melee swords", get("showMeleeIcon"), set("showMeleeIcon"))
    parent.meleeIcon:SetPoint("TOPLEFT", x, y + 46 - 90)
    parent.smallBottom = UI.Check(parent, "Small 8-10 yd chevron", get("smallBottomChevron"),
        set("smallBottomChevron", updateBottomChevron))
    parent.smallBottom:SetPoint("TOPLEFT", x, y + 46 - 120)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, y + 46 - 200)
    hint:SetPoint("RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("The chevrons sit at the centre of the screen while a living hostile target is "
        .. "selected. The bands are approximate probes: 8-10, 10-15, 15-20, 20-25, 25-30, 30-35, "
        .. "and beyond 35 yd to Auto Shot's maximum. /bit hunterprobe prints what the client "
        .. "answers for the probes.")

    tabRefresh = function()
        parent.lockButton:SetText(settings.locked and "Unlock and move" or "Lock position")
        changed()
    end
end

BIT.RegisterTab("HunterRangeFinder", {
    title = "Hunter range",
    summary = "Seven stacked chevrons tell a hunter where the target is, from 8-10 yd to past Auto Shot's maximum.",
    width = 700, height = 400,
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