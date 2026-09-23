--!nonstrict
-- Noctalia bar widget for NaN Usage.
--
-- The widget holds no logic of its own. `nan-usage watch --json` decides which
-- model is the worst, whether the burn rate is heading for trouble, and what the
-- text should say, and it prints one JSON record per redraw (the format is
-- documented in the project README). This file reads four fields of it, colours
-- the text when the level is not "ok", and puts the rest in the tooltip.
--
-- Clicking opens the GTK popup with the per-model detail; right-clicking opens
-- the settings window. Both are ordinary programs, so this plugin is only a
-- thin adapter: remove it and the rest of the tool is unaffected.

local command = noctalia.getConfig("command") or "nan-usage"
local interval = noctalia.getConfig("interval") or 60
local showIcon = noctalia.getConfig("show_icon") == true
local showGlyph = noctalia.getConfig("show_glyph") == true
local glyphName = noctalia.getConfig("glyph") or "chart-pie"
local showTooltip = noctalia.getConfig("show_tooltip") ~= false
-- panel | popup | nothing. The panel is Noctalia's own surface, which it places
-- next to the widget; the popup is the external GTK window.
local leftClick = noctalia.getConfig("left_click") or "panel"
local iconStyle = noctalia.getConfig("icon_style") or "ghost"

-- The panel this plugin owns, addressed the way Noctalia names entries.
local PANEL_ID = "cmoro-deusto/nan-usage:panel"

-- The NaN logo, next to this file. The PNGs are rasterised
-- from the SVG beside them, because whether the shell's Qt build can render an SVG
-- is not something to bet on. An image replaces the glyph — the API shows one or
-- the other — so this wins over show_glyph.
local ICON_COLOR = "nan.png"
local ICON_GHOST_ON_DARK = "nan-ghost-white.png"
local ICON_GHOST_ON_LIGHT = "nan-ghost-black.png"
local ICON_SIZE = 16

-- The gauge. A bar widget draws one only through the declarative tree below:
-- setText/setGlyph/setImage have no way to draw a bar, and ui.progress is the
-- only gauge Noctalia renders in a bar — there is no arc primitive, so "ring"
-- comes out as this bar too (the separate GTK popup still draws a real one).
-- See the plugin README.
local GAUGE_WIDTH = 34
local GAUGE_HEIGHT = 5

-- The two alarm colours, the same ones the GTK popup uses. The healthy level keeps the theme's own text colour, so the bar stays
-- quiet until there is something to say.
local COLOR_WARN = "#ff7800"
local COLOR_CRIT = "#e01b24"

-- How often update() runs, and how many of those ticks to wait before trying to
-- start a stream that failed (the tool not on PATH yet, or reinstalled).
local UPDATE_MS = 15000
local RETRY_TICKS = 20

local streamStarted = false
local gotRecord = false
local ticksUntilRetry = 0
local gtkFrontEnd = nil
local warnedAboutPopup = false

-- runStream and runAsync run their command through the shell, so the configured
-- path has to be quoted: single quotes, with the usual escape for an embedded one.
local function shellQuote(text)
  return "'" .. string.gsub(text, "'", "'\\''") .. "'"
end

-- hasGTKFrontEnd looks for the GTK binary next to the configured command, or on
-- PATH when the setting is a bare name. The popup cannot open without it, and a
-- detached launch cannot tell us so afterwards, so it is checked up front.
local function hasGTKFrontEnd()
  if gtkFrontEnd ~= nil then
    return gtkFrontEnd
  end
  local dir = string.match(command, "^(.*)/[^/]+$")
  if dir ~= nil then
    gtkFrontEnd = noctalia.fileExists(dir .. "/nan-usage-gtk")
  else
    gtkFrontEnd = noctalia.commandExists("nan-usage-gtk")
  end
  return gtkFrontEnd
end

-- The tooltip is the per-model detail, which is what the bar has no room for.
local function rowsFor(record)
  local rows = {}
  -- Values only. The tool's caption says the same thing in a sentence
  -- ("… · resets in 7d 8h · at this rate …"), and its tail is what gets cut off
  -- first.
  if record.error ~= nil and record.error ~= "" then
    local text = record.error
    if record.stale == true then
      text = text .. " (showing the last data)"
    end
    table.insert(rows, { key = "error", value = text })
  end
  if record.windows ~= nil then
    for _, window in ipairs(record.windows) do
      local value = (window.usedText or "") .. " / " .. (window.capText or "")
    if window.resetsIn ~= nil and window.resetsIn ~= "" then
      value = value .. " · " .. window.resetsIn
    end
    table.insert(rows, { key = window.model, value = value })
    end
  end
  -- Consumption one row per period, from the numbers the tool sends, rather than
  -- the sentence it prints: a tooltip that does not fit is a tooltip nobody can
  -- read.
  for _, bucket in ipairs(record.usage or {}) do
    table.insert(rows, { key = bucket.label, value = bucket.text })
  end
  return rows
