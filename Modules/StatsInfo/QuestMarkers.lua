-- BattleInfoTool module StatsInfo: over a quest's reward buttons, one small badge that answers
-- the only question the screen asks -- which reward to take: a green up arrow on an upgrade,
-- or a coin on the choice that sells for the most when nothing is an upgrade.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- Written from scratch after the IDEA of Pawn's quest reward advisor (Pawn is CC BY-NC-ND,
-- its code is not copied; the public API shapes it walks are the game's own). Like the bag
-- markers (BagMarkers.lua) the verdict comes from this module's OWN evaluator -- M.Compare,
-- M.SpecRatings and the tri-state M.BagVerdictState against what the character wears -- never
-- another addon's weights, so a badge never disagrees with the tooltip's score lines.
--
-- Decision rules (quest-reward-advisor-r1):
--   * exactly ONE badge per rewards screen (a reward button never carries two), chosen by
--     priority: an upgrade first, the vendor coin only when nothing is an upgrade.
--   * upgrade: a reward whose item M.BagVerdictState rates unequivocally "up" against what is
--     worn in its slot AND which the player can use now (the quest API's isUsable or the
--     client's own C_Item.IsUsableItem; an explicit "cannot use" from either side vetoes).
--     The first such reward in display order gets the arrow: choices before fixed rewards,
--     each in its own index order -- that is also the order the reward buttons are numbered.
--   * coin: the CHOICE with the highest vendor sell price (C_Item.GetItemInfo's 11th return),
--     strictly greater than the rest so a tie keeps the first; only among choices (a fixed
--     reward is granted anyway) and only for a real positive price.
--   * an item above the player's level is never an upgrade: the level gate lives in
--     M.BagVerdictState and applies to bag badges and quest badges alike.
--
-- Placement (clean-room patterns, public API only): the buttons come from
-- QuestInfo_GetRewardButton(QuestInfoFrame.rewardsFrame, Index), Index = i for a choice and
-- i + number-of-choices for a fixed reward, exactly as the quest UI lays its row out. Item
-- links come from the quest APIs where a client hands them over (or the modern
-- C_TooltipInfo quest shapes), else from a private hidden GameTooltip (SetQuestLogItem/
-- SetQuestItem + GetItem) -- the link shape that agrees with what the button shows on every
-- client. The badge is a plain OVERLAY texture on the button (draw sublayer 7, for
-- ElvUI-style skins that repaint a button's own layers), pooled per reward index and reused
-- across displays. No secure frames and no combat restrictions: a texture on someone else's
-- button is ordinary UI, and nothing here moves, protects or anchors a secure frame.

local _, BIT = ...
local M = BIT.Module("StatsInfo")

-- A secret value is never read as a number and never used as a key (the client raises on
-- secret keys and on comparisons with them); ask() runs every game call through pcall so one
-- raising binding can never take the quest frame down with it (the rule BagMarkers.lua uses).
local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, r = pcall(issecretvalue, v)
  return ok and r or false
end

local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g
end

local active = false -- the badges are wanted (module on, setting on AND the live switch on)

-------------------------------------------------------------------------------------------------
-- The badge over a reward button
-------------------------------------------------------------------------------------------------

-- The green up arrow is the same ONE texture the bag markers draw: Interface\Buttons\
-- UI-MicroStream-Green, the game's own small stream arrow (the micro button's download status,
-- FrameXML/MainMenuBarMicroButtons.lua), mirrored vertically so its tip points up -- the file
-- ships pointing down. The coin is the game's own coin icon. A client that cannot take the file
-- on a texture keeps the bag markers' white-primitive fallback (a shaft and three head steps of
-- WHITE8X8, the old geometry).
local UP_TEXTURE = "Interface\\Buttons\\UI-MicroStream-Green" -- mirrored vertically: tip up
local WHITE = "Interface\\Buttons\\WHITE8X8" -- the fallback pieces' primitive
local UP_R, UP_G, UP_B = 0.302, 1, 0.302
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local ARROW_SIZE = 24                      -- the bag badges' corner box, drawn the same way
local ARROW_DX, ARROW_DY = -2, -2          -- TOPRIGHT of the button, 2px inside the corner
-- The FALLBACK's up arrow pieces (tip at the TOP): { width, height, TOPRIGHT-x, TOPRIGHT-y } in
-- the button's corner, edge to edge like the bag badges' fallback.
local UP_PIECES = { { 2, 2, -4, -4 }, { 6, 3, -2, -6 }, { 10, 3, 0, -9 }, { 2, 8, -4, -12 } }
local COIN_SIZE, COIN_DX, COIN_DY = 12, -2, -2

-- One badge per reward index, lazily created and reused: QuestInfo reuses its reward buttons
-- between quests, so the textures are pooled by index (and moved along when another button
-- stands at that index) exactly like the bag markers pool per button. Hide first, show at
-- most one: a hidden badge never leaves stale pixels behind for the next quest.
local overlays = {} -- reward index -> { button, arrow = texture, pieces = {texture x4} on the
                    -- primitive fallback only, coin = texture, mode }
M._questOverlays = overlays -- the tests read these; not part of the addon's interface

-- Which look this client can draw (the bag markers' own rule): the Blizzard file on one
-- texture, or the white-primitive pieces. Decided once, lazily, from the first texture handed
-- the file; a MISSING file is not detectable from Lua (see BagMarkers.lua's decideArrowMode).
local arrowMode -- nil = undecided, else "blizzard" or "primitive"
local function decideArrowMode(t)
  if arrowMode then return end
  ask(t.SetTexture, t, UP_TEXTURE)
  local got = ask(t.GetTexture, t)
  arrowMode = (got ~= nil and got ~= "") and "blizzard" or "primitive"
end

local function hideOverlays()
  for _, o in pairs(overlays) do
    if o.arrow then o.arrow:Hide() end
    for _, t in ipairs(o.pieces or {}) do t:Hide() end
    if o.coin then o.coin:Hide() end
    o.mode = nil
  end
end

-- The fallback's four primitive pieces: created once per overlay and only when this client
-- cannot draw the Blizzard arrow, then pooled like every texture here (never created twice).
local function fallbackPieces(o, button)
  if o.pieces then return o.pieces end
  o.pieces = {}
  for i = 1, #UP_PIECES do
    local t = button:CreateTexture(nil, "OVERLAY")
    -- ElvUI-style skins repaint a button's own OVERLAY layers; draw sublayer 7 keeps the
    -- badge above whatever the skin puts there (the pattern Pawn's overlay uses too).
    if type(t.SetDrawLayer) == "function" then t:SetDrawLayer("OVERLAY", 7) end
    o.pieces[i] = t
  end
  return o.pieces
end

local function overlayFor(index, button)
  local o = overlays[index]
  if o and o.button == button then return o end
  if o then
    -- the reward button pool moved this index to another button: the same textures move too
    o.button = button
    local kids = { o.arrow, o.coin }
    for _, t in ipairs(o.pieces or {}) do kids[#kids + 1] = t end
    for _, t in ipairs(kids) do
      if type(t) == "table" and type(t.SetParent) == "function" then t:SetParent(button) end
    end
    return o
  end
  o = { button = button }
  o.arrow = button:CreateTexture(nil, "OVERLAY")
  o.coin = button:CreateTexture(nil, "OVERLAY")
  for _, t in ipairs({ o.arrow, o.coin }) do
    -- ElvUI-style skins repaint a button's own OVERLAY layers; draw sublayer 7 keeps the
    -- badge above whatever the skin puts there (the pattern Pawn's overlay uses too).
    if type(t.SetDrawLayer) == "function" then t:SetDrawLayer("OVERLAY", 7) end
  end
  overlays[index] = o
  return o
end

local function drawUpgrade(o, button)
  decideArrowMode(o.arrow)
  if arrowMode == "blizzard" then
    for _, t in ipairs(o.pieces or {}) do t:Hide() end
    local t = o.arrow
    t:SetTexture(UP_TEXTURE)
    -- the file ships pointing down (a download chevron): mirrored vertically the tip is at
    -- the top. Set on every draw -- the pooled texture is shared with whatever drew before.
    t:SetTexCoord(0, 1, 1, 0)
    t:SetVertexColor(1, 1, 1, 1) -- the file's own Blizzard green, never tinted here
    t:SetSize(ARROW_SIZE, ARROW_SIZE)
    t:ClearAllPoints()
    t:SetPoint("TOPRIGHT", button, "TOPRIGHT", ARROW_DX, ARROW_DY)
    t:Show()
  else
    -- the white-primitive fallback: the old arrow, unchanged geometry and colours
    o.arrow:Hide()
    local ts = fallbackPieces(o, button)
    for i, p in ipairs(UP_PIECES) do
      local t = ts[i]
      t:SetTexture(WHITE)
      t:SetVertexColor(UP_R, UP_G, UP_B, 1)
      t:SetSize(p[1], p[2])
      t:ClearAllPoints()
      t:SetPoint("TOPRIGHT", button, "TOPRIGHT", p[3], p[4])
      t:Show()
    end
  end
  if o.coin then o.coin:Hide() end
  o.mode = "upgrade"
end

local function drawCoin(o, button)
  if o.arrow then o.arrow:Hide() end
  for _, t in ipairs(o.pieces or {}) do t:Hide() end
  o.coin:SetTexture(COIN)
  o.coin:SetSize(COIN_SIZE, COIN_SIZE)
  o.coin:ClearAllPoints()
  o.coin:SetPoint("TOPRIGHT", button, "TOPRIGHT", COIN_DX, COIN_DY)
  o.coin:Show()
  o.mode = "coin"
end

-------------------------------------------------------------------------------------------------
-- The rewards on screen: counts, info, links
-------------------------------------------------------------------------------------------------

-- The reward counts of the quest on screen: the quest-log shape (GetNumQuestLog*) when the
-- frame shows a quest log entry, the dialog shape (GetNumQuest*) otherwise. Every client has
-- its own argument list for these; each variant is tried in turn and a raising or missing
-- binding just reads as "no such rewards".
local function cleanCount(n)
  if type(n) ~= "number" or isSecret(n) or n ~= n or n == math.huge or n < 0 then return 0 end
  return math.floor(n)
end

local function numRewards(questLog, questID, isChoice)
  local n
  if questLog then
    if isChoice then
      if questID then n = ask(GetNumQuestLogChoices, questID, true) end
      if type(n) ~= "number" and questID then n = ask(GetNumQuestLogChoices, questID) end
      if type(n) ~= "number" then n = ask(GetNumQuestLogChoices) end
    else
      if questID then n = ask(GetNumQuestLogRewards, questID) end
      if type(n) ~= "number" then n = ask(GetNumQuestLogRewards) end
    end
  else
    local fn = isChoice and GetNumQuestChoices or GetNumQuestRewards
    if type(fn) == "function" then n = ask(fn) end
  end
  return cleanCount(n)
end

-- One reward's info (name, texture, count, quality, isUsable, itemID, ...), the same
-- questID tolerance as the counts. The isUsable return is the quest's own answer about
-- whether the player can use the item at all.
local function rewardInfo(questLog, isChoice, index, questID)
  if questLog then
    local fn = isChoice and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
    if type(fn) ~= "function" then return nil end
    if questID then return ask(fn, index, questID) end
    return ask(fn, index)
  end
  if type(GetQuestItemInfo) ~= "function" then return nil end
  return ask(GetQuestItemInfo, isChoice and "choice" or "reward", index)
end

-- A plain item link, or nil. The quest info APIs return six or seven values and none of them
-- is a link on every client; a client that adds one is picked up without a version check.
local function itemLink(v)
  if type(v) ~= "string" or isSecret(v) then return nil end
  if v:find("|Hitem:", 1, true) or v:sub(1, 5) == "item:" then return v end
  return nil
end

local function linkAmong(...)
  for i = 1, select("#", ...) do
    local link = itemLink((select(i, ...)))
    if link then return link end
  end
  return nil
end

-- The modern one-shot shape: C_TooltipInfo's quest calls carry the link on the data itself.
-- Absent or silent on older clients, where the hidden tooltip below answers instead.
local function modernLink(questLog, kind, index)
  local fn
  if questLog then fn = C_TooltipInfo and C_TooltipInfo.GetQuestLogItem
  else fn = C_TooltipInfo and C_TooltipInfo.GetQuestItem end
  if type(fn) ~= "function" then return nil end
  local data = ask(fn, kind, index)
  if type(data) == "table" then return itemLink(data.hyperlink) end
  return nil
end

-- The hidden tooltip shape: a private GameTooltip (never the visible one the player may be
-- reading), filled by the quest UI's own setters and read back with GetItem(). It is the link
-- source that agrees with what the reward button actually shows on every client -- the direct
-- quest answers have been wrong for some quests even where a link exists.
local tipFrame
local function hiddenTooltipLink(kind, index, questLog)
  if not tipFrame then
    local ok, f = pcall(CreateFrame, "GameTooltip", "BattleInfoToolQuestRewardTooltip", nil, "GameTooltipTemplate")
    if ok then tipFrame = f end
  end
  if type(tipFrame) ~= "table" then return nil end
  local setter
  if questLog then setter = tipFrame.SetQuestLogItem
  else setter = tipFrame.SetQuestItem end
  if type(setter) ~= "function" then return nil end
  ask(tipFrame.SetOwner, tipFrame, UIParent or WorldFrame, "ANCHOR_NONE")
  ask(setter, tipFrame, kind, index)
  local _, link = ask(tipFrame.GetItem, tipFrame)
  ask(tipFrame.ClearLines, tipFrame)
  return itemLink(link)
end

-- One reward of the quest on screen: its place on the button row (choices first, then the
-- fixed rewards -- the order QuestInfo_GetRewardButton numbers them in), its link, and what
-- the quest itself says about using it.
local function rewardEntry(kind, index, screenIndex, questLog, questID)
  local name, texture, count, quality, apiUsable, itemID, extra =
    rewardInfo(questLog, kind == "choice", index, questID)
  local link = linkAmong(name, texture, count, quality, apiUsable, itemID, extra)
  if not link then link = modernLink(questLog, kind, index) end
  if not link then link = hiddenTooltipLink(kind, index, questLog) end
  if isSecret(apiUsable) then apiUsable = nil end
  local quantity = not isSecret(count) and (count == nil and 1 or cleanCount(count)) or 0
  return { kind = kind, index = screenIndex, link = link, apiUsable = apiUsable,
    quantity = quantity > 0 and quantity or nil }
end

-------------------------------------------------------------------------------------------------
-- The decision
-------------------------------------------------------------------------------------------------

-- The vendor price: C_Item.GetItemInfo's 11th return. A missing, hidden or malformed price
-- never buys the coin (0 is "nothing to gain" and loses to any real price).
local function sellPriceOf(link)
  if type(link) ~= "string" or isSecret(link) then return nil end
  if not (C_Item and type(C_Item.GetItemInfo) == "function") then return nil end
  local r = { pcall(C_Item.GetItemInfo, link) }
  if not r[1] then return nil end
  local price = r[12] -- pcall's own true is [1]; the sell price is GetItemInfo's 11th return
  if type(price) ~= "number" or isSecret(price) or price ~= price or price == math.huge or price <= 0 then return nil end
  return price
end

-- Usable now: an explicit "cannot use" from the quest itself or from the client's own check
-- vetoes the reward; otherwise one of the two saying "usable" is enough (an unusable item is
-- never an upgrade, but it can still be the coin).
local function usableNow(entry)
  if not entry.link then return false end
  if entry.apiUsable == false then return false end
  if entry.apiUsable == true then return true end
  local usable = ask(C_Item and C_Item.IsUsableItem, entry.link)
  return not isSecret(usable) and usable == true
end

-- An upgrade by THIS module's own evaluator (never another addon's weights): the same
-- tri-state the bag badges use, against what the character wears in the item's slot.
local function isUpgrade(entry)
  if not usableNow(entry) then return false end
  local state, verdict = M.BagVerdictState(entry.link)
  return state == "ok" and type(verdict) == "table" and verdict.verdict == "up"
end

-- What the rewards on screen get: clear every badge first, then show at most one. Called
-- after QuestInfo_Display (when the template draws the rewards block) and on the quest
-- events, coalesced through scheduleRefresh below.
local function updateQuestRewards()
  hideOverlays()
  if not active then return end
  if not (M.settings and M.settings.questMarkers == true) then return end
  if not (BIT.IsRunning("StatsInfo") and BIT.IsSwitchedOn("StatsInfo")) then return end
  if type(QuestInfoFrame) ~= "table" then return end
  local rewardsFrame = QuestInfoFrame.rewardsFrame
  if rewardsFrame == nil then return end
  local questLog = QuestInfoFrame.questLog == true
  local questID = ask(C_QuestLog and C_QuestLog.GetSelectedQuest)
  if type(questID) ~= "number" or isSecret(questID) then questID = nil end
  local nChoices = numRewards(questLog, questID, true)
  local nFixed = numRewards(questLog, questID, false)
  if nChoices + nFixed <= 0 then return end
  local rewards = {}
  for i = 1, nChoices do
    rewards[#rewards + 1] = rewardEntry("choice", i, i, questLog, questID)
  end
  for i = 1, nFixed do
    -- the fixed rewards sit after the choices on the button row (the quest UI's own numbering)
    rewards[#rewards + 1] = rewardEntry("reward", i, i + nChoices, questLog, questID)
  end
  -- One badge on the whole screen: the first upgrade in display order, else the coin on the
  -- most valuable choice. A second upgrade never earns a second badge (one look, one answer),
  -- and a coin never shares the screen with an upgrade.
  local picked, mode
  for _, r in ipairs(rewards) do
    if isUpgrade(r) then
      picked, mode = r, "upgrade"
      break
    end
  end
  if not picked then
    local best, bestPrice = nil, 0
    for _, r in ipairs(rewards) do
      if r.kind == "choice" then
        local unitPrice = sellPriceOf(r.link)
        local price = unitPrice and r.quantity and unitPrice * r.quantity
        if price and price < math.huge and price > bestPrice then best, bestPrice = r, price end
      end
    end
    picked, mode = best, "coin"
  end
  if not picked then return end
  local button = ask(QuestInfo_GetRewardButton, rewardsFrame, picked.index)
  if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return end
  local o = overlayFor(picked.index, button)
  if mode == "upgrade" then drawUpgrade(o, button) else drawCoin(o, button) end
end
M.UpdateQuestRewards = updateQuestRewards -- test seam, not part of the addon's interface

-- QuestInfo_Display draws its blocks from a template list; when the rewards block is among
-- them the reward buttons exist and the badge can be laid out. The scan looks at every entry
-- of the list -- the client's own stride through it is its own business.
local function onQuestInfoDisplay(template)
  if type(QuestInfo_ShowRewards) ~= "function" then return end
  if type(template) ~= "table" or type(template.elements) ~= "table" then return end
  for _, fn in pairs(template.elements) do
    if fn == QuestInfo_ShowRewards then
      updateQuestRewards()
      return
    end
  end
end

-------------------------------------------------------------------------------------------------
-- Refresh, events, lifecycle
-------------------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader.questMarkersLoader = true -- the tests identify the loader by this

local installedHooks, hookedSwitch, scheduled = false, false, false

local function scheduleRefresh()
  if not active then return end
  if scheduled then return end
  scheduled = true
  local function flush()
    scheduled = false
    updateQuestRewards()
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0.05, flush) -- coalesces the quest events; no OnUpdate polling
  else
    flush()
  end
end

-- The quest events are the safety net under the display hook: the reward data can arrive
-- after the screen is up, and the quest itself can change while it is open. An event name the
-- client does not know raises on registration and would kill the whole wiring (see the
-- ITEM_DATA_LOADED note in BagMarkers.lua), so the optional ones are registered only where
-- the client itself vouches for the name (C_EventUtils.IsEventValid).
local CORE_EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_LOG_UPDATE",
  "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED" }
local OPTIONAL_EVENTS = { "QUEST_DATA_READY", "QUEST_DATA_LOAD_RESULT" }

local function ensureEvents()
  if not active then return end
  for _, e in ipairs(CORE_EVENTS) do loader:RegisterEvent(e) end
  pcall(loader.RegisterEvent, loader, "ITEM_DATA_LOAD_RESULT")
  if type(C_EventUtils) == "table" and type(C_EventUtils.IsEventValid) == "function" then
    for _, e in ipairs(OPTIONAL_EVENTS) do
      if ask(C_EventUtils.IsEventValid, e) == true then loader:RegisterEvent(e) end
    end
  end
end

local function clearEvents()
  loader:UnregisterAllEvents()
end

local function installHooks()
  if installedHooks then return end
  installedHooks = true
  if type(hooksecurefunc) == "function" then
    if type(QuestInfo_Display) == "function" then hooksecurefunc("QuestInfo_Display", onQuestInfoDisplay) end
  end
  -- the narrow lifecycle seam BagMarkers.lua uses too: the badges follow the core module
  -- switch immediately (clear / re-enable), while every other module keeps the core's
  -- reload-scoped semantics untouched
  if type(BIT.SetSwitchedOn) == "function" and type(hooksecurefunc) == "function"
      and not hookedSwitch then
    hookedSwitch = true
    hooksecurefunc(BIT, "SetSwitchedOn", function(name, on)
      if name ~= "StatsInfo" then return end
      if on then M.EnableQuestMarkers() else M.DisableQuestMarkers() end
    end)
  end
end

-- The settings box (StatsInfo.lua) and the core module switch call these when the user flips
-- their toggles.
function M.EnableQuestMarkers()
  if not (M.settings and M.settings.questMarkers == true) then
    active = false
    clearEvents()
    hideOverlays()
    return
  end
  active = true
  installHooks()
  ensureEvents()
  scheduleRefresh()
end

function M.DisableQuestMarkers()
  active = false
  clearEvents()
  hideOverlays()
end

loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= BIT.name then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not BIT.ShouldRun("StatsInfo") then self:UnregisterAllEvents() return end
    active = M.settings and M.settings.questMarkers == true
    return
  elseif event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    if not active then self:UnregisterAllEvents() return end
    installHooks()
    ensureEvents()
    return
  end
  if not active then return end
  scheduleRefresh()
end)
