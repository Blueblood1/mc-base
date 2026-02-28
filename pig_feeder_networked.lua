-- Networked Pig Feeder Turtle Program
-- Feeds pigs in a 9x9 area and reports status to central computer

local Network = require("lib_network")
local TurtleLib = require("lib_turtle")
local Updater = require("lib_updater")

-- Configuration
local FUEL_SLOT = 16
local FOOD_SLOT = 1
local GRID_SIZE = 9
local STATE_FILE = "pig_feeder_state.txt"
local TELEMETRY_INTERVAL = 10 -- Send telemetry every 10 seconds
local TURTLE_NAME = "Pig Feeder"

-- Central computer ID (will be discovered)
local centralId = nil

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
local function sendTelemetry()
    if not centralId then
        centralId = Network.lookup("central")
    end
    
    local fuel = TurtleLib.getFuelStatus()
    local inventory = TurtleLib.getInventoryStatus()
    
    local telemetryData = {
        name = TURTLE_NAME,
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
    
    if centralId then
        Network.send(centralId, Network.MSG_TYPES.TELEMETRY, telemetryData)
    else
        Network.broadcast(Network.MSG_TYPES.TELEMETRY, telemetryData)
    end
end

-- Send alert to central computer
local function sendAlert(message)
    status.lastError = message
    if centralId then
        Network.send(centralId, Network.MSG_TYPES.ALERT, {message = message})
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, {message = message})
    end
end

-- Check for commands from central
local function checkCommands()
    local senderId, msgType, data = Network.receive(0.1)
    if senderId and msgType == Network.MSG_TYPES.COMMAND then
        if data.command == "report_status" then
            sendTelemetry()
        elseif data.command == "stop" then
            sendAlert("Received stop command")
            error("Stopped by central command")
        elseif data.command == "update" then
            sendAlert("Received update command, updating...")
            -- Update only files that exist locally
            local results = Updater.updateLocal()
            local successCount = 0
            local failCount = 0
            for filename, result in pairs(results) do
                if result.success then
                    successCount = successCount + 1
                else
                    failCount = failCount + 1
                end
            end
            sendAlert("Update complete: " .. successCount .. " success, " .. failCount .. " failed")
            -- Reboot to apply updates
            sleep(2)
            os.reboot()
        end
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
    turtle.select(FUEL_SLOT)
    turtle.turnRight()
    local success = turtle.suck()
    turtle.turnLeft()
    if success then
        refuel()
    else
        sendAlert("Failed to load fuel from chest")
        status.lastError = "No fuel available"
    end
end

-- Load food from chest in front
local function loadFood()
    turtle.select(FOOD_SLOT)
    local success = turtle.suck()
    if not success then
        sendAlert("Failed to load food from chest")
        status.lastError = "No food available"
    end
end

-- Feed pigs below
local function feedPigs()
    turtle.select(FOOD_SLOT)
    local fedCount = 0
    while turtle.getItemCount(FOOD_SLOT) > 0 do
        local success = turtle.placeDown()
        if not success then
            break
        end
        fedCount = fedCount + 1
        status.foodUsed = status.foodUsed + 1
        sleep(0.5)
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
            checkCommands()
            
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
                refuel()
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
            refuel()
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
        refuel()
    end
    
    -- Turn left to face the starting direction
    turtle.turnLeft()
    
    -- Go back to first row
    for i = 1, GRID_SIZE - 1 do
        turtle.forward()
        refuel()
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
end

-- Install startup file
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        print("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start pig feeder on boot\n')
        file.write('-- Update before running\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("lib_updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting pig feeder daemon...")\n')
        file.write('shell.run("pig_feeder_networked")\n')
        file.close()
        print("Startup file installed!")
        return true
    end
    return false
end

-- Main program loop (runs forever)
local function mainLoop()
    while true do
        print("Starting fresh cycle...")
        
        -- Load resources
        print("Loading fuel...")
        loadFuel()
        
        print("Loading food...")
        loadFood()
        
        -- Check if we have food
        if turtle.getItemCount(FOOD_SLOT) == 0 then
            print("No food available, waiting...")
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
            print("Navigating to pig farm...")
            navigateGrid()
            
            print("Returning home...")
            returnHome()
            
            print("Feeding cycle complete!")
            sendTelemetry()
            
            -- Brief pause before next cycle
            sleep(5)
        end
    end
end

-- Main program
local function main()
    print("Networked Pig Feeder Starting...")
    
    -- Initialize network
    if not Network.init() then
        print("Warning: No modem found! Running in offline mode.")
    else
        print("Network initialized")
        -- Set computer label
        if not os.getComputerLabel() then
            os.setComputerLabel(TURTLE_NAME)
        end
    end
    
    -- Install startup file
    installStartup()
    
    -- Check if we're resuming from a saved state
    local resuming = loadState()
    
    if resuming then
        print("Resuming from saved state...")
        print("Phase: " .. state.phase)
        print("Position: Row " .. state.row .. ", Col " .. state.col)
        sendTelemetry()
        
        -- Complete the interrupted cycle
        if state.phase == "idle" or state.phase == "descending" or state.phase == "navigating" then
            print("Completing interrupted cycle...")
            navigateGrid()
        end
        
        if state.phase == "ascending" then
            print("Returning home...")
            returnHome()
        end
        
        print("Resumed cycle complete!")
        sendTelemetry()
    end
    
    -- Enter main loop (never exits)
    print("Entering main loop...")
    mainLoop()
end

-- Run the program
main()
