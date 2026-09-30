"""Copies SpellDamageInfo and ResourceDing into BattleInfoTool, and makes the few
changes they need to live inside it. Every change is listed here, so a module can be brought up
to date with its addon by running this again:

    python tools/port.py [module ...]

Each change must apply exactly as often as listed, or nothing is written: an addon that changed
where a change goes needs a look, not a guess. The files are read from each addon's git HEAD,
never from its working tree, so work in progress there does not leak in.

DoTInfo lives only here and is edited directly in Modules/DoTInfo/* (its standalone port
recipe was removed; port() below guards the module as frozen).

What every module gets:
- its own namespace, BIT.Module(name), in place of the addon's own table;
- its SavedVariables under a BattleInfoTool_ name, so it never shares settings with the
  original addon;
- at ADDON_LOADED, BIT.ShouldRun(name): off, and it
  unregisters its events and stays silent;
- its settings built into its tab of the BattleInfoTool window (BIT.RegisterTab) instead of
  a window or an Options page of its own.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECTS = ROOT.parent
BS = chr(92)


def git_show(repo, path):
    r = subprocess.run(["git", "-C", str(repo), "show", "HEAD:" + path], capture_output=True)
    if r.returncode:
        sys.exit(f"{repo.name}: cannot read {path} at HEAD: {r.stderr.decode(errors='replace')}")
    return r.stdout.decode("utf-8")


def git_head(repo):
    r = subprocess.run(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"], capture_output=True, text=True)
    return r.stdout.strip()


def apply(name, text, edits):
    for edit in edits:
        if callable(edit):  # a change that is easier to say in code: it checks what it needs itself
            text = edit(name, text)
            continue
        old, new = edit[0], edit[1]
        want = edit[2] if len(edit) > 2 else 1
        got = text.count(old)
        if got != want:
            sys.exit(f"{name}: change not applied ({got} matches, {want} wanted):\n{old[:300]}")
        text = text.replace(old, new)
    return text


def header(module, repo, src):
    return (f"-- BattleInfoTool module {module}: ported by tools/port.py from {repo.name}/{src} at "
            f"{git_head(repo)}.\n-- Change it there, or in tools/port.py; an edit made here is lost at the next port.\n")


MODULES = {}

# ---------------------------------------------------------------------------------------------
# ResourceDing
# ---------------------------------------------------------------------------------------------
def rd_replay_secret_guid_fix(name, text):
    """Replays the BIT-only usableGuid fix (Modules/ResourceDing/Core.lua, added with the RD-1
    per-target latch): "secret and nil or value" is value for a secret string -- true and nil or
    value is value -- and the client raises on the first touch of the per-target table (8241
    errors). The standalone repo has not shipped this function yet; where the buggy idiom
    arrives it is replaced exactly once, and any other shape of the helpers stops the port
    (fail closed: a silent pass-through would re-ship the crash at the next port)."""
    buggy = "    if ok then return secret and nil or value end\n"
    fixed = ("    if ok then\n"
             "      if secret then return nil end\n"
             "      return value\n"
             "    end\n")
    got = text.count(buggy)
    if got > 1:
        sys.exit(f"{name}: the secret-GUID idiom appears {got} times; inspect before adapting")
    if got == 1:
        text = text.replace(buggy, fixed)
    if "usableGuid" in text or "isSecret" in text:
        if text.count(buggy) != 0 or text.count("if secret then return nil end") != 1:
            sys.exit(f"{name}: usableGuid changed shape upstream; the fail-closed secret branch "
                     "cannot be reproduced -- inspect before the next port")
    return text


MODULES["ResourceDing"] = {
    "repo": PROJECTS / "ResourceDing",
    "files": [
        # Loaded without the core (ResourceDing's own tests, run by tools/test_modules.py) it
        # behaves as the standalone addon does, apart from the SavedVariables name.
        ("Core.lua", "Core.lua", [
            ('local addonName, Addon = ...\n_G.ResourceDing = Addon\n',
             'local addonName, BIT = ...\n'
             '-- Inside BattleInfoTool its own namespace; loaded on its own, the addon\'s table as before.\n'
             'local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT\n'
             'if not BIT.Module then _G.ResourceDing = Addon end\n'),
            ('ResourceDingDB', 'BattleInfoTool_ResourceDingDB', 7),
            ('    if arg1 ~= addonName then return end\n    initializeDatabase()\n'
             '    if Addon.CreateSettingsPanel then Addon.CreateSettingsPanel() end\n',
             '    if arg1 ~= addonName then return end\n'
             '    -- switched off in BattleInfoTool: silent\n'
             '    if BIT.ShouldRun and not BIT.ShouldRun("ResourceDing") then events:UnregisterAllEvents() return end\n'
             '    initializeDatabase()\n'
             '    -- inside BattleInfoTool the settings are built into its tab when that is first shown\n'
             '    if not BIT.RegisterTab and Addon.CreateSettingsPanel then Addon.CreateSettingsPanel() end\n'),
            # the hooks on Blizzard's combo point display are there from the start; switched off (no
            # settings loaded), they schedule nothing
            ('local function lookAgainLater()\n  if C_Timer and C_Timer.After then',
             'local function lookAgainLater()\n  if not Addon.db then return end\n  if C_Timer and C_Timer.After then'),
            ('SlashCmdList.RESOURCEDING = function(message)\n',
             'SlashCmdList.RESOURCEDING = function(message)\n'
             '  if BIT.IsRunning and not BIT.IsRunning("ResourceDing") then BIT.SayOff("ResourceDing") return end\n'),
            rd_replay_secret_guid_fix,
        ]),
        # the dots under the target's nameplate; started by Core.lua once the module runs
        ("Dots.lua", "Dots.lua", [
            ('local _, Addon = ...\n',
             'local _, BIT = ...\n'
             '-- Inside BattleInfoTool its own namespace; loaded on its own, the addon\'s table as before.\n'
             'local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT\n'),
        ]),
        # a warlock's Soul Shards and the mana level; started by Core.lua once the module runs
        ("Shards.lua", "Shards.lua", [
            ('local _, Addon = ...\n',
             'local _, BIT = ...\n'
             '-- Inside BattleInfoTool its own namespace; loaded on its own, the addon\'s table as before.\n'
             'local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT\n'),
        ]),
        ("Mana.lua", "Mana.lua", [
            ('local _, Addon = ...\n',
             'local _, BIT = ...\n'
             '-- Inside BattleInfoTool its own namespace; loaded on its own, the addon\'s table as before.\n'
             'local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT\n'),
        ]),
        ("Settings.lua", "Settings.lua", [
            ('local Addon = ResourceDing\n', 'local _, BIT = ...\nlocal Addon = BIT.Module("ResourceDing")\n'),
            # named frames of their own, apart from the standalone addon's (a dropdown's legacy frame
            # is named after it)
            ('"ResourceDingSoundDropdown"', '"BattleInfoTool_ResourceDingSoundDropdown"'),
            ('"ResourceDingManaSoundDropdown"', '"BattleInfoTool_ResourceDingManaSoundDropdown"'),
            ('"ResourceDingShardsCheck"', '"BattleInfoTool_ResourceDingShardsCheck"'),
            ('"ResourceDingShardDiamondsCheck"', '"BattleInfoTool_ResourceDingShardDiamondsCheck"'),
            ('"ResourceDingManaCheck"', '"BattleInfoTool_ResourceDingManaCheck"'),
            ('function Addon.CreateSettingsPanel()\n  if Addon.settingsPanel then return Addon.settingsPanel end\n'
             '  local panel = CreateFrame("Frame", "ResourceDingSettingsPanel", UIParent)\n',
             '-- Built into its tab of the BattleInfoTool window.\n'
             'function Addon.CreateSettingsPanel(parent)\n  if Addon.settingsPanel then return Addon.settingsPanel end\n'
             '  local panel = CreateFrame("Frame", nil, parent)\n  panel:SetAllPoints()\n'),
            # The tab's own switch turns the module on and off; this one silences its sounds and hides its marks.
            ('panel.enabled = checkbox(panel, "ResourceDingEnabledCheck", "Enable ResourceDing", -102,',
             'panel.enabled = checkbox(panel, "BattleInfoTool_ResourceDingEnabledCheck", "Sounds, dots and diamonds", -102,'),
            ('"ResourceDingCombatCheck"', '"BattleInfoTool_ResourceDingCombatCheck"'),
            ('"ResourceDingDotsCheck"', '"BattleInfoTool_ResourceDingDotsCheck"'),
            ('  if Settings and Settings.RegisterCanvasLayoutCategory then\n'
             '    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)\n'
             '    Settings.RegisterAddOnCategory(category)\n'
             '    Addon.settingsCategory = category\n'
             '    Addon.settingsCategoryID = category.GetID and category:GetID() or category.ID\n'
             '  elseif InterfaceOptions_AddCategory then\n'
             '    InterfaceOptions_AddCategory(panel)\n'
             '  end\n'
             '  return panel\n'
             'end\n',
             '  panel.refresh()\n  return panel\nend\n'),
            ('function Addon.OpenSettings()\n'
             '  if not Addon.settingsPanel then Addon.CreateSettingsPanel() end\n'
             '  Addon.settingsPanel.refresh()\n'
             '  if Settings and Settings.OpenToCategory and Addon.settingsCategoryID then\n'
             '    Settings.OpenToCategory(Addon.settingsCategoryID)\n'
             '  elseif InterfaceOptionsFrame_OpenToCategory then\n'
             '    InterfaceOptionsFrame_OpenToCategory(Addon.settingsPanel)\n'
             '    InterfaceOptionsFrame_OpenToCategory(Addon.settingsPanel)\n'
             '  end\n'
             'end\n',
             'function Addon.OpenSettings() BIT.OpenSettings("ResourceDing") end\n\n'
             'BIT.RegisterTab("ResourceDing", {\n'
             '  title = "ResourceDing",\n'
             '  summary = "A sound when your combo points are full, and the points as dots under the target; for "\n'
             '    .. "casters a sound when mana climbs to a level, and for warlocks one on each Soul Shard.",\n'
             '  width = 640, height = 410,\n'
             '  build = function(parent) Addon.CreateSettingsPanel(parent) end,\n'
             '})\n'
             'BIT.tabWords.ding = "ResourceDing"\n'),
        ]),
    ],
}


# ---------------------------------------------------------------------------------------------
# SpellDamageInfo
# ---------------------------------------------------------------------------------------------
# Loaded without the core (its own test suite, run by tools/test_modules.py), every file behaves
# as the standalone addon does, apart from the SavedVariables name.

def sdi_sanitize_options_credit(name, text):
    """Options.lua: the standalone addon credits its options window as adapted from the addon it
    was copied from. Inside BattleInfoTool the credit stays; the other addon's name goes."""
    marker = "-- Options window adapted from "
    got = text.count(marker)
    if got != 1:
        sys.exit(f"{name}: the options-window attribution comment is not where it was ({got} matches)")
    i = text.index(marker)
    tail = text[i + len(marker):]
    m = re.match(r"\S+( by Joe Greive \(MIT\)\.)", tail)
    if not m:
        sys.exit(f"{name}: the options-window attribution comment changed shape; inspect before adapting")
    return text[:i] + marker + "a standalone DoT addon" + m.group(1) + tail[m.end():]


