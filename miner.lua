-- startup.lua
-- Auto Ore Miner v19
-- Fix: Scanner-Koordinaten werden als Minecraft-Weltachsen behandelt.
-- Setup erkennt die Startausrichtung nach Moeglichkeit automatisch ueber die Fuel-Kiste.
-- Fallback ist fest konfiguriert: aktuelle Y 63, Facing north, tiefste Ziel-Y -50.
-- Fuel-Kiste VOR der Turtle, Lager-Kiste HINTER der Turtle.
-- Turtle schaut beim Start zur Fuel-Kiste.

local STATE = "miner_state"
local STATE_VERSION = 19

local MAX_SCAN_RADIUS = 15
local MIN_SCAN_RADIUS = 4

local LOW_FUEL_STOP = 20
local RETURN_FUEL_BUFFER = 120
local SCAN_WAIT = 3
local MAX_VEIN_STEPS = 128

local RANDOM_MOVE_MIN = 6
local RANDOM_MOVE_MAX = 18
local MIN_START_DEPTH_BELOW_TOP = 20
local MAX_DISTANCE_FROM_SHAFT = 70
local STATUS_INTERVAL = 15
local COMMAND_WAIT = 5
local ADMIN_PROTOCOL = "miner_admin"
local MODEM_SLOT = 13
local UNLOAD_CHEST_SLOT = 15
local FUEL_CHEST_SLOT = 16
local WORK_SLOT_LAST = 12

local CONFIG_TOP_Y = 63
local CONFIG_LOWEST_Y = -50
local CONFIG_NETHERITE_TARGET_Y = 15
local CONFIG_HEADING = 0

