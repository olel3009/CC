local PROTOCOL = "miner_admin"
local DEFAULT_DURATION = 90
local SEND_EVERY = 2
local QUEUE_FILE = "admin_command_queue"

local miners = {}
local activeSends = {}
local nextSeq = 1
local selectedMinerId = nil
local listPage = 1
local statusMessage = "Bereit."

local function now()
  return os.epoch("utc")
end

local function log(msg)
  print("[Control] "..msg)
end

local function writeTable(path, data)
  local tmpPath = path..".tmp"

  if fs.exists(tmpPath) then
    fs.delete(tmpPath)
  end

  local f = fs.open(tmpPath, "w")
  if not f then
    return false, "Kann Datei nicht schreiben: "..tostring(tmpPath)
  end

  local ok, err = pcall(function()
    f.write(textutils.serialize(data))
    f.close()
  end)

  if not ok then
    pcall(function() f.close() end)
    if fs.exists(tmpPath) then
      fs.delete(tmpPath)
    end
    return false, err
  end

  if fs.exists(path) then
    fs.delete(path)
  end

  fs.move(tmpPath, path)
  return true
end

local function readTable(path)
  local f = fs.open(path, "r")
  if not f then
    return nil, "Kann Datei nicht lesen: "..tostring(path)
  end

  local ok, content = pcall(function()
    local text = f.readAll()
    f.close()
    return text
  end)

  if not ok then
    pcall(function() f.close() end)
    return nil, content
  end

  local data = textutils.unserialize(content)
  if data == nil then
    return nil, "Datei enthaelt keine gueltigen Daten"
  end

  return data
end

local function saveQueue()
  local ok, err = writeTable(QUEUE_FILE, activeSends)
  if not ok then
    log("Queue speichern fehlgeschlagen: "..tostring(err))
  end
end

local function loadQueue()
  if not fs.exists(QUEUE_FILE) then return end

  local data, err = readTable(QUEUE_FILE)
  if type(data) ~= "table" then
    log("Queue laden fehlgeschlagen: "..tostring(err))
    return
  end

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

local function readNumber(prompt, default)
  while true do
    if default ~= nil then
      write(prompt.." ["..default.."]: ")
    else
      write(prompt..": ")
    end

    local input = read()

    if input == "" and default ~= nil then
      return default
    end

    local value = tonumber(input)
    if value then return math.floor(value + 0.5) end

    print("Bitte Zahl eingeben.")
  end
end

local function readString(prompt, default)
  if default ~= nil then
    write(prompt.." ["..default.."]: ")
  else
    write(prompt..": ")
  end

  local input = read()
  if input == "" then return default end
  return input
end

local function queueCommand(message, duration)
  duration = duration or DEFAULT_DURATION
  if not message.targetId then
    message.targetId = "all"
  end

  message.seq = message.seq or nextSeq
  nextSeq = nextSeq + 1

  table.insert(activeSends, {
    message=message,
    untilAt=now() + duration * 1000,
    nextAt=0
  })

  saveQueue()
  print("Befehl queued fuer "..duration.." Sekunden.")
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

        if message.command == "set_recovery" or message.command == "recovery" or message.command == "recover" then
          log("SEND REC cmd="..tostring(message.command).." target="..tostring(message.targetId).." x="..tostring(message.x).." y="..tostring(message.y).." z="..tostring(message.z).." r="..tostring(message.radius))
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
end

local function sortedMinerIds()
  local ids = {}

  for id in pairs(miners) do
    table.insert(ids, id)
  end

  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  return ids
end

local function selectedMiner()
  if selectedMinerId and miners[selectedMinerId] then
    return selectedMinerId, miners[selectedMinerId]
  end

  return nil, nil
end

local function commandTarget()
  local id = selectedMiner()
  return id or "all"
end

local function setStatus(msg)
  statusMessage = tostring(msg or "")
end

local function formatCoords(x, y, z)
  if x == nil or y == nil or z == nil then
    return "-"
  end

  return tostring(x)..","..tostring(y)..","..tostring(z)
end

local function recoverySummary(status)
  if status.recoveryX ~= nil and status.recoveryY ~= nil and status.recoveryZ ~= nil then
    return "JA  "..formatCoords(status.recoveryX, status.recoveryY, status.recoveryZ).." r="..tostring(status.recoveryRadius or "-")
  end

  return "NEIN"
end

