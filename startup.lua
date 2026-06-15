local MINER_URL = "https://raw.githubusercontent.com/olel3009/CC/main/miner.lua"
local MINER_FILE = "miner.lua"
local UPDATE_FILE = "miner.lua.new"
local BACKUP_FILE = "miner.lua.old"
local STATE_FILE = "miner_state"
local MIN_MINER_SIZE = 20000
local ADMIN_PROTOCOL = "miner_admin"

local function log(msg)
  print("[Startup] "..msg)
end

local function computerId()
  if os.getComputerID then return os.getComputerID() end
  return nil
end

local function openWirelessModem()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local modem = peripheral.wrap(name)

      if modem and modem.isWireless and modem.isWireless() then
        if not rednet.isOpen(name) then
          rednet.open(name)
        end

        return true
      end
    end
  end

  return false
end

local function sendStartupStatus(state, alert, err)
  if not openWirelessModem() then
    log("Kein Wireless/Ender Modem fuer Crash-Status gefunden.")
    return false
  end

  rednet.broadcast({
    type="miner_status",
    kind=state,
    state=state,
    alert=alert,
    crashError=tostring(err or ""),
    id=computerId(),
    label=os.getComputerLabel and os.getComputerLabel() or nil,
    wantsCommand=true
  }, ADMIN_PROTOCOL)

  return true
end

local function minerDownloadUrl()
  if os.epoch then
    return MINER_URL.."?t="..tostring(os.epoch("utc"))
  end

  return MINER_URL
end

local function validateMiner(path)
  if not fs.exists(path) then
    return false, "Datei fehlt"
  end

  local size = fs.getSize(path)
  if size < MIN_MINER_SIZE then
    return false, "Datei zu klein: "..tostring(size).." Bytes"
  end

  local program, err = loadfile(path)
  if not program then
    return false, "Lua-Syntaxfehler: "..tostring(err)
  end

  return true
end

local function updateMiner()
  local url = minerDownloadUrl()

  log("Lade Miner von GitHub main.")
  log(url)
  sleep(10)

  if fs.exists(UPDATE_FILE) then
    fs.delete(UPDATE_FILE)
  end

  local ok = shell.run("wget", url, UPDATE_FILE)

  if ok and fs.exists(UPDATE_FILE) then
    local valid, err = validateMiner(UPDATE_FILE)

    if not valid then
      log("Update verworfen: "..tostring(err))
      fs.delete(UPDATE_FILE)
      return validateMiner(MINER_FILE)
    end

    if fs.exists(BACKUP_FILE) then
      fs.delete(BACKUP_FILE)
    end

    if fs.exists(MINER_FILE) then
      fs.move(MINER_FILE, BACKUP_FILE)
    end

    fs.move(UPDATE_FILE, MINER_FILE)
    log("Miner aktualisiert.")
    return true
  end

  log("Update fehlgeschlagen. Nutze vorhandenen Miner.")
  return validateMiner(MINER_FILE)
end

local function deleteMinerState()
  if fs.exists(STATE_FILE) then
    fs.delete(STATE_FILE)
    log("Miner-State geloescht: "..STATE_FILE)
  end
end

local function runMiner()
  local program, err = loadfile(MINER_FILE)

  if not program then
    return false, err
  end

  return pcall(program)
end

while true do
  if updateMiner() then
    local ok, err = runMiner()

    if not ok then
      log("Miner crash: "..tostring(err))
      sendStartupStatus("crashed", "crashed", err)
      deleteMinerState()
    else
      log("Miner beendet oder abgestuerzt ohne Lua-Fehler.")
      sendStartupStatus("stopped", "stopped", "Miner beendet ohne pcall-Fehler.")
      deleteMinerState()
    end
  else
    log("Kein Miner vorhanden. Warte.")
    sendStartupStatus("startup_error", "startup_error", "Kein gueltiger Miner vorhanden.")
  end

  sleep(5)
  os.reboot()
end
