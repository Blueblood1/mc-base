-- Simple network test for pocket computer
local Network = require("network")

print("=== Network Test ===")
print("")

-- Initialize network
if not Network.init() then
    print("ERROR: No modem found!")
    return
end

print("Network initialized")
print("Computer ID: " .. os.getComputerID())
print("")

-- Try to find central
print("Looking for 'central'...")
local centralId = Network.lookup("central")

if centralId then
    print("Found central: " .. centralId)
    print("")
    print("Sending test message...")
    print("Protocol: " .. Network.PROTOCOL)
    print("Message type: " .. Network.MSG_TYPES.COMMAND)
    
    Network.send(centralId, Network.MSG_TYPES.COMMAND, {
        command = "report_status"
    })
    
    print("Message sent!")
    print("Waiting for response (5 seconds)...")
    print("")
    
    local timer = os.startTimer(5)
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "timer" and param1 == timer then
            print("Timeout - no response received")
            break
        elseif event == "rednet_message" then
            local senderId, msgType, data = Network.receive(0)
            if senderId then
                print("")
                print("Received message!")
                print("From: " .. senderId)
                print("Type: " .. msgType)
                if data and data.workers then
                    local count = 0
                    for _ in pairs(data.workers) do
                        count = count + 1
                    end
                    print("Workers: " .. count)
                end
                break
            end
        end
    end
else
    print("Central computer not found!")
    print("")
    print("Available hosts:")
    -- This won't work in current Network lib, but shows intent
    print("(lookup only works for specific hostnames)")
end

print("")
print("Test complete")
Network.close()
