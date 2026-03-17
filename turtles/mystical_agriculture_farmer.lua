-- Mystical Agriculture Farmer Turtle
-- Manages seed planting across two star-pattern farms
-- Requests desired config from central, diffs against current state, replants as needed

local Network = require("network")
local TurtleLib = require("turtle")
local Worker = require("worker")
local Updater = require("updater")
local Version = require("version")

-- Debug flag: when true, skips central computer farm state lookup and assumes all slots empty.
-- Useful for testing navigation without a central computer connection.
local DEBUG_ASSUME_EMPTY = false

-- Configuration
local TURTLE_NAME = "MA Farmer"
local FUEL_SLOT = 16
local SEED_SLOTS_START = 1
local SEED_SLOTS_END = 15
local CYCLE_FUEL_REQUIREMENT = 500  -- Covers both farms in one cycle
local CHECK_INTERVAL = 30
local STATE_FILE = "ma_farmer_state.txt"

-- Farm 2 is 17 blocks to the left of farm 1's park position.
local FARM2_OFFSET = 17  -- blocks left from farm 1 park to farm 2 park

-- ---------------------------------------------------------------------------
-- Desired seed configuration per farm
-- Edit and push an update to change what's planted.
-- Total per farm should not exceed TOTAL_SLOTS (36).
-- ---------------------------------------------------------------------------
local FARM_CONFIGS = {
    [1] = {
        ["mysticalagriculture:inferium_seeds"] = 36,
    },
    [2] = {
        ["mysticalagriculture:inferium_seeds"] = 36,
    },
    [3] = {
        ["mysticalagriculture:inferium_seeds"] = 36,
    },
}

-- Shared state for command listener
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Forward declarations
local sendAlert
local sendTelemetry

-- Runtime state (persisted across crashes)
local state = {
    phase = "idle",
    currentSlot = 0,
    currentFarm = 1,
    facing = 0,   -- 0=toward row 1 (forward/north), 1=right (east), 2=back (south), 3=left (west)
    posRow = 10,  -- starts at home row
    posCol = 1,   -- starts at home col
}

local stats = {
    seedsPlanted = 0,
    seedsHarvested = 0,
    cyclesCompleted = 0,
    lastError = nil
}

-- ---------------------------------------------------------------------------
-- Farm Layout
-- ---------------------------------------------------------------------------
-- 9x9 checkerboard-style star farm. Farmland sits on alternating cells.
-- Turtle enters at row 10, col 1, facing toward row 1 (forward = decreasing row).
-- Home position = (row=10, col=1).
--
-- Coordinate system:
--   posRow decreases as turtle moves forward (toward row 1)
--   posCol increases as turtle moves right (toward col 9)
--
-- Farmland positions (row, col) - 36 total:
--   Row 1: cols 3,5,7
--   Row 2: cols 2,4,6,8
--   Row 3: cols 1,3,5,7,9
--   Row 4: cols 2,4,6,8
--   Row 5: cols 1,3,7,9        (centre col 5 is empty - cable)
--   Row 6: cols 2,4,6,8
--   Row 7: cols 1,3,5,7,9
--   Row 8: cols 2,4,6,8
--   Row 9: cols 3,5,7

local SLOT_MAP = {
    -- Row 9 (closest to turtle home, visited first)
    {row=9,  col=3}, {row=9,  col=5}, {row=9,  col=7},
    -- Row 8
    {row=8,  col=2}, {row=8,  col=4}, {row=8,  col=6}, {row=8,  col=8},
    -- Row 7
    {row=7,  col=1}, {row=7,  col=3}, {row=7,  col=5}, {row=7,  col=7}, {row=7, col=9},
    -- Row 6
    {row=6,  col=2}, {row=6,  col=4}, {row=6,  col=6}, {row=6,  col=8},
    -- Row 5 (no centre)
    {row=5,  col=1}, {row=5,  col=3}, {row=5,  col=7}, {row=5,  col=9},
    -- Row 4
    {row=4,  col=2}, {row=4,  col=4}, {row=4,  col=6}, {row=4,  col=8},
    -- Row 3
    {row=3,  col=1}, {row=3,  col=3}, {row=3,  col=5}, {row=3,  col=7}, {row=3, col=9},
    -- Row 2
    {row=2,  col=2}, {row=2,  col=4}, {row=2,  col=6}, {row=2,  col=8},
    -- Row 1 (furthest from home)
    {row=1,  col=3}, {row=1,  col=5}, {row=1,  col=7},
}

