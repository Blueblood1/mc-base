-- Networked Pig Feeder Turtle Program
-- Feeds pigs in a 9x9 area and reports status to central computer

local Network = require("network")
local Worker = require("worker")
local TurtleLib = require("turtle")
local Updater = require("updater")
local Version = require("version")

-- Configuration
local FUEL_SLOT = 16
local FOOD_SLOTS_START = 1
local FOOD_SLOTS_END = 15
local GRID_SIZE = 9
local STATE_FILE = "pig_feeder_state.txt"
local TELEMETRY_INTERVAL = 10 -- Send telemetry every 10 seconds
local TURTLE_NAME = "Pig Feeder"
local CYCLE_FUEL_REQUIREMENT = 115 -- Fuel needed for complete cycle (9x9 grid + descent/ascent + safety margin)

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

-- State tracking
local state = {
    phase = "idle",
    row = 1,
    col = 1,
    depth = 0
}

-- Status tracking
local status = {
    lastError = nil,
    blockedCount = 0,
    foodUsed = 0,
    cyclesCompleted = 0
}

-- Save state to file
local function saveState()
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Load state from file
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local data = file.readAll()
        file.close()
        state = textutils.unserialize(data)
        return true
    end
    return false
end

-- Clear state file
local function clearState()
    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end
end

-- Send telemetry to central computer
sendTelemetry = function()
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    
    local fuel = TurtleLib.getFuelStatus()
    local inventory = TurtleLib.getInventoryStatus()
    
    local telemetryData = {
        name = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
        status = state.phase == "idle" and "idle" or "working",
        fuel = fuel,
        inventory = inventory,
        task = {
            phase = state.phase,
            row = state.row,
            col = state.col,
            depth = state.depth
        },
        stats = {
            foodUsed = status.foodUsed,
            cyclesCompleted = status.cyclesCompleted,
            blockedCount = status.blockedCount
        }
    }
    
    -- Add error status if applicable
    if status.lastError then
        telemetryData.status = "error"
        telemetryData.error = status.lastError
    elseif fuel.percent < 20 then
        telemetryData.status = "warning"
    end
    
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, telemetryData)
    else
        Network.broadcast(Network.MSG_TYPES.TELEMETRY, telemetryData)
    end
end

-- Send alert to central computer
sendAlert = function(message)
    status.lastError = message
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            name = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
            message = message
        })
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, {
            name = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
            message = message
        })
    end
end

-- Load fuel from chest on the right
local function loadFuel()
    -- Use cleanup function to return food to front chest before loading fuel
    local success, fuelPercent = TurtleLib.loadFuelFromChestWithCleanup("right", {[""] = "front"}, 80)
    
    if not success or fuelPercent < 80 then
        sendAlert("Could not reach 80% fuel (currently " .. fuelPercent .. "%)")
        status.lastError = "Low fuel: " .. fuelPercent .. "%"
    end
end

-- Load food from chest in front
local function loadFood()
    -- Load into any available food slot
    for slot = FOOD_SLOTS_START, FOOD_SLOTS_END do
        turtle.select(slot)
        turtle.suck()
    end
end

-- Check if we have any food in any slot
local function hasFood()
    for slot = FOOD_SLOTS_START, FOOD_SLOTS_END do
        if turtle.getItemCount(slot) > 0 then
            return true
        end
    end
    return false
end

-- Feed pigs below using any food slot
local function feedPigs()
    local fedCount = 0
    
    -- Try each food slot
    for slot = FOOD_SLOTS_START, FOOD_SLOTS_END do
        turtle.select(slot)
        while turtle.getItemCount(slot) > 0 do
            local success = turtle.placeDown()
            if not success then
                break
            end
            fedCount = fedCount + 1
            status.foodUsed = status.foodUsed + 1
            sleep(0.5)
        end
    end
    
    saveState()
    
    -- Periodic telemetry
    if math.random(1, 5) == 1 then
        sendTelemetry()
    end
end

-- Navigate the 9x9 grid
local function navigateGrid()
    -- Descend 3 blocks if needed
    if state.phase == "idle" or state.phase == "descending" then
        state.phase = "descending"
        saveState()
        sendTelemetry()  -- Send telemetry to show we're starting work
        
        while state.depth < 3 do
            if not turtle.down() then
                sendAlert("Blocked while descending at depth " .. state.depth)
                status.blockedCount = status.blockedCount + 1
                sleep(5)
            else
                state.depth = state.depth + 1
                saveState()
            end
        end
        
        state.phase = "navigating"
        saveState()
        sendTelemetry()
    end
    
    -- Navigate the 9x9 grid from current position
    for row = state.row, GRID_SIZE do
        local startCol = (row == state.row) and state.col or 1
        
        for col = startCol, GRID_SIZE do
            state.row = row
            state.col = col
            saveState()
            
            feedPigs()
            
            -- Move forward unless we're at the end of the row
            if col < GRID_SIZE then
                if not turtle.forward() then
                    sendAlert("Blocked at row " .. row .. ", col " .. col)
                    status.blockedCount = status.blockedCount + 1
                    sleep(5)
                    if not turtle.forward() then
                        sendAlert("Still blocked, waiting...")
                        sleep(30)
                    end
                end
            end
        end
        
        -- Turn and move to next row unless we're done
        if row < GRID_SIZE then
            if row % 2 == 1 then
                turtle.turnLeft()
                turtle.forward()
                turtle.turnLeft()
            else
                turtle.turnRight()
                turtle.forward()
                turtle.turnRight()
            end
        end
    end
    
    state.phase = "ascending"
    saveState()
    sendTelemetry()
