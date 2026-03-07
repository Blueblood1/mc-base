-- Wither Boss Farm Door Controller
-- Controls up to 16 cell doors via bundled cable
-- Doors are closed by default, constant signal opens them
-- Only one door can be open at a time

local Network = require("network")
local Worker = require("worker")
local Updater = require("updater")
local Version = require("version")

-- Configuration
local COMPUTER_NAME = "Wither Boss Farm"
local TELEMETRY_INTERVAL = 10
local NUM_CELLS = 6  -- Start with 6, expandable to 16

-- Bundled cable color mapping for each cell
local CELL_COLORS = {
    [1] = colors.white,
    [2] = colors.orange,
    [3] = colors.magenta,
    [4] = colors.lightBlue,
    [5] = colors.yellow,
    [6] = colors.lime,
    [7] = colors.pink,
    [8] = colors.gray,
    [9] = colors.lightGray,
    [10] = colors.cyan,
    [11] = colors.purple,
    [12] = colors.blue,
    [13] = colors.brown,
    [14] = colors.green,
    [15] = colors.red,
    [16] = colors.black
}

-- Shared state for command listener
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Door state tracking
local doorState = {
    openDoor = nil,  -- Which door is currently open (nil = all closed)
    turtleId = nil,  -- ID of the turtle we're working with
    lastError = nil
}

-- Forward declarations
local sendAlert
local sendTelemetry

-- Close all doors (no signal = closed)
local function closeAllDoors()
    redstone.setBundledOutput("back", 0)
    doorState.openDoor = nil
    Version.log("All doors closed")
end

-- Open a specific door (signal = open)
local function openDoor(cellNumber)
    if cellNumber < 1 or cellNumber > NUM_CELLS then
        return false, "Invalid cell number: " .. cellNumber
    end
    
    -- Close all doors first
    closeAllDoors()
    
    -- Open the requested door
    local color = CELL_COLORS[cellNumber]
    redstone.setBundledOutput("back", color)
    doorState.openDoor = cellNumber
    Version.log("Door " .. cellNumber .. " opened")
    
    return true
end

-- Close a specific door
local function closeDoor(cellNumber)
    if cellNumber < 1 or cellNumber > NUM_CELLS then
        return false, "Invalid cell number: " .. cellNumber
    end
    
    if doorState.openDoor == cellNumber then
        closeAllDoors()
        return true
    end
    
    -- Door wasn't open, but that's okay
    return true
end

-- Send telemetry to central computer
sendTelemetry = function()
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    
    local telemetryData = {
        name = os.getComputerLabel() or (COMPUTER_NAME .. " #" .. os.getComputerID()),
        status = sharedState.operatingMode == "running" and "working" or "idle",
        task = {
            phase = doorState.openDoor and ("door_" .. doorState.openDoor .. "_open") or "all_doors_closed",
            openDoor = doorState.openDoor,
            numCells = NUM_CELLS
        },
        stats = {
            turtleId = doorState.turtleId
        }
    }
    
    if doorState.lastError then
        telemetryData.status = "error"
        telemetryData.error = doorState.lastError
    end
    
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, telemetryData)
    else
        Network.broadcast(Network.MSG_TYPES.TELEMETRY, telemetryData)
    end
end

-- Send alert to central computer
sendAlert = function(message)
    doorState.lastError = message
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            name = os.getComputerLabel() or (COMPUTER_NAME .. " #" .. os.getComputerID()),
            message = message
        })
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, {
            name = os.getComputerLabel() or (COMPUTER_NAME .. " #" .. os.getComputerID()),
            message = message
        })
    end
end

