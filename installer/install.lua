-- GitHub-based Installer
-- Run this on any computer/turtle to install the automation system
-- Usage: install [turtle_type]
-- Example: install pig_feeder  OR  install cow_feeder

local GITHUB_USER = "Blueblood1"
local GITHUB_REPO = "mc-base"
local GITHUB_BRANCH = "master"
local LOCAL_SERVER = "http://127.0.0.1:8080"

-- Build URL with fallback logic
local function buildUrl(path, useLocal)
    if useLocal then
        return LOCAL_SERVER .. "/" .. path
    end
    
    -- GitHub with cache buster
    local cacheBuster = "?cb=" .. os.epoch("utc")
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s%s",
        GITHUB_USER,
        GITHUB_REPO,
        GITHUB_BRANCH,
        path,
        cacheBuster
    )
end

-- Download a file with local fallback
local function download(githubPath, localFilename)
    if not http then
        print("Error: HTTP API is not enabled!")
        return false
    end
    
    print("Downloading " .. localFilename .. "...")
    
    -- Try local server first
    local localUrl = buildUrl(githubPath, true)
    local response = http.get(localUrl)
    
    if response then
        local responseCode = response.getResponseCode()
        if responseCode == 200 then
            local content = response.readAll()
            response.close()
            
            if content and content ~= "" then
                local file = fs.open(localFilename, "w")
                file.write(content)
                file.close()
                print("✓ " .. localFilename .. " (local)")
                return true
            end
        else
            response.close()
        end
    end
    
    -- Fallback to GitHub
    local githubUrl = buildUrl(githubPath, false)
    response = http.get(githubUrl)
    
    if not response then
        print("Failed to download " .. localFilename)
        return false
    end
    
    local responseCode = response.getResponseCode()
    if responseCode ~= 200 then
        print("HTTP Error " .. responseCode .. " for " .. localFilename)
        response.close()
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or content == "" then
        print("Empty response for " .. localFilename)
        return false
    end
    
    local file = fs.open(localFilename, "w")
    file.write(content)
    file.close()
    
    print("✓ " .. localFilename .. " (GitHub)")
    return true
end

-- Main installation
local function install(args)
    -- Get command line argument for turtle type
    local turtleType = args[1]
    
    print("=== MC Base Automation System ===")
    print("Installing...")
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
        
        -- If no type specified, ask user
        if not turtleType then
            print("")
            print("Available computer types:")
            print("  1. central_computer - Main control system")
            print("  2. wither_mob_farm - Wither mob farm controller")
            print("")
            write("Select computer type (1-2): ")
            local choice = read()
            
            if choice == "1" then
                turtleType = "central_computer"
            elseif choice == "2" then
                turtleType = "wither_mob_farm"
            else
                print("Invalid choice, defaulting to central_computer")
                turtleType = "central_computer"
            end
        end
        
        print("")
        print("Installing: " .. turtleType)
        print("")
    end
    
    local success = 0
    local failed = 0
    
    -- Install BUILD_NUMBER file first
    print("Installing version info...")
    if download("BUILD_NUMBER", "BUILD_NUMBER") then
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
    
    if download("libs/state.lua", "state.lua") then
        success = success + 1
    else
        failed = failed + 1
        print("FAILED: state.lua")
    end
    
    if download("libs/ui.lua", "ui.lua") then
        success = success + 1
    else
        failed = failed + 1
        print("FAILED: ui.lua")
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
        print("Installing " .. turtleType .. "...")
        if download("computers/" .. turtleType .. ".lua", turtleType .. ".lua") then
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
    end
    
    print("")
    print("=== Installation Complete ===")
    print("Success: " .. success)
    if failed > 0 then
        print("Failed: " .. failed)
    end
    
    if isTurtle then
        print("Run: " .. turtleType)
    else
        print("Run: " .. turtleType)
    end
end

-- Run installation
local args = {...}
install(args)
