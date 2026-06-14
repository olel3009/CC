-- Certus-Quartz-Sammler fuer CC:Tweaked + Advanced Peripherals GeoScanner.
-- Start: Turtle steht ueber dem Lager und schaut in die gewuenschte Startrichtung.
-- Lager: direkt unter der Startposition.
-- Fuel-Kiste: direkt hinter der Startposition.
-- Ersatz fuer Flawed Budding Certus Quartz: optional im Lager unten.
-- Der Sammler graebt auf Wegen keine Bloecke frei.

local STATE_FILE = "certus_quartz_collector_state"

local AREA_MIN_X = -8
local AREA_MAX_X = 7
local AREA_MIN_Z = -8
local AREA_MAX_Z = 7

local AREA_MIN_Y = -8
local AREA_MAX_Y = 8

local SCAN_RADIUS = 16
local SCAN_WAIT = 3
local LOW_FUEL = 30
local REFUEL_TARGET = 600
local RETURN_BUFFER = 20
local CONFIG_HEADING = 0

local STORAGE_SIDE = "bottom"
local STORAGE_POS_KEY = "0,-1,0"

local FLAWED_BUDDING = "ae2:flawed_budding_quartz"

local MATURE_CLUSTERS = {
  ["ae2:quartz_cluster"] = true,
  ["ae2:certus_quartz_cluster"] = true
}

local x, y, z = 0, 0, 0
local heading = CONFIG_HEADING
local startHeading = CONFIG_HEADING
local replacedFlawedPositions = {}

local scanner = peripheral.find("geoScanner") or peripheral.find("geo_scanner")
if not scanner then
  error("Kein Geo Scanner gefunden.")
end

local function log(msg)
  print("[CertusQuartz] "..msg)
end

local function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return 999999999 end
  return f
end

local function headingName(h)
  if h == 0 then return "north" end
  if h == 1 then return "east" end
  if h == 2 then return "south" end
  if h == 3 then return "west" end
  return tostring(h)
end

local function key(px, py, pz)
  return tostring(px)..","..tostring(py)..","..tostring(pz)
end

local function parseKey(k)
  local a, b, c = string.match(k, "^(-?%d+),(-?%d+),(-?%d+)$")
  return tonumber(a), tonumber(b), tonumber(c)
end

local function inSearchArea(px, py, pz)
  return px >= AREA_MIN_X and px <= AREA_MAX_X
    and pz >= AREA_MIN_Z and pz <= AREA_MAX_Z
    and py >= AREA_MIN_Y and py <= AREA_MAX_Y
end

local function inScanReach(px, py, pz)
  return math.abs(px - x) <= SCAN_RADIUS
    and math.abs(py - y) <= SCAN_RADIUS
    and math.abs(pz - z) <= SCAN_RADIUS
end

local function isTargetBlock(name)
  return name == FLAWED_BUDDING or MATURE_CLUSTERS[name] == true
end

local function turnRight()
  turtle.turnRight()
  heading = (heading + 1) % 4
end

local function turnLeft()
  turtle.turnLeft()
  heading = (heading + 3) % 4
end

local function face(h)
  while heading ~= h do
    turnRight()
  end
end

local function writeState()
  local data = {
    version = 1,
    start = { x = 0, y = 0, z = 0, heading = startHeading },
    area = {
      minX = AREA_MIN_X,
      maxX = AREA_MAX_X,
      minZ = AREA_MIN_Z,
      maxZ = AREA_MAX_Z,
      minY = AREA_MIN_Y,
      maxY = AREA_MAX_Y
    }
  }

  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(data))
  f.close()
end

local function isInventoryBlock(name)
  if not name then return false end
  local lower = string.lower(name)
  return string.find(lower, "chest", 1, true) ~= nil
    or string.find(lower, "barrel", 1, true) ~= nil
    or string.find(lower, "drawer", 1, true) ~= nil
    or string.find(lower, "sophisticatedstorage", 1, true) ~= nil
end

local function hasStorageBelow()
  local inv = peripheral.wrap(STORAGE_SIDE)
  if inv and inv.list then return true end

  local ok, data = turtle.inspectDown()
  return ok and data and isInventoryBlock(data.name)
