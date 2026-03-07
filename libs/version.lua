-- Version Library
-- Provides build number information and logging

local Version = {}

Version.BUILD_NUMBER = nil

-- Read version from local VERSION file
function Version.get()
    if Version.BUILD_NUMBER then
        return Version.BUILD_NUMBER
    end
    
    if not fs.exists("VERSION") then
        return "?"
    end
    
    local file = fs.open("VERSION", "r")
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

-- Log with version prefix
function Version.log(message)
    local build = Version.get()
    print("[v" .. tostring(build) .. "] " .. message)
end

return Version
