-- Networked Wither Mob Farm Computer Program
-- Controls redstone signal for wither mob farm based on central computer commands

local Network = require("network")
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

-- Wait for connection to central and get initial mode
local function waitForCentralConnection()
    Version.log("Waiting for central computer...")
    
    -- Try to find central computer
    while not sharedState.centralId do
        sharedState.centralId = Network.lookup("central")
        if not sharedState.centralId then
            sleep(2)
        end
    end
    
    Version.log("Found central computer: " .. sharedState.centralId)
    sharedState.centralConnected = true
    
    -- Small delay to let any DNS responses clear
    sleep(0.1)
    
    -- Request initial mode
    Network.send(sharedState.centralId, Network.MSG_TYPES.COMMAND, {
        command = "request_mode",
        name = COMPUTER_NAME .. " #" .. os.getComputerID()
    })
    
    Version.log("Requested initial mode from central")
    
    -- Wait for mode response (with timeout)
    local timeout = os.startTimer(5)
    local modeReceived = false
    
    while not modeReceived do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "timer" and param1 == timeout then
            Version.log("Timeout waiting for mode, defaulting to paused")
            break
        elseif event == "rednet_message" then
            Version.log("Received rednet message from " .. param1)
            local senderId, msgType, data = Network.receive(0)
            if senderId then
                Version.log("Message type: " .. tostring(msgType))
                if data and data.command then
                    Version.log("Command: " .. data.command)
                end
                
                if senderId == sharedState.centralId and msgType == Network.MSG_TYPES.COMMAND then
                    if data.command == "set_mode" then
                        sharedState.operatingMode = data.mode
                        Version.log("Initial mode set to: " .. data.mode)
                        modeReceived = true
                        os.cancelTimer(timeout)
                    end
                else
                    Version.log("Ignoring message (sender=" .. senderId .. ", expected=" .. sharedState.centralId .. ")")
                end
            else
                Version.log("Message not for our protocol")
            end
        end
    end
    
    if not modeReceived then
        os.cancelTimer(timeout)
    end
end

-- Command listener (runs in parallel with main loop)
local function createCommandListener()
    return function()
        while true do
            local senderId, msgType, data = Network.receive()
            
            if msgType == Network.MSG_TYPES.COMMAND then
                if data.command == "set_mode" then
                    local oldMode = sharedState.operatingMode
                    sharedState.operatingMode = data.mode
                    Version.log("Mode changed: " .. oldMode .. " -> " .. data.mode)
                    
                    -- Update redstone immediately
                    updateRedstone()
                    
                    -- Always send telemetry after mode change
                    sendTelemetry()
                    
                elseif data.command == "report_status" then
                    sendTelemetry()
                    
                elseif data.command == "update" then
                    Version.log("Update command received, updating...")
                    sendAlert("Starting update...")
                    
                    local results = Updater.updateLocal()
                    local updated = false
                    for filename, result in pairs(results) do
                        if result.success then
                            updated = true
                        end
                    end
                    
                    if updated then
                        sendAlert("Update complete, rebooting...")
                        sleep(2)
                        os.reboot()
                    else
                        sendAlert("Already up to date")
                    end
                end
            end
        end
    end
end

-- Install startup file
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
    waitForCentralConnection()
    
    -- Send initial telemetry
    sendTelemetry()
    
    -- Set initial redstone state
    updateRedstone()
    
    Version.log("Entering main loop...")
    Version.log("Mode: " .. sharedState.operatingMode)
    
    -- Create command listener
    local commandListener = createCommandListener()
    
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
