-- SPDX-License-Identifier: MIT
--
-- Run the plugin's scripts for real, against stubs of the Noctalia API.
--
-- `tests/plugin_check.py` reads the scripts; this executes them. Two bugs reached a real
-- session that a reading could not have caught — a `#!` first line Luau rejects
-- but `luac` accepts, and a click closure calling a `render` that was declared
-- as a local *below* it, so it resolved to a nil global and raised on every
-- click until Noctalia disabled the plugin. Both are "the script runs" bugs, so
-- this is where they belong.
--
--     lua tests/plugin_test.lua              # from the plugin directory
--
-- It is deliberately plain Lua 5.4: the scripts are written in the subset the
-- two dialects share (no `+=`, no backticks, no type annotations), which is what
-- lets them be checked here at all. It stubs the API rather than the behaviour —
-- `noctalia.json.decode` hands back a table, since parsing JSON is Noctalia's job
-- and not code that lives in this repository.

local ok = 0
local failures = {}

local function check(condition, message)
  if condition then
    ok = ok + 1
  else
    table.insert(failures, message)
    print("FAIL " .. message)
  end
end

local function section(name)
  print("-- " .. name)
end

local root = arg[0]:match("^(.*)/[^/]*$") or "."
-- The scripts and their translations are one level up: this file lives in the
-- plugin's own tests/ directory.
local PLUGIN = root .. "/.."

-- ---------------------------------------------------------------- fixtures

-- A record shaped like the one the tool prints; the contract is in the project
-- README. Two models, so a click has somewhere to move to.
local function record(overrides)
  local base = {
    version = 1,
    ok = true,
    stale = false,
    updated = "Updated at 17:37",
    ageSeconds = 5,
    account = { handle = "someone", region = "EU", tier = "INFERENCE", summary = "someone · EU" },
    period = "Period from 1 Sep · resets in 7d 8h",
    metrics = "24 h: 91.9M · month: 227.7M · 30 d: 227.7M",
    usage = {
      { label = "24 h", text = "91.9M", tokens = 91900000 },
      { label = "month", text = "227.7M", tokens = 227700000 },
      { label = "30 d", text = "227.7M", tokens = 227700000 },
    },
    totalWindows = 3,
    windows = {
      {
        key = "deepseek-v4-flash", model = "deepseek-v4-flash", short = "ds4f",
        percent = 8.0, percentText = "8.0%", level = "ok", resetsIn = "7d",
        used = 241300000, usedText = "241.3M", capText = "3B",
        caption = "241.3M / 3B · resets in 7d 8h",
      },
      {
        key = "glm5.2", model = "glm5.2", short = "glm5.2",
        percent = 0.0, percentText = "0.0%", level = "ok", resetsIn = "3d",
        used = 0, usedText = "0", capText = "3B", caption = "0 / 3B · resets in 3d",
      },
      {
        key = "glm5.3-flash", model = "glm5.3-flash", short = "glm5.3f",
        percent = 96.4, percentText = "96.4%", level = "crit", resetsIn = "2d",
        used = 1900000000, usedText = "1.9B", capText = "2B",
        caption = "1.9B / 2B · resets in 2d",
        note = "at this rate it runs out in ~6h",
      },
    },
    panel = { model = "glm5.3-flash", short = "glm5.3f", percent = 96.4, percentText = "96.4%",
              level = "crit", resetsIn = "2d", text = "96.4% · 2d" },
  }
  for key, value in pairs(overrides or {}) do
    base[key] = value
  end
  return base
end

-- A reader for the translations file: nested objects of strings, flattened to
-- dotted paths, because that is how they are looked up. It is nested on purpose —
-- the store's keys are single lowercase segments, so a dotted key in the file would
-- be rewritten on the next i18n sync — and the plugin's own `tr("...")` calls use
-- the dotted path. Noctalia does the real parsing; this exists so the harness can
-- tell a rendered label from an unresolved key.
local function readTranslations()
  local handle = assert(io.open(PLUGIN .. "/translations/en.json", "r"), "translations/en.json")
  local text = handle:read("a")
  handle:close()

  local out, path, position = {}, {}, 1
  while true do
    local index = text:find('[{}"]', position)
    if index == nil then
      break
    end
    local char = text:sub(index, index)
    if char == "{" then
      position = index + 1
    elseif char == "}" then
      table.remove(path)
      position = index + 1
    else
      local key, after = text:match('^"([^"]*)"%s*:%s*()', index)
      assert(key ~= nil, "cannot read translations/en.json at byte " .. index)
      if text:sub(after, after) == "{" then
        table.insert(path, key)
        position = after + 1
      else
        local value, afterValue = text:match('^"([^"]*)"%s*()', after)
        assert(value ~= nil, "expected a string or an object after " .. key)
        local full = #path > 0 and (table.concat(path, ".") .. "." .. key) or key
        out[full] = value
        position = afterValue
      end
    end
  end

  assert(next(out) ~= nil, "translations/en.json did not parse")
  return out
