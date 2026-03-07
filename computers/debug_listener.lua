-- Debug listener for central computer
-- This will show ALL incoming rednet messages

local Network = require("network")

print("=== Debug Listener ===")
print("Listening for ALL rednet messages...")
print("Press Ctrl+T to stop")
print("")

-- Initialize network
if not Network.init() then
    print("ERROR: No modem found!")
    return
end

print("Network initialized")
print("Computer ID: " .. os.getComputerID())
print("Protocol: " .. Network.PROTOCOL)
print("")

-- Host as central
Network.host("central")
print("Hosting as 'central'")
print("")

local count = 0

while true do
    local event, param1, param2, param3 = os.pullEvent()
    
    if event == "rednet_message" then
        count = count + 1
        print("--- Message #" .. count .. " ---")
        print("Sender ID: " .. param1)
        print("Protocol: " .. param3)
        
        -- Try to receive with our protocol
        local senderId, msgType, data = Network.receive(0)
        if senderId then
            print("Type: " .. tostring(msgType))
            if data and data.command then
                print("Command: " .. data.command)
                
                -- If it's report_status, send a test response
                if data.command == "report_status" then
                    print("Sending test response...")
                    Network.send(senderId, Network.MSG_TYPES.TELEMETRY, {
                        workers = {
                            [1] = {name = "Test Worker", status = "working", mode = "running"}
                        }
                    })
                    print("Response sent!")
                end
            end
        else
            print("(Not our protocol)")
        end
        print("")
    end
end
