local PROTOCOL = "miner_admin"
local DEFAULT_DURATION = 90
local SEND_EVERY = 2
local REDRAW_EVERY = 1
local MINER_ONLINE_AFTER = 150
local MINER_STALE_AFTER = 300
local QUEUE_FILE = "admin_monitor_command_queue"
local MAX_HISTORY = 30
local DISK_MIN_FREE = 4096
local DISK_KEEP_LINES = 500

local miners = {}
local histories = {}
local activeSends = {}
local buttons = {}
local rowTargets = {}
local selectedMinerId = nil
local monitor = nil
local monitorSide = nil
local statsDiskPath = nil
local diskAlert = nil
local nextSeq = 1

local function now()
  return os.epoch("utc")
end

local function log(msg)
  print("[Monitor] "..msg)
end

local function findStatsDisk()
  if statsDiskPath and fs.exists(statsDiskPath) then
    return statsDiskPath
  end

  statsDiskPath = nil

  if not disk or not disk.isPresent then
    return nil
  end

  for _,side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "drive" and disk.isPresent(side) then
      local path = disk.getMountPath(side)

      if path and fs.exists(path) then
        statsDiskPath = path
        return statsDiskPath
      end
    end
  end

  return nil
end

local function trimStatsLog(filePath)
  if not fs.exists(filePath) then return true end

  local f = fs.open(filePath, "r")
  if not f then return false end

  local lines = {}
  while true do
    local line = f.readLine()
    if not line then break end

    table.insert(lines, line)
    if #lines > DISK_KEEP_LINES then
      table.remove(lines, 1)
    end
  end
  f.close()

  f = fs.open(filePath, "w")
  if not f then return false end

  for _,line in ipairs(lines) do
    f.writeLine(line)
  end
  f.close()

  return true
end

local function appendStatsLog(id, message)
  local path = findStatsDisk()

  if not path then
    diskAlert = nil
    return
  end

  local filePath = fs.combine(path, "miner_stats.log")
  local free = fs.getFreeSpace(path)

  if free and free < DISK_MIN_FREE then
    if not trimStatsLog(filePath) then
      diskAlert = "DISK TRIM ERR"
      return
    end
  end

  free = fs.getFreeSpace(path)
  if free and free < 512 then
    diskAlert = "DISK FULL"
    return
  end

  local f = fs.open(filePath, "a")

  if not f then
    if trimStatsLog(filePath) then
      f = fs.open(filePath, "a")
    end
  end

  if not f then
    diskAlert = "DISK WRITE ERR"
    return
  end

  f.writeLine(textutils.serialize({
    t=now(),
    id=id,
    kind=message.kind,
    state=message.state,
    alert=message.alert,
    x=message.x,
    y=message.y,
    z=message.z,
    fuel=message.fuel,
    fuelLimit=message.fuelLimit,
    minedLastMinute=message.minedLastMinute,
    minedLastMinuteTotal=message.minedLastMinuteTotal,
    minedTotal=message.minedTotal,
    miningMode=message.miningMode,
    wantedOrePatterns=message.wantedOrePatterns,
    normalLowestY=message.normalLowestY,
    targetY=message.targetY
  }))
  f.close()

  diskAlert = nil
end

local function writeTable(path, data)
  local f = fs.open(path, "w")
  f.write(textutils.serialize(data))
  f.close()
end

local function readTable(path)
  local f = fs.open(path, "r")
  local data = textutils.unserialize(f.readAll())
  f.close()
  return data
end

local function saveQueue()
  writeTable(QUEUE_FILE, activeSends)
end

local function loadQueue()
  if not fs.exists(QUEUE_FILE) then return end

  local data = readTable(QUEUE_FILE)
  if type(data) ~= "table" then return end

  local t = now()
  for _,entry in ipairs(data) do
    if type(entry) == "table" and type(entry.message) == "table" and type(entry.untilAt) == "number" and t <= entry.untilAt then
      entry.nextAt = 0
      table.insert(activeSends, entry)
    end
  end
end

local function openWirelessModem()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local modem = peripheral.wrap(name)

      if modem and modem.isWireless and modem.isWireless() then
        rednet.open(name)
        log("Wireless/Ender Modem offen auf Seite: "..name)
        return true
      end
    end
  end

  return false