end

-- ------------------------------------------------------------------- stubs

local journal, env, settings

local function reset(world)
  journal = {
    renders = {}, commands = {}, notifications = {}, watch = {},
    text = nil, color = nil, tooltips = {}, images = {}, glyphs = {},
  }
  settings = {
    command = "nan-usage", interval = 60, left_click = "panel",
    show_icon = true, show_glyph = false, glyph = "chart-pie", show_tooltip = true,
    icon_style = "ghost",
  }
  for key, value in pairs(world.settings or {}) do
    settings[key] = value
  end
  local translations = readTranslations()

  local function node(kind)
    return function(props, children)
      return { type = kind, props = props or {}, children = children or {} }
    end
  end

  local ui = {}
  for _, kind in ipairs({
    "column", "row", "scroll", "box", "label", "markdown", "glyph", "image", "separator",
    "spacer", "progress", "button", "graph", "input", "select", "slider", "toggle",
    "dragSource", "dropZone",
  }) do
    ui[kind] = node(kind)
  end

  env = setmetatable({
    ui = ui,
    panel = {
      render = function(tree) table.insert(journal.renders, tree) end,
      close = function() end,
      openContextMenu = function() return false end,
      setWantsSecondTicks = function() end,
      setNeedsFrameTick = function() end,
    },
    barWidget = {
      setText = function(text) journal.text = text end,
      setColor = function(color, mode) journal.color = color; journal.colorMode = mode end,
      setTooltip = function(tooltip) journal.tooltip = tooltip end,
      clearTooltip = function() journal.tooltip = nil end,
      setGlyph = function(name) journal.glyph = name end,
      setGlyphColor = function() end,
      setImage = function(path, watch, width, height)
        journal.image = { path = path, width = width, height = height }
      end,
      setFont = function() end,
      isVertical = function() return false end,
      outputName = function() return "eDP-1" end,
      render = function(tree) table.insert(journal.renders, tree) end,
    },
    noctalia = {
      log = function() end,
      getConfig = function(key) return settings[key] end,
      tr = function(key, subst)
        local text = translations[key]
        if text == nil then
          text = key -- Noctalia falls back to the key; the checker reports it.
        end
        for name, value in pairs(subst or {}) do
          text = text:gsub("{" .. name .. "}", tostring(value))
        end
        return text
      end,
      notify = function() end,
      notifyError = function(title, body) table.insert(journal.notifications, body) end,
      openSettings = function() journal.settingsOpened = true end,
      togglePanel = function(id) journal.toggledPanel = id end,
      setUpdateInterval = function(ms) journal.updateInterval = ms end,
      isDarkMode = function() return world.darkMode ~= false end,
      commandExists = function(name) return (world.openers or {})[name] == true end,
      fileExists = function() return true end,
      expandPath = function(path) return path end,
      runAsync = function(command, callback)
        table.insert(journal.commands, command)
        if callback then
          callback(world.commandResult or { exitCode = 0, stdout = "", stderr = "" })
        end
        return true
      end,
      runStream = function(command, onLine)
        journal.streamCommand = command
        journal.stream = onLine
        return true
      end,
      json = {
        decode = function(text)
          if text == nil then
            return nil, "empty"
          end
          if text:match("UNREADABLE") then
            return nil, "not JSON"
          end
          if text:match("FAILED") then
            -- Built here rather than by overriding: a table literal cannot set a
            -- key to nil, and the whole point is a record with no panel.
            local failed = record()
            failed.panel = nil
            failed.windows = {}
            failed.totalWindows = 0
            failed.ok = false
            failed.error = "NaN rejects the API key (401)"
            return failed
          end
          return world.record or record()
        end,
      },
      string = {
        trim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end,
        urlEncode = function(text) return text end,
        urlDecode = function(text) return text end,
      },
      state = {
        values = {},
        set = function(key, value) journal.state = journal.state or {}; journal.state[key] = value end,
        get = function(key) return (journal.state or {})[key] end,
        watch = function(key, callback) journal.watch[key] = callback end,
      },
    },
  }, { __index = _G })
