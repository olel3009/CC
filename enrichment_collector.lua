-- enrichment_collector.lua
-- Patrol turtle for a 9 block line.
-- Start: turtle faces the patrol line.
-- Chest above start: fuel.
-- Chests above or in front of the patrol line: ore batches to process.
-- Chest below start: Mekanism Enrichment Chamber input.

local PATROL_DISTANCE = 9
local MIN_ENRICH_COUNT = 3
local LOW_FUEL_STOP = 30
local REFUEL_TARGET = 200

local METAL_KEYWORDS = {
  "aluminum",
  "aluminium",
  "iron",
  "gold",
  "copper",
  "tin",
  "lead",
  "silver",
  "nickel",
  "osmium",
  "uranium",
  "zinc",
  "platinum",
  "iridium",
  "iesnium",
  "cloggrum",
  "froststeel",
  "neptunium",
  "crimson_iron",
  "azure_silver"
}

local EXACT_ENRICH_ITEMS = {
  ["minecraft:raw_iron"]=true,
  ["minecraft:raw_gold"]=true,
  ["minecraft:raw_copper"]=true
}

local function log(msg)
  print("[EnrichCollector] "..msg)
end

local function fuel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return 999999999 end
  return f
end

local function waitForFuel()
  while fuel() < LOW_FUEL_STOP do
    log("Fuel zu niedrig: "..fuel()..". Bitte Fuel in die Turtle legen oder Fuel-Kiste oben fuellen.")
    sleep(10)

    for i=1,16 do
      turtle.select(i)
      turtle.refuel()
    end
  end
end

local function refuelFromTop()
  if fuel() >= REFUEL_TARGET then
    return
  end

  log("Tanke aus Fuel-Kiste oben. Aktuell: "..fuel())

  for i=1,16 do
    turtle.select(i)

    while fuel() < REFUEL_TARGET do
      if not turtle.suckUp(64) then
        break
      end

      if not turtle.refuel() then
        turtle.dropUp()
        break
      end
    end

    if fuel() >= REFUEL_TARGET then
      break
    end
  end

  log("Fuel nach Tanken: "..fuel())
end

local function containsAny(text, words)
  for _,word in ipairs(words) do
    if string.find(text, word, 1, true) then
      return true
    end
  end

  return false
end

local function isEnrichmentCandidate(name)
  if not name then return false end
  if EXACT_ENRICH_ITEMS[name] then return true end

  local lower = string.lower(name)

  if string.find(lower, ":raw_", 1, true) and containsAny(lower, METAL_KEYWORDS) then
    return true
  end

  if string.find(lower, "_ore", 1, true) and containsAny(lower, METAL_KEYWORDS) then
    return true
  end

  return false
end

local function forwardStrict()
  waitForFuel()

  local tries = 0
  while not turtle.forward() do
    if turtle.detect() then
      log("Weg nach vorne blockiert. Stoppe Patrol.")
      return false
    end

    turtle.attack()
    tries = tries + 1
    if tries >= 8 then return false end
    sleep(0.2)
  end

  return true
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

local countItemsByName

local function pullItemsFromChest(side)
  local moved = false

  while true do
    if not selectEmptySlot() then
      log("Inventar voll. Fahre mit gesammelten Items weiter.")
      return moved
    end

    local ok
    if side == "front" then
      ok = turtle.suck(64)
    elseif side == "top" then
      ok = turtle.suckUp(64)
    else
      ok = false
    end

    if not ok then
      return moved
    end

    local item = turtle.getItemDetail()
    if item then
      log("Aus Kiste "..side.." geholt: "..item.name.." x"..item.count)
    end

    moved = true
  end
end

local function returnUnwantedItems(side)
  local counts = countItemsByName()

  for i=1,16 do
    local item = turtle.getItemDetail(i)

    if item then
      local keep = isEnrichmentCandidate(item.name) and (counts[item.name] or 0) >= MIN_ENRICH_COUNT

      if not keep then
        turtle.select(i)
        log("Zurueck in Kiste "..side..": "..item.name.." x"..item.count)

        while turtle.getItemCount(i) > 0 do
          local ok
          if side == "front" then
            ok = turtle.drop()
          elseif side == "top" then
            ok = turtle.dropUp()
          else
            ok = false
          end

          if not ok then
            log("Kiste "..side.." voll. Item bleibt in Turtle: "..item.name)
            break
          end
        end
      end
    end
  end