end

local function openMonitor()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      monitor = peripheral.wrap(name)
      monitorSide = name
      monitor.setTextScale(0.5)
      monitor.setBackgroundColor(colors.black)
      monitor.setTextColor(colors.white)
      monitor.clear()
      log("Monitor offen auf Seite: "..name)
      return true
    end
  end

  return false
end

local function queueCommand(message, duration)
  duration = duration or DEFAULT_DURATION
  message.seq = message.seq or nextSeq
  nextSeq = nextSeq + 1

  table.insert(activeSends, {
    message=message,
    untilAt=now() + duration * 1000,
    nextAt=0
  })

  saveQueue()
end

local function processActiveSends()
  local t = now()
  local kept = {}

  for _,entry in ipairs(activeSends) do
    if t <= entry.untilAt then
      if t >= entry.nextAt then
        local message = entry.message

        if message.targetId and message.targetId ~= "all" and message.targetId ~= "*" then
          rednet.send(message.targetId, message, PROTOCOL)
        else
          rednet.broadcast(message, PROTOCOL)
        end

        entry.nextAt = t + SEND_EVERY * 1000
      end

      table.insert(kept, entry)
    end
  end

  activeSends = kept
  saveQueue()
end

local function rememberMiner(sender, message)
  if type(message) ~= "table" or message.type ~= "miner_status" then
    return
  end

  local id = message.id or sender
  miners[id] = {
    rednetId=sender,
    last=now(),
    status=message
  }

  appendStatsLog(id, message)

  histories[id] = histories[id] or {}

  local fuel = tonumber(message.fuel) or 0
  local fuelLimit = tonumber(message.fuelLimit) or 1
  local fuelPct = fuel / math.max(1, fuelLimit)

  table.insert(histories[id], {
    t=now(),
    mined=tonumber(message.minedLastMinuteTotal) or 0,
    fuelPct=fuelPct
  })

  while #histories[id] > MAX_HISTORY do
    table.remove(histories[id], 1)
  end
end

local function sortedMinerIds()
  local ids = {}

  for id in pairs(miners) do
    table.insert(ids, id)
  end

  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  return ids
end

local function writeAt(target, x, y, text, fg, bg)
  local w, h = target.getSize()
  text = tostring(text or "")

  if y < 1 or y > h or x > w or #text == 0 then return end

  if x < 1 then
    text = text:sub(2 - x)
    x = 1
  end

  if x + #text - 1 > w then
    text = text:sub(1, w - x + 1)
  end

  if #text == 0 then return end

  local oldFg = target.getTextColor()
  local oldBg = target.getBackgroundColor()

  if fg then target.setTextColor(fg) end
  if bg then target.setBackgroundColor(bg) end
  target.setCursorPos(x, y)
  target.write(text)
  target.setTextColor(oldFg)
  target.setBackgroundColor(oldBg)
end

local function fill(target, x, y, w, h, bg)
  local maxW, maxH = target.getSize()
  if w <= 0 or h <= 0 or x > maxW or y > maxH then return end

  if x < 1 then
    w = w + x - 1
    x = 1
  end

  if y < 1 then
    h = h + y - 1
    y = 1
  end

  if x + w - 1 > maxW then
    w = maxW - x + 1
  end

  if y + h - 1 > maxH then
    h = maxH - y + 1
  end

  if w <= 0 or h <= 0 then return end

  local oldBg = target.getBackgroundColor()
  target.setBackgroundColor(bg)

  for row=y,y+h-1 do
    target.setCursorPos(x, row)
    target.write(string.rep(" ", w))
  end

  target.setBackgroundColor(oldBg)
end

local function addButton(id, label, x, y, w, h, bg, fg, action)
  table.insert(buttons, {
    id=id,
    label=label,
    x=x,
    y=y,
    w=w,
    h=h,
    bg=bg,
    fg=fg or colors.white,
    action=action
  })
end

