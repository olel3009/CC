-- Drone Builder Turtle
-- Baut neue Miner-Turtles aus Material in einer Kiste hinter der Builder-Turtle.
--
-- Erwartung:
-- - Kiste direkt HINTER der Builder-Turtle.
-- - Vorne ist Platz fuer die neue Turtle.
-- - Rechts ist Platz, damit der Builder nach jeder Drone eine Position weitergehen kann.
-- - Die Kiste enthaelt pro Drone:
--   * 1 Turtle
--   * 1 Geo/Ore Scanner
--   * 1 Pickaxe Upgrade
--   * 1 Wireless/Ender Modem
--   * 2 Ender-Chests
--   * mindestens 14 gleiche, stapelbare Dummy-Items als Slot-Blocker
--
-- Ziel-Inventar der neuen Drone:
-- - Slot 15: Entlade-Ender-Chest
-- - Slot 16: Fuel-Ender-Chest, automatisch erkannt durch kurzen Fuel-Test
-- - Scanner/Pickaxe/Modem landen in freien Slots; miner.lua sortiert/equipped sie beim Start.

local BLOCKER_COUNT = 14
local args = { ... }

local function log(msg)
  print("[DroneBuilder] "..msg)
end

local function lowerText(value)
  return string.lower(tostring(value or ""))
end

local function itemText(detail)
  if not detail then return "" end

  local parts = { detail.name or "" }

  if detail.displayName then
    table.insert(parts, detail.displayName)
  end

  if detail.nbt then
    table.insert(parts, tostring(detail.nbt))
  end

  return lowerText(table.concat(parts, " "))
end

local function item(slot)
  return turtle.getItemDetail(slot, true)
end

local function isTurtleItem(detail)
  local text = itemText(detail)
  return string.find(text, "turtle", 1, true) ~= nil
end

local function isScannerItem(detail)
  local text = itemText(detail)
  return (string.find(text, "geo", 1, true) ~= nil or string.find(text, "ore", 1, true) ~= nil)
    and string.find(text, "scanner", 1, true) ~= nil
end

local function isPickaxeItem(detail)
  return string.find(itemText(detail), "pickaxe", 1, true) ~= nil
end

local function isModemItem(detail)
  return string.find(itemText(detail), "modem", 1, true) ~= nil
end

local function isEnderStorageItem(detail)
  local text = itemText(detail)
  return string.find(text, "ender", 1, true) ~= nil
    and (string.find(text, "chest", 1, true) ~= nil or string.find(text, "storage", 1, true) ~= nil)
end

local function isSpecialItem(detail)
  return isTurtleItem(detail)
    or isScannerItem(detail)
    or isPickaxeItem(detail)
    or isModemItem(detail)
    or isEnderStorageItem(detail)
end

local function findSlot(testFn, ignoreSlot)
  for slot=1,16 do
    if slot ~= ignoreSlot then
      local detail = item(slot)

      if detail and testFn(detail, slot) then
        return slot, detail
      end
    end
  end

  return nil, nil
end

local function findEmptySlot(ignoreSlot)
  for slot=1,16 do
    if slot ~= ignoreSlot and turtle.getItemCount(slot) == 0 then
      return slot
    end
  end

  return nil
end

local function findBlockerSlotFixed()
  for slot=1,16 do
    local detail = item(slot)
    if detail and not isSpecialItem(detail) and turtle.getItemCount(slot) >= BLOCKER_COUNT then
      return slot, detail
    end
  end

  return nil, nil
end

local function findEnderChestSlots()
  local slots = {}

  for slot=1,16 do
    local detail = item(slot)

    if detail and isEnderStorageItem(detail) then
      table.insert(slots, slot)
    end
  end

  return slots
end

local function countEnderChests()
  local total = 0

  for slot=1,16 do
    local detail = item(slot)
    if detail and isEnderStorageItem(detail) then
      total = total + turtle.getItemCount(slot)
    end
  end

  return total
end

local function hasRequirements()
  local turtleSlot = findSlot(isTurtleItem)
  local scannerSlot = findSlot(isScannerItem)
  local pickaxeSlot = findSlot(isPickaxeItem)
  local modemSlot = findSlot(isModemItem)
  local blockerSlot = findBlockerSlotFixed()

  return turtleSlot and scannerSlot and pickaxeSlot and modemSlot and countEnderChests() >= 2 and blockerSlot
end

local function faceSupply()
  turtle.turnRight()
  turtle.turnRight()
end

local function faceBuild()
  turtle.turnRight()
  turtle.turnRight()
end

local function pullOneFromSupply()
  faceSupply()
  local ok = turtle.suck(1)
  faceBuild()
  return ok
end

local function ensureRequirements(droneIndex)
  local pulls = 0

  while not hasRequirements() do
    if not pullOneFromSupply() then
      error("Kiste hinten hat nicht genug Material fuer Drone #"..droneIndex..".")
    end

    pulls = pulls + 1

    if pulls > 512 then
      error("Zu viele Items gezogen, aber Requirements fehlen weiter. Pruefe Item-Namen und Kisteninhalt.")
    end

    local empty = false
    for slot=1,16 do
      if turtle.getItemCount(slot) == 0 then
        empty = true
        break
      end
    end

    if not empty and not hasRequirements() then
      error("Builder-Inventar voll, aber Requirements fehlen. Lege nur Drone-Material und Dummy-Blocker in die Kiste.")
    end
  end
end

local function selectSlot(slot, label)
  if not slot then
    error(label.." fehlt.")
  end

  turtle.select(slot)
end

local function dropFront(slot, count, label)
  selectSlot(slot, label)

  if not turtle.drop(count) then
    error(label.." konnte nicht in die neue Drone gelegt werden.")
  end
end

