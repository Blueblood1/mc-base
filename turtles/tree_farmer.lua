-- Networked Tree Farmer Turtle Program
-- Grows and harvests 2x2 spruce trees with bonemeal automation

local Network = require("network")
local TurtleLib = require("turtle")
local Updater = require("updater")

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

-- Refuel from the last slot
local function refuel()
    turtle.select(FUEL_SLOT)
    if turtle.getItemCount(FUEL_SLOT) > 0 then
        turtle.refuel(1)
    end
end

-- Load fuel from chest on the right
local function loadFuel()
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
        print("FUEL LOCK: Critical fuel level (" .. fuel.percent .. "%)")
        sendAlert("FUEL LOCK: Critical fuel level, waiting for refuel")
        status.lastError = "FUEL LOCK: Critical fuel"
        sendTelemetry()
        
        while fuel.percent <= 5 do
            print("Fuel: " .. fuel.percent .. "% - Waiting for refuel...")
            
            turtle.select(FUEL_SLOT)
            turtle.turnRight()
            turtle.suck()
            turtle.turnLeft()
            refuel()
            
            fuel = TurtleLib.getFuelStatus()
            sendTelemetry()
            checkCommands()
            sleep(5)
        end
        
        print("Fuel lock released: " .. fuel.percent .. "%")
        sendAlert("Fuel lock released: " .. fuel.percent .. "%")
        status.lastError = nil
        sendTelemetry()
    end
end

-- Load saplings from chest on the left
local function loadSaplings()
    turtle.turnLeft()
    for slot = SAPLING_SLOTS_START, SAPLING_SLOTS_END do
        turtle.select(slot)
        turtle.suck(16)
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
    
    -- Move forward one
    if not turtle.forward() then
        sendAlert("Blocked while moving to planting position")
        status.blockedCount = status.blockedCount + 1
        sleep(5)
        turtle.forward()
    end
    refuel()
    
    -- Place sapling at position 1 (front-right)
    turtle.select(SAPLING_SLOTS_START)
    turtle.placeDown()
    
    -- Move left to position 2 (front-left)
    turtle.turnLeft()
    turtle.forward()
    turtle.turnRight()
    refuel()
    
    -- Place sapling at position 2
    turtle.select(SAPLING_SLOTS_START + 1)
    turtle.placeDown()
    
    -- Move back to position 3 (back-left)
    turtle.back()
    refuel()
    
    -- Place sapling at position 3
    turtle.select(SAPLING_SLOTS_START + 2)
    turtle.placeDown()
    
    -- Move right to position 4 (back-right)
    turtle.turnRight()
    turtle.forward()
    turtle.turnLeft()
    refuel()
    
    -- Place sapling at position 4
    turtle.select(SAPLING_SLOTS_START + 3)
    turtle.placeDown()
    
    -- Return to front-right position (position 1)
    turtle.forward()
    refuel()
    
    print("2x2 saplings planted")
end

-- Use bonemeal until tree grows
local function growTree()
    state.phase = "growing"
    saveState()
    
    print("Growing tree with bonemeal...")
    local attempts = 0
    local maxAttempts = 200
    
    while isSapling() and attempts < maxAttempts do
        -- Find a bonemeal slot
        local bonemealSlot = nil
        for slot = BONEMEAL_SLOTS_START, BONEMEAL_SLOTS_END do
            if turtle.getItemCount(slot) > 0 then
                bonemealSlot = slot
                break
            end
        end
        
        if not bonemealSlot then
            sendAlert("Out of bonemeal while growing tree")
            status.lastError = "Out of bonemeal"
            return false
        end
        
        turtle.select(bonemealSlot)
        turtle.place()
        status.bonemealUsed = status.bonemealUsed + 1
        attempts = attempts + 1
        sleep(0.5)
        
        checkCommands()
        
        if attempts % 20 == 0 then
            sendTelemetry()
        end
    end
    
    if attempts >= maxAttempts then
        sendAlert("Tree failed to grow after " .. maxAttempts .. " bonemeal")
        status.lastError = "Tree growth failed"
        return false
    end
    
    print("Tree grown! Used " .. attempts .. " bonemeal")
    return true
end

