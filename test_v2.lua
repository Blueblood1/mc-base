-- Test script to see full error
local success, err = pcall(function()
    local Executor = require("executor")
    print("Executor loaded successfully!")
end)

if not success then
    print("ERROR loading executor:")
    print(tostring(err))
    
    -- Write error to file so we can read it
    local file = fs.open("error.txt", "w")
    file.write(tostring(err))
    file.close()
    print("Error written to error.txt")
end
