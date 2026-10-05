-- BattleInfoTool module StatsInfo: over the game's own bag buttons, a small arrow that
-- tells whether the item is an upgrade for some spec against what is worn in that slot,
-- and, on an upgrade, one beneficiary-spec icon (Blizzard assets only).
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- Loaded after StatsInfo.lua (see BattleInfoTool.toc). Everything here uses the module's
-- own existing evaluator (M.Compare, M.SpecRatings and their generated Weights.lua) and the
-- tooltip's own 0.05% display threshold, so a badge never disagrees with the tooltip's
-- score lines. The meaning is "against what you wear in that slot", never a BiS claim.
--
-- Verdict rules (stats-bag-marker-r1, binding):
--   * per spec: UP only when at least one rating part is positive and none is negative;
--     DOWN only when at least one is negative and none positive; a tank whose survival
--     and threat parts push opposite ways is AMBIGUOUS and gets no verdict. Secret,
--     missing, malformed or nonfinite data is unknown, never numerically coerced.
--   * overall: green (UP) when at least one spec has an unequivocal UP in at least one
--     legal replacement comparison; red (DOWN) only when every replacement path is
--     strictly worse for every evaluated spec (no positive, neutral, ambiguous or
--     unknown path). Equal is no arrow.
--   * fallback: when every weighted rating is neutral because the changed stats are not
--     modelled (armor-only cloth on a damage class), a conservative raw-diff dominance
--     decides per path: some positive and none negative -> up, some negative and none
--     positive -> down. It never overrides contradictory nonzero weighted parts.
--   * a druid Restoration gain is the heuristic's approximate score: the badge shows the
--     spec icon with a tiny "~" (never a claim of measured healing), the exact meaning
--     stays in the settings legend and the tooltip marks "(approx.)".
--
-- The green UP arrow is the button's OWN native UpgradeIcon (Blizzard ships one on
-- every native container button; Pawn-style, clean-room -- Pawn is CC BY-NC-ND,
-- its code is not copied): no custom green pixels, no invented atlas. The red
-- DOWN arrow stays custom (the native icon is green-only), drawn from the native
-- WHITE8X8 primitive, vertex-coloured like the tooltip's red. Never the native
-- JunkIcon/new-item textures or their positions. The badge fits the top-right
-- corner, small and noninteractive. The beneficiary icon is the spec's own
-- row.spec.icon.
--
-- Native integration (primaries: forever-mainline-container.lua/XML, pinned Gethe
-- wow-ui-source 966519cf0ad2c10301ea011a88c14b25697c9687; the Camelot override only
-- touches the portrait and the combined-footer jump hints): the refresh reads the
-- buttons the client itself enumerates (ContainerFrameUtil_EnumerateContainerFrames ->
-- EnumerateValidItems, individual and combined frames alike) and the hyperlink the
-- client itself reads at UpdateItems (C_Container.GetContainerItemInfo; the classic
-- global as a guarded fallback). It is driven by secure post-hooks only
-- (hooksecurefunc on the mixin's UpdateItems, on ContainerFrame_UpdateAll, and on
-- ContainerFrame_Update when the enumerator is absent -- the legacy path marks only
-- buttons whose bag identity the button itself can give), plus event-driven/coalesced
-- refreshes (bag changes, item data arrival, equipment swap, spec change, bag close,
-- combat-regen for deferred creation). No OnUpdate polling, no scans while the module
-- or the setting is off, no touching of the buttons' identities, scripts or overlays.

local _, BIT = ...
local M = BIT.Module("StatsInfo")

local THRESHOLD = 0.05 -- the tooltip's display threshold (changesNothing in StatsInfo.lua)

-- A secret value is never touched: issecretvalue is asked inside a pcall (as in
-- ResourceDing/Core.lua:179-184), so a client whose own check raises still reads as
-- "not secret" here, never as an error out of a bag handler.
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

-------------------------------------------------------------------------------------------------
-- Safe arithmetic: the values the real evaluator (M.Compare / M.SpecRatings with the real
-- M.SPECS weights) can hold. A stat that could push any of its multiplications past the
-- double range must be rejected as unknown BEFORE the capped percent can conceal it.
-------------------------------------------------------------------------------------------------

local active = false -- the badge part is running (module on, setting on AND the live switch on)

-- Defined in the sections below; the readiness/arrival machinery needs them while it is
-- defined earlier (Lua locals are captured by reference, so these forward declarations
-- keep the closures bound to the real functions, not to nil globals).
local scheduleRefresh, requestBaganatorRefresh

local safeBound
local function safeStatBound()
  if safeBound then return safeBound end
  local _, class = ask(UnitClass, "player")
  local specs = type(class) == "string" and M.SPECS and M.SPECS[class]
  local maxW = 0
  for _, spec in ipairs(specs or {}) do
    for _, kind in ipairs({ "survival", "threat", "damage", "healing" }) do
      local measure = spec[kind]
      if type(measure) == "table" and type(measure.weights) == "table" then
        for _, w in pairs(measure.weights) do
          if type(w) == "number" and math.abs(w) > maxW then maxW = math.abs(w) end
        end
        for _, key in ipairs({ "mainHand", "offHand", "ranged" }) do
          local w = measure[key]
          if type(w) == "number" and math.abs(w) > maxW then maxW = math.abs(w) end
        end
      end
    end
  end
  -- The evaluator multiplies a stat by a weight, sums about sixty such terms (two items,
  -- both hands, several stats) and multiplies the result by 100 for the percent: a safe
  -- value must keep every step finite. Derived from the REAL weights: no invented cap.
  local bound = 1.7e308 / ((maxW * 100) + 1) / 64
  if not (bound > 1) then bound = 1.7e308 / 64 end -- no weighted measure: raw diffs only
  safeBound = bound
  return bound
end

-------------------------------------------------------------------------------------------------
-- The verdict
-------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------
-- Data readiness: every answer is one of
--   "ok"   the item's stats are real, finite, non-secret and loadable -> classify
--   "wait" the data may still arrive: a bounded/coalesced request is (or was) issued and
--          the arrival events re-run the evaluation
--   "dead" a permanent unknown: secret/malformed/nonfinite data, or a state that stayed
--          unresolved after arrival -- never retried, never read as a zero
-------------------------------------------------------------------------------------------------

