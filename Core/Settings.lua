-- BattleInfoTool: the settings window (/bit). One tab per module, in the order the modules'
-- files load, plus a Together tab that is not a module. Each module tab starts with Enable.
-- The module's own settings are built the first time the tab is shown while it runs, and
-- also the moment Enable is ticked while it is still off (a waker fills defaults only;
-- gameplay still starts at the next /reload). Opening a tab that is off does not wake it.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- The window is made of plain frames (no secure templates, no protected calls), so it opens in
-- combat too.

local _, BIT = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local HEADER_HEIGHT = 40
local TAB_HEIGHT = 26
local SWITCH_HEIGHT = 36
local MARGIN = 10
local SCROLL_BAR_WIDTH = 16
local DEFAULT_TAB = { width = 640, height = 360 }
local MAX_CONTENT_HEIGHT = 470 -- the window stays bounded; taller tabs scroll inside it
local MODULE_PREVIEW_GAP = 12 -- OFF-page gap between the appearance editor and a module's own preview scene
local MODULE_PREVIEW_BOTTOM = 8 -- OFF-page bottom allowance below a module's preview scene
local TOGETHER = "__together"

local SHORT_LABEL = {
  SpellDamageInfo = "Spells",
  DoTInfo = "DoTs",
  StatsInfo = "Stats",
  ResourceDing = "Points",
  Range = "Range",
  ShieldsInfo = "Shields",
  HunterRangeFinder = "Hunter",
}

local window
local tabButtons, pages = {}, {}
local current
local tabRows = 1

---------------------------------------------------------------------------------------------
-- Widgets shared by the modules of the core (StatsInfo, Range)
---------------------------------------------------------------------------------------------

local UI = BIT.UI or {} -- Appearance.lua (loaded before this file) may have added members
BIT.UI = UI

function UI.Backdrop(frame, shade, alpha)
  if type(frame.SetBackdrop) ~= "function" then return end
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(shade, shade, shade, alpha or 1)
  frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

