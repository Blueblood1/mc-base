-- GitHub Updater Library
-- Handles downloading scripts from GitHub and updating

local Updater = {}

-- Server configuration
Updater.LOCAL_SERVER = "http://localhost:8080"
Updater.GITHUB_USER = "Blueblood1"
Updater.GITHUB_REPO = "mc-base"
Updater.GITHUB_BRANCH = "master"

-- Build URL with fallback logic
local function buildUrl(path)
    -- Try local server first
    local localUrl = Updater.LOCAL_SERVER .. "/" .. path
    
    -- Test if local server is available with a quick timeout
    local response = http.get(localUrl, nil, nil, 2)
    if response then
        response.close()
        return localUrl
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
    ["VERSION"] = "VERSION",
    
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
    ["tree_farmer.lua"] = "turtles/tree_farmer.lua"
}

-- Download a file from GitHub
function Updater.download(githubPath, localFilename)
    if not http then
        return false, "HTTP API is not enabled"
    end
    
    local url = buildUrl(githubPath)
    print("Downloading " .. localFilename .. "...")
    print("From: " .. (url:match("localhost") and "local server" or "GitHub"))
    
    local response = http.get(url)
    if not response then
        return false, "Failed to download"
    end
    
    local content = response.readAll()
    response.close()
    
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

-- Check if update is needed by comparing VERSION file
function Updater.checkVersion()
    -- Download VERSION file
    local success, message = Updater.download("VERSION", "VERSION")
    
    if not success and message ~= "File unchanged" then
        return false, "Failed to check version: " .. message
    end
    
    -- If VERSION file changed, update is needed
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
    -- First check if VERSION changed
    local needsUpdate, message = Updater.checkVersion()
    
    if not needsUpdate then
        print(message)
        return {}
    end
    
    print(message .. ", updating files...")
    
    local results = {}
    
    for localFilename, githubPath in pairs(Updater.MANIFEST) do
        if fs.exists(localFilename) and localFilename ~= "VERSION" then
            local success, msg = Updater.download(githubPath, localFilename)
            results[localFilename] = {success = success, message = msg}
            if success then
                print("✓ " .. localFilename)
            elseif msg ~= "File unchanged" then
                print("✗ " .. localFilename .. ": " .. msg)
            end
        end
    end
    
    return results
end

-- Install all files (downloads everything, even if missing)
function Updater.installAll()
    print("Installing all files from manifest...")
    return Updater.updateAll()
end

return Updater
