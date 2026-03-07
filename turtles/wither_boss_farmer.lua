-- Wither Boss Farmer Turtle
-- Builds withers in multiple cells, coordinating with door controller

local Network = require("network")
local Turtle = require("turtle")
local Worker = require("worker")
local Version = require("version")

-- Configuration
local TURTLE_NAME = "Wither Boss Farmer"
local FUEL_SLOT = 1
local SOUL_SAND_SLOT = 2
local SKULL_SLOT = 3  -- Wither skeleton skulls (dirt for testing)
local NUM_CELLS = 2  -- Testing with 2 cells for now
local CYCLE_FUEL_REQUIREMENT = 200  -- Estimated fuel for full cycle (will adjust after testing)

-- Shared state
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false,
    farmComputerId = nil
}

-- Status tracking
local status = {
    currentCell = 0,
    withersBuilt = 0,
    lastError = nil
}

-- Forward declarations
local sendAlert
local sendTelemetry

-- Send telemetry to central computer
sendTelemetry = function()
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    
    local fuel = Turtle.getFuelStatus()
    
    local telemetryData = {
        name = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
        status = sharedState.operatingMode == "running" and "working" or "idle",
        fuel = fuel,
        task = {
            phase = status.currentCell > 0 and ("building_cell_" .. status.currentCell) or "idle",
            currentCell = status.currentCell
        },
        stats = {
            withersBuilt = status.withersBuilt,
            fuelLevel = turtle.getFuelLevel()
        }
    }
    
    if status.lastError then
        telemetryData.status = "error"
        telemetryData.error = status.lastError
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

-- Find the wither boss farm computer
local function findFarmComputer()
    Version.log("Looking up wither_boss_farm...")
    local farmId = Network.lookup("wither_boss_farm")
    
    if not farmId then
        sendAlert("Could not find wither_boss_farm computer!")
        return false
    end
    
    sharedState.farmComputerId = farmId
    Version.log("Found farm computer: " .. farmId)
    return true
end

-- Request door to open
local function openDoor(cellNumber)
    if not sharedState.farmComputerId then
        sendAlert("No farm computer ID!")
        return false
    end
    
    Version.log("Requesting door " .. cellNumber .. " open...")
    Network.send(sharedState.farmComputerId, Network.MSG_TYPES.COMMAND, {
        command = "open_door",
        cell = cellNumber
    })
    
    -- Wait for response
    local senderId, msgType, data = Network.receive(5)
    
    if senderId and msgType == Network.MSG_TYPES.RESPONSE then
        if data.success then
            Version.log("Door " .. cellNumber .. " opened")
            return true
        else
            sendAlert("Failed to open door " .. cellNumber .. ": " .. (data.error or "unknown"))
            return false
        end
    else
        sendAlert("Timeout waiting for door " .. cellNumber .. " response")
        return false
    end
end

-- Request door to close
local function closeDoor(cellNumber)
    if not sharedState.farmComputerId then
        sendAlert("No farm computer ID!")
        return false
    end
    
    Version.log("Requesting door " .. cellNumber .. " close...")
    Network.send(sharedState.farmComputerId, Network.MSG_TYPES.COMMAND, {
        command = "close_door",
        cell = cellNumber
    })
    
    -- Wait for response
    local senderId, msgType, data = Network.receive(5)
    
    if senderId and msgType == Network.MSG_TYPES.RESPONSE then
        if data.success then
            Version.log("Door " .. cellNumber .. " closed")
            return true
        else
            sendAlert("Failed to close door " .. cellNumber .. ": " .. (data.error or "unknown"))
            return false
        end
    else
        sendAlert("Timeout waiting for door " .. cellNumber .. " response")
        return false
    end
end

-- Place soul sand from inventory
local function placeSoulSand()
    turtle.select(SOUL_SAND_SLOT)
    if not turtle.place() then
        sendAlert("Failed to place soul sand!")
        return false
    end
    return true
end

-- Place wither skull from inventory
local function placeSkull()
    turtle.select(SKULL_SLOT)
    if not turtle.place() then
        sendAlert("Failed to place skull!")
        return false
    end
    return true
end

