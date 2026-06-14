local PROTOCOL = "miner_admin"
local DEFAULT_DURATION = 90
local SEND_EVERY = 2
local QUEUE_FILE = "admin_command_queue"

local miners = {}
local activeSends = {}
local nextSeq = 1

local function now()
  return os.epoch("utc")
end

local function log(msg)
  print("[Control] "..msg)
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
  local x1 = readNumber("x1")
  local z1 = readNumber("z1")
  local x2 = readNumber("x2")
  local z2 = readNumber("z2")
  local y = readNumber("Mining-Y", 15)
  local mode = readString("Modus normal/netherite", "normal")
  local orePatterns = readString("Ore Lua-Patterns optional", "")
  local duration = readNumber("Sendedauer Sekunden", DEFAULT_DURATION)

  local cmd = {
    command="mine",
    targetId=targetId,
    area={ x1=x1, z1=z1, x2=x2, z2=z2, y=y },
    mode=mode
  }

  if orePatterns and orePatterns ~= "" then
    cmd.orePatterns = orePatterns
  end

  queueCommand(cmd, duration)
end

local function oreCommand(targetId)
  local orePatterns = readString("Ore Lua-Patterns, leer/all = default", "")
  local duration = readNumber("Sendedauer Sekunden", DEFAULT_DURATION)

  queueCommand({
    command="set_ores",
    targetId=targetId,
    orePatterns=orePatterns
  }, duration)
end

local function simpleCommand(command, targetId)
  local duration = readNumber("Sendedauer Sekunden", DEFAULT_DURATION)
  queueCommand({ command=command, targetId=targetId }, duration)
end

local function menu()
  while true do
    print("")
    print("=== Miner Control ===")
    print("Queued: "..#activeSends)
    print("1) Miner anzeigen")
    print("2) Bereich an alle senden")
    print("3) Bereich an einen Miner senden")
    print("4) Unload an alle")
    print("5) Refuel an alle")
    print("6) Start an alle")
    print("7) Ores an alle setzen")
    print("8) Ores an einen Miner setzen")
    print("q) Ende")
    write("> ")

    local choice = read()

    if choice == "1" then
      listMiners()
    elseif choice == "2" then
      areaCommand("all")
    elseif choice == "3" then
      local id = readNumber("Miner Computer-ID")
      areaCommand(id)
    elseif choice == "4" then
      simpleCommand("unload", "all")
    elseif choice == "5" then
      simpleCommand("refuel", "all")
    elseif choice == "6" then
      simpleCommand("start", "all")
    elseif choice == "7" then
      oreCommand("all")
    elseif choice == "8" then
      local id = readNumber("Miner Computer-ID")
      oreCommand(id)
    elseif choice == "q" or choice == "Q" then
      return
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
parallel.waitForAny(menu, rednetLoop)