-- Harvest the tree (2x2 logs going upward)
local function harvestTree()
    state.phase = "harvesting"
    state.treeHeight = 0
    saveState()
    
    print("Harvesting tree...")
    local logsThisTree = 0
    
    -- Mine upward through the tree
    while true do
        local success, data = turtle.inspectUp()
        
        -- Check if there's a log above
        if success and data.name and data.name:find("log") then
            turtle.digUp()
            turtle.up()
            state.treeHeight = state.treeHeight + 1
            logsThisTree = logsThisTree + 1
            saveState()
            refuel()
            checkCommands()
        else
            -- No more logs above, we're done going up
            break
        end
        
        if state.treeHeight % 5 == 0 then
            sendTelemetry()
        end
    end
    
    print("Reached top at height: " .. state.treeHeight)
    
    -- Now mine the other 3 logs in the 2x2 at each level going down
    for height = state.treeHeight, 1, -1 do
        -- We're at front-right position, mine the other 3 positions
        
        -- Move left to front-left
        turtle.turnLeft()
        local success, data = turtle.inspect()
        if success and data.name and data.name:find("log") then
            turtle.dig()
            logsThisTree = logsThisTree + 1
        end
        turtle.forward()
        turtle.turnRight()
        refuel()
        
        -- Mine back-left
        success, data = turtle.inspect()
        if success and data.name and data.name:find("log") then
            turtle.dig()
            logsThisTree = logsThisTree + 1
        end
        
        -- Move right to back-right
        turtle.turnRight()
        turtle.forward()
        turtle.turnLeft()
        refuel()
        
        -- Mine back-right
        success, data = turtle.inspect()
        if success and data.name and data.name:find("log") then
            turtle.dig()
            logsThisTree = logsThisTree + 1
        end
        
        -- Return to front-right position
        turtle.forward()
        refuel()
        
        -- Descend one level
        if height > 1 then
            turtle.down()
        end
        
        checkCommands()
    end
    
    print("Harvested " .. logsThisTree .. " logs")
    status.logsCollected = status.logsCollected + logsThisTree
    status.treesHarvested = status.treesHarvested + 1
    
    -- Return to starting position (back one from planting area)
    turtle.back()
    refuel()
    
    clearState()
    state.phase = "idle"
    state.treeHeight = 0
    status.lastError = nil
end

-- Deposit items into chests
local function depositItems()
    state.phase = "depositing"
    saveState()
    
    print("Depositing items...")
    
    -- Deposit logs and other items to left chest (sapling chest)
    turtle.turnLeft()
    for slot = SAPLING_SLOTS_START, BONEMEAL_SLOTS_END do
        turtle.select(slot)
        local item = turtle.getItemDetail(slot)
        if item and not item.name:find("sapling") and not item.name:find("bone_meal") then
            turtle.drop()
        end
    end
    turtle.turnRight()
    
    print("Items deposited")
end

-- Install startup file
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        print("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start tree farmer on boot\n')
        file.write('-- Update before running\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting tree farmer daemon...")\n')
        file.write('shell.run("tree_farmer")\n')
        file.close()
        print("Startup file installed!")
        return true
    end
    return false
end

-- Main program loop
local function mainLoop()
    while true do
        print("Starting fresh cycle...")
        
        checkFuelLock()
        
        -- Load resources
        print("Loading fuel...")
        loadFuel()
        
        print("Loading saplings...")
        loadSaplings()
        
        print("Loading bonemeal...")
        loadBonemeal()
        
        -- Check if we have required resources
        if not hasSaplings() then
            print("No saplings available, waiting...")
            sendAlert("No saplings available, waiting for resupply")
            status.lastError = "No saplings available"
            sendTelemetry()
            
            for i = 1, 60 do
                checkCommands()
                sleep(1)
            end
        elseif not hasBonemeal() then
            print("No bonemeal available, waiting...")
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
            print("Planting 2x2 saplings...")
            placeSaplings()
            
            print("Growing tree...")
            local grown = growTree()
            
            if grown then
                print("Harvesting tree...")
                harvestTree()
                
                print("Depositing items...")
                depositItems()
                
                print("Tree farming cycle complete!")
                sendTelemetry()
            else
                -- Growth failed, clean up saplings and try again
                print("Growth failed, cleaning up...")
                for i = 1, 4 do
                    turtle.digDown()
                end
                turtle.back()
                refuel()
            end
            
            sleep(2)
        end
    end
end

-- Main program
local function main()
    print("Networked Tree Farmer Starting...")
    
    -- Initialize network
    if not Network.init() then
        print("Warning: No modem found! Running in offline mode.")
    else
        print("Network initialized")
        if not os.getComputerLabel() then
            os.setComputerLabel(TURTLE_NAME)
        end
    end
    
    installStartup()
    
    -- Check if we're resuming from a saved state
    local resuming = loadState()
    
    if resuming then
        print("Resuming from saved state...")
        print("Phase: " .. state.phase)
        sendTelemetry()
        
        -- Complete the interrupted cycle based on phase
        if state.phase == "harvesting" then
            print("Completing harvest...")
            harvestTree()
            depositItems()
        elseif state.phase == "growing" or state.phase == "planting" then
            print("Restarting growth cycle...")
            -- Try to grow if saplings still there
            if isSapling() then
                growTree()
                harvestTree()
            end
            depositItems()
        end
        
        print("Resumed cycle complete!")
        sendTelemetry()
    end
    
    print("Entering main loop...")
    
    -- Wrap in error handler
    while true do
        local success, err = pcall(mainLoop)
        if not success then
            print("Error in main loop: " .. tostring(err))
            sendAlert("Critical error: " .. tostring(err))
            print("Restarting in 10 seconds...")
            sleep(10)
        end
    end
end

-- Run the program
main()
