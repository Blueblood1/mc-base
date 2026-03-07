-- Networked Slayer Turtle Program
-- Attacks mobs continuously in one location

local Network = require("network")
local TurtleLib = require("turtle")
local Updater = require("updater")
local Version = require("version")

-- Configuration
local FUEL_SLOT = 16
local ATTACK_DELAY = 0.5 -- Delay between attacks in seconds
local TELEMETRY_INTERVAL = 10
local TURTLE_NAME = "Slayer"

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
    
    local fuel = TurtleLib.getFuelStatus()
    
    local telemetryData = {
        name = TURTLE_NAME .. " #" .. os.getComputerID(),
        status = sharedState.operatingMode == "paused" and "paused" or "active",
        fuel = fuel,
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

-- Wait for initial connection and mode from central
local function waitForCentralConnection()
    Version.log("Waiting for connection to central computer...")
    Version.log("Requesting initial mode...")
    
    while not sharedState.centralConnected do
        -- Try to find central
        if not sharedState.centralId then
            sharedState.centralId = Network.lookup("central")
        end
        
        -- Request our mode
        if sharedState.centralId then
            Network.send(sharedState.centralId, Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = TURTLE_NAME .. " #" .. os.getComputerID()
            })
        else
            Network.broadcast(Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = TURTLE_NAME .. " #" .. os.getComputerID()
            })
        end
        
        -- Wait for response
        local timeout = os.startTimer(3)
        while true do
            local event, param1, param2, param3 = os.pullEvent()
            
            if event == "timer" and param1 == timeout then
                Version.log("No response, retrying...")
                break
            elseif event == "rednet_message" then
                local senderId = param1
                local message = param2
                local protocol = param3
                
                if protocol == Network.PROTOCOL and message and message.type == Network.MSG_TYPES.COMMAND then
                    local data = message.data
                    if data.command == "set_mode" and data.mode then
                        sharedState.operatingMode = data.mode
                        sharedState.centralId = senderId
                        sharedState.centralConnected = true
                        Version.log("Connected to central! Mode: " .. sharedState.operatingMode)
                        os.cancelTimer(timeout)
                        return
                    end
                end
            end
        end
        
        sleep(2)
    end
end

-- Refuel from the fuel slot
local function refuel()
    turtle.select(FUEL_SLOT)
    if turtle.getItemCount(FUEL_SLOT) > 0 then
        turtle.refuel(1)
    end
end

-- Check fuel and refuel if needed
local function checkFuel()
    local fuel = TurtleLib.getFuelStatus()
    
    if fuel.percent <= 20 then
        Version.log("Low fuel: " .. fuel.percent .. "%")
        refuel()
        fuel = TurtleLib.getFuelStatus()
        
        if fuel.percent <= 5 then
            Version.log("FUEL LOCK: Critical fuel level (" .. fuel.percent .. "%)")
            sendAlert("FUEL LOCK: Critical fuel level, waiting for refuel")
            status.lastError = "FUEL LOCK: Critical fuel"
            sendTelemetry()
            
            while fuel.percent <= 5 do
                Version.log("Fuel: " .. fuel.percent .. "% - Waiting for refuel...")
                sleep(5)
                refuel()
                fuel = TurtleLib.getFuelStatus()
                sendTelemetry()
            end
            
            Version.log("Fuel lock released: " .. fuel.percent .. "%")
            sendAlert("Fuel lock released: " .. fuel.percent .. "%")
            status.lastError = nil
            sendTelemetry()
        end
    end
end

-- Main slaying loop
local function mainLoop()
    local lastTelemetry = os.epoch("utc")
    
    while true do
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        -- Check fuel periodically
        checkFuel()
        
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
    waitForCentralConnection()
    
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
