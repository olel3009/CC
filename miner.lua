-- startup.lua
-- Auto Ore Miner v20
-- Fix: Scanner-Koordinaten werden als Minecraft-Weltachsen behandelt.
-- Setup erkennt die Startausrichtung nach Moeglichkeit automatisch ueber die Fuel-Kiste.
-- Fallback ist fest konfiguriert: aktuelle Y 63, Facing north, tiefste Ziel-Y -50.
-- Fuel-Kiste VOR der Turtle, Lager-Kiste HINTER der Turtle.
-- Turtle schaut beim Start zur Fuel-Kiste.

STATE = "miner_state"
DEBUG_LOG = "miner_debug.log"
STATE_VERSION = 19
STARTUP_FILE = "startup.lua"
STARTUP_UPDATE_FILE = "startup.lua.new"
STARTUP_BACKUP_FILE = "startup.lua.old"
STARTUP_URL = "https://raw.githubusercontent.com/olel3009/CC/main/startup.lua"
REQUIRED_STARTUP_VERSION = 2
MIN_STARTUP_SIZE = 1000

MAX_SCAN_RADIUS = 15
MIN_SCAN_RADIUS = 4

LOW_FUEL_STOP = 20
RETURN_FUEL_BUFFER = 120
FUEL_CHEST_EMPTY_RETRIES = 50
SCAN_WAIT = 3
MAX_VEIN_STEPS = 128

RANDOM_MOVE_MIN = 6
RANDOM_MOVE_MAX = 18
MIN_START_DEPTH_BELOW_TOP = 20
MAX_DISTANCE_FROM_SHAFT = 70
STATUS_INTERVAL = 120
COMMAND_WAIT = 5
COMMAND_POLL_MAX_PACKETS = 64
ADMIN_PROTOCOL = "miner_admin"
ADMIN_COMMAND_PROTOCOL = "miner_admin_cmd"
MODEM_SLOT = 13
UNLOAD_CHEST_SLOT = 15
FUEL_CHEST_SLOT = 16
WORK_SLOT_LAST = 12

CONFIG_TOP_Y = 63
CONFIG_LOWEST_Y = -50
CONFIG_HIGHEST_NORMAL_TARGET_Y = 40
CONFIG_NETHERITE_TARGET_Y = 15
CONFIG_HEADING = 0

JUNK = {
  ["minecraft:stone"]=true,
  ["minecraft:cobblestone"]=true,
  ["minecraft:deepslate"]=true,
  ["minecraft:cobbled_deepslate"]=true,
  ["minecraft:dirt"]=true,
  ["minecraft:gravel"]=true,
  ["minecraft:granite"]=true,
  ["minecraft:diorite"]=true,
  ["minecraft:andesite"]=true,
  ["minecraft:tuff"]=true,
  ["minecraft:netherrack"]=true,
  ["minecraft:basalt"]=true,
  ["minecraft:blackstone"]=true,
  ["minecraft:sand"]=true,
  ["minecraft:sandstone"]=true,
  ["minecraft:calcite"]=true
}

TARGET_ORES = {
  ["minecraft:iron_ore"]=true,
  ["minecraft:deepslate_iron_ore"]=true,
  ["minecraft:gold_ore"]=true,
  ["minecraft:deepslate_gold_ore"]=true,
  ["minecraft:diamond_ore"]=true,
  ["minecraft:deepslate_diamond_ore"]=true,

  -- Applied Energistics 2 / AE2
  ["ae2:quartz_ore"]=true,
  ["ae2:deepslate_quartz_ore"]=true,
  ["ae2:charged_quartz_ore"]=true,
  ["ae2:deepslate_charged_quartz_ore"]=true,
  ["ae2:sky_stone_block"]=true,
  ["ae2:sky_stone_chest"]=true,

  -- Draconic Evolution / Draconium
  ["draconicevolution:draconium_ore"]=true,
  ["draconicevolution:deepslate_draconium_ore"]=true,
  ["draconicevolution:end_draconium_ore"]=true,
  ["draconicevolution:nether_draconium_ore"]=true,
  ["extendedcrafting:draconium_ore"]=true
}

NETHERITE_TARGETS = {
  ["minecraft:ancient_debris"]=true
}

DRACONIUM_ORES = {
  ["draconicevolution:draconium_ore"]=true,
  ["draconicevolution:deepslate_draconium_ore"]=true,
  ["draconicevolution:end_draconium_ore"]=true,
  ["draconicevolution:nether_draconium_ore"]=true,
  ["extendedcrafting:draconium_ore"]=true
}

NETHER_BLOCKS = {
  ["minecraft:netherrack"]=true,
  ["minecraft:basalt"]=true,
  ["minecraft:smooth_basalt"]=true,
  ["minecraft:blackstone"]=true,
  ["minecraft:nether_quartz_ore"]=true,
  ["minecraft:nether_gold_ore"]=true,
  ["minecraft:soul_sand"]=true,
  ["minecraft:soul_soil"]=true,
  ["minecraft:crimson_nylium"]=true,
  ["minecraft:warped_nylium"]=true,
  ["minecraft:ancient_debris"]=true
}

NETHERITE_JUNK = {
  ["minecraft:nether_quartz_ore"]=true,
  ["minecraft:nether_gold_ore"]=true,
  ["minecraft:quartz"]=true,
  ["minecraft:gold_nugget"]=true
}

TARGET_MODS = {
  ["ae2"]=true,
  ["appliedenergistics2"]=true,
  ["appeng"]=true
}

-- Minecraft-Weltachsen:
-- x+ = east
-- x- = west
-- z+ = south
-- z- = north
--
-- heading:
-- 0 = north
-- 1 = east
-- 2 = south
-- 3 = west

x, y, z = 0, 0, 0
homeX, homeZ = 0, 0
mineCenterX, mineCenterZ = 0, 0
mineMinX, mineMaxX, mineMinZ, mineMaxZ = nil, nil, nil, nil
heading = 0
storageHeading = 0
fuelHeading = 2
topY, targetY = nil, nil
normalLowestY = CONFIG_LOWEST_Y
miningMode = "normal"
wantedOres = nil
wantedOrePatterns = nil
recoveryX, recoveryY, recoveryZ = nil, nil, nil
recoveryRadius = 6
recoveryTravelMode = false
unloadChestFingerprint = nil
fuelChestFingerprint = nil

oreMinedCount = 0
minedSinceStatus = {}
veinSteps = 0
skippedTargets = {}
adminId = nil
modemSide = nil
modemEquipped = false
lastStatusAt = 0
adminStartReceived = false
pendingUnload = false
pendingRefuel = false
minerState = "boot"
minerAlert = nil
lastCommand = nil
lastCommandSeq = nil
activePlacedReservedChestSlot = nil
goToRecoveryIfConfigured = nil
fatalRecoveryHandler = nil
inFatalRecovery = false

scanner = peripheral.find("geoScanner") or peripheral.find("geo_scanner")

math.randomseed(os.epoch("utc"))

function log(msg)
  print("[Miner] "..msg)
end

function debugLog(msg)
  local text = tostring(msg)
  print("[Miner] "..text)
end

function writeTable(path, data)
  local f = fs.open(path, "w")
  f.write(textutils.serialize(data))
  f.close()
end

function readTable(path)
  local f = fs.open(path, "r")
  local data = textutils.unserialize(f.readAll())
  f.close()
  return data
end

function readFile(path)
  if not fs.exists(path) then return nil end

  local f = fs.open(path, "r")
  local text = f.readAll()
  f.close()
  return text
end

function startupDownloadUrl()
  if os.epoch then
    return STARTUP_URL.."?t="..tostring(os.epoch("utc"))
  end

  return STARTUP_URL
end

function localStartupVersion()
  local text = readFile(STARTUP_FILE)
  if not text then return 0 end

  local version = string.match(text, "STARTUP_VERSION%s*=%s*(%d+)")
  return tonumber(version) or 0
end

function validateStartupFile(path)
  if not fs.exists(path) then
    return false, "Datei fehlt"
  end

  local size = fs.getSize(path)
  if size < MIN_STARTUP_SIZE then
    return false, "Datei zu klein: "..tostring(size).." Bytes"
  end

  local program, err = loadfile(path)
  if not program then
    return false, "Lua-Syntaxfehler: "..tostring(err)
  end

  return true
end

function ensureStartupVersion()
  local current = localStartupVersion()
  if current >= REQUIRED_STARTUP_VERSION then
    return true
  end

  log("Startup-Version zu alt: "..tostring(current).." < "..REQUIRED_STARTUP_VERSION..". Lade Update.")

  if fs.exists(STARTUP_UPDATE_FILE) then
    fs.delete(STARTUP_UPDATE_FILE)
  end

  local ok = shell.run("wget", startupDownloadUrl(), STARTUP_UPDATE_FILE)
  if not ok or not fs.exists(STARTUP_UPDATE_FILE) then
    log("Startup-Update durch Miner fehlgeschlagen.")
    return false
  end

  local valid, err = validateStartupFile(STARTUP_UPDATE_FILE)
  if not valid then
    log("Startup-Update durch Miner verworfen: "..tostring(err))
    fs.delete(STARTUP_UPDATE_FILE)
    return false
  end

  if fs.exists(STARTUP_BACKUP_FILE) then
    fs.delete(STARTUP_BACKUP_FILE)
  end

  if fs.exists(STARTUP_FILE) then
    fs.move(STARTUP_FILE, STARTUP_BACKUP_FILE)
  end

  fs.move(STARTUP_UPDATE_FILE, STARTUP_FILE)
  log("Startup durch Miner aktualisiert auf Version "..REQUIRED_STARTUP_VERSION..".")
  return true
end

save = nil
stop = nil

function computerId()
  if os.getComputerID then return os.getComputerID() end
  return nil
end

function findWirelessModemSide()
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local modem = peripheral.wrap(name)

      if modem and modem.isWireless and modem.isWireless() then
        return name
      end
    end
  end

  return nil
end

function equipEnderModem()
  if modemEquipped then return true end

  modemSide = findWirelessModemSide()
  if modemSide then return true end

  local item = turtle.getItemDetail(MODEM_SLOT)
  if not item then
    return false
  end

  turtle.select(MODEM_SLOT)

  if turtle.equipRight and turtle.equipRight() then
    modemEquipped = true
    modemSide = findWirelessModemSide()
    if modemSide then return true end
  end

  if turtle.equipLeft and turtle.equipLeft() then
    modemEquipped = true
    modemSide = findWirelessModemSide()
    if modemSide then return true end
  end

  return false
end

function forceUnequipWirelessModem()
  local side = findWirelessModemSide()
  if not side then return false end

  if rednet.isOpen and rednet.isOpen(side) then
    rednet.close(side)
  end

  turtle.select(MODEM_SLOT)

  if side == "right" and turtle.equipRight and turtle.equipRight() then
    modemEquipped = false
    modemSide = nil
    return true
  end

  if side == "left" and turtle.equipLeft and turtle.equipLeft() then
    modemEquipped = false
    modemSide = nil
    return true
  end

  if turtle.equipRight and turtle.equipRight() and not findWirelessModemSide() then
    modemEquipped = false
    modemSide = nil
    return true
  end

  if turtle.equipLeft and turtle.equipLeft() and not findWirelessModemSide() then
    modemEquipped = false
    modemSide = nil
    return true
  end

  return false
end

function unequipEnderModem()
  if modemSide and rednet.isOpen and rednet.isOpen(modemSide) then
    rednet.close(modemSide)
  end

  forceUnequipWirelessModem()
  modemSide = nil

  if restoreMiningUpgrades then
    restoreMiningUpgrades()
  end
end

function openWirelessModem()
  if modemSide and rednet.isOpen and rednet.isOpen(modemSide) then
    return true
  end

  ensureModemAvailable()

  if not equipEnderModem() then
    return false
  end

  modemSide = findWirelessModemSide()

  if modemSide then
    rednet.open(modemSide)
    return true
  end

  return false
end

function lowerName(name)
  return string.lower(tostring(name or ""))
end

function isScannerItemName(name)
  local lower = lowerName(name)
  return string.find(lower, "geo", 1, true) ~= nil
    and string.find(lower, "scanner", 1, true) ~= nil
end

function isModemItemName(name)
  return string.find(lowerName(name), "modem", 1, true) ~= nil
end

function isPickaxeItemName(name)
  return string.find(lowerName(name), "pickaxe", 1, true) ~= nil
end

function isEnderStorageName(name)
  local lower = lowerName(name)
  return string.match(lower, "^enderstorage:") ~= nil
    or string.match(lower, "^ender_storage:") ~= nil
    or string.find(lower, "enderstorage", 1, true) ~= nil
    or string.find(lower, "ender_storage", 1, true) ~= nil
end

function isEnderChestItemName(name)
  local lower = lowerName(name)
  return string.find(lower, "ender", 1, true) ~= nil
    and string.find(lower, "chest", 1, true) ~= nil
end

function isEnderChestBlockName(name)
  return isEnderChestItemName(name) or isEnderStorageName(name)
end

function isReservedEnderChestItemName(name)
  return isEnderChestItemName(name) or isEnderStorageName(name)
end

function detailedItem(slot)
  local ok, item = pcall(function()
    return turtle.getItemDetail(slot, true)
  end)

  if ok then return item end
  return turtle.getItemDetail(slot)
end

function itemFingerprint(item)
  if not item then return nil end
  return tostring(item.name or "").."|"..tostring(item.nbt or "").."|"..tostring(item.displayName or "")
end

function reservedChestFingerprintForSlot(slot)
  if slot == UNLOAD_CHEST_SLOT then return unloadChestFingerprint end
  if slot == FUEL_CHEST_SLOT then return fuelChestFingerprint end
  return nil
end

function setReservedChestFingerprint(slot, force)
  local item = detailedItem(slot)

  if not item or not isReservedEnderChestItemName(item.name) then
    return nil
  end

  local fingerprint = itemFingerprint(item)
  local existing = reservedChestFingerprintForSlot(slot)

  if existing and existing ~= fingerprint and not force then
    return existing
  end

  if slot == UNLOAD_CHEST_SLOT then
    unloadChestFingerprint = fingerprint
  elseif slot == FUEL_CHEST_SLOT then
    fuelChestFingerprint = fingerprint
  end

  return fingerprint
end

function reservedChestMatchesSlot(slot, item)
  if not item or not isReservedEnderChestItemName(item.name) then
    return false
  end

  local fingerprint = reservedChestFingerprintForSlot(slot)
  if not fingerprint then return true end
  return itemFingerprint(item) == fingerprint