local TOTAL_SLOTS = #SLOT_MAP  -- 36

-- Home position (within farm coordinate space)
local HOME_ROW = 10
local HOME_COL = 1

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

local function saveState()
    local f = fs.open(STATE_FILE, "w")
    f.write(textutils.serialize(state))
    f.close()
end

local function loadState()
    if fs.exists(STATE_FILE) then
        local f = fs.open(STATE_FILE, "r")
        local data = f.readAll()
        f.close()
        local loaded = textutils.unserialize(data)
        if loaded then state = loaded; return true end
    end
    return false
end

local function clearState()
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

-- ---------------------------------------------------------------------------
-- Telemetry / Alerts
-- ---------------------------------------------------------------------------

sendTelemetry = function()
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    local data = {
        name      = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
        status    = stats.lastError and "error" or (state.phase == "idle" and "idle" or "working"),
        fuel      = TurtleLib.getFuelStatus(),
        inventory = TurtleLib.getInventoryStatus(),
        task      = { phase = state.phase, farm = state.currentFarm,
                      currentSlot = state.currentSlot, totalSlots = TOTAL_SLOTS },
        stats     = { seedsPlanted = stats.seedsPlanted,
                      seedsHarvested = stats.seedsHarvested,
                      cyclesCompleted = stats.cyclesCompleted },
        error     = stats.lastError,
    }
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, data)
    else
        Network.broadcast(Network.MSG_TYPES.TELEMETRY, data)
    end
end

sendAlert = function(message)
    stats.lastError = message
    Version.log("ALERT: " .. message)
    local payload = {
        name    = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
        message = message,
    }
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, payload)
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, payload)
    end
end

local function checkPause()
    TurtleLib.checkPauseState(sharedState, sendTelemetry)
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

local function turnRight()
    turtle.turnRight()
    state.facing = (state.facing + 1) % 4
    saveState()
end

local function turnLeft()
    turtle.turnLeft()
    state.facing = (state.facing + 3) % 4
    saveState()
end

local function faceDirection(target)
    local diff = (target - state.facing + 4) % 4
    if diff == 1 then turnRight()
    elseif diff == 2 then turnRight(); turnRight()
    elseif diff == 3 then turnLeft()
    end
end

local function stepForward()
    if turtle.forward() then
        if state.facing == 0 then state.posRow = state.posRow - 1
        elseif state.facing == 1 then state.posCol = state.posCol + 1
        elseif state.facing == 2 then state.posRow = state.posRow + 1
        elseif state.facing == 3 then state.posCol = state.posCol - 1
        end
        saveState()
        return true
    end
    sendAlert("Blocked at row=" .. state.posRow .. " col=" .. state.posCol)
    return false
end

-- The centre cell (5,5) is permanently blocked by a cable.
local BLOCK_ROW, BLOCK_COL = 5, 5

local function moveToRow(targetRow)
    local rowDiff = targetRow - state.posRow
    if rowDiff < 0 then
        faceDirection(0)
        for _ = 1, -rowDiff do if not stepForward() then return false end end
    elseif rowDiff > 0 then
        faceDirection(2)
        for _ = 1, rowDiff do if not stepForward() then return false end end
    end
    return true
end

local function moveToCol(targetCol)
    local colDiff = targetCol - state.posCol
    if colDiff > 0 then
        faceDirection(1)
        for _ = 1, colDiff do if not stepForward() then return false end end
    elseif colDiff < 0 then
        faceDirection(3)
        for _ = 1, -colDiff do if not stepForward() then return false end end
    end
    return true
end