local function drawButton(target, button)
  fill(target, button.x, button.y, button.w, button.h, button.bg)
  local labelX = button.x + math.max(0, math.floor((button.w - #button.label) / 2))
  local labelY = button.y + math.floor(button.h / 2)
  writeAt(target, labelX, labelY, button.label, button.fg, button.bg)
end

local function fuelColor(status)
  local fuel = tonumber(status.fuel) or 0
  local limit = tonumber(status.fuelLimit) or 1
  local pct = fuel / math.max(1, limit)

  if pct < 0.15 then return colors.red end
  if pct < 0.35 then return colors.orange end
  return colors.lime
end

local function ageColor(age)
  if age > 180 then return colors.red end
  if age > 90 then return colors.orange end
  return colors.lime
end

local function stateColor(status)
  if status.state == "crashed" or status.state == "startup_error" or status.state == "stopped" then return colors.red end
  if status.alert then return colors.red end
  if status.state == "waiting" then return colors.yellow end
  if status.state == "unloading" then return colors.orange end
  if status.state == "refueling" then return colors.cyan end
  if status.kind == "command_ack" then return colors.lime end
  return colors.lightBlue
end

local function drawSparkline(target, x, y, w, values, maxValue, color, bg)
  if w <= 0 then return end

  local count = #values
  local start = math.max(1, count - w + 1)
  local pos = x

  for i=start,count do
    local value = values[i] or 0
    local mark = "."

    if maxValue > 0 then
      local pct = value / maxValue
      if pct >= 0.75 then
        mark = "#"
      elseif pct >= 0.5 then
        mark = "+"
      elseif pct >= 0.25 then
        mark = "-"
      end
    end

    writeAt(target, pos, y, mark, color, bg)
    pos = pos + 1
  end
end

local function clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function shortNumber(value)
  value = tonumber(value) or 0

  if value >= 1000000 then
    return string.format("%.1fm", value / 1000000)
  end

  if value >= 10000 then
    return string.format("%.1fk", value / 1000)
  end

  return tostring(math.floor(value + 0.5))
end

local function safeText(value, maxLen)
  local text = tostring(value or "-")
  if maxLen and maxLen > 0 and #text > maxLen then
    return text:sub(1, maxLen)
  end
  return text
end

local function commandTarget()
  if selectedMinerId and miners[selectedMinerId] then
    return selectedMinerId
  end

  return "all"
end

local function commandScopeText()
  local target = commandTarget()

  if target == "all" then
    return "ALL"
  end

  return "#"..tostring(target)
end

local function drawBar(target, x, y, w, pct, fillColor, bg, emptyColor)
  if w <= 0 then return end

  pct = clamp(tonumber(pct) or 0, 0, 1)
  local filled = math.floor(w * pct + 0.5)

  if filled > 0 then
    fill(target, x, y, filled, 1, fillColor)
  end

  if filled < w then
    fill(target, x + filled, y, w - filled, 1, emptyColor or colors.gray)
  end

  target.setBackgroundColor(bg or colors.black)
end

local function drawChart(target, x, y, w, h, values, maxValue, color, bg)
  if w <= 0 or h <= 0 then return end

  fill(target, x, y, w, h, bg)
  local count = #values
  if count == 0 then
    writeAt(target, x + 1, y + math.floor(h / 2), "no history", colors.gray, bg)
    return
  end

  maxValue = math.max(tonumber(maxValue) or 0, 1)
  local start = math.max(1, count - w + 1)
  local pos = x

  for i=start,count do
    local value = tonumber(values[i]) or 0
    local barH = clamp(math.floor((value / maxValue) * h + 0.5), 0, h)

    if barH > 0 then
      fill(target, pos, y + h - barH, 1, barH, color)
    end

    pos = pos + 1
  end
end

local function drawPanel(target, x, y, w, h, title, accent)
  fill(target, x, y, w, h, colors.black)
  fill(target, x, y, w, 1, accent or colors.gray)
  writeAt(target, x + 1, y, safeText(title, math.max(1, w - 2)), colors.white, accent or colors.gray)
end

local function drawMetric(target, x, y, w, h, title, value, detail, accent)
  drawPanel(target, x, y, w, h, title, accent)
  writeAt(target, x + 1, y + 2, safeText(value, math.max(1, w - 2)), colors.white, colors.black)

  if h >= 5 and detail then
    writeAt(target, x + 1, y + 4, safeText(detail, math.max(1, w - 2)), colors.lightGray, colors.black)
  end
end

local function historyValues(id, key)
  local values = {}
  local maxValue = 0

  for _,point in ipairs(histories[id] or {}) do
    local value = point[key] or 0
    table.insert(values, value)
    if value > maxValue then maxValue = value end
  end

  return values, maxValue
end

local function drawMonitor()
  buttons = {}
  rowTargets = {}
  local w, h = monitor.getSize()
  local ids = sortedMinerIds()
  local minerCount = #ids
  local onlineCount = 0
  local alertCount = 0
  local waitingCount = 0
  local totalMined = 0
  local totalRate = 0
  local fuelSum = 0

  for _,id in ipairs(ids) do
    local entry = miners[id]
    local s = entry.status
    local age = math.floor((now() - entry.last) / 1000)
    local fuel = tonumber(s.fuel) or 0
    local limit = tonumber(s.fuelLimit) or 1

    if age <= MINER_ONLINE_AFTER then onlineCount = onlineCount + 1 end
    if s.alert or age > MINER_STALE_AFTER then alertCount = alertCount + 1 end
    if s.state == "waiting" then waitingCount = waitingCount + 1 end

    totalMined = totalMined + (tonumber(s.minedTotal) or 0)
    totalRate = totalRate + (tonumber(s.minedLastMinuteTotal) or 0)
    fuelSum = fuelSum + (fuel / math.max(1, limit))
  end

  local avgFuel = 0
  if minerCount > 0 then
    avgFuel = fuelSum / minerCount
  end

  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  fill(monitor, 1, 1, w, 3, colors.black)
  fill(monitor, 1, 1, w, 1, colors.blue)
  writeAt(monitor, 2, 1, "MINER OPS // LIVE FLEET", colors.white, colors.blue)
  writeAt(monitor, math.max(2, w - 18), 1, textutils.formatTime(os.time(), true), colors.white, colors.blue)
  writeAt(monitor, 2, 2, "ONLINE "..onlineCount.."/"..minerCount.."   QUEUE "..#activeSends.."   RATE "..shortNumber(totalRate).."/min", colors.lightGray, colors.black)

  local diskText = "NO DISK"
  local diskColor = colors.lightGray
  local diskPath = findStatsDisk()

  if diskAlert then
    diskText = diskAlert
    diskColor = colors.red
  elseif diskPath then
    diskText = "DISK "..tostring(fs.getFreeSpace(diskPath)).."B"
    diskColor = colors.lime
  end

  writeAt(monitor, 2, 3, diskText, diskColor, colors.black)

  local buttonW = math.min(16, math.max(12, math.floor(w * 0.22)))
  local bx = w - buttonW + 1
  local mainW = bx - 2
  local actionY = 5

  fill(monitor, bx - 1, 1, 1, h, colors.gray)
  writeAt(monitor, bx, 3, "CMD "..safeText(commandScopeText(), buttonW - 4), colors.lightGray, colors.black)

  addButton("scope", commandTarget() == "all" and "TARGET ALL" or "TARGET SEL", bx, actionY, buttonW, 3, colors.blue, colors.white, function()
    selectedMinerId = nil
  end)

  addButton("start", "START "..commandScopeText(), bx, actionY + 4, buttonW, 3, colors.green, colors.black, function()
    queueCommand({ command="start", targetId=commandTarget() }, DEFAULT_DURATION)
  end)

  addButton("unload", "UNLOAD "..commandScopeText(), bx, actionY + 8, buttonW, 3, colors.orange, colors.black, function()
    queueCommand({ command="unload", targetId=commandTarget() }, DEFAULT_DURATION)
  end)

  addButton("refuel", "REFUEL "..commandScopeText(), bx, actionY + 12, buttonW, 3, colors.cyan, colors.black, function()
    queueCommand({ command="refuel", targetId=commandTarget() }, DEFAULT_DURATION)
  end)

  addButton("ping", "PING "..commandScopeText(), bx, actionY + 16, buttonW, 3, colors.purple, colors.white, function()
    queueCommand({ command="start", targetId=commandTarget() }, 20)
  end)

  addButton("clear", "CLEAR", bx, actionY + 20, buttonW, 3, colors.gray, colors.white, function()
    miners = {}
    selectedMinerId = nil
  end)

  for _,button in ipairs(buttons) do
    if button.y + button.h - 1 <= h then
      drawButton(monitor, button)
    end
  end

  local cardW = math.max(6, math.floor((mainW - 3) / 4))
  local cardY = 5
  drawMetric(monitor, 1, cardY, cardW, 5, "FLEET", onlineCount.."/"..minerCount, alertCount.." alerts", alertCount > 0 and colors.red or colors.green)
  drawMetric(monitor, cardW + 2, cardY, cardW, 5, "FUEL", math.floor(avgFuel * 100 + 0.5).."%", "avg reserve", avgFuel < 0.25 and colors.orange or colors.cyan)
  drawMetric(monitor, cardW * 2 + 3, cardY, cardW, 5, "ORE/MIN", shortNumber(totalRate), "last sample", colors.yellow)
  drawMetric(monitor, cardW * 3 + 4, cardY, math.max(4, mainW - (cardW * 3 + 3)), 5, "TOTAL", shortNumber(totalMined), waitingCount.." waiting", colors.purple)

  local chartY = cardY + 6
  local chartH = 6
  local chartW = math.max(8, math.floor((mainW - 1) / 2))
  local fleetRates = {}
  local fleetFuels = {}
  local rateMax = 1

  for _,id in ipairs(ids) do
    local s = miners[id].status
    local rate = tonumber(s.minedLastMinuteTotal) or 0
    local fuel = tonumber(s.fuel) or 0
    local limit = tonumber(s.fuelLimit) or 1

    table.insert(fleetRates, rate)
    table.insert(fleetFuels, fuel / math.max(1, limit))
    if rate > rateMax then rateMax = rate end
  end

  drawPanel(monitor, 1, chartY, chartW, chartH + 2, "ORE RATE BY MINER", colors.yellow)
  drawChart(monitor, 2, chartY + 2, chartW - 2, chartH - 1, fleetRates, rateMax, colors.yellow, colors.black)
  drawPanel(monitor, chartW + 2, chartY, mainW - chartW - 1, chartH + 2, "FUEL BY MINER", colors.cyan)
  drawChart(monitor, chartW + 3, chartY + 2, mainW - chartW - 3, chartH - 1, fleetFuels, 1, colors.cyan, colors.black)

  local listY = chartY + chartH + 3
  local detailRows = 0
  if selectedMinerId and miners[selectedMinerId] and h - listY > 13 then
    detailRows = 8
  end

  local listH = h - listY + 1 - detailRows
  if detailRows > 0 then listH = listH - 1 end

  drawPanel(monitor, 1, listY, mainW, math.max(3, listH), "ACTIVE MINERS", colors.gray)

  if minerCount == 0 then
    writeAt(monitor, 3, listY + 2, "Waiting for miner_status packets...", colors.lightGray, colors.black)
  else
    local row = listY + 2

    for _,id in ipairs(ids) do
      if row >= listY + listH then break end

      local entry = miners[id]
      local status = entry.status
      local age = math.floor((now() - entry.last) / 1000)
      local fuel = tonumber(status.fuel) or 0
      local limit = tonumber(status.fuelLimit) or 1
      local fuelPct = fuel / math.max(1, limit)
      local bg = selectedMinerId == id and colors.gray or colors.black
      local state = status.alert or status.state or status.kind or "?"
      local stateCol = stateColor(status)
      local pos = tostring(status.x)..","..tostring(status.y)..","..tostring(status.z)

      if age > MINER_STALE_AFTER then
        state = "stale"
        stateCol = colors.red
      end

      fill(monitor, 2, row, mainW - 2, 2, bg)
      rowTargets[row] = id
      rowTargets[row + 1] = id

      writeAt(monitor, 3, row, "#"..safeText(id, 4), colors.white, bg)
      writeAt(monitor, 9, row, safeText(state, 12), stateCol, bg)
      writeAt(monitor, 23, row, tostring(age).."s", ageColor(age), bg)
      writeAt(monitor, 31, row, shortNumber(status.minedLastMinuteTotal or 0).."/m", colors.yellow, bg)

      if mainW > 48 then
        writeAt(monitor, 40, row, safeText(pos, mainW - 40), colors.lightBlue, bg)
      end

      writeAt(monitor, 3, row + 1, "fuel", colors.lightGray, bg)
      drawBar(monitor, 9, row + 1, math.max(6, mainW - 26), fuelPct, fuelColor(status), bg, colors.gray)
      writeAt(monitor, mainW - 14, row + 1, math.floor(fuelPct * 100 + 0.5).."%", fuelColor(status), bg)

      row = row + 3
    end
  end

  if detailRows > 0 then
    local detailY = h - detailRows + 1
    local s = miners[selectedMinerId].status
    local minedValues, minedMax = historyValues(selectedMinerId, "mined")
    local fuelValues = {}
    local oreMode = "default"

    for _,point in ipairs(histories[selectedMinerId] or {}) do
      table.insert(fuelValues, point.fuelPct or 0)
    end

    if s.wantedOrePatterns then
      oreMode = "patterns"
    elseif s.wantedOres then
      oreMode = "custom"
    end

    drawPanel(monitor, 1, detailY, mainW, detailRows, "DETAIL #"..tostring(selectedMinerId), colors.blue)
    writeAt(monitor, 3, detailY + 1, "State "..safeText(s.alert or s.state or s.kind, 14), stateColor(s), colors.black)
    writeAt(monitor, 24, detailY + 1, "Fuel "..tostring(s.fuel).."/"..tostring(s.fuelLimit), fuelColor(s), colors.black)
    writeAt(monitor, 3, detailY + 2, "Total "..shortNumber(s.minedTotal).."  Last "..shortNumber(s.minedLastMinuteTotal or 0).."/min", colors.yellow, colors.black)
    writeAt(monitor, 3, detailY + 3, safeText("Mode "..tostring(s.miningMode).." / "..oreMode.."  Y "..tostring(s.targetY).."  low "..tostring(s.normalLowestY or "-"), mainW - 4), colors.lightGray, colors.black)
    writeAt(monitor, 3, detailY + 4, safeText("Pos "..tostring(s.x)..","..tostring(s.y)..","..tostring(s.z).."  Cmd "..tostring(s.lastCommand or "-").."#"..tostring(s.lastCommandSeq or "-"), mainW - 4), colors.lightBlue, colors.black)
    if s.crashError then
      writeAt(monitor, 3, detailY + 5, safeText("Error "..tostring(s.crashError), mainW - 4), colors.red, colors.black)
    end
    writeAt(monitor, 3, detailY + 6, "ORE", colors.yellow, colors.black)
    drawSparkline(monitor, 8, detailY + 6, math.max(1, mainW - 8), minedValues, math.max(1, minedMax), colors.yellow, colors.black)
    writeAt(monitor, 3, detailY + 7, "FUEL", colors.cyan, colors.black)
    drawSparkline(monitor, 8, detailY + 7, math.max(1, mainW - 8), fuelValues, 1, colors.cyan, colors.black)
  end
end

local function rednetLoop()
  local nextDraw = 0

  while true do
    processActiveSends()

    local sender, message = rednet.receive(PROTOCOL, 0.5)
    if sender and message then
      rememberMiner(sender, message)
    end

    if now() >= nextDraw then
      drawMonitor()
      nextDraw = now() + REDRAW_EVERY * 1000
    end
  end
end

local function monitorTouchLoop()
  while true do
    local _, side, x, y = os.pullEvent("monitor_touch")

    if monitorSide == side then
      if rowTargets[y] then
        selectedMinerId = rowTargets[y]
        drawMonitor()
      end

      for _,button in ipairs(buttons) do
        if x >= button.x and x < button.x + button.w and y >= button.y and y < button.y + button.h then
          button.action()
          drawMonitor()
          break
        end
      end
    end
  end
end

if not openWirelessModem() then
  error("Kein Wireless/Ender Modem gefunden.")
end

if not openMonitor() then
  error("Kein Monitor gefunden.")
end

loadQueue()
drawMonitor()
parallel.waitForAny(rednetLoop, monitorTouchLoop)