local function snapshotInventory()
  local snapshot = {}

  for slot=1,16 do
    local detail = item(slot)

    snapshot[slot] = {
      name=detail and detail.name or nil,
      count=turtle.getItemCount(slot)
    }
  end

  return snapshot
end

local function findChangedSlot(snapshot)
  for slot=1,16 do
    local detail = item(slot)
    local before = snapshot[slot]
    local count = turtle.getItemCount(slot)

    if detail and count > (before.count or 0) then
      if before.name == nil or before.name == detail.name then
        return slot
      end
    end
  end

  return nil
end

local function isFuelSlot(slot)
  if not slot or turtle.getItemCount(slot) == 0 then
    return false
  end

  turtle.select(slot)
  return turtle.refuel(0) == true
end

local function isolateOneChest(slot)
  if turtle.getItemCount(slot) <= 1 then
    return slot
  end

  local spareSlot = findEmptySlot(slot)

  if not spareSlot then
    error("Fuel-Test braucht einen freien Slot, um gestapelte Ender-Chests kurz zu trennen.")
  end

  turtle.select(slot)

  if not turtle.transferTo(spareSlot, turtle.getItemCount(slot) - 1) then
    error("Ender-Chest-Stack konnte fuer Fuel-Test nicht getrennt werden.")
  end

  return slot
end

local function testChestHasFuel(slot)
  slot = isolateOneChest(slot)
  turtle.select(slot)

  if not turtle.place() then
    error("Ender-Chest konnte fuer Fuel-Test vorne nicht platziert werden. Ist der Platz frei?")
  end

  local snapshot = snapshotInventory()
  local gotItem = turtle.suck(1)
  local sampleSlot = nil
  local hasFuel = false

  if gotItem then
    sampleSlot = findChangedSlot(snapshot)
    hasFuel = isFuelSlot(sampleSlot)

    if sampleSlot then
      turtle.select(sampleSlot)
      turtle.drop(1)
    end
  end

  turtle.select(slot)

  if not turtle.dig() then
    error("Getestete Ender-Chest konnte nicht wieder abgebaut werden.")
  end

  return hasFuel
end

local function chooseEnderChestSlots()
  local fuelSlot = nil
  local unloadSlot = nil

  while countEnderChests() >= 2 do
    local slots = findEnderChestSlots()

    if #slots == 0 then break end

    for _,slot in ipairs(slots) do
      if testChestHasFuel(slot) then
        fuelSlot = slot
        break
      end

      if not unloadSlot then
        unloadSlot = slot
      end
    end

    break
  end

  if not fuelSlot then
    error("Keine Fuel-Ender-Chest erkannt. Die Fuel-Chest muss beim Test mindestens ein Fuel-Item liefern.")
  end

  if not unloadSlot or unloadSlot == fuelSlot then
    local slots = findEnderChestSlots()

    for _,slot in ipairs(slots) do
      if slot ~= fuelSlot then
        unloadSlot = slot
        break
      end
    end
  end

  if not unloadSlot then
    error("Keine zweite Ender-Chest fuer Slot 15 gefunden.")
  end

  log("Fuel-Chest erkannt in Builder-Slot "..fuelSlot.."; Entlade-Chest in Slot "..unloadSlot..".")
  return unloadSlot, fuelSlot
end

local function loadNewDrone()
  local turtleSlot = findSlot(isTurtleItem)
  local scannerSlot = findSlot(isScannerItem)
  local pickaxeSlot = findSlot(isPickaxeItem)
  local modemSlot = findSlot(isModemItem)
  local blockerSlot = findBlockerSlotFixed()

  if countEnderChests() < 2 then
    error("Es werden 2 Ender-Chests pro Drone gebraucht.")
  end

  local unloadSlot, fuelSlot = chooseEnderChestSlots()

  selectSlot(turtleSlot, "Turtle")
  if not turtle.place() then
    error("Neue Turtle konnte vorne nicht platziert werden. Ist der Platz frei?")
  end

  dropFront(blockerSlot, BLOCKER_COUNT, "Slot-Blocker")
  dropFront(unloadSlot, 1, "Entlade-Ender-Chest fuer Slot 15")
  dropFront(fuelSlot, 1, "Fuel-Ender-Chest fuer Slot 16")

  if not turtle.suck(BLOCKER_COUNT) then
    error("Slot-Blocker konnten nicht aus der neuen Drone zurueckgezogen werden.")
  end

  scannerSlot = findSlot(isScannerItem)
  pickaxeSlot = findSlot(isPickaxeItem)
  modemSlot = findSlot(isModemItem)

  dropFront(scannerSlot, 1, "Geo/Ore Scanner")
  dropFront(pickaxeSlot, 1, "Pickaxe Upgrade")
  dropFront(modemSlot, 1, "Wireless/Ender Modem")
end

local function moveToNextBuildSpot()
  turtle.turnRight()

  if not turtle.forward() then
    error("Kann nicht nach rechts zum naechsten Bauplatz fahren.")
  end

  turtle.turnLeft()
end

local function askCount()
  local arg = args[1]

  if arg then
    local n = tonumber(arg)
    if n and n > 0 then return math.floor(n) end
  end

  write("Wie viele Dronen bauen? ")
  local n = tonumber(read())

  if not n or n < 1 then
    error("Ungueltige Anzahl.")
  end

  return math.floor(n)
end

local count = askCount()

log("Baue "..count.." Dronen.")
log("Kiste muss hinter mir sein; Bauplaetze vorne und rechts frei halten.")

for i=1,count do
  log("Drone #"..i.." vorbereiten.")
  ensureRequirements(i)
  loadNewDrone()
  log("Drone #"..i.." fertig.")

  if i < count then
    moveToNextBuildSpot()
  end
end

log("Fertig.")
