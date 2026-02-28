-- Updater Library
-- Handles downloading scripts from pastebin and updating

local Updater = {}

-- Centralized configuration with all pastebin codes
-- Edit this table and distribute to all computers/turtles
Updater.CONFIG = {
    ["lib_network.lua"] = "W5yWxnp6",
    ["lib_turtle.lua"] = "6jNV0Wbm",
    ["lib_updater.lua"] = "Ttum66A3",
    ["central_computer.lua"] = "4Zt8grvd",
    ["pig_feeder_networked.lua"] = "R8Nmn6ep"
}

-- Download a file from pastebin
function Updater.download(pastebinCode, filename)
    if not http then
        return false, "HTTP API is not enabled"
    end
    
    if not pastebinCode or pastebinCode == "" then
        return false, "No pastebin code configured"
    end
    
    local url = "https://pastebin.com/raw/" .. pastebinCode
    print("Downloading " .. filename .. " from pastebin: " .. pastebinCode)
    
    local response = http.get(url)
    if not response then
        return false, "Failed to download from pastebin"
    end
    
    local content = response.readAll()
    response.close()
    
    -- Check if content is different from existing file
    if fs.exists(filename) then
        local file = fs.open(filename, "r")
        local existingContent = file.readAll()
        file.close()
        
        if existingContent == content then
            return false, "File unchanged"
        end
    end
    
    -- Delete existing file if it exists
    if fs.exists(filename) then
        fs.delete(filename)
    end
    
    -- Write new file
    local file = fs.open(filename, "w")
    file.write(content)
    file.close()
    
    return true, "Downloaded successfully"
end

-- Update a specific file
function Updater.updateFile(filename)
    local code = Updater.CONFIG[filename]
    
    if not code or code == "" then
        return false, "No pastebin code configured for " .. filename
    end
    
    return Updater.download(code, filename)
end

-- Update all configured files
function Updater.updateAll()
    local results = {}
    
    for filename, code in pairs(Updater.CONFIG) do
        if code and code ~= "" then
            local success, message = Updater.download(code, filename)
            results[filename] = {success = success, message = message}
            if success then
                print("✓ " .. filename)
            else
                print("✗ " .. filename .. ": " .. message)
            end
        end
    end
    
    return results
end

-- Update only the files that exist locally
function Updater.updateLocal()
    local results = {}
    
    for filename, code in pairs(Updater.CONFIG) do
        if code and code ~= "" and fs.exists(filename) then
            local success, message = Updater.download(code, filename)
            results[filename] = {success = success, message = message}
            if success then
                print("✓ " .. filename)
            else
                print("✗ " .. filename .. ": " .. message)
            end
        end
    end
    
    return results
end

return Updater