end

local function load(filename)
  local chunk, err = loadfile(PLUGIN .. "/" .. filename, "t", env)
  if chunk == nil then
    table.insert(failures, filename .. ": " .. tostring(err))
    print("FAIL " .. filename .. " does not load: " .. tostring(err))
    return false
  end
  local success, runtime = pcall(chunk)
  if not success then
    table.insert(failures, filename .. " raised on load: " .. tostring(runtime))
    print("FAIL " .. filename .. " raised on load: " .. tostring(runtime))
    return false
  end
  return true
end

-- Call into the script, turning any error into a reported failure rather than a
-- traceback: the point is the assertion, not the crash.
local function attempt(label, fn)
  local success, err = pcall(fn)
  check(success, label .. " (raised: " .. tostring(err) .. ")")
  return success
end

-- ------------------------------------------------------------------ walking

local function walk(node, visit)
  if node == nil then
    return
  end
  visit(node)
  for _, child in ipairs(node.children or {}) do
    walk(child, visit)
  end
end

local function collect(container, predicate)
  local found = {}
  for _, node in ipairs(container or {}) do
    walk(node, function(candidate)
      if predicate(candidate) then
        table.insert(found, candidate)
      end
    end)
  end
  return found
end

-- Which card, if any, is marked out from the others: the border value that
-- appears once. Style-agnostic on purpose, so changing the colours does not need
-- the harness edited.
local function oddCardOut(tree)
  local counts, order = {}, {}
  walk(tree, function(node)
    local border = node.props and node.props.border
    if border ~= nil and type(node.props.onClick) == "function" then
      if counts[border] == nil then
        counts[border] = 0
        table.insert(order, border)
      end
      counts[border] = counts[border] + 1
    end
  end)
  for _, border in ipairs(order) do
    if counts[border] == 1 then
      return border
    end
  end
  return nil
end

-- The list's cards are the clickable nodes; the overall entry is the one keyed
-- "overall", which is where the account's totals live.
local function clickableCards(tree)
  return collect({ tree }, function(node) return type(node.props.onClick) == "function" end)
end

local function nodeWithKey(tree, key)
  local found = collect({ tree }, function(node) return node.props.key == key end)
  return found[1]
end

local function firstLabelText(node)
  local text = nil
  walk(node, function(candidate)
    if text == nil and candidate.type == "label" then
      text = candidate.props.text
    end
  end)
  return text
end

