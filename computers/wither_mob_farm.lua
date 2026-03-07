-- Networked Wither Mob Farm Computer Program
-- Controls redstone signal for wither mob farm based on central computer commands

local Network = require("network")
local Worker = require("worker")
local Updater = require("updater")
local Version = require("version")

-- Configuration
local COMPUTER_NAME = "Wither Mob Farm"
local TELEMETRY_INTERVAL = 10 -- Send telemetry every 10 seconds

-- Shared state for command listener
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "paused", -- Start paused (redstone off)
    stopRequested = false
}

-- Status tracking
local status = {
    lastError = nil,
    redstoneActive = false,
    toggleCount = 0
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
        name = COMPUTER_NAME .. " #" .. os.getComputerID(),
        status = sharedState.operatingMode == "running" and "working" or "idle",
        task = {
            phase = sharedState.operatingMode == "running" and "emitting_redstone" or "idle",
            redstoneActive = status.redstoneActive
        },
        stats = {
            toggleCount = status.toggleCount
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
            name = COMPUTER_NAME .. " #" .. os.getComputerID(),
            message = message
        })
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, {
            name = COMPUTER_NAME .. " #" .. os.getComputerID(),
            message = message
        })
    end
end

-- Set redstone output based on operating mode
local function updateRedstone()
    local shouldBeActive = (sharedState.operatingMode == "running")
    
    if shouldBeActive ~= status.redstoneActive then
        status.redstoneActive = shouldBeActive
        status.toggleCount = status.toggleCount + 1
        
        if shouldBeActive then
            redstone.setOutput("bottom", true)
            Version.log("Redstone ON - Mob farm enabled")
        else
            redstone.setOutput("bottom", false)
            Version.log("Redstone OFF - Mob farm disabled")
        end
        
        sendTelemetry()
    end
end

-- Main program
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        Version.log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start wither mob farm on boot\n')
        file.write('-- Update before running\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting wither mob farm daemon...")\n')
        file.write('shell.run("wither_mob_farm")\n')
        file.close()
        Version.log("Startup file installed!")
        return true
    end
    return false
end

-- Main program loop
local function mainLoop()
    while true do
        -- Update redstone based on current mode
        updateRedstone()
        
        -- Send periodic telemetry
        sleep(TELEMETRY_INTERVAL)
        sendTelemetry()
    end
end

-- Main program
local function main()
    Version.printBanner("Networked Wither Mob Farm")
    
    -- Initialize network
    if not Network.init() then
        Version.log("Warning: No modem found! Running in offline mode.")
    else
        Version.log("Network initialized")
        -- Set computer label
        if not os.getComputerLabel() then
            os.setComputerLabel(COMPUTER_NAME .. "_" .. os.getComputerID())
        end
    end
    
    -- Install startup file
    installStartup()
    
    -- Wait for connection to central and get initial mode
    Worker.waitForCentralConnection(sharedState, COMPUTER_NAME)
    
    -- Send initial telemetry
    sendTelemetry()
    
    -- Set initial redstone state
    updateRedstone()
    
    Version.log("Entering main loop...")
    Version.log("Mode: " .. sharedState.operatingMode)
    
    -- Create command listener
    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert = sendAlert,
        sendTelemetry = sendTelemetry,
        onModeChange = updateRedstone
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
