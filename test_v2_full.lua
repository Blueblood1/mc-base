-- Test full v2 script loading
print("Testing v2 script loading...")

local success, err = pcall(function()
    print("Loading Executor...")
    local Executor = require("executor")
    print("Executor OK")
    
    print("Loading Network...")
    local Network = require("network")
    print("Network OK")
    
    print("Loading Version...")
    local Version = require("version")
    print("Version OK")
    
    print("All libraries loaded successfully!")
end)

if not success then
    print("ERROR:")
    print(tostring(err))
    
    local file = fs.open("error.txt", "w")
    file.write(tostring(err))
    file.close()
    print("Error written to error.txt")
else
    print("SUCCESS - All libraries loaded!")
end
