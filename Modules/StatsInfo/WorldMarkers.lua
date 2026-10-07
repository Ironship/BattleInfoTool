-- BattleInfoTool module StatsInfo: the bag verdict on loot, need/greed rolls and the merchant.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- Same answer as the bag arrows (M.BagVerdict) and the same Blizzard stream textures
-- (M.PaintVerdictMarker). No second set of weights. Frames are created only out of combat.

local _, BIT = ...
local M = BIT.Module("StatsInfo")

local markers = {}

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function allowed()
  return M.settings and M.settings.worldMarkers ~= false and BIT.IsRunning and BIT.IsRunning("StatsInfo")
end

local function ensure(button)
  if type(button) ~= "table" then return nil end
  local marker = markers[button]
  if marker then return marker end
  if inCombat() then return nil end
  marker = CreateFrame("Frame", nil, button)
  marker:SetSize(24, 24)
  marker:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
  if type(button.GetFrameLevel) == "function" then
    marker:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
  end
  marker:EnableMouse(false)
  marker:Hide()
  markers[button] = marker
  return marker
end

local function paintButton(button, link)
  if type(button) ~= "table" then return end
  if not allowed() or type(link) ~= "string" or link == "" then
    local marker = markers[button]
    if marker and type(marker.Hide) == "function" then marker:Hide() end
    return
  end
  local marker = ensure(button)
  if not marker or type(M.PaintVerdictMarker) ~= "function" or type(M.BagVerdict) ~= "function" then return end
  M.PaintVerdictMarker(marker, M.BagVerdict(link))
end

local function slotLink(reader, slot)
  if type(reader) ~= "function" then return nil end
  local ok, link = pcall(reader, slot)
  if ok and type(link) == "string" then return link end
  return nil
end

local function shownButton(button)
  if type(button) ~= "table" then return false end
  if type(button.IsShown) ~= "function" then return true end
  local ok, shown = pcall(button.IsShown, button)
  return ok and shown ~= false
end

local function paintLoot()
  local n = _G.LOOTFRAME_NUMBUTTONS
  if type(n) ~= "number" or n < 1 or n > 20 then n = 4 end
  for i = 1, n do
    local button = _G["LootButton" .. i]
    if type(button) == "table" then
      -- LootFrame_Update writes button.slot. On a later page that is not the button index.
      local slot = button.slot
      if type(slot) ~= "number" then slot = i end
      local link = shownButton(button) and slotLink(GetLootSlotLink, slot) or nil
      paintButton(button, link)
    end
  end
end

local function paintRolls()
  for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
    local frame = _G["GroupLootFrame" .. i]
    if type(frame) == "table" then
      local rollID = frame.rollID
      local link = slotLink(GetLootRollItemLink, rollID)
      paintButton(frame.IconFrame or frame, link)
    end
  end
end

local function merchantLink(button, index)
  if type(button) == "table" and type(button.link) == "string" and button.link ~= "" then
    return button.link
  end
  local frame = _G.MerchantFrame
  local tab = type(frame) == "table" and frame.selectedTab or nil
  if tab ~= nil and tab ~= 1 then
    return slotLink(GetBuybackItemLink, index)
  end
  local per = _G.MERCHANT_ITEMS_PER_PAGE
  if type(per) ~= "number" or per < 1 or per > 20 then per = 10 end
  local page = type(frame) == "table" and tonumber(frame.page) or 1
  if type(page) ~= "number" or page < 1 then page = 1 end
  return slotLink(GetMerchantItemLink, (page - 1) * per + index)
end

local function paintMerchant()
  local n = _G.MERCHANT_ITEMS_PER_PAGE
  if type(n) ~= "number" or n < 1 or n > 20 then n = 10 end
  for i = 1, n do
    local button = _G["MerchantItem" .. i .. "ItemButton"]
    local link = shownButton(button) and merchantLink(button, i) or nil
    paintButton(button, link)
  end
end

local function refresh()
  if inCombat() then return end
  paintLoot()
  paintRolls()
  paintMerchant()
end

function M.EnableWorldMarkers()
  if not (BIT.IsRunning and BIT.IsRunning("StatsInfo")) then return end
  refresh()
end

function M.DisableWorldMarkers()
  for _, marker in pairs(markers) do
    if type(marker) == "table" and type(marker.Hide) == "function" then marker:Hide() end
  end
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    if not (BIT.IsRunning and BIT.IsRunning("StatsInfo")) then return end
    if type(hooksecurefunc) == "function" then
      if type(LootFrame_Update) == "function" then hooksecurefunc("LootFrame_Update", paintLoot) end
      if type(MerchantFrame_Update) == "function" then hooksecurefunc("MerchantFrame_Update", paintMerchant) end
      if type(GroupLootFrame_OpenNewFrame) == "function" then
        hooksecurefunc("GroupLootFrame_OpenNewFrame", paintRolls)
      end
    end
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_SLOT_CLEARED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("START_LOOT_ROLL")
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("MERCHANT_UPDATE")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    refresh()
    return
  end
  if event == "LOOT_CLOSED" then
    paintLoot()
    return
  end
  refresh()
end)
