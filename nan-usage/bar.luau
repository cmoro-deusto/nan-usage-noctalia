--!nonstrict
-- Noctalia bar widget for NaN Usage.
--
-- The widget holds no logic of its own. `service.luau` polls NaN and publishes what
-- came back on the plugin's shared state; `shared.luau` turns that into the record
-- this file paints. Nothing is spawned, no command has to be on PATH, and the
-- countdowns are rebuilt on every tick from the same data — so they move between
-- polls instead of only when one lands.
--
-- Clicking opens the panel, which Noctalia places next to the widget, so there is
-- no window rule to get wrong. Right-clicking opens this plugin's own settings.

local shared = require("./shared.luau")

-- Read per paint rather than once at load, so a change in the settings page lands
-- without a reload. `~= false` for a setting whose manifest default is true, `== true`
-- for one whose default is false: an unset value has to mean what the manifest says,
-- and show_icon defaults to true.
local function showIcon()
  return noctalia.getConfig("show_icon") ~= false
end

local function showGlyph()
  return noctalia.getConfig("show_glyph") == true
end

local function glyphName()
  return noctalia.getConfig("glyph") or "chart-pie"
end

local function showTooltip()
  return noctalia.getConfig("show_tooltip") ~= false
end

-- panel | nothing. The panel is Noctalia's own surface.
local function leftClick()
  return noctalia.getConfig("left_click") or "panel"
end

local function iconStyle()
  return noctalia.getConfig("icon_style") or "ghost"
end

-- The panel this plugin owns, addressed the way Noctalia names entries.
local PANEL_ID = "cmoro-deusto/nan-usage:panel"

-- The NaN logo, next to this file. The PNGs are rasterised from the SVG beside
-- them, because whether the shell's Qt build can render an SVG is not something to
-- bet on. An image replaces the glyph — the API shows one or the other — so this
-- wins over show_glyph.
local ICON_COLOR = "nan.png"
local ICON_GHOST_ON_DARK = "nan-ghost-white.png"
local ICON_GHOST_ON_LIGHT = "nan-ghost-black.png"
local ICON_SIZE = 16

-- The gauge. A bar widget draws one only through the declarative tree below:
-- setText/setGlyph/setImage have no way to draw a bar, and ui.progress is the only
-- gauge Noctalia renders in a bar — there is no arc primitive, so there is no ring
-- setting either. See the plugin README.
local GAUGE_WIDTH = 34
local GAUGE_HEIGHT = 5

-- The two alarm colours. The healthy level keeps the theme's own text colour, so
-- the bar stays quiet until there is something to say.
local COLOR_WARN = "#ff7800"
local COLOR_CRIT = "#e01b24"

-- How often the record is rebuilt from the data already held. Polling is the
-- service's business; this only moves the countdowns on, so 15 s is plenty and
-- costs nothing.
local UPDATE_MS = 15000

-- Read per tick rather than once, so a change in the settings page lands without
-- a reload.
local function config()
  return {
    panelModel = noctalia.getConfig("panel_model") or "worst",
    panelModelId = noctalia.getConfig("panel_model_id") or "deepseek-v4-flash",
    gauge = noctalia.getConfig("panel_gauge") or "bar",
    hideUnused = noctalia.getConfig("hide_unused") == true,
    showMetrics = noctalia.getConfig("show_metrics") ~= false,
    showPercentage = noctalia.getConfig("show_percentage") ~= false,
    showReset = noctalia.getConfig("show_reset") ~= false,
    showModel = noctalia.getConfig("show_model") ~= false,
    pollSeconds = tonumber(noctalia.getConfig("interval")) or 60,
  }
end

