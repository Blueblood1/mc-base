-- Central Computer Debug Version
-- Logs every message received and sent

local Network = require("network")
local State = require("state")
local Version = require("version")

local HOSTNAME = "central"
local centralState = {}

print("=== Central Computer Debug Mode ===")
print("")

-- Initialize network
if not Network.init() then
    print("ERROR: No modem found!")
    return
end

Network.host(HOSTNAME)
print("Hosting as 'central'")
print("Computer ID: " .. os.getComputerID())
print("")
print("Listening for messages...")
print("Press Ctrl+T to stop")
print("")

-- Load state
centralState = State.load()

local messageCount = 0

while true do
    local event, param1, param2, param3 = os.pullEvent()
    
    if event == "rednet_message" then
        messageCount = messageCount + 1
        
        print("--- Message #" .. messageCount .. " ---")
        print("Time: " .. os.date("%H:%M:%S"))
        print("Sender: " .. param1)
        
        local senderId, msgType, data = Network.receive(0)
        if senderId then
            print("Type: " .. msgType)
            
            if msgType == Network.MSG_TYPES.COMMAND and data.command then
                print("Command: " .. data.command)
                
                if data.command == "request_mode" then
                    print("Processing request_mode...")
                    
                    local mode = State.getTurtleMode(centralState, senderId)
                    print("Mode for " .. senderId .. ": " .. mode)
                    
                    print("Sending response...")
                    print("Target ID: " .. senderId)
                    print("Protocol: " .. Network.PROTOCOL)
                    local startTime = os.epoch("utc")
                    
                    Network.send(senderId, Network.MSG_TYPES.COMMAND, {
                        command = "set_mode",
                        mode = mode
                    })
                    
                    local endTime = os.epoch("utc")
                    print("Response sent! (took " .. (endTime - startTime) .. "ms)")
                    print("Sent to computer ID: " .. senderId)
                    
                elseif data.command == "report_status" then
                    print("Processing report_status...")
                    print("Sending empty worker list...")
                    
                    Network.send(senderId, Network.MSG_TYPES.TELEMETRY, {
                        workers = {}
                    })
                    
                    print("Response sent!")
                end
            end
        end
        
        print("")
    end
end
