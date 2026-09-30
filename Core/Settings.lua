-- BattleInfoTool: the settings window (/bit). One tab per module, in the order the modules'
-- files load. Each tab starts with the module's Enable switch; below it the module builds its own
-- settings (BIT.RegisterTab), the first time the tab is shown, and only while the module runs:
-- a module that is off never ran its code, so it has nothing to show settings for.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
--
-- The window is made of plain frames (no secure templates, no protected calls), so it opens in
-- combat too.

local _, BIT = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local HEADER_HEIGHT = 40
local TAB_HEIGHT = 26
local SWITCH_HEIGHT = 36
local MARGIN = 10
local DEFAULT_TAB = { width = 640, height = 360 }

local window
local tabButtons, pages = {}, {}
local current

---------------------------------------------------------------------------------------------
-- Widgets shared by the modules of the core (StatsInfo, Range)
---------------------------------------------------------------------------------------------

local UI = {}
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
  box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
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
  box:Refresh()
  return box
end

-- A slider with its label above and its value to the right.
function UI.Slider(parent, labelText, min, max, step, get, set, format)
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
  local function show(v) holder.value:SetText(string.format(format or "%d", v)) end
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
  page.switch:Refresh()
  page.stateLine:SetText(stateText(page.name))
  local pending = (BIT.state[page.name] == "on") ~= BIT.IsSwitchedOn(page.name)
  page.reload:SetShown(pending)
end

local function buildPage(name)
  local tab = BIT.tabs[name] or {}
  local page = CreateFrame("Frame", nil, window)
  page:SetPoint("TOPLEFT", MARGIN, -(HEADER_HEIGHT + TAB_HEIGHT))
  page:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
  page:Hide()
  page.name = name

  page.switch = UI.Check(page, "Enable " .. (tab.title or name),
    function() return BIT.IsSwitchedOn(name) end,
    function(v)
      BIT.SetSwitchedOn(name, v)
      refreshSwitch(page)
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

  page.content = CreateFrame("Frame", nil, page)
  page.content:SetPoint("TOPLEFT", 0, -SWITCH_HEIGHT)
  page.content:SetPoint("BOTTOMRIGHT", 0, 0)

  if BIT.IsRunning(name) and type(tab.build) == "function" then
    local ok, err = pcall(tab.build, page.content)
    if not ok then
      BIT.Say("the " .. name .. " settings could not be built: " .. tostring(err))
    end
  else
    local note = page.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", 8, -8)
    note:SetPoint("RIGHT", -8, 0)
    note:SetJustifyH("LEFT")
    note:SetText((tab.summary and (tab.summary .. "\n\n") or "")
      .. "Its settings are here while it runs.")
    page.offNote = note
  end
  refreshSwitch(page)
  return page
end

local function select(name)
  if not pages[name] then pages[name] = buildPage(name) end
  for n, page in pairs(pages) do page:SetShown(n == name) end
  for _, button in ipairs(tabButtons) do
    local on = button.name == name
    button.bg:SetColorTexture(on and 0.2 or 0.1, on and 0.3 or 0.1, on and 0.45 or 0.12, 1)
    button.text:SetTextColor(on and 1 or 0.75, on and 1 or 0.75, on and 1 or 0.75)
  end
  current = name
  refreshSwitch(pages[name])
end

local function createWindow()
  local w, h = tabSize()
  window = CreateFrame("Frame", "BattleInfoToolSettings", UIParent, "BackdropTemplate")
  window:Hide()
  window:SetSize(w + 2 * MARGIN, HEADER_HEIGHT + TAB_HEIGHT + SWITCH_HEIGHT + h + MARGIN)
  window:SetPoint("CENTER")
  window:SetFrameStrata("DIALOG")
  window:SetToplevel(true)
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:SetMovable(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  UI.Backdrop(window, 0.06, 0.97)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "BattleInfoToolSettings") end

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("BattleInfoTool")
  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local x = MARGIN
  for _, name in ipairs(BIT.order) do
    local tab = BIT.tabs[name] or {}
    local button = CreateFrame("Button", nil, window)
    button.name = name
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("CENTER")
    button.text:SetText(tab.title or name)
    button:SetSize(math.max(96, (button.text:GetStringWidth() or 80) + 24), TAB_HEIGHT - 2)
    button:SetPoint("TOPLEFT", x, -HEADER_HEIGHT)
    button:SetScript("OnClick", function() select(name) end)
    x = x + button:GetWidth() + 4
    tabButtons[#tabButtons + 1] = button
  end
  window:SetScript("OnShow", function()
    if current and pages[current] then refreshSwitch(pages[current]) end
  end)
end

-- Opens the window, on a module's tab when name is given; a second call without a name closes it.
function BIT.OpenSettings(name)
  if not window then createWindow() end
  if name and BIT.tabs[name] then
    select(name)
    window:Show()
    return
  end
  if window:IsShown() then
    window:Hide()
    return
  end
  select(current or BIT.order[1])
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
