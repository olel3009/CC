-- Prepares a 27x27 farm area around the turtle.
-- Start in the center, one block above the target ground layer.
-- Requirements: mining turtle/pickaxe, enough fuel, dirt in inventory.

local RADIUS = 13
local CLEAR_HEIGHT = 4

local x, z, dir = 0, 0, 0
-- dir: 0 = start-facing forward, 1 = right, 2 = back, 3 = left

local dirtNames = {
  ["minecraft:dirt"] = true,
  ["minecraft:grass_block"] = true,
  ["minecraft:coarse_dirt"] = true,
  ["minecraft:rooted_dirt"] = true,
  ["minecraft:podzol"] = true,
  ["minecraft:mycelium"] = true,
}

local function refuelIfPossible()
  if turtle.getFuelLevel() == "unlimited" then
    return
  end

  if turtle.getFuelLevel() > 200 then
    return
  end

  local oldSlot = turtle.getSelectedSlot()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then
      turtle.refuel()
      break
    end
  end
  turtle.select(oldSlot)
end

local function findDirt()
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and dirtNames[detail.name] then
      return slot
    end
  end
  return nil
end

local function ensureDirtSelected()
  local selected = turtle.getItemDetail()
  if selected and dirtNames[selected.name] then
    return true
  end

  local slot = findDirt()
  if not slot then
    error("Keine Erde im Inventar gefunden.")
  end
  turtle.select(slot)
  return true
end

local function inspectDownName()
  local ok, detail = turtle.inspectDown()
  if ok and detail then
    return detail.name
  end
  return nil
end

local function digForward()
  while turtle.detect() do
    if not turtle.dig() then
      turtle.attack()
      sleep(0.2)
    end
  end
end

local function forward()
  refuelIfPossible()
  digForward()
  while not turtle.forward() do
    turtle.attack()
    digForward()
    sleep(0.2)
  end

  if dir == 0 then
    z = z + 1
  elseif dir == 1 then
    x = x + 1
  elseif dir == 2 then
    z = z - 1
  else
    x = x - 1
  end
end

local function up()
  refuelIfPossible()
  while turtle.detectUp() do
    if not turtle.digUp() then
      turtle.attackUp()
      sleep(0.2)
    end
  end
  while not turtle.up() do
    turtle.attackUp()
    turtle.digUp()
    sleep(0.2)
  end
end

local function down()
  refuelIfPossible()
  while turtle.detectDown() do
    if not turtle.digDown() then
      turtle.attackDown()
      sleep(0.2)
    end
  end
  while not turtle.down() do
    turtle.attackDown()
    turtle.digDown()
    sleep(0.2)
  end
end

local function turnRight()
  turtle.turnRight()
  dir = (dir + 1) % 4
end

local function turnLeft()
  turtle.turnLeft()
  dir = (dir + 3) % 4
end

local function turnTo(target)
  while dir ~= target do
    local diff = (target - dir) % 4
    if diff == 1 then
      turnRight()
    elseif diff == 3 then
      turnLeft()
    else
      turnRight()
      turnRight()
    end
  end
end

local function moveTo(targetX, targetZ)
  if x < targetX then
    turnTo(1)
    while x < targetX do forward() end
  elseif x > targetX then
    turnTo(3)
    while x > targetX do forward() end
  end

  if z < targetZ then
    turnTo(0)
    while z < targetZ do forward() end
  elseif z > targetZ then
    turnTo(2)
    while z > targetZ do forward() end
  end
end

local function makeGroundDirt()
  ensureDirtSelected()

  local below = inspectDownName()
  if below and not dirtNames[below] then
    turtle.digDown()
    sleep(0.1)
  end

  if not turtle.detectDown() then
    ensureDirtSelected()
    while not turtle.placeDown() do
      local slot = findDirt()
      if not slot then
        error("Erde ist leer. Bitte nachfuellen und Script neu starten.")
      end
      turtle.select(slot)
      sleep(0.2)
    end
  end
end

local function clearAbove()
  for level = 1, CLEAR_HEIGHT do
    while turtle.detectUp() do
      if not turtle.digUp() then
        turtle.attackUp()
        sleep(0.2)
      end
    end
    if level < CLEAR_HEIGHT then
      up()
    end
  end

  for _ = 1, CLEAR_HEIGHT - 1 do
    down()
  end
end

local function prepareCell()
  makeGroundDirt()
  clearAbove()
end

print("Starte Farm-Vorbereitung: 27x27, 4 hoch frei.")
print("Startposition wird als Mitte verwendet.")

moveTo(-RADIUS, -RADIUS)

for row = 0, RADIUS * 2 do
  local currentZ = -RADIUS + row

  if row % 2 == 0 then
    for currentX = -RADIUS, RADIUS do
      moveTo(currentX, currentZ)
      prepareCell()
    end
  else
    for currentX = RADIUS, -RADIUS, -1 do
      moveTo(currentX, currentZ)
      prepareCell()
    end
  end
end

moveTo(0, 0)
turnTo(0)

print("Fertig. 27x27 Boden mit Erde vorbereitet und 4 Bloecke nach oben freigemacht.")
