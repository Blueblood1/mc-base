-- Test script for wither boss farm door controller
-- Run this on any computer/turtle to test door commands

local Network = require("network")

-- Initialize network
if not Network.init() then
    print("ERROR: No modem found!")
    return
end

-- Get the wither boss farm computer ID via DNS
print("Looking up wither_boss_farm via DNS...")
local farmId = Network.lookup("wither_boss_farm")

if not farmId then
    print("Could not find wither_boss_farm via DNS")
    write("Enter wither boss farm computer ID manually: ")
    farmId = tonumber(read())
end

print("Using computer ID: " .. farmId)
print("")
print("=== Door Test Menu ===")
print("Commands:")
print("  open <cell>  - Open a door (1-6)")
print("  close <cell> - Close a door (1-6)")
print("  quit         - Exit")
print("")

while true do
    write("> ")
    local input = read()
    
    if input == "quit" or input == "exit" then
        print("Goodbye!")
        break
    end
    
    -- Parse command
    local parts = {}
    for word in input:gmatch("%S+") do
        table.insert(parts, word)
    end
    
    if #parts < 2 then
        print("Usage: open <cell> or close <cell>")
    else
        local command = parts[1]
        local cell = tonumber(parts[2])
        
        if not cell then
            print("Invalid cell number")
        elseif cell < 1 or cell > 6 then
            print("Cell must be between 1 and 6")
        elseif command == "open" then
            print("Sending open_door command for cell " .. cell .. "...")
            Network.send(farmId, Network.MSG_TYPES.COMMAND, {
                command = "open_door",
                cell = cell
            })
            
            -- Wait for response
            print("Waiting for response...")
            local senderId, msgType, data = Network.receive(5)
            
            if senderId then
                if data.success then
                    print("SUCCESS: Door " .. cell .. " opened")
                else
                    print("FAILED: " .. (data.error or "Unknown error"))
                end
            else
                print("TIMEOUT: No response from farm computer")
            end
            
        elseif command == "close" then
            print("Sending close_door command for cell " .. cell .. "...")
            Network.send(farmId, Network.MSG_TYPES.COMMAND, {
                command = "close_door",
                cell = cell
            })
            
            -- Wait for response
            print("Waiting for response...")
            local senderId, msgType, data = Network.receive(5)
            
            if senderId then
                if data.success then
                    print("SUCCESS: Door " .. cell .. " closed")
                else
                    print("FAILED: " .. (data.error or "Unknown error"))
                end
            else
                print("TIMEOUT: No response from farm computer")
            end
            
        else
            print("Unknown command: " .. command)
            print("Use 'open' or 'close'")
        end
    end
    
    print("")
end
