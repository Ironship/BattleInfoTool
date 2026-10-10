"""Check native aura bindings and host lifecycle; WoW must verify actual secret rendering."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = ROOT / "tests/test_bit.py"
context = {"__file__": str(fixture)}
exec(compile(fixture.read_text(encoding="utf-8").split(
    'print("-- every module on")', 1)[0], str(fixture), "exec"), context)

NATIVE = r"""
function GetBuildInfo() return '12.1.0', '69933', '', 120100 end
playerClass = 'ROGUE'
SECRET = setmetatable({}, { __index = function() error('secret aura was read') end,
    __tostring = function() error('secret aura was formatted') end })
function issecretvalue(v) return rawequal(v, SECRET) end
nativeLoaded, loadCalls, auraCalls = false, 0, 0
C_AddOns.IsAddOnLoaded = function(name) return name == 'Blizzard_AuraContainer' and nativeLoaded end
C_AddOns.LoadAddOn = function(name)
    assert(name == 'Blizzard_AuraContainer')
    loadCalls = loadCalls + 1
    nativeLoaded = true
end
C_XMLUtil = { GetTemplateInfo = function(name)
    assert(name == 'CustomAuraContainerTemplate')
    return nativeLoaded and {} or nil
end }
C_UnitAuras = setmetatable({}, { __index = function()
    return function() auraCalls = auraCalls + 1; error('addon aura API is restricted') end
end })
C_TooltipInfo = C_UnitAuras
containers, nativeButtons, plateMap = {}, {}, {}
local originalCreateFrame = CreateFrame
function CreateFrame(kind, name, parent, template)
    if kind ~= 'AuraContainer' then return originalCreateFrame(kind, name, parent, template) end
    assert(nativeLoaded and template == 'CustomAuraContainerTemplate')
    local container = originalCreateFrame(kind, name, parent, template)
    container.setUnitCalls, container.refreshCalls = 0, 0
    container.SetUnit = function(self, unit)
        assert(type(unit) == 'string' and not issecretvalue(unit))
        self.unit = unit; self.setUnitCalls = self.setUnitCalls + 1
    end
    container.SetEnabled = function(self, enabled) self.enabled = enabled end
    container.UpdateAllAuras = function(self) self.refreshCalls = self.refreshCalls + 1 end
    container.AddAuraGroup = function(self, key, filter, options)
        assert(self.width == 1 and self.height == 1 and #self.points == 1)
        self.groupKey, self.filter, self.options = key, filter, options
        for i = 1, 10 do
            local button = FakeMock('AuraButton', self)
            local original = getmetatable(button).__index
            local locked = false
            local function check() assert(not locked, 'restricted aura button was accessed') end
            setmetatable(button, { __index = function(t, k)
                check()
                local method = original(t, k)
                if type(method) ~= 'function' then return method end
                return function(...) check(); return method(...) end
            end })
            button.CreateFontString = function(self)
                check()
                local region = FakeMock('FontString', self)
                region.SetFont = function(self, ...) self.fontSet = true end
                return region
            end
            button.SetIcon = function(self, region) check(); self.iconBinding = region end
            button.SetDurationCooldown = function(self, region)
                check(); assert(region.template == 'CooldownFrameTemplate'); self.cooldownBinding = region
            end
            button.SetDurationText = function(self, region)
                check(); assert(region.fontSet); self.durationBinding = region
            end
            button.SetApplicationCount = function(self, region)
                check(); assert(region.fontSet); self.countBinding = region
            end
            options.initializeFrame(button)
            assert(button.width == 18 and button.height == 18)
            assert(button.iconBinding and button.cooldownBinding and button.durationBinding and button.countBinding)
            -- The native engine owns aura values after this point, including visibility.
            locked = true
            table.insert(nativeButtons, button)
        end
    end
    table.insert(containers, container)
    return container
end
units.target, units.nameplate1, units.nameplate2 = { hostile = true }, { hostile = true }, { hostile = false }
target = units.target
function UnitCanAttack(_, unit) return units[unit] and units[unit].hostile end
function C_NamePlate.GetNamePlateForUnit(unit) return plateMap[unit] end
plateA, plateB = NewPlate(), NewPlate()
plateMap.nameplate1, plateMap.nameplate2 = plateA, plateB
function FindContainer(parent)
    for i = #containers, 1, -1 do if rawequal(containers[i].parent, parent) then return containers[i] end end
end
"""


def boot(extra="", retail=True, start=True):
    rt = context["LuaRuntime"](unpack_returned_tuples=True)
    rt.execute(context["FAKE"])
    rt.execute(NATIVE + extra)
    addon = rt.eval("{}")
    loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))"
                     "('UsefulPlatesAndTooltips', addon) end")
    names = ["Core/Init.lua", "Core/PlateLayout.lua"]
    if retail:
        names.append("Modules/DoTInfo/Retail.lua")
    names.append("Modules/DoTInfo/RogueAuras.lua")
    for name in names:
        loader((ROOT / name).read_text(encoding="utf-8"), name, addon)
    dot = addon.Module("DoTInfo")
    dot.db = rt.eval("{ showMarkers = true, nameplateMode = 'markerIcon' }")
    if start and dot.Retail:
        dot.Retail.StartRogueAuras()
    return rt, rt.globals(), dot


rt, game, dot = boot()
game.Fire("PLAYER_ENTERING_WORLD")
target = game.FindContainer(game.TargetFrame)
plate = game.FindContainer(game.plateA)
assert len(game.containers) == 2 and game.loadCalls == 1
assert target.enabled and target.shown and plate.enabled and plate.shown
assert target.unit == "target" and plate.unit == "nameplate1"
assert target.filter == plate.filter == "HARMFUL|PLAYER"
expected = {703, 1943, 2818, 383414, 385627, 360194, 381628, 394021}
assert set(target.options.candidateFilters.includeSpellIDs.keys()) == expected
assert set(plate.options.candidateFilters.includeSpellIDs.keys()) == expected
assert target.points[1][1] == plate.points[1][1] == "BOTTOMLEFT"
assert target.points[1][3] == plate.points[1][3] == "TOPLEFT"
assert target.points[1][5] == plate.points[1][5] == 4
assert len(game.nativeButtons) == 20 and game.auraCalls == 0
print("ok target and hostile nameplates bind eight actual rogue auras to native icons/timers/stacks above health bars")

# A custom nameplate hides Blizzard's bar but leaves a larger health widget visible.
platy_rt, platy_game, platy_dot = boot("""
    Platynator = {}
    hiddenHost = FakeMock('hiddenHost')
    hiddenHost:Hide()
    plateA.UnitFrame.healthBar:SetParent(hiddenHost)
    display = FakeMock('PlatyDisplay', plateA)
    customBar = FakeMock('PlatyHealth', display)
    customBar:SetFrameStrata('HIGH')
    display.widgets = { { details = { kind = 'health' }, statusBar = customBar } }
    plateA.GetChildren = function() return display end
""")
platy_container = platy_game.FindContainer(platy_game.plateA)
assert platy_game.Same(platy_container.points[1][2], platy_game.customBar)
assert platy_container.strata == platy_game.customBar.strata
assert platy_container.enabled and not platy_game.plateA.UnitFrame.healthBar.IsVisible(platy_game.plateA.UnitFrame.healthBar)
platy_rt.execute("""
    replacement = FakeMock('ReplacementPlatyHealth', display)
    display.widgets[1].statusBar = replacement
""")
platy_dot.Retail.UpdateRogueAuras()
assert not platy_container.enabled and not platy_container.shown
platy_container = platy_game.FindContainer(platy_game.plateA)
assert platy_game.Same(platy_container.points[1][2], platy_game.replacement) and platy_container.enabled
platy_game.display.Hide(platy_game.display)
platy_dot.Retail.UpdateRogueAuras()
assert not platy_container.enabled and not platy_container.shown
print("ok rogue aura icons select the active Platynator bar and retire bindings when its widget changes or hides")

unit_calls, refreshes, containers = target.setUnitCalls, target.refreshCalls, len(game.containers)
for _ in range(10):
    dot.Retail.UpdateRogueAuras()
assert target.setUnitCalls == unit_calls and target.refreshCalls == refreshes
assert len(game.containers) == containers
game.Fire("PLAYER_TARGET_CHANGED")
assert target.refreshCalls > refreshes and target.setUnitCalls == unit_calls
assert game.auraCalls == 0
print("ok repeated updates avoid new containers/unit/layout writes; target changes explicitly refresh native assignments")

dot.db.showMarkers = False
dot.Retail.UpdateRogueAuras()
assert not target.enabled and not target.shown and not plate.enabled and not plate.shown
dot.db.showMarkers = True
dot.db.nameplateMode = "off"
dot.Retail.UpdateRogueAuras()
assert target.enabled and target.shown and not plate.enabled and not plate.shown
dot.db.nameplateMode = "marker"
dot.Retail.UpdateRogueAuras()
assert plate.enabled and plate.shown
print("ok shared marker and nameplate settings hide and restore native rogue displays independently")

game.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert not plate.enabled and not plate.shown
rt.execute("plateMap.nameplate3 = plateA; units.nameplate3 = { hostile = true }")
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
assert game.Same(game.FindContainer(game.plateA), plate)
assert plate.unit == "nameplate3" and plate.enabled
refreshes = plate.refreshCalls
game.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
assert plate.refreshCalls >= refreshes and plate.enabled
rt.execute("units.nameplate1 = nil; units.nameplate3 = nil; plateMap.nameplate3 = nil")
game.Fire("PLAYER_ENTERING_WORLD")
assert not plate.enabled and not plate.shown
print("ok plate removal, same-frame token reuse and world transitions cannot leave a former unit's icons enabled")

rt, game, dot = boot()
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
old_target, old_plate = game.FindContainer(game.TargetFrame), game.FindContainer(game.plateA)
rt.execute("""
TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar = FakeMock('replacementTarget', TargetFrame)
plateA.UnitFrame.healthBar = nil
plateA.UnitFrame.HealthBarsContainer = { healthBar = FakeMock('replacementPlate', plateA) }
""")
dot.Retail.UpdateRogueAuras()
assert not old_target.enabled and not old_target.shown and not old_plate.enabled and not old_plate.shown
assert game.FindContainer(game.TargetFrame).enabled and game.FindContainer(game.plateA).enabled
rt.execute("TargetFrame = nil; plateA.IsForbidden = function() return true end")
dot.Retail.UpdateRogueAuras()
assert not game.containers[3].enabled and not game.containers[4].enabled
print("ok replaced health bars, vanished target frames and forbidden nameplate hosts retire old native displays")

rt, game, dot = boot("""
plateMap.nameplate1 = nil
units.target.hostile = SECRET
""")
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert len(game.containers) == 0
rt.execute("plateMap.nameplate1 = plateA; units.target.hostile = true")
dot.Retail.UpdateRogueAuras()
assert len(game.containers) == 2
game.Fire("NAME_PLATE_UNIT_ADDED", game.SECRET)
game.Fire("NAME_PLATE_UNIT_REMOVED", game.SECRET)
assert game.FindContainer(game.plateA).enabled and game.auraCalls == 0
print("ok hidden hostility/tokens fail closed while late-created nameplate hosts become visible on the shared refresh")

rt, game, dot = boot("combat = true; TargetFrame.IsProtected = function() return true end")
assert game.FindContainer(game.TargetFrame) is None
assert game.FindContainer(game.plateA).enabled
rt.execute("combat = false")
game.Fire("PLAYER_REGEN_ENABLED")
assert game.FindContainer(game.TargetFrame).enabled
print("ok protected target setup during combat is deferred and retried after combat")

rt, game, dot = boot("""
units.nameplate1 = nil
workingCreateFrame = CreateFrame
function CreateFrame(kind, ...)
    local frame = workingCreateFrame(kind, ...)
    if kind == 'AuraContainer' then frame.AddAuraGroup = function() error('native initializer failed') end end
    return frame
end
""")
assert len(game.containers) == 1 and not game.containers[1].enabled and not game.containers[1].shown
for _ in range(10):
    dot.Retail.UpdateRogueAuras()
assert len(game.containers) == 1
rt.execute("CreateFrame = workingCreateFrame")
game.Fire("PLAYER_REGEN_ENABLED")
assert len(game.containers) == 2 and game.FindContainer(game.TargetFrame).enabled
print("ok initializer failures retire their container and cannot allocate batches repeatedly; lifecycle retry recovers")

rt, game, dot = boot("""
C_XMLUtil.GetTemplateInfo = function() return nil end
""")
assert len(game.containers) == 0
rt.execute("C_XMLUtil.GetTemplateInfo = function() return {} end")
game.Fire("PLAYER_REGEN_ENABLED")
assert game.FindContainer(game.TargetFrame).enabled and game.FindContainer(game.plateA).enabled
count = len(game.containers)
game.Fire("PLAYER_ENTERING_WORLD")
dot.Retail.StartRogueAuras()
assert len(game.containers) == count and game.loadCalls == 1 and game.auraCalls == 0
print("ok a temporarily unavailable native template starts on the next lifecycle event without duplicate setup")

rt, game, dot = boot("""
TargetFrame.IsProtected = function() return true end
blockedShow = 0
local factory = CreateFrame
function CreateFrame(kind, name, parent, template)
    local frame = factory(kind, name, parent, template)
    if kind == 'AuraContainer' and parent == TargetFrame then
        local show = frame.Show
        frame.Show = function(self)
            if combat then blockedShow = blockedShow + 1; return end
            return show(self)
        end
    end
    return frame
end
""")
target = game.FindContainer(game.TargetFrame)
dot.db.showMarkers = False
dot.Retail.UpdateRogueAuras()
assert not target.shown
game.combat = True
dot.db.showMarkers = True
dot.Retail.UpdateRogueAuras()
assert target.enabled and not target.shown and game.blockedShow == 0
game.combat = False
game.Fire("PLAYER_REGEN_ENABLED")
assert target.shown and game.blockedShow == 0
print("ok protected visibility is deferred without treating a silently blocked Show as success")

for extra in ("playerClass = 'WARLOCK'", "playerClass = SECRET", "C_XMLUtil = nil",
              "C_XMLUtil.GetTemplateInfo = function() error('missing template') end"):
    rt, game, dot = boot(extra)
    game.Fire("PLAYER_ENTERING_WORLD")
    dot.Retail.UpdateRogueAuras()
    assert len(game.containers) == 0 and game.auraCalls == 0
rt, game, dot = boot("", retail=False)
assert dot.Retail is None and len(game.containers) == 0 and game.loadCalls == 0
rt, game, dot = boot("", start=False)
dot.off = True
dot.Retail.StartRogueAuras()
assert len(game.containers) == 0 and game.loadCalls == 0
print("ok non-rogues, hidden class, absent native APIs, disabled modules and Classic stay silent")

rt = context["LuaRuntime"](unpack_returned_tuples=True)
rt.execute(context["FAKE"] + NATIVE)
addon = rt.eval("{}")
loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))"
                 "('UsefulPlatesAndTooltips', addon) end")
for name in (ROOT / "UsefulPlatesAndTooltips_Mainline.toc").read_text(encoding="utf-8").splitlines():
    if name.strip() and not name.startswith("#"):
        name = name.strip().replace("\\", "/")
        loader((ROOT / name).read_text(encoding="utf-8"), name, addon)
game = rt.globals()
game.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
game.Fire("PLAYER_ENTERING_WORLD")
assert game.FindContainer(game.TargetFrame).enabled and game.FindContainer(game.plateA).enabled
game.Fire("PLAYER_TARGET_CHANGED")
game.Tick(0.3)
assert game.auraCalls == 0
print("ok the real Mainline loader starts native rogue displays and its shared refresh leaves hidden aura state untouched")