local function navigateTo(targetRow, targetCol)
    local alreadyOnBlockRow = (state.posRow == BLOCK_ROW)
    local headingToBlockRow = (targetRow == BLOCK_ROW)
    local colCrossesBlock = (state.posCol < BLOCK_COL and targetCol > BLOCK_COL)
                         or (state.posCol > BLOCK_COL and targetCol < BLOCK_COL)
                         or (state.posCol == BLOCK_COL or targetCol == BLOCK_COL)

    local needsDetour = (alreadyOnBlockRow or headingToBlockRow) and colCrossesBlock

    if not needsDetour then
        return moveToRow(targetRow) and moveToCol(targetCol)
    end

    -- Detour via row 6 to safely cross col 5
    local detourRow = BLOCK_ROW + 1
    if not moveToRow(detourRow) then return false end
    if not moveToCol(targetCol) then return false end
    if not moveToRow(targetRow) then return false end
    return true
end

local function returnHome()
    state.phase = "returning"
    saveState()
    navigateTo(HOME_ROW, HOME_COL)
    faceDirection(0)  -- face into farm ready for next cycle
    state.phase = "idle"
    clearState()
end

-- ---------------------------------------------------------------------------
-- Inter-farm travel
-- ---------------------------------------------------------------------------
-- Farm 2 park is FARM2_OFFSET blocks to the LEFT of farm 1 park.
-- At park position the turtle faces direction 0 (into the farm).
-- Left from that perspective is facing=3.

local function travelToFarm2()
    Version.log("Travelling to farm 2...")
    state.currentFarm = 2
    saveState()
    faceDirection(3)  -- face left
    for _ = 1, FARM2_OFFSET do
        if not turtle.forward() then
            sendAlert("Blocked travelling to farm 2")
            return false
        end
    end
    faceDirection(0)  -- face into farm 2
    saveState()
    return true
end

local function travelToFarm1()
    Version.log("Travelling back to farm 1...")
    state.currentFarm = 1
    saveState()
    faceDirection(1)  -- face right (back toward farm 1)
    for _ = 1, FARM2_OFFSET do
        if not turtle.forward() then
            sendAlert("Blocked travelling back to farm 1")
            return false
        end
    end
    faceDirection(0)  -- face into farm 1
    saveState()
    return true
end

-- Farm 3 route from farm 1 park:
--   left 4, forward 15, right 4 → same park orientation as farm 1
local function travelToFarm3()
    Version.log("Travelling to farm 3...")
    state.currentFarm = 3
    saveState()
    faceDirection(3)  -- face left
    for _ = 1, 4 do
        if not turtle.forward() then
            sendAlert("Blocked travelling to farm 3 (left leg)")
            return false
        end
    end
    faceDirection(0)  -- face forward (same as start)
    for _ = 1, 15 do
        if not turtle.forward() then
            sendAlert("Blocked travelling to farm 3 (forward leg)")
            return false
        end
    end
    faceDirection(1)  -- face right
    for _ = 1, 4 do
        if not turtle.forward() then
            sendAlert("Blocked travelling to farm 3 (right leg)")
            return false
        end
    end
    faceDirection(0)  -- face into farm 3
    saveState()
    return true
end

local function travelFromFarm3ToFarm1()
    Version.log("Travelling back to farm 1 from farm 3...")
    state.currentFarm = 1
    saveState()
    faceDirection(3)  -- face left (reverse of right leg)
    for _ = 1, 4 do
        if not turtle.forward() then
            sendAlert("Blocked returning from farm 3 (left leg)")
            return false
        end
    end
    faceDirection(2)  -- face back (reverse of forward leg)
    for _ = 1, 15 do
        if not turtle.forward() then
            sendAlert("Blocked returning from farm 3 (back leg)")
            return false
        end
    end
    faceDirection(1)  -- face right (reverse of left leg)
    for _ = 1, 4 do
        if not turtle.forward() then
            sendAlert("Blocked returning from farm 3 (right leg)")
            return false
        end
    end
    faceDirection(0)  -- face into farm 1
    saveState()
    return true
end

-- ---------------------------------------------------------------------------
-- Seed inventory helpers
-- ---------------------------------------------------------------------------

