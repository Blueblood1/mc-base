-- Networked Cow Feeder Turtle Program
-- Feeds cows in a 9x9 area and reports status to central computer

local Network = require("network")
local TurtleLib = require("turtle")
local Updater = require("updater")
local Version = require("version")

-- Configuration
local FUEL_SLOT = 16
local FOOD_SLOTS_START = 1
local FOOD_SLOTS_END = 15
local GRID_SIZE = 9
local STATE_FILE = "cow_feeder_state.txt"
local TELEMETRY_INTERVAL = 10 -- Send telemetry every 10 seconds
local TURTLE_NAME = "Cow Feeder" 

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
    height = 0
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
        name = TURTLE_NAME .. " #" .. os.getComputerID(),
        status = state.phase == "idle" and "idle" or "working",
        fuel = fuel,
        inventory = inventory,
        task = {
            phase = state.phase,
            row = state.row,
            col = state.col,
            height = state.height
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
            name = TURTLE_NAME .. " #" .. os.getComputerID(),
            message = message
        })
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, {
            name = TURTLE_NAME .. " #" .. os.getComputerID(),
            message = message
        })
    end
end

-- Refuel from the last slot
local function refuel()
    turtle.select(FUEL_SLOT)
    if turtle.getItemCount(FUEL_SLOT) > 0 then
        turtle.refuel(1)
    end
end

-- Load fuel from chest on the right
local function loadFuel()
    -- First, dump any food back to food chest (on left)
    turtle.turnLeft()
    for slot = FOOD_SLOTS_START, FOOD_SLOTS_END do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            turtle.drop()
        end
    end
    turtle.turnRight()
    
    -- Now load fuel
    local success, fuelPercent = TurtleLib.loadFuelFromChest("right", 80)
    
    if not success or fuelPercent < 80 then
        sendAlert("Could not reach 80% fuel (currently " .. fuelPercent .. "%)")
        status.lastError = "Low fuel: " .. fuelPercent .. "%"
    end
end

-- Check fuel and enter fuel lock if critically low
local function checkFuelLock()
    local fuel = TurtleLib.getFuelStatus()
    
    if fuel.percent <= 5 then
        Version.log("FUEL LOCK: Critical fuel level (" .. fuel.percent .. "%)")
        sendAlert("FUEL LOCK: Critical fuel level, waiting for refuel")
        status.lastError = "FUEL LOCK: Critical fuel"
        sendTelemetry()
        
        -- Stay in fuel lock until we get above 5%
        while fuel.percent <= 5 do
            Version.log("Fuel: " .. fuel.percent .. "% - Waiting for refuel...")
            
            -- Try to load fuel
            turtle.select(FUEL_SLOT)
            turtle.turnRight()
            turtle.suck()
            turtle.turnLeft()
            refuel()
            
            -- Check fuel again
            fuel = TurtleLib.getFuelStatus()
            
            -- Send telemetry and check commands
            sendTelemetry()
            checkCommands()
            
            sleep(5)
        end
        
        Version.log("Fuel lock released: " .. fuel.percent .. "%")
        sendAlert("Fuel lock released: " .. fuel.percent .. "%")
        status.lastError = nil
        sendTelemetry()
    end
end

-- Load food from chest on the left
local function loadFood()
    turtle.turnLeft()
    -- Load into any available food slot
    for slot = FOOD_SLOTS_START, FOOD_SLOTS_END do
        turtle.select(slot)
        turtle.suck()
    end
    turtle.turnRight()
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

-- Feed cows below using any food slot
local function feedCows()
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