-- The candidate/worn item id for the cache check and the load request: the client's own
-- answer first, then the classic link's own item:<id> (the hyperlink shape is defined by
-- the client; the id needs no cached data to parse).
local function itemIDOf(link)
  if type(link) ~= "string" then return nil end
  local id = ask(C_Item and C_Item.GetItemInfoInstant, link)
  if type(id) == "number" then return id end
  return tonumber(link:match("^item:(%d+):")) or tonumber(link:match("item:(%d+):"))
end

-- C_Item.IsItemDataCachedByID boundary: "proceed" | "wait" | "dead". A FAILED available
-- API (error/nil) stays unknown: it must never read as an implicit "ready".
local function cacheState(link)
  if not (C_Item and type(C_Item.IsItemDataCachedByID) == "function") then return "proceed" end
  local id = itemIDOf(link)
  if not id then return "proceed" end -- nothing to verify against; the stats check decides
  local cached = ask(C_Item.IsItemDataCachedByID, id)
  if cached == nil then return "dead" end
  if isSecret(cached) then return "dead" end
  if cached == false then return "wait" end
  return "proceed"
end

-- Bounded, coalesced missing-data requests (candidate AND worn). wanted/outstanding are
-- flushed by ONE timer; arrived marks that the client's arrival event came back for the
-- id, after which an unresolved state is FINAL (never a nil-retry loop forever).
local REQUEST_FLUSH_DELAY = 0.1
local REQUEST_FLUSH_MAX = 20
local MAX_WAIT_STATE = 30
local wanted, outstanding, arrived, waits = {}, {}, {}, {}
local flushTimer = false

local function scheduleRequestFlush()
  if flushTimer then return end
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
    flushTimer = false
    return
  end
  flushTimer = true
  C_Timer.After(REQUEST_FLUSH_DELAY, function()
    flushTimer = false
    local sent = 0
    for id in pairs(wanted) do
      if sent >= REQUEST_FLUSH_MAX then
        scheduleRequestFlush() -- the rest goes on the next tick (bounded per flush)
        return
      end
      wanted[id] = nil
      outstanding[id] = true
      sent = sent + 1
      ask(C_Item and C_Item.RequestLoadItemDataByID, id)
    end
  end)
end

local function requestState(link)
  if not active then return "dead" end
  local id = itemIDOf(link)
  if not id then return "dead" end
  -- A secret id must never key the plain request tables (arrived/waits/outstanding/wanted):
  -- the client raises "cannot be indexed with secret keys" on any touch, and type() reads a
  -- secret number as a number. Asked once here, before any of them is indexed at all.
  if isSecret(id) then return "dead" end
  if arrived[id] then return "dead" end
  if waits[id] and waits[id] >= MAX_WAIT_STATE then return "dead" end
  if outstanding[id] or wanted[id] then return "wait" end
  wanted[id] = true
  scheduleRequestFlush()
  return "wait"
end

-- One link's readiness: stats shape first (malformed/secret/nonfinite/huge values are a
-- PERMANENT unknown; an EMPTY {} table is the API-failure shape and waits for arrival),
-- then the cache boundary, then the request machine.
local function itemReadiness(link)
  if type(link) ~= "string" or isSecret(link) then return "dead" end
  local stats = ask(C_Item and C_Item.GetItemStats, link)
  if type(stats) ~= "table" then stats = ask(GetItemStats, link) end
  if type(stats) ~= "table" then
    if not ((C_Item and type(C_Item.GetItemStats) == "function") or type(GetItemStats) == "function") then
      return "dead" -- no stats API anywhere: nothing can ever be known
    end
    return requestState(link)
  end
  local bound = safeStatBound()
  local n = 0
  for _, v in pairs(stats) do
    n = n + 1
    if isSecret(v) then return "dead" end
    if type(v) ~= "number" then return "dead" end
    if v ~= v or v == math.huge or v == -math.huge then return "dead" end
    if math.abs(v) > bound then return "dead" end
  end
  if n == 0 then return requestState(link) end -- {}: unloaded/failed, not a zero-stat item
  local cached = cacheState(link)
  if cached == "wait" then return requestState(link) end -- not cached -> request it
  if cached ~= "proceed" then return cached end
  return "ok"
end