local function findSeedSlot(seedName)
    for slot = SEED_SLOTS_START, SEED_SLOTS_END do
        local item = turtle.getItemDetail(slot)
        if item and item.name:find(seedName, 1, true) then return slot end
    end
    return nil
end

local function countSeeds(seedName)
    local total = 0
    for slot = SEED_SLOTS_START, SEED_SLOTS_END do
        local item = turtle.getItemDetail(slot)
        if item and item.name:find(seedName, 1, true) then total = total + item.count end
    end
    return total
end

-- Seed chest is directly behind home position (facing=2)
local function loadSeedsFromChest(seedList)
    Version.log("Loading seeds from chest...")
    faceDirection(2)
    for _, entry in ipairs(seedList) do
        local needed = entry.count - countSeeds(entry.name)
        if needed > 0 then
            for slot = SEED_SLOTS_START, SEED_SLOTS_END do
                if turtle.getItemCount(slot) == 0 then
                    turtle.select(slot)
                    local remaining = needed
                    while remaining > 0 do
                        if not turtle.suck(math.min(remaining, 64)) then break end
                        local item = turtle.getItemDetail(slot)
                        if item then remaining = remaining - item.count else break end
                    end
                    break
                end
            end
        end
    end
    faceDirection(0)
end

local function depositSeeds()
    Version.log("Depositing leftover seeds...")
    faceDirection(2)
    for slot = SEED_SLOTS_START, SEED_SLOTS_END do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            turtle.drop()
        end
    end
    faceDirection(0)
end

-- ---------------------------------------------------------------------------
-- Central computer communication
-- ---------------------------------------------------------------------------

local function requestFarmState(farmId)
    if not sharedState.centralId then return nil end

    Network.send(sharedState.centralId, Network.MSG_TYPES.COMMAND, {
        command = "get_farm_state",
        farmId  = farmId,
    })

    local timer = os.startTimer(5)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == timer then
            Version.log("Timeout waiting for farm_state (farm " .. farmId .. ")")
            return nil
        elseif event == "rednet_message" then
            if p3 == Network.PROTOCOL and type(p2) == "table" then
                if p2.type == Network.MSG_TYPES.RESPONSE and p2.data then
                    local d = p2.data
                    if d.command == "farm_state" and d.farmId == farmId then
                        os.cancelTimer(timer)
                        return d.state
                    end
                end
            end
        end
    end
end

local function reportSlotUpdate(farmId, slotIdx, seedName)
    if not sharedState.centralId then return end
    Network.send(sharedState.centralId, Network.MSG_TYPES.COMMAND, {
        command  = "update_farm_slot",
        farmId   = farmId,
        slotIdx  = slotIdx,
        seedName = seedName,
    })
end

-- ---------------------------------------------------------------------------
-- Planting / harvesting at a slot
-- ---------------------------------------------------------------------------

local function harvestCurrentSlot()
    local has, data = turtle.inspectDown()
    if has and data.name then
        local n = data.name
        if not n:find("farmland") and not n:find("dirt") and
           not n:find("accelerator") then
            turtle.digDown()
            stats.seedsHarvested = stats.seedsHarvested + 1
            return true
        end
    end
    return false
end

local function plantSeed(seedName)
    local slot = findSeedSlot(seedName)
    if not slot then
        sendAlert("Seed not in inventory: " .. seedName)
        return false
    end
    -- Always clear the slot before planting
    turtle.digDown()
    turtle.select(slot)
    if turtle.placeDown() then
        stats.seedsPlanted = stats.seedsPlanted + 1
        return true
    end
    Version.log("Could not place " .. seedName .. " (already planted?)")
    return false
end

-- ---------------------------------------------------------------------------
-- Diff and execute
-- ---------------------------------------------------------------------------

local function buildDesiredSlots(desiredConfig)
    local desired = {}
    local remaining = {}
    for k, v in pairs(desiredConfig) do remaining[k] = v end

    for slotIdx = 1, TOTAL_SLOTS do
        for seedName, count in pairs(remaining) do
            if count > 0 then
                desired[slotIdx] = seedName
                remaining[seedName] = count - 1
                break
            end
        end
    end
    return desired
end

