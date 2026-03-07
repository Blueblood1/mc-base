-- GitHub Updater Library
-- Handles downloading scripts from GitHub and updating

local Updater = {}

-- Server configuration
Updater.LOCAL_SERVER = "http://127.0.0.1:8080"
Updater.GITHUB_USER = "Blueblood1"
Updater.GITHUB_REPO = "mc-base"
Updater.GITHUB_BRANCH = "master"

-- Build URL with fallback logic
local function buildUrl(path)
    -- Try local server first
    local localUrl = Updater.LOCAL_SERVER .. "/" .. path
    
    print("Checking local server...")
    
    -- Use http.checkURL to test if local server is reachable
    local success, err = http.checkURL(localUrl)
    
    if success then
        print("Local server available, using: " .. localUrl)
        return localUrl
    else
        print("Local server not available (" .. tostring(err) .. "), using GitHub")
    end
    
    -- Fallback to GitHub with cache buster
    local cacheBuster = "?cb=" .. os.epoch("utc")
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s%s",
        Updater.GITHUB_USER,
        Updater.GITHUB_REPO,
        Updater.GITHUB_BRANCH,
        path,
        cacheBuster
    )
end

-- File manifest - maps local filename to GitHub path
Updater.MANIFEST = {
    -- Version
    ["BUILD_NUMBER"] = "BUILD_NUMBER",
    
    -- Libraries
    ["network.lua"] = "libs/network.lua",
    ["turtle.lua"] = "libs/turtle.lua",
    ["updater.lua"] = "libs/updater.lua",
    ["ui.lua"] = "libs/ui.lua",
    ["state.lua"] = "libs/state.lua",
    ["version.lua"] = "libs/version.lua",
    
    -- Central Computer
    ["central_computer.lua"] = "computers/central_computer.lua",
    
    -- Turtles
    ["pig_feeder.lua"] = "turtles/pig_feeder.lua",
    ["cow_feeder.lua"] = "turtles/cow_feeder.lua",
    ["tree_farmer.lua"] = "turtles/tree_farmer.lua",
    
    -- Debug
    ["test_version.lua"] = "test_version.lua"
}

-- Download a file from GitHub
function Updater.download(githubPath, localFilename)
    if not http then
        return false, "HTTP API is not enabled"
    end
    
    local url = buildUrl(githubPath)
    print("Downloading " .. localFilename .. "...")
    print("URL: " .. url)
    
    local response = http.get(url)
    if not response then
        print("ERROR: Failed to get response from " .. url)
        return false, "Failed to download"
    end
    
    local responseCode = response.getResponseCode()
    if responseCode ~= 200 then
        print("ERROR: HTTP " .. responseCode)
        response.close()
        return false, "HTTP error: " .. responseCode
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or content == "" then
        print("ERROR: Empty response")
        return false, "Empty file"
    end
    
    -- Check if content is different from existing file
    if fs.exists(localFilename) then
        local file = fs.open(localFilename, "r")
        local existingContent = file.readAll()
        file.close()
        
        if existingContent == content then
            return false, "File unchanged"
        end
    end
    
    -- Delete existing file if it exists
    if fs.exists(localFilename) then
        fs.delete(localFilename)
    end
    
    -- Write new file
    local file = fs.open(localFilename, "w")
    file.write(content)
    file.close()
    
    return true, "Downloaded successfully"
end

-- Update a specific file
function Updater.updateFile(localFilename)
    local githubPath = Updater.MANIFEST[localFilename]
    
    if not githubPath then
        return false, "File not in manifest: " .. localFilename
    end
    
    return Updater.download(githubPath, localFilename)
end

-- Check if update is needed by comparing BUILD_NUMBER file
function Updater.checkVersion()
    -- Download BUILD_NUMBER file
    local success, message = Updater.download("BUILD_NUMBER", "BUILD_NUMBER")
    
    if not success and message ~= "File unchanged" then
        return false, "Failed to check version: " .. message
    end
    
    -- If BUILD_NUMBER file changed, update is needed
    if success then
        return true, "New version available"
    end
    
    return false, "Already up to date"
end

-- Update all configured files
function Updater.updateAll()
    local results = {}
    
    for localFilename, githubPath in pairs(Updater.MANIFEST) do
        local success, message = Updater.download(githubPath, localFilename)
        results[localFilename] = {success = success, message = message}
        if success then
            print("✓ " .. localFilename)
        elseif message ~= "File unchanged" then
            print("✗ " .. localFilename .. ": " .. message)
        end
    end
    
    return results
end

-- Update only the files that exist locally (for auto-update)
function Updater.updateLocal()
    -- Get current version before update
    local currentVersion = "unknown"
    if fs.exists("BUILD_NUMBER") then
        local file = fs.open("BUILD_NUMBER", "r")
        local content = file.readAll()
        file.close()
        content = content:match("^%s*(.-)%s*$")
        currentVersion = tonumber(content) or "unknown"
    end
    
    -- First check if BUILD_NUMBER changed
    local needsUpdate, message = Updater.checkVersion()
    
    if not needsUpdate then
        term.clear()
        term.setCursorPos(1, 1)
        print("=================================")
        print("UPDATE CHECK")
        print("=================================")
        print("Current version: " .. tostring(currentVersion))
        print("Status: " .. message)
        print("=================================")
        sleep(3)
        return {}
    end
    
    -- Get new version
    local newVersion = "unknown"
    if fs.exists("BUILD_NUMBER") then
        local file = fs.open("BUILD_NUMBER", "r")
        local content = file.readAll()
        file.close()
        content = content:match("^%s*(.-)%s*$")
        newVersion = tonumber(content) or "unknown"
    end
    
    term.clear()
    term.setCursorPos(1, 1)
    print("=================================")
    print("UPDATING")
    print("=================================")
    print("From version: " .. tostring(currentVersion))
    print("To version:   " .. tostring(newVersion))
    print("=================================")
    print("")
    
    local results = {}
    local updated = 0
    
    for localFilename, githubPath in pairs(Updater.MANIFEST) do
        if fs.exists(localFilename) and localFilename ~= "BUILD_NUMBER" then
            local success, msg = Updater.download(githubPath, localFilename)
            results[localFilename] = {success = success, message = msg}
            if success then
                print("✓ " .. localFilename)
                updated = updated + 1
            elseif msg ~= "File unchanged" then
                print("✗ " .. localFilename .. ": " .. msg)
            end
        end
    end
    
    print("")
    print("=================================")
    print("UPDATE COMPLETE")
    print("=================================")
    print("Updated " .. updated .. " files")
    print("New version: " .. tostring(newVersion))
    print("=================================")
    sleep(3)
    
    return results
end

-- Install all files (downloads everything, even if missing)
function Updater.installAll()
    print("Installing all files from manifest...")
    return Updater.updateAll()
end

return Updater
