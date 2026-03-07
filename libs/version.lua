-- Version Library
-- Provides build number information and logging

local Version = {}

Version.BUILD_NUMBER = nil

-- Download and get build number from GitHub
function Version.fetch()
    if not http then
        return nil, "HTTP API not enabled"
    end
    
    -- Add cache buster
    local cacheBuster = "?cb=" .. os.epoch("utc")
    local url = "https://raw.githubusercontent.com/Blueblood1/mc-base/master/VERSION" .. cacheBuster
    local response = http.get(url)
    
    if not response then
        return nil, "Failed to fetch version"
    end
    
    local content = response.readAll()
    response.close()
    
    Version.BUILD_NUMBER = tonumber(content)
    return Version.BUILD_NUMBER
end

-- Get cached build number or fetch if not available
function Version.get()
    if not Version.BUILD_NUMBER then
        Version.fetch()
    end
    return Version.BUILD_NUMBER or "unknown"
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
