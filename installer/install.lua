-- GitHub-based Installer
-- Run this on any computer/turtle to install the automation system

local GITHUB_USER = "Blueblood1"
local GITHUB_REPO = "mc-base"
local GITHUB_BRANCH = "main"

-- Build GitHub raw URL
local function buildUrl(path)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        GITHUB_USER,
        GITHUB_REPO,
        GITHUB_BRANCH,
        path
    )
end

-- Download a file from GitHub
local function download(githubPath, localFilename)
    if not http then
        print("Error: HTTP API is not enabled!")
        return false
    end
    
    local url = buildUrl(githubPath)
    print("Downloading " .. localFilename .. "...")
    
    local response = http.get(url)
    if not response then
        print("Failed to download " .. localFilename)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    local file = fs.open(localFilename, "w")
    file.write(content)
    file.close()
    
    print("✓ " .. localFilename)
    return true
end

-- Main installation
local function install()
    print("=== MC Base Automation System ===")
    print("Installing from GitHub...")
    print("Repo: " .. GITHUB_USER .. "/" .. GITHUB_REPO)
    print("")
    
    -- Detect device type
    local isTurtle = turtle ~= nil
    
    if isTurtle then
        print("Detected: Turtle")
        print("")
    else
        print("Detected: Computer")
        print("")
    end
    
    local success = 0
    local failed = 0
    
    -- Install libraries (always needed)
    print("Installing libraries...")
    if download("libs/network.lua", "network.lua") then
        success = success + 1
    else
        failed = failed + 1
    end
    
    if download("libs/updater.lua", "updater.lua") then
        success = success + 1
    else
        failed = failed + 1
    end
    
    if isTurtle then
        -- Install turtle-specific files
        print("")
        print("Installing turtle libraries...")
        if download("libs/turtle.lua", "turtle.lua") then
            success = success + 1
        else
            failed = failed + 1
        end
        
        print("")
        print("Installing pig feeder...")
        if download("turtles/pig_feeder.lua", "pig_feeder.lua") then
            success = success + 1
        else
            failed = failed + 1
        end
        
        -- Create startup file
        if not fs.exists("startup.lua") and not fs.exists("startup") then
            print("")
            print("Creating startup.lua...")
            local startup = fs.open("startup.lua", "w")
            startup.write('-- Auto-start pig feeder on boot\n')
            startup.write('print("Checking for updates...")\n')
            startup.write('local Updater = require("updater")\n')
            startup.write('Updater.updateLocal()\n')
            startup.write('print("Starting pig feeder...")\n')
            startup.write('shell.run("pig_feeder")\n')
            startup.close()
            print("✓ startup.lua")
        else
            print("⚠ startup.lua already exists, skipping")
        end
    else
        -- Install computer-specific files
        print("")
        print("Installing central computer...")
        if download("computers/central_computer.lua", "central_computer.lua") then
            success = success + 1
        else
            failed = failed + 1
        end
        
        -- Create startup file
        if not fs.exists("startup.lua") and not fs.exists("startup") then
            print("")
            print("Creating startup.lua...")
            local startup = fs.open("startup.lua", "w")
            startup.write('-- Auto-start central computer on boot\n')
            startup.write('print("Checking for updates...")\n')
            startup.write('local Updater = require("updater")\n')
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
    print("=== Installation Complete ===")
    print("Success: " .. success)
    print("Failed: " .. failed)
    print("")
    
    if isTurtle then
        print("To start: pig_feeder")
        print("Or reboot to auto-start")
        print("")
        print("Setup:")
        print("1. Attach wireless modem")
        print("2. Place fuel chest to the right")
        print("3. Place food chest in front")
    else
        print("To start: central_computer")
        print("Or reboot to auto-start")
        print("")
        print("Setup:")
        print("1. Attach wireless modem")
        print("2. (Optional) Attach monitor")
    end
    
    print("")
    print("Updates: Press U on central computer")
end

-- Run installation
install()