-- Build a wither in the current cell
local function buildWitherInCell(cellNumber)
    Version.log("Building wither in cell " .. cellNumber)
    status.currentCell = cellNumber
    sendTelemetry()  -- Send telemetry on phase change
    
    -- Move forward 2 blocks
    Version.log("Moving forward 2 blocks...")
    for i = 1, 2 do
        if not turtle.forward() then
            sendAlert("Failed to move forward at step " .. i .. "/2")
            return false
        end
    end
    
    -- Check pause state before opening door
    Turtle.checkPauseState(sharedState, sendTelemetry)
    
    -- Request door open
    Version.log("Requesting door " .. cellNumber .. " open...")
    if not openDoor(cellNumber) then
        return false
    end
    
    -- Move forward 4 blocks into cell
    Version.log("Moving into cell (4 blocks)...")
    for i = 1, 4 do
        if not turtle.forward() then
            sendAlert("Failed to move into cell at step " .. i .. "/4")
            return false
        end
    end
    
    -- Request previous door close (if not first cell)
    if cellNumber > 1 then
        Version.log("Closing door " .. (cellNumber - 1) .. "...")
        if not closeDoor(cellNumber - 1) then
            return false
        end
    end
    
    -- Check pause state before building
    Turtle.checkPauseState(sharedState, sendTelemetry)
    
    -- Turn around to face where we came from
    Version.log("Turning around...")
    turtle.turnRight()
    turtle.turnRight()
    
    -- Ascend once (don't place soul sand yet - bottom is last)
    Version.log("Ascending 1 block...")
    if not turtle.up() then
        sendAlert("Failed to ascend")
        return false
    end
    
    -- Turn right
    Version.log("Turning right...")
    turtle.turnRight()
    
    -- Move forward once
    Version.log("Moving to right arm position...")
    if not turtle.forward() then
        sendAlert("Failed to move right")
        return false
    end
    
    -- Turn left and place soul sand
    Version.log("Placing right arm soul sand...")
    turtle.turnLeft()
    if not placeSoulSand() then
        return false
    end
    
    -- Ascend once and place wither skull
    Version.log("Ascending and placing right skull...")
    if not turtle.up() then
        sendAlert("Failed to ascend for skull")
        return false
    end
    if not placeSkull() then
        return false
    end
    
    -- Descend once
    Version.log("Descending...")
    if not turtle.down() then
        sendAlert("Failed to descend")
        return false
    end
    
    -- Turn left
    Version.log("Turning left to center...")
    turtle.turnLeft()
    
    -- Move forward twice
    Version.log("Moving to center (2 blocks)...")
    for i = 1, 2 do
        if not turtle.forward() then
            sendAlert("Failed to move to center at step " .. i .. "/2")
            return false
        end
    end
    
    -- Turn right and place soul sand
    Version.log("Placing center soul sand...")
    turtle.turnRight()
    if not placeSoulSand() then
        return false
    end
    
    -- Ascend once and place wither skull
    Version.log("Ascending and placing center skull...")
    if not turtle.up() then
        sendAlert("Failed to ascend for center skull")
        return false
    end
    if not placeSkull() then
        return false
    end
    
    -- Descend once
    Version.log("Descending from center...")
    if not turtle.down() then
        sendAlert("Failed to descend from center")
        return false
    end
    
    -- Turn right
    Version.log("Turning right to left arm...")
    turtle.turnRight()
    
    -- Move forward once
    Version.log("Moving to left arm position...")
    if not turtle.forward() then
        sendAlert("Failed to move to left position")
        return false
    end
    
    -- Turn left and place soul sand
    Version.log("Placing left arm soul sand...")
    turtle.turnLeft()
    if not placeSoulSand() then
        return false
    end
    
    -- Ascend once and place wither skull
    Version.log("Ascending and placing left skull...")
    if not turtle.up() then
        sendAlert("Failed to ascend for left skull")
        return false
    end
    if not placeSkull() then
        return false
    end
    
    -- Descend twice (back to ground level)
    Version.log("Descending to ground (2 blocks)...")
    for i = 1, 2 do
        if not turtle.down() then
            sendAlert("Failed to descend to ground at step " .. i .. "/2")
            return false
        end
    end
    
    -- Check pause state before opening next door
    Turtle.checkPauseState(sharedState, sendTelemetry)
    
    -- Request next door open
    Version.log("Requesting door " .. (cellNumber + 1) .. " open...")
    if not openDoor(cellNumber + 1) then
        return false
    end
    
    -- Place soul sand (bottom of T)
    Version.log("Placing bottom soul sand...")
    if not placeSoulSand() then
        return false
    end
    
    -- Turn 180
    Version.log("Turning around...")
    turtle.turnRight()
    turtle.turnRight()
    
    -- Move forward 4 blocks (into next cell position)
    Version.log("Moving to next cell (4 blocks)...")
    for i = 1, 4 do
        if not turtle.forward() then
            sendAlert("Failed to move to next cell at step " .. i .. "/4")
            return false
        end
    end
    
    Version.log("Completed cell " .. cellNumber)
    status.withersBuilt = status.withersBuilt + 1
    return true
end

-- Main farming loop
local function mainLoop()
    -- Check pause state
    Turtle.checkPauseState(sharedState, sendTelemetry)
    
    -- Ensure we have enough fuel for the cycle
    Version.log("Checking fuel...")
    Turtle.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendTelemetry, sendAlert)
    
    -- Find the farm computer
    if not findFarmComputer() then
        return
    end
    
    Version.log("Starting wither building sequence...")
    
    -- Build withers in cells
    for cell = 1, NUM_CELLS do
        if not buildWitherInCell(cell) then
            sendAlert("Failed to build wither in cell " .. cell)
            return
        end
        
        sendTelemetry()
    end
    
    Version.log("Completed " .. NUM_CELLS .. " cells!")
    Version.log("Turtle stopped at current position for inspection")
    sendTelemetry()
end

-- Main program
local function main()
    Version.printBanner("Wither Boss Farmer")
    
    -- Initialize network
    if not Network.init() then
        Version.log("ERROR: No modem found!")
        return
    end
    Version.log("Network initialized")
    
    -- Set turtle label
    if not os.getComputerLabel() then
        os.setComputerLabel(TURTLE_NAME .. "_" .. os.getComputerID())
    end
    
    -- Install startup file
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        Version.log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start wither boss farmer on boot\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting wither boss farmer...")\n')
        file.write('shell.run("wither_boss_farmer")\n')
        file.close()
        Version.log("Startup file installed!")
    end
    
    -- Wait for connection to central
    Worker.waitForCentralConnection(sharedState, TURTLE_NAME)
    
    -- Send initial telemetry
    sendTelemetry()
    
    Version.log("Starting main loop...")
    
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
                    Version.log("Error: " .. tostring(err))
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