end

local function selectItem(name)
  for i=1,16 do
    local item = turtle.getItemDetail(i)
    if item and item.name == name then
      turtle.select(i)
      return true
    end
  end

  return false
end

local function selectEmptySlot()
  for i=1,16 do
    if turtle.getItemCount(i) == 0 then
      turtle.select(i)
      return true
    end
  end

  return false
end

local function refuelFromBack()
  if x ~= 0 or y ~= 0 or z ~= 0 then return true end
  if fuel() >= REFUEL_TARGET then return true end

  log("Tanke aus Fuel-Kiste hinter der Startposition. Fuel="..fuel())
  local oldHeading = heading
  face((startHeading + 2) % 4)

  for _=1,16 do
    if not selectEmptySlot() then break end

    if not turtle.suck(64) then break end

    if not turtle.refuel() then
      turtle.drop()
    end
  end

  face(oldHeading)
  log("Fuel jetzt: "..fuel())
  return fuel() >= LOW_FUEL
end

local function scanRaw()
  while true do
    local result, err

    if scanner.scanBlocks then
      result, err = scanner.scanBlocks(SCAN_RADIUS)
    elseif scanner.scan then
      result, err = scanner.scan(SCAN_RADIUS)
    else
      error("Scanner hat weder scanBlocks() noch scan().")
    end

    if type(result) == "table" then
      return result
    end

    log("Scanner Fehler: "..tostring(err))
    sleep(SCAN_WAIT)
  end
end

local function inferMoveHeading(before, after)
  local afterSet = {}

  for _,b in ipairs(after) do
    if b and b.name and b.x and b.y and b.z then
      afterSet[b.name.."@"..key(b.x, b.y, b.z)] = true
    end
  end

  local candidates = {
    { h = 0, dx = 0, dz = -1 },
    { h = 1, dx = 1, dz = 0 },
    { h = 2, dx = 0, dz = 1 },
    { h = 3, dx = -1, dz = 0 }
  }
  local scores = {}

  for _,candidate in ipairs(candidates) do
    scores[candidate.h] = 0

    for _,old in ipairs(before) do
      if old and old.name and old.x and old.y and old.z then
        local shifted = old.name.."@"..key(old.x - candidate.dx, old.y, old.z - candidate.dz)

        if afterSet[shifted] then
          scores[candidate.h] = scores[candidate.h] + 1
        end
      end
    end
  end

  local best, bestScore, tied = nil, 0, false

  for h,score in pairs(scores) do
    if score > bestScore then
      best = h
      bestScore = score
      tied = false
    elseif score == bestScore then
      tied = true
    end
  end

  if best ~= nil and bestScore > 0 and not tied then
    return best
  end

  return nil
end

local function autoHeading()
  local before = scanRaw()

  turtle.turnRight()

  if turtle.detect() or not turtle.forward() then
    turtle.turnLeft()
    return CONFIG_HEADING
  end

  local after = scanRaw()
  local returned = false

  for _=1,8 do
    if turtle.back() then
      returned = true
      break
    end

    sleep(0.2)
  end

  turtle.turnLeft()

  if not returned then
    error("Auto-Ausrichtung: Probe konnte nicht zurueck zur Startposition fahren.")
  end

  local moveHeading = inferMoveHeading(before, after)
  if moveHeading == nil then return CONFIG_HEADING end

  return (moveHeading + 3) % 4
end

local function buildBlockMap(blocks)
  local map = {}

  for _,b in ipairs(blocks) do
    if b and b.name and b.x and b.y and b.z then
      local px = x + b.x
      local py = y + b.y
      local pz = z + b.z

      if inSearchArea(px, py, pz) or key(px, py, pz) == STORAGE_POS_KEY then
        map[key(px, py, pz)] = b.name
      end
    end
  end

  return map
end

local function currentMap()
  log("Scan Radius "..SCAN_RADIUS.." bei x="..x.." y="..y.." z="..z)
  return buildBlockMap(scanRaw())
end

