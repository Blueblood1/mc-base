-- GitHub-based Installer
-- Run this on any computer/turtle to install the automation system
-- Usage: install [turtle_type]
-- Example: install pig_feeder  OR  install cow_feeder

local GITHUB_USER = "Blueblood1"
local GITHUB_REPO = "mc-base"
local GITHUB_BRANCH = "master"

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
local function install(args)
    -- Get command line argument for turtle type
    local turtleType = args[1]
    
    print("=== MC Base Automation System ===")
    print("Installing from GitHub...")
    print("Repo: " .. GITHUB_USER .. "/" .. GITHUB_REPO)
    print("")
    
    -- Detect device type
    local isTurtle = turtle ~= nil
    
    if isTurtle then
        print("Detected: Turtle")
        
        -- If no type specified, ask user
        if not turtleType then
            print("")
            print("Available turtle types:")
            print("  1. pig_feeder - Pig feeding automation")
            print("  2. cow_feeder - Cow feeding automation")
            print("  3. tree_farmer - Spruce tree farming")
            print("")
            write("Select turtle type (1-3): ")
            local choice = read()
            
            if choice == "1" then
                turtleType = "pig_feeder"
            elseif choice == "2" then
                turtleType = "cow_feeder"
            elseif choice == "3" then
                turtleType = "tree_farmer"
            else
                print("Invalid choice, defaulting to pig_feeder")
                turtleType = "pig_feeder"
            end
        end
        
        print("")
        print("Installing: " .. turtleType)
        print("")
    else
        print("Detected: Computer")
        print("")
    end
    
    local success = 0
    local failed = 0
    
    -- Install VERSION file first
    print("Installing version info...")
    if download("VERSION", "VERSION") then
        success = success + 1
    else
        failed = failed + 1
    end
    
    -- Install libraries (always needed)
    print("Installing libraries...")
    if download("libs/network.lua", "network.lua") then
        success = success + 1
    else
        failed = failed + 1
        print("FAILED: network.lua")
    end
    
    if download("libs/updater.lua", "updater.lua") then
        success = success + 1
    else
        failed = failed + 1
        print("FAILED: updater.lua")
    end
    
    if download("libs/version.lua", "version.lua") then
        success = success + 1
    else
        failed = failed + 1
        print("FAILED: version.lua")
    end
    
    if isTurtle then
        -- Install turtle-specific files
        print("")
        print("Installing turtle libraries...")
        if download("libs/turtle.lua", "turtle.lua") then
            success = success + 1
        else
            failed = failed + 1
            print("FAILED: turtle.lua")
        end
        
        print("")
        print("Installing " .. turtleType .. "...")
        if download("turtles/" .. turtleType .. ".lua", turtleType .. ".lua") then
            success = success + 1
        else
            failed = failed + 1
            print("FAILED: " .. turtleType .. ".lua")
        end
        
        -- Create startup file
        if not fs.exists("startup.lua") and not fs.exists("startup") then
            print("")
            print("Creating startup.lua...")
            local startup = fs.open("startup.lua", "w")
            startup.write('-- Auto-start ' .. turtleType .. ' on boot\n')
            startup.write('print("Checking for updates...")\n')
            startup.write('local Updater = require("updater")\n')
            startup.write('Updater.updateLocal()\n')
            startup.write('print("Starting ' .. turtleType .. '...")\n')
            startup.write('shell.run("' .. turtleType .. '")\n')
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
            print("FAILED: central_computer.lua")
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
        print("To start: " .. turtleType)
        print("Or reboot to auto-start")
        print("")
        print("Setup:")
        print("1. Attach wireless modem")
        
        if turtleType == "pig_feeder" then
            print("2. Place fuel chest to the RIGHT")
            print("3. Place food chest in FRONT")
            print("4. Position at bottom-right of 9x9")
        elseif turtleType == "cow_feeder" then
            print("2. Place fuel chest to the RIGHT")
            print("3. Place food chest to the LEFT")
            print("4. Position at bottom-right of 9x9")
        elseif turtleType == "tree_farmer" then
            print("2. Place fuel chest to the RIGHT")
            print("3. Place sapling chest to the LEFT")
            print("4. Place bonemeal chest BEHIND")
            print("5. Face forward toward planting area")
        end
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
local args = {...}
install(args)