local JUNK = {
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

local TARGET_ORES = {
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
  ["ae2:sky_stone_chest"]=true
}

local NETHERITE_TARGETS = {
  ["minecraft:ancient_debris"]=true
}

local NETHER_BLOCKS = {
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

local NETHERITE_JUNK = {
  ["minecraft:nether_quartz_ore"]=true,
  ["minecraft:nether_gold_ore"]=true,
  ["minecraft:quartz"]=true,
  ["minecraft:gold_nugget"]=true
}

local TARGET_MODS = {
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

local x, y, z = 0, 0, 0
local homeX, homeZ = 0, 0
local mineCenterX, mineCenterZ = 0, 0
local mineMinX, mineMaxX, mineMinZ, mineMaxZ = nil, nil, nil, nil
local heading = 0
local storageHeading = 0
local fuelHeading = 2
local topY, targetY = nil, nil
local miningMode = "normal"
local wantedOres = nil
local wantedOrePatterns = nil

local oreMinedCount = 0
local minedSinceStatus = {}
local veinSteps = 0
local skippedTargets = {}
local adminId = nil
local modemSide = nil
local modemEquipped = false
local lastStatusAt = 0
local adminStartReceived = false
local pendingUnload = false
local pendingRefuel = false
local minerState = "boot"
local minerAlert = nil
local lastCommand = nil
local lastCommandSeq = nil

local scanner = peripheral.find("geoScanner") or peripheral.find("geo_scanner")

math.randomseed(os.epoch("utc"))

local function log(msg)
  print("[Miner] "..msg)
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

local save
local stop

local function computerId()
  if os.getComputerID then return os.getComputerID() end
  return nil
end

local function findWirelessModemSide()
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

local function equipEnderModem()
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

local function unequipEnderModem()
  if modemSide and rednet.isOpen and rednet.isOpen(modemSide) then
    rednet.close(modemSide)
  end

  if modemEquipped then
    turtle.select(MODEM_SLOT)

    if turtle.equipRight and turtle.equipRight() then
      modemEquipped = false
    elseif turtle.equipLeft and turtle.equipLeft() then
      modemEquipped = false
    end
  end

  modemSide = nil
end

local function openWirelessModem()
  if modemSide and rednet.isOpen and rednet.isOpen(modemSide) then
    return true
  end

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

local function lowerName(name)
  return string.lower(tostring(name or ""))
end

local function isScannerItemName(name)
  local lower = lowerName(name)
  return string.find(lower, "geo", 1, true) ~= nil
    and string.find(lower, "scanner", 1, true) ~= nil
end

local function isModemItemName(name)
  return string.find(lowerName(name), "modem", 1, true) ~= nil
end

local function isPickaxeItemName(name)
  return string.find(lowerName(name), "pickaxe", 1, true) ~= nil
end

local function isEnderChestItemName(name)
  local lower = lowerName(name)
  return string.find(lower, "ender", 1, true) ~= nil
    and string.find(lower, "chest", 1, true) ~= nil
end

local function isEnderChestBlockName(name)
  return isEnderChestItemName(name)
end

local function refreshScanner()
  scanner = peripheral.find("geoScanner") or peripheral.find("geo_scanner")
  return scanner ~= nil
end

local function findSlotByNameTest(testFn, firstSlot, lastSlot)
  for i=firstSlot or 1,lastSlot or 16 do
    local item = turtle.getItemDetail(i)
    if item and testFn(item.name) then
      return i, item
    end
  end

  return nil, nil
end

local function moveMatchingItemToSlot(testFn, targetSlot, label)
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

local function equipItemFromSlot(slot, label)
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

local function recoverScannerUpgrade()
  if refreshScanner() then return true end

  local slot = findSlotByNameTest(isScannerItemName, 1, 16)
  if slot and equipItemFromSlot(slot, "GeoScanner") and refreshScanner() then
    return true
  end

  return false
end

local function recoverPickaxeUpgrade()
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

local function recoverModemSlot()
  if moveMatchingItemToSlot(isModemItemName, MODEM_SLOT, "Ender/Wireless Modem") then
    return true
  end

  if findWirelessModemSide() then
    return true
  end

  return false
end

local function turnRightRaw()
  turtle.turnRight()
  heading = (heading + 1) % 4
end

local function turnLeftRaw()
  turtle.turnLeft()
  heading = (heading + 3) % 4
end

local function faceRaw(targetHeading)
  while heading ~= targetHeading do
    turnRightRaw()
  end
end

local function tryDigEnderChestHere(inspectFn, digFn, slot, label)
  local ok, data = inspectFn()

  if not ok or not data or not isEnderChestBlockName(data.name) then
    return false
  end

  log(label.." fehlt in Slot "..slot.."; gefundene Ender-Chest wird eingesammelt: "..data.name)
  turtle.select(slot)

  if not digFn() then
    return false
  end

  if turtle.getItemCount(slot) > 0 then
    return true
  end

  return moveMatchingItemToSlot(isEnderChestItemName, slot, label)
end

local function recoverAdjacentEnderChest(slot, label)
  if moveMatchingItemToSlot(isEnderChestItemName, slot, label) then
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

local function repairStartupEquipment()
  recoverModemSlot()
  recoverScannerUpgrade()
  recoverPickaxeUpgrade()

  if not refreshScanner() then
    stop("Kein Geo Scanner gefunden. Lege ihn in einen Slot oder rueste ihn wieder aus.")
  end

  recoverAdjacentEnderChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")
  recoverAdjacentEnderChest(FUEL_CHEST_SLOT, "Fuel-Ender-Chest")
end

local function locateGps(required)
  if not gps or not gps.locate then
    if required then error("GPS API nicht verfuegbar.") end
    return nil
  end

  local equippedForGps = false

  if not findWirelessModemSide() then
    if not equipEnderModem() then
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

local function tableCount(t)
  local n = 0
  for _,count in pairs(t) do
    n = n + count
  end
  return n
end

local function isInventoryBlockName(name)
  if not name then return false end

  local lower = string.lower(name)
  return string.find(lower, "chest", 1, true) ~= nil
    or string.find(lower, "barrel", 1, true) ~= nil
    or string.find(lower, "drawer", 1, true) ~= nil
    or string.find(lower, "sophisticatedstorage", 1, true) ~= nil
end

local function headingFromDelta(dx, dz)
  if dx == 1 and dz == 0 then return 1 end
  if dx == -1 and dz == 0 then return 3 end
  if dx == 0 and dz == 1 then return 2 end
  if dx == 0 and dz == -1 then return 0 end
  return nil
end

local function headingName(h)
  if h == 0 then return "north" end
  if h == 1 then return "east" end
  if h == 2 then return "south" end
  if h == 3 then return "west" end
  return tostring(h)
end

local function setupScan(radius)
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

local function collectInventoryPositions(blocks, maxDist)
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

local function looksLikeNether(blocks)
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

local function inferMoveHeading(before, after)
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

local function setupBackToProbeStart()
  for _=1,8 do
    if turtle.back() then
      return true
    end

    turtle.attack()
    sleep(0.2)
  end

  return false
end

local function probeSideForHeading(before, side)
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

local function resolveAmbiguousStartHeading(candidates)
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

local function autoDetectStartHeading()
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

local function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return 999999999 end
  return f
end

local function fuelLimit()
  if turtle.getFuelLimit then
    local f = turtle.getFuelLimit()
    if f == "unlimited" then return 999999999 end
    return f
  end
  return 999999999
end

local function chooseNormalTargetY(currentTopY)
  local lowestY = CONFIG_LOWEST_Y
  local safeTopY = tonumber(currentTopY) or tonumber(y) or CONFIG_TOP_Y
  local highestStartY = math.floor(safeTopY - MIN_START_DEPTH_BELOW_TOP)

  lowestY = math.floor(lowestY)

  if highestStartY < lowestY then
    log("Start-Y ist zu tief fuer zufaellige Zielhoehe. Nutze aktuelle/naechste sichere Zielhoehe.")

    local currentY = tonumber(y)
    if currentY and currentY < lowestY then
      currentY = math.floor(currentY)
      return currentY, currentY, currentY
    end

    return lowestY, lowestY, lowestY
  end

  return math.random(lowestY, highestStartY), lowestY, highestStartY
end

local function ensureTargetY()
  if type(targetY) == "number" then return end

  if miningMode == "netherite" then
    targetY = CONFIG_NETHERITE_TARGET_Y
  else
    targetY = y or CONFIG_LOWEST_Y
  end

  log("Ziel-Y fehlte im State. Setze Ziel-Y auf "..targetY..".")
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
    miningMode=miningMode,
    wantedOres=wantedOres,
    wantedOrePatterns=wantedOrePatterns,
    adminId=adminId,
    adminStartReceived=adminStartReceived
  })
end

stop = function(msg)
  save()
  print("")
  print("========== STOP ==========")
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
  print("==========================")
  error(msg)
end

local function setup()
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
    targetY, lowestY, highestStartY = chooseNormalTargetY(topY)
    print("Zufaellige Mining-Start-Y: "..targetY.." (zwischen "..lowestY.." und "..highestStartY..")")
  end

  fuelHeading = heading
  storageHeading = (heading + 2) % 4

  save()
end

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
    miningMode=s.miningMode or "normal"
    wantedOres=s.wantedOres
    wantedOrePatterns=s.wantedOrePatterns
    adminId=s.adminId
    adminStartReceived = s.adminStartReceived ~= false
    log("Resume gefunden.")
  else
    fs.delete(STATE)
    setup()
  end
else
  setup()
end

repairStartupEquipment()
ensureTargetY()

local function isOre(name)
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

local function isJunkItem(name)
  if not name then return false end

  if JUNK[name] then return true end

  if miningMode == "netherite" and NETHERITE_JUNK[name] then
    return true
  end

  return false
end

local function isProtectedBlock(name)
  if not name then return false end

  if string.find(name, "turtle", 1, true) then
    return true
  end

  return false
end

local function recordOreMined(name)
  oreMinedCount = oreMinedCount + 1
  minedSinceStatus[name or "unknown"] = (minedSinceStatus[name or "unknown"] or 0) + 1
end

local function statusPayload(kind)
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

local function sendStatus(kind, resetMinute)
  if not openWirelessModem() then
    log("Kein Ender/Wireless Modem gefunden.")
    return false
  end

  locateGps(false)

  local payload = statusPayload(kind)

  if adminId then
    rednet.send(adminId, payload, ADMIN_PROTOCOL)
  else
    rednet.broadcast(payload, ADMIN_PROTOCOL)
  end

  unequipEnderModem()

  if resetMinute then
    minedSinceStatus = {}
    lastStatusAt = os.epoch("utc")
  end

  return true
end

local function commandTargetsThisMiner(cmd)
  local id = computerId()
  local target = cmd.targetId or cmd.minerId or cmd.id

  return target == nil or target == id or target == "all" or target == "*"
end

local function commandValue(cmd, key)
  if cmd[key] ~= nil then return cmd[key] end
  if type(cmd.target) == "table" then return cmd.target[key] end
  if type(cmd.coords) == "table" then return cmd.coords[key] end
  if type(cmd.area) == "table" then return cmd.area[key] end
  if type(cmd.bounds) == "table" then return cmd.bounds[key] end
  return nil
end

local function normalizeOreName(name)
  if not name then return nil end

  local text = string.lower(tostring(name))
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")

  if text == "" then return nil end
  if text == "all" or text == "*" then return "all" end
  if text == "netherite" or text == "ancient_debris" then return "minecraft:ancient_debris" end
  if string.find(text, ":", 1, true) then return text end
  if string.find(text, "_ore", 1, true) then return "minecraft:"..text end

  return "minecraft:"..text.."_ore"
end

local function oreSetFromCommand(value)
  if value == nil then return nil, false end

  local result = {}
  local function addOreName(name)
    result[name] = true

    local vanilla = string.match(name, "^minecraft:(.+_ore)$")
    if vanilla and not string.find(vanilla, "^deepslate_", false) then
      result["minecraft:deepslate_"..vanilla] = true
    end
  end

  if type(value) == "string" then
    for part in string.gmatch(value, "[^,]+") do
      local name = normalizeOreName(part)
      if name == "all" then return nil, true end
      if name then
        addOreName(name)
      end
    end
  elseif type(value) == "table" then
    for _,part in pairs(value) do
      local name = normalizeOreName(part)
      if name == "all" then return nil, true end
      if name then
        addOreName(name)
      end
    end
  end

  for _ in pairs(result) do
    return result, true
  end

  return nil, true
end

local function orePatternsFromCommand(value)
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

local function areaValue(cmd, ...)
  local keys = { ... }

  for _,key in ipairs(keys) do
    local value = commandValue(cmd, key)
    if value ~= nil then return tonumber(value) end
  end

  return nil
end

local function setMineArea(ax1, az1, ax2, az2)
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

local function clearMineArea()
  mineMinX = nil
  mineMaxX = nil
  mineMinZ = nil
  mineMaxZ = nil
end

local function inMineArea(tx, tz)
  if mineMinX then
    return tx >= mineMinX and tx <= mineMaxX and tz >= mineMinZ and tz <= mineMaxZ
  end

  return math.abs(tx - mineCenterX) <= MAX_DISTANCE_FROM_SHAFT
    and math.abs(tz - mineCenterZ) <= MAX_DISTANCE_FROM_SHAFT
end

local function clampToMineArea(tx, tz)
  if not mineMinX then return tx, tz end

  if tx < mineMinX then tx = mineMinX end
  if tx > mineMaxX then tx = mineMaxX end
  if tz < mineMinZ then tz = mineMinZ end
  if tz > mineMaxZ then tz = mineMaxZ end

  return tx, tz
end

local function applyAdminCommand(sender, cmd)
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
  local ax1 = areaValue(cmd, "x1", "minX", "fromX")
  local ax2 = areaValue(cmd, "x2", "maxX", "toX")
  local az1 = areaValue(cmd, "z1", "minZ", "fromZ")
  local az2 = areaValue(cmd, "z2", "maxZ", "toZ")

  if ax1 and ax2 and az1 and az2 then
    setMineArea(math.floor(ax1 + 0.5), math.floor(az1 + 0.5), math.floor(ax2 + 0.5), math.floor(az2 + 0.5))
  else
    if tx or tz then clearMineArea() end
    if tx then mineCenterX = math.floor(tx + 0.5) end
    if tz then mineCenterZ = math.floor(tz + 0.5) end
  end

  if ty then targetY = math.floor(ty + 0.5) end

  if cmd.mode == "netherite" or action == "netherite" then
    miningMode = "netherite"
    if not ty then targetY = CONFIG_NETHERITE_TARGET_Y end
  elseif cmd.mode == "normal" then
    miningMode = "normal"
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

local function pollAdminCommands(timeout)
  if not openWirelessModem() then return false end

  local sender, message = rednet.receive(ADMIN_PROTOCOL, timeout or 0)
  local applied = false

  if sender and message then
    applied = applyAdminCommand(sender, message)
  end

  unequipEnderModem()
  return applied
end

local function sendMinuteStatusIfDue()
  if os.epoch("utc") - lastStatusAt >= STATUS_INTERVAL * 1000 then
    sendStatus("minute", true)
    pollAdminCommands(COMMAND_WAIT)
  else
    pollAdminCommands(0)
  end
end

local function waitForAdminStart()
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

log("Gestartet.")
log("Position: x="..x.." y="..y.." z="..z.." heading="..heading)
log("Top-Y: "..topY)
log("Ziel-Y: "..targetY)
log("Mining-Modus: "..miningMode)
log("Turtle-Fuel: "..fuel().." / "..fuelLimit())

local function turnRight()
  turtle.turnRight()
  heading = (heading + 1) % 4
  save()
end

local function face(h)
  while heading ~= h do
    turnRight()
  end
end

local function redstoneSideForHeading(worldHeading)
  local diff = (worldHeading - heading) % 4

  if diff == 0 then return "front" end
  if diff == 1 then return "right" end
  if diff == 2 then return "back" end
  return "left"
end

local function hasTopCalibrationSignal()
  local side = redstoneSideForHeading(storageHeading)
  return redstone.getInput(side), side
end

local function calibrateTopFromRedstone(context)
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

local refuelFromEnderChestFull

local function checkFuel()
  if fuel() < LOW_FUEL_STOP then
    if refuelFromEnderChestFull then
      refuelFromEnderChestFull()
      return
    end

    log("Turtle-Fuel zu niedrig. Warte auf Fuel in der Turtle.")

    while fuel() < LOW_FUEL_STOP do
      sleep(10)
    end

    log("Fuel wieder ausreichend: "..fuel().." / "..fuelLimit())
  end
end

local function updateForwardPosition()
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

local function clean()
  local old = turtle.getSelectedSlot()

  for i=1,WORK_SLOT_LAST do
    turtle.select(i)
    local item = turtle.getItemDetail()
    if item and isJunkItem(item.name) then
      turtle.drop()
    end
  end

  turtle.select(old)
end

local function inventoryFull()
  for i=1,WORK_SLOT_LAST do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

local function hasValuableItems()
  for i=1,WORK_SLOT_LAST do
    local item = turtle.getItemDetail(i)
    if item and not isJunkItem(item.name) then return true end
  end
  return false
end

local function printValuables()
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

local function digFrontCanFail()
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

local function digUpCanFail()
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

local function digDownCanFail()
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

local function rawForward(allowAboveTarget, entityAvoid)
  checkFuel()

  if y > targetY and not allowAboveTarget then
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

local function rawUp()
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

local function rawDown()
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

local function up()
  if not rawUp() then stop("Kann nicht nach oben fahren.") end
end

local function down()
  if not rawDown() then stop("Kann nicht nach unten fahren.") end
end

local function forwardStrict()
  if not rawForward(false) then
    stop("Kann nicht streng nach vorne fahren.")
  end
end

local function tryBypassUp()
  log("Versuche Ausweichroute: hoch -> 2 vor -> runter")

  if y > targetY then
    log("Ausweichen ueber Ziel-Y nicht erlaubt.")
    return false
  end

  local startY = y
  local startHeading = heading

  if not rawUp() then
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

local function forwardTravel(remaining)
  if rawForward(false, true) then
    return true
  end

  if remaining < 2 then
    log("Vorne blockiert, aber fuer Ausweichroute bleiben weniger als 2 Bloecke.")
    return false
  end

  return tryBypassUp()
end

local function moveBackStrict()
  local old = heading
  face((old + 2) % 4)

  if not rawForward(false) then
    stop("Kann nicht zurueck fahren.")
  end

  face(old)
end

local function minimumFuelForTripFromTop()
  local shaftDistance = math.abs(topY - targetY)
  return shaftDistance * 2 + RETURN_FUEL_BUFFER
end

local function waitForTopRedstoneRelease()
  if x ~= 0 or z ~= 0 or y ~= topY then
    return
  end

  while redstone.getInput("top") do
    log("Redstone oben aktiv. Warte bei den Kisten.")
    sleep(5)
  end
end

local function refuelFromFrontFull()
  if x ~= 0 or z ~= 0 or y ~= topY then
    stop("Tanken geht nur oben an der Fuel-Kiste.")
  end

  local old = heading
  face(fuelHeading)

  while fuel() < fuelLimit() do
    log("Warte auf Fuel in der Kiste VOR der Turtle. Aktuell "..fuel().." / "..fuelLimit())

    local before = fuel()

    for i=1,WORK_SLOT_LAST do
      turtle.select(i)

      while fuel() < fuelLimit() do
        local got = turtle.suck(64)
        if not got then break end

        local ok = turtle.refuel()
        if not ok then
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

local function storeToBack()
  log("Lagere Items in Kiste HINTER der Turtle.")

  local old = heading
  face(storageHeading)

  for i=1,WORK_SLOT_LAST do
    turtle.select(i)
    local item = turtle.getItemDetail()
    if item and not isJunkItem(item.name) then
      local ok = turtle.drop()
      if not ok then
        stop("Lager-Kiste hinten ist voll oder nicht erreichbar.")
      end
    end
  end

  face(old)
end

local function requireReservedChest(slot, label)
  if slot == MODEM_SLOT then
    recoverModemSlot()

    local modemItem = turtle.getItemDetail(slot)
    if modemItem and isModemItemName(modemItem.name) then
      return modemItem.name
    end

    if findWirelessModemSide() then
      return "equipped_modem"
    end

    stop(label.." fehlt in Slot "..slot.." oder ist nicht ausgeruestet.")
  end

  local item = turtle.getItemDetail(slot)

  if not item or not isEnderChestItemName(item.name) then
    recoverAdjacentEnderChest(slot, label)
    item = turtle.getItemDetail(slot)
  end

  if not item or not isEnderChestItemName(item.name) then
    stop(label.." fehlt in Slot "..slot.." oder ist keine Ender-Chest.")
  end

  return item.name
end

local function placeReusableChest(slot, label)
  local chestName = requireReservedChest(slot, label)
  turtle.select(slot)

  while turtle.detect() do
    log("Platz fuer "..label.." vorne blockiert. Raeume Block weg.")
    if not digFrontCanFail() then
      sleep(5)
    end
  end

  while not turtle.place() do
    log("Kann "..label.." nicht platzieren. Warte.")
    sleep(5)
  end

  return chestName
end

local function recoverReusableChest(slot, label, chestName)
  turtle.select(slot)

  while turtle.detect() do
    if turtle.dig() then
      break
    end

    log("Kann "..label.." nicht abbauen. Warte.")
    sleep(5)
  end

  if turtle.getItemCount(slot) > 0 then
    return
  end

  for i=1,WORK_SLOT_LAST do
    local item = turtle.getItemDetail(i)

    if item and item.name == chestName then
      turtle.select(i)
      turtle.transferTo(slot)
      turtle.select(slot)
      return
    end
  end

  stop(label.." konnte nach dem Abbauen nicht in Slot "..slot.." wiedergefunden werden.")
end

local function unloadToEnderChest()
  clean()
  log("Entlade in wiederverwendbare Ender-Chest aus Slot "..UNLOAD_CHEST_SLOT..".")

  local chestName = placeReusableChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest")

  for i=1,WORK_SLOT_LAST do
    turtle.select(i)

    while turtle.getItemCount(i) > 0 do
      local item = turtle.getItemDetail(i)

      if not item or isJunkItem(item.name) then
        turtle.drop()
        break
      end

      if not turtle.drop() then
        log("Entlade-Ender-Chest voll. Warte auf freien Platz.")
        minerAlert = "unload_chest_full"
        sendStatus("unload_chest_full", false)
        pollAdminCommands(COMMAND_WAIT)
        sleep(10)
      end
    end
  end

  recoverReusableChest(UNLOAD_CHEST_SLOT, "Entlade-Ender-Chest", chestName)
  clean()
end

refuelFromEnderChestFull = function()
  if fuel() >= fuelLimit() then return end

  clean()

  if inventoryFull() then
    unloadToEnderChest()
  end

  log("Tanke aus wiederverwendbarer Fuel-Ender-Chest aus Slot "..FUEL_CHEST_SLOT..".")

  local chestName = placeReusableChest(FUEL_CHEST_SLOT, "Fuel-Ender-Chest")

  while fuel() < fuelLimit() do
    local before = fuel()

    for i=1,WORK_SLOT_LAST do
      turtle.select(i)

      while fuel() < fuelLimit() do
        local got = turtle.suck(64)
        if not got then break end

        if not turtle.refuel() then
          turtle.drop()
          break
        end
      end
    end

    if fuel() == before then
      log("Fuel-Ender-Chest liefert gerade keinen Fuel. Warte.")
      minerAlert = "fuel_wait"
      sendStatus("fuel_wait", false)
      pollAdminCommands(COMMAND_WAIT)
      sleep(10)
    end
  end

  recoverReusableChest(FUEL_CHEST_SLOT, "Fuel-Ender-Chest", chestName)
  minerAlert = nil
  log("Turtle-Fuel voll: "..fuel().." / "..fuelLimit())
end

local function scannerFuel()
  if scanner.getFuelLevel then
    local ok, f = pcall(function() return scanner.getFuelLevel() end)
    if ok and type(f) == "number" then return f end
  end
  return nil
end

local function scannerMaxFuel()
  if scanner.getMaxFuelLevel then
    local ok, f = pcall(function() return scanner.getMaxFuelLevel() end)
    if ok and type(f) == "number" then return f end
  end
  return nil
end

local function scanCost(radius)
  local side = radius * 2 + 1
  return side * side * side
end

local function bestRadiusByFuel()
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

local function targetKey(tx,ty,tz)
  return tostring(tx)..","..tostring(ty)..","..tostring(tz)
end

local function scan()
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

local function nearestOre()
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

local function goHorizontal(tx, tz)
  if y > targetY then
    stop("Seitliche Bewegung ueber Ziel-Y blockiert.")
  end

  if x < tx then
    face(1)
    while x < tx do
      local remaining = tx - x
      if not forwardTravel(remaining) then stop("Weg nach Osten blockiert.") end
      clean()
    end
  end

  if x > tx then
    face(3)
    while x > tx do
      local remaining = x - tx
      if not forwardTravel(remaining) then stop("Weg nach Westen blockiert.") end
      clean()
    end
  end

  if z < tz then
    face(2)
    while z < tz do
      local remaining = tz - z
      if not forwardTravel(remaining) then stop("Weg nach Sueden blockiert.") end
      clean()
    end
  end

  if z > tz then
    face(0)
    while z > tz do
      local remaining = z - tz
      if not forwardTravel(remaining) then stop("Weg nach Norden blockiert.") end
      clean()
    end
  end
end

local function goTo(tx, ty, tz)
  log("Gehe zu x="..tx.." y="..ty.." z="..tz.." von x="..x.." y="..y.." z="..z)

  while y > targetY do
    down()
    clean()
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

local unload
local mineAdjacentOres

local function returnFuelNeeded()
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

local function ensureCanReturn()
  local needed = returnFuelNeeded()

  if fuel() < needed and not (x==homeX and z==homeZ and y==topY) then
    log("Fuel wird knapp. Fuel="..fuel().." benoetigt~"..needed)
    unload()
  end
end

local function mineFrontOreAndEnter()
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

local function mineUpOreAndEnter()
  local ok, data = turtle.inspectUp()

  if not ok or not data or not isOre(data.name) then
    log("Oben ist kein Ore mehr.")
    return false
  end

  log("Ziel-Ore oben bestaetigt: "..data.name)

  if not digUpCanFail() then return false end
  if not rawUp() then return false end

  printValuables()
  mineAdjacentOres()
  return true
end

local function mineDownOreAndEnter()
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

local function mineScannedOre(ore)
  local tx = x + ore.x
  local ty = y + ore.y
  local tz = z + ore.z
  local key = targetKey(tx,ty,tz)

  log("Gezieltes Ore-Mining: "..ore.name.." bei x="..tx.." y="..ty.." z="..tz)

  local success = false

  if ty > targetY then
    goTo(tx, ty - 1, tz)
    success = mineUpOreAndEnter()
  elseif ty < targetY then
    goTo(tx, ty + 1, tz)
    success = mineDownOreAndEnter()
  else
    if ore.x > 0 then
      goTo(tx - 1, ty, tz)
      face(1)
      success = mineFrontOreAndEnter()
    elseif ore.x < 0 then
      goTo(tx + 1, ty, tz)
      face(3)
      success = mineFrontOreAndEnter()
    elseif ore.z > 0 then
      goTo(tx, ty, tz - 1)
      face(2)
      success = mineFrontOreAndEnter()
    elseif ore.z < 0 then
      goTo(tx, ty, tz + 1)
      face(0)
      success = mineFrontOreAndEnter()
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
      rawUp()
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

local function descendToTarget()
  if x == homeX and z == homeZ and y > targetY then
    log("Fahre runter von Y "..y.." zu Ziel-Y "..targetY)

    while y > targetY do
      down()
      clean()
      log("Aktuelle Y: "..y.." / Ziel-Y: "..targetY)
    end

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

local function alignToTargetY()
  while y > targetY do
    down()
    clean()
  end

  while y < targetY do
    up()
    clean()
  end
end

local function tooFarFromShaft()
  return not inMineArea(x, z)
end

local function randomMove()
  ensureCanReturn()

  while y > targetY do
    down()
    clean()
  end

  if tooFarFromShaft() then
    log("Zu weit vom Mining-Center entfernt. Kehre zum Mining-Center zurueck.")
    goHorizontal(mineCenterX,mineCenterZ)
    return
  end

  for attempt=1,6 do
    local h = math.random(0,3)
    local dist = math.random(RANDOM_MOVE_MIN, RANDOM_MOVE_MAX)

    local tx, tz = x, z

    if h == 0 then
      tz = z - dist
    elseif h == 1 then
      tx = x + dist
    elseif h == 2 then
      tz = z + dist
    elseif h == 3 then
      tx = x - dist
    end

    tx, tz = clampToMineArea(tx, tz)

    if inMineArea(tx, tz) and (tx ~= x or tz ~= z) then
      log("Kein Ore gefunden. Random Move: heading "..h..", Distanz "..dist)
      face(h)

      local moved = 0

      while moved < dist do
        ensureCanReturn()

        local remaining = dist - moved

        if not forwardTravel(remaining) then
          log("Random Move blockiert nach "..moved.." Bloecken.")
          return
        end

        moved = moved + 1
        clean()
      end

      log("Random Move fertig. Position: x="..x.." y="..y.." z="..z)
      return
    end
  end

  log("Keine passende Random-Richtung gefunden. Gehe zum Mining-Center.")
  goHorizontal(mineCenterX,mineCenterZ)
end

local function miningLoop()
  minerState = "mining"
  log("Mining-Loop startet.")

  while true do
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
end

local function main()
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

main()