function UI.Button(parent, text, width, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

-- A check box with its label to the right. get() and set(value) read and write the setting.
function UI.Check(parent, labelText, get, set, tooltip)
  local box = CreateFrame("CheckButton", nil, parent)
  box:SetSize(24, 24)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  box.label:SetPoint("LEFT", box, "RIGHT", 4, 0)
  box.label:SetText(labelText)
  if tooltip then
    box:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(labelText, 1, 1, 1)
      GameTooltip:AddLine(tooltip, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  function box:Refresh() self:SetChecked(get() and true or false) end
  box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  box:Refresh()
  return box
end

-- A slider with its label above and its value to the right. The optional tooltip (the same
-- extra argument UI.Check takes) explains the setting while the label or the slider is hovered.
function UI.Slider(parent, labelText, min, max, step, get, set, format, tooltip)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(260, 40)
  holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  holder.label:SetPoint("TOPLEFT", 0, 0)
  holder.label:SetText(labelText)
  local bar = CreateFrame("Slider", nil, holder)
  bar:SetOrientation("HORIZONTAL")
  bar:SetSize(200, 16)
  bar:SetPoint("TOPLEFT", 0, -18)
  bar:SetMinMaxValues(min, max)
  bar:SetValueStep(step)
  if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
  bar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.2, 0.2, 0.22, 1)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(6)
  holder.value = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  holder.value:SetPoint("LEFT", bar, "RIGHT", 8, 0)
  local function show(v) holder.value:SetText(UI.SliderLabel(format, v)) end
  -- The label of a slider value. A format ending in a literal "%" means the value is a fraction
  -- or multiplier: the label shows the percent (0.5 -> 50%). Without a format, whole values stay
  -- plain and fractional values are multipliers, shown with an x (1.25 -> 1.25x). A function
  -- formats the value itself. The stored value is never changed by the label.
  function UI.SliderLabel(format, v)
    if type(format) == "function" then return format(v) end
    if type(format) == "string" then
      if string.find(format, "%%", 1, true) then
        return string.format("%d%%", math.floor(v * 100 + 0.5))
      end
      return string.format(format, v)
    end
    if v == math.floor(v) then return string.format("%d", v) end
    local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
    return s .. "x"
  end
  bar:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / step + 0.5) * step
    show(v)
    if holder.refreshing then return end
    set(v)
  end)
  function holder:Refresh()
    self.refreshing = true
    bar:SetValue(get())
    show(get())
    self.refreshing = false
  end
  holder.bar = bar
  -- Hovering the label or the slider shows the tooltip, so neither spot is dead.
  if tooltip then
    local function enter(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(labelText, 1, 1, 1)
      GameTooltip:AddLine(tooltip, nil, nil, nil, true)
      GameTooltip:Show()
    end
    local function leave() GameTooltip:Hide() end
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", enter)
    holder:SetScript("OnLeave", leave)
    bar:SetScript("OnEnter", enter)
    bar:SetScript("OnLeave", leave)
  end
  holder:Refresh()
  return holder
end

---------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------

local function tabSize()
  local w, h = DEFAULT_TAB.width, DEFAULT_TAB.height
  for _, name in ipairs(BIT.order) do
    local tab = BIT.tabs[name]
    if tab then
      w = math.max(w, tab.width or 0)
      h = math.max(h, tab.height or 0)
    end
  end
  h = math.min(h, MAX_CONTENT_HEIGHT)
  return w, h
end

local STATE_TEXT = {
  on = "Running.",
  off = "Switched off.",
}

local function stateText(name)
  local state = BIT.state[name]
  local wanted = BIT.IsSwitchedOn(name)
  if (state == "on") ~= wanted then
    return (wanted and "Switched on" or "Switched off") .. " after a reload of the interface."
  end
  return STATE_TEXT[state] or ""
end

local function refreshSwitch(page)
  if not page.switch then return end
  page.switch:Refresh()
  page.stateLine:SetText(stateText(page.name))
  local pending = (BIT.state[page.name] == "on") ~= BIT.IsSwitchedOn(page.name)
  page.reload:SetShown(pending)
end

local function playerClass()
  if type(UnitClass) ~= "function" then return nil end
  return select(2, UnitClass("player"))
end

local function tabTextColor(name, on)
  local irrelevant = name == "HunterRangeFinder" and playerClass() ~= "HUNTER"
  if on then
    if irrelevant then return 0.62, 0.62, 0.48 end
    return 1, 1, 1
  end
  if irrelevant then return 0.42, 0.42, 0.38 end
  return 0.75, 0.75, 0.75
end

-- A vertical slider on the scroll frame's right. The thumb at the top is the start of the
-- content (WoW's vertical slider keeps its minimum at the bottom, so the value is inverted).
-- Hidden while the content fits. Mouse wheel and the slider move the same offset.
local function attachScroll(page, topOffset)
  local scroll = CreateFrame("ScrollFrame", nil, page)
  scroll:SetPoint("TOPLEFT", 0, -topOffset)
  scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR_WIDTH, 0)
  scroll:EnableMouseWheel(true)
  local content = CreateFrame("Frame", nil, scroll)
  local function contentWidth()
    local w = 0
    if type(scroll.GetWidth) == "function" then w = scroll:GetWidth() or 0 end
    if type(w) ~= "number" or w <= 1 then
      w = (window:GetWidth() or 200) - 2 * MARGIN - SCROLL_BAR_WIDTH
    end
    return math.max(1, w)
  end
  content:SetWidth(contentWidth())
  scroll:SetScrollChild(content)

  local bar = CreateFrame("Slider", nil, page)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(12)
  bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
  bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)
  if type(bar.SetThumbTexture) == "function" then
    bar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Vertical")
  end
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.28, 0.28, 0.32, 1)
  track:SetPoint("TOPLEFT", 4, 0)
  track:SetPoint("BOTTOMRIGHT", -4, 0)

  local function scrollOffset()
    if type(scroll.GetVerticalScroll) ~= "function" then return 0 end
    local v = scroll:GetVerticalScroll()
    if type(v) ~= "number" then return 0 end
    return v
  end
  local function maxScroll()
    return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
  end
  local function syncBar()
    local max = maxScroll()
    bar:SetMinMaxValues(0, math.max(max, 0.001))
    if max <= 0 then bar:Hide() else bar:Show() end
    bar._sync = true
    bar:SetValue(max - math.min(scrollOffset(), max))
    bar._sync = false
  end
  local function setScroll(at)
    local max = maxScroll()
    at = math.min(math.max(at or 0, 0), max)
    if type(scroll.SetVerticalScroll) == "function" then scroll:SetVerticalScroll(at) end
    syncBar()
  end
  scroll:SetScript("OnMouseWheel", function(_, delta)
    setScroll(scrollOffset() - (delta or 0) * 24)
  end)
  scroll:SetScript("OnSizeChanged", function(_, width)
    if type(width) == "number" and width > 0 then content:SetWidth(width) end
    syncBar()
  end)
  bar:SetScript("OnValueChanged", function(_, value)
    if bar._sync or type(value) ~= "number" then return end
    local max = maxScroll()
    if type(scroll.SetVerticalScroll) == "function" then
      scroll:SetVerticalScroll(math.min(math.max(max - value, 0), max))
    end
  end)
  page.scroll, page.content, page.scrollBar = scroll, content, bar
  page.syncScroll = syncBar
  return content
