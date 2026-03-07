-- Version Library
-- Provides build number information and logging

local Version = {}

Version.BUILD_NUMBER = nil

-- Read version from local BUILD_NUMBER file
function Version.get()
    if Version.BUILD_NUMBER then
        return Version.BUILD_NUMBER
    end
    
    if not fs.exists("BUILD_NUMBER") then
        return "?"
    end
    
    local file = fs.open("BUILD_NUMBER", "r")
    if not file then
        return "?"
    end
    
    local content = file.readAll()
    file.close()
    
    if not content or content == "" then
        return "?"
    end
    
    -- Trim whitespace and convert to number
    content = content:match("^%s*(.-)%s*$")
    if not content or content == "" then
        return "?"
    end
    
    Version.BUILD_NUMBER = tonumber(content)
    if not Version.BUILD_NUMBER then
        return "?"
    end
    
    return Version.BUILD_NUMBER
end

-- Print version banner
function Version.printBanner(programName)
    local build = Version.get()
    print("=================================")
    print(programName)
    print("Build: " .. tostring(build))
    print("=================================")
end

-- Log with version prefix and real-world timestamp
function Version.log(message)
    local build = Version.get()
    -- Get real-world time in milliseconds since epoch
    local epoch = os.epoch("local")
    -- Convert to seconds
    local seconds = math.floor(epoch / 1000)
    -- Calculate hours, minutes, seconds
    local hours = math.floor(seconds / 3600) % 24
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    -- Format as HH:MM:SS
    local time = string.format("%02d:%02d:%02d", hours, minutes, secs)
    print("[" .. tostring(build) .. " " .. time .. "] " .. message)
end

return Version