-- The arrival events (ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED): forget the pending
-- request, mark the id as arrived-once, and wake both renderers.
local function onItemDataArrived(id)
  -- Same secret-id rule as requestState: type() reads a secret number as a number, and a
  -- secret id must never key outstanding/wanted/arrived below ("cannot be indexed with
  -- secret keys"), so it is asked once here, before any of them is touched.
  if type(id) ~= "number" or isSecret(id) then return end
  if outstanding[id] or wanted[id] then
    outstanding[id] = nil
    wanted[id] = nil
    arrived[id] = true
  end
  scheduleRefresh()
  requestBaganatorRefresh()
end

-- One spec's verdict from its rating parts (rows of M.SpecRatings): "up" when at least
-- one part is positive and none is negative, "down" when at least one is negative and
-- none positive, "none" otherwise (nothing changes, or the parts push opposite ways).
local function specVerdict(parts)
  local up, down, approx = false, false, false
  for _, p in ipairs(parts) do
    local v = p.percent or 0
    if p.approx then approx = true end
    if v >= THRESHOLD then up = true
    elseif v <= -THRESHOLD then down = true end
  end
  if up and not down then return "up", approx end
  if down and not up then return "down", approx end
  return "none", approx
end

-- Stat keys the model prices for this class (any spec, any measure, nonzero):
-- only their losses can veto an arrow. An unmodelled loss (3 armor the class
-- never converts) still prints its line, but never blocks an upgrade alone.
local function modelledKeys()
  local _, class = ask(UnitClass, "player")
  local specs = type(class) == "string" and M.SPECS and M.SPECS[class]
  local set = {}
  if specs then for _, spec in ipairs(specs) do
    for _, mname in ipairs({ "damage", "survival", "threat", "healing" }) do
      local m = spec[mname]
      if type(m) == "table" then
        if type(m.weights) == "table" then
          for k, v in pairs(m.weights) do if v ~= 0 then set[k] = true end end
        end
        if (m.mainHand or 0) ~= 0 or (m.offHand or 0) ~= 0 or (m.ranged or 0) ~= 0 then
          set["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = true
        end
      end
    end
  end end
  return set
end

-- One replacement path's verdict; nil when the ratings cannot be computed (the class is
-- not known, or it has no SPECS entry): that path is unknown and no arrow may use it.
local function comparisonVerdict(link, c)
  local ratings = M.SpecRatings(link, c.against, c.slots, c.offHand)
  if not ratings then return nil end
  local sawUp, sawDown, sawNeutral, sawSignificant = false, false, false, false
  local upSpecs = {}
  for _, row in ipairs(ratings) do
    local v, approx = specVerdict(row.parts)
    if v == "up" then
      sawUp = true
      upSpecs[#upSpecs + 1] = { spec = row.spec, approx = approx }
    elseif v == "down" then
      sawDown = true
    else
      sawNeutral = true
    end
    -- any part beyond the display threshold, whatever its direction, counts as a
    -- modelled opinion: it blocks the raw fallback (a contradictory nonzero answer is
    -- never overridden by a raw-diff guess)
    for _, p in ipairs(row.parts) do
      local pv = p.percent or 0
      if pv >= THRESHOLD or pv <= -THRESHOLD then sawSignificant = true end
    end
  end
  if sawUp then return { verdict = "up", upSpecs = upSpecs } end
  if sawDown and not sawNeutral then return { verdict = "down" } end
  if sawDown or sawSignificant then return { verdict = "none" } end
  -- Every rated part is neutral: the changed stats are not modelled for these specs
  -- (armor-only cloth on a damage class). The conservative raw-diff dominance
  -- fallback, per path: up if some diff is positive and no MODELLED diff is negative
  -- (an unmodelled loss never vetoes alone: 3 armor a rogue never converts cannot block
  -- +2 stamina, though its line still prints). Off-armor with stats therefore gets arrows
  -- too -- an up arrow only.
  local modelled = modelledKeys()
  local pos, negModelled = false, false
  for _, d in ipairs(c.diffs) do
    if d.diff > 0 then pos = true
    elseif d.diff < 0 and modelled[d.key] then negModelled = true end
  end
  if pos and not negModelled then return { verdict = "up", fallback = true } end
  -- No arrow when every modelled opinion is neutral (never invent a down for zero-opinion
  -- items): the legend's red down is "every replacement path is strictly worse for every
  -- spec" (StatsInfo.lua:1262), and raw diffs with no opinion behind them cannot prove
  -- that. Zero gains (not pos) is that case: no plus, no arrow.
  return { verdict = "none", fallback = true }
end

-- The level gate (the bag badges and the quest reward badges share it): an item whose
-- required level is above the player's cannot be worn yet, so it never gets a badge -- it
-- reads "dead", no verdict and no retry. A requirement the client hides is unknown and never
-- coerced; a player level the client will not answer for is not a gate (nothing is proven
-- against it), and an item with no requirement on record passes to the other gates.
local function levelGate(link)
  local _, _, _, _, minLevel = ask(C_Item and C_Item.GetItemInfo, link)
  if isSecret(minLevel) then return "dead" end
  if minLevel == nil then return "ok" end
  if isSecret(minLevel) then return "dead" end
  if type(minLevel) ~= "number" or minLevel ~= minLevel
      or minLevel == math.huge or minLevel == -math.huge then
    return "dead" -- a malformed requirement is unknown, never a number to compare with
  end
  local level = ask(UnitLevel, "player")
  if type(level) ~= "number" or isSecret(level) or level ~= level then return "ok" end
  if minLevel > level then return "dead" end
  return "ok"
end

-- The badge verdict for a bag item. BagVerdictState answers the tri-state the Baganator
-- corner contract needs:
--   "dead"                 permanent unknown (secret/malformed/nonfinite/unresolved,
--                          ineligible, worn, or a path nobody can rate) -> never retried
--   "wait"                 the data may still arrive; a request was issued -> retry later
--   "ok", { verdict = ... } computed verdict:
--     { verdict = "up",   beneficiaries = { { spec, approx }, ... } } -- the specs that gain,
--                                                                     in the class's SPECS order
--     { verdict = "down" }                                            -- every path strictly worse
--     { verdict = "none" }                                            -- computed neutral (equal ...)
function M.BagVerdictState(link)
  if type(link) ~= "string" or isSecret(link) then return "dead" end
  local r = itemReadiness(link)
  if r ~= "ok" then return r end
  if levelGate(link) ~= "ok" then return "dead" end -- above the player's level: never a badge
  -- Equippability AND current-player usability, from the pinned C_Item boundaries
  -- (forever-item-documentation.lua:1324/1627). false/error/secret/missing => no marker;
  -- a missing API is never permission to invent class restrictions.
  if ask(C_Item and C_Item.IsEquippableItem, link) ~= true then return "dead" end
  if ask(C_Item and C_Item.IsUsableItem, link) ~= true then return "dead" end
  local comparisons = M.Compare(link)
  if not comparisons then return "dead" end
  for _, c in ipairs(comparisons) do
    for _, worn in ipairs(c.against) do
      local wr = itemReadiness(worn)
      if wr ~= "ok" then return wr end
    end
  end
  local upSpecs, sawUp, sawDown, sawUseless = {}, false, false, false
  for _, c in ipairs(comparisons) do
    local v = comparisonVerdict(link, c)
    if not v then return "dead" end
    if v.verdict == "up" then
      sawUp = true
      for _, u in ipairs(v.upSpecs or {}) do
        local known
        for _, b in ipairs(upSpecs) do
          if b.spec == u.spec then known = b break end
        end
        if known then
          if u.approx and not known.approx then known.approx = true end
        else
          upSpecs[#upSpecs + 1] = u
        end
      end
    elseif v.verdict == "down" then
      sawDown = true
    else
      sawUseless = true
    end
  end
  if sawUp then
    if #upSpecs > 0 then return "ok", { verdict = "up", beneficiaries = upSpecs } end
    return "ok", { verdict = "up" } -- fallback gain only: no beneficiary spec
  end
  if sawDown and not sawUseless then return "ok", { verdict = "down" } end
  return "ok", { verdict = "none" }
end

-- The R1-compatible single answer: nil unless the item can be classified right now.
function M.BagVerdict(link)
  local state, verdict = M.BagVerdictState(link)
  if state ~= "ok" then return nil end
  return verdict
end

-- Bag-arrow diagnostics: /bit bagprobe <shift-clicked item> prints every gate of
-- the marker pipeline, so a never-showing arrow can be pinned to one cause.
function M.BagProbe(link)
  local function say(m) if BIT.Say then BIT.Say("bagprobe: " .. tostring(m)) end end
  if type(link) ~= "string" or link == "" then
    say("shift-click an item after the command, e.g. /bit bagprobe [Sword]")
    return
  end
  if isSecret(link) then say("link is secret -> dead (wait for data, then retry)") return end
  local r = itemReadiness(link)
  say("readiness=" .. tostring(r))
  if r ~= "ok" then
    say(r == "wait" and "data still loading: keep bags open, it retries on arrival"
      or "item data unusable: check the tooltip loads")
    return
  end
  local gate = levelGate(link)
  say("level gate=" .. tostring(gate) .. (gate == "dead" and " (above the player's level: never a badge)" or ""))
  say("equippable=" .. tostring(ask(C_Item and C_Item.IsEquippableItem, link))
    .. " usable=" .. tostring(ask(C_Item and C_Item.IsUsableItem, link)))
  local comparisons = M.Compare(link)
  if not comparisons then say("no worn slot to compare against -> dead") return end
  say("paths=" .. tostring(#comparisons))
  for i, c in ipairs(comparisons) do
    local v = comparisonVerdict(link, c)
    say("path" .. tostring(i) .. "=" .. (v and (v.verdict .. (v.fallback and " (raw fallback)" or "")) or "dead (class has no spec weights)"))
  end
  local state, verdict = M.BagVerdictState(link)
  if state == "ok" and verdict and verdict.verdict == "up" and verdict.beneficiaries then
    local names = {}
    for _, u in ipairs(verdict.beneficiaries) do names[#names + 1] = tostring(u.spec and u.spec.name or "?") end
    say("final=ok/up for: " .. table.concat(names, ", "))
  else
    say("final=" .. tostring(state) .. (verdict and ("/" .. tostring(verdict.verdict)) or "")
      .. (state == "wait" and " (keep bags open)" or state == "dead" and " (see reason above)" or ""))
  end
  if M.BagProbeButtons then M.BagProbeButtons(link) end
end
if BIT.RegisterCommand then BIT.RegisterCommand("bagprobe", function(rest) M.BagProbe(rest) end) end

-------------------------------------------------------------------------------------------------
-- The overlay over a bag button
-------------------------------------------------------------------------------------------------

-- The arrow is a shaft and three head steps, each a piece of the game's own WHITE8X8
-- texture (no new bitmap), vertex-coloured like the tooltip's green/red. The whole
-- arrow lives in the button's TOPRIGHT corner, inside the button face; the beneficiary
-- icon sits in the corner next to it and the arrow shifts left of the icon when both
-- are shown. Native WoW coordinates: positive y is UP (pinned Blizzard
-- AnchorUtil.lua: a lower row stacks with a NEGATIVE y offset, line 188; labels above
-- a frame use positive offsets, as do BIT ShieldsInfo.lua:428 and DoTInfo
-- Nameplates.lua:228), so a TOPRIGHT-anchored piece paints the native rectangle
-- (x-width, y-height, x, y). The green UP arrow's 2x2 tip is the piece with the
-- LARGEST y (tip above the shaft); the red DOWN arrow's tip has the SMALLEST y.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local UP_R, UP_G, UP_B = 0.302, 1, 0.302
local DOWN_R, DOWN_G, DOWN_B = 1, 0.349, 0.349
local MARKER_W, MARKER_H = 24, 24          -- accurate size for the anchor and Baganator's layout
local MARKER_DX, MARKER_DY = -2, -2        -- TOPRIGHT of the button, 2px inside the corner
local ICON_SIZE = 12
local ICON_DX, ICON_DY = -2, -12           -- the icon: 12x12 fully inside the corner (native rect (x-12, y-12, x, y))
local PLUSN_DX, PLUSN_DY = -2, -16         -- the +N / ~ cues: a second row below the icon
local ARROW_SHIFT = -14                    -- arrow moves left of the icon when the icon is shown
-- Up arrow (tip at the TOP, largest y): { width, height, TOPRIGHT-x, TOPRIGHT-y } of the marker.
-- Native rectangles touch edge-to-edge: tip (-6,-6,-4,-4), step (-8,-9,-2,-6),
-- flare (-10,-12,0,-9), shaft (-6,-20,-4,-12).
local UP_PIECES = { { 2, 2, -4, -4 }, { 6, 3, -2, -6 }, { 10, 3, 0, -9 }, { 2, 8, -4, -12 } }
-- Down arrow: the mirror image (tip at the BOTTOM, smallest y): shaft (-6,-14,-4,-6),
-- flare (-10,-17,0,-14), step (-8,-20,-2,-17), tip (-6,-22,-4,-20).
local DOWN_PIECES = { { 2, 8, -4, -6 }, { 10, 3, 0, -14 }, { 6, 3, -2, -17 }, { 2, 2, -4, -20 } }

local markers = {}      -- button -> marker frame (pooled per button, as the buttons are)
M._bagMarkers = markers -- the tests read these; not part of the addon's interface
function M._bagMarkerFor(button) return markers[button] end
local pendingCreate = {} -- buttons whose marker waited for PLAYER_REGEN_ENABLED
M._pendingCreate = pendingCreate -- test seam, not part of the addon's interface

-- Forward declarations: defined in the lifecycle section below (after scheduleRefresh);
-- eachVisibleButton and the event handler need them while they are defined earlier.
local ensureFrameHook, eachContainerFrame
-- driveNativeUpgradeIcon is defined with applyMarker below; hideMarker above calls
-- it, so the local must be declared here (a later `local function` would read as
-- a nil global inside hideMarker).
local driveNativeUpgradeIcon

-- The badge content is SHARED verbatim between a native bag button's marker frame and
-- the Baganator832 corner widget: the same pieces, the same anchors (children of the
-- CONTAINER, TOPRIGHT, inside the 24x24 face), the same sizes and colours.
local function initContents(container)
  container.arrowPieces = {}
  for _ = 1, 4 do
    container.arrowPieces[#container.arrowPieces + 1] = container:CreateTexture(nil, "OVERLAY")
  end
  container.icon = container:CreateTexture(nil, "OVERLAY")
  container.icon:SetSize(ICON_SIZE, ICON_SIZE)
  container.plusN = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  container.tilde = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
end

-- Always clear stale pixels/text BEFORE a false/nil answer: a hidden widget must never
-- leave an old arrow behind for the next true.
local function clearContents(container)
  if not container then return end
  for _, t in ipairs(container.arrowPieces or {}) do t:Hide() end
  if container.icon then container.icon:Hide() end
  if container.plusN then container.plusN:SetText("") end
  if container.tilde then container.tilde:SetText("") end
end

local function paintContents(container, verdict, nativeUp)
  local up = verdict.verdict == "up"
  local r, g, b = up and UP_R or DOWN_R, up and UP_G or DOWN_G, up and UP_B or DOWN_B
  local pieces = up and UP_PIECES or DOWN_PIECES
  local s = M.settings
  local gave = verdict.beneficiaries and verdict.beneficiaries[1]
  -- The arrow and the icon share the corner: when the icon is shown the arrow moves
  -- one icon-width + gap to the left; without the icon the arrow owns the corner.
  -- nativeUp: the button's own UpgradeIcon carries the green UP, so no custom
  -- arrow pieces are painted (only the icon row below is ours).
  local shift = (up and not nativeUp and s and s.bagSpecIcons and gave) and ARROW_SHIFT or 0
  for i, t in ipairs(container.arrowPieces) do
    if nativeUp then
      t:Hide()
    else
      local p = pieces[i]
      t:SetTexture(WHITE)
      t:SetVertexColor(r, g, b, 1)
      t:SetSize(p[1], p[2])
      t:ClearAllPoints()
      t:SetPoint("TOPRIGHT", container, "TOPRIGHT", p[3] + shift, p[4])
      t:Show()
    end
  end
  if up and s and s.bagSpecIcons and gave then
    container.icon:SetTexture(gave.spec.icon)
    container.icon:ClearAllPoints()
    container.icon:SetPoint("TOPRIGHT", container, "TOPRIGHT", ICON_DX, ICON_DY)
    container.icon:Show()
    container.plusN:ClearAllPoints()
    container.plusN:SetPoint("TOPRIGHT", container, "TOPRIGHT", PLUSN_DX, PLUSN_DY)
    container.plusN:SetText(#verdict.beneficiaries > 1 and ("+" .. (#verdict.beneficiaries - 1)) or "")
    container.tilde:ClearAllPoints()
    container.tilde:SetPoint("RIGHT", container.plusN, "LEFT", -1, 0)
    container.tilde:SetText(gave.approx and "~" or "") -- the heuristic's (approx.) cue
  else
    container.icon:Hide()
    container.plusN:SetText("")
    container.tilde:SetText("")
  end
end

local function hideMarker(button)
  if button then button.bitCheckedRefresh, button.bitCheckedLink = nil, nil end
  driveNativeUpgradeIcon(button, false)
  local marker = markers[button]
  if not marker then return end
  marker:Hide()
  clearContents(marker)
end

local function hideAll()
  for button in pairs(markers) do hideMarker(button) end
end

local function createMarker(button)
  local marker = CreateFrame("Frame", nil, button)
  marker:EnableMouse(false)
  marker:Hide()
  marker:SetSize(MARKER_W, MARKER_H)
  if type(button.GetFrameLevel) == "function" then
    marker:SetFrameLevel((button:GetFrameLevel() or 1) + 1)
  end
  marker:SetPoint("TOPRIGHT", button, "TOPRIGHT", MARKER_DX, MARKER_DY)
  initContents(marker)
  markers[button] = marker
  return marker
end

-- Pawn-style, clean-room (Pawn is CC BY-NC-ND: technique only, no code copied):
-- an UP verdict lights the button's OWN native UpgradeIcon instead of the custom
-- green arrow. DOWN/none/unknown always hide it (the native icon is green-only).
-- Buttons without the texture (older templates) keep the custom arrows. SetShown
-- on an existing texture is combat-safe; no frames are created here.
driveNativeUpgradeIcon = function(button, show)
  local icon = type(button) == "table" and button.UpgradeIcon
  if type(icon) ~= "table" or type(icon.SetShown) ~= "function" then return false end
  icon:SetShown(show == true)
  return true
end

local function applyMarker(button, verdict)
  local up = verdict and verdict.verdict == "up"
  local native = driveNativeUpgradeIcon(button, up)
  local marker = markers[button]
  if not verdict or verdict.verdict == "none" then
    if marker then hideMarker(button) end
    return
  end
  if not marker then
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
      pendingCreate[button] = verdict
      return
    end
    marker = createMarker(button)
  end
  paintContents(marker, verdict, up and native)
  marker:Show()
end
M._applyMarker = applyMarker -- test seam, not part of the addon's interface

-------------------------------------------------------------------------------------------------
-- Baganator832 (the user's installed bag addon): one composite corner widget via the
-- public API (payload/API/Main.lua:229-242). Baganator owns showing/hiding/reparenting/
-- anchors; children anchor to THIS widget. The widget answers the tri-state contract:
-- true (show), false (permanent no-visual), nil (data not yet available -> bounded).
-------------------------------------------------------------------------------------------------

local WIDGET_ID = "statsinfo_bag_arrows"
local baganatorRegistered = false

-- Which live slot is THIS player's own to mark. details.bagType is the BAG's own type
-- (0 = regular bag, 1..10 = a specialty bag, or "quiver"/"reagentBag"/"keyring" --
-- Baganator ItemViewCommon/Utilities.lua:325-341 GetBagType against Core/Constants.lua:
-- 192-208 ContainerKeyToInfo), never the CONTAINER context: "backpack"/"character_bank"/
-- "warband_bank" live only on the sort API (Baganator.API.Constants.ContainerType,
-- API/Main.lua) and never appear on a button's details, so a context gate keyed on
-- bagType could not match a single slot (BagLayout puts the GetBagType answer there,
-- CategoryViews/BagLayout.lua:50-54) and no arrow could ever show. The live
-- itemLocation IS the context: bags and the character bank are the player's own, an
-- account/warband bank tab is a shared context and is never marked.
local function ownSlot(loc)
  local bag = loc.bagID
  -- {equipmentSlotIndex} and any other shape is not a container slot: never marked
  if type(bag) ~= "number" or isSecret(bag) then return false end
  if type(Enum) == "table" and type(Enum.BagIndex) == "table" then
    for i = 1, 9 do
      local tab = Enum.BagIndex["AccountBankTab_" .. i]
      if tab ~= nil and bag == tab then return false end -- the shared warband bank
    end
  end
  return true
end

-- Current-player ownership of a Baganator button: Baganator sets BGR.guid and
-- BGR.itemLocation ONLY for live containers the player can see (ItemViewCommon/
-- ItemButton.lua:667-674, 1177-1182); cached other-character/alt/mail/auction/guild
-- views have neither. The guid must still match the live item (pool reuse), exactly
-- like Baganator's own stale check (ItemButton.lua:164).
local function liveOwned(details)
  local loc = details.itemLocation
  if type(loc) ~= "table" then return false end
  if not ownSlot(loc) then return false end
  if not (C_Item and type(C_Item.DoesItemExist) == "function") then return false end
  if ask(C_Item.DoesItemExist, loc) ~= true then return false end
  local guid = details.guid
  if guid == nil or isSecret(guid) then return false end
  local live = ask(C_Item.GetItemGUID, loc)
  -- Only a proven-plain guid may be compared with the recorded one: a secret one
  -- raises on the comparison itself (and on every table touch it would flow into).
  -- The client hands back either a string or a number guid (Baganator's own "none"
  -- sentinel is the string "-1", Sorting/OrderBags.lua:54), so both are plain here.
  local liveType = type(live)
  if (liveType ~= "string" and liveType ~= "number") or isSecret(live) then return false end
  if live ~= guid then return false end
  return true
end

local function baganatorOnInit(itemButton)
  local widget = CreateFrame("Frame", nil, itemButton)
  widget:SetSize(MARKER_W, MARKER_H)
  widget:EnableMouse(false)
  widget:Hide()
  widget.padding = 1 -- Baganator's corner padding multiplier (default 1)
  initContents(widget)
  return widget
end

local function baganatorOnUpdate(widget, details)
  clearContents(widget)
  widget:Hide()
  if not active then return false end
  if type(details) ~= "table" then return false end
  if not liveOwned(details) then return false end -- context/guid gate (ownSlot inside)
  -- the hyperlink the client itself reads for the live container; the BGR link as the
  -- guarded fallback (Syndicator may lag the container by a tick)
  local link
  local loc = details.itemLocation
  local info = ask(C_Container and C_Container.GetContainerItemInfo, loc.bagID, loc.slotIndex)
  local stackCount
  if type(info) == "table" then stackCount = info.stackCount end
  if isSecret(stackCount) then stackCount = nil end
  if stackCount == 0 then return false end -- a slot being emptied or moved: never a marker
  if type(info) == "table" and type(info.hyperlink) == "string" and not isSecret(info.hyperlink) then
    link = info.hyperlink
  elseif type(details.itemLink) == "string" and not isSecret(details.itemLink) then
    link = details.itemLink
  end
  if not link then return false end
  local state, verdict = M.BagVerdictState(link)
  if state == "wait" then
    -- the client retries while the data loads; we already issued the coalesced request.
    -- Bound the waits so a never-loading item ends as false, not as an endless nil loop.
    -- A secret id never keys waits either (type() reads it as a number; indexing raises).
    local id = details.itemID
    if type(id) == "number" and not isSecret(id) then waits[id] = (waits[id] or 0) + 1 end
    return nil
  end
  if state ~= "ok" then return false end
  if verdict.verdict == "none" then return false end
  paintContents(widget, verdict)
  widget:Show()
  return true
end

-- Ask Baganator to re-run the corner callbacks (ItemWidgets only: no search reflow).
-- Never called from onUpdate itself; the loader's events and the item-data arrivals
-- drive it, and the API coalesces the actual RefreshStateChange.
requestBaganatorRefresh = function()
  if not baganatorRegistered then return end
  if not (Baganator and Baganator.API and type(Baganator.API.RequestItemButtonsRefresh) == "function"
      and Baganator.Constants and Baganator.Constants.RefreshReason
      and Baganator.Constants.RefreshReason.ItemWidgets) then return end
  Baganator.API.RequestItemButtonsRefresh({ Baganator.Constants.RefreshReason.ItemWidgets })
end

local function registerBaganator()
  if baganatorRegistered then return end
  if not active then return end -- startup-off: zero plugin resources
  if not (Baganator and Baganator.API and type(Baganator.API.RegisterCornerWidget) == "function") then
    return -- Baganator not loaded (yet); a later ADDON_LOADED retries
  end
  baganatorRegistered = true
  Baganator.API.RegisterCornerWidget(
    "BattleInfoTool StatsInfo: green up / red down against what you wear",
    WIDGET_ID, baganatorOnUpdate, baganatorOnInit, { corner = "top_right", priority = 5 })
  requestBaganatorRefresh()
end

-------------------------------------------------------------------------------------------------
-- The refresh
-------------------------------------------------------------------------------------------------

-- The buttons of the visible native bag frames, combined bags included (the combined
-- frame's buttons carry their own bag ids, exactly as the individual frames' do).
-- Legacy (no ContainerFrameUtil enumerator): the named ContainerFrameNItemM path, only
-- for buttons whose bag the button itself can name -- eligibility is never guessed.
local function eachVisibleButton(cb)
  if type(ContainerFrameUtil_EnumerateContainerFrames) == "function" then
    for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
      ensureFrameHook(frame) -- instance methods, old and pooled frames alike
      if not (type(frame.IsShown) == "function" and not frame:IsShown()) then
        if type(frame.EnumerateValidItems) == "function" then
          for _, button in frame:EnumerateValidItems() do
            -- SLOT FIRST, BAG SECOND (native). A button without the native accessor takes
            -- the legacy GetBagID/GetID pair (as the paths below); one whose bag neither
            -- names is skipped, never guessed.
            if type(button.GetSlotAndBagID) ~= "function" then
              local bag = type(button.GetBagID) == "function" and button:GetBagID() or nil
              if bag ~= nil then cb(button, bag, button:GetID()) end
            else
              local slot, bag = button:GetSlotAndBagID()
              cb(button, bag, slot)
            end
          end
        end
      end
    end
    return
  end
  for i = 1, 256 do
    local frame = _G["ContainerFrame" .. i]
    if not frame then break end
    ensureFrameHook(frame)
    if not (type(frame.IsShown) == "function" and not frame:IsShown()) then
      if type(frame.EnumerateValidItems) == "function" then
        for _, button in frame:EnumerateValidItems() do
          local bag = type(button.GetBagID) == "function" and button:GetBagID() or nil
          if bag ~= nil then cb(button, bag, button:GetID()) end
        end
      else
        local name = type(frame.GetName) == "function" and frame:GetName()
        if type(name) == "string" then
          for j = 1, 256 do
            local button = _G[name .. "Item" .. j]
            if not button then break end
            local bag = type(button.GetBagID) == "function" and button:GetBagID() or nil
            if bag ~= nil then cb(button, bag, button:GetID()) end
          end
        end
      end
    end
  end
end

-- One slot's hyperlink and stack count: the one the native code itself reads at UpdateItems
-- (C_Container.GetContainerItemInfo; the classic global GetContainerItemInfo as the
-- guarded fallback), else nil (an empty or unreadable slot). A stack count of 0 means the
-- slot is being emptied or moved; a hidden count is unknown, never compared with.
local function linkOf(bag, slot)
  local info = ask(C_Container and C_Container.GetContainerItemInfo, bag, slot)
  if type(info) == "table" then
    local count = info.stackCount
    if isSecret(count) then count = nil end
    if type(info.hyperlink) == "string" and not isSecret(info.hyperlink) then return info.hyperlink, count end
    return nil, count
  end
  -- the classic global answers (texture, itemCount, locked, quality, readable, lootable,
  -- itemLink, ...): the link is the 7th return and the count the 2nd, never the first (that
  -- one is the texture)
  local _, itemCount, _, _, _, _, l = ask(GetContainerItemInfo, bag, slot)
  if isSecret(itemCount) then itemCount = nil end
  if type(l) == "string" and not isSecret(l) then return l, itemCount end
  return nil, itemCount
end

-- The per-slot memo (Pawn-style, clean-room: the pattern, not the code): a verdict is
-- recomputed only when the slot's link changed, or when the revision counter grew -- a
-- settings change, a gear swap or a level-up, i.e. anything that can give an UNCHANGED
-- (slot, link) pair a NEW verdict. Only a computed "ok" verdict is remembered; a "wait" or
-- "dead" answer is never pinned to a slot (data may still arrive, combat secrets clear) and
-- is re-asked on the next pass, where it fails cheaply before the weights.
local refreshCounter = 0
local function bumpRevision() refreshCounter = refreshCounter + 1 end

-- One button: the hyperlink and the stack count, then the verdict, then the marker.
local function evaluate(button, bag, slot)
  local link, stackCount = linkOf(bag, slot)
  if not link or stackCount == 0 then
    -- no item, or a slot being emptied or moved: never a marker
    applyMarker(button, nil)
    button.bitCheckedRefresh, button.bitCheckedLink = nil, nil
    return
  end
  if button.bitCheckedRefresh == refreshCounter and button.bitCheckedLink == link then
    return -- the same item in the same slot since the last revision: the verdict cannot have changed
  end
  local state, verdict = M.BagVerdictState(link)
  if state ~= "ok" then
    -- "wait"/"dead": clear now; the arrival events (ITEM_DATA_LOAD_RESULT / ...) re-run this
    applyMarker(button, nil)
    button.bitCheckedRefresh, button.bitCheckedLink = nil, nil
    return
  end
  applyMarker(button, verdict)
  button.bitCheckedRefresh, button.bitCheckedLink = refreshCounter, link
end

-- The live module switch (Core/Settings.lua writes BIT.SetSwitchedOn): the reload-scoped
-- core latch stays as it is for every module, but THIS marker subsystem reads the live
-- IsSwitchedOn switch at every refresh and clears/registers through a narrow seam.
local function moduleOn() return BIT.IsSwitchedOn("StatsInfo") end

local function refreshVisible()
  if not (M.settings and M.settings.bagMarkers) or not BIT.IsRunning("StatsInfo") or not moduleOn() then
    hideAll()
    return
  end
  eachVisibleButton(evaluate)
end

-- A narrow refresh API for the settings boxes (and the tests): immediate, no events sway.
-- It grows the memo's revision counter first: a settings change can give an unchanged
-- (slot, link) pair a new verdict, so nothing may be skipped after it.
function M.RefreshBags(force)
  bumpRevision()
  refreshVisible()
end

-- The marker pipeline over the buttons the client shows right now: one line per button --
-- which link (if any) the client reads there, what it verdicts to, and whether a marker
-- frame exists and is shown. /bit bagprobe runs it after the per-link report; want (a
-- shift-clicked link) narrows it to that item's buttons.
function M.BagProbeButtons(want)
  local function say(m) if BIT.Say then BIT.Say("bagprobe: " .. tostring(m)) end end
  local setting = M.settings and M.settings.bagMarkers
  say("buttons: bagMarkers=" .. tostring(setting) .. " running=" .. tostring(BIT.IsRunning("StatsInfo"))
    .. " switch=" .. tostring(moduleOn()) .. " baganator="
    .. (baganatorRegistered and "widget registered" or "no widget (Baganator not loaded)"))
  if not (setting and BIT.IsRunning("StatsInfo") and moduleOn()) then
    say("buttons: the gate above is off, nothing is drawn")
    return
  end
  local wanted = type(want) == "string" and tonumber(want:match("item:(%d+)")) or nil
  local n, shown = 0, 0
  eachVisibleButton(function(button, bag, slot)
    local link = linkOf(bag, slot)
    if not link then return end
    if wanted and tonumber(link:match("item:(%d+)")) ~= wanted then return end
    n = n + 1
    local state, verdict = M.BagVerdictState(link)
    local marker = markers[button]
    local isShown = marker and type(marker.IsShown) == "function" and marker:IsShown() or false
    if isShown then shown = shown + 1 end
    say(string.format("button %s/%s: link=ok state=%s verdict=%s marker=%s",
      tostring(bag), tostring(slot), tostring(state),
      tostring(verdict and verdict.verdict or "-"),
      marker and (isShown and "shown" or "hidden") or "none"))
  end)
  say("buttons: " .. n .. " with this item, " .. shown .. " marker(s) shown")
end

-------------------------------------------------------------------------------------------------
-- Hooks, events, lifecycle
-------------------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader.bagMarkersLoader = true -- the tests identify the loader by this

local installedHooks = false
local hookedSwitch = false
local scheduled = false

scheduleRefresh = function()
  if not active then return end
  if scheduled then return end
  scheduled = true
  local function flush()
    scheduled = false
    refreshVisible()
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0.05, flush) -- coalesces the BAG_UPDATE storms; no OnUpdate polling
  else
    flush()
  end
end

-- The client's Mixin() COPIES the container methods onto every frame instance at
-- OnLoad (SharedXMLBase/Mixin.lua), so a post-hook on the mixin TABLE entry alone is
-- inert for frames that existed before this addon loaded. Each frame's own instance
-- method gets its own secure post-hook, once per frame lifetime (weak-keyed: pooled
-- frames are reused and the hook dies with the frame).
local hookedFrames = setmetatable({}, { __mode = "k" })
ensureFrameHook = function(frame)
  if hookedFrames[frame] then return end
  hookedFrames[frame] = true
  if type(frame) == "table" and type(frame.UpdateItems) == "function"
      and type(hooksecurefunc) == "function" then
    hooksecurefunc(frame, "UpdateItems", scheduleRefresh)
  end
end

-- Every container frame the client knows (shown or pooled), on any client shape.
eachContainerFrame = function(cb)
  local any = false
  if type(ContainerFrameUtil_EnumerateContainerFrames) == "function" then
    for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
      any = true
      cb(frame)
    end
  end
  if any then return end
  for i = 1, 256 do
    local frame = _G["ContainerFrame" .. i]
    if not frame then break end
    cb(frame)
  end
end

local REFRESH_EVENTS = {
  -- NOTE: there is no ITEM_DATA_LOADED on any client (Baganator only ever touches
  -- ITEM_DATA_LOAD_RESULT); registering it raises and kills the whole wiring.
  "BAG_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
  "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
}

local function ensureEvents()
  if not active then return end
  for _, e in ipairs(REFRESH_EVENTS) do loader:RegisterEvent(e) end
  loader:RegisterEvent("ITEM_DATA_LOAD_RESULT") -- request arrivals (Baganator's loader too)
  loader:RegisterEvent("ADDON_LOADED")           -- a LATE Baganator load still registers
  if type(GetSpecialization) == "function" then loader:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") end
  loader:RegisterEvent("BAG_CLOSED")
  loader:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function clearEvents()
  loader:UnregisterAllEvents()
end

local function installHooks()
  if installedHooks then return end
  installedHooks = true
  if type(ContainerFrameMixin) == "table" and type(ContainerFrameMixin.UpdateItems) == "function"
      and type(hooksecurefunc) == "function" then
    hooksecurefunc(ContainerFrameMixin, "UpdateItems", scheduleRefresh)
  end
  if type(ContainerFrameUtil_EnumerateContainerFrames) ~= "function" and type(ContainerFrame_Update) == "function" then
    hooksecurefunc("ContainerFrame_Update", scheduleRefresh)
  end
  if type(ContainerFrame_UpdateAll) == "function" then
    hooksecurefunc("ContainerFrame_UpdateAll", scheduleRefresh)
  end
  -- frames that existed before this addon loaded hold INSTANCE COPIES of the methods;
  -- hook each frame's own UpdateItems once (new/pooled frames are hooked at first sight)
  eachContainerFrame(ensureFrameHook)
  -- the narrow lifecycle seam: the marker subsystem reacts to the core module switch
  -- IMMEDIATELY (clear + unregister / re-enable), while every other module keeps the
  -- core's reload-scoped semantics untouched.
  if type(BIT.SetSwitchedOn) == "function" and type(hooksecurefunc) == "function"
      and not hookedSwitch then
    hookedSwitch = true
    hooksecurefunc(BIT, "SetSwitchedOn", function(name, on)
      if name ~= "StatsInfo" then return end
      if on then M.EnableBagMarkers() else M.DisableBagMarkers() end
    end)
  end
end

-- The settings boxes (StatsInfo.lua) and the core module switch (via the SetSwitchedOn
-- seam below) call these when the user flips their respective toggles.
function M.EnableBagMarkers()
  if not (M.settings and M.settings.bagMarkers == true) then
    active = false
    clearEvents()
    hideAll()
    return
  end
  active = true
  installHooks()
  ensureEvents()
  registerBaganator()
  M.RefreshBags(true)
  requestBaganatorRefresh()
end

function M.DisableBagMarkers()
  active = false
  clearEvents()
  for k in pairs(pendingCreate) do pendingCreate[k] = nil end
  for _, map in ipairs({ wanted, outstanding, arrived, waits }) do
    for k in pairs(map) do map[k] = nil end
  end
  M.RefreshBags(true) -- hides whatever is out there
  requestBaganatorRefresh() -- the corner widgets clear through onUpdate (active is off)
end

loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "Baganator" then
      -- the user enabled Baganator later; Baganator owns the bag grid now
      registerBaganator()
      return
    end
    if arg1 ~= BIT.name then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not BIT.ShouldRun("StatsInfo") then self:UnregisterAllEvents() return end
    active = M.settings and M.settings.bagMarkers == true
    return
  elseif event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    if not active then self:UnregisterAllEvents() return end
    installHooks()
    ensureEvents()
    registerBaganator()
    return
  end
  if not active then return end
  if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
    onItemDataArrived(arg1)
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    local waiting = {}
    for button in pairs(pendingCreate) do
      waiting[#waiting + 1] = button
      pendingCreate[button] = nil
    end
    for _, button in ipairs(waiting) do createMarker(button) end
    scheduleRefresh()
    return
  end
  if event == "BAG_CLOSED" then
    -- hide ONLY the closed bag's buttons (arg1 = bag index); the other open bags keep
    -- their markers, and the re-read re-evaluates anything the pool reshuffled
    if type(arg1) == "number" then
      for button in pairs(markers) do
        local bag = type(button.GetBagID) == "function" and button:GetBagID() or nil
        if bag == arg1 then hideMarker(button) end
      end
    else
      hideAll() -- a close without a bag index (never sent by the client): clear all
    end
    scheduleRefresh()
    return
  end
  if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" then
    -- the verdict is against what is worn (and gated by the player's level): an unchanged
    -- (slot, link) pair can answer differently now, so the memo must not skip this pass
    bumpRevision()
  end
  scheduleRefresh()
  requestBaganatorRefresh() -- the corner widgets follow the same events (never from onUpdate)
end)