-- Navigate the 9x9 grid (vertical columns)
local function navigateGrid()
    -- Ascend 2 blocks if needed
    if state.phase == "idle" or state.phase == "ascending_start" then
        state.phase = "ascending_start"
        saveState()
        
        while state.height < 2 do
            if not turtle.up() then
                sendAlert("Blocked while ascending at height " .. state.height)
                status.blockedCount = status.blockedCount + 1
                sleep(5)
            else
                state.height = state.height + 1
                saveState()
            end
        end
        
        -- Move forward TWO steps to enter the grid
        for i = 1, 2 do
            if not turtle.forward() then
                sendAlert("Blocked entering grid (step " .. i .. ")")
                status.blockedCount = status.blockedCount + 1
                sleep(5)
                turtle.forward()
            end
        end
        
        state.phase = "navigating"
        saveState()
        sendTelemetry()
    end
    
    -- Navigate the 9x9 grid in vertical columns
    for col = state.col, GRID_SIZE do
        local goingDown = (col % 2 == 1) -- Odd columns go down, even go up
        local startRow = state.row
        
        -- Reset row to correct starting position for new columns
        if col ~= state.col then
            if goingDown then
                startRow = 1 -- Start at top for going down
            else
                startRow = GRID_SIZE -- Start at bottom for going up
            end
        end
        
        if goingDown then
            -- Go down the column (1 to 9)
            for row = startRow, GRID_SIZE do
                state.row = row
                state.col = col
                saveState()
                
                feedCows()
                checkCommands()
                
                -- Move forward unless we're at the end
                if row < GRID_SIZE then
                    if not turtle.forward() then
                        sendAlert("Blocked at row " .. row .. ", col " .. col)
                        status.blockedCount = status.blockedCount + 1
                        sleep(5)
                        if not turtle.forward() then
                            sendAlert("Still blocked, waiting...")
                            sleep(30)
                        end
                    end
                    refuel()
                end
            end
        else
            -- Go up the column (9 to 1)
            for row = startRow, 1, -1 do
                state.row = row
                state.col = col
                saveState()
                
                feedCows()
                checkCommands()
                
                -- Move backward unless we're at the end
                if row > 1 then
                    if not turtle.back() then
                        sendAlert("Blocked at row " .. row .. ", col " .. col)
                        status.blockedCount = status.blockedCount + 1
                        sleep(5)
                        if not turtle.back() then
                            sendAlert("Still blocked, waiting...")
                            sleep(30)
                        end
                    end
                    refuel()
                end
            end
        end
        
        -- Move to next column unless we're done
        if col < GRID_SIZE then
            turtle.turnLeft()
            if not turtle.forward() then
                sendAlert("Blocked moving to next column")
                status.blockedCount = status.blockedCount + 1
                sleep(5)
                turtle.forward()
            end
            turtle.turnRight()
            refuel()
        end
    end
    
    state.phase = "returning"
    saveState()
    sendTelemetry()
end

-- Return to starting position
local function returnHome()
    if state.phase ~= "returning" then
        return
    end
    
    -- After column 9 (odd), we're at row 9, column 9 (front-left of grid)
    -- Still facing forward (toward front of farm)
    
    -- Turn right to face across the columns (toward front-right)
    turtle.turnRight()
    
    -- Go to column 1 (front-right)
    for i = 1, GRID_SIZE - 1 do
        turtle.forward()
        refuel()
    end
    
    -- Now at row 9, column 1 (front-right of grid)
    -- Turn right again to face back toward starting position
    turtle.turnRight()
    
    -- Go back through the grid and exit (8 rows + 2 exit steps = 10 total)
    for i = 1, GRID_SIZE - 1 + 2 do
        turtle.forward()
        refuel()
    end
    
    -- Descend 2 blocks
    for i = 1, 2 do
        turtle.down()
    end
    
    -- Turn around to face the farm again (original orientation)
    turtle.turnRight()
    turtle.turnRight()
    
    -- Clear state - we're done
    clearState()
    state.phase = "idle"
    state.row = 1
    state.col = 1
    state.height = 0
    status.cyclesCompleted = status.cyclesCompleted + 1
    status.lastError = nil
end

-- Install startup file
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        Version.log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start cow feeder on boot\n')
        file.write('-- Update before running\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting cow feeder daemon...")\n')
        file.write('shell.run("cow_feeder")\n')
        file.close()
        Version.log("Startup file installed!")
        return true
    end
    return false
end

-- Main program loop (runs forever)
local function mainLoop()
    while true do
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        Version.log("Starting fresh cycle...")
        
        -- Check fuel lock BEFORE starting cycle
        checkFuelLock()
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
            
            -- Wait and check for commands
            for i = 1, 60 do -- Wait 60 seconds
                checkCommands()
                sleep(1)
            end
        else
            status.lastError = nil
            sendTelemetry()
            
            -- Execute feeding cycle
            Version.log("Navigating to cow farm...")
            navigateGrid()
            
            Version.log("Returning home...")
            returnHome()
            
            Version.log("Feeding cycle complete!")
            status.lastError = nil
            sendTelemetry()
            
            -- Cooldown for breeding timeout (2 minutes = 120 seconds)
            Version.log("Waiting for breeding cooldown (2 minutes)...")
            status.lastError = "Cooldown: waiting for breeding timer"
            sendTelemetry()
            
            for i = 1, 120 do
                checkCommands()
                sleep(1)
                
                -- Send telemetry every 30 seconds during cooldown
                if i % 30 == 0 then
                    sendTelemetry()
                end
            end
            
            status.lastError = nil
            Version.log("Cooldown complete!")
        end
    end
end

-- Main program
local function main()
    Version.printBanner("Networked Cow Feeder")
    
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
    TurtleLib.waitForCentralConnection(sharedState, TURTLE_NAME)
    
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
        if state.phase == "idle" or state.phase == "ascending_start" or state.phase == "navigating" then
            Version.log("Completing interrupted cycle...")
            navigateGrid()
        end
        
        if state.phase == "returning" then
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
    local commandListener = TurtleLib.createCommandListener(sharedState, {
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