local function isPassable(px, py, pz, map)
  if key(px, py, pz) == STORAGE_POS_KEY then return false end
  if not inSearchArea(px, py, pz) then return false end
  if not inScanReach(px, py, pz) then return false end
  if px == x and py == y and pz == z then return true end
  return map[key(px, py, pz)] == nil
end

local function neighbors(node, map)
  local result = {}
  local dirs = {
    { 1, 0, 0 },
    { -1, 0, 0 },
    { 0, 0, 1 },
    { 0, 0, -1 },
    { 0, 1, 0 },
    { 0, -1, 0 }
  }

  for _,d in ipairs(dirs) do
    local nx, ny, nz = node.x + d[1], node.y + d[2], node.z + d[3]
    if isPassable(nx, ny, nz, map) then
      table.insert(result, { x = nx, y = ny, z = nz })
    end
  end

  return result
end

local function findPath(tx, ty, tz, map)
  if x == tx and y == ty and z == tz then return {} end
  if not isPassable(tx, ty, tz, map) then return nil end

  local start = { x = x, y = y, z = z }
  local startKey = key(x, y, z)
  local targetKey = key(tx, ty, tz)
  local queue = { start }
  local head = 1
  local cameFrom = {}
  local seen = { [startKey] = true }

  while head <= #queue do
    local node = queue[head]
    head = head + 1

    for _,nextNode in ipairs(neighbors(node, map)) do
      local nk = key(nextNode.x, nextNode.y, nextNode.z)

      if not seen[nk] then
        seen[nk] = true
        cameFrom[nk] = key(node.x, node.y, node.z)

        if nk == targetKey then
          local reversed = {}
          local cursor = nk

          while cursor ~= startKey do
            local px, py, pz = parseKey(cursor)
            table.insert(reversed, { x = px, y = py, z = pz })
            cursor = cameFrom[cursor]
          end

          local path = {}
          for i=#reversed,1,-1 do
            table.insert(path, reversed[i])
          end

          return path
        end

        table.insert(queue, nextNode)
      end
    end
  end

  return nil
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

local function moveForwardNoDig()
  if fuel() < LOW_FUEL then return false end
  if turtle.detect() then return false end

  local tries = 0
  while not turtle.forward() do
    tries = tries + 1
    if tries >= 8 then return false end
    sleep(0.2)
  end

  updateForwardPosition()
  return true
end

local function moveUpNoDig()
  if fuel() < LOW_FUEL then return false end
  if turtle.detectUp() then return false end

  local tries = 0
  while not turtle.up() do
    tries = tries + 1
    if tries >= 8 then return false end
    sleep(0.2)
  end

  y = y + 1
  return true
end

local function moveDownNoDig()
  if fuel() < LOW_FUEL then return false end
  if turtle.detectDown() then return false end

  local tries = 0
  while not turtle.down() do
    tries = tries + 1
    if tries >= 8 then return false end
    sleep(0.2)
  end

  y = y - 1
  return true
end

local function followPath(path)
  if not path then return false end
  if fuel() < #path + RETURN_BUFFER then return false end

  for _,step in ipairs(path) do
    local dx, dy, dz = step.x - x, step.y - y, step.z - z

    if dy == 1 and dx == 0 and dz == 0 then
      if not moveUpNoDig() then return false end
    elseif dy == -1 and dx == 0 and dz == 0 then
      if not moveDownNoDig() then return false end
    elseif dx == 1 and dy == 0 and dz == 0 then
      face(1)
      if not moveForwardNoDig() then return false end
    elseif dx == -1 and dy == 0 and dz == 0 then
      face(3)
      if not moveForwardNoDig() then return false end
    elseif dz == 1 and dy == 0 and dx == 0 then
      face(2)
      if not moveForwardNoDig() then return false end
    elseif dz == -1 and dy == 0 and dx == 0 then
      face(0)
      if not moveForwardNoDig() then return false end
    else
      return false
    end
  end

  return true
end

local function inventoryFull()
  for i=1,16 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

local function dropSlotDown(slot)
  turtle.select(slot)

  while turtle.getItemCount(slot) > 0 do
    if not turtle.dropDown() then
      return false
    end
  end

  return true
end