local function computeChanges(currentState, desiredConfig)
    local desiredSlots = buildDesiredSlots(desiredConfig)
    local changes = {}

    for slotIdx = 1, TOTAL_SLOTS do
        local current = currentState[slotIdx] or "empty"
        local desired = desiredSlots[slotIdx] or "empty"

        if current ~= desired then
            if current ~= "empty" then
                table.insert(changes, {slotIdx = slotIdx, action = "harvest", seedName = current})
            end
            if desired ~= "empty" then
                table.insert(changes, {slotIdx = slotIdx, action = "plant",   seedName = desired})
            end
        end
    end

    return changes
end

-- Execute changes for a specific farm. farmId is used for slot update reporting.
local function executeChanges(changes, farmId)
    if #changes == 0 then
        Version.log("Farm " .. farmId .. " already configured correctly.")
        return true
    end

    -- Group by slot so we visit each slot once
    local bySlot = {}
    for _, c in ipairs(changes) do
        if not bySlot[c.slotIdx] then bySlot[c.slotIdx] = {} end
        table.insert(bySlot[c.slotIdx], c)
    end

    for slotIdx = 1, TOTAL_SLOTS do
        if bySlot[slotIdx] then
            checkPause()
            local info = SLOT_MAP[slotIdx]
            state.phase = "navigating"
            state.currentSlot = slotIdx
            state.currentFarm = farmId
            saveState()

            Version.log("Farm " .. farmId .. " slot " .. slotIdx .. " -> row=" .. info.row .. " col=" .. info.col)

            if not navigateTo(info.row, info.col) then
                sendAlert("Navigation failed at farm " .. farmId .. " slot " .. slotIdx)
                return false
            end

            for _, change in ipairs(bySlot[slotIdx]) do
                if change.action == "harvest" then
                    state.phase = "harvesting"; saveState()
                    Version.log("Harvesting " .. change.seedName)
                    harvestCurrentSlot()
                    reportSlotUpdate(farmId, slotIdx, "empty")

                elseif change.action == "plant" then
                    state.phase = "planting"; saveState()
                    Version.log("Planting " .. change.seedName)
                    if plantSeed(change.seedName) then
                        reportSlotUpdate(farmId, slotIdx, change.seedName)
                    end
                end
            end

            sendTelemetry()
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Farm entry / exit
-- ---------------------------------------------------------------------------
-- Park position is 2 blocks back and 2 blocks down from the farm entry point.
-- To enter: forward x2, up x2. To exit: returnHome(), down x2, back x2.

local function enterFarm()
    state.phase = "entering"
    saveState()
    Version.log("Entering farm...")
    for _ = 1, 2 do turtle.forward() end
    for _ = 1, 2 do turtle.up() end
    -- Now at farm entry (HOME_ROW, HOME_COL) at working height
    state.posRow = HOME_ROW
    state.posCol = HOME_COL
    saveState()
end

local function exitFarm()
    returnHome()
    Version.log("Exiting farm...")
    for _ = 1, 2 do turtle.down() end
    for _ = 1, 2 do turtle.back() end
    state.phase = "idle"
    saveState()
end

-- ---------------------------------------------------------------------------
-- Work cycle
-- ---------------------------------------------------------------------------

