-- Retail predicts explicitly cast, single-target DoTs; it never reads protected aura state.
local _, BIT = ...
local ns = BIT.Module("DoTInfo")
local ok, version = pcall(GetBuildInfo)
if not ok or type(version) ~= "string" or (tonumber(version:match("^(%d+)")) or 0) < 10 then return end

local R = {}
ns.Retail = R

-- Proc, ground and channel effects have no reliable recipient in a player cast event.
R.spells = {
    [172] = {}, [980] = {}, -- Corruption, Agony
    [589] = {}, [34914] = {}, -- Shadow Word: Pain, Vampiric Touch
    [8921] = {}, [93402] = {}, [1822] = {}, [1079] = { finisher = true }, -- Moonfire, Sunfire, Rake, Rip
    [703] = {}, [1943] = { finisher = true }, -- Garrote, Rupture
    [188389] = {}, [772] = {}, -- Flame Shock, Rend
}

local function secret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local success, value = pcall(fn, ...)
    if not success or secret(value) then return nil end
    return value
end

local function integer(value, minimum)
    return not secret(value) and type(value) == "number" and value == value
        and value < math.huge and value >= minimum and value == math.floor(value)
end

-- The cast event can name an override rather than the base spell in the supported list.
function R.SpellID(spellID)
    if not integer(spellID, 1) then return end
    if R.spells[spellID] then return spellID end
    local base = ask(C_Spell and C_Spell.GetBaseSpell, spellID)
    if integer(base, 1) and R.spells[base] then return base end
end

function R.IsFinisher(spellID)
    local base = R.SpellID(spellID)
    return base and R.spells[base].finisher
end

function R.SpellDescription(spellID, readDescription)
    if not integer(spellID, 1) then return end
    local base = R.SpellID(spellID)
    if C_Spell and type(C_Spell.GetOverrideSpell) == "function" then
        local ok, override = pcall(C_Spell.GetOverrideSpell, base or spellID)
        if not ok or secret(override) then return end
        if integer(override, 1) then spellID = override end
    end
    return readDescription(spellID)
end

function R.ComboPoints()
    local power = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
    local points, maximum = ask(UnitPower, "player", power), ask(UnitPowerMax, "player", power)
    if integer(maximum, 1) and integer(points, 0) and points <= maximum then return points end
end

local plates, serial, targetKey = {}, 0, nil
local function freshKey()
    serial = serial + 1
    return "retail-unit:" .. serial
end

local function plainGUID(unit)
    local guid = ask(UnitGUID, unit)
    if type(guid) == "string" and guid ~= "" then return guid end
end

local function sameUnit(first, second)
    return ask(UnitIsUnit, first, second) == true
end

local function ephemeral(key)
    return type(key) == "string" and key:match("^retail%-unit:%d+$") ~= nil
end

function R.AddPlate(unit)
    if secret(unit) or type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
    local old = plates[unit]
    local key = targetKey and sameUnit(unit, "target") and targetKey or plainGUID(unit)
    plates[unit] = key or freshKey()
    if ephemeral(old) then return old end
end

function R.RemovePlate(unit)
    if secret(unit) or type(unit) ~= "string" then return end
    local key = plates[unit]
    plates[unit] = nil
    if ephemeral(key) then
        if key == targetKey then targetKey = nil end
        return key
    end
end

function R.SeedPlates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if not plates[unit] and ask(UnitExists, unit) == true then R.AddPlate(unit) end
    end
end

function R.Reset()
    plates, targetKey = {}, nil
end

function R.UnitKey(unit)
    if secret(unit) or type(unit) ~= "string" then return end
    if unit:match("^nameplate%d+$") then return plates[unit] end
    for plateUnit, key in pairs(plates) do
        if sameUnit(plateUnit, unit) then
            if unit == "target" then targetKey = key end
            return key
        end
    end
    if unit == "target" then
        if ask(UnitExists, unit) ~= true then return end
        targetKey = targetKey or plainGUID(unit) or freshKey()
        return targetKey
    end
    if sameUnit(unit, "target") then return R.UnitKey("target") end
    return plainGUID(unit)
end

-- Only an unbacked target alias is forgotten on selection change. Active plates retain their keys.
function R.TargetChanged()
    local old = targetKey
    targetKey = nil
    for _, key in pairs(plates) do if key == old then return end end
    if ephemeral(old) then return old end
end

function R.Recipient(sentName)
    local default = R.UnitKey("target") or R.UnitKey("softenemy")
    if secret(sentName) or type(sentName) ~= "string" or sentName == "" then
        -- A hidden SENT name cannot distinguish a selected-target cast from a focus/mouseover macro.
        for _, unit in ipairs({ "mouseover", "focus" }) do
            if ask(UnitExists, unit) == true and ask(UnitCanAttack, "player", unit) ~= false then
                local key = R.UnitKey(unit)
                if not key or key ~= default then return end
            end
        end
        return default
    end
    -- A readable SENT name can identify a focus/mouseover cast, but identical NPC names are ambiguous.
    local recipient
    for _, unit in ipairs({ "target", "softenemy", "mouseover", "focus" }) do
        if ask(UnitExists, unit) == true and ask(UnitName, unit) == sentName then
            local key = R.UnitKey(unit)
            if not key then return end
            if recipient and key ~= recipient then return end
            recipient = key
        end
    end
    return recipient