local function unloadAtBase()
  if x ~= 0 or y ~= 0 or z ~= 0 then return false end

  for i=1,16 do
    if turtle.getItemCount(i) > 0 then
      if not dropSlotDown(i) then
        return false
      end
    end
  end

  return true
end

local function goBase()
  local map = currentMap()
  local path = findPath(0, 0, 0, map)
  return followPath(path)
end

local function pullReplacementFromStorage()
  if x ~= 0 or y ~= 0 or z ~= 0 then return false end
  if selectItem(FLAWED_BUDDING) then return true end

  local heldUnwanted = {}
  local function restoreHeld()
    local ok = true

    for _,heldSlot in ipairs(heldUnwanted) do
      if not dropSlotDown(heldSlot) then
        ok = false
      end
    end

    return ok
  end

  for _=1,16 do
    if not selectEmptySlot() then
      restoreHeld()
      return false
    end

    local slot = turtle.getSelectedSlot()

    if not turtle.suckDown(1) then
      restoreHeld()
      return false
    end

    local item = turtle.getItemDetail()
    if item and item.name == FLAWED_BUDDING then
      restoreHeld()

      turtle.select(slot)
      return true
    end

    table.insert(heldUnwanted, slot)
  end

  restoreHeld()
  return false
end

local function ensureReplacementBlock(adjX, adjY, adjZ)
  if selectItem(FLAWED_BUDDING) then return true end

  if not goBase() then return false end
  refuelFromBack()

  if not unloadAtBase() then
    return false
  end

  if not pullReplacementFromStorage() then
    return false
  end

  local map = currentMap()
  local path = findPath(adjX, adjY, adjZ, map)
  return followPath(path) and selectItem(FLAWED_BUDDING)
end

local function placeReplacement(side)
  if not selectItem(FLAWED_BUDDING) then return false end

  if side == "up" then
    if turtle.detectUp() then return false end
    return turtle.placeUp()
  elseif side == "down" then
    if turtle.detectDown() then return false end
    return turtle.placeDown()
  end

  face(side)
  if turtle.detect() then return false end
  return turtle.place()
end

local function collectDrops(side)
  for _=1,16 do
    if inventoryFull() then return end

    local ok
    if side == "up" then
      ok = turtle.suckUp(64)
    elseif side == "down" then
      ok = turtle.suckDown(64)
    else
      ok = turtle.suck(64)
    end

    if not ok then return end
  end
end

local function adjacentPositions(target)
  return {
    { x = target.x - 1, y = target.y, z = target.z, side = 1 },
    { x = target.x + 1, y = target.y, z = target.z, side = 3 },
    { x = target.x, y = target.y, z = target.z - 1, side = 2 },
    { x = target.x, y = target.y, z = target.z + 1, side = 0 },
    { x = target.x, y = target.y - 1, z = target.z, side = "up" },
    { x = target.x, y = target.y + 1, z = target.z, side = "down" }
  }
end

local function findTargets(map)
  local targets = {}

  for pos,name in pairs(map) do
    local tx, ty, tz = parseKey(pos)

    if tx and inSearchArea(tx, ty, tz) and isTargetBlock(name) and not replacedFlawedPositions[pos] then
      table.insert(targets, {
        x = tx,
        y = ty,
        z = tz,
        name = name,
        dist = math.abs(tx - x) + math.abs(ty - y) + math.abs(tz - z)
      })
    end
  end

  table.sort(targets, function(a, b)
    if a.dist == b.dist then
      return key(a.x, a.y, a.z) < key(b.x, b.y, b.z)
    end

    return a.dist < b.dist
  end)

  return targets
end