local function targetSummary(status)
  if status.targetY == nil then
    return "NEIN"
  end

  if status.mineCenterX ~= nil and status.mineCenterZ ~= nil then
    return "JA  "..formatCoords(status.mineCenterX, status.targetY, status.mineCenterZ)
  end

  return "JA  Y="..tostring(status.targetY)
end

local function clearScreen()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function writeLineAt(x, y, text)
  local w = select(1, term.getSize())
  if y < 1 then return end
  if x < 1 then
    text = tostring(text):sub(2 - x)
    x = 1
  end

  text = tostring(text or "")
  if x > w or text == "" then return end
  if x + #text - 1 > w then
    text = text:sub(1, w - x + 1)
  end

  term.setCursorPos(x, y)
  term.write(text)
end

local function fillLine(y, text)
  local w = select(1, term.getSize())
  text = tostring(text or "")
  if #text < w then
    text = text .. string.rep(" ", w - #text)
  else
    text = text:sub(1, w)
  end

  term.setCursorPos(1, y)
  term.write(text)
end

local function drawBox(x, y, w, h, title)
  if w < 2 or h < 2 then return end

  local top = "+"..string.rep("-", math.max(0, w - 2)).."+"
  local mid = "|"..string.rep(" ", math.max(0, w - 2)).."|"
  writeLineAt(x, y, top)

  for row = y + 1, y + h - 2 do
    writeLineAt(x, row, mid)
  end

  writeLineAt(x, y + h - 1, top)

  if title and w > 4 then
    writeLineAt(x + 2, y, tostring(title):sub(1, w - 4))
  end
end

local function promptLine(label)
  local _, h = term.getSize()
  term.setCursorPos(2, h - 1)
  term.clearLine()
  write(label..": ")
end

local function readNumberPrompt(label, default)
  while true do
    local shown = label
    if default ~= nil then
      shown = shown.." ["..default.."]"
    end

    promptLine(shown)
    local input = read()
    if input == "" and default ~= nil then
      return default
    end

    local value = tonumber(input)
    if value then
      return math.floor(value + 0.5)
    end

    setStatus("Bitte Zahl eingeben.")
  end
end

local function readStringPrompt(label, default)
  local shown = label
  if default ~= nil then
    shown = shown.." ["..default.."]"
  end

  promptLine(shown)
  local input = read()
  if input == "" then return default end
  return input
end

local function listMiners()
  print("Bekannte Miner:")

  local ids = sortedMinerIds()
  if #ids == 0 then
    print(" Keine Miner bekannt.")
    return
  end

  for _,id in ipairs(ids) do
    local entry = miners[id]
    local s = entry.status
    local age = math.floor((now() - entry.last) / 1000)
    print(" "..id..
      " rednet="..entry.rednetId..
      " age="..age.."s"..
      " pos=("..tostring(s.x)..","..tostring(s.y)..","..tostring(s.z)..")"..
      " mode="..tostring(s.miningMode)..
      " state="..tostring(s.state or s.kind)..
      " alert="..tostring(s.alert or "-")..
      " fuel="..tostring(s.fuel).."/"..tostring(s.fuelLimit)..
      " mined/min="..tostring(s.minedLastMinuteTotal or 0)..
      " cmd="..tostring(s.lastCommand or "-").."#"..tostring(s.lastCommandSeq or "-"))
  end
end

local function areaCommand(targetId)
  local x1 = readNumberPrompt("x1")
  local z1 = readNumberPrompt("z1")
  local x2 = readNumberPrompt("x2")
  local z2 = readNumberPrompt("z2")
  local y = readNumberPrompt("Mining-Y", 15)
  local recoveryX = readNumberPrompt("Recovery-X")
  local recoveryY = readNumberPrompt("Recovery-Y")
  local recoveryZ = readNumberPrompt("Recovery-Z")
  local recoveryRadius = readNumberPrompt("Warteplatz-Radius", 6)
  local mode = readStringPrompt("Modus normal/netherite", "normal")
  local orePatterns = readStringPrompt("Ore Lua-Patterns optional", "")
  local duration = readNumberPrompt("Sendedauer Sekunden", DEFAULT_DURATION)

  local cmd = {
    command="mine",
    targetId=targetId,
    area={ x1=x1, z1=z1, x2=x2, z2=z2, y=y },
    mode=mode,
    recoveryX=recoveryX,
    recoveryY=recoveryY,
    recoveryZ=recoveryZ,
    radius=recoveryRadius
  }

  if orePatterns and orePatterns ~= "" then
    cmd.orePatterns = orePatterns
  end

  queueCommand(cmd, duration)
  setStatus("Mining-Bereich an "..tostring(targetId).." queued.")
end

local function oreCommand(targetId)
  local orePatterns = readStringPrompt("Ore Lua-Patterns, leer/all = default", "")
  local duration = readNumberPrompt("Sendedauer Sekunden", DEFAULT_DURATION)

  queueCommand({
    command="set_ores",
    targetId=targetId,
    orePatterns=orePatterns
  }, duration)
  setStatus("Ore-Filter an "..tostring(targetId).." queued.")
end

local function simpleCommand(command, targetId)
  local duration = readNumberPrompt("Sendedauer Sekunden", DEFAULT_DURATION)
  queueCommand({ command=command, targetId=targetId }, duration)
  setStatus("Befehl "..command.." an "..tostring(targetId).." queued.")
end

local function recoveryCommand(targetId, command)
  local x = readNumberPrompt("Recovery-X")
  local y = readNumberPrompt("Recovery-Y")
  local z = readNumberPrompt("Recovery-Z")
  local radius = readNumberPrompt("Warteplatz-Radius", 6)
  local duration = readNumberPrompt("Sendedauer Sekunden", DEFAULT_DURATION)

  queueCommand({
    command=command,
    targetId=targetId,
    x=x,
    y=y,
    z=z,
    coords={ x=x, y=y, z=z },
    recoveryX=x,
    recoveryY=y,
    recoveryZ=z,
    radius=radius
  }, duration)
  setStatus("Recovery-Befehl "..command.." an "..tostring(targetId).." queued.")
end

local function drawUi()
  clearScreen()

  local w, h = term.getSize()
  local header = "MINER CONTROL  Target="..tostring(commandTarget()).."  Queue="..tostring(#activeSends).."  Miner="..tostring(#sortedMinerIds())
  fillLine(1, header)

  local leftW = math.max(28, math.floor(w * 0.44))
  if leftW > w - 24 then
    leftW = math.max(20, w - 24)
  end
  local rightX = leftW + 2
  local rightW = w - leftW - 1
  local listH = math.max(8, h - 7)

  drawBox(1, 2, leftW, listH, "Miner")
  drawBox(rightX, 2, rightW, math.max(10, listH), "Details")
  drawBox(1, h - 4, w, 4, "Aktionen")

  local ids = sortedMinerIds()
  if selectedMinerId and not miners[selectedMinerId] then
    selectedMinerId = nil
  end
  if not selectedMinerId and ids[1] then
    selectedMinerId = ids[1]
  end

  local rows = math.max(1, listH - 2)
  local pageCount = math.max(1, math.ceil(math.max(1, #ids) / rows))
  if listPage < 1 then listPage = 1 end
  if listPage > pageCount then listPage = pageCount end

  writeLineAt(3, 3, "Page "..listPage.."/"..pageCount.."  W/S Auswahl  A/D Seite")

  if #ids == 0 then
    writeLineAt(3, 5, "Keine Miner bekannt.")
  else
    local firstIndex = (listPage - 1) * rows + 1
    local lastIndex = math.min(#ids, firstIndex + rows - 1)
    local rowY = 4

    for index = firstIndex, lastIndex do
      local id = ids[index]
      local entry = miners[id]
      local s = entry.status
      local age = math.floor((now() - entry.last) / 1000)
      local prefix = (id == selectedMinerId) and ">" or " "
      local line = prefix.."#"..tostring(id)
        .." "..tostring(s.state or s.kind or "?")
        .." fuel="..tostring(s.fuel or "-")
        .." age="..tostring(age).."s"
      writeLineAt(3, rowY, line)
      rowY = rowY + 1
    end
  end

  local _, entry = selectedMiner()
  local detailY = 4
  if entry then
    local s = entry.status
    writeLineAt(rightX + 2, detailY, "Miner: #"..tostring(selectedMinerId).." rednet="..tostring(entry.rednetId))
    writeLineAt(rightX + 2, detailY + 1, "State: "..tostring(s.state or s.kind or "-"))
    writeLineAt(rightX + 2, detailY + 2, "Alert: "..tostring(s.alert or "-"))
    writeLineAt(rightX + 2, detailY + 3, "Fuel : "..tostring(s.fuel or "-").."/"..tostring(s.fuelLimit or "-"))
    writeLineAt(rightX + 2, detailY + 4, "Pos  : "..formatCoords(s.x, s.y, s.z))
    writeLineAt(rightX + 2, detailY + 5, "Mode : "..tostring(s.miningMode or "-"))
    writeLineAt(rightX + 2, detailY + 6, "Cmd  : "..tostring(s.lastCommand or "-").."#"..tostring(s.lastCommandSeq or "-"))
    writeLineAt(rightX + 2, detailY + 7, "Recovery: "..recoverySummary(s))
    writeLineAt(rightX + 2, detailY + 8, "Ziel    : "..targetSummary(s))

    if s.mineMinX ~= nil and s.mineMaxX ~= nil and s.mineMinZ ~= nil and s.mineMaxZ ~= nil then
      writeLineAt(rightX + 2, detailY + 9, "Area    : x="..tostring(s.mineMinX)..".."..tostring(s.mineMaxX).." z="..tostring(s.mineMinZ)..".."..tostring(s.mineMaxZ))
    elseif s.mineCenterX ~= nil and s.mineCenterZ ~= nil then
      writeLineAt(rightX + 2, detailY + 9, "Center  : "..formatCoords(s.mineCenterX, s.targetY, s.mineCenterZ))
    end
  else
    writeLineAt(rightX + 2, detailY, "Kein Miner ausgewaehlt.")
    writeLineAt(rightX + 2, detailY + 2, "Recovery: -")
    writeLineAt(rightX + 2, detailY + 3, "Ziel    : -")
  end

  writeLineAt(3, h - 3, "[1]Start [2]Unload [3]Refuel [4]Ores [5]Mine [6]SetRecovery [7]Recover")
  writeLineAt(3, h - 2, "[0]Target=ALL  [Enter] Target=Selektiert  [R] Refresh  [Q] Ende")
  writeLineAt(3, h - 1, "Status: "..statusMessage)
end

local function moveSelection(delta)
  local ids = sortedMinerIds()
  if #ids == 0 then
    selectedMinerId = nil
    return
  end

  local currentIndex = 1
  for i, id in ipairs(ids) do
    if id == selectedMinerId then
      currentIndex = i
      break
    end
  end

  currentIndex = math.max(1, math.min(#ids, currentIndex + delta))
  selectedMinerId = ids[currentIndex]

  local _, h = term.getSize()
  local listH = math.max(8, h - 7)
  local rows = math.max(1, listH - 2)
  listPage = math.max(1, math.ceil(currentIndex / rows))
end

local function uiLoop()
  local refreshTimer = os.startTimer(1)
  drawUi()

  while true do
    local event, p1 = os.pullEvent()

    if event == "timer" and p1 == refreshTimer then
      drawUi()
      refreshTimer = os.startTimer(1)
    elseif event == "char" then
      local key = string.lower(p1)

      if key == "q" then
        clearScreen()
        return
      elseif key == "w" then
        moveSelection(-1)
      elseif key == "s" then
        moveSelection(1)
      elseif key == "a" then
        listPage = math.max(1, listPage - 1)
      elseif key == "d" then
        listPage = listPage + 1
      elseif key == "r" then
        setStatus("Anzeige aktualisiert.")
      elseif key == "0" then
        selectedMinerId = nil
        setStatus("Target auf ALL gesetzt.")
      elseif key == "1" then
        simpleCommand("start", commandTarget())
      elseif key == "2" then
        simpleCommand("unload", commandTarget())
      elseif key == "3" then
        simpleCommand("refuel", commandTarget())
      elseif key == "4" then
        oreCommand(commandTarget())
      elseif key == "5" then
        areaCommand(commandTarget())
      elseif key == "6" then
        recoveryCommand(commandTarget(), "set_recovery")
      elseif key == "7" then
        recoveryCommand(commandTarget(), "recover")
      end

      drawUi()
    elseif event == "key" then
      if p1 == keys.up then
        moveSelection(-1)
      elseif p1 == keys.down then
        moveSelection(1)
      elseif p1 == keys.left then
        listPage = math.max(1, listPage - 1)
      elseif p1 == keys.right then
        listPage = listPage + 1
      elseif p1 == keys.enter then
        local id = selectedMiner()
        if id then
          selectedMinerId = id
          setStatus("Target auf #"..tostring(id).." gesetzt.")
        end
      end

      drawUi()
    end
  end
end

local function rednetLoop()
  while true do
    processActiveSends()

    local sender, message = rednet.receive(PROTOCOL, 0.5)
    if sender and message then
      rememberMiner(sender, message)
    end
  end
end

if not openWirelessModem() then
  error("Kein Wireless/Ender Modem gefunden.")
end

loadQueue()
parallel.waitForAny(uiLoop, rednetLoop)
