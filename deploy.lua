-- Deployment Script
-- Run this on any computer/turtle to install the automation system

local Updater = {
    CONFIG = {
        ["lib_network.lua"] = "W5yWxnp6",
        ["lib_turtle.lua"] = "6jNV0Wbm",
        ["lib_updater.lua"] = "Ttum66A3",
        ["central_computer.lua"] = "4Zt8grvd",
        ["pig_feeder_networked.lua"] = "R8Nmn6ep"
    }
}

-- Download a file from pastebin
local function download(pastebinCode, filename)
    if not http then
        print("Error: HTTP API is not enabled!")
        return false
    end
    
    if not pastebinCode or pastebinCode == "" then
        print("Skipping " .. filename .. " (no code configured)")
        return false
    end
    
    local url = "https://pastebin.com/raw/" .. pastebinCode
    print("Downloading " .. filename .. "...")
    
    local response = http.get(url)
    if not response then
        print("Failed to download " .. filename)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    local file = fs.open(filename, "w")
    file.write(content)
    file.close()
    
    print("✓ " .. filename)
    return true
end

-- Main deployment
local function deploy()
    print("=== Turtle Automation System Deployment ===")
    print("")
    
    -- Check if this is a turtle or computer
    local isTurtle = turtle ~= nil
    
    if isTurtle then
        print("Detected: Turtle")
        print("Installing: Libraries + Turtle Programs")
        print("")
    else
        print("Detected: Computer")
        print("Installing: Libraries + Central Computer")
        print("")
    end
    
    local success = 0
    local failed = 0
    
    -- Always install libraries
    if download(Updater.CONFIG["lib_network.lua"], "lib_network.lua") then
        success = success + 1
    else
        failed = failed + 1
    end
    
    if download(Updater.CONFIG["lib_updater.lua"], "lib_updater.lua") then
        success = success + 1
    else
        failed = failed + 1
    end
    
    if isTurtle then
        -- Install turtle-specific files
        if download(Updater.CONFIG["lib_turtle.lua"], "lib_turtle.lua") then
            success = success + 1
        else
            failed = failed + 1
        end
        
        if download(Updater.CONFIG["pig_feeder_networked.lua"], "pig_feeder_networked.lua") then
            success = success + 1
        else
            failed = failed + 1
        end
        
        -- Create startup file for turtle
        if not fs.exists("startup.lua") and not fs.exists("startup") then
            print("Creating startup.lua...")
            local startup = fs.open("startup.lua", "w")
            startup.write('-- Auto-start pig feeder on boot\n')
            startup.write('print("Checking for updates...")\n')
            startup.write('local Updater = require("lib_updater")\n')
            startup.write('Updater.updateLocal()\n')
            startup.write('print("Starting pig feeder daemon...")\n')
            startup.write('shell.run("pig_feeder_networked")\n')
            startup.close()
            print("✓ startup.lua")
        else
            print("⚠ startup.lua already exists, skipping")
        end
    else
        -- Install computer-specific files
        if download(Updater.CONFIG["central_computer.lua"], "central_computer.lua") then
            success = success + 1
        else
            failed = failed + 1
        end
        
        -- Create startup file for central computer
        if not fs.exists("startup.lua") and not fs.exists("startup") then
            print("Creating startup.lua...")
            local startup = fs.open("startup.lua", "w")
            startup.write('-- Auto-start central computer on boot\n')
            startup.write('print("Checking for updates...")\n')
            startup.write('local Updater = require("lib_updater")\n')
            startup.write('Updater.updateLocal()\n')
            startup.write('print("Starting central computer...")\n')
            startup.write('shell.run("central_computer")\n')
            startup.close()
            print("✓ startup.lua")
        else
            print("⚠ startup.lua already exists, skipping")
        end
    end
    
    print("")
    print("=== Deployment Complete ===")
    print("Success: " .. success)
    print("Failed: " .. failed)
    print("")
    
    if isTurtle then
        print("To start the pig feeder:")
        print("  pig_feeder_networked")
        print("")
        print("Or just reboot - startup.lua is configured!")
        print("The turtle will:")
        print("  - Auto-update on boot")
        print("  - Run continuously")
        print("  - Report status to central")
    else
        print("To start the central computer:")
        print("  central_computer")
        print("")
        print("Or just reboot - startup.lua is configured!")
        print("The computer will:")
        print("  - Auto-update on boot")
        print("  - Monitor all turtles")
        print("  - Display on attached monitor")
    end
    
    print("")
    print("Make sure to attach wireless modems!")
end

-- Run deployment
deploy()
