-- Networked Tree Farmer Turtle Program
-- Grows and harvests 2x2 spruce trees with bonemeal automation

local Network = require("network")
local TurtleLib = require("turtle")
local Updater = require("updater")

-- Try to load version, but don't fail if it doesn't exist
local Version = nil
pcall(function()
    Version = require("version")
end)

-- Logging helper - always uses version prefix
local function log(message)
    local build = "?"
    if Version then
        build = tostring(Version.get())
    end
    print("[v" .. build .. "] " .. message)
end

-- Configuration
local FUEL_SLOT = 16
local SAPLING_SLOTS_START = 1
local SAPLING_SLOTS_END = 4
local BONEMEAL_SLOTS_START = 5
local BONEMEAL_SLOTS_END = 15
local STATE_FILE = "tree_farmer_state.txt"
local TELEMETRY_INTERVAL = 10
local TURTLE_NAME = "Tree Farmer"

-- Central computer ID (will be discovered)
local centralId = nil

-- Operating mode
local operatingMode = nil -- nil = not connected, "running" or "paused"
local stopRequested = false
local centralConnected = false

-- Wait for initial connection and mode from central
local function waitForCentralConnection()
    log("Waiting for connection to central computer...")
    log("Requesting initial mode...")
    
    while not centralConnected do
        -- Try to find central
        if not centralId then
            centralId = Network.lookup("central")
        end
        
        -- Request our mode
        if centralId then
            Network.send(centralId, Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = "Tree Farmer #" .. os.getComputerID()
            })
        else
            Network.broadcast(Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = "Tree Farmer #" .. os.getComputerID()
            })
        end
        
        -- Wait for response
        local timeout = os.startTimer(3)
        while true do
            local event = os.pullEvent()
            
            if event == "timer" then
                log("No response, retrying...")
                break
            elseif event == "rednet_message" then
                local senderId, msgType, data = Network.receive(0)
                if senderId and msgType == Network.MSG_TYPES.COMMAND then
                    if data.command == "set_mode" and data.mode then
                        operatingMode = data.mode
                        centralId = senderId
                        centralConnected = true
                        log("Connected to central! Mode: " .. operatingMode)
                        os.cancelTimer(timeout)
                        return
                    end
                end
            end
        end
        
        sleep(2)
    end
end

-- Command listener for parallel execution
local function commandListener()
    while not stopRequested do
        local senderId, msgType, data = Network.receive(1)
        if senderId and msgType == Network.MSG_TYPES.COMMAND then
            if data.command == "report_status" then
                sendTelemetry()
            elseif data.command == "set_mode" then
                local oldMode = operatingMode
                operatingMode = data.mode or "running"
                centralId = senderId
                centralConnected = true
                if oldMode ~= operatingMode then
                    sendAlert("Mode changed: " .. tostring(oldMode) .. " -> " .. operatingMode)
                end
                -- Send acknowledgment
                Network.send(senderId, Network.MSG_TYPES.RESPONSE, {
                    ack = true,
                    command = "set_mode",
                    mode = operatingMode
                })
            elseif data.command == "stop" then
                sendAlert("Received stop command")
                stopRequested = true
            elseif data.command == "update" then
                sendAlert("Received update command, updating...")
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
                sleep(2)
                os.reboot()
            end
        end
    end
end

-- State tracking
local state = {
    phase = "idle",
    treeHeight = 0
}

-- Status tracking
local status = {
    lastError = nil,
    blockedCount = 0,
    bonemealUsed = 0,
    treesHarvested = 0,
    logsCollected = 0
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
            treeHeight = state.treeHeight
        },
        stats = {
            bonemealUsed = status.bonemealUsed,
            treesHarvested = status.treesHarvested,
            logsCollected = status.logsCollected
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
        Network.send(centralId, Network.MSG_TYPES.ALERT, {
            name = TURTLE_NAME,
            message = message
        })
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, {
            name = TURTLE_NAME,
            message = message
        })
    end
end

-- Check for commands from central
local function checkCommands()
    local senderId, msgType, data = Network.receive(0.1)
    if senderId and msgType == Network.MSG_TYPES.COMMAND then
        if data.command == "report_status" then
            sendTelemetry()
        elseif data.command == "set_mode" then
            operatingMode = data.mode or "running"
            sendAlert("Mode set to: " .. operatingMode)
        elseif data.command == "stop" then
            sendAlert("Received stop command")
            error("Stopped by central command")
        elseif data.command == "update" then
            sendAlert("Received update command, updating...")
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
            sleep(2)
            os.reboot()
        end
    end