end

function refreshReservedChestFingerprints(force)
  setReservedChestFingerprint(UNLOAD_CHEST_SLOT, force)
  setReservedChestFingerprint(FUEL_CHEST_SLOT, force)
end

function refreshScanner()
  scanner = peripheral.find("geoScanner") or peripheral.find("geo_scanner")
  return scanner ~= nil
end

function findSlotByNameTest(testFn, firstSlot, lastSlot)
  for i=firstSlot or 1,lastSlot or 16 do
    local item = turtle.getItemDetail(i)
    if item and testFn(item.name) then
      return i, item
    end
  end

  return nil, nil
end

function findEmptySlot(firstSlot, lastSlot)
  for i=firstSlot or 1,lastSlot or 16 do
    if turtle.getItemCount(i) == 0 then
      return i
    end
  end

  return nil
end

function moveMatchingItemToSlot(testFn, targetSlot, label)
  local targetItem = turtle.getItemDetail(targetSlot)

  if targetItem and testFn(targetItem.name) then
    return true
  end

  local sourceSlot = findSlotByNameTest(testFn, 1, 16)

  if not sourceSlot then
    return false
  end

  if targetItem then
    for i=1,16 do
      if i ~= targetSlot and turtle.getItemCount(i) == 0 then
        turtle.select(targetSlot)
        turtle.transferTo(i)
        break
      end
    end
  end

  if turtle.getItemCount(targetSlot) > 0 then
    log("Kann "..label.." nicht nach Slot "..targetSlot.." sortieren: Zielslot ist belegt.")
    return false
  end

  turtle.select(sourceSlot)
  turtle.transferTo(targetSlot)
  log(label.." nach Slot "..targetSlot.." sortiert.")
  return true
end

function moveReservedChestToSlot(targetSlot, label)
  local targetItem = detailedItem(targetSlot)

  if reservedChestMatchesSlot(targetSlot, targetItem) and turtle.getItemCount(targetSlot) == 1 then
    setReservedChestFingerprint(targetSlot)
    return true
  end

  if reservedChestMatchesSlot(targetSlot, targetItem) and turtle.getItemCount(targetSlot) > 1 then
    local emptySlot = findEmptySlot(1, WORK_SLOT_LAST) or findEmptySlot(1, 16)

    if not emptySlot then
      log(label.." in Slot "..targetSlot.." ist gestapelt, aber kein freier Slot zum Trennen.")
      return false
    end

    turtle.select(targetSlot)
    if turtle.transferTo(emptySlot, turtle.getItemCount(targetSlot) - 1) then
      setReservedChestFingerprint(targetSlot)
      log(label.." in Slot "..targetSlot.." auf Einzel-Chest getrennt.")
      return true
    end

    return false
  end

  if targetItem then
    local emptySlot = nil

    for i=1,16 do
      if i ~= targetSlot and turtle.getItemCount(i) == 0 then
        emptySlot = i
        break
      end
    end

    if emptySlot then
      turtle.select(targetSlot)
      turtle.transferTo(emptySlot)
    end
  end

  if turtle.getItemCount(targetSlot) > 0 then
    log("Kann "..label.." nicht nach Slot "..targetSlot.." sortieren: Zielslot ist belegt.")
    return false
  end

  local fingerprint = reservedChestFingerprintForSlot(targetSlot)

  for i=1,16 do
    if i ~= targetSlot then
      local item = detailedItem(i)
      local matches = false

      if item and isReservedEnderChestItemName(item.name) then
        if fingerprint then
          matches = itemFingerprint(item) == fingerprint
        else
          matches = true
        end
      end

      if matches then
        turtle.select(i)
        turtle.transferTo(targetSlot, 1)
        setReservedChestFingerprint(targetSlot)
        log(label.." nach Slot "..targetSlot.." sortiert.")
        return true
      end
    end
  end

  return false
end