end

-- Which raster to draw: the coloured mark, or the ghost in whichever ink the
-- theme will read.
local function iconFile()
  if iconStyle == "color" then
    return ICON_COLOR
  end
  if noctalia.isDarkMode() then
    return ICON_GHOST_ON_DARK
  end
  return ICON_GHOST_ON_LIGHT
end

-- The colour a level draws in. "on_surface" for a healthy one, so the widget
-- keeps the theme's own ink until there is something to say.
local function levelColor(level)
  if level == "crit" then
    return COLOR_CRIT
  end
  if level == "warn" then
    return COLOR_WARN
  end
  return "on_surface"
end

-- The widget as a tree: the mark, the gauge, the text. One node set per paint,
-- so nothing is left over from the render before it — the same reason the
-- panel's cards set every prop.
local function nodesFor(level, text, percent, gauge)
  local nodes = {}
  if showIcon then
    table.insert(nodes, ui.image({ path = iconFile(), width = ICON_SIZE, height = ICON_SIZE }))
  elseif showGlyph then
    table.insert(nodes, ui.glyph({ name = glyphName, size = ICON_SIZE, color = levelColor(level) }))
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
  table.insert(nodes, ui.label({ text = text, color = levelColor(level), fontSize = 13 }))
  return nodes
end

local function paint(level, text, percent, gauge, tooltip)
  barWidget.render(ui.row({ gap = 6, align = "center" }, nodesFor(level, text, percent, gauge)))
  if not showTooltip then
    return
  end
  if tooltip == nil or (type(tooltip) == "table" and #tooltip == 0) then
    barWidget.clearTooltip()
  else
    barWidget.setTooltip(tooltip)
  end
end

local function onLine(line)
  if line == nil or line == "" then
    return
  end
  local record, err = noctalia.json.decode(line)
  if record == nil then
    noctalia.log("NaN Usage: could not read a record from " .. command .. " (" .. tostring(err) .. ")")
    return
  end
  gotRecord = true
  -- The panel is a separate entry with its own VM, so the record travels through
  -- the plugin's shared state channel rather than through memory.
  noctalia.state.set("report", record)

  local panel = record.panel
  if panel == nil then
    -- The tool answered, but has nothing to show: no API key, or no connection.
    local reason = record.error
    if reason == nil or reason == "" then
      reason = "no data"
    end
    -- Nothing to measure, so no gauge: a hollow bar next to a dash reads as a
    -- broken widget.
    paint("ok", "—", 0, "none", reason)
    return
  end

  local text = panel.text
  if text == nil or text == "" then
    text = panel.percentText
  end
  -- The gauge is the tool's own setting, carried in the record, so changing it in
  -- `nan-usage prefs` changes the bar. Older records that predate the field get
  -- the bar.
  paint(panel.level, text, panel.percent, record.gauge or "bar", rowsFor(record))
end

local function start()
  local started = noctalia.runStream(
    shellQuote(command) .. " watch --json --interval " .. tostring(interval),
    onLine
  )
  streamStarted = started == true
  if not streamStarted then
    noctalia.log("NaN Usage: could not start " .. command .. " watch; is it on PATH?")
  end
end

start()

-- There is nothing to recompute between records: the tool prints one per redraw,
-- with the countdowns already moved on. update() is here only to say something
-- while nothing has arrived, and to pick the stream back up if it never started.
function update()
  noctalia.setUpdateInterval(UPDATE_MS)
  if gotRecord then
    return
  end
  paint("ok", "—", 0, "none", "NaN Usage: waiting for " .. command)
  if streamStarted then
    return
  end
  ticksUntilRetry = ticksUntilRetry + 1
  if ticksUntilRetry >= RETRY_TICKS then
    ticksUntilRetry = 0
    start()
  end
end

function onClick()
  if leftClick == "nothing" then
    return
  end
  if leftClick == "popup" then
    openPopup()
    return
  end
  -- Noctalia places this itself, so there is no window rule to get wrong.
  noctalia.togglePanel(PANEL_ID)
end

-- openPopup runs the GTK window detached, with no result callback on purpose. A
-- callback makes Noctalia capture the output and wait for the process to end,
-- which it cannot do for long: the popup stays up until it is dismissed, so the
-- callback would report a failure — and a notification — for a popup that opened
-- perfectly well. What we can predict (a missing GTK front end) is checked first.
function openPopup()
  if not hasGTKFrontEnd() then
    if not warnedAboutPopup then
      warnedAboutPopup = true
      noctalia.notifyError("NaN Usage", "nan-usage-gtk is missing, so the popup cannot open. It needs GTK4: run `nan-usage doctor`.")
    end
    return
  end
  noctalia.runAsync(shellQuote(command) .. " popup")
end

function onRightClick()
  noctalia.runAsync(shellQuote(command) .. " prefs")
end