def sdi_header(first_line):
    return (first_line, 'local _, BIT = ...\n'
            '-- Inside BattleInfoTool its own namespace; loaded on its own, the addon\'s table as before.\n'
            'local ns = BIT and BIT.Module and BIT.Module("SpellDamageInfo") or BIT or {}\n')


SDI_LIB_HEADER = sdi_header('local _, ns = ...\nns = ns or {}\n')


def sdi_move_content(name, text):
    """Options.lua: the preview and the settings go into buildContent(top), which the standalone
    window calls below its title bar and the BattleInfoTool tab calls at its top."""
    start = '  local pane = CreateFrame("Frame", nil, window, "BackdropTemplate")\n  pane:SetPoint("TOPLEFT", 10, -HEADER_HEIGHT)\n'
    end = '  window:SetScript("OnShow", changed)\n  window:SetScript("OnHide", closeMenu)\nend\n'
    if text.count(start) != 1 or text.count(end) != 1 or text.index(start) > text.index(end):
        sys.exit(f"{name}: the window's content block is not where it was")
    i, j = text.index(start), text.index(end)
    block = text[i:j] + '  window:SetScript("OnShow", changed)\n  window:SetScript("OnHide", closeMenu)\n'
    block = block.replace('pane:SetPoint("TOPLEFT", 10, -HEADER_HEIGHT)', 'pane:SetPoint("TOPLEFT", 10, -top)')
    text = text[:i] + '  buildContent(HEADER_HEIGHT)\nend\n' + text[j + len(end):]
    marker = 'local function createWindow()\n'
    if text.count(marker) != 1:
        sys.exit(f"{name}: createWindow is not where it was")
    fn = ('-- The preview and the settings, in window: the addon\'s own window, below its title bar, or\n'
          '-- inside BattleInfoTool the tab it is built into.\n'
          'local function buildContent(top)\n' + block + 'end\n\n')
    return text.replace(marker, fn + marker)


