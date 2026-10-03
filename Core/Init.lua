-- BattleInfoTool: one addon made of parts (modules), each of which can be switched off.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- Every module keeps its own namespace, BIT.Module(name), so two modules can both have a "db"
-- or an "L" without meeting. A module's code runs at load like any addon's; at ADDON_LOADED,
-- the first moment the saved settings can be read, it asks BIT.ShouldRun(name) and, when the
-- answer is no, unregisters its events and stays silent. Switching a module on or off takes
-- effect at the next /reload.

local ADDON, BIT = ...
BIT = BIT or {}
BIT.name = ADDON or "BattleInfoTool"
BIT.modules = {} -- name -> the module's namespace
BIT.order = {}   -- module names in the order their files load: the order of the settings tabs
BIT.state = {}   -- name -> "on" | "off", decided at ADDON_LOADED

function BIT.Module(name)
  local m = BIT.modules[name]
  if not m then
    m = { moduleName = name }
    BIT.modules[name] = m
    BIT.order[#BIT.order + 1] = name
  end
  return m
end

local function say(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffBattleInfoTool|r: " .. tostring(msg))
  elseif print then
    print("BattleInfoTool: " .. tostring(msg))
  end
end
BIT.Say = say

---------------------------------------------------------------------------------------------
-- Saved settings: BattleInfoToolDB.modules[name].enabled, and whatever a module of the core
-- keeps there (BIT.Settings(name)). The ported modules keep their own SavedVariables.
---------------------------------------------------------------------------------------------

local function db()
  if type(BattleInfoToolDB) ~= "table" then BattleInfoToolDB = {} end
  local d = BattleInfoToolDB
  if type(d.modules) ~= "table" then d.modules = {} end
  return d
end
BIT.DB = db

-- The settings table of one module in BattleInfoToolDB, created with its defaults.
function BIT.Settings(name, defaults)
  local d = db()
  if type(d.modules[name]) ~= "table" then d.modules[name] = {} end
  local s = d.modules[name]
  for k, v in pairs(defaults or {}) do
    if s[k] == nil then s[k] = v end
  end
  return s
end

function BIT.IsSwitchedOn(name)
  local s = db().modules[name]
  return not (type(s) == "table" and s.enabled == false)
end

function BIT.SetSwitchedOn(name, on)
  BIT.Settings(name).enabled = on and true or false
end

---------------------------------------------------------------------------------------------
-- Switching modules on and off
---------------------------------------------------------------------------------------------

-- Called by a module at ADDON_LOADED: should it run? Remembers the answer for the settings.
function BIT.ShouldRun(name)
  if not BIT.IsSwitchedOn(name) then
    BIT.state[name] = "off"
    return false
  end
  BIT.state[name] = "on"
  return true
end

function BIT.IsRunning(name) return BIT.state[name] == "on" end

-- A module's own slash command while the module is off.
function BIT.SayOff(name)
  say(name .. " is switched off. /bit opens the settings, where it can be switched on.")
end

---------------------------------------------------------------------------------------------
-- Settings tabs: a module registers how to build its settings into a tab (Core/Settings.lua).
---------------------------------------------------------------------------------------------

BIT.tabs = {} -- name -> { title, build = function(parent), onShow, onHide }

function BIT.RegisterTab(name, tab)
  BIT.Module(name) -- keeps the order of the files
  tab.name = name
  BIT.tabs[name] = tab
end

---------------------------------------------------------------------------------------------
-- The core's own start: the saved settings.
---------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == BIT.name then
    db()
    self:UnregisterEvent("ADDON_LOADED")
  end
end)