end

local function headerBottom()
  return HEADER_HEIGHT + TAB_HEIGHT * tabRows
end

local function savedWindowPoint()
  if type(BIT.DB) ~= "function" then return nil end
  local saved = BIT.DB()
  local p = type(saved) == "table" and saved.window or nil
  if type(p) ~= "table" or type(p.point) ~= "string" then return nil end
  if type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
  return p
end

local function applyWindowPoint()
  window:ClearAllPoints()
  local p = savedWindowPoint()
  if not p then
    window:SetPoint("CENTER")
    return
  end
  window:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
end

local function rememberWindowPoint()
  if type(window.GetPoint) ~= "function" then return end
  local point, _, relativePoint, x, y = window:GetPoint(1)
  if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return end
  if type(BIT.DB) ~= "function" then return end
  BIT.DB().window = {
    point = point,
    relativePoint = type(relativePoint) == "string" and relativePoint or point,
    x = x,
    y = y,
  }
end

local selectTab

local function buildTogether(page)
  local content = attachScroll(page, 0)
  local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 8, -8)
  title:SetText("Together")
  local blurb = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  blurb:SetPoint("RIGHT", content, "RIGHT", -8, 0)
  blurb:SetJustifyH("LEFT")
  blurb:SetText("Every enabled mark on one nameplate. Offsets use the live seat: the top of a row is -offset under the health bar.")

  local bar = CreateFrame("StatusBar", nil, content)
  bar:SetSize(240, 18)
  bar:SetPoint("TOPLEFT", 28, -78)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(100)
  local barFill = bar:CreateTexture(nil, "BACKGROUND")
  barFill:SetAllPoints()
  barFill:SetColorTexture(0.25, 0.05, 0.05, 1)

  local dotFill = bar:CreateTexture(nil, "ARTWORK")
  dotFill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  dotFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  dotFill:SetWidth(150)
  dotFill:SetColorTexture(0.75, 0.2, 0.25, 0.9)

  local shield = bar:CreateTexture(nil, "OVERLAY")
  shield:SetColorTexture(0.95, 0.85, 0.35, 0.85)

  local rangeIcon = content:CreateTexture(nil, "OVERLAY")
  rangeIcon:SetSize(16, 16)
  rangeIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

  local dots = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dots:SetText("● ● ● ● ○")
  local shards = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  shards:SetText("◆ ◆")
  shards:SetTextColor(0.65, 0.35, 0.9)
  local rail = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  rail:SetTextColor(0.9, 0.75, 0.3)

  local caption = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  caption:SetPoint("TOPLEFT", 8, -112)
  caption:SetPoint("RIGHT", content, "RIGHT", -8, 0)
  caption:SetJustifyH("LEFT")

  local warn = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  warn:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -8)
  warn:SetPoint("RIGHT", content, "RIGHT", -8, 0)
  warn:SetJustifyH("LEFT")

  local function moduleOn(name)
    if BIT.IsRunning(name) then return true end
    return BIT.woke and BIT.woke[name] == true
  end
  local function seat(widget, offset)
    widget:ClearAllPoints()
    widget:SetPoint("TOP", bar, "BOTTOM", 0, -(offset or 0))
  end

  function page:refresh()
    local plate = BIT.Plate or {}
    local hunter, dotOffset, shardOffset = -8, 2, 2
    if type(plate.ReadOffsets) == "function" then
      hunter, dotOffset, shardOffset = plate.ReadOffsets()
    end
    local owns = type(plate.HunterOwnsNameplate) == "function" and plate.HunterOwnsNameplate()
    local dotsOn = moduleOn("DoTInfo")
    local shieldsOn = moduleOn("ShieldsInfo")
    local rangeOn = moduleOn("Range")
    local rdOn = moduleOn("ResourceDing")
    local hunterOn = moduleOn("HunterRangeFinder")

    dotFill:SetShown(dotsOn)
    shield:ClearAllPoints()
    if shieldsOn and dotsOn then
      shield:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
      shield:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
      shield:SetHeight(plate.SHIELD_EDGE or 4)
      shield:Show()
    elseif shieldsOn then
      shield:SetAllPoints(bar)
      shield:Show()
    else
      shield:Hide()
    end

    rangeIcon:ClearAllPoints()
    rangeIcon:SetPoint("BOTTOM", bar, "TOP", 0, 6)
    rangeIcon:SetShown(rangeOn and not owns)

    dots:SetShown(rdOn)
    shards:SetShown(rdOn)
    rail:SetShown(hunterOn)
    if rdOn then
      seat(dots, dotOffset)
      seat(shards, shardOffset)
    end
    if hunterOn then
      seat(rail, hunter)
      if owns then
        rail:SetText("hunter rail")
      elseif playerClass() ~= "HUNTER" then
        rail:SetText("hunter rail (sample, this character is not a hunter)")
      else
        rail:SetText("hunter rail (not attached to the plate)")
      end
    end
    local parts = {}
    if not dotsOn then parts[#parts + 1] = "DoTs off" end
    if not shieldsOn then parts[#parts + 1] = "Shields off" end
    if not rangeOn then parts[#parts + 1] = "Range off" end
    if not rdOn then parts[#parts + 1] = "Points off" end
    if not hunterOn then parts[#parts + 1] = "Hunter off" end
    if owns then parts[#parts + 1] = "Range check hidden: the hunter rail owns this plate" end
    if #parts == 0 then
      caption:SetText("DoT fill stays on the bar. A shield shares that bar as a thin top edge.")
    else
      caption:SetText(table.concat(parts, " · "))
    end
    -- Only rows this plate is actually drawing. A switched-off module is not a clash.
    local clashes = {}
    local function addClash(aOn, aOff, aH, bOn, bOff, bH, text)
      if aOn and bOn and type(plate.Clash) == "function" and plate.Clash(aOff, aH, bOff, bH) then
        clashes[#clashes + 1] = text
      end
    end
    local railH = plate.HUNTER_RAIL_HEIGHT or 16
    local dotH = plate.DOT_ROW_HEIGHT or 14
    local shardH = plate.SHARD_ROW_HEIGHT or 14
    addClash(hunterOn, hunter, railH, rdOn, dotOffset, dotH, "Hunter rail overlaps combo dots.")
    addClash(hunterOn, hunter, railH, rdOn, shardOffset, shardH, "Hunter rail overlaps shard diamonds.")
    addClash(rdOn, dotOffset, dotH, rdOn, shardOffset, shardH, "Combo dots overlap shard diamonds.")
    local clash = #clashes == 0 and "Nameplate lanes are clear." or table.concat(clashes, " ")
    warn:SetText(clash)
    if type(clash) == "string" and clash ~= "Nameplate lanes are clear." then
      warn:SetTextColor(1, 0.75, 0.3)
    else
      warn:SetTextColor(0.6, 0.85, 0.6)
    end
    content:SetHeight(220)
    if page.syncScroll then page.syncScroll() end
  end
  page:refresh()
  return page
end

local function buildPage(name)
  if name == TOGETHER then
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", MARGIN, -headerBottom())
    page:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
    page:Hide()
    page.name = name
    return buildTogether(page)
  end

  local tab = BIT.tabs[name] or {}
  local page = CreateFrame("Frame", nil, window)
  page:SetPoint("TOPLEFT", MARGIN, -headerBottom())
  page:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
  page:Hide()
  page.name = name

  page.switch = UI.Check(page, "Enable " .. (tab.title or name),
    function() return BIT.IsSwitchedOn(name) end,
    function(v)
      BIT.SetSwitchedOn(name, v)
      -- Still running: the page stays, and only the pending-reload line changes.
      -- Ticked on while off: wake defaults and build the real settings.
      -- Ticked off while not running: back to the off note. Gameplay waits for /reload.
      if BIT.IsRunning(name) then
        refreshSwitch(page)
        return
      end
      if v then
        BIT.Wake(name)
      elseif BIT.woke then
        BIT.woke[name] = nil
      end
      page:Hide()
      pages[name] = nil
      selectTab(name)
    end, tab.summary)
  page.switch:SetPoint("TOPLEFT", 4, -6)
  page.stateLine = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  page.stateLine:SetPoint("LEFT", page.switch.label, "RIGHT", 14, 0)
  page.stateLine:SetPoint("RIGHT", page, "RIGHT", -120, 0)
  page.stateLine:SetJustifyH("LEFT")
  page.reload = UI.Button(page, "Reload UI", 100, function()
    if type(ReloadUI) == "function" then ReloadUI() end
  end)
  page.reload:SetPoint("TOPRIGHT", -4, -7)

  local content = attachScroll(page, SWITCH_HEIGHT)

  local viewport = window:GetHeight() - headerBottom() - SWITCH_HEIGHT - 2 * MARGIN
  local function layoutContent()
    local needed = tab.height or DEFAULT_TAB.height
    if page.appearance then
      needed = math.max(needed, 74 + page.appearance:GetHeight())
      if page.modulePreview then
        needed = math.max(needed, 74 + page.appearance:GetHeight() + MODULE_PREVIEW_GAP
          + page.modulePreview:GetHeight() + MODULE_PREVIEW_BOTTOM)
      end
    end
    content:SetHeight(math.max(needed, viewport))
    if page.syncScroll then page.syncScroll() end
  end

  local showLive = (BIT.IsRunning(name) or (BIT.woke and BIT.woke[name])) and type(tab.build) == "function"
  if showLive then
    local ok, err = pcall(tab.build, content)
    if not ok then
      BIT.Say("the " .. name .. " settings could not be built: " .. tostring(err))
    end
  else
    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", 8, -8)
    note:SetPoint("RIGHT", -8, 0)
    note:SetJustifyH("LEFT")
    note:SetText((tab.summary and (tab.summary .. "\n\n") or "")
      .. "Its settings are here while it runs; its appearance and a sample preview are below"
      .. " -- they need no module runtime. Tick Enable to open the settings before the next reload.")
    page.offNote = note
    local refreshModulePreview = nil
    if type(tab.buildPreview) == "function" or type(tab.previewRender) == "function" then
      refreshModulePreview = function()
        local scene = page.modulePreview
        if scene == nil then return end
        if type(tab.previewRender) == "function" then
          local okRender, err = pcall(tab.previewRender, scene, BIT.Style.Resolve(name, tab.legacy))
          if not okRender then
            BIT.Say("the " .. name .. " preview could not render: " .. tostring(err))
          end
        end
        layoutContent()
      end
    end
    page.appearance = BIT.UI.Appearance(content, name, tab.capabilities, refreshModulePreview, tab.legacy)
    page.appearance:SetPoint("TOPLEFT", 8, -74)
    page.appearance.onLayout = layoutContent
    if type(tab.buildPreview) == "function" then
      local ok, scene = pcall(tab.buildPreview, content)
      if ok and type(scene) == "table"
        and type(scene.SetPoint) == "function" and type(scene.GetHeight) == "function" then
        page.modulePreview = scene
        scene:SetPoint("TOPLEFT", page.appearance, "BOTTOMLEFT", 0, -MODULE_PREVIEW_GAP)
        if type(tab.previewRender) == "function" then
          local okRender, err = pcall(tab.previewRender, scene, BIT.Style.Resolve(name, tab.legacy))
          if not okRender then
            BIT.Say("the " .. name .. " preview could not render: " .. tostring(err))
          end
        end
      elseif not ok then
        BIT.Say("the " .. name .. " preview could not be built: " .. tostring(scene))
      end
    end
  end

  layoutContent()
  refreshSwitch(page)
  return page
end

selectTab = function(name)
  if not pages[name] then pages[name] = buildPage(name) end
  for n, page in pairs(pages) do page:SetShown(n == name) end
  for _, button in ipairs(tabButtons) do
    local on = button.name == name
    local r, g, b = tabTextColor(button.name, on)
    button.bg:SetColorTexture(on and 0.2 or 0.1, on and 0.3 or 0.1, on and 0.45 or 0.12, 1)
    button.text:SetTextColor(r, g, b)
  end
  current = name
  local page = pages[name]
  if name == TOGETHER and type(page.refresh) == "function" then page:refresh() end
  refreshSwitch(page)
end

local function addTabButton(name, label, tipTitle, tipBody, extraTip)
  local button = CreateFrame("Button", nil, window)
  button.name = name
  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.text:SetPoint("CENTER")
  button.text:SetText(label)
  local width = math.max(64, (button.text:GetStringWidth() or 48) + 18)
  button:SetSize(width, TAB_HEIGHT - 2)
  button:SetScript("OnClick", function() selectTab(name) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tipTitle or label, 1, 1, 1)
    if tipBody and tipBody ~= "" then GameTooltip:AddLine(tipBody, nil, nil, nil, true) end
    if extraTip then GameTooltip:AddLine(extraTip, 0.8, 0.8, 0.6, true) end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  tabButtons[#tabButtons + 1] = button
  return button
end

local function layoutTabs()
  local maxW = (window:GetWidth() or 400) - MARGIN
  local x = MARGIN
  local row = 0
  for _, button in ipairs(tabButtons) do
    local width = button:GetWidth() or 64
    if x > MARGIN and x + width > maxW then
      x = MARGIN
      row = row + 1
    end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", x, -(HEADER_HEIGHT + row * TAB_HEIGHT))
    x = x + width + 4
  end
  tabRows = row + 1
end

local function createWindow()
  local w, h = tabSize()
  window = CreateFrame("Frame", "BattleInfoToolSettings", UIParent, "BackdropTemplate")
  window:Hide()
  window:SetSize(w + 2 * MARGIN, HEADER_HEIGHT + TAB_HEIGHT + SWITCH_HEIGHT + h + MARGIN)
  window:SetFrameStrata("DIALOG")
  window:SetToplevel(true)
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:SetMovable(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", function(self)
    if type(self.StopMovingOrSizing) == "function" then self:StopMovingOrSizing() end
    rememberWindowPoint()
  end)
  applyWindowPoint()
  UI.Backdrop(window, 0.06, 0.97)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BattleInfoToolSettings") end

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("BattleInfoTool")
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  addTabButton(TOGETHER, "Together", "Together",
    "Every enabled mark on one nameplate, and a warning when their lanes overlap.")
  for _, name in ipairs(BIT.order) do
    local tab = BIT.tabs[name] or {}
    local extra
    if name == "HunterRangeFinder" and playerClass() ~= "HUNTER" then
      extra = "Hunter only. Settings are here for an alt."
    end
    addTabButton(name, SHORT_LABEL[name] or tab.title or name, tab.title or name, tab.summary, extra)
  end
  layoutTabs()
  window:SetHeight(HEADER_HEIGHT + TAB_HEIGHT * tabRows + SWITCH_HEIGHT + h + MARGIN)

  window:SetScript("OnShow", function()
    if current and pages[current] then
      if current == TOGETHER and type(pages[current].refresh) == "function" then
        pages[current]:refresh()
      end
      refreshSwitch(pages[current])
    end
  end)
end

-- Opens the window, on a module's tab when name is given; a second call without a name closes it.
function BIT.OpenSettings(name)
  if not window then createWindow() end
  if name == TOGETHER or (name and BIT.tabs[name]) then
    selectTab(name)
    window:Show()
    return
  end
  if window:IsShown() then
    window:Hide()
    return
  end
  selectTab(current or TOGETHER)
  window:Show()
end

---------------------------------------------------------------------------------------------
-- /bit, and a page in Options > AddOns
---------------------------------------------------------------------------------------------

BIT.commands = {} -- word -> function(rest), from the modules (/bit probe)

function BIT.RegisterCommand(word, fn) BIT.commands[word] = fn end

-- Short names for the tabs: /bit sdi, /bit did, /bit stats, /bit ding, /bit range
BIT.tabWords = {}

local function slash(msg)
  msg = type(msg) == "string" and msg or ""
  local word, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  word = (word or ""):lower()
  if word == "" then BIT.OpenSettings() return end
  if word == "together" or word == "all" then BIT.OpenSettings(TOGETHER) return end
  if BIT.commands[word] then BIT.commands[word](rest) return end
  for _, name in ipairs(BIT.order) do
    if word == name:lower() or BIT.tabWords[word] == name then BIT.OpenSettings(name) return end
  end
  BIT.Say("/bit opens the settings; /bit <part> opens a part's tab ("
    .. table.concat(BIT.order, ", ") .. "); /bit probe records what StatsInfo can read.")
end

SLASH_BATTLEINFOTOOL1 = "/bit"
SLASH_BATTLEINFOTOOL2 = "/battleinfotool"
if type(SlashCmdList) == "table" then SlashCmdList.BATTLEINFOTOOL = slash end

local function registerOptionsPage()
  local panel = CreateFrame("Frame")
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("BattleInfoTool")
  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  text:SetText("The settings have their own window. You can also type /bit.")
  local open = UI.Button(panel, "Open BattleInfoTool settings", 240, function()
    if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and type(HideUIPanel) == "function"
      and not (type(InCombatLockdown) == "function" and InCombatLockdown()) then
      pcall(HideUIPanel, SettingsPanel)
    end
    if not (window and window:IsShown()) then BIT.OpenSettings() end
  end)
  open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
  if type(Settings) == "table" and type(Settings.RegisterCanvasLayoutCategory) == "function"
    and type(Settings.RegisterAddOnCategory) == "function" then
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "BattleInfoTool"))
  elseif type(InterfaceOptions_AddCategory) == "function" then
    panel.name = "BattleInfoTool"
    InterfaceOptions_AddCategory(panel)
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
  local ok, err = pcall(registerOptionsPage)
  if not ok then BIT.Say("Options > AddOns page not added (" .. tostring(err) .. "); /bit still opens the settings.") end
  self:UnregisterAllEvents()
end)

-- For the tests.
BIT._window = function() return window end
BIT._pages = pages
