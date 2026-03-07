-- Networked Slayer Turtle Program
-- Attacks mobs continuously in one location

local Network = require("network")
local TurtleLib = require("turtle")
local Updater = require("updater")
local Version = require("version")

-- Configuration
local ATTACK_DELAY = 0.5 -- Delay between attacks in seconds
local TELEMETRY_INTERVAL = 10
local TURTLE_NAME = "Slayer"
local MIN_FREE_SLOTS = 2 -- Dump inventory when free slots drop below this

-- Central computer ID (will be discovered)
local centralId = nil

-- Shared state for command listener
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Status tracking
local status = {
    lastError = nil,
    totalKills = 0,
    sessionKills = 0
}

-- Forward declarations
local sendAlert
local sendTelemetry

-- Send telemetry to central computer
sendTelemetry = function()
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    
    local telemetryData = {
        name = TURTLE_NAME .. " #" .. os.getComputerID(),
        status = sharedState.operatingMode == "paused" and "paused" or "active",
        task = {
            phase = "slaying",
            kills = status.sessionKills,
            totalKills = status.totalKills
        }
    }
    
    -- Add error status if applicable
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

-- Dump inventory into chest below
local function dumpInventory()
    local dumped = false
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            turtle.dropDown()
            dumped = true
        end
    end
    return dumped
end

-- Check if inventory is getting full
local function checkInventory()
    local inventory = TurtleLib.getInventoryStatus()
    
    if inventory.emptySlots <= MIN_FREE_SLOTS then
        Version.log("Inventory full, dumping items...")
        if dumpInventory() then
            Version.log("Inventory dumped")
        end
    end
end

-- Main slaying loop
local function mainLoop()
    local lastTelemetry = os.epoch("utc")
    
    while true do
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        -- Check inventory periodically
        checkInventory()
        
        -- Attack
        if turtle.attack() then
            status.sessionKills = status.sessionKills + 1
            status.totalKills = status.totalKills + 1
        end
        
        -- Send telemetry periodically
        local now = os.epoch("utc")
        if (now - lastTelemetry) > (TELEMETRY_INTERVAL * 1000) then
            sendTelemetry()
            lastTelemetry = now
        end
        
        -- Small delay between attacks
        sleep(ATTACK_DELAY)
    end
end

-- Install startup file
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        Version.log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start slayer on boot\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting slayer...")\n')
        file.write('shell.run("slayer")\n')
        file.close()
        Version.log("Startup file installed!")
        return true
    end
    return false
end

-- Main program
local function main()
    Version.printBanner("Networked Slayer")
    
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
    
    -- Install startup if needed
    installStartup()
    
    -- Wait for connection to central and get initial mode
    TurtleLib.waitForCentralConnection(sharedState, TURTLE_NAME)
    
    -- Send initial telemetry
    sendTelemetry()
    
    -- Check if we should be paused before starting work
    if sharedState.operatingMode == "paused" then
        Version.log("Starting in paused mode")
    end
    
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