-- Handle door commands from turtle
local function handleDoorCommand(senderId, data)
    Version.log("Received door command: " .. data.command .. " from " .. senderId)
    
    if data.command == "open_door" then
        local cellNumber = data.cell
        Version.log("Opening door " .. cellNumber)
        local success, err = openDoor(cellNumber)
        
        if success then
            doorState.turtleId = senderId
            Version.log("Door opened successfully, sending response")
            -- Send acknowledgment
            Network.send(senderId, Network.MSG_TYPES.RESPONSE, {
                success = true,
                cell = cellNumber,
                command = "open_door"
            })
            sendTelemetry()
        else
            Version.log("Failed to open door: " .. tostring(err))
            Network.send(senderId, Network.MSG_TYPES.RESPONSE, {
                success = false,
                cell = cellNumber,
                command = "open_door",
                error = err
            })
            sendAlert("Failed to open door " .. cellNumber .. ": " .. err)
        end
        
    elseif data.command == "close_door" then
        local cellNumber = data.cell
        Version.log("Closing door " .. cellNumber)
        local success, err = closeDoor(cellNumber)
        
        if success then
            Version.log("Door closed successfully, sending response")
            -- Send acknowledgment
            Network.send(senderId, Network.MSG_TYPES.RESPONSE, {
                success = true,
                cell = cellNumber,
                command = "close_door"
            })
            sendTelemetry()
        else
            Version.log("Failed to close door: " .. tostring(err))
            Network.send(senderId, Network.MSG_TYPES.RESPONSE, {
                success = false,
                cell = cellNumber,
                command = "close_door",
                error = err
            })
            sendAlert("Failed to close door " .. cellNumber .. ": " .. err)
        end
    end
end

-- Custom command listener that handles both worker commands and door commands
local function createDoorCommandListener()
    return function()
        while not sharedState.stopRequested do
            local event, param1, param2, param3 = os.pullEvent()
            
            if event == "rednet_message" then
                local senderId = param1
                local message = param2
                local protocol = param3
                
                Version.log("Received message from " .. senderId .. ", protocol: " .. tostring(protocol))
                
                if protocol == Network.PROTOCOL and type(message) == "table" then
                    local msgType = message.type
                    local data = message.data
                    
                    Version.log("Message type: " .. tostring(msgType) .. ", command: " .. tostring(data and data.command))
                    
                    if msgType == Network.MSG_TYPES.COMMAND then
                        -- Handle standard worker commands
                        if data.command == "report_status" then
                            sendTelemetry()
                            
                        elseif data.command == "set_mode" then
                            local oldMode = sharedState.operatingMode
                            sharedState.operatingMode = data.mode or "running"
                            sharedState.centralId = senderId
                            sharedState.centralConnected = true
                            
                            if oldMode ~= sharedState.operatingMode then
                                Version.log("Mode: " .. oldMode .. " -> " .. sharedState.operatingMode)
                                sendAlert("Mode changed to " .. sharedState.operatingMode)
                            end
                            
                            sendTelemetry()
                            
                        elseif data.command == "stop" then
                            sendAlert("Stop command received")
                            closeAllDoors()
                            sharedState.stopRequested = true
                            
                        elseif data.command == "update" then
                            sendAlert("Updating...")
                            local results = Updater.updateLocal()
                            local successCount = 0
                            for _, result in pairs(results) do
                                if result.success then
                                    successCount = successCount + 1
                                end
                            end
                            sendAlert("Updated " .. successCount .. " files")
                            sleep(2)
                            os.reboot()
                            
                        -- Handle door-specific commands
                        elseif data.command == "open_door" or data.command == "close_door" then
                            handleDoorCommand(senderId, data)
                        end
                    end
                end
            end
        end
    end
end

-- Main program loop
local function mainLoop()
    while true do
        -- Send periodic telemetry
        sleep(TELEMETRY_INTERVAL)
        sendTelemetry()
    end
end

-- Install startup file
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        Version.log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start wither boss farm on boot\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting wither boss farm daemon...")\n')
        file.write('shell.run("wither_boss_farm")\n')
        file.close()
        Version.log("Startup file installed!")
        return true
    end
    return false
end

-- Main program
local function main()
    Version.printBanner("Wither Boss Farm Door Controller")
    
    -- Initialize network
    if not Network.init() then
        Version.log("ERROR: No modem found!")
        return
    end
    Version.log("Network initialized")
    
    -- Set computer label
    if not os.getComputerLabel() then
        os.setComputerLabel(COMPUTER_NAME .. "_" .. os.getComputerID())
    end
    
    -- Register DNS name so turtle can find us
    Network.host("wither_boss_farm")
    Version.log("Registered DNS: wither_boss_farm")
    
    -- Install startup file
    installStartup()
    
    -- Ensure all doors start closed
    closeAllDoors()
    Version.log("Initialized with " .. NUM_CELLS .. " cells")
    
    -- Wait for connection to central
    Worker.waitForCentralConnection(sharedState, COMPUTER_NAME)
    
    -- Send initial telemetry
    sendTelemetry()
    
    Version.log("Entering main loop...")
    Version.log("Listening for door commands...")
    
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
        createDoorCommandListener()
    )
end

-- Run the program
main()