end

function R.Parse(spellID, desc, comboPoints, parseLegacy)
    spellID = R.SpellID(spellID)
    if not spellID or secret(desc) or type(desc) ~= "string" then return end
    local text = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("\194\160", " "):gsub("\226\128\175", " ")
    local locale = ask(GetLocale) or "enUS"
    local original = text
    local count = 1
    if locale == "enUS" or locale == "enGB" then
        while count > 0 do text, count = text:gsub("(%d),(%d)", "%1%2") end
    elseif locale == "deDE" then
        while count > 0 do text, count = text:gsub("(%d)%.(%d%d%d)%f[%D]", "%1%2") end
        text = text:gsub("(%d),(%d)", "%1.%2")
    end
    local total, school, duration, interval
    local byPoints, hasRows = {}, false
    local function germanSchool(words)
        words = words:lower()
        for word, mask in pairs({ schatten = 32, feuer = 4, natur = 8, arkan = 64, heilig = 2, frost = 16 }) do
            if words:find(word, 1, true) then return mask end
        end
        return 1
    end
    if locale == "enUS" or locale == "enGB" then
        if R.spells[spellID].finisher then
            hasRows = text:find("%d+ points?%s*:") ~= nil
            for count, amount, secs in text:gmatch("(%d+) points?%s*:%s*(%d+%.?%d*)%s*[^%d\n]-over (%d+%.?%d*) sec") do
                local points = tonumber(count)
                byPoints[points] = { total = tonumber(amount), duration = tonumber(secs) }
            end
        end
        if not hasRows then
            for amount, words, secs in text:gmatch("(%d+%.?%d*)%s*([%a ]-)%s*[Dd]amage over (%d+%.?%d*) sec") do
                total, duration = tonumber(amount), tonumber(secs)
                school = 1
                for word, mask in pairs({ Shadow = 32, Fire = 4, Nature = 8, Arcane = 64, Holy = 2, Frost = 16 }) do
                    if words:find(word, 1, true) then school = mask end
                end
            end
        end
    elseif locale == "deDE" then
        if R.spells[spellID].finisher then
            hasRows = text:find("%d+ Punkte?%s*:") ~= nil
            for count, amount, words, secs in text:gmatch("(%d+) Punkte?%s*:%s*(%d+%.?%d*)%s+([^%d\n]-)(%d+%.?%d*) Sek") do
                if words:match("über%s*$") or words:match("im Verlauf von%s*$") then
                    byPoints[tonumber(count)] = { total = tonumber(amount), duration = tonumber(secs) }
                end
            end
        end
        if not hasRows then
            for _, pattern in ipairs({
                "(%d+%.?%d*)([^%d%.\n]-)[Ss]chaden%s+im Verlauf von (%d+%.?%d*) Sek",
                "(%d+%.?%d*)([^%d%.\n]-)[Ss]chaden%s+über (%d+%.?%d*) Sek",
            }) do
                for amount, words, secs in text:gmatch(pattern) do
                    total, school, duration = tonumber(amount), germanSchool(words), tonumber(secs)
                end
            end
            if not total then
                for _, pattern in ipairs({
                    "(%d+%.?%d*) Sek%a*%.? lang([^\n]*)",
                    "im Verlauf von (%d+%.?%d*) Sek%a*%.?([^\n]*)",
                    "über (%d+%.?%d*) Sek%a*%.?([^\n]*)",
                }) do
                    for secs, clause in text:gmatch(pattern) do
                        local amount, words = clause:match("(%d+%.?%d*)([^%d%.\n]-)[Ss]chaden")
                        if amount then total, school, duration = tonumber(amount), germanSchool(words), tonumber(secs) end
                    end
                end
            end
        end
    end
    if hasRows then
        -- A missing or unreadable point count is not a one-point cast; absent rows cannot be extrapolated.
        local entry = integer(comboPoints, 1) and byPoints[comboPoints]
        if not entry then return end
        total, school, duration = entry.total, 1, entry.duration
    elseif not total and type(parseLegacy) == "function" then
        total, school, duration, interval = parseLegacy(original, comboPoints)
    end
    if type(total) ~= "number" or type(duration) ~= "number" or total <= 0 or duration <= 0
        or total ~= total or duration ~= duration or total == math.huge or duration == math.huge then return end
    return total, school or 1, duration, interval
end

function R.Prepare(dot)
    dot.predictionOnly = true
    dot.tickKey, dot.learnedAtApply, dot.shape = nil, nil, nil
end

-- These twelve effects use Pandemic refreshes in the 12.1.0 client data (SimC spell data).
function R.ApplyRefresh(dot, previous, now)
    if previous and previous.predictionOnly then
        local carry = math.min(math.max(0, previous.expiresAt - now), dot.duration * 0.3)
        dot.expiresAt = dot.expiresAt + carry
    end
end

function R.RefreshDue(dot, now)
    local remaining = dot.expiresAt - now
    return remaining > 0 and remaining <= dot.duration * 0.3 + 0.001
end

function R.Remaining(dot, now)
    return dot.total * math.max(0, math.min(1.3, (dot.expiresAt - now) / dot.duration))
end
