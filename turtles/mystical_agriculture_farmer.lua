-- Mystical Agriculture Farmer Turtle
-- Manages seed planting across a star-pattern farm
-- Requests desired config from central, diffs against current state, replants as needed

local Network = require("network")
local TurtleLib = require("turtle")
local Worker = require("worker")
local Updater = require("updater")
local Version = require("version")

-- Configuration
local TURTLE_NAME = "MA Farmer"
local FARM_ID = 1                   -- Which farm this turtle manages (1-4)
local FUEL_SLOT = 16
local SEED_SLOTS_START = 1
local SEED_SLOTS_END = 15
local CYCLE_FUEL_REQUIREMENT = 300
local CHECK_INTERVAL = 30           -- Seconds between config checks when idle
local STATE_FILE = "ma_farmer_state.txt"

-- ---------------------------------------------------------------------------
-- Desired seed configuration - edit this and push an update to change the farm
-- Keys are seed item names (partial match is fine), values are slot counts.
-- Total should not exceed TOTAL_SLOTS (36).
-- Example: all fire seeds
--   DESIRED_CONFIG = { ["mysticalagriculture:fire_seeds"] = 36 }
-- Example: mixed farm
--   DESIRED_CONFIG = {
--       ["mysticalagriculture:fire_seeds"]  = 16,
--       ["mysticalagriculture:water_seeds"] = 20,
--   }
-- ---------------------------------------------------------------------------
local DESIRED_CONFIG = {
    ["mysticalagriculture:dirt_seeds"] = 36,
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
--   Row 5: cols 1,3,7,9        (centre col 5 is empty)
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

-- Home position
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
        task      = { phase = state.phase, farmId = FARM_ID,
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
    -- Shouldn't happen at elevation, but handle gracefully
    sendAlert("Blocked at row=" .. state.posRow .. " col=" .. state.posCol)
    return false
end

-- Cells that are physically blocked and cannot be entered
local BLOCKED = {
    [{5, 5}] = true,  -- centre cable
}
local function isBlocked(row, col)
    for _, b in ipairs({{5, 5}}) do
        if b[1] == row and b[2] == col then return true end
    end
    return false
end

local function navigateTo(targetRow, targetCol)
    -- Determine if row-first path would pass through a blocked cell.
    -- Row-first means we travel along col=state.posCol until we hit targetRow,
    -- so the intermediate cell at (targetRow, state.posCol) must not be blocked.
    -- Col-first means we travel along row=state.posRow until we hit targetCol,
    -- so the intermediate cell at (state.posRow, targetCol) must not be blocked.
    local rowFirstBlocked = isBlocked(targetRow, state.posCol)
    local colFirstBlocked = isBlocked(state.posRow, targetCol)

    -- Choose order: prefer row-first unless it's blocked
    local doRowFirst = not rowFirstBlocked

    -- If both are blocked we need a two-step detour via a safe waypoint.
    -- In practice with only one blocked cell this shouldn't happen, but handle it.
    if rowFirstBlocked and colFirstBlocked then
        -- Detour: move to (state.posRow, targetCol-1) then (targetRow, targetCol)
        -- or any adjacent safe cell - pick col offset by 1
        local detourCol = targetCol + (targetCol <= state.posCol and 1 or -1)
        navigateTo(targetRow, detourCol)
        navigateTo(targetRow, targetCol)
        return true
    end

    local function moveRow()
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

    local function moveCol()
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

    if doRowFirst then
        return moveRow() and moveCol()
    else
        return moveCol() and moveRow()
    end
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

-- Seed chest is directly behind home position
local function loadSeedsFromChest(seedList)
    Version.log("Loading seeds from chest...")
    faceDirection(2)  -- face behind (seed chest)
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

local function requestFromCentral(command, responseCommand, timeout)
    timeout = timeout or 5
    if not sharedState.centralId then return nil end

    Network.send(sharedState.centralId, Network.MSG_TYPES.COMMAND, {
        command = command,
        farmId  = FARM_ID,
    })

    local timer = os.startTimer(timeout)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == timer then
            Version.log("Timeout waiting for " .. responseCommand)
            return nil
        elseif event == "rednet_message" then
            if p3 == Network.PROTOCOL and type(p2) == "table" then
                if p2.type == Network.MSG_TYPES.RESPONSE and p2.data then
                    local d = p2.data
                    if d.command == responseCommand and d.farmId == FARM_ID then
                        os.cancelTimer(timer)
                        return d
                    end
                end
            end
        end
    end
end

local function requestFarmState()
    local resp = requestFromCentral("get_farm_state", "farm_state")
    return resp and resp.state or nil
end

local function reportSlotUpdate(slotIdx, seedName)
    if not sharedState.centralId then return end
    Network.send(sharedState.centralId, Network.MSG_TYPES.COMMAND, {
        command  = "update_farm_slot",
        farmId   = FARM_ID,
        slotIdx  = slotIdx,
        seedName = seedName,
    })
end

-- ---------------------------------------------------------------------------
-- Planting / harvesting at a slot
-- ---------------------------------------------------------------------------

-- Turtle is positioned directly above the farmland block
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

-- Build desired slot assignment from config {seedName = count}
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

local function executeChanges(changes)
    if #changes == 0 then
        Version.log("Farm already configured correctly.")
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
            saveState()

            Version.log("Slot " .. slotIdx .. " -> row=" .. info.row .. " col=" .. info.col)

            if not navigateTo(info.row, info.col) then
                sendAlert("Navigation failed at slot " .. slotIdx)
                return false
            end

            for _, change in ipairs(bySlot[slotIdx]) do
                if change.action == "harvest" then
                    state.phase = "harvesting"; saveState()
                    Version.log("Harvesting " .. change.seedName)
                    harvestCurrentSlot()
                    reportSlotUpdate(slotIdx, "empty")

                elseif change.action == "plant" then
                    state.phase = "planting"; saveState()
                    Version.log("Planting " .. change.seedName)
                    if plantSeed(change.seedName) then
                        reportSlotUpdate(slotIdx, change.seedName)
                    end
                end
            end

            sendTelemetry()
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Work cycle
-- ---------------------------------------------------------------------------

local function workCycle()
    state.phase = "idle"; saveState()

    local currentState = requestFarmState()
    if not currentState then
        sendAlert("Could not get farm state from central")
        return false
    end

    local changes = computeChanges(currentState, DESIRED_CONFIG)

    if #changes == 0 then
        Version.log("No changes needed.")
        stats.cyclesCompleted = stats.cyclesCompleted + 1
        stats.lastError = nil
        sendTelemetry()
        return true
    end

    Version.log(#changes .. " changes needed.")

    -- Collect seeds we need to load
    local seedsNeeded = {}
    for _, c in ipairs(changes) do
        if c.action == "plant" then
            seedsNeeded[c.seedName] = (seedsNeeded[c.seedName] or 0) + 1
        end
    end
    local seedLoadList = {}
    for name, count in pairs(seedsNeeded) do
        table.insert(seedLoadList, {name = name, count = count})
    end

    TurtleLib.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendAlert, sendTelemetry)
    checkPause()

    if #seedLoadList > 0 then
        loadSeedsFromChest(seedLoadList)
    end

    local ok = executeChanges(changes)

    returnHome()
    depositSeeds()

    if ok then
        stats.cyclesCompleted = stats.cyclesCompleted + 1
        stats.lastError = nil
        Version.log("Cycle complete!")
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