end

-- Return to starting position
local function returnHome()
    if state.phase ~= "ascending" then
        return
    end
    
    -- Turn around
    turtle.turnRight()
    turtle.turnRight()
    
    -- Go back to first column
    for i = 1, GRID_SIZE - 1 do
        turtle.forward()
    end
    
    -- Turn left to face the starting direction
    turtle.turnLeft()
    
    -- Go back to first row
    for i = 1, GRID_SIZE - 1 do
        turtle.forward()
    end
    
    -- Turn left to face original direction
    turtle.turnLeft()
    
    -- Ascend 3 blocks
    for i = 1, 3 do
        turtle.up()
    end
    
    -- Clear state - we're done
    clearState()
    state.phase = "idle"
    state.row = 1
    state.col = 1
    state.depth = 0
    status.cyclesCompleted = status.cyclesCompleted + 1
    status.lastError = nil
    
    -- Send telemetry to show we're back to idle
    sendTelemetry()
end

-- Install startup file
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        print("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start pig feeder on boot\n')
        file.write('-- Update before running\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting pig feeder daemon...")\n')
        file.write('shell.run("pig_feeder")\n')
        file.close()
        print("Startup file installed!")
        return true
    end
    return false
end

-- Main program loop (runs forever)
local function mainLoop()
    while true do
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        Version.log("Starting fresh cycle...")
        
        -- Ensure we have enough fuel for the complete cycle
        TurtleLib.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendTelemetry, sendAlert)
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        -- Load resources
        Version.log("Loading fuel...")
        loadFuel()
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        Version.log("Loading food...")
        loadFood()
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        -- Check if we have food
        if not hasFood() then
            Version.log("No food available, waiting...")
            sendAlert("No food available, waiting for resupply")
            status.lastError = "No food available"
            sendTelemetry()
            
            -- Wait for resupply
            for i = 1, 60 do -- Wait 60 seconds
                sleep(1)
            end
        else
            status.lastError = nil
            sendTelemetry()
            
            -- Execute feeding cycle
            Version.log("Navigating to pig farm...")
            navigateGrid()
            
            Version.log("Returning home...")
            returnHome()
            
            Version.log("Feeding cycle complete!")
            sendTelemetry()
            
            -- Brief pause before next cycle
            sleep(5)
        end
    end
end

-- Main program
local function main()
    Version.printBanner("Networked Pig Feeder")
    
    -- Initialize network
    if not Network.init() then
        Version.log("Warning: No modem found! Running in offline mode.")
    else
        Version.log("Network initialized")
        -- Set computer label
        if not os.getComputerLabel() then
            os.setComputerLabel(TURTLE_NAME .. "_" .. os.getComputerID())
        end
    end
    
    -- Install startup file
    installStartup()
    
    -- Wait for connection to central and get initial mode
    Worker.waitForCentralConnection(sharedState, TURTLE_NAME)
    
    -- Send initial telemetry
    sendTelemetry()
    
    -- Check if we should be paused before starting work
    if sharedState.operatingMode == "paused" then
        Version.log("Starting in paused mode")
    end
    
    -- Check if we're resuming from a saved state
    local resuming = loadState()
    
    if resuming then
        Version.log("Resuming from saved state...")
        Version.log("Phase: " .. state.phase)
        Version.log("Position: Row " .. state.row .. ", Col " .. state.col)
        sendTelemetry()
        
        -- Check if paused before resuming work
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        -- Complete the interrupted cycle
        if state.phase == "idle" or state.phase == "descending" or state.phase == "navigating" then
            Version.log("Completing interrupted cycle...")
            navigateGrid()
        end
        
        if state.phase == "ascending" then
            Version.log("Returning home...")
            returnHome()
        end
        
        Version.log("Resumed cycle complete!")
        sendTelemetry()
    end
    
    -- Enter main loop (never exits)
    Version.log("Entering main loop...")
    Version.log("Mode: " .. sharedState.operatingMode)
    
    -- Create command listener
    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert = sendAlert,
        sendTelemetry = sendTelemetry
    })
    
    -- Run main loop and command listener in parallel
    parallel.waitForAll(
        function()
            while true do
                local success, err = pcall(mainLoop)
                if not success then
                    Version.log("Error in main loop: " .. tostring(err))
                    sendAlert("Critical error: " .. tostring(err))
                    Version.log("Restarting in 10 seconds...")
                    sleep(10)
                end
            end
        end,
        commandListener
    )
end

-- Run the program
main()
