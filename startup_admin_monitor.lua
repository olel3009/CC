local SCRIPT_URL = "https://raw.githubusercontent.com/olel3009/CC/main/admin_monitor.lua"
local SCRIPT_FILE = "admin_monitor.lua"
local UPDATE_FILE = "admin_monitor.lua.new"
local BACKUP_FILE = "admin_monitor.lua.old"

local function log(msg)
  print("[AdminMonitorStartup] "..msg)
end

local function downloadUrl()
  if os.epoch then
    return SCRIPT_URL.."?t="..tostring(os.epoch("utc"))
  end

  return SCRIPT_URL
end

local function updateScript()
  local url = downloadUrl()

  log("Lade Admin Monitor von GitHub main.")
  log(url)
  sleep(5)

  if fs.exists(UPDATE_FILE) then
    fs.delete(UPDATE_FILE)
  end

  local ok = shell.run("wget", url, UPDATE_FILE)

  if ok and fs.exists(UPDATE_FILE) then
    if fs.exists(BACKUP_FILE) then
      fs.delete(BACKUP_FILE)
    end

    if fs.exists(SCRIPT_FILE) then
      fs.move(SCRIPT_FILE, BACKUP_FILE)
    end

    fs.move(UPDATE_FILE, SCRIPT_FILE)
    log("Admin Monitor aktualisiert.")
    return true
  end

  log("Update fehlgeschlagen. Nutze vorhandenen Admin Monitor.")
  return fs.exists(SCRIPT_FILE)
end

while true do
  if updateScript() then
    local ok, err = pcall(function()
      shell.run(SCRIPT_FILE)
    end)

    if not ok then
      log("Admin Monitor crash: "..tostring(err))
    else
      log("Admin Monitor beendet.")
    end
  else
    log("Kein Admin Monitor vorhanden. Warte.")
  end

  sleep(5)
  os.reboot()
end