MODULES["SpellDamageInfo"] = {
    "repo": PROJECTS / "SpellDamageInfo",
    "files": [
        ("Locale.lua", "Locale.lua", [SDI_LIB_HEADER]),
        ("SpellIDs.lua", "SpellIDs.lua", [SDI_LIB_HEADER]),
        ("SpellCoefficients.lua", "SpellCoefficients.lua", [SDI_LIB_HEADER]),
        ("Parser.lua", "Parser.lua", [SDI_LIB_HEADER]),
        ("Estimate.lua", "Estimate.lua", [SDI_LIB_HEADER]),
        ("Core.lua", "Core.lua", [
            ('local ADDON, ns = ...\n',
             'local ADDON, BIT = ...\n'
             '-- Inside BattleInfoTool its own namespace; loaded on its own, the addon\'s table as before.\n'
             'local ns = BIT.Module and BIT.Module("SpellDamageInfo") or BIT\n'),
            ('SpellDamageInfoDB', 'BattleInfoTool_SpellDamageInfoDB', 3),
            ('    if arg1 == ADDON then\n      ns.DecideLangsAtLoad()\n',
             '    if arg1 == ADDON then\n'
             '      -- switched off in BattleInfoTool: silent\n'
             '      if BIT.ShouldRun and not BIT.ShouldRun("SpellDamageInfo") then frame:UnregisterAllEvents() return end\n'
             '      ns.DecideLangsAtLoad()\n'),
            ('if type(SlashCmdList) == "table" then SlashCmdList["SPELLDAMAGEINFO"] = slash end\n',
             'if type(SlashCmdList) == "table" then\n'
             '  SlashCmdList["SPELLDAMAGEINFO"] = function(msg)\n'
             '    if BIT.IsRunning and not BIT.IsRunning("SpellDamageInfo") then BIT.SayOff("SpellDamageInfo") return end\n'
             '    slash(msg)\n'
             '  end\n'
             'end\n'),
        ]),
        ("Options.lua", "Options.lua", [
            ('local _, ns = ...\n',
             'local _, BIT = ...\n'
             '-- Inside BattleInfoTool its own namespace; loaded on its own, the addon\'s table as before.\n'
             'local ns = BIT.Module and BIT.Module("SpellDamageInfo") or BIT\n'),
            sdi_sanitize_options_credit,
            sdi_move_content,
            ('function ns.OpenOptions()\n  if not window then createWindow() end\n',
             'function ns.OpenOptions()\n'
             '  if BIT.OpenSettings then BIT.OpenSettings("SpellDamageInfo") return end\n'
             '  if not window then createWindow() end\n'),
            # Inside BattleInfoTool: no page of its own in Options > AddOns, a tab instead.
            ('local loader = CreateFrame("Frame")\nloader:RegisterEvent("PLAYER_LOGIN")\n',
             'local loader = CreateFrame("Frame")\nif not BIT.RegisterTab then loader:RegisterEvent("PLAYER_LOGIN") end\n'),
            ('-- For the tests.\nns._optionsWindow = function() return window end\n',
             'if BIT.RegisterTab then\n'
             '  BIT.RegisterTab("SpellDamageInfo", {\n'
             '    title = "SpellDamageInfo",\n'
             '    summary = "The damage and healing from each spell\'s description on your action buttons and in its tooltip.",\n'
             '    width = WINDOW_WIDTH, height = WINDOW_HEIGHT - HEADER_HEIGHT + 10,\n'
             '    build = function(parent)\n'
             '      window = parent\n'
             '      buildContent(10)\n'
             '      changed()\n'
             '    end,\n'
             '  })\n'
             '  BIT.tabWords.sdi = "SpellDamageInfo"\n'
             'end\n\n'
             '-- For the tests.\nns._optionsWindow = function() return window end\n'),
        ]),
    ],
}