local latest = function()
  return journal.renders[#journal.renders]
end

local function commandMatching(pattern)
  for _, command in ipairs(journal.commands) do
    if command:match(pattern) then
      return command
    end
  end
  return nil
end

-- ------------------------------------------------------------------- panel

section("panel.luau")

reset({ openers = { ["gio"] = true } })
if load("panel.luau") then
  local loaded = attempt("onOpen() renders", function() env.onOpen({}) end)
  local tree = latest()

  if loaded and tree ~= nil then
    check(collect({ tree }, function(n)
      return n.type == "image" and n.props.path ~= nil and n.props.path:match("^nan.*%.png$") ~= nil
    end)[1] ~= nil, "the logo is drawn from a raster")

    local scrolls = collect({ tree }, function(n) return n.type == "scroll" end)
    check(#scrolls == 1 and (scrolls[1].props.gap or 0) > 0,
      "the model list scrolls with a gap, so the cards are separated")

    local cards = collect({ tree }, function(n) return type(n.props.onClick) == "function" end)
    local overall = nodeWithKey(tree, "overall")
    check(overall ~= nil, "the list leads with the account's totals, as their own entry")
    check(cards[1].props.key == "overall", "and it comes first")
    local models = {}
    for _, card in ipairs(cards) do
      if card.props.key ~= "overall" then
        table.insert(models, card)
      end
    end
    check(#models == 3, "one clickable card per model (" .. #models .. " found)")

    local shaped = true
    for _, card in ipairs(cards) do
      if card.props.fill == nil or card.props.radius == nil or card.props.padding == nil then
        shaped = false
      end
    end
    check(shaped, "every card has a fill, a radius and padding")

    -- The host keeps props it is not given, so a card that stopped being selected
    -- would keep its highlight unless each card sets its own look every render.
    local complete = true
    for _, card in ipairs(cards) do
      if card.props.border == nil or card.props.borderWidth == nil or card.props.fill == nil then
        complete = false
      end
    end
    check(complete, "every card sets fill, border and borderWidth, so none can keep a stale highlight")
    check(oddCardOut(tree) ~= nil, "one card stands out as the selected one")

    check(oddCardOut(tree) ~= nil, "exactly one card is marked as selected")
    check(overall.props.border == oddCardOut(tree),
      "the overall entry is the one selected to begin with")

    check(collect({ tree }, function(n)
      return n.type == "button" and n.props.glyph == "settings" end)[1] ~= nil,
      "the header carries the settings cog")

    -- The click that raised for the user: a card's closure calling render.
    local clickedModel = firstLabelText(models[2])
    local rendersBefore = #journal.renders
    if attempt("clicking a model re-renders", function() models[2].props.onClick() end) then
      check(#journal.renders == rendersBefore + 1, "the click produced a new render")
      check(oddCardOut(latest()) ~= nil, "still exactly one card stands out after the click")
      check(journal.state ~= nil and journal.state.selected == clickedModel,
        "the selection is remembered for the next time the panel opens (" ..
        tostring(journal.state and journal.state.selected) .. ")")
      -- The exact complaint: the card that was selected kept its highlight. So
      -- assert the swap, not just the presence of one.
      local now = clickableCards(latest())
      local nowOverall = nodeWithKey(latest(), "overall")
      check(nowOverall.props.border ~= overall.props.border,
        "the overall entry let its highlight go")
      check(nodeWithKey(latest(), "model-" .. clickedModel).props.border == overall.props.border,
        "the clicked model took it")
      local marked = collect({ latest() }, function(n)
        return type(n.props.onClick) == "function" and n.props.border == overall.props.border
      end)
      check(#marked == 1, "and only the clicked card has it (" .. #marked .. " have it)")
      local moved = collect({ latest() }, function(n)
        return n.type == "label" and n.props.fontSize == 20 and n.props.text == clickedModel end)
      check(#moved > 0, "the detail column moved to the clicked model (" .. tostring(clickedModel) .. ")")
      check(nodeWithKey(latest(), "usage-bars") == nil and nodeWithKey(latest(), "contributions") == nil,
        "and a model's detail carries neither the totals nor the split")
    end

    -- The totals live in the overall entry, with the split behind them.
    local contributions = nodeWithKey(tree, "contributions")
    check(contributions ~= nil, "the overall detail says where the totals came from")
    if contributions ~= nil then
      local shares, sum = 0, 0
      walk(contributions, function(node)
        local percent = type(node.props.text) == "string" and node.props.text:match("^(%d+)%%$")
        if node.type == "label" and percent ~= nil then
          shares = shares + 1
          sum = sum + tonumber(percent)
        end
      end)
      check(shares == 3, "one share per model (" .. shares .. " found)")
      check(sum >= 99 and sum <= 101, "the shares add up to the whole (" .. sum .. "%)")
    end
    check(nodeWithKey(tree, "period") == nil,
      "the account's period is not repeated in every model's detail")

    -- And clicking the overall entry again comes back to it.
    if attempt("clicking the overall entry", function()
      nodeWithKey(latest(), "overall").props.onClick()
    end) then
      check(nodeWithKey(latest(), "usage-bars") ~= nil, "the totals come back")
      check(journal.state ~= nil and journal.state.selected == "#overall",
        "and the choice is remembered as the overall entry")
    end

    -- Refresh: the tool is run and the answer is painted.
    reset({ openers = { ["gio"] = true } })
    if load("panel.luau") then
      env.onOpen({})
      local beforeRefresh = #journal.renders
      attempt("onRefresh()", function() env.onRefresh() end)
      check(journal.commands[1] ~= nil and journal.commands[1]:match("json %-%-force") ~= nil,
        "refresh asks the tool for a fresh record (" .. tostring(journal.commands[1]) .. ")")
      check(journal.state ~= nil and journal.state.report ~= nil, "the fresh record is published for the widget")
      check(#journal.renders > beforeRefresh, "refresh re-rendered")
    end

    -- A caller whose command fails: the log gets it, the panel still paints.
    reset({ openers = {}, commandResult = { exitCode = 1, stdout = "", stderr = "boom" } })
    if load("panel.luau") then
      env.onOpen({})
      local rendersBeforeFailure = #journal.renders
      attempt("onRefresh() with a failing command", function() env.onRefresh() end)
      check(#journal.renders > rendersBeforeFailure, "a failed refresh still paints")
    end

    -- The link button: no opener anywhere is reported, not swallowed.
    reset({ openers = {} })
    if load("panel.luau") then
      env.onOpen({})
      attempt("onOpenSite() with no opener", function() env.onOpenSite() end)
      check(journal.notifications[1] ~= nil, "a missing opener is reported to the user")
    end

    reset({ openers = { ["gio"] = true } })
    if load("panel.luau") then
      env.onOpen({})
      attempt("onOpenSite()", function() env.onOpenSite() end)
      check(commandMatching("cloud%.nan%.builders") == "gio open https://cloud.nan.builders",
        "the link goes through gio when xdg-open is absent (" ..
        tostring(commandMatching("cloud%.nan%.builders")) .. ")")
    end

    reset({ openers = { ["xdg-open"] = true } })
    if load("panel.luau") then
      env.onOpen({})
      attempt("onOpenSite() with only xdg-open", function() env.onOpenSite() end)
      check(commandMatching("cloud%.nan%.builders") == "xdg-open https://cloud.nan.builders",
        "xdg-open is used when that is what exists (" ..
        tostring(commandMatching("cloud%.nan%.builders")) .. ")")
    end

    -- The logo: ghost by default, in the ink the theme will read.
    for _, case in ipairs({
      { name = "ghost on a dark theme", settings = { icon_style = "ghost" }, dark = true,
        want = "nan-ghost-white.png" },
      { name = "ghost on a light theme", settings = { icon_style = "ghost" }, dark = false,
        want = "nan-ghost-black.png" },
      { name = "the coloured mark", settings = { icon_style = "color" }, dark = true,
        want = "nan.png" },
    }) do
      reset({ openers = {}, settings = case.settings, darkMode = case.dark })
      if load("panel.luau") then
        env.onOpen({})
        local drawn = collect({ latest() }, function(n)
          return n.type == "image" and n.props.width == 20 end)
        check(drawn[1] ~= nil and drawn[1].props.path == case.want,
          "the panel draws " .. case.want .. " with " .. case.name ..
          " (got " .. tostring(drawn[1] and drawn[1].props.path) .. ")")
      end
    end

    -- Consumption: the numbers as bars when the tool sends them...
    reset({ openers = {} })
    if load("panel.luau") then
      env.onOpen({})
      local card = nodeWithKey(latest(), "usage-bars")
      check(card ~= nil, "the totals card is in the overall detail")
      -- Scoped to the card: the contributions below it draw bars of the same
      -- height, and counting those as periods would be nonsense.
      local bars = card ~= nil and collect({ card }, function(n) return n.type == "progress" end) or {}
      check(#bars == 3, "one bar per period (" .. #bars .. " bars)")
    end

    -- ...and the printed line when it does not (an older tool).
    local older = record()
    older.usage = nil
    reset({ openers = {}, record = older })
    if load("panel.luau") then
      env.onOpen({})
      local line = collect({ latest() }, function(n) return n.props.key == "usage-line" end)
      check(#line == 1, "an older tool's consumption line still shows, without bars")
    end

    reset({ openers = {} })
    if load("panel.luau") then
      env.onOpen({})
      attempt("onOpenSettings()", function() env.onOpenSettings() end)
      check(journal.settingsOpened == true, "the cog opens the plugin's settings")
    end

    -- No record and nothing to fetch: the panel says so instead of painting an
    -- empty surface.
    reset({ openers = {}, commandResult = { exitCode = 1, stdout = "", stderr = "no key" } })
    if load("panel.luau") then
      journal.state = nil
      attempt("onOpen() before any record", function() env.onOpen() end)
      local texts = {}
      walk(latest(), function(n)
        if n.type == "label" then table.insert(texts, n.props.text or "") end
      end)
      check(table.concat(texts, " "):match("Waiting for") ~= nil, "a panel opened before the first record says so")
    end
  end
end

-- ------------------------------------------------------------------- widget

section("bar.luau")

-- The widget paints a declarative tree — a bar widget has no other way to draw a
-- gauge — so these assertions read the tree rather than imperative calls.
local function labelTexts(tree)
  local out = {}
  walk(tree, function(node)
    if node.type == "label" then
      table.insert(out, node.props.text or "")
    end
  end)
  return out
end

local function hasText(tree, want)
  for _, text in ipairs(labelTexts(tree)) do
    if text == want then
      return true
    end
  end
  return false
end

local function images(tree)
  return collect({ tree }, function(node) return node.type == "image" end)
end

local function gauges(tree)
  return collect({ tree }, function(node) return node.type == "progress" end)
end

reset({ openers = {} })
if load("bar.luau") then
  check(journal.streamCommand ~= nil and journal.streamCommand:match("watch %-%-json") ~= nil,
    "the widget starts a watch stream (" .. tostring(journal.streamCommand) .. ")")

  if journal.stream ~= nil then
    attempt("feeding a record", function() journal.stream('{"ok":true}') end)
    local tree = latest()

    check(tree ~= nil, "the widget painted a tree")
    check(hasText(tree, "96.4% · 2d"), "the widget shows the tool's own text")
    check(images(tree)[1] ~= nil and images(tree)[1].props.path == "nan-ghost-white.png",
      "the widget draws the ghost logo on a dark theme")

    -- The gauge, which the widget never used to draw at all: the setting comes
    -- from the tool's own config, carried in the record.
    local drawn = gauges(tree)
    check(#drawn == 1, "the gauge is drawn (" .. #drawn .. " found)")
    check(drawn[1] ~= nil and math.abs(drawn[1].props.progress - 0.964) < 0.001,
      "the gauge shows the panel model's percentage (" ..
      (drawn[1] and tostring(drawn[1].props.progress) or "nothing") .. ")")
    check(drawn[1] ~= nil and drawn[1].props.fill == "#e01b24",
      "the gauge takes the level's colour")
    check(journal.state ~= nil and journal.state.report ~= nil, "the record is published for the panel")

    -- Values only: the tool's caption is a sentence, and its tail is what a
    -- tooltip cuts off.
    local rows = journal.tooltip
    check(type(rows) == "table" and #rows >= 4, "the tooltip lists the models and the aggregates")
    local longest, prose = 0, false
    for _, row in ipairs(rows or {}) do
      local value = tostring(row.value or "")
      longest = math.max(longest, #value)
      if value:match("resets in") or value:match("Period from") or value:match("at this rate") then
        prose = true
      end
    end
    check(not prose, "the tooltip carries values, not sentences")
    check(longest <= 24, "no tooltip entry is long enough to be cut off (" .. longest .. " chars)")

    attempt("feeding a failed record", function() journal.stream('{"FAILED":true}') end)
    check(hasText(latest(), "—"), "a record with no data shows a dash")
    check(#gauges(latest()) == 0, "and no gauge, rather than a hollow one")

    local before = #journal.renders
    attempt("feeding an unreadable record", function() journal.stream('{"UNREADABLE":true}') end)
    check(#journal.renders == before, "an unreadable record does not repaint")
  end

  -- The gauge follows the tool's setting: none hides it, and ring — which a bar
  -- widget cannot draw — is the bar, as the README says.
  for _, case in ipairs({
    { gauge = "none", want = 0 }, { gauge = "bar", want = 1 }, { gauge = "ring", want = 1 },
  }) do
    local withGauge = record()
    withGauge.gauge = case.gauge
    reset({ openers = {}, record = withGauge })
    if load("bar.luau") then
      if journal.stream ~= nil then
        journal.stream('{"ok":true}')
        check(#gauges(latest()) == case.want,
          "gauge = " .. case.gauge .. " draws " .. case.want .. " bar(s) (" ..
          #gauges(latest()) .. ")")
      end
    end
  end

  -- The coloured mark, when that is what the setting asks for.
  reset({ openers = {}, settings = { icon_style = "color" } })
  if load("bar.luau") then
    if journal.stream ~= nil then
      journal.stream('{"ok":true}')
      check(images(latest())[1] ~= nil and images(latest())[1].props.path == "nan.png",
        "the widget draws the coloured mark when asked")
    end
  end

  reset({ openers = {} })
  if load("bar.luau") then
    if journal.stream ~= nil then
      journal.stream('{"ok":true}')
    end
    attempt("update()", function() env.update() end)
    attempt("onClick()", function() env.onClick() end)
    check(journal.toggledPanel == "nan-usage/quota:panel",
      "clicking opens the plugin's own panel (" .. tostring(journal.toggledPanel) .. ")")
  end
end

-- -------------------------------------------------------------------- verdict

print()
if #failures > 0 then
  print(#failures .. " failure(s)")
  os.exit(1)
end
print(ok .. " checks pass")
