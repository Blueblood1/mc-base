-- GitHub Updater Library
-- Handles downloading scripts from GitHub and updating

local Updater = {}

-- GitHub repository configuration
Updater.GITHUB_USER = "Blueblood1"
Updater.GITHUB_REPO = "mc-base"
Updater.GITHUB_BRANCH = "main"

-- Build GitHub raw URL
local function buildGitHubUrl(path)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        Updater.GITHUB_USER,
        Updater.GITHUB_REPO,
        Updater.GITHUB_BRANCH,
        path
    )
end

-- File manifest - maps local filename to GitHub path
Updater.MANIFEST = {
    -- Libraries
    ["network.lua"] = "libs/network.lua",
    ["turtle.lua"] = "libs/turtle.lua",
    ["updater.lua"] = "libs/updater.lua",
    
    -- Central Computer
    ["central_computer.lua"] = "computers/central_computer.lua",
    
    -- Turtles
    ["pig_feeder.lua"] = "turtles/pig_feeder.lua"
}

-- Download a file from GitHub
function Updater.download(githubPath, localFilename)
    if not http then
        return false, "HTTP API is not enabled"
    end
    
    local url = buildGitHubUrl(githubPath)
    print("Downloading " .. localFilename .. "...")
    print("From: " .. githubPath)
    
    local response = http.get(url)
    if not response then
        return false, "Failed to download from GitHub"
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

-- Update only the files that exist locally
function Updater.updateLocal()
    local results = {}
    
    for localFilename, githubPath in pairs(Updater.MANIFEST) do
        if fs.exists(localFilename) then
            local success, message = Updater.download(githubPath, localFilename)
            results[localFilename] = {success = success, message = message}
            if success then
                print("✓ " .. localFilename)
            elseif message ~= "File unchanged" then
                print("✗ " .. localFilename .. ": " .. message)
            end
        end
    end
    
    return results
end

return Updater
