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
-- Automatically handles lava buckets (returns empty buckets to chest)
-- direction: "front", "right", "left", "top", "bottom"
-- fuelSlot: which slot to use for fuel
-- targetPercent: stop when fuel reaches this percentage (default 80)
function TurtleLib.loadFuelFromChest(direction, fuelSlot, targetPercent)
    targetPercent = targetPercent or 80
    turtle.select(fuelSlot)
    
    -- Turn to face the chest
    if direction == "right" then
        turtle.turnRight()
    elseif direction == "left" then
        turtle.turnLeft()
    elseif direction == "back" then
        turtle.turnRight()
        turtle.turnRight()
    end
    
    -- Keep loading fuel until we reach target
    local fuel = TurtleLib.getFuelStatus()
    local success = false
    local attempts = 0
    local maxAttempts = 64 -- Prevent infinite loops
    
    while fuel.percent < targetPercent and attempts < maxAttempts do
        attempts = attempts + 1
        
        -- Make sure we're using the fuel slot and it's empty
        turtle.select(fuelSlot)
        if turtle.getItemCount(fuelSlot) > 0 then
            -- Slot not empty, drop whatever is there
            if direction == "top" then
                turtle.dropUp()
            elseif direction == "bottom" then
                turtle.dropDown()
            else
                turtle.drop()
            end
        end
        
        -- Try to get ONE item from chest
        local suckSuccess = false
        if direction == "top" then
            suckSuccess = turtle.suckUp(1)
        elseif direction == "bottom" then
            suckSuccess = turtle.suckDown(1)
        else
            suckSuccess = turtle.suck(1)
        end
        
        if not suckSuccess then
            break -- No more items in chest
        end
        
        -- Check what we got
        local item = turtle.getItemDetail(fuelSlot)
        if item then
            if item.name == "minecraft:lava_bucket" then
                -- Use lava bucket
                turtle.refuel()
                success = true
                
                -- Now we have an empty bucket, put it back
                sleep(0.1) -- Small delay to ensure refuel completed
                if direction == "top" then
                    turtle.dropUp()
                elseif direction == "bottom" then
                    turtle.dropDown()
                else
                    turtle.drop()
                end
            elseif item.name == "minecraft:bucket" then
                -- Empty bucket, put it back immediately
                if direction == "top" then
                    turtle.dropUp()
                elseif direction == "bottom" then
                    turtle.dropDown()
                else
                    turtle.drop()
                end
            else
                -- Try to use as fuel (coal, etc)
                if turtle.refuel() then
                    success = true
                else
                    -- Not fuel, put it back
                    if direction == "top" then
                        turtle.dropUp()
                    elseif direction == "bottom" then
                        turtle.dropDown()
                    else
                        turtle.drop()
                    end
                end
            end
        end
        
        fuel = TurtleLib.getFuelStatus()
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

return TurtleLib