-- The tooltip is the per-model detail, which is what the bar has no room for.
local function rowsFor(record)
  local rows = {}
  -- Values only, and tight: the caption says the same thing in a sentence ("… ·
  -- resets in 7d 8h · at this rate …"), whose tail is what a tooltip cuts off first.
  if record.error ~= nil and record.error ~= "" then
    local text = record.error
    if record.stale == true then
      text = text .. " (showing the last data)"
    end
    table.insert(rows, { key = "error", value = text })
  end
  for _, window in ipairs(record.windows or {}) do
    local value = (window.usedText or "") .. " / " .. (window.capText or "")
    if window.resetsIn ~= nil and window.resetsIn ~= "" then
      value = value .. "·" .. window.resetsIn
    end
    table.insert(rows, { key = window.model, value = value })
  end
  -- Consumption one row per period, from the numbers rather than from a sentence:
  -- a tooltip that does not fit is a tooltip nobody can read.
  for _, bucket in ipairs(record.usage or {}) do
    table.insert(rows, { key = bucket.label, value = bucket.text })
  end
  return rows
end

-- Which raster to draw: the coloured mark, or the ghost in whichever ink the theme
-- will read.
local function iconFile()
  if iconStyle() == "color" then
    return ICON_COLOR
  end
  if noctalia.isDarkMode() then
    return ICON_GHOST_ON_DARK
  end
  return ICON_GHOST_ON_LIGHT
end

-- The colour a level draws in. "on_surface" for a healthy one, so the widget keeps
-- the theme's own ink until there is something to say.
local function levelColor(level)
  if level == "crit" then
    return COLOR_CRIT
  end
  if level == "warn" then
    return COLOR_WARN
  end
  return "on_surface"
end

-- The widget as a tree: the mark, the gauge, the text. One node set per paint, so
-- nothing is left over from the render before it — the same reason the panel's
-- cards set every prop.
local function nodesFor(level, text, percent, gauge)
  local nodes = {}
  if showIcon() then
    table.insert(nodes, ui.image({ path = iconFile(), width = ICON_SIZE, height = ICON_SIZE }))
  elseif showGlyph() then
    table.insert(nodes, ui.glyph({ name = glyphName(), size = ICON_SIZE, color = levelColor(level) }))
  end
  if gauge ~= "none" then
    table.insert(nodes, ui.progress({
      progress = math.max(0, math.min(tonumber(percent) or 0, 100)) / 100,
      fill = levelColor(level),
      track = "on_surface/0.12",
      width = GAUGE_WIDTH,
      height = GAUGE_HEIGHT,
      radius = 3,
    }))
  end
  -- No fontSize on purpose: an unset size inherits the bar's own font and scale, so
  -- this text sits exactly where the other widgets' text sits. Setting one made it a
  -- couple of points larger than its neighbours, whose cap-line therefore rode higher
  -- in the bar.
  table.insert(nodes, ui.label({ text = text, color = levelColor(level) }))
  return nodes
end

local function paint(level, text, percent, gauge, tooltip)
  barWidget.render(ui.row({ gap = 6, align = "center" }, nodesFor(level, text, percent, gauge)))
  if not showTooltip() then
    return
  end
  if tooltip == nil or (type(tooltip) == "table" and #tooltip == 0) then
    barWidget.clearTooltip()
  else
    barWidget.setTooltip(tooltip)
  end
end

-- No data at all yet, or nothing to show: a dash, no gauge — a hollow bar next to a
-- dash reads as a broken widget — and the reason in the tooltip.
local function paintNothing(record)
  local reason = record.error
  if reason == nil or reason == "" then
    reason = "no data"
  end
  if record.stale == true then
    reason = reason .. " (showing the last data)"
  end
  paint("ok", "—", 0, "none", reason)
end

local function paintRecord(record)
  local panel = record.panel
  if panel == nil then
    paintNothing(record)
    return
  end
  local text = panel.text
  if text == nil or text == "" then
    text = panel.percentText
  end
  paint(panel.level, text, panel.percent, record.gauge or "bar", rowsFor(record))
end

local function repaint(data)
  if data == nil then
    paintNothing({ error = "waiting for the first poll" })
    return
  end
  paintRecord(shared.build(data, config(), os.time()))
end

-- The service publishes as soon as a poll lands, so the bar never waits for the
-- next tick to show it.
noctalia.state.watch("data", repaint)

-- Between polls, rebuild from the data already held: that is what moves the
-- countdowns, and it is the only reason this widget has a tick at all.
function update()
  noctalia.setUpdateInterval(UPDATE_MS)
  repaint(noctalia.state.get("data"))
end

function onClick()
  if leftClick() == "nothing" then
    return
  end
  noctalia.togglePanel(PANEL_ID)
end

-- No external settings window any more: the plugin's own page is the cog, and it is
-- where the key path, the poll interval and the gauge live.
function onRightClick()
  noctalia.openSettings()
end

repaint(noctalia.state.get("data"))
