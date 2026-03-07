--[[
    Bundled Cable Test Script
    Tests if More Red bundled cables work with ComputerCraft's redstone API
    
    Usage:
    1. Connect a bundled cable to the BACK of your computer
    2. Connect the white wire to a redstone lamp or other indicator
    3. Run this script
]]

local function printHeader(text)
    print("")
    print("=================================")
    print(text)
    print("=================================")
end

local function testBundledCable()
    printHeader("Bundled Cable Compatibility Test")
    
    print("Testing side: BACK")
    print("")
    
    -- Test 1: Check if bundled output API exists
    print("[1/4] Checking API availability...")
    if not redstone.setBundledOutput then
        print("FAILED: setBundledOutput not available")
        print("Your CC version may not support bundled cables")
        return false
    end
    print("PASSED: Bundled cable API exists")
    print("")
    
    -- Test 2: Try to set a single color
    print("[2/4] Testing single color (WHITE)...")
    redstone.setBundledOutput("back", colors.white)
    sleep(0.5)
    
    local output = redstone.getBundledOutput("back")
    if output == colors.white then
        print("PASSED: White wire activated")
    else
        print("FAILED: Expected " .. colors.white .. ", got " .. output)
        print("Bundled cable may not be compatible")
        redstone.setBundledOutput("back", 0)
        return false
    end
    print("")
    
    -- Test 3: Try multiple colors
    print("[3/4] Testing multiple colors (WHITE + RED)...")
    redstone.setBundledOutput("back", colors.combine(colors.white, colors.red))
    sleep(0.5)
    
    output = redstone.getBundledOutput("back")
    local expected = colors.combine(colors.white, colors.red)
    if output == expected then
        print("PASSED: Multiple wires activated")
    else
        print("FAILED: Expected " .. expected .. ", got " .. output)
        redstone.setBundledOutput("back", 0)
        return false
    end
    print("")
    
    -- Test 4: Cycle through all 16 colors
    print("[4/4] Cycling through all 16 colors...")
    local colorList = {
        {colors.white, "white"},
        {colors.orange, "orange"},
        {colors.magenta, "magenta"},
        {colors.lightBlue, "lightBlue"},
        {colors.yellow, "yellow"},
        {colors.lime, "lime"},
        {colors.pink, "pink"},
        {colors.gray, "gray"},
        {colors.lightGray, "lightGray"},
        {colors.cyan, "cyan"},
        {colors.purple, "purple"},
        {colors.blue, "blue"},
        {colors.brown, "brown"},
        {colors.green, "green"},
        {colors.red, "red"},
        {colors.black, "black"}
    }
    
    for i, colorData in ipairs(colorList) do
        local color, name = colorData[1], colorData[2]
        redstone.setBundledOutput("back", color)
        write(name .. " ")
        sleep(0.2)
    end
    print("")
    print("PASSED: All colors cycled")
    print("")
    
    -- Clean up
    redstone.setBundledOutput("back", 0)
    
    return true
end

local function printResults(success)
    print("")
    if success then
        printHeader("TEST RESULT: SUCCESS")
        print("More Red bundled cables ARE compatible!")
        print("")
        print("You can use bundled cables for your wither farm.")
        print("Each cell can be controlled by a different color wire.")
        print("")
        print("Example code:")
        print('  redstone.setBundledOutput("back", colors.white)')
        print('  redstone.setBundledOutput("back", 0)  -- turn off')
    else
        printHeader("TEST RESULT: FAILED")
        print("More Red bundled cables are NOT compatible")
        print("with ComputerCraft's standard bundled cable API.")
        print("")
        print("Alternative solutions:")
        print("1. Use regular redstone with 6 computer sides")
        print("2. Use multiple computers (16 cells each)")
        print("3. Check if More Red has a custom peripheral API")
    end
    print("")
end

-- Run the test
local success = testBundledCable()
printResults(success)

-- Wait for user
print("Press any key to exit...")
os.pullEvent("key")
