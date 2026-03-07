-- Turtle Utility Library
-- Common functions for turtle operations and state management

local TurtleLib = {}

-- Get fuel level and percentage
function TurtleLib.getFuelStatus()
    local level = turtle.getFuelLevel()
    local limit = turtle.getFuelLimit()
    local percent = (level / limit) * 100
    
    return {
        level = level,
        limit = limit,
        percent = math.floor(percent)
    }
end

-- Get inventory status
function TurtleLib.getInventoryStatus()
    local slots = {}
    local emptySlots = 0
    
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            slots[i] = {
                name = item.name,
                count = item.count
            }
        else
            emptySlots = emptySlots + 1
        end
    end
    
    return {
        slots = slots,
        emptySlots = emptySlots,
        totalSlots = 16
    }
end

-- Check if a specific item exists in inventory
function TurtleLib.hasItem(itemName, minCount)
    minCount = minCount or 1
    local total = 0
    
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == itemName then
            total = total + item.count
        end
    end
    
    return total >= minCount, total
end

-- Smart refuel - refuels from a specific slot if fuel is low
function TurtleLib.smartRefuel(fuelSlot, threshold)
    threshold = threshold or 100
    local fuel = turtle.getFuelLevel()
    
    if fuel < threshold then
        turtle.select(fuelSlot)
        if turtle.getItemCount(fuelSlot) > 0 then
            turtle.refuel(1)
            return true
        end
        return false
    end
    return true
end

-- Load fuel from chest with lava bucket support
-- Loads fuel until target percentage is reached
-- Uses all inventory slots temporarily, then returns unused items
-- direction: "front", "right", "left", "top", "bottom"
-- targetPercent: stop when fuel reaches this percentage (default 80)
function TurtleLib.loadFuelFromChest(direction, targetPercent)
    targetPercent = targetPercent or 80
    
    -- Turn to face the chest
    if direction == "right" then
        turtle.turnRight()
    elseif direction == "left" then
        turtle.turnLeft()
    elseif direction == "back" then
        turtle.turnRight()
        turtle.turnRight()
    end
    
    -- Step 1: Fill entire inventory with fuel from chest
    for slot = 1, 16 do
        turtle.select(slot)
        if direction == "top" then
            turtle.suckUp()
        elseif direction == "bottom" then
            turtle.suckDown()
        else
            turtle.suck()
        end
    end
    
    -- Step 2: Consume fuel from inventory until we hit target
    local fuel = TurtleLib.getFuelStatus()
    local success = false
    
    for slot = 1, 16 do
        if fuel.percent >= targetPercent then
            break
        end
        
        turtle.select(slot)
        local item = turtle.getItemDetail(slot)
        
        if item then
            if item.name == "minecraft:lava_bucket" then
                -- Use all lava buckets in this slot
                local lavaBuckets = item.count
                
                for i = 1, lavaBuckets do
                    if fuel.percent >= targetPercent then
                        break
                    end
                    
                    turtle.refuel(1)
                    fuel = TurtleLib.getFuelStatus()
                    success = true
                end
            elseif item.name == "minecraft:bucket" then
                -- Empty bucket, skip it
            else
                -- Try regular fuel (coal, etc)
                local itemCount = item.count
                
                for i = 1, itemCount do
                    if fuel.percent >= targetPercent then
                        break
                    end
                    
                    if turtle.refuel(1) then
                        success = true
                        fuel = TurtleLib.getFuelStatus()
                    else
                        break -- Not fuel
                    end
                end
            end
        end
    end
    
    -- Step 3: Return everything back to chest
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            if direction == "top" then
                turtle.dropUp()
            elseif direction == "bottom" then
                turtle.dropDown()
            else
                turtle.drop()
            end
        end
    end
    
    -- Turn back to original direction
    if direction == "right" then
        turtle.turnLeft()
    elseif direction == "left" then
        turtle.turnRight()
    elseif direction == "back" then
        turtle.turnRight()
        turtle.turnRight()
    end
    
    return success, fuel.percent