end

-- Check if paused and wait until resumed
local function checkPauseState()
    checkCommands()
    
    while operatingMode == "paused" do
        log("Paused - waiting for resume...")
        sendTelemetry()
        sleep(2)
        checkCommands()
    end
end

-- Refuel from the last slot (only if it's actually fuel)
local function refuel()
    turtle.select(FUEL_SLOT)
    local item = turtle.getItemDetail(FUEL_SLOT)
    if item and turtle.getItemCount(FUEL_SLOT) > 0 then
        -- Only refuel if it's not a sapling or bonemeal
        if not item.name:find("sapling") and not item.name:find("bone") then
            turtle.refuel(1)
        end
    end
end

-- Load fuel from chest on the right
local function loadFuel()
    -- First, ensure sapling and bonemeal slots are empty by returning items
    turtle.turnLeft()
    for slot = SAPLING_SLOTS_START, BONEMEAL_SLOTS_END do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            local item = turtle.getItemDetail(slot)
            if item and item.name:find("sapling") then
                turtle.drop()
            end
        end
    end
    turtle.turnRight()
    
    -- Return bonemeal to back chest
    turtle.turnRight()
    turtle.turnRight()
    for slot = BONEMEAL_SLOTS_START, BONEMEAL_SLOTS_END do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            local item = turtle.getItemDetail(slot)
            if item and item.name:find("bone") then
                turtle.drop()
            end
        end
    end
    turtle.turnRight()
    turtle.turnRight()
    
    -- Now load fuel safely
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
        log("FUEL LOCK: Critical fuel level (" .. fuel.percent .. "%)")
        sendAlert("FUEL LOCK: Critical fuel level, waiting for refuel")
        status.lastError = "FUEL LOCK: Critical fuel"
        sendTelemetry()
        
        while fuel.percent <= 5 do
            log("Fuel: " .. fuel.percent .. "% - Waiting for refuel...")
            
            -- Try to load fuel from chest
            turtle.turnRight()
            turtle.select(FUEL_SLOT)
            turtle.suck()
            turtle.turnLeft()
            
            -- Try to refuel if we got something
            if turtle.getItemCount(FUEL_SLOT) > 0 then
                turtle.refuel()
            end
            
            fuel = TurtleLib.getFuelStatus()
            sendTelemetry()
            checkCommands()
            sleep(5)
        end
        
        log("Fuel lock released: " .. fuel.percent .. "%")
        sendAlert("Fuel lock released: " .. fuel.percent .. "%")
        status.lastError = nil
        sendTelemetry()
    end
end

-- Load saplings from chest on the left
local function loadSaplings()
    turtle.turnLeft()
    -- Only load into the 4 sapling slots
    for slot = SAPLING_SLOTS_START, SAPLING_SLOTS_END do
        turtle.select(slot)
        turtle.suck(1) -- Only take 1 sapling per slot
    end
    turtle.turnRight()
end

-- Load bonemeal from chest behind
local function loadBonemeal()
    turtle.turnRight()
    turtle.turnRight()
    for slot = BONEMEAL_SLOTS_START, BONEMEAL_SLOTS_END do
        turtle.select(slot)
        turtle.suck(64)
    end
    turtle.turnRight()
    turtle.turnRight()
end

-- Check if we have saplings
local function hasSaplings()
    for slot = SAPLING_SLOTS_START, SAPLING_SLOTS_END do
        if turtle.getItemCount(slot) > 0 then
            return true
        end
    end
    return false
end

-- Check if we have bonemeal
local function hasBonemeal()
    for slot = BONEMEAL_SLOTS_START, BONEMEAL_SLOTS_END do
        if turtle.getItemCount(slot) > 0 then
            return true
        end
    end
    return false
end

-- Check if block in front is a sapling
local function isSapling()
    local success, data = turtle.inspect()
    if success and data.name then
        return data.name:find("sapling") ~= nil
    end
    return false
end

-- Place 2x2 saplings
local function placeSaplings()
    state.phase = "planting"
    saveState()
    
    -- Move forward three times
    for i = 1, 3 do
        if not turtle.forward() then
            sendAlert("Blocked while moving to planting position (step " .. i .. ")")
            status.blockedCount = status.blockedCount + 1
            sleep(5)
            turtle.forward()
        end
    end
    
    -- Turn right and place sapling (position 1)
    turtle.turnRight()
    turtle.select(SAPLING_SLOTS_START)
    if not turtle.place() then
        log("Failed to place sapling 1")
    end
    
    -- Turn left, move backwards 1, place sapling (position 2)
    turtle.turnLeft()
    turtle.back()
    turtle.select(SAPLING_SLOTS_START + 1)
    if not turtle.place() then
        log("Failed to place sapling 2")
    end
    
    -- Turn right, place sapling in front (position 3)
    turtle.turnRight()
    turtle.select(SAPLING_SLOTS_START + 2)
    if not turtle.place() then
        log("Failed to place sapling 3")
    end
    
    -- Turn left, move backwards 1, place sapling in front (position 4)
    turtle.turnLeft()
    turtle.back()
    turtle.select(SAPLING_SLOTS_START + 3)
    if not turtle.place() then
        log("Failed to place sapling 4")
    end
    
    log("2x2 saplings planted")
end

-- Use bonemeal until tree grows
local function growTree()
    state.phase = "growing"
    saveState()
    
    log("Growing tree with bonemeal...")
    local attempts = 0
    local maxAttempts = 200
    
    -- Switch to bonemeal slot
    local bonemealSlot = nil
    for slot = BONEMEAL_SLOTS_START, BONEMEAL_SLOTS_END do
        if turtle.getItemCount(slot) > 0 then
            bonemealSlot = slot
            break
        end
    end
    
    if not bonemealSlot then
        sendAlert("No bonemeal available")
        status.lastError = "No bonemeal"
        return false
    end
    
    turtle.select(bonemealSlot)
    
    -- Use bonemeal until we detect a log (not a sapling anymore)
    while attempts < maxAttempts do
        local success, data = turtle.inspect()
        
        -- Check if it's still a sapling
        if success and data.name and data.name:find("sapling") then
            -- Still a sapling, use more bonemeal
            turtle.place()
            status.bonemealUsed = status.bonemealUsed + 1
            attempts = attempts + 1
            sleep(0.5)
            
            -- Check if we need to switch to another bonemeal slot
            if turtle.getItemCount(bonemealSlot) == 0 then
                bonemealSlot = nil
                for slot = BONEMEAL_SLOTS_START, BONEMEAL_SLOTS_END do
                    if turtle.getItemCount(slot) > 0 then
                        bonemealSlot = slot
                        turtle.select(bonemealSlot)
                        break
                    end
                end
                
                if not bonemealSlot then
                    sendAlert("Out of bonemeal while growing tree")
                    status.lastError = "Out of bonemeal"
                    return false
                end
            end
            
            checkCommands()
            
            if attempts % 20 == 0 then
                sendTelemetry()
            end
        elseif success and data.name and data.name:find("log") then
            -- Tree has grown! We detected a log
            log("Tree grown! Used " .. attempts .. " bonemeal")
            return true
        else
            -- Something else is there or nothing at all
            sleep(0.5)
        end
    end
    
    if attempts >= maxAttempts then
        sendAlert("Tree failed to grow after " .. maxAttempts .. " bonemeal")
        status.lastError = "Tree growth failed"
        return false
    end
    
    return true
end

-- Harvest the tree (2x2 logs going upward)
local function harvestTree()
    state.phase = "harvesting"
    state.treeHeight = 0
    saveState()
    
    log("Harvesting tree...")
    local logsThisTree = 0
    
    -- We're facing the front-left log of the 2x2
    -- Dig it and move into that position
    turtle.dig()
    logsThisTree = logsThisTree + 1
    turtle.forward()
    
    -- Phase 1: Mine upward, clearing 3 columns (above, front, and right side)
    while true do
        local hasLogAbove = false
        local hasLogFront = false
        local hasLogRight = false
        
        -- Check and dig above
        local success, data = turtle.inspectUp()
        if success and data.name and data.name:find("log") then
            turtle.digUp()
            logsThisTree = logsThisTree + 1
            hasLogAbove = true
        end
        
        -- Check and dig in front
        success, data = turtle.inspect()
        if success and data.name and data.name:find("log") then
            turtle.dig()
            logsThisTree = logsThisTree + 1
            hasLogFront = true
        end
        
        -- Check and dig to the right
        turtle.turnRight()
        success, data = turtle.inspect()
        if success and data.name and data.name:find("log") then
            turtle.dig()
            logsThisTree = logsThisTree + 1
            hasLogRight = true
        end
        turtle.turnLeft()
        
        -- If no logs in any of the three directions, we're near the top
        if not hasLogAbove and not hasLogFront and not hasLogRight then
            break
        end
        
        -- Move up for next iteration
        turtle.up()
        state.treeHeight = state.treeHeight + 1
        saveState()
        checkCommands()
        
        if state.treeHeight % 5 == 0 then
            sendTelemetry()
        end
    end
    
    log("Reached near top at height: " .. state.treeHeight)
    
    -- Phase 2: Move forward to access the 4th column area
    turtle.forward()
    
    -- Check if there's wood above us, if so mine upward breaking right side too
    local success, data = turtle.inspectUp()
    if success and data.name and data.name:find("log") then
        -- There's wood above, mine upward breaking right side
        while true do
            -- Dig above
            success, data = turtle.inspectUp()
            if success and data.name and data.name:find("log") then
                turtle.digUp()
                logsThisTree = logsThisTree + 1
            else
                -- No more wood above
                break
            end
            
            -- Move up
            turtle.up()
            state.treeHeight = state.treeHeight + 1
            saveState()
            
            -- Dig to the right
            turtle.turnRight()
            success, data = turtle.inspect()
            if success and data.name and data.name:find("log") then
                turtle.dig()
                logsThisTree = logsThisTree + 1
            end
            turtle.turnLeft()
            
            checkCommands()
        end
    end
    
    -- Now turn right to face the 4th column and mine it going upward
    turtle.turnRight()
    
    -- Break whatever is in front (log or leaves) and move into the 4th column
    if turtle.detect() then
        turtle.dig()
        local success, data = turtle.inspect()
        if success and data.name and data.name:find("log") then
            logsThisTree = logsThisTree + 1
        end
    end
    
    -- Always move forward into the 4th column position
    if not turtle.forward() then
        -- If blocked, dig again and try
        turtle.dig()
        turtle.forward()
    end
    
    -- Mine upward from within the 4th column
    while true do
        local success, data = turtle.inspectUp()
        if success and data.name and data.name:find("log") then
            turtle.digUp()
            logsThisTree = logsThisTree + 1
            turtle.up()
            state.treeHeight = state.treeHeight + 1
            saveState()
            checkCommands()
        else
            -- No more logs above in this column
            break
        end
    end
    
    log("Cleared 4th column, total height: " .. state.treeHeight)
    
    -- Phase 3: Descend back down, breaking any remaining logs below and in front
    for height = state.treeHeight, 1, -1 do
        -- Break any log below before descending
        local success, data = turtle.inspectDown()
        if success and data.name and data.name:find("log") then
            turtle.digDown()
            logsThisTree = logsThisTree + 1
        end
        
        turtle.down()
        
        -- Break any log in front while descending
        success, data = turtle.inspect()
        if success and data.name and data.name:find("log") then
            turtle.dig()
            logsThisTree = logsThisTree + 1
        end
        
        checkCommands()
    end
    
    log("Harvested " .. logsThisTree .. " logs")
    status.logsCollected = status.logsCollected + logsThisTree
    status.treesHarvested = status.treesHarvested + 1
    
    -- Return to starting position
    -- We're in the 4th column facing right
    -- Back up 1 to exit the column, turn left to face original direction, back up 4 blocks
    turtle.back()
    turtle.turnLeft()
    for i = 1, 4 do
        turtle.back()
    end
    
    clearState()
    state.phase = "idle"
    state.treeHeight = 0
    status.lastError = nil
end

-- Deposit items into chests
local function depositItems()
    state.phase = "depositing"
    saveState()
    
    log("Depositing items...")
    
    -- Deposit logs into chest below
    for slot = 1, 16 do
        turtle.select(slot)
        local item = turtle.getItemDetail(slot)
        if item and item.name:find("log") then
            turtle.dropDown()
        end
    end
    
    -- Return any leftover saplings to left chest
    turtle.turnLeft()
    for slot = SAPLING_SLOTS_START, SAPLING_SLOTS_END do
        turtle.select(slot)
        local item = turtle.getItemDetail(slot)
        if item and item.name:find("sapling") then
            turtle.drop()
        end
    end
    turtle.turnRight()
    
    -- Return any leftover bonemeal to back chest
    turtle.turnRight()
    turtle.turnRight()
    for slot = BONEMEAL_SLOTS_START, BONEMEAL_SLOTS_END do
        turtle.select(slot)
        local item = turtle.getItemDetail(slot)
        if item and item.name:find("bone") then
            turtle.drop()
        end
    end
    turtle.turnRight()
    turtle.turnRight()
    
    log("Items deposited")
end

-- Install startup file
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start tree farmer on boot\n')
        file.write('-- Update before running\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting tree farmer daemon...")\n')
        file.write('shell.run("tree_farmer")\n')
        file.close()
        log("Startup file installed!")
        return true
    end
    return false
end

-- Main program loop
local function mainLoop()
    while true do
        -- Check if we're paused at the start of each cycle
        checkPauseState()
        
        log("Starting fresh cycle...")
        
        checkFuelLock()
        checkPauseState() -- Check after fuel lock
        
        -- Load resources
        log("Loading fuel...")
        loadFuel()
        checkPauseState() -- Check after loading fuel
        
        log("Loading saplings...")
        loadSaplings()
        checkPauseState() -- Check after loading saplings
        
        log("Loading bonemeal...")
        loadBonemeal()
        checkPauseState() -- Check after loading bonemeal
        
        -- Check if we have required resources
        if not hasSaplings() then
            log("No saplings available, waiting...")
            sendAlert("No saplings available, waiting for resupply")
            status.lastError = "No saplings available"
            sendTelemetry()
            
            for i = 1, 60 do
                checkCommands()
                sleep(1)
            end
        elseif not hasBonemeal() then
            log("No bonemeal available, waiting...")
            sendAlert("No bonemeal available, waiting for resupply")
            status.lastError = "No bonemeal available"
            sendTelemetry()
            
            for i = 1, 60 do
                checkCommands()
                sleep(1)
            end
        else
            status.lastError = nil
            sendTelemetry()
            
            -- Execute tree farming cycle
            log("Planting 2x2 saplings...")
            placeSaplings()
            checkPauseState() -- Check after planting
            
            log("Growing tree...")
            local grown = growTree()
            checkPauseState() -- Check after growing
            
            if grown then
                log("Harvesting tree...")
                harvestTree()
                checkPauseState() -- Check after harvesting
                
                log("Depositing items...")
                depositItems()
                checkPauseState() -- Check after depositing
                
                log("Tree farming cycle complete!")
                sendTelemetry()
            else
                -- Growth failed, clean up saplings and try again
                log("Growth failed, cleaning up...")
                for i = 1, 4 do
                    turtle.digDown()
                end
                turtle.back()
            end
            
            sleep(2)
        end
    end
end

-- Main program
local function main()
    log("Networked Tree Farmer Starting...")
    
    -- Print version if available
    if Version then
        Version.printBanner("Tree Farmer")
        print("")
    end
    
    -- Initialize network
    if not Network.init() then
        log("ERROR: No modem found!")
        log("Cannot connect to central computer.")
        log("Please attach a wireless modem and reboot.")
        return
    else
        log("Network initialized")
        if not os.getComputerLabel() then
            os.setComputerLabel(TURTLE_NAME)
        end
    end
    
    installStartup()
    
    -- Wait for connection to central and get initial mode
    waitForCentralConnection()
    
    -- Check if we're resuming from a saved state
    local resuming = loadState()
    
    if resuming then
        log("Resuming from saved state...")
        log("Phase: " .. state.phase)
        sendTelemetry()
        
        -- Complete the interrupted cycle based on phase
        if state.phase == "harvesting" then
            log("Completing harvest...")
            harvestTree()
            depositItems()
        elseif state.phase == "growing" or state.phase == "planting" then
            log("Restarting growth cycle...")
            -- Try to grow if saplings still there
            if isSapling() then
                growTree()
                harvestTree()
            end
            depositItems()
        end
        
        log("Resumed cycle complete!")
        sendTelemetry()
    end
    
    log("Entering main loop...")
    log("Mode: " .. operatingMode)
    
    -- Wrap in error handler
    while true do
        local success, err = pcall(mainLoop)
        if not success then
            log("Error in main loop: " .. tostring(err))
            sendAlert("Critical error: " .. tostring(err))
            log("Restarting in 10 seconds...")
            sleep(10)
        end
    end
end

-- Run the program
main()