local function pathToTarget(target, map)
  local bestPath, bestSide, bestAdj = nil, nil, nil

  for _,adj in ipairs(adjacentPositions(target)) do
    local path = findPath(adj.x, adj.y, adj.z, map)

    if path and (not bestPath or #path < #bestPath) then
      bestPath = path
      bestSide = adj.side
      bestAdj = adj
    end
  end

  return bestPath, bestSide, bestAdj
end

local function digConfirmed(side, expectedName)
  if side == "up" then
    local ok, data = turtle.inspectUp()
    if ok and data and data.name == expectedName and isTargetBlock(data.name) then
      if turtle.digUp() then
        collectDrops("up")
        return true
      end
    end
  elseif side == "down" then
    local ok, data = turtle.inspectDown()
    if ok and data and data.name == expectedName and isTargetBlock(data.name) then
      if turtle.digDown() then
        collectDrops("down")
        return true
      end
    end
  else
    face(side)
    local ok, data = turtle.inspect()
    if ok and data and data.name == expectedName and isTargetBlock(data.name) then
      if turtle.dig() then
        collectDrops("front")
        return true
      end
    end
  end

  return false
end

local function mineTarget(target, map)
  local path, side, adj = pathToTarget(target, map)

  if not path then
    log("Kein freier Weg zu "..target.name.." bei "..key(target.x, target.y, target.z)..". Ueberspringe.")
    return false
  end

  if not followPath(path) then
    log("Weg blockiert. Ziel wird uebersprungen.")
    return false
  end

  if digConfirmed(side, target.name) then
    log("Abgebaut: "..target.name.." bei "..key(target.x, target.y, target.z))

    if target.name == FLAWED_BUDDING then
      if ensureReplacementBlock(adj.x, adj.y, adj.z) and placeReplacement(side) then
        log("Ersatz-Flawed-Budding gesetzt bei "..key(target.x, target.y, target.z))
        replacedFlawedPositions[key(target.x, target.y, target.z)] = true
      else
        log("Kein Ersatz-Flawed-Budding gesetzt. Alter Platz bleibt frei.")
      end
    end

    return true
  end

  log("Ziel nicht mehr bestaetigt: "..target.name.." bei "..key(target.x, target.y, target.z))
  return false
end

local function finish(ok, msg)
  if x ~= 0 or y ~= 0 or z ~= 0 then
    if not goBase() then
      error("Rueckkehr zur Startposition fehlgeschlagen: "..msg)
    end
  end

  face(startHeading)

  if ok then
    log(msg)
    return
  end

  error(msg)
end

local function main()
  heading = autoHeading()
  startHeading = heading
  writeState()

  log("Startposition gespeichert. Suchbereich x="..AREA_MIN_X..".."..AREA_MAX_X
    .." z="..AREA_MIN_Z..".."..AREA_MAX_Z
    .." y="..AREA_MIN_Y..".."..AREA_MAX_Y
    .." heading="..headingName(startHeading))

  if not hasStorageBelow() then
    error("Kein Lager direkt unter der Startposition gefunden.")
  end

  if not refuelFromBack() then
    error("Zu wenig Fuel und keine nutzbare Fuel-Kiste hinter der Startposition.")
  end

  while true do
    if inventoryFull() then
      if not goBase() then
        finish(false, "Inventar voll und Rueckkehr zur Startposition nicht moeglich.")
      end

      if not unloadAtBase() then
        finish(false, "Lager voll. Items bleiben in der Turtle.")
      end

      refuelFromBack()
    end

    local map = currentMap()
    local targets = findTargets(map)

    if #targets == 0 then
      if not goBase() then
        finish(false, "Keine Ziele mehr, aber Rueckkehr zur Startposition nicht moeglich.")
      end

      if not unloadAtBase() then
        finish(false, "Lager voll. Items bleiben in der Turtle.")
      end

      refuelFromBack()

      finish(true, "Fertig. Keine passenden Certus-Quartz-Ziele mehr im Suchbereich.")
      return
    end

    local mined = false

    for _,target in ipairs(targets) do
      if inventoryFull() then break end

      map = currentMap()
      if map[key(target.x, target.y, target.z)] == target.name then
        if mineTarget(target, map) then
          mined = true
          break
        end
      end
    end

    if not mined then
      if not goBase() then
        finish(false, "Alle Ziele sind unerreichbar und Rueckkehr zur Startposition nicht moeglich.")
      end

      if not unloadAtBase() then
        finish(false, "Lager voll. Items bleiben in der Turtle.")
      end

      refuelFromBack()

      finish(true, "Fertig. Verbleibende Ziele haben keinen freien Weg ohne unerwuenschtes Graben.")
      return
    end
  end
end

main()