end

-- Get turtle label or ID
function TurtleLib.getIdentifier()
    return os.getComputerLabel() or "turtle_" .. os.getComputerID()
end

-- Ensure turtle has enough fuel for a complete cycle
-- Enters fuel lock if insufficient, waits for refueling, then continues
-- Parameters:
--   minimumFuel: minimum fuel level required for cycle
--   fuelChestDirection: direction of fuel chest ("front", "right", "left", "back", "top", "bottom")
--   sendTelemetry: function to send telemetry updates
--   sendAlert: function to send alert messages
-- Returns: true when fuel is sufficient
function TurtleLib.ensureFuelForCycle(minimumFuel, fuelChestDirection, sendTelemetry, sendAlert)
    local Version = require("version")
    local fuel = TurtleLib.getFuelStatus()
    
    if fuel.level >= minimumFuel then
        return true  -- Already have enough fuel
    end
    
    -- Enter fuel lock
    Version.log("FUEL LOCK: Need " .. minimumFuel .. ", have " .. fuel.level)
    sendAlert("FUEL LOCK: Insufficient fuel for cycle")
    
    while fuel.level < minimumFuel do
        Version.log("Fuel: " .. fuel.level .. "/" .. minimumFuel .. " - Loading...")
        
        -- Try to load fuel
        local success, fuelPercent = TurtleLib.loadFuelFromChest(fuelChestDirection, 100)
        
        fuel = TurtleLib.getFuelStatus()
        sendTelemetry()
        
        if fuel.level < minimumFuel then
            Version.log("Still need more fuel, waiting...")
            sleep(5)
        end
    end
    
    Version.log("Fuel lock released: " .. fuel.level .. " fuel")
    sendAlert("Fuel lock released")
    return true
end

-- Load fuel from chest with cleanup of non-fuel items first
-- Parameters:
--   fuelDirection: direction of fuel chest ("front", "right", "left", "back", "top", "bottom")
--   cleanupDirections: table mapping item patterns to chest directions
--     Example: {["sapling"] = "left", ["bone"] = "back"}
--   targetPercent: target fuel percentage (default 80)
-- Returns: success (boolean), final fuel percentage
function TurtleLib.loadFuelFromChestWithCleanup(fuelDirection, cleanupDirections, targetPercent)
    targetPercent = targetPercent or 80
    
    -- Step 1: Clean up non-fuel items to their respective chests
    for itemPattern, direction in pairs(cleanupDirections) do
        -- Turn to face cleanup chest
        if direction == "left" then
            turtle.turnLeft()
        elseif direction == "right" then
            turtle.turnRight()
        elseif direction == "back" then
            turtle.turnRight()
            turtle.turnRight()
        end
        
        -- Drop items matching this pattern
        for slot = 1, 16 do
            turtle.select(slot)
            local item = turtle.getItemDetail(slot)
            if item and item.name:find(itemPattern) then
                if direction == "top" then
                    turtle.dropUp()
                elseif direction == "bottom" then
                    turtle.dropDown()
                else
                    turtle.drop()
                end
            end
        end
        
        -- Turn back to original direction
        if direction == "left" then
            turtle.turnRight()
        elseif direction == "right" then
            turtle.turnLeft()
        elseif direction == "back" then
            turtle.turnRight()
            turtle.turnRight()
        end
    end
    
    -- Step 2: Load fuel using existing function
    return TurtleLib.loadFuelFromChest(fuelDirection, targetPercent)
end

-- Check if paused and wait until resumed
-- Parameters:
--   state: shared state table with operatingMode
--   sendTelemetry: function to send telemetry
function TurtleLib.checkPauseState(state, sendTelemetry)
    local Version = require("version")
    
    while state.operatingMode == "paused" do
        Version.log("Paused - waiting for resume...")
        sendTelemetry()
        sleep(2)
    end
end

return TurtleLib