function protectReservedChests(context)
  local okUnload = moveReservedChestToSlot(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")
  local okFuel = moveReservedChestToSlot(FUEL_CHEST_SLOT, "Fuel-Ender-Chest")

  if okUnload and okFuel then
    return true
  end

  local missingSlot = nil
  local missingLabel = nil

  if not reservedChestMatchesSlot(UNLOAD_CHEST_SLOT, detailedItem(UNLOAD_CHEST_SLOT)) then
    missingSlot = UNLOAD_CHEST_SLOT
    missingLabel = "Entlade-Ender-Chest"
  elseif not reservedChestMatchesSlot(FUEL_CHEST_SLOT, detailedItem(FUEL_CHEST_SLOT)) then
    missingSlot = FUEL_CHEST_SLOT
    missingLabel = "Fuel-Ender-Chest"
  end

  if missingSlot then
    minerAlert = "missing_reserved_chest"
    sendStatus("missing_reserved_chest", false)
    stop(tostring(missingLabel).." fehlt beim Chest-Schutz ("..tostring(context)..") in Slot "..tostring(missingSlot)..".")
  end

  return false
end

function isReservedChestInWorkSlot(slot)
  if slot < 1 or slot > WORK_SLOT_LAST then return false end
  local item = detailedItem(slot)
  return item and isReservedEnderChestItemName(item.name)
end

function rescueWorkSlotReservedChest(slot, context)
  if not isReservedChestInWorkSlot(slot) then return false end

  if activePlacedReservedChestSlot ~= UNLOAD_CHEST_SLOT and moveReservedChestToSlot(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest") then
    return true
  end

  if activePlacedReservedChestSlot ~= FUEL_CHEST_SLOT and moveReservedChestToSlot(FUEL_CHEST_SLOT, "Fuel-Ender-Chest") then
    return true
  end

  stop("Reservierte Ender-Chest in Arbeitsslot "..slot.." kann nicht gesichert werden ("..tostring(context)..").")
end

function equipItemFromSlot(slot, label)
  if not slot then return false end

  turtle.select(slot)

  if turtle.equipRight and turtle.equipRight() then
    log(label.." rechts ausgeruestet.")
    return true
  end

  if turtle.equipLeft and turtle.equipLeft() then
    log(label.." links ausgeruestet.")
    return true
  end

  return false
end

function recoverScannerUpgrade()
  if refreshScanner() then return true end

  local slot = findSlotByNameTest(isScannerItemName, 1, 16)
  if slot and equipItemFromSlot(slot, "GeoScanner") and refreshScanner() then
    return true
  end

  return false
end

function recoverPickaxeUpgrade()
  local slot = findSlotByNameTest(isPickaxeItemName, 1, 16)
  if not slot then return false end

  turtle.select(slot)

  if turtle.equipRight and turtle.equipRight() then
    if refreshScanner() then
      log("Pickaxe rechts ausgeruestet.")
      return true
    end

    recoverScannerUpgrade()
    slot = findSlotByNameTest(isPickaxeItemName, 1, 16)
  end

  if not slot then return false end

  turtle.select(slot)

  if turtle.equipLeft and turtle.equipLeft() then
    if refreshScanner() then
      log("Pickaxe links ausgeruestet.")
      return true
    end

    recoverScannerUpgrade()
    log("Pickaxe konnte nicht ausgeruestet bleiben, ohne den GeoScanner zu verdraengen.")
    return false
  end

  return false
end

restoreMiningUpgrades = function()
  recoverScannerUpgrade()
  recoverPickaxeUpgrade()
  moveMatchingItemToSlot(isModemItemName, MODEM_SLOT, "Ender/Wireless Modem")
end

function ensureMiningUpgrades(context)
  if findWirelessModemSide() and not forceUnequipWirelessModem() then
    stop("Wireless/Ender-Modem ist vor dem Graben noch ausgeruestet und konnte nicht abgelegt werden ("..tostring(context)..").")
  end

  restoreMiningUpgrades()

  if findWirelessModemSide() then
    stop("Wireless/Ender-Modem ist vor dem Graben noch ausgeruestet ("..tostring(context)..").")
  end
end

function recoverModemSlot()
  if moveMatchingItemToSlot(isModemItemName, MODEM_SLOT, "Ender/Wireless Modem") then
    return true
  end

  if findWirelessModemSide() then
    return true
  end

  return false
end

function ensureModemAvailable()
  if findWirelessModemSide() then
    return true, "equipped_modem"
  end

  recoverModemSlot()

  local modemItem = turtle.getItemDetail(MODEM_SLOT)
  if modemItem and isModemItemName(modemItem.name) then
    return true, modemItem.name
  end

  for i=1,16 do
    local item = turtle.getItemDetail(i)

    if item and isModemItemName(item.name) then
      moveMatchingItemToSlot(isModemItemName, MODEM_SLOT, "Ender/Wireless Modem")
      modemItem = turtle.getItemDetail(MODEM_SLOT)

      if modemItem and isModemItemName(modemItem.name) then
        return true, modemItem.name
      end
    end
  end

  forceUnequipWirelessModem()

  modemItem = turtle.getItemDetail(MODEM_SLOT)
  if modemItem and isModemItemName(modemItem.name) then
    return true, modemItem.name
  end

  return false, nil
end

function turnRightRaw()
  turtle.turnRight()
  heading = (heading + 1) % 4
end

function turnLeftRaw()
  turtle.turnLeft()
  heading = (heading + 3) % 4
end

function faceRaw(targetHeading)
  while heading ~= targetHeading do
    turnRightRaw()
  end
end

function tryDigEnderChestHere(inspectFn, digFn, slot, label)
  local ok, data = inspectFn()

  if not ok or not data or not isEnderChestBlockName(data.name) then
    return false
  end

  log(label.." fehlt in Slot "..slot.."; gefundene Ender-Chest wird eingesammelt: "..data.name)
  turtle.select(slot)

  if not digFn() then
    return false
  end

  if reservedChestMatchesSlot(slot, detailedItem(slot)) then
    setReservedChestFingerprint(slot)
    return true
  end

  return moveReservedChestToSlot(slot, label)
end

function recoverFrontEnderChest(slot, label)
  local ok, data = turtle.inspect()

  if not ok or not data or not isEnderChestBlockName(data.name) then
    return false
  end

  local targetSlot = slot

  if turtle.getItemCount(targetSlot) > 0 then
    local otherReservedSlot = nil

    if slot == UNLOAD_CHEST_SLOT then
      otherReservedSlot = FUEL_CHEST_SLOT
    elseif slot == FUEL_CHEST_SLOT then
      otherReservedSlot = UNLOAD_CHEST_SLOT
    end

    if otherReservedSlot and turtle.getItemCount(otherReservedSlot) == 0 then
      targetSlot = otherReservedSlot
    else
      targetSlot = findEmptySlot(1, WORK_SLOT_LAST) or findEmptySlot(1, 16)
    end

    if not targetSlot then
      stop(label.." vorne blockiert durch Ender-Chest, aber kein freier Slot zum Einsammeln: "..data.name)
    end
  end

  log(label.." vorne blockiert durch Ender-Chest. Sammle sie ein: "..data.name)
  turtle.select(targetSlot)

  if not turtle.dig() then
    return false
  end

  if targetSlot == slot and reservedChestMatchesSlot(slot, detailedItem(targetSlot)) then
    setReservedChestFingerprint(slot)
    return true
  end

  return moveReservedChestToSlot(slot, label)
end

function recoverAdjacentEnderChest(slot, label)
  if moveReservedChestToSlot(slot, label) then
    return true
  end

  if tryDigEnderChestHere(turtle.inspectUp, turtle.digUp, slot, label) then
    return true
  end

  if tryDigEnderChestHere(turtle.inspectDown, turtle.digDown, slot, label) then
    return true
  end

  local startHeading = heading

  for _=1,4 do
    if tryDigEnderChestHere(turtle.inspect, turtle.dig, slot, label) then
      faceRaw(startHeading)
      return true
    end

    turnRightRaw()
  end

  faceRaw(startHeading)
  return false
end

function repairStartupEquipment()
  recoverModemSlot()
  recoverScannerUpgrade()
  recoverPickaxeUpgrade()

  if not refreshScanner() then
    stop("Kein Geo Scanner gefunden. Lege ihn in einen Slot oder rueste ihn wieder aus.")
  end

  recoverAdjacentEnderChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")
  recoverAdjacentEnderChest(FUEL_CHEST_SLOT, "Fuel-Ender-Chest")
  recoverFrontEnderChest(FUEL_CHEST_SLOT, "Start-Front-Ender-Chest")
end

function locateGps(required)
  if not gps or not gps.locate then
    if required then error("GPS API nicht verfuegbar.") end
    return nil
  end

  local equippedForGps = false

  if not findWirelessModemSide() then
    if not ensureModemAvailable() or not equipEnderModem() then
      if required then error("GPS braucht das Ender-Modem-Modul in Slot "..MODEM_SLOT..".") end
      return nil
    end

    equippedForGps = true
  end

  local gx, gy, gz = gps.locate(5)

  if gx and gy and gz then
    x = math.floor(gx + 0.5)
    y = math.floor(gy + 0.5)
    z = math.floor(gz + 0.5)

    if equippedForGps then
      unequipEnderModem()
    end

    return x, y, z
  end

  if equippedForGps then
    unequipEnderModem()
  end

  if required then
    error("GPS konnte Position nicht bestimmen.")
  end

  return nil
end

function tableCount(t)
  local n = 0
  for _,count in pairs(t) do
    n = n + count
  end
  return n
end

function isInventoryBlockName(name)
  if not name then return false end

  local lower = string.lower(name)
  return string.find(lower, "chest", 1, true) ~= nil
    or string.find(lower, "barrel", 1, true) ~= nil
    or string.find(lower, "drawer", 1, true) ~= nil
    or string.find(lower, "sophisticatedstorage", 1, true) ~= nil
end

function headingFromDelta(dx, dz)
  if dx == 1 and dz == 0 then return 1 end
  if dx == -1 and dz == 0 then return 3 end
  if dx == 0 and dz == 1 then return 2 end
  if dx == 0 and dz == -1 then return 0 end
  return nil
end

function headingName(h)
  if h == 0 then return "north" end
  if h == 1 then return "east" end
  if h == 2 then return "south" end
  if h == 3 then return "west" end
  return tostring(h)
end

function gpsHeadingCalibration(context, required)
  local sx, sy, sz = locateGps(required)

  if not sx then
    log("GPS-Ausrichtung nicht moeglich ("..tostring(context)..").")
    return false
  end

  for turns=0,3 do
    if turtle.forward() then
      local nx, ny, nz = locateGps(required)

      if not nx then
        turtle.back()
        for _=1,turns do
          turtle.turnLeft()
        end
        return false
      end

      local moveHeading = headingFromDelta(nx - sx, nz - sz)

      local returned = false

      for _=1,8 do
        if turtle.back() then
          returned = true
          break
        end

        sleep(0.2)
      end

      if not returned then
        error("GPS-Ausrichtung: Probe-Schritt konnte nicht zurueckfahren.")
      end

      local rx, ry, rz = locateGps(false)
      if rx then
        x, y, z = rx, ry, rz
      else
        x, y, z = sx, sy, sz
      end

      if moveHeading ~= nil then
        local originalHeading = (moveHeading - turns) % 4

        for _=1,turns do
          turtle.turnLeft()
        end

        heading = originalHeading
        log("GPS-Ausrichtung "..tostring(context)..": heading="..headingName(heading)..".")

        if save then save() end
        return true
      end
    end

    turtle.turnRight()
  end

  log("GPS-Ausrichtung nicht moeglich ("..tostring(context).."): keine freie Probe-Richtung.")
  return false
end

function setupScan(radius)
  local ok, result, err

  if scanner.scanBlocks then
    ok, result, err = pcall(function() return scanner.scanBlocks(radius) end)
  elseif scanner.scan then
    ok, result, err = pcall(function() return scanner.scan(radius) end)
  else
    return nil, "Scanner hat weder scanBlocks() noch scan()."
  end

  if not ok then
    return nil, result
  end

  if type(result) ~= "table" then
    return nil, err or "Scanner lieferte keine Tabelle."
  end

  return result, nil
end

function collectInventoryPositions(blocks, maxDist)
  local positions = {}

  for _,b in ipairs(blocks) do
    if b and isInventoryBlockName(b.name) and b.y == 0 then
      local dist = math.abs(b.x or 0) + math.abs(b.z or 0)

      if dist > 0 and dist <= maxDist then
        table.insert(positions, { name=b.name, x=b.x, z=b.z })
      end
    end
  end

  return positions
end

function looksLikeNether(blocks)
  local netherBlocks = 0
  local totalBlocks = 0

  for _,b in ipairs(blocks) do
    if b and b.name then
      totalBlocks = totalBlocks + 1

      if NETHER_BLOCKS[b.name] then
        netherBlocks = netherBlocks + 1
      end
    end
  end

  return netherBlocks >= 10 or (totalBlocks > 0 and netherBlocks / totalBlocks >= 0.35)
end

function inferMoveHeading(before, after)
  local scores = {}

  for _,old in ipairs(before) do
    for _,new in ipairs(after) do
      if old.name == new.name then
        local dx = old.x - new.x
        local dz = old.z - new.z
        local h = headingFromDelta(dx, dz)

        if h ~= nil then
          local key = tostring(h)
          scores[key] = (scores[key] or 0) + 1
        end
      end
    end
  end

  local bestHeading, bestScore, tied = nil, 0, false

  for key,score in pairs(scores) do
    local h = tonumber(key)

    if score > bestScore then
      bestHeading = h
      bestScore = score
      tied = false
    elseif score == bestScore then
      tied = true
    end
  end

  if bestHeading ~= nil and bestScore >= #before and not tied then
    return bestHeading
  end

  return nil
end

function setupBackToProbeStart()
  for _=1,8 do
    if turtle.back() then
      return true
    end

    turtle.attack()
    sleep(0.2)
  end

  return false
end

function probeSideForHeading(before, side)
  if side == "right" then
    turtle.turnRight()
  else
    turtle.turnLeft()
  end

  if turtle.detect() or not turtle.forward() then
    if side == "right" then
      turtle.turnLeft()
    else
      turtle.turnRight()
    end

    return nil
  end

  local movedBlocks, err = setupScan(2)
  local returned = setupBackToProbeStart()

  if side == "right" then
    turtle.turnLeft()
  else
    turtle.turnRight()
  end

  if not returned then
    error("Auto-Ausrichtung: Probe-Bewegung konnte nicht zurueckfahren.")
  end

  if not movedBlocks then
    log("Auto-Ausrichtung: Probe-Scan fehlgeschlagen: "..tostring(err))
    return nil
  end

  local after = collectInventoryPositions(movedBlocks, 2)
  local moveHeading = inferMoveHeading(before, after)

  if moveHeading == nil then
    return nil
  end

  if side == "right" then
    return (moveHeading + 3) % 4
  end

  return (moveHeading + 1) % 4
end

function resolveAmbiguousStartHeading(candidates)
  log("Auto-Ausrichtung: Fuehre kurze Seiten-Probe aus, um die Weltachse zu bestimmen.")

  local h = probeSideForHeading(candidates, "right")

  if h ~= nil then
    log("Auto-Ausrichtung: Seiten-Probe rechts ergibt heading="..headingName(h)..".")
    return h
  end

  h = probeSideForHeading(candidates, "left")

  if h ~= nil then
    log("Auto-Ausrichtung: Seiten-Probe links ergibt heading="..headingName(h)..".")
    return h
  end

  log("Auto-Ausrichtung: Seiten-Probe konnte keine eindeutige Richtung bestimmen.")
  return nil
end

function autoDetectStartHeading()
  local blocks, err = setupScan(1)

  if not blocks then
    log("Auto-Ausrichtung nicht moeglich: "..tostring(err))
    return nil
  end

  local candidates = {}

  for _,b in ipairs(blocks) do
    if b and isInventoryBlockName(b.name) and b.y == 0 then
      local dist = math.abs(b.x or 0) + math.abs(b.z or 0)

      if dist == 1 then
        local h = headingFromDelta(b.x, b.z)

        if h ~= nil then
          table.insert(candidates, { heading=h, name=b.name, x=b.x, z=b.z })
        end
      end
    end
  end

  if #candidates == 1 then
    local c = candidates[1]
    log("Auto-Ausrichtung: Fuel-Kiste erkannt bei dx="..c.x.." dz="..c.z.." ("..c.name.."), heading="..headingName(c.heading)..".")
    return c.heading
  end

  if #candidates == 0 then
    log("Auto-Ausrichtung: Keine direkt angrenzende Kiste im GeoScanner gefunden.")
  else
    local resolvedHeading = resolveAmbiguousStartHeading(candidates)

    if resolvedHeading ~= nil then
      return resolvedHeading
    end

    log("Auto-Ausrichtung: Mehrere direkt angrenzende Kisten gefunden; Fuel-Kiste ist nicht eindeutig.")
  end

  return nil
end

function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return 999999999 end
  return f
end

function fuelLimit()
  if turtle.getFuelLimit then
    local f = turtle.getFuelLimit()
    if f == "unlimited" then return 999999999 end
    return f
  end
  return 999999999
end

function chooseNormalTargetY()
  local lowestY = normalLowestY or CONFIG_LOWEST_Y
  local highestStartY = CONFIG_HIGHEST_NORMAL_TARGET_Y

  lowestY = math.floor(lowestY)
  highestStartY = math.floor(highestStartY)

  if highestStartY < lowestY then
    return lowestY, lowestY, lowestY
  end

  local id = tonumber(computerId()) or math.random(0, highestStartY - lowestY)
  local target = lowestY + (math.abs(id) % (highestStartY - lowestY + 1))

  return target, lowestY, highestStartY
end

function ensureTargetY()
  if miningMode == "netherite" then
    if type(targetY) == "number" then return end

    targetY = CONFIG_NETHERITE_TARGET_Y
    log("Ziel-Y fehlte im State. Setze Ziel-Y auf "..targetY..".")
  else
    local previousTargetY = targetY
    local lowestY, highestStartY

    targetY, lowestY, highestStartY = chooseNormalTargetY()

    if previousTargetY ~= targetY then
      log("Normale Mining-Y aus Miner-ID verteilt: "..targetY.." (zwischen "..lowestY.." und "..highestStartY..").")
    end
  end

  save()
end

save = function()
  writeTable(STATE, {
    version=STATE_VERSION,
    x=x,
    y=y,
    z=z,
    homeX=homeX,
    homeZ=homeZ,
    mineCenterX=mineCenterX,
    mineCenterZ=mineCenterZ,
    mineMinX=mineMinX,
    mineMaxX=mineMaxX,
    mineMinZ=mineMinZ,
    mineMaxZ=mineMaxZ,
    heading=heading,
    storageHeading=storageHeading,
    fuelHeading=fuelHeading,
    topY=topY,
    targetY=targetY,
    normalLowestY=normalLowestY,
    miningMode=miningMode,
    wantedOres=wantedOres,
    wantedOrePatterns=wantedOrePatterns,
    recoveryX=recoveryX,
    recoveryY=recoveryY,
    recoveryZ=recoveryZ,
    recoveryRadius=recoveryRadius,
    unloadChestFingerprint=unloadChestFingerprint,
    fuelChestFingerprint=fuelChestFingerprint,
    adminId=adminId,
    adminStartReceived=adminStartReceived
  })
end

stop = function(msg)
  save()
  print("")
  print("====== STOP / RECOVERY ======")
  print(msg)
  print("Position: x="..x.." y="..y.." z="..z.." heading="..heading)
  print("Home: x="..tostring(homeX).." z="..tostring(homeZ))
  print("Mine-Center: x="..tostring(mineCenterX).." z="..tostring(mineCenterZ))
  if mineMinX then
    print("Mine-Bereich: x="..mineMinX..".."..mineMaxX.." z="..mineMinZ..".."..mineMaxZ)
  end
  print("Top-Y: "..tostring(topY))
  print("Ziel-Y: "..tostring(targetY))
  print("Mining-Modus: "..tostring(miningMode))
  print("Turtle-Fuel: "..fuel().." / "..fuelLimit())
  print("Ores abgebaut: "..oreMinedCount)
  print("=============================")

  if fatalRecoveryHandler and not inFatalRecovery then
    local ok, recovered = pcall(fatalRecoveryHandler, "Stop: "..tostring(msg), nil)

    if ok and recovered then
      return
    end

    if not ok then
      debugLog("REC fail pcall: "..tostring(recovered))
    else
      debugLog("REC fail returned false")
    end
  end

  debugLog("STOP error: "..tostring(msg))
  error(msg)
end

function setup()
  print("========== SETUP ==========")
  print("Turtle steht am Startpunkt.")
  print("Slot 13: Ender-Modem-Modul.")
  print("Slot 15: Entlade-Ender-Chest.")
  print("Slot 16: Fuel-Ender-Chest.")
  print("Ender/Wireless Modem und GPS werden genutzt.")
  print("")

  repairStartupEquipment()

  locateGps(true)
  print("GPS-Position: x="..x.." y="..y.." z="..z)

  topY = y
  homeX = x
  homeZ = z
  mineCenterX = x
  mineCenterZ = z
  mineMinX = nil
  mineMaxX = nil
  mineMinZ = nil
  mineMaxZ = nil

  heading = autoDetectStartHeading() or CONFIG_HEADING
  print("Startausrichtung: "..headingName(heading).." ("..heading..")")
  gpsHeadingCalibration("Setup", false)
  normalLowestY = CONFIG_LOWEST_Y

  local setupBlocks, setupErr = setupScan(MIN_SCAN_RADIUS)
  if setupBlocks and looksLikeNether(setupBlocks) then
    miningMode = "netherite"
    targetY = CONFIG_NETHERITE_TARGET_Y
    print("Nether erkannt. Mining-Modus: netherite")
    print("Suche nur Ancient Debris auf Ziel-Y "..targetY)
  else
    if setupErr then
      print("Nether-Check nicht moeglich: "..tostring(setupErr))
    end

    miningMode = "normal"
    local lowestY, highestStartY
    targetY, lowestY, highestStartY = chooseNormalTargetY()
    print("Verteilte Mining-Start-Y: "..targetY.." (zwischen "..lowestY.." und "..highestStartY..")")
  end

  fuelHeading = heading
  storageHeading = (heading + 2) % 4
  refreshReservedChestFingerprints(true)

  save()
end

function loadOrSetupState()
  if fs.exists(STATE) then
    local s = readTable(STATE)

    if type(s) == "table" and s.version == STATE_VERSION then
      x=s.x
      y=s.y
      z=s.z
      homeX=s.homeX or s.x or 0
      homeZ=s.homeZ or s.z or 0
      mineCenterX=s.mineCenterX or homeX
      mineCenterZ=s.mineCenterZ or homeZ
      mineMinX=s.mineMinX
      mineMaxX=s.mineMaxX
      mineMinZ=s.mineMinZ
      mineMaxZ=s.mineMaxZ
      heading=s.heading
      storageHeading=s.storageHeading
      fuelHeading=s.fuelHeading
      topY=s.topY
      targetY=s.targetY
      normalLowestY=s.normalLowestY or CONFIG_LOWEST_Y
      miningMode=s.miningMode or "normal"
      wantedOres=s.wantedOres
      wantedOrePatterns=s.wantedOrePatterns
      recoveryX=s.recoveryX
      recoveryY=s.recoveryY
      recoveryZ=s.recoveryZ
      recoveryRadius=s.recoveryRadius or recoveryRadius
      unloadChestFingerprint=s.unloadChestFingerprint
      fuelChestFingerprint=s.fuelChestFingerprint
      adminId=s.adminId
      adminStartReceived = s.adminStartReceived ~= false
      log("Resume gefunden.")
      gpsHeadingCalibration("Resume", false)
    else
      fs.delete(STATE)
      setup()
    end
  else
    setup()
  end

  repairStartupEquipment()
  refreshReservedChestFingerprints()
  ensureTargetY()
end

function isOre(name)
  if not name then return false end

  if wantedOrePatterns then
    for _,pattern in ipairs(wantedOrePatterns) do
      if string.find(name, pattern) then
        return true
      end
    end

    return false
  end

  if wantedOres then
    return wantedOres[name] == true
  end

  if miningMode == "netherite" then
    return NETHERITE_TARGETS[name] == true
  end

  if TARGET_ORES[name] then return true end

  local lowerName = string.lower(name)
  if string.find(lowerName, "_ore", 1, true) or string.find(lowerName, ":ore", 1, true) then
    return true
  end

  local mod = string.match(name, "^([^:]+):")
  if mod and TARGET_MODS[mod] then
    return true
  end

  return false
end

function isJunkItem(name)
  if not name then return false end

  if JUNK[name] then return true end

  if miningMode == "netherite" and NETHERITE_JUNK[name] then
    return true
  end

  return false
end

function isProtectedBlock(name)
  if not name then return false end

  if isEnderChestBlockName(name) then
    return true
  end

  if string.find(name, "turtle", 1, true) then
    return true
  end

  return false
end

function recordOreMined(name)
  oreMinedCount = oreMinedCount + 1
  minedSinceStatus[name or "unknown"] = (minedSinceStatus[name or "unknown"] or 0) + 1
end

function statusPayload(kind)
  local mined = minedSinceStatus

  return {
    type="miner_status",
    kind=kind or "status",
    id=computerId(),
    label=os.getComputerLabel and os.getComputerLabel() or nil,
    x=x,
    y=y,
    z=z,
    homeX=homeX,
    homeZ=homeZ,
    mineCenterX=mineCenterX,
    mineCenterZ=mineCenterZ,
    mineMinX=mineMinX,
    mineMaxX=mineMaxX,
    mineMinZ=mineMinZ,
    mineMaxZ=mineMaxZ,
    heading=headingName(heading),
    fuel=fuel(),
    fuelLimit=fuelLimit(),
    miningMode=miningMode,
    wantedOres=wantedOres,
    wantedOrePatterns=wantedOrePatterns,
    recoveryX=recoveryX,
    recoveryY=recoveryY,
    recoveryZ=recoveryZ,
    recoveryRadius=recoveryRadius,
    normalLowestY=normalLowestY,
    targetY=targetY,
    minedLastMinute=mined,
    minedLastMinuteTotal=tableCount(mined),
    minedTotal=oreMinedCount,
    state=minerState,
    alert=minerAlert,
    lastCommand=lastCommand,
    lastCommandSeq=lastCommandSeq,
    wantsCommand=true
  }
end

function sendStatus(kind, resetMinute)
  if not openWirelessModem() then
    log("Kein Ender/Wireless Modem gefunden.")
    return false
  end

  locateGps(false)

  local payload = statusPayload(kind)

  rednet.broadcast(payload, ADMIN_PROTOCOL)

  unequipEnderModem()

  if resetMinute then
    minedSinceStatus = {}
    lastStatusAt = os.epoch("utc")
  end

  return true
end

function sendStatusKeepModem(kind, resetMinute)
  if not openWirelessModem() then
    log("Kein Ender/Wireless Modem gefunden.")
    return false
  end

  locateGps(false)
  rednet.broadcast(statusPayload(kind), ADMIN_PROTOCOL)

  if resetMinute then
    minedSinceStatus = {}
    lastStatusAt = os.epoch("utc")
  end

  return true
end

function sendAlert(alert, kind)
  minerAlert = alert
  return sendStatus(kind or alert or "alert", false)
end

function clearAlert(alert)
  if not alert or minerAlert == alert then
    minerAlert = nil
  end
end

function commandTargetsThisMiner(cmd)
  local id = computerId()
  local target = cmd.targetId or cmd.minerId or cmd.id

  return target == nil
    or target == id
    or tostring(target) == tostring(id)
    or target == "all"
    or target == "*"
end

function commandValue(cmd, key)
  if cmd[key] ~= nil then return cmd[key] end
  if type(cmd.target) == "table" then return cmd.target[key] end
  if type(cmd.coords) == "table" then return cmd.coords[key] end
  if type(cmd.coord) == "table" then return cmd.coord[key] end
  if type(cmd.position) == "table" then return cmd.position[key] end
  if type(cmd.pos) == "table" then return cmd.pos[key] end
  if type(cmd.area) == "table" then return cmd.area[key] end
  if type(cmd.bounds) == "table" then return cmd.bounds[key] end
  return nil
end

function normalizeOreName(name)
  if not name then return nil end

  local text = string.lower(tostring(name))
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")

  if text == "" then return nil end
  if text == "all" or text == "*" then return "all" end
  if text == "netherite" or text == "ancient_debris" then return "minecraft:ancient_debris" end
  if text == "draconium" or text == "draconium_ore" then return "draconicevolution:draconium_ore" end
  if string.find(text, ":", 1, true) then return text end
  if string.find(text, "_ore", 1, true) then return "minecraft:"..text end

  return "minecraft:"..text.."_ore"
end

function oreSetFromCommand(value)
  if value == nil then return nil, false end

  local result = {}

  local function addOreName(name)
    if name == "draconicevolution:draconium_ore" then
      for alias in pairs(DRACONIUM_ORES) do
        result[alias] = true
      end
    end

    result[name] = true

    local vanilla = string.match(name, "^minecraft:(.+_ore)$")
    if vanilla and not string.find(vanilla, "^deepslate_", false) then
      result["minecraft:deepslate_"..vanilla] = true
    end
  end

  local function addCommandPart(part)
    local raw = string.lower(tostring(part))
    raw = string.gsub(raw, "^%s+", "")
    raw = string.gsub(raw, "%s+$", "")

    if raw == "draconium" or raw == "draconium_ore" then
      for alias in pairs(DRACONIUM_ORES) do
        result[alias] = true
      end
      return false
    end

    local name = normalizeOreName(part)
    if name == "all" then return true end
    if name then addOreName(name) end
    return false
  end

  if type(value) == "string" then
    for part in string.gmatch(value, "[^,]+") do
      if addCommandPart(part) then return nil, true end
    end
  elseif type(value) == "table" then
    for _,part in pairs(value) do
      if addCommandPart(part) then return nil, true end
    end
  end

  for _ in pairs(result) do
    return result, true
  end

  return nil, true
end

function orePatternsFromCommand(value)
  if value == nil then return nil, false end

  local patterns = {}

  if type(value) == "string" then
    if value == "" or value == "all" or value == "*" then
      return nil, true
    end

    for part in string.gmatch(value, "[^,]+") do
      local text = string.gsub(part, "^%s+", "")
      text = string.gsub(text, "%s+$", "")

      if text ~= "" then
        table.insert(patterns, text)
      end
    end
  elseif type(value) == "table" then
    for _,part in pairs(value) do
      local text = string.gsub(tostring(part), "^%s+", "")
      text = string.gsub(text, "%s+$", "")

      if text ~= "" and text ~= "all" and text ~= "*" then
        table.insert(patterns, text)
      end
    end
  end

  if #patterns == 0 then return nil, true end
  return patterns, true
end

function areaValue(cmd, ...)
  local keys = { ... }

  for _,key in ipairs(keys) do
    local value = commandValue(cmd, key)
    if value ~= nil then return tonumber(value) end
  end

  return nil
end

function setMineArea(ax1, az1, ax2, az2)
  mineMinX = math.min(ax1, ax2)
  mineMaxX = math.max(ax1, ax2)
  mineMinZ = math.min(az1, az2)
  mineMaxZ = math.max(az1, az2)

  local width = mineMaxX - mineMinX + 1
  local depth = mineMaxZ - mineMinZ + 1
  local id = computerId() or 0

  mineCenterX = mineMinX + (id % width)
  mineCenterZ = mineMinZ + (math.floor(id / width) % depth)
end

function clearMineArea()
  mineMinX = nil
  mineMaxX = nil
  mineMinZ = nil
  mineMaxZ = nil
end

function inMineArea(tx, tz)
  if mineMinX then
    return tx >= mineMinX and tx <= mineMaxX and tz >= mineMinZ and tz <= mineMaxZ
  end

  return math.abs(tx - mineCenterX) <= MAX_DISTANCE_FROM_SHAFT
    and math.abs(tz - mineCenterZ) <= MAX_DISTANCE_FROM_SHAFT
end

function clampToMineArea(tx, tz)
  if not mineMinX then return tx, tz end

  if tx < mineMinX then tx = mineMinX end
  if tx > mineMaxX then tx = mineMaxX end
  if tz < mineMinZ then tz = mineMinZ end
  if tz > mineMaxZ then tz = mineMaxZ end

  return tx, tz
end

function nearestPointInMineArea(tx, tz)
  if mineMinX then
    return clampToMineArea(tx, tz)
  end

  local minX = mineCenterX - MAX_DISTANCE_FROM_SHAFT
  local maxX = mineCenterX + MAX_DISTANCE_FROM_SHAFT
  local minZ = mineCenterZ - MAX_DISTANCE_FROM_SHAFT
  local maxZ = mineCenterZ + MAX_DISTANCE_FROM_SHAFT

  if tx < minX then tx = minX end
  if tx > maxX then tx = maxX end
  if tz < minZ then tz = minZ end
  if tz > maxZ then tz = maxZ end

  return tx, tz
end

function reservedChestsReady()
  recoverAdjacentEnderChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")
  recoverAdjacentEnderChest(FUEL_CHEST_SLOT, "Fuel-Ender-Chest")

  local unloadItem = detailedItem(UNLOAD_CHEST_SLOT)
  local fuelItem = detailedItem(FUEL_CHEST_SLOT)

  if not reservedChestMatchesSlot(UNLOAD_CHEST_SLOT, unloadItem) then
    return false, UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest"
  end

  if not reservedChestMatchesSlot(FUEL_CHEST_SLOT, fuelItem) then
    return false, FUEL_CHEST_SLOT, "Fuel-Ender-Chest"
  end

  setReservedChestFingerprint(UNLOAD_CHEST_SLOT)
  setReservedChestFingerprint(FUEL_CHEST_SLOT)
  return true
end

function commandNeedsReservedChests(action)
  if action == "set_recovery" or action == "recovery" or action == "recover" then return false end
  if action == "miner_status" then return false end
  return true
end

function applyAdminCommand(sender, cmd)
  if type(cmd) == "string" then
    cmd = { command=cmd }
  end

  if type(cmd) ~= "table" or not commandTargetsThisMiner(cmd) then
    return false
  end

  adminId = sender

  local action = cmd.command or cmd.cmd or cmd.type or "start"

  if action == "miner_status" then
    return false
  end

  lastCommand = action
  lastCommandSeq = cmd.seq
  minerAlert = nil

  local tx = tonumber(commandValue(cmd, "x"))
  local ty = tonumber(commandValue(cmd, "y"))
  local tz = tonumber(commandValue(cmd, "z"))
  if not tx then tx = tonumber(commandValue(cmd, "X")) end
  if not ty then ty = tonumber(commandValue(cmd, "Y")) end
  if not tz then tz = tonumber(commandValue(cmd, "Z")) end
  local recoveryTx = tonumber(cmd.recoveryX)
  local recoveryTy = tonumber(cmd.recoveryY)
  local recoveryTz = tonumber(cmd.recoveryZ)
  local rr = tonumber(cmd.recoveryRadius or cmd.radius or cmd.spread)
  local ax1 = areaValue(cmd, "x1", "minX", "fromX")
  local ax2 = areaValue(cmd, "x2", "maxX", "toX")
  local az1 = areaValue(cmd, "z1", "minZ", "fromZ")
  local az2 = areaValue(cmd, "z2", "maxZ", "toZ")

  if action == "set_recovery" or action == "recovery" or action == "recover" then
    if not recoveryTx then recoveryTx = tx end
    if not recoveryTy then recoveryTy = ty end
    if not recoveryTz then recoveryTz = tz end
    debugLog("REC cmd raw x="..tostring(commandValue(cmd, "x")).." y="..tostring(commandValue(cmd, "y")).." z="..tostring(commandValue(cmd, "z")).." rx="..tostring(commandValue(cmd, "recoveryX")).." ry="..tostring(commandValue(cmd, "recoveryY")).." rz="..tostring(commandValue(cmd, "recoveryZ")).." r="..tostring(rr))

    if not recoveryTx or not recoveryTy or not recoveryTz then
      debugLog("REC set rejected missing coords tx="..tostring(recoveryTx).." ty="..tostring(recoveryTy).." tz="..tostring(recoveryTz))
      sendStatus("command_error", false)
      return true
    end

    if recoveryTx then recoveryX = math.floor(recoveryTx + 0.5) end
    if recoveryTy then recoveryY = math.floor(recoveryTy + 0.5) end
    if recoveryTz then recoveryZ = math.floor(recoveryTz + 0.5) end
    if rr then recoveryRadius = math.max(1, math.floor(rr + 0.5)) end

    save()
    log("REC set x="..tostring(recoveryX).." y="..tostring(recoveryY).." z="..tostring(recoveryZ).." r="..tostring(recoveryRadius))

    if action == "recover" and goToRecoveryIfConfigured then
      goToRecoveryIfConfigured("Admin-Recovery", nil)
    end

    sendStatus("command_ack", false)
    return true
  end

  if recoveryTx and recoveryTy and recoveryTz then
    recoveryX = math.floor(recoveryTx + 0.5)
    recoveryY = math.floor(recoveryTy + 0.5)
    recoveryZ = math.floor(recoveryTz + 0.5)
    if rr then recoveryRadius = math.max(1, math.floor(rr + 0.5)) end
    save()
    debugLog("REC embedded set x="..tostring(recoveryX).." y="..tostring(recoveryY).." z="..tostring(recoveryZ).." r="..tostring(recoveryRadius))
  end

  if commandNeedsReservedChests(action) then
    local ready, missingSlot, missingLabel = reservedChestsReady()

    if not ready then
      minerState = "recovery"
      minerAlert = "missing_reserved_chest"
      sendStatus("missing_reserved_chest", false)
      debugLog("REC chest fehlt: "..tostring(missingLabel).." s"..tostring(missingSlot).." cmd="..tostring(action))

      if goToRecoveryIfConfigured then
        local recoveryOk, recoveryErr = pcall(goToRecoveryIfConfigured, missingLabel, missingSlot)
        if not recoveryOk then
          debugLog("REC direct fail: "..tostring(recoveryErr))
        elseif recoveryErr == false then
          debugLog("REC direct false: "..tostring(missingLabel).." s"..tostring(missingSlot))
        end
      end

      waitForRecoveryCoords(missingLabel, missingSlot)
      return true
    end
  end

  if ax1 and ax2 and az1 and az2 then
    setMineArea(math.floor(ax1 + 0.5), math.floor(az1 + 0.5), math.floor(ax2 + 0.5), math.floor(az2 + 0.5))
  else
    if tx or tz then clearMineArea() end
    if tx then mineCenterX = math.floor(tx + 0.5) end
    if tz then mineCenterZ = math.floor(tz + 0.5) end
  end

  if cmd.mode == "netherite" or action == "netherite" then
    miningMode = "netherite"
    if ty then targetY = math.floor(ty + 0.5) end
    if not ty then targetY = CONFIG_NETHERITE_TARGET_Y end
  elseif cmd.mode == "normal" then
    miningMode = "normal"
    if ty then normalLowestY = math.floor(ty + 0.5) end
    targetY = chooseNormalTargetY()
  elseif ty and miningMode == "normal" then
    normalLowestY = math.floor(ty + 0.5)
    targetY = chooseNormalTargetY()
  end

  if action == "unload" then pendingUnload = true end
  if action == "refuel" then pendingRefuel = true end

  local patternSet, patternsSpecified = orePatternsFromCommand(cmd.orePatterns or cmd.patterns)
  if patternsSpecified then
    wantedOrePatterns = patternSet
    wantedOres = nil
  end

  local oreSet, oreSpecified = oreSetFromCommand(cmd.ores or cmd.ore or cmd.want or cmd.wantedOres)
  if oreSpecified then
    wantedOres = oreSet
    wantedOrePatterns = nil
  end

  adminStartReceived = true
  skippedTargets = {}
  save()

  log("Admin-Befehl von "..sender..": "..tostring(action)..
    " center=("..mineCenterX..","..targetY..","..mineCenterZ..")")

  if mineMinX then
    log("Mining-Bereich: x="..mineMinX..".."..mineMaxX.." z="..mineMinZ..".."..mineMaxZ)
  end

  sendStatus("command_ack", false)
  return true
end

function pollAdminCommands(timeout)
  if not openWirelessModem() then return false end

  local waitSeconds = tonumber(timeout) or 0
  local deadline = os.epoch("utc") + math.max(0, waitSeconds) * 1000
  local applied = false

  for _ = 1, COMMAND_POLL_MAX_PACKETS do
    local receiveTimeout = 0

    if waitSeconds > 0 then
      local remainingMs = deadline - os.epoch("utc")
      if remainingMs <= 0 then break end
      receiveTimeout = remainingMs / 1000
    end

    local sender, message, protocol = rednet.receive(nil, receiveTimeout)
    if not sender or not message then break end

    if (protocol == ADMIN_COMMAND_PROTOCOL or protocol == ADMIN_PROTOCOL)
        and not (type(message) == "table" and message.type == "miner_status")
        and applyAdminCommand(sender, message) then
      applied = true
      break
    end
  end

  unequipEnderModem()
  return applied
end

function waitForRecoveryCoords(reason, missingSlot)
  minerState = "recovery_wait_coords"
  minerAlert = "missing_recovery_coords"
  debugLog("REC wait coords reason="..tostring(reason).." slot="..tostring(missingSlot))
  local lastWaitStatusAt = 0

  if not openWirelessModem() then
    debugLog("REC wait no modem at start")
  end

  while not (recoveryX and recoveryY and recoveryZ) do
    save()
    debugLog("REC need coords rx="..tostring(recoveryX).." ry="..tostring(recoveryY).." rz="..tostring(recoveryZ))

    if os.epoch("utc") - lastWaitStatusAt >= 10000 then
      sendStatusKeepModem("missing_recovery_coords", false)
      lastWaitStatusAt = os.epoch("utc")
    end

    if openWirelessModem() then
      local sender, message, protocol = rednet.receive(nil, COMMAND_WAIT)

      if sender and message then
        debugLog("REC got msg sender="..tostring(sender).." proto="..tostring(protocol).." type="..tostring(type(message)))

        if protocol == ADMIN_PROTOCOL or type(message) == "table" then
          applyAdminCommand(sender, message)
        end
      else
        debugLog("REC no cmd")
      end
    else
      debugLog("REC no modem")
      sleep(COMMAND_WAIT)
    end
  end

  unequipEnderModem()

  debugLog("REC coords arrived rx="..tostring(recoveryX).." ry="..tostring(recoveryY).." rz="..tostring(recoveryZ))

  if goToRecoveryIfConfigured then
    local recoveryOk, recoveryErr = pcall(goToRecoveryIfConfigured, reason, missingSlot)

    if not recoveryOk then
      debugLog("REC wait go fail: "..tostring(recoveryErr))
    elseif recoveryErr == false then
      debugLog("REC wait go false")
    end
  end

  return false
end

function sendMinuteStatusIfDue()
  if os.epoch("utc") - lastStatusAt >= STATUS_INTERVAL * 1000 then
    sendStatus("minute", true)
    pollAdminCommands(COMMAND_WAIT)
  else
    pollAdminCommands(0)
  end
end

function waitForAdminStart()
  minerState = "waiting"

  if not openWirelessModem() then
    stop("Kein Ender/Wireless Modem gefunden.")
  end

  log("Computer-ID: "..tostring(computerId()))
  log("Warte auf Start-/Mining-Befehl vom Admin.")

  while not adminStartReceived do
    sendStatus("hello", false)
    pollAdminCommands(COMMAND_WAIT)
    sleep(1)
  end

  minedSinceStatus = {}
  lastStatusAt = os.epoch("utc")
  minerState = "mining"
end

function turnRight()
  turtle.turnRight()
  heading = (heading + 1) % 4
  save()
end

function face(h)
  while heading ~= h do
    turnRight()
  end
end

function redstoneSideForHeading(worldHeading)
  local diff = (worldHeading - heading) % 4

  if diff == 0 then return "front" end
  if diff == 1 then return "right" end
  if diff == 2 then return "back" end
  return "left"
end

function hasTopCalibrationSignal()
  local side = redstoneSideForHeading(storageHeading)
  return redstone.getInput(side), side
end

function calibrateTopFromRedstone(context)
  if x ~= 0 or z ~= 0 or not topY then
    return false
  end

  local active, side = hasTopCalibrationSignal()

  if not active then
    return false
  end

  if y ~= topY then
    log("Kalibriere Top-Y durch Redstone-"..side.." beim Entlader: "..y.." -> "..topY.." ("..context..")")
    y = topY
    save()
  else
    log("Top-Y durch Redstone-"..side.." beim Entlader bestaetigt ("..context..")")
  end

  return true
end

refuelFromEnderChestFull = nil

function checkFuel()
  if fuel() < LOW_FUEL_STOP then
    if refuelFromEnderChestFull then
      refuelFromEnderChestFull()
      return
    end

    log("Turtle-Fuel zu niedrig. Warte auf Fuel in der Turtle.")
    sendAlert("low_fuel_wait", "low_fuel_wait")

    while fuel() < LOW_FUEL_STOP do
      sleep(10)
    end

    clearAlert("low_fuel_wait")
    log("Fuel wieder ausreichend: "..fuel().." / "..fuelLimit())
  end
end

function updateForwardPosition()
  if heading == 0 then
    z = z - 1
  elseif heading == 1 then
    x = x + 1
  elseif heading == 2 then
    z = z + 1
  elseif heading == 3 then
    x = x - 1
  end
end

function forwardPosition()
  local nx, nz = x, z

  if heading == 0 then
    nz = nz - 1
  elseif heading == 1 then
    nx = nx + 1
  elseif heading == 2 then
    nz = nz + 1
  elseif heading == 3 then
    nx = nx - 1
  end

  return nx, nz
end

function distanceFromMineArea(tx, tz)
  if mineMinX then
    local dx = 0
    local dz = 0

    if tx < mineMinX then
      dx = mineMinX - tx
    elseif tx > mineMaxX then
      dx = tx - mineMaxX
    end

    if tz < mineMinZ then
      dz = mineMinZ - tz
    elseif tz > mineMaxZ then
      dz = tz - mineMaxZ
    end

    return dx + dz
  end

  local dx = math.max(0, math.abs(tx - mineCenterX) - MAX_DISTANCE_FROM_SHAFT)
  local dz = math.max(0, math.abs(tz - mineCenterZ) - MAX_DISTANCE_FROM_SHAFT)
  return dx + dz
end

function forwardStaysInMineArea()
  if recoveryTravelMode then return true end

  local nx, nz = forwardPosition()

  if inMineArea(x, z) then
    return inMineArea(nx, nz)
  end

  return distanceFromMineArea(nx, nz) < distanceFromMineArea(x, z)
end

function clean()
  local old = turtle.getSelectedSlot()

  for i=1,WORK_SLOT_LAST do
    rescueWorkSlotReservedChest(i, "clean")
    turtle.select(i)
    local item = turtle.getItemDetail()
    if item and isJunkItem(item.name) then
      turtle.drop()
    end
  end

  turtle.select(old)
end

function inventoryFull()
  for i=1,WORK_SLOT_LAST do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

function hasValuableItems()
  for i=1,WORK_SLOT_LAST do
    local item = turtle.getItemDetail(i)
    if item and not isJunkItem(item.name) then return true end
  end
  return false
end

function printValuables()
  local found = false
  log("Inventar-Check:")

  for i=1,WORK_SLOT_LAST do
    local item = turtle.getItemDetail(i)
    if item and not isJunkItem(item.name) then
      found = true
      print(" Slot "..i..": "..item.name.." x"..item.count)
    end
  end

  if not found then
    print(" Keine wertvollen Items im Inventar.")
  end
end

function digFrontCanFail()
  ensureMiningUpgrades("front")

  local tries = 0

  while turtle.detect() do
    local hasBlock, data = turtle.inspect()

    if hasBlock and data and isProtectedBlock(data.name) then
      log("Geschuetzter Block vorne erkannt, wird nicht abgebaut: "..data.name)
      return false
    end

    local oreBlock = hasBlock and data and isOre(data.name)

    if oreBlock then
      log("BAUE ORE vorne: "..data.name)
    end

    local ok = turtle.dig()

    if ok then
      if oreBlock then recordOreMined(data.name) end
      tries = 0
    else
      tries = tries + 1

      if tries >= 8 then
        local hb, d = turtle.inspect()
        if hb and d then
          log("Block vorne nicht abbaubar: "..d.name)
          return false
        else
          return true
        end
      end
    end

    sleep(0.05)
  end

  return true
end

function digUpCanFail()
  ensureMiningUpgrades("up")

  local tries = 0

  while turtle.detectUp() do
    local hasBlock, data = turtle.inspectUp()

    if hasBlock and data and isProtectedBlock(data.name) then
      log("Geschuetzter Block oben erkannt, wird nicht abgebaut: "..data.name)
      return false
    end

    local oreBlock = hasBlock and data and isOre(data.name)

    if oreBlock then
      log("BAUE ORE oben: "..data.name)
    end

    local ok = turtle.digUp()

    if ok then
      if oreBlock then recordOreMined(data.name) end
      tries = 0
    else
      tries = tries + 1

      if tries >= 8 then
        local hb, d = turtle.inspectUp()
        if hb and d then
          log("Block oben nicht abbaubar: "..d.name)
          return false
        else
          return true
        end
      end
    end

    sleep(0.05)
  end

  return true
end

function digDownCanFail()
  ensureMiningUpgrades("down")

  local tries = 0

  while turtle.detectDown() do
    local hasBlock, data = turtle.inspectDown()

    if hasBlock and data and isProtectedBlock(data.name) then
      log("Geschuetzter Block unten erkannt, wird nicht abgebaut: "..data.name)
      return false
    end

    local oreBlock = hasBlock and data and isOre(data.name)

    if oreBlock then
      log("BAUE ORE unten: "..data.name)
    end

    local ok = turtle.digDown()

    if ok then
      if oreBlock then recordOreMined(data.name) end
      tries = 0
    else
      tries = tries + 1

      if tries >= 8 then
        local hb, d = turtle.inspectDown()
        if hb and d then
          log("Block unten nicht abbaubar: "..d.name)
          return false
        else
          return true
        end
      end
    end

    sleep(0.05)
  end

  return true
end

function rawForward(allowAboveTarget, entityAvoid)
  checkFuel()

  if y > targetY and not allowAboveTarget then
    return false
  end

  if not forwardStaysInMineArea() then
    local nx, nz = forwardPosition()
    log("Bewegung aus Mining-Bereich verhindert: x="..nx.." z="..nz)
    return false
  end

  if not digFrontCanFail() then
    return false
  end

  local tries = 0

  while not turtle.forward() do
    if turtle.detect() then
      turtle.attack()

      if not digFrontCanFail() then
        return false
      end
    else
      if entityAvoid then
        local old = heading
        local dir = ({1, 3})[math.random(1, 2)]
        local side = (old + dir) % 4

        log("Bewegung blockiert ohne Block. Weiche zufaellig zur Seite aus.")
        sleep(math.random(2, 8) / 10)
        face(side)

        if rawForward(allowAboveTarget, false) then
          face(old)
          save()
          return true
        end

        face(old)
      else
        sleep(math.random(2, 8) / 10)
      end
    end

    tries = tries + 1
    if tries >= 8 then return false end
    sleep(0.1)
  end

  updateForwardPosition()
  save()
  return true
end

function rawUp()
  checkFuel()

  if not digUpCanFail() then return false end

  local tries = 0

  while not turtle.up() do
    if turtle.detectUp() then
      turtle.attackUp()

      if not digUpCanFail() then return false end
    else
      log("Nach oben blockiert ohne Block. Warte kurz.")
      sleep(math.random(2, 8) / 10)
    end

    tries = tries + 1
    if tries >= 20 then return false end
    sleep(0.05)
  end

  y = y + 1
  save()
  return true
end

function rawDown()
  checkFuel()

  if not digDownCanFail() then return false end

  local tries = 0

  while not turtle.down() do
    if turtle.detectDown() then
      turtle.attackDown()

      if not digDownCanFail() then return false end
    else
      log("Nach unten blockiert ohne Block. Warte kurz.")
      sleep(math.random(2, 8) / 10)
    end

    tries = tries + 1
    if tries >= 20 then return false end
    sleep(0.05)
  end

  y = y - 1
  save()
  return true
end

tryUpWithBypass = nil

function trySideBypassUp()
  log("Nach oben blockiert. Versuche seitlich auszuweichen.")

  local startHeading = heading
  local directions = { 1, 3, 2, 0 }

  for _,offset in ipairs(directions) do
    face((startHeading + offset) % 4)

    if rawForward(true, true) then
      if rawUp() then
        face(startHeading)
        log("Aufwaerts-Ausweichroute erfolgreich.")
        return true
      end

      face((heading + 2) % 4)
      rawForward(true, true)
    end

    face(startHeading)
  end

  return false
end

tryUpWithBypass = function()
  if rawUp() then return true end
  return trySideBypassUp()
end

function up()
  if tryUpWithBypass() then return end
  stop("Kann nicht nach oben fahren.")
end

function down()
  if not rawDown() then stop("Kann nicht nach unten fahren.") end
end

function forwardStrict()
  if not rawForward(false) then
    stop("Kann nicht streng nach vorne fahren.")
  end
end

function tryBypassUp()
  log("Versuche Ausweichroute: hoch -> 2 vor -> runter")

  if y > targetY then
    log("Ausweichen ueber Ziel-Y nicht erlaubt.")
    return false
  end

  local startY = y
  local startHeading = heading

  if not tryUpWithBypass() then
    face(startHeading)
    return false
  end

  if not rawForward(true) then
    while y > startY do
      if not rawDown() then
        stop("Ausweichen fehlgeschlagen und Rueckweg nach unten blockiert.")
      end
    end
    face(startHeading)
    return false
  end

  if not rawForward(true) then
    face((startHeading + 2) % 4)

    if not rawForward(true) then
      stop("Ausweichen fehlgeschlagen und Rueckweg oben blockiert.")
    end

    face(startHeading)

    while y > startY do
      if not rawDown() then
        stop("Ausweichen fehlgeschlagen und Rueckweg nach unten blockiert.")
      end
    end

    return false
  end

  while y > startY do
    if not rawDown() then
      stop("Ausweichen fast fertig, aber kann nicht runter.")
    end
  end

  face(startHeading)
  log("Ausweichroute erfolgreich.")
  return true
end

function forwardTravel(remaining)
  if rawForward(false, true) then
    return true
  end

  if remaining < 2 then
    log("Vorne blockiert, aber fuer Ausweichroute bleiben weniger als 2 Bloecke.")
    return false
  end

  return tryBypassUp()
end

function descendToTargetWithSidestep()
  local sidesteps = 0

  while y > targetY do
    if rawDown() then
      clean()
    else
      local startHeading = heading
      local moved = false

      log("Abstieg zu Ziel-Y blockiert. Suche seitlich eine freie Abstiegsspalte.")

      for _,offset in ipairs({1, 3, 0, 2}) do
        face((startHeading + offset) % 4)

        if rawForward(true, true) then
          moved = true
          sidesteps = sidesteps + 1
          clean()
          break
        end
      end

      if not moved then
        face(startHeading)
        return false
      end

      if sidesteps >= 16 then
        log("Zu viele Seitenschritte beim Abstieg zu Ziel-Y.")
        return false
      end
    end
  end

  return true
end

function moveBackStrict()
  local old = heading
  face((old + 2) % 4)

  if not rawForward(false) then
    stop("Kann nicht zurueck fahren.")
  end

  face(old)
end

function minimumFuelForTripFromTop()
  local shaftDistance = math.abs(topY - targetY)
  return shaftDistance * 2 + RETURN_FUEL_BUFFER
end

function waitForTopRedstoneRelease()
  if x ~= 0 or z ~= 0 or y ~= topY then
    return
  end

  while redstone.getInput("top") do
    log("Redstone oben aktiv. Warte bei den Kisten.")
    sleep(5)
  end
end

function refuelFromFrontFull()
  if x ~= 0 or z ~= 0 or y ~= topY then
    stop("Tanken geht nur oben an der Fuel-Kiste.")
  end

  local old = heading
  face(fuelHeading)

  while fuel() < fuelLimit() do
    log("Warte auf Fuel in der Kiste VOR der Turtle. Aktuell "..fuel().." / "..fuelLimit())

    local before = fuel()

    for i=1,WORK_SLOT_LAST do
      rescueWorkSlotReservedChest(i, "refuel front")
      turtle.select(i)

      while fuel() < fuelLimit() do
        local got = turtle.suck(64)
        if not got then break end

        if rescueWorkSlotReservedChest(i, "refuel front suck") then
          break
        end

        local ok = turtle.refuel()
        if not ok then
          if rescueWorkSlotReservedChest(i, "refuel front reject") then
            break
          end

          turtle.drop()
          break
        end
      end
    end

    if fuel() == before then
      sleep(10)
    end
  end

  face(old)

  log("Turtle-Fuel voll: "..fuel().." / "..fuelLimit())

  local needed = minimumFuelForTripFromTop()

  if fuel() < needed then
    log("Warnung: Fuel voll, aber Reserve kleiner als berechnet. Benoetigt ca. "..needed..", vorhanden "..fuel())
  end
end

function storeToBack()
  log("Lagere Items in Kiste HINTER der Turtle.")
  protectReservedChests("storeToBack")

  local old = heading
  face(storageHeading)

  for i=1,WORK_SLOT_LAST do
    rescueWorkSlotReservedChest(i, "storeToBack")
    turtle.select(i)
    local item = turtle.getItemDetail()

    if item and isReservedEnderChestItemName(item.name) then
      log("Lager-Kiste ueberspringt reservierte Chest in Arbeitsslot "..i..": "..tostring(item.name))
      item = nil
    end

    if item and not isJunkItem(item.name) then
      local ok = turtle.drop()
      if not ok then
        stop("Lager-Kiste hinten ist voll oder nicht erreichbar.")
      end
    end
  end

  face(old)
end

function requireReservedChest(slot, label)
  if slot == MODEM_SLOT then
    local ok, modemName = ensureModemAvailable()

    if ok then
      return modemName
    end

    stop(label.." fehlt in Slot "..slot.." oder ist nicht ausgeruestet.")
  end

  if slot == UNLOAD_CHEST_SLOT or slot == FUEL_CHEST_SLOT then
    local ready, missingSlot, missingLabel = reservedChestsReady()

    if not ready then
      if goToRecoveryIfConfigured then
        local recoveryOk, recoveryErr = pcall(goToRecoveryIfConfigured, missingLabel, missingSlot)
        if not recoveryOk then
          debugLog("REC direct fail: "..tostring(recoveryErr))
        elseif recoveryErr == false then
          debugLog("REC direct false: "..tostring(missingLabel).." s"..tostring(missingSlot))
        end
      end

      waitForRecoveryCoords(missingLabel, missingSlot)
      stop(missingLabel.." fehlt in Slot "..missingSlot.." oder ist keine Ender-Chest.")
    end
  end

  local item = detailedItem(slot)

  if not reservedChestMatchesSlot(slot, item) then
    recoverAdjacentEnderChest(slot, label)
    item = detailedItem(slot)
  end

  if not reservedChestMatchesSlot(slot, item) then
    if item then
      log(label.." Slot "..slot.." enthaelt: "..tostring(item.name).." x"..tostring(item.count))
    else
      log(label.." Slot "..slot.." ist leer.")
    end

    if goToRecoveryIfConfigured then
      local recoveryOk, recoveryErr = pcall(goToRecoveryIfConfigured, label, slot)
      if not recoveryOk then
        debugLog("REC direct fail: "..tostring(recoveryErr))
      elseif recoveryErr == false then
        debugLog("REC direct false: "..tostring(label).." s"..tostring(slot))
      end
    end

    waitForRecoveryCoords(label, slot)
    stop(label.." fehlt in Slot "..slot.." oder ist keine Ender-Chest.")
  end

  setReservedChestFingerprint(slot)
  return item.name
end

function placeReusableChest(slot, label)
  local chestName = requireReservedChest(slot, label)
  local chestFingerprint = setReservedChestFingerprint(slot)
  turtle.select(slot)

  while turtle.detect() do
    local hasBlock, data = turtle.inspect()

    if hasBlock and data and isEnderChestBlockName(data.name) then
      if not recoverFrontEnderChest(slot, label) then
        log("Ender-Chest vorne konnte nicht eingesammelt werden. Warte.")
        sleep(5)
      end
    else
      log("Platz fuer "..label.." vorne blockiert. Raeume Block weg.")
      if not digFrontCanFail() then
        sleep(5)
      end
    end
  end

  turtle.select(slot)

  while not turtle.place() do
    log("Kann "..label.." nicht platzieren. Warte.")
    sleep(5)
  end

  activePlacedReservedChestSlot = slot
  return chestName, chestFingerprint
end

function recoverReusableChest(slot, label, chestName, chestFingerprint)
  turtle.select(slot)

  while turtle.detect() do
    local hasBlock, data = turtle.inspect()

    if hasBlock and data and data.name ~= chestName then
      stop(label.." vorne ist nicht die eigene Chest: "..data.name)
    end

    if hasBlock and data and isProtectedBlock(data.name) and data.name ~= chestName then
      stop("Geschuetzter Block vorne wird nicht abgebaut: "..data.name)
    end

    if turtle.dig() then
      break
    end

    log("Kann "..label.." nicht abbauen. Warte.")
    sleep(5)
  end

  local slotItem = detailedItem(slot)
  if reservedChestMatchesSlot(slot, slotItem) and turtle.getItemCount(slot) == 1 then
    setReservedChestFingerprint(slot)
    if activePlacedReservedChestSlot == slot then
      activePlacedReservedChestSlot = nil
    end
    return
  end

  if moveReservedChestToSlot(slot, label) then
    if activePlacedReservedChestSlot == slot then
      activePlacedReservedChestSlot = nil
    end
    return
  end

  for i=1,WORK_SLOT_LAST do
    local item = detailedItem(i)
    local matchesFingerprint = chestFingerprint and itemFingerprint(item) == chestFingerprint

    if item and (matchesFingerprint or (not chestFingerprint and item.name == chestName)) then
      turtle.select(i)
      turtle.transferTo(slot, 1)
      turtle.select(slot)
      setReservedChestFingerprint(slot)
      if activePlacedReservedChestSlot == slot then
        activePlacedReservedChestSlot = nil
      end
      return
    end
  end

  stop(label.." konnte nach dem Abbauen nicht in Slot "..slot.." wiedergefunden werden.")
end

function sendStatusWithReservedChest(slot, label, chestName, chestFingerprint, kind, resetMinute)
  if turtle.getItemCount(slot) == 0 then
    recoverReusableChest(slot, label, chestName, chestFingerprint)
  end

  return sendStatus(kind, resetMinute)
end

function swapReservedChestSlots()
  local tempSlot = findEmptySlot(1, WORK_SLOT_LAST)

  if not tempSlot then
    stop("Kann Ender-Chests nicht tauschen: kein freier Arbeitsslot.")
  end

  log("Fuel- und Entlade-Ender-Chest waren vertauscht. Tausche Slot "..UNLOAD_CHEST_SLOT.." und "..FUEL_CHEST_SLOT..".")

  turtle.select(UNLOAD_CHEST_SLOT)
  if not turtle.transferTo(tempSlot) then
    stop("Kann Entlade-Ender-Chest nicht in temporaeren Slot "..tempSlot.." verschieben.")
  end

  turtle.select(FUEL_CHEST_SLOT)
  if not turtle.transferTo(UNLOAD_CHEST_SLOT) then
    stop("Kann falsche Fuel-Ender-Chest nicht nach Slot "..UNLOAD_CHEST_SLOT.." verschieben.")
  end

  turtle.select(tempSlot)
  if not turtle.transferTo(FUEL_CHEST_SLOT) then
    stop("Kann echte Fuel-Ender-Chest nicht nach Slot "..FUEL_CHEST_SLOT.." verschieben.")
  end
end

function tryRefuelFromReusableChest(slot, label)
  log("Tanke aus wiederverwendbarer "..label.." aus Slot "..slot..".")
  protectReservedChests("tryRefuelFromReusableChest")

  local chestName, chestFingerprint = placeReusableChest(slot, label)
  local emptyFuelRounds = 0
  local gainedFuel = false

  while fuel() < fuelLimit() do
    local before = fuel()

    for i=1,WORK_SLOT_LAST do
      rescueWorkSlotReservedChest(i, label.." refuel")
      turtle.select(i)

      while fuel() < fuelLimit() do
        local got = turtle.suck(64)
        if not got then break end

        if rescueWorkSlotReservedChest(i, label.." suck") then
          break
        end

        if not turtle.refuel() then
          if rescueWorkSlotReservedChest(i, label.." reject") then
            break
          end

          turtle.drop()
          break
        end
      end
    end

    if fuel() > before then
      gainedFuel = true
      emptyFuelRounds = 0
    else
      emptyFuelRounds = emptyFuelRounds + 1
      log(label.." liefert gerade keinen Fuel. Versuch "..emptyFuelRounds.." / "..FUEL_CHEST_EMPTY_RETRIES..".")
      minerAlert = "fuel_wait"
      sendStatusWithReservedChest(slot, label, chestName, chestFingerprint, "fuel_wait", false)

      if emptyFuelRounds >= FUEL_CHEST_EMPTY_RETRIES then
        recoverReusableChest(slot, label, chestName, chestFingerprint)
        return false, gainedFuel
      end

      pollAdminCommands(COMMAND_WAIT)
      sleep(10)

      if fuel() < fuelLimit() then
        chestName, chestFingerprint = placeReusableChest(slot, label)
      end
    end
  end

  recoverReusableChest(slot, label, chestName, chestFingerprint)
  return true, gainedFuel
end

function unloadToEnderChest()
  clean()
  protectReservedChests("unloadToEnderChest")
  log("Entlade in wiederverwendbare Ender-Chest aus Slot "..UNLOAD_CHEST_SLOT..".")

  local chestName, chestFingerprint = placeReusableChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")

  for i=1,WORK_SLOT_LAST do
    rescueWorkSlotReservedChest(i, "unloadToEnderChest")
    turtle.select(i)

    while turtle.getItemCount(i) > 0 do
      local item = turtle.getItemDetail(i)

      if item and isReservedEnderChestItemName(item.name) then
        rescueWorkSlotReservedChest(i, "unloadToEnderChest loop")
        item = turtle.getItemDetail(i)
        if item and isReservedEnderChestItemName(item.name) then
          log("Entlade-Ender-Chest ueberspringt reservierte Chest in Arbeitsslot "..i..": "..tostring(item.name))
          break
        end
      end

      if not item or isJunkItem(item.name) then
        turtle.drop()
        break
      end

      if not turtle.drop() then
        log("Entlade-Ender-Chest voll. Warte auf freien Platz.")
        minerAlert = "unload_chest_full"
        sendStatusWithReservedChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest", chestName, chestFingerprint, "unload_chest_full", false)
        pollAdminCommands(COMMAND_WAIT)
        sleep(10)
        chestName, chestFingerprint = placeReusableChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")
      end
    end
  end

  recoverReusableChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest", chestName, chestFingerprint)
  protectReservedChests("unloadToEnderChest done")
  clean()
end

refuelFromEnderChestFull = function()
  if fuel() >= fuelLimit() then return end

  clean()
  protectReservedChests("refuelFromEnderChestFull")

  if inventoryFull() then
    unloadToEnderChest()
  end

  local fueled, primaryGainedFuel = tryRefuelFromReusableChest(FUEL_CHEST_SLOT, "Fuel-Ender-Chest")

  if not fueled then
    log("Fuel-Ender-Chest in Slot "..FUEL_CHEST_SLOT.." liefert nach "..FUEL_CHEST_EMPTY_RETRIES.." Versuchen nicht genug Fuel. Teste andere Ender-Chest in Slot "..UNLOAD_CHEST_SLOT..".")
    minerAlert = "try_other_fuel_chest"
    sendStatus("try_other_fuel_chest", false)

    local alternateFueled = tryRefuelFromReusableChest(UNLOAD_CHEST_SLOT, "Alternative-Fuel-Ender-Chest")

    if alternateFueled then
      if not primaryGainedFuel then
        swapReservedChestSlots()
      end
    else
      minerAlert = "wrong_fuel_chest"
      sendStatus("wrong_fuel_chest", false)
      stop("Keine Ender-Chest liefert genug Fuel nach je "..FUEL_CHEST_EMPTY_RETRIES.." Versuchen. Pruefe Slot "..FUEL_CHEST_SLOT.." und Slot "..UNLOAD_CHEST_SLOT..".")
    end
  end

  minerAlert = nil
  log("Turtle-Fuel voll: "..fuel().." / "..fuelLimit())
end

function scannerFuel()
  if scanner.getFuelLevel then
    local ok, f = pcall(function() return scanner.getFuelLevel() end)
    if ok and type(f) == "number" then return f end
  end
  return nil
end

function scannerMaxFuel()
  if scanner.getMaxFuelLevel then
    local ok, f = pcall(function() return scanner.getMaxFuelLevel() end)
    if ok and type(f) == "number" then return f end
  end
  return nil
end

function scanCost(radius)
  local side = radius * 2 + 1
  return side * side * side
end

function bestRadiusByFuel()
  local sfuel = scannerFuel()

  if not sfuel then
    return math.min(MAX_SCAN_RADIUS, 8)
  end

  local best = MIN_SCAN_RADIUS

  for r=MIN_SCAN_RADIUS,MAX_SCAN_RADIUS do
    if scanCost(r) <= sfuel then
      best = r
    else
      break
    end
  end

  return best
end

function targetKey(tx,ty,tz)
  return tostring(tx)..","..tostring(ty)..","..tostring(tz)
end

function scan()
  while true do
    local sfuel = scannerFuel()
    local smax = scannerMaxFuel()
    local radius = bestRadiusByFuel()

    log("Scanner-Fuel: "..tostring(sfuel).." / "..tostring(smax))
    log("Scanner scannt Radius "..radius.." ...")

    local result, err

    if scanner.scanBlocks then
      result, err = scanner.scanBlocks(radius)
    elseif scanner.scan then
      result, err = scanner.scan(radius)
    else
      stop("Scanner hat weder scanBlocks() noch scan().")
    end

    if type(result) == "table" then
      log("Scan fertig. Eintraege: "..#result)
      return result
    end

    log("Scanner Fehler: "..tostring(err))
    sleep(SCAN_WAIT)
  end
end

function nearestOre()
  local blocks = scan()
  local best, bestDist = nil, 999999
  local oreCount = 0

  for _,b in ipairs(blocks) do
    if b.name and isOre(b.name) then
      local tx = x + b.x
      local ty = y + b.y
      local tz = z + b.z
      local key = targetKey(tx,ty,tz)

      if not skippedTargets[key] and inMineArea(tx, tz) then
        oreCount = oreCount + 1

        local d = math.abs(b.x) + math.abs(b.y) + math.abs(b.z)

        if d < bestDist and d > 0 then
          best = b
          bestDist = d
        end
      end
    end
  end

  log("Ores im Scan: "..oreCount)

  if best then
    log("Naechstes Ore: "..best.name.." dx="..best.x.." dy="..best.y.." dz="..best.z)
  end

  return best
end

function recoveryFuelAvailable()
  local f = turtle.getFuelLevel()
  return f == "unlimited" or (type(f) == "number" and f > 0)
end

function recoveryDigCanFail(inspectFn, detectFn, digFn, attackFn, label)
  local tries = 0

  while detectFn() do
    local hasBlock, data = inspectFn()

    if hasBlock and data and isProtectedBlock(data.name) then
      log("Recovery: Geschuetzter Block "..label.." erkannt, wird nicht abgebaut: "..data.name)
      return false
    end

    if digFn() then
      tries = 0
    else
      tries = tries + 1
      if attackFn then attackFn() end

      if tries >= 8 then
        local stillBlocked, blockedData = inspectFn()
        if stillBlocked and blockedData then
          log("Recovery: Block "..label.." nicht abbaubar: "..blockedData.name)
        end
        return false
      end
    end

    sleep(0.05)
  end

  return true
end

function recoveryForwardDirect(entityAvoid)
  if not recoveryFuelAvailable() then
    log("Recovery: Kein Fuel fuer Vorwaertsbewegung.")
    return false
  end

  if not recoveryDigCanFail(turtle.inspect, turtle.detect, turtle.dig, turtle.attack, "vorne") then
    return false
  end

  local tries = 0

  while not turtle.forward() do
    if turtle.detect() then
      turtle.attack()

      if not recoveryDigCanFail(turtle.inspect, turtle.detect, turtle.dig, turtle.attack, "vorne") then
        return false
      end
    else
      if entityAvoid then
        sleep(math.random(2, 8) / 10)
        turtle.attack()
      else
        sleep(math.random(2, 8) / 10)
      end
    end

    tries = tries + 1
    if tries >= 12 then return false end
    sleep(0.1)
  end

  updateForwardPosition()
  save()
  return true
end

function recoveryForward(entityAvoid)
  if recoveryForwardDirect(entityAvoid) then
    return true
  end

  log("Recovery: Vorwaerts blockiert. Weiche nach oben aus.")

  if not recoveryUp() then
    return false
  end

  return recoveryForwardDirect(entityAvoid)
end

function recoveryUp()
  if not recoveryFuelAvailable() then
    log("Recovery: Kein Fuel fuer Aufwaertsbewegung.")
    return false
  end

  if not recoveryDigCanFail(turtle.inspectUp, turtle.detectUp, turtle.digUp, turtle.attackUp, "oben") then
    return false
  end

  local tries = 0

  while not turtle.up() do
    if turtle.detectUp() then
      turtle.attackUp()

      if not recoveryDigCanFail(turtle.inspectUp, turtle.detectUp, turtle.digUp, turtle.attackUp, "oben") then
        return false
      end
    else
      turtle.attackUp()
      sleep(math.random(2, 8) / 10)
    end

    tries = tries + 1
    if tries >= 20 then return false end
    sleep(0.05)
  end

  y = y + 1
  save()
  return true
end

function recoveryDown()
  if not recoveryFuelAvailable() then
    log("Recovery: Kein Fuel fuer Abwaertsbewegung.")
    return false
  end

  if not recoveryDigCanFail(turtle.inspectDown, turtle.detectDown, turtle.digDown, turtle.attackDown, "unten") then
    return false
  end

  local tries = 0

  while not turtle.down() do
    if turtle.detectDown() then
      turtle.attackDown()

      if not recoveryDigCanFail(turtle.inspectDown, turtle.detectDown, turtle.digDown, turtle.attackDown, "unten") then
        return false
      end
    else
      turtle.attackDown()
      sleep(math.random(2, 8) / 10)
    end

    tries = tries + 1
    if tries >= 20 then return false end
    sleep(0.05)
  end

  y = y - 1
  save()
  return true
end

function goHorizontal(tx, tz, allowOutside, allowAboveTarget)
  if y > targetY and not allowAboveTarget then
    log("Seitliche Bewegung ueber Ziel-Y verhindert. Fahre zuerst runter zu Ziel-Y.")

    if not descendToTargetWithSidestep() then
      stop("Seitliche Bewegung ueber Ziel-Y blockiert.")
    end
  end

  if not allowOutside then
    tx, tz = nearestPointInMineArea(tx, tz)
  end

  local function travelAxis(target, isX)
    local function travelStep(remaining)
      if recoveryTravelMode then
        return recoveryForward(true)
      end

      if allowAboveTarget then
        return rawForward(true, true)
      end

      return forwardTravel(remaining)
    end

    if isX then
      if x < target then
        face(1)
        while x < target do
          local remaining = target - x
          if recoveryTravelMode then
            debugLog("REC E r="..tostring(remaining).." p="..tostring(x)..","..tostring(y)..","..tostring(z).." f="..tostring(fuel()))
            sleep(0.2)
          end
          if not travelStep(remaining) then return false, "Weg nach Osten blockiert." end
          if recoveryTravelMode then
            debugLog("REC E ok p="..tostring(x)..","..tostring(y)..","..tostring(z))
            sleep(0.2)
          end
          clean()
        end
      elseif x > target then
        face(3)
        while x > target do
          local remaining = x - target
          if recoveryTravelMode then
            debugLog("REC W r="..tostring(remaining).." p="..tostring(x)..","..tostring(y)..","..tostring(z).." f="..tostring(fuel()))
            sleep(0.2)
          end
          if not travelStep(remaining) then return false, "Weg nach Westen blockiert." end
          if recoveryTravelMode then
            debugLog("REC W ok p="..tostring(x)..","..tostring(y)..","..tostring(z))
            sleep(0.2)
          end
          clean()
        end
      end
    else
      if z < target then
        face(2)
        while z < target do
          local remaining = target - z
          if recoveryTravelMode then
            debugLog("REC S r="..tostring(remaining).." p="..tostring(x)..","..tostring(y)..","..tostring(z).." f="..tostring(fuel()))
            sleep(0.2)
          end
          if not travelStep(remaining) then return false, "Weg nach Sueden blockiert." end
          if recoveryTravelMode then
            debugLog("REC S ok p="..tostring(x)..","..tostring(y)..","..tostring(z))
            sleep(0.2)
          end
          clean()
        end
      elseif z > target then
        face(0)
        while z > target do
          local remaining = z - target
          if recoveryTravelMode then
            debugLog("REC N r="..tostring(remaining).." p="..tostring(x)..","..tostring(y)..","..tostring(z).." f="..tostring(fuel()))
            sleep(0.2)
          end
          if not travelStep(remaining) then return false, "Weg nach Norden blockiert." end
          if recoveryTravelMode then
            debugLog("REC N ok p="..tostring(x)..","..tostring(y)..","..tostring(z))
            sleep(0.2)
          end
          clean()
        end
      end
    end

    return true
  end

  local function travelDirect(targetX, targetZ, firstAxisIsX)
    local ok, err

    if firstAxisIsX then
      ok, err = travelAxis(targetX, true)
      if not ok then return false, err end
      return travelAxis(targetZ, false)
    end

    ok, err = travelAxis(targetZ, false)
    if not ok then return false, err end
    return travelAxis(targetX, true)
  end

  local function travelWithFallback(targetX, targetZ)
    local startX, startZ = x, z
    local firstAxisIsX = math.abs(targetX - x) >= math.abs(targetZ - z)
    local ok, err = travelDirect(targetX, targetZ, firstAxisIsX)

    if ok then return true end

    if x ~= startX or z ~= startZ then
      return false, err
    end

    log(tostring(err).." Versuche andere Achse zuerst.")
    return travelDirect(targetX, targetZ, not firstAxisIsX)
  end

  local function travelOrStop(targetX, targetZ)
    local ok, err = travelWithFallback(targetX, targetZ)
    if not ok then stop(err or "Horizontaler Weg blockiert.") end
  end

  if not allowOutside and not inMineArea(x, z) then
    local safeX, safeZ = nearestPointInMineArea(x, z)

    if x ~= safeX or z ~= safeZ then
      log("Ausserhalb Mining-Bereich. Fahre zuerst zurueck nach x="..safeX.." z="..safeZ)
      travelOrStop(safeX, safeZ)
    end
  end

  travelOrStop(tx, tz)
end

function goTo(tx, ty, tz)
  log("Gehe zu x="..tx.." y="..ty.." z="..tz.." von x="..x.." y="..y.." z="..z)

  if not descendToTargetWithSidestep() then
    stop("Abstieg zu Ziel-Y vor Reise blockiert.")
  end

  goHorizontal(tx, tz)

  while y < ty do
    up()
    clean()
  end

  while y > ty do
    down()
    clean()
  end

  log("Ziel erreicht: x="..x.." y="..y.." z="..z)
end

function recoveryTargetForMiner()
  if not recoveryX or not recoveryY or not recoveryZ then
    return nil
  end

  local travelY = tonumber(recoveryY)
  if travelY then
    travelY = math.floor(travelY + 0.5)
  else
    travelY = recoveryY
  end

  local radius = math.max(1, tonumber(recoveryRadius) or 6)
  local side = radius * 2 + 1
  local capacity = side * side
  local id = computerId() or os.getComputerID and os.getComputerID() or 0
  local index = id % capacity
  local dx = (index % side) - radius
  local dz = (math.floor(index / side) % side) - radius

  return recoveryX + dx, travelY, recoveryZ + dz, dx, dz
end

goToRecoveryIfConfigured = function(reason, missingSlot)
  local tx, ty, tz, dx, dz = recoveryTargetForMiner()

  if not tx then
    debugLog("REC no coords rx="..tostring(recoveryX).." ry="..tostring(recoveryY).." rz="..tostring(recoveryZ).." state="..tostring(fs.exists(STATE)))
    return false
  end

  local id = computerId() or 0
  local delay = (id % 20) * 0.5

  minerState = "recovery"
  minerAlert = "recovery_missing_chest"
  sendStatus("recovery_missing_chest", false)
  local function recoveryLog(msg)
    debugLog("REC "..tostring(msg).." p="..tostring(x)..","..tostring(y)..","..tostring(z).." h="..tostring(heading).." f="..tostring(fuel()))
  end

  recoveryLog("start slot="..tostring(missingSlot).." ziel="..tostring(tx)..","..tostring(ty)..","..tostring(tz).." off="..tostring(dx)..","..tostring(dz).." grund="..tostring(reason))
  debugLog("REC wait "..tostring(delay).."s")
  sleep(delay)

  recoveryTravelMode = true
  save()
  sleep(0.5)

  recoveryLog("horiz ->"..tostring(tx)..","..tostring(tz))
  sendStatus("recovery_travel", false)
  sleep(0.5)
  goHorizontal(tx, tz, true, true)

  while y < ty do
    recoveryLog("up ->"..tostring(ty))
    sleep(0.25)
    if not recoveryUp() then
      error("Recovery-Aufstieg blockiert.")
    end
    clean()
    recoveryLog("up ok")
    sleep(0.25)
  end

  while y > ty do
    recoveryLog("down ->"..tostring(ty))
    sleep(0.25)
    if not recoveryDown() then
      error("Recovery-Abstieg blockiert.")
    end
    clean()
    recoveryLog("down ok")
    sleep(0.25)
  end

  recoveryTravelMode = false

  save()
  recoveryLog("arrived slot="..tostring(missingSlot))

  while true do
    minerState = "recovery_wait"
    minerAlert = "recovery_arrived"
    sendStatus("recovery_arrived", false)
    recoveryLog("wait admin/check chests")

    local ready = reservedChestsReady()
    if ready then
      minerAlert = nil
      minerState = "recovery_resume"
      sendStatus("recovery_resume", false)
      recoveryLog("chests ready, resume mining")

      recoveryTravelMode = true
      goHorizontal(mineCenterX, mineCenterZ, true, true)
      recoveryTravelMode = false
      save()

      if miningLoop then
        miningLoop()
      end

      return true
    end

    pollAdminCommands(COMMAND_WAIT)
    sleep(5)
  end
end

fatalRecoveryHandler = function(reason, missingSlot)
  if inFatalRecovery then
    debugLog("REC fatal skip nested")
    return false
  end

  if not goToRecoveryIfConfigured then
    debugLog("REC fatal no handler")
    return false
  end

  inFatalRecovery = true
  debugLog("REC fatal start: "..tostring(reason))
  local ok, recovered = pcall(goToRecoveryIfConfigured, reason, missingSlot)

  if ok and recovered ~= false then
    return true
  end

  recoveryTravelMode = false
  inFatalRecovery = false

  if not ok then
    debugLog("REC fatal fail: "..tostring(recovered))
  else
    debugLog("REC fatal false")
  end

  return false
end

unload = nil
mineAdjacentOres = nil

function returnFuelNeeded()
  local needed = 0
  local tempY = y

  if tempY > targetY then
    needed = needed + (tempY - targetY)
    tempY = targetY
  end

  needed = needed + math.abs(x - homeX) + math.abs(z - homeZ)
  needed = needed + math.abs(topY - tempY)

  return needed + RETURN_FUEL_BUFFER
end

function ensureCanReturn()
  local needed = returnFuelNeeded()

  if fuel() < needed and not (x==homeX and z==homeZ and y==topY) then
    log("Fuel wird knapp. Fuel="..fuel().." benoetigt~"..needed)
    sendAlert("low_return_fuel", "low_return_fuel")
    unload()
    clearAlert("low_return_fuel")
  end
end

function mineFrontOreAndEnter()
  local ok, data = turtle.inspect()

  if not ok or not data or not isOre(data.name) then
    log("Vor mir ist kein Ore mehr.")
    return false
  end

  log("Ziel-Ore vorne bestaetigt: "..data.name)

  if not digFrontCanFail() then
    return false
  end

  if not rawForward(false) then
    return false
  end

  printValuables()
  mineAdjacentOres()
  return true
end

function mineUpOreAndEnter()
  local ok, data = turtle.inspectUp()

  if not ok or not data or not isOre(data.name) then
    log("Oben ist kein Ore mehr.")
    return false
  end

  log("Ziel-Ore oben bestaetigt: "..data.name)

  if not digUpCanFail() then return false end
  if not tryUpWithBypass() then return false end

  printValuables()
  mineAdjacentOres()
  return true
end

function mineDownOreAndEnter()
  local ok, data = turtle.inspectDown()

  if not ok or not data or not isOre(data.name) then
    log("Unten ist kein Ore mehr.")
    return false
  end

  log("Ziel-Ore unten bestaetigt: "..data.name)

  if not digDownCanFail() then return false end
  if not rawDown() then return false end

  printValuables()
  mineAdjacentOres()
  return true
end

function mineScannedOre(ore)
  local tx = x + ore.x
  local ty = y + ore.y
  local tz = z + ore.z
  local key = targetKey(tx,ty,tz)

  log("Gezieltes Ore-Mining: "..ore.name.." bei x="..tx.." y="..ty.." z="..tz)

  local success = false

  if ty > targetY then
    if inMineArea(tx, tz) then
      goTo(tx, ty - 1, tz)
      success = mineUpOreAndEnter()
    end
  elseif ty < targetY then
    if inMineArea(tx, tz) then
      goTo(tx, ty + 1, tz)
      success = mineDownOreAndEnter()
    end
  else
    if ore.x > 0 then
      if inMineArea(tx - 1, tz) then
        goTo(tx - 1, ty, tz)
        face(1)
        success = mineFrontOreAndEnter()
      end
    elseif ore.x < 0 then
      if inMineArea(tx + 1, tz) then
        goTo(tx + 1, ty, tz)
        face(3)
        success = mineFrontOreAndEnter()
      end
    elseif ore.z > 0 then
      if inMineArea(tx, tz - 1) then
        goTo(tx, ty, tz - 1)
        face(2)
        success = mineFrontOreAndEnter()
      end
    elseif ore.z < 0 then
      if inMineArea(tx, tz + 1) then
        goTo(tx, ty, tz + 1)
        face(0)
        success = mineFrontOreAndEnter()
      end
    else
      log("Ore-Koordinate ist eigene Position. Ueberspringe.")
      success = false
    end
  end

  if not success then
    log("Ore konnte an Zielposition nicht bestaetigt werden. Ziel wird uebersprungen.")
    skippedTargets[key] = true
  end
end

unload = function()
  minerState = "unloading"
  log("Entladen/Tanken gestartet.")
  unloadToEnderChest()
  minerState = "refueling"
  refuelFromEnderChestFull()
  minerState = "mining"
  sendStatus("unloaded", false)
  log("Entladen/Tanken fertig.")
  save()
end

mineAdjacentOres = function()
  if veinSteps >= MAX_VEIN_STEPS then
    log("Vein-Limit erreicht.")
    return
  end

  veinSteps = veinSteps + 1

  ensureCanReturn()

  if inventoryFull() then unload() end

  clean()

  local startHeading = heading

  local okU, dataU = turtle.inspectUp()
  if okU and isOre(dataU.name) then
    log("Vein-Ore oben gefunden: "..dataU.name)

    if mineUpOreAndEnter() then
      rawDown()
    end
  end

  face(startHeading)

  local okD, dataD = turtle.inspectDown()
  if okD and isOre(dataD.name) then
    log("Vein-Ore unten gefunden: "..dataD.name)

    if mineDownOreAndEnter() then
      tryUpWithBypass()
    end
  end

  face(startHeading)

  if y <= targetY then
    for i=1,4 do
      local okF, dataF = turtle.inspect()

      if okF and isOre(dataF.name) then
        log("Vein-Ore vorne gefunden: "..dataF.name)
        forwardStrict()
        printValuables()
        mineAdjacentOres()
        moveBackStrict()
      end

      turnRight()
    end
  end

  face(startHeading)
end

function descendToTarget()
  if x == homeX and z == homeZ and y > targetY then
    log("Fahre runter von Y "..y.." zu Ziel-Y "..targetY)

    if not descendToTargetWithSidestep() then
      stop("Abstieg zu Ziel-Y blockiert.")
    end

    log("Aktuelle Y: "..y.." / Ziel-Y: "..targetY)
    log("Zielhoehe erreicht.")
  elseif y == targetY then
    log("Bin bereits auf Ziel-Y.")
  elseif y < targetY then
    log("Turtle ist unter Ziel-Y. Fahre hoch.")

    while y < targetY do
      up()
      clean()
      log("Aktuelle Y: "..y.." / Ziel-Y: "..targetY)
    end
  else
    log("Resume-Position wird genutzt.")
  end
end

function alignToTargetY()
  if not descendToTargetWithSidestep() then
    stop("Abstieg zu Ziel-Y blockiert.")
  end

  while y < targetY do
    up()
    clean()
  end
end

function tooFarFromShaft()
  return not inMineArea(x, z)
end

function randomMineTarget()
  if mineMinX then
    return math.random(mineMinX, mineMaxX), math.random(mineMinZ, mineMaxZ)
  end

  return math.random(mineCenterX - MAX_DISTANCE_FROM_SHAFT, mineCenterX + MAX_DISTANCE_FROM_SHAFT),
    math.random(mineCenterZ - MAX_DISTANCE_FROM_SHAFT, mineCenterZ + MAX_DISTANCE_FROM_SHAFT)
end

function chooseNewExplorationCenter()
  local tx, tz = randomMineTarget()
  tx, tz = clampToMineArea(tx, tz)

  if mineMinX then
    mineCenterX = tx
    mineCenterZ = tz
    save()
    log("Neues Suchzentrum im Mining-Bereich: x="..mineCenterX.." z="..mineCenterZ)
  else
    log("Neues Suchziel um Mining-Center: x="..tx.." z="..tz)
  end

  return tx, tz
end

function randomSpin()
  local turns = math.random(0, 7)

  for _=1,turns do
    if math.random(0, 1) == 0 then
      turnRight()
    else
      turnRight()
      turnRight()
      turnRight()
    end
  end
end

function travelRandomMoveAxis(target, isX)
  local delta
  local headingToFace

  if isX then
    delta = target - x
    headingToFace = delta > 0 and 1 or 3
  else
    delta = target - z
    headingToFace = delta > 0 and 2 or 0
  end

  local steps = math.abs(delta)
  if steps == 0 then return 0, false end

  face(headingToFace)

  local moved = 0

  while moved < steps do
    ensureCanReturn()

    local remaining = steps - moved

    if not forwardTravel(remaining) then
      log("Random-Ziel blockiert nach "..moved.." Bloecken.")
      return moved, true
    end

    moved = moved + 1
    clean()
  end

  return moved, false
end

function travelRandomMoveTarget(tx, tz, firstAxisIsX)
  local movedTotal = 0
  local moved

  if firstAxisIsX then
    moved = travelRandomMoveAxis(tx, true)
    movedTotal = movedTotal + moved

    if z ~= tz then
      moved = travelRandomMoveAxis(tz, false)
      movedTotal = movedTotal + moved
    end
  else
    moved = travelRandomMoveAxis(tz, false)
    movedTotal = movedTotal + moved

    if x ~= tx then
      moved = travelRandomMoveAxis(tx, true)
      movedTotal = movedTotal + moved
    end
  end

  return movedTotal
end

function randomMove()
  ensureCanReturn()

  if not descendToTargetWithSidestep() then
    stop("Abstieg zu Ziel-Y vor Random Move blockiert.")
  end

  if tooFarFromShaft() then
    log("Zu weit vom Mining-Center entfernt. Kehre zum Mining-Center zurueck.")
    goHorizontal(mineCenterX,mineCenterZ)
    return
  end

  randomSpin()

  for _=1,8 do
    local tx, tz = chooseNewExplorationCenter()
    if tx ~= x or tz ~= z then
      log("Keine Ores gefunden. Bewege zum neuen Suchzentrum: x="..tx.." y="..targetY.." z="..tz)

      local firstAxisIsX = math.random(0, 1) == 0
      local moved = travelRandomMoveTarget(tx, tz, firstAxisIsX)

      if moved > 0 then
        randomSpin()
        log("Random Move fertig. Position: x="..x.." y="..y.." z="..z)
        return
      end
    end
  end

  log("Keine passende Random-Richtung gefunden. Gehe zum Mining-Center.")
  goHorizontal(mineCenterX,mineCenterZ)
end

function isRecoverableMiningError(err)
  local text = tostring(err or "")

  return string.find(text, "blockiert", 1, true) ~= nil
    or string.find(text, "Abstieg zu Ziel-Y", 1, true) ~= nil
    or string.find(text, "Ausweich", 1, true) ~= nil
    or string.find(text, "Kann nicht nach oben fahren", 1, true) ~= nil
    or string.find(text, "Kann nicht nach unten fahren", 1, true) ~= nil
    or string.find(text, "Kann nicht streng nach vorne fahren", 1, true) ~= nil
    or string.find(text, "Kann nicht zurueck fahren", 1, true) ~= nil
end

function miningLoopStep()
  sendMinuteStatusIfDue()
  clean()
  ensureCanReturn()

  if pendingUnload then
    pendingUnload = false
    unload()
  end

  if pendingRefuel then
    pendingRefuel = false
    refuelFromEnderChestFull()
  end

  alignToTargetY()

  if inventoryFull() then unload() end

  local ore = nearestOre()

  if not ore then
    log("Keine Ores gefunden. Bewege mich zufaellig weiter.")
    skippedTargets = {}
    randomMove()
    sleep(1)
  else
    veinSteps = 0
    mineScannedOre(ore)
    clean()
    save()

    log("Ores abgebaut seit Start: "..oreMinedCount)
    printValuables()
  end
end

function miningLoop()
  minerState = "mining"
  log("Mining-Loop startet.")

  while true do
    local ok, err = pcall(miningLoopStep)

    if not ok then
      debugLog("ERR mining: "..tostring(err))

      if not isRecoverableMiningError(err) then
        if fatalRecoveryHandler and fatalRecoveryHandler("Mining-Crash: "..tostring(err), nil) then
          return
        end

        debugLog("Mining fatal throw: "..tostring(err))
        error(err)
      end

      log("ERR recoverable")
      log("Suche neues Zentrum")
      skippedTargets = {}
      chooseNewExplorationCenter()
      sleep(1)
    end
  end
end

function main()
  ensureStartupVersion()
  if fs.exists(STATE) then
    fs.delete(STATE)
    log("Alter Miner-State geloescht: "..STATE)
  end
  loadOrSetupState()
  log("Gestartet.")
  log("Position: x="..x.." y="..y.." z="..z.." heading="..heading)
  log("Top-Y: "..tostring(topY))
  log("Ziel-Y: "..tostring(targetY))
  log("Mining-Modus: "..tostring(miningMode))
  log("Turtle-Fuel: "..fuel().." / "..fuelLimit())
  locateGps(false)
  requireReservedChest(MODEM_SLOT, "Ender-Modem-Modul")
  requireReservedChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")
  requireReservedChest(FUEL_CHEST_SLOT, "Fuel-Ender-Chest")
  waitForAdminStart()
  calibrateTopFromRedstone("Start")

  descendToTarget()
  goHorizontal(mineCenterX, mineCenterZ)
  miningLoop()
end

debugLog("BOOT miner.lua state="..tostring(STATE).." debug="..tostring(DEBUG_LOG))
ok, err = pcall(main)

if not ok then
  if fatalRecoveryHandler and fatalRecoveryHandler("Main-Crash: "..tostring(err), nil) then
    return
  end

  debugLog("Main fatal throw: "..tostring(err))
  error(err)
end
