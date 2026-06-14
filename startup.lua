local MINER_URL = "https://raw.githubusercontent.com/olel3009/CC/ae5389b36ca3ce4bee568f470be6b41f40a9dbfa/miner.lua"
local MINER_FILE = "miner.lua"
local UPDATE_FILE = "miner.lua.new"
local BACKUP_FILE = "miner.lua.old"

local function log(msg)
  print("[Startup] "..msg)
end

local function updateMiner()
  log("Lade Miner von GitHub.")

  if fs.exists(UPDATE_FILE) then
    fs.delete(UPDATE_FILE)
  end

  local ok = shell.run("wget", MINER_URL, UPDATE_FILE)

  if ok and fs.exists(UPDATE_FILE) then
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
  return fs.exists(MINER_FILE)
end

while true do
  if updateMiner() then
    local ok, err = pcall(function()
      shell.run(MINER_FILE)
    end)

    if not ok then
      log("Miner crash: "..tostring(err))
    else
      log("Miner beendet oder abgestuerzt ohne Lua-Fehler.")
    end
  else
    log("Kein Miner vorhanden. Warte.")
  end

  sleep(5)
  os.reboot()
end
