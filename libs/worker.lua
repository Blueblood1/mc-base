-- Worker Library for Shared Worker Utilities
-- Provides common functions for all worker devices (turtles and computers)

local Worker = {}

-- Wait for connection to central computer and get initial operating mode
-- Parameters:
--   state: shared state table with fields:
--     centralId, centralConnected, operatingMode
--   workerName: name of the worker (e.g., "Pig Feeder", "Wither Mob Farm")
-- Returns: nothing (updates state table)
function Worker.waitForCentralConnection(state, workerName)
    local Network = require("network")
    local Version = require("version")
    
    Version.log("Connecting to central computer...")
    
    while not state.centralConnected do
        -- Try DNS lookup for central computer
        if not state.centralId then
            state.centralId = Network.lookup("central")
        end
        
        -- Send request_mode command
        local fullName = workerName .. " #" .. os.getComputerID()
        if state.centralId then
            Network.send(state.centralId, Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = fullName
            })
        else
            Network.broadcast(Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = fullName
            })
        end
        
        -- Wait for response with timeout
        local timeout = os.startTimer(5)
        while true do
            local event, param1, param2, param3 = os.pullEvent()
            
            if event == "timer" and param1 == timeout then
                Version.log("Timeout waiting for mode, retrying...")
                break
            elseif event == "rednet_message" then
                local senderId = param1
                local message = param2
                local protocol = param3
                
                if protocol == Network.PROTOCOL and type(message) == "table" then
                    if message.type == Network.MSG_TYPES.COMMAND then
                        if message.data and message.data.command == "set_mode" then
                            state.operatingMode = message.data.mode
                            state.centralId = senderId
                            state.centralConnected = true
                            Version.log("Connected to central! Mode: " .. state.operatingMode)
                            os.cancelTimer(timeout)
                            return
                        end
                    end
                end
            end
        end
        
        sleep(2)
    end
end

-- Create a command listener function for parallel execution
-- Parameters:
--   state: shared state table with fields:
--     operatingMode, stopRequested, centralId, centralConnected
--   callbacks: table with functions:
--     sendAlert(message) - function to send alerts
--     sendTelemetry() - function to send telemetry
--     onModeChange() - (optional) function called after mode changes
-- Returns: function suitable for parallel.waitForAll()
function Worker.createCommandListener(state, callbacks)
    local Network = require("network")
    local Updater = require("updater")
    local Version = require("version")
    
    return function()
        while not state.stopRequested do
            -- Use event-driven message handling (not blocking receive)
            local event, param1, param2, param3 = os.pullEvent()
            
            if event == "rednet_message" then
                -- Read from event parameters (networking best practice)
                local senderId = param1
                local message = param2
                local protocol = param3
                
                -- Verify protocol
                if protocol == Network.PROTOCOL and type(message) == "table" then
                    local msgType = message.type
                    local data = message.data
                    
                    if msgType == Network.MSG_TYPES.COMMAND then
                        if data.command == "report_status" then
                            callbacks.sendTelemetry()
                            
                        elseif data.command == "set_mode" then
                            local oldMode = state.operatingMode
                            state.operatingMode = data.mode or "running"
                            state.centralId = senderId
                            state.centralConnected = true
                            
                            if oldMode ~= state.operatingMode then
                                Version.log("Mode: " .. oldMode .. " -> " .. state.operatingMode)
                                callbacks.sendAlert("Mode changed to " .. state.operatingMode)
                                
                                -- Call optional mode change callback
                                if callbacks.onModeChange then
                                    callbacks.onModeChange()
                                end
                            end
                            
                            callbacks.sendTelemetry()
                            
                        elseif data.command == "stop" then
                            callbacks.sendAlert("Stop command received")
                            state.stopRequested = true
                            
                        elseif data.command == "update" then
                            callbacks.sendAlert("Updating...")
                            local results = Updater.updateLocal()
                            local successCount = 0
                            for _, result in pairs(results) do
                                if result.success then
                                    successCount = successCount + 1
                                end
                            end
                            callbacks.sendAlert("Updated " .. successCount .. " files")
                            sleep(2)
                            os.reboot()
                        end
                    end
                end
            end
        end
    end
end

return Worker