end

local function turnAround()
  turtle.turnRight()
  turtle.turnRight()
end

local function isInventoryName(name)
  if not name then return false end

  local lower = string.lower(name)
  return string.find(lower, "chest", 1, true) ~= nil
    or string.find(lower, "barrel", 1, true) ~= nil
    or string.find(lower, "drawer", 1, true) ~= nil
    or string.find(lower, "sophisticatedstorage", 1, true) ~= nil
end

local function hasInventory(side)
  local inv = peripheral.wrap(side)
  if inv and inv.list then
    return true
  end

  local ok, data
  if side == "front" then
    ok, data = turtle.inspect()
  elseif side == "top" then
    ok, data = turtle.inspectUp()
  else
    return false
  end

  if not ok or not data or not data.name then
    return false
  end

  return isInventoryName(data.name)
end

local function alignToMarker()
  log("Suche Ausrichtung: vorne Kiste, hinten Redstone.")

  for turn=0,3 do
    if hasInventory("front") and redstone.getInput("back") then
      log("Ausrichtung gefunden.")
      return true
    end

    if turn < 3 then
      turtle.turnRight()
    end
  end

  log("Keine Marker-Ausrichtung gefunden. Nutze aktuelle Blickrichtung.")
  return false
end

function countItemsByName()
  local counts = {}

  for i=1,16 do
    local item = turtle.getItemDetail(i)
    if item then
      counts[item.name] = (counts[item.name] or 0) + item.count
    end
  end

  return counts
end

local function dropSlotDown(slot)
  turtle.select(slot)

  while turtle.getItemCount(slot) > 0 do
    if not turtle.dropDown() then
      log("Enrichment-Kiste unten voll oder nicht erreichbar.")
      return false
    end
  end

  return true
end

local function unloadAtStart()
  refuelFromTop()
  log("Sortiere Inventar.")

  local counts = countItemsByName()

  for i=1,16 do
    local item = turtle.getItemDetail(i)

    if item and isEnrichmentCandidate(item.name) and (counts[item.name] or 0) >= MIN_ENRICH_COUNT then
      log("Zur Enrichment-Kiste: "..item.name.." x"..item.count)
      if not dropSlotDown(i) then return false end
    end
  end

  for i=1,16 do
    if turtle.getItemCount(i) > 0 then
      local item = turtle.getItemDetail(i)
      if item then
        log("Bleibt in Turtle, keine Rest-Kiste konfiguriert: "..item.name.." x"..item.count)
      end
    end
  end

  return true
end

local function processAvailableChest()
  if hasInventory("front") then
    if pullItemsFromChest("front") then
      returnUnwantedItems("front")
      return true
    end

    log("Kiste vorne leer oder keine Items ziehbar.")
    return true
  end

  if hasInventory("top") then
    if pullItemsFromChest("top") then
      returnUnwantedItems("top")
      return true
    end

    log("Kiste oben leer oder keine Items ziehbar.")
    return true
  end

  log("Keine Kiste vorne oder oben.")
  return false
end

local function patrolOnce()
  local moved = 0

  processAvailableChest()

  for step=1,PATROL_DISTANCE do
    if hasInventory("front") then
      log("Vorne steht eine Kiste. Bleibe an dieser Position.")
      break
    end

    if not forwardStrict() then
      break
    end

    moved = moved + 1
    log("Position im Gang: "..moved.." / "..PATROL_DISTANCE)
    processAvailableChest()
  end

  turnAround()

  for _=1,moved do
    if not forwardStrict() then
      error("Rueckweg zur Startposition blockiert.")
    end
  end

  turnAround()

  if not unloadAtStart() then
    error("Entladen fehlgeschlagen.")
  end
end

log("Start. Oben am Start = Fuel, vorne/oben = Ore-Kisten, unten = Enrichment.")
refuelFromTop()
alignToMarker()

while true do
  refuelFromTop()
  patrolOnce()
  sleep(2)
end
