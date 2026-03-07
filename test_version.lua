-- Test script to debug version reading
print("=== VERSION DEBUG ===")

-- Check if BUILD_NUMBER file exists
print("1. BUILD_NUMBER file exists: " .. tostring(fs.exists("BUILD_NUMBER")))

if fs.exists("BUILD_NUMBER") then
    -- Read raw content
    local file = fs.open("BUILD_NUMBER", "r")
    local content = file.readAll()
    file.close()
    
    print("2. Raw content: [" .. content .. "]")
    print("3. Content length: " .. #content)
    print("4. Content bytes: " .. table.concat({string.byte(content, 1, -1)}, ", "))
    
    -- Try trimming
    local trimmed = content:match("^%s*(.-)%s*$")
    print("5. Trimmed: [" .. trimmed .. "]")
    print("6. Trimmed length: " .. #trimmed)
    
    -- Try converting to number
    local num = tonumber(trimmed)
    print("7. As number: " .. tostring(num))
    print("8. Type: " .. type(num))
end

-- Test Version library
print("")
print("=== VERSION LIBRARY TEST ===")
local Version = require("version")
print("9. Version.get(): " .. tostring(Version.get()))
print("10. Type: " .. type(Version.get()))

-- Test log
Version.log("Test message")