# A module's files with every change applied, as [(path, bytes)]. Writes nothing: an edit that does
# not apply stops the run before any file changes, so a module is never left half ported.
def port(name):
    if name == "DoTInfo":
        sys.exit("DoTInfo frozen in BIT per user decision: the standalone addon is read-only; edit Modules/DoTInfo/* directly")
    spec = MODULES[name]
    repo = spec["repo"]
    out_dir = ROOT / "Modules" / name
    files = []
    for src, dst, edits in spec["files"]:
        text = apply(f"{name}/{src}", git_show(repo, src), edits)
        if name == "SpellDamageInfo":
            # BIT-only fixes are replayed after the standard embedding edits. Fail closed if
            # an upstream change moves an anchor; never discard macros/Black Arrow/Life Tap.
            import json
            bit_edits = json.loads((ROOT / "tools" / "sdi_bit_edits.json").read_text(encoding="utf-8"))
            text = apply(f"{name}/{src} BIT fixes", text, bit_edits.get(dst, []))
        files.append((out_dir / dst, (header(name, repo, src) + text).encode("utf-8")))
    for src, dst in spec.get("binary", []):
        r = subprocess.run(["git", "-C", str(repo), "show", "HEAD:" + src], capture_output=True)
        if r.returncode:
            sys.exit(f"{name}: cannot read {src}")
        files.append((out_dir / dst, r.stdout))
    return files


if __name__ == "__main__":
    ported = [(name, port(name)) for name in (sys.argv[1:] or list(MODULES))]
    for name, files in ported:
        for path, data in files:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(f"{name} @ {git_head(MODULES[name]['repo'])}: {', '.join(p.relative_to(ROOT / 'Modules' / name).as_posix() for p, _ in files)}")