local function workCycle()
    state.phase = "idle"; saveState()

    -- 1. Gather current state for all farms
    local farmStates = {}
    for farmId = 1, 3 do
        if DEBUG_ASSUME_EMPTY then
            Version.log("DEBUG: assuming farm " .. farmId .. " is empty")
            farmStates[farmId] = {}
        else
            local fs_state = requestFarmState(farmId)
            if not fs_state then
                sendAlert("Could not get farm " .. farmId .. " state from central")
                return false
            end
            farmStates[farmId] = fs_state
        end
    end

    -- 2. Compute changes for all farms
    local allChanges = {}
    for farmId = 1, 3 do
        allChanges[farmId] = computeChanges(farmStates[farmId], FARM_CONFIGS[farmId])
        Version.log("Farm " .. farmId .. ": " .. #allChanges[farmId] .. " changes needed")
    end

    local totalChanges = #allChanges[1] + #allChanges[2] + #allChanges[3]
    if totalChanges == 0 then
        Version.log("No changes needed on any farm.")
        stats.cyclesCompleted = stats.cyclesCompleted + 1
        stats.lastError = nil
        sendTelemetry()
        return true
    end

    -- 3. Collect all seeds needed across all farms
    local seedsNeeded = {}
    for farmId = 1, 3 do
        for _, c in ipairs(allChanges[farmId]) do
            if c.action == "plant" then
                seedsNeeded[c.seedName] = (seedsNeeded[c.seedName] or 0) + 1
            end
        end
    end
    local seedLoadList = {}
    for name, count in pairs(seedsNeeded) do
        table.insert(seedLoadList, {name = name, count = count})
    end

    -- 4. Load fuel and seeds at farm 1 park position
    TurtleLib.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendAlert, sendTelemetry)
    checkPause()

    if #seedLoadList > 0 then
        loadSeedsFromChest(seedLoadList)
    end

    -- 5. Work farm 1
    state.currentFarm = 1; saveState()
    enterFarm()
    local ok1 = executeChanges(allChanges[1], 1)
    exitFarm()

    if not ok1 then
        sendAlert("Farm 1 work failed")
        depositSeeds()
        return false
    end

    -- 6. Travel to farm 2 and work it
    if not travelToFarm2() then
        depositSeeds()
        return false
    end

    enterFarm()
    local ok2 = executeChanges(allChanges[2], 2)
    exitFarm()

    if not ok2 then
        sendAlert("Farm 2 work failed")
        travelToFarm1()
        depositSeeds()
        return false
    end

    -- 7. Travel back to farm 1, then on to farm 3
    travelToFarm1()

    if not travelToFarm3() then
        depositSeeds()
        return false
    end

    enterFarm()
    local ok3 = executeChanges(allChanges[3], 3)
    exitFarm()

    -- 8. Travel back to farm 1 park position
    travelFromFarm3ToFarm1()

    -- 9. Deposit leftover seeds
    depositSeeds()

    local ok = ok1 and ok2 and ok3
    if ok then
        stats.cyclesCompleted = stats.cyclesCompleted + 1
        stats.lastError = nil
        Version.log("Cycle complete! All 3 farms done.")
    else
        sendAlert("Farm 3 work failed")
    end

    sendTelemetry()
    return ok
end

-- ---------------------------------------------------------------------------
-- Main loop + startup
-- ---------------------------------------------------------------------------

local function mainLoop()
    while true do
        checkPause()

        local ok, err = pcall(workCycle)
        if not ok then
            sendAlert("Cycle error: " .. tostring(err))
            sleep(15)
        else
            state.phase = "idle"; saveState()
            sendTelemetry()
            Version.log("Idle. Next check in " .. CHECK_INTERVAL .. "s")
            local elapsed = 0
            while elapsed < CHECK_INTERVAL do
                sleep(1); elapsed = elapsed + 1
                checkPause()
            end
        end
    end
end

local function installStartup()
    if not fs.exists("startup.lua") and not fs.exists("startup") then
        local f = fs.open("startup.lua", "w")
        f.write('local Updater = require("updater")\n')
        f.write('Updater.updateLocal()\n')
        f.write('shell.run("mystical_agriculture_farmer")\n')
        f.close()
    end
end

local function main()
    Version.printBanner(TURTLE_NAME)

    if not Network.init() then
        print("ERROR: No modem found. Attach a wireless modem and reboot.")
        return
    end

    if not os.getComputerLabel() then
        os.setComputerLabel(TURTLE_NAME .. " #" .. os.getComputerID())
    end

    installStartup()
    Worker.waitForCentralConnection(sharedState, TURTLE_NAME)
    sendTelemetry()

    if loadState() and state.phase ~= "idle" then
        Version.log("Crash recovery: returning home to reset position...")
        returnHome()
    end

    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert    = sendAlert,
        sendTelemetry = sendTelemetry,
    })

    parallel.waitForAll(
        function()
            local ok, err = pcall(mainLoop)
            if not ok then sendAlert("Fatal: " .. tostring(err)) end
        end,
        commandListener
    )
end

main()